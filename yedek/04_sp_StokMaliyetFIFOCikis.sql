-- =============================================================
-- FIFO ÇIKIŞ PROSEDÜRÜ - bkm.sp_fifo_StokMaliyetFIFOCikis
-- POS iade mantığı, miktarKalan güncelleme, yetersiz stok kontrolü ile
-- =============================================================

CREATE OR ALTER PROCEDURE bkm.sp_fifo_StokMaliyetFIFOCikis
(
    @satisBaslangic DATE,
    @satisBitis DATE,
    @stkID INT = NULL,
    @runId UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    -- Parametre validasyonu
    IF @satisBaslangic IS NULL OR @satisBitis IS NULL
    BEGIN
        RAISERROR('Tarih parametreleri boş olamaz', 16, 1);
        RETURN;
    END
    
    IF @satisBaslangic > @satisBitis
    BEGIN
        RAISERROR('Başlangıç tarihi bitiş tarihinden büyük olamaz', 16, 1);
        RETURN;
    END
    
    BEGIN TRY
        BEGIN TRANSACTION;

        /* 1) Havuzdaki tüm katmanları al */
        IF OBJECT_ID('tempdb..#katman', 'U') IS NOT NULL DROP TABLE #katman;

        SELECT
            h.ID AS katmanID, h.stkID, h.girisTarihi,
            h.belgeNo AS girisBelgeNo,
            h.miktarKalan AS miktarToplam,
            h.birimMaliyet
        INTO #katman
        FROM bkm.fifo_StokMaliyetHavuzu h
        WHERE h.girisTarihi <= @satisBitis
          -- Only include sources that are actually written by this deployment.
          AND h.kaynakTip IN ('ACILIS','ACILIS_TAMAMLA','ALIS','AYLIK_DEVIR')
          AND h.miktarKalan > 0
          AND (@stkID IS NULL OR h.stkID = @stkID);

        CREATE INDEX IX_tmp_katman_stkID
            ON #katman(stkID, girisTarihi, katmanID);

        /* 2) Satış hareketlerini al - POS İADE MANTIĞI İLE */
        IF OBJECT_ID('tempdb..#satislar', 'U') IS NOT NULL DROP TABLE #satislar;

        SELECT
            ID = IDENTITY(INT,1,1),
            dt.ehStkID AS stkID,
            CAST(bs.eTarihS AS DATE) AS satisTarihi,
            netMiktar = SUM(CONVERT(DECIMAL(18,4), dt.ehAdet))
        INTO #satislar
        FROM dbo.irs bs WITH(NOLOCK)
        JOIN dbo.irsAyr dt WITH(NOLOCK) ON dt.ehID = bs.eID
        WHERE bs.eTip IN (1,4,5,100,101)
          AND bs.eMekan IN (1, 4477, 4478)
          AND bs.eTarihS >= CONVERT(smalldatetime, @satisBaslangic)
          AND bs.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @satisBitis))
          AND (@stkID IS NULL OR dt.ehStkID = @stkID)
        GROUP BY dt.ehStkID, CAST(bs.eTarihS AS DATE);

        CREATE INDEX IX_tmp_satislar_stkID
            ON #satislar(stkID, satisTarihi, ID);

        /* 3) Katmanlar için kümülatif */
        IF OBJECT_ID('tempdb..#katmanCum', 'U') IS NOT NULL DROP TABLE #katmanCum;

        SELECT
            k.katmanID, k.stkID, k.girisTarihi, k.girisBelgeNo,
            k.miktarToplam, k.birimMaliyet,
            layerCumEnd = SUM(k.miktarToplam) OVER (
                PARTITION BY k.stkID
                ORDER BY k.girisTarihi, k.katmanID
            ),
            layerCumStart = SUM(k.miktarToplam) OVER (
                PARTITION BY k.stkID
                ORDER BY k.girisTarihi, k.katmanID
            ) - k.miktarToplam
        INTO #katmanCum
        FROM #katman k;

        CREATE INDEX IX_tmp_katmanCum_stkID
            ON #katmanCum(stkID, layerCumStart, layerCumEnd);

        /* 4) Satışlar için kümülatif */
        IF OBJECT_ID('tempdb..#satisCum', 'U') IS NOT NULL DROP TABLE #satisCum;

        SELECT
            s.ID AS satisID, s.stkID, s.satisTarihi,
            s.netMiktar AS miktar,
            satisCumEnd = SUM(ABS(s.netMiktar)) OVER (
                PARTITION BY s.stkID
                ORDER BY s.satisTarihi, s.ID
            ),
            satisCumStart = SUM(ABS(s.netMiktar)) OVER (
                PARTITION BY s.stkID
                ORDER BY s.satisTarihi, s.ID
            ) - ABS(s.netMiktar)
        INTO #satisCum
        FROM #satislar s
        WHERE s.netMiktar <> 0;

        CREATE INDEX IX_tmp_satisCum_stkID
            ON #satisCum(stkID, satisCumStart, satisCumEnd);

        /* 5) FIFO kesişim */
        IF OBJECT_ID('tempdb..#cikisDetay', 'U') IS NOT NULL DROP TABLE #cikisDetay;

        SELECT
            c.stkID, c.satisTarihi, c.satisID,
            c.miktar AS satirNetMiktar,
            l.katmanID, l.girisTarihi AS katmanTarihi,
            l.girisBelgeNo, l.birimMaliyet,
            cikisMiktar = CAST(
                CASE 
                    WHEN l.layerCumEnd <= c.satisCumStart 
                      OR c.satisCumEnd <= l.layerCumStart THEN 0
                    ELSE
                        (CASE WHEN l.layerCumEnd < c.satisCumEnd 
                              THEN l.layerCumEnd ELSE c.satisCumEnd END)
                      - (CASE WHEN l.layerCumStart > c.satisCumStart 
                              THEN l.layerCumStart ELSE c.satisCumStart END)
                END
            AS DECIMAL(18,4))
        INTO #cikisDetay
        FROM #satisCum c
        JOIN #katmanCum l
          ON l.stkID = c.stkID
         AND l.layerCumEnd > c.satisCumStart
         AND c.satisCumEnd > l.layerCumStart;

        DELETE FROM #cikisDetay WHERE cikisMiktar <= 0;

        /* 6) YETERSIZ STOK KONTROLÜ */
        INSERT INTO bkm.fifo_StokMaliyetSorunlu
            (stkID, envanterTarihi, stokMiktar, sorunTip, aciklama)
        SELECT
            s.stkID, @satisBitis,
            ABS(s.netMiktar) - ISNULL(SUM(ABS(d.cikisMiktar)), 0) AS eksikMiktar,
            'STOK_YETERSIZ',
            'Hareket miktarı (' + CAST(ABS(s.netMiktar) AS VARCHAR(20)) + 
            ') mevcut katmanları (' + CAST(ISNULL(SUM(ABS(d.cikisMiktar)), 0) AS VARCHAR(20)) + 
            ') aşıyor.'
        FROM #satislar s
        LEFT JOIN #cikisDetay d ON d.stkID = s.stkID
        WHERE s.netMiktar <> 0
        GROUP BY s.stkID, s.netMiktar
        HAVING ABS(s.netMiktar) > ISNULL(SUM(ABS(d.cikisMiktar)), 0);

        /* 7) SONUÇLARI TABLOYA YAZ */
        DELETE FROM bkm.fifo_StokMaliyetCikis
        WHERE hareketTarihi >= @satisBaslangic
          AND hareketTarihi <= @satisBitis
          AND (@stkID IS NULL OR stkID = @stkID);

        INSERT INTO bkm.fifo_StokMaliyetCikis
            (stkID, hareketTarihi, hareketTipi, katmanID, 
             katmanTarihi, katmanBelgeNo, miktar, birimMaliyet)
        SELECT
            d.stkID, d.satisTarihi,
            CASE WHEN d.satirNetMiktar < 0 THEN 'SATIS' ELSE 'IADE' END,
            d.katmanID, d.katmanTarihi, d.girisBelgeNo,
            d.cikisMiktar, d.birimMaliyet
        FROM #cikisDetay d;

        /* 8) KATMAN KALAN MİKTARLARINI GÜNCELLE */
        UPDATE h
        SET h.miktarKalan = h.miktarKalan - d.toplamCikis
        FROM bkm.fifo_StokMaliyetHavuzu h
        JOIN (
            SELECT katmanID, SUM(ABS(cikisMiktar)) AS toplamCikis
            FROM #cikisDetay
            GROUP BY katmanID
        ) d ON d.katmanID = h.ID
        WHERE h.miktarKalan > 0;

        COMMIT TRANSACTION;
        
        SELECT
            stkID, hareketTarihi, hareketTipi, katmanID,
            katmanTarihi, katmanBelgeNo, miktar, birimMaliyet, cikisTutar
        FROM bkm.fifo_StokMaliyetCikis
        WHERE hareketTarihi >= @satisBaslangic
          AND hareketTarihi <= @satisBitis
          AND (@stkID IS NULL OR stkID = @stkID)
        ORDER BY stkID, hareketTarihi, katmanTarihi, katmanID;
        
        PRINT 'FIFO çıkış işlemi başarıyla tamamlandı. Tarih aralığı: ' + 
              CONVERT(VARCHAR(10), @satisBaslangic, 120) + ' - ' + 
              CONVERT(VARCHAR(10), @satisBitis, 120);
        
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

PRINT 'sp_fifo_StokMaliyetFIFOCikis prosedürü oluşturuldu';
GO

