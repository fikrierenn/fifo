-- =============================================================
-- ALIŞ KATMANLARI PROSEDÜRÜ - bkm.sp_fifo_StokMaliyetAlisKatman
-- Transaction yönetimi ve hata kontrolü ile
-- =============================================================

CREATE OR ALTER PROCEDURE bkm.sp_fifo_StokMaliyetAlisKatman
(
    @baslangicTarihi DATE,
    @bitisTarihi DATE,
    @stkID INT = NULL,
    @runId UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    -- Parametre validasyonu
    IF @baslangicTarihi IS NULL OR @bitisTarihi IS NULL
    BEGIN
        RAISERROR('Tarih parametreleri boş olamaz', 16, 1);
        RETURN;
    END
    
    IF @baslangicTarihi > @bitisTarihi
    BEGIN
        RAISERROR('Başlangıç tarihi bitiş tarihinden büyük olamaz', 16, 1);
        RETURN;
    END
    
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('tempdb..#alislar', 'U') IS NOT NULL DROP TABLE #alislar;
        CREATE TABLE #alislar (
            stkID        INT           NOT NULL,
            girisTarihi  DATETIME      NOT NULL,
            belgeNo      VARCHAR(50)   NULL,
            belgeTarihi  DATE          NULL,
            firmaID      INT           NULL,
            miktar       DECIMAL(18,4) NOT NULL,
            netTutar     DECIMAL(18,4) NOT NULL
        );

        /* Verilen tarih aralığındaki alışları çek */
        DECLARE @firmaCol SYSNAME = NULL;
        DECLARE @belgeTarihCol SYSNAME = NULL;

        IF COL_LENGTH('dbo.fat', 'eFirma') IS NOT NULL SET @firmaCol = 'eFirma';
        ELSE IF COL_LENGTH('dbo.fat', 'eCariID') IS NOT NULL SET @firmaCol = 'eCariID';
        ELSE IF COL_LENGTH('dbo.fat', 'eCari') IS NOT NULL SET @firmaCol = 'eCari';

        IF COL_LENGTH('dbo.fat', 'eTarih') IS NOT NULL SET @belgeTarihCol = 'eTarih';
        ELSE IF COL_LENGTH('dbo.fat', 'eTarihF') IS NOT NULL SET @belgeTarihCol = 'eTarihF';

        DECLARE @belgeTarihExpr NVARCHAR(200) =
            CASE WHEN @belgeTarihCol IS NULL THEN 'i.eTarih' ELSE 'f.' + QUOTENAME(@belgeTarihCol) END;
        DECLARE @firmaExpr NVARCHAR(200) =
            CASE WHEN @firmaCol IS NULL THEN 'NULL' ELSE 'f.' + QUOTENAME(@firmaCol) END;
        DECLARE @groupByExtra NVARCHAR(400) = '';

        IF @belgeTarihCol IS NOT NULL SET @groupByExtra = @groupByExtra + ', ' + @belgeTarihExpr;
        IF @firmaCol IS NOT NULL SET @groupByExtra = @groupByExtra + ', ' + @firmaExpr;

        DECLARE @sql NVARCHAR(MAX) = N'
        INSERT INTO #alislar (stkID, girisTarihi, belgeNo, belgeTarihi, firmaID, miktar, netTutar)
        SELECT 
            a.ehStkID AS stkID,
            i.eTarih  AS girisTarihi,
            f.eNo     AS belgeNo,
            ' + @belgeTarihExpr + N' AS belgeTarihi,
            ' + @firmaExpr + N' AS firmaID,
            SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS miktar,
            SUM(
                CONVERT(DECIMAL(18,4),
                    CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END
                )
            ) AS netTutar
        FROM dbo.irs i WITH(NOLOCK)
        JOIN dbo.irsAyr ia WITH(NOLOCK) ON ia.ehID = i.eID
        JOIN dbo.fatAyr a WITH(NOLOCK)
             ON a.ehIrsID = i.eID AND a.ehIrsSira = ia.ehSira
        JOIN dbo.fat f WITH(NOLOCK) ON f.eID = a.ehID
        WHERE i.eTip IN (2,0,10,3,6,102,103)
          AND i.eTarih >  CONVERT(smalldatetime, @baslangicTarihi)
          AND i.eTarih <  DATEADD(DAY, 1, CONVERT(smalldatetime, @bitisTarihi))
          AND a.ehAdetN <> 0
          AND (@stkID IS NULL OR a.ehStkID = @stkID)
        GROUP BY a.ehStkID, i.eTarih, i.eID, f.eNo' + @groupByExtra + N'
        HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;';

        EXEC sp_executesql
            @sql,
            N'@baslangicTarihi DATE, @bitisTarihi DATE, @stkID INT',
            @baslangicTarihi = @baslangicTarihi,
            @bitisTarihi = @bitisTarihi,
            @stkID = @stkID;

        /* Birim maliyet hesapla */
        ALTER TABLE #alislar ADD birimMaliyet DECIMAL(18,6);

        UPDATE #alislar
        SET birimMaliyet = CASE WHEN miktar = 0 THEN 0 ELSE netTutar / miktar END;

        /* Aynı tarih aralığındaki eski ALIS katmanlarını sil */
        DELETE FROM bkm.fifo_StokMaliyetHavuzu
        WHERE kaynakTip = 'ALIS'
          AND girisTarihi >  @baslangicTarihi
          AND girisTarihi <= @bitisTarihi
          AND (@stkID IS NULL OR stkID = @stkID);

        /* Yeni ALIS katmanlarını havuza yaz */
        INSERT INTO bkm.fifo_StokMaliyetHavuzu
            (stkID, girisTarihi, kaynakTip, belgeNo, belgeTarihi, firmaID,
             miktarToplam, miktarKalan, birimMaliyet, durum)
        SELECT
            stkID, girisTarihi, 'ALIS', belgeNo, belgeTarihi, firmaID,
            miktar, miktar, birimMaliyet, 'NORMAL'
        FROM #alislar;

        COMMIT TRANSACTION;
        
        PRINT 'Alış katmanları başarıyla oluşturuldu. Tarih aralığı: ' + 
              CONVERT(VARCHAR(10), @baslangicTarihi, 120) + ' - ' + 
              CONVERT(VARCHAR(10), @bitisTarihi, 120);
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @runMessage VARCHAR(500) = SUBSTRING(CONVERT(VARCHAR(500), @ErrorMessage), 1, 500);
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        
        THROW;
    END CATCH
END
GO

PRINT 'sp_fifo_StokMaliyetAlisKatman prosedürü oluşturuldu';
GO

