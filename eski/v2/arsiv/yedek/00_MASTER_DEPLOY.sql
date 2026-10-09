-- =============================================================
-- BKM FIFO STOK MALIYET SISTEMI - MASTER DEPLOYMENT SCRIPT
-- Tum bilesenleri sirayla calistirir
-- =============================================================

PRINT '========================================';
PRINT 'BKM FIFO STOK MALIYET SISTEMI';
PRINT 'Deployment basliyor...';
PRINT '========================================';
PRINT '';

PRINT '1/6 - Tablolar ve indeksler olusturuluyor...';

-- =============================================================
-- BKM FIFO STOK MALİYET SİSTEMİ - TABLOLAR VE İNDEKSLER
-- =============================================================
SET NOCOUNT ON;
GO

IF SCHEMA_ID('bkm') IS NULL
    EXEC('CREATE SCHEMA bkm');
GO

-- 1.1) Stok Maliyet Havuzu
IF OBJECT_ID('bkm.fifo_StokMaliyetHavuzu', 'U') IS NOT NULL
    DROP TABLE bkm.fifo_StokMaliyetHavuzu;
GO

CREATE TABLE bkm.fifo_StokMaliyetHavuzu (
    ID            INT IDENTITY(1,1) PRIMARY KEY,
    stkID         INT             NOT NULL,
    girisTarihi   DATE            NOT NULL,
    kaynakTip     VARCHAR(20)     NOT NULL,
    belgeNo       VARCHAR(50)     NULL,
    belgeTarihi   DATE            NULL,
    firmaID       INT             NULL,
    miktarToplam  DECIMAL(18,4)   NOT NULL,
    miktarKalan   DECIMAL(18,4)   NOT NULL,
    birimMaliyet  DECIMAL(18,6)   NOT NULL,
    durum         VARCHAR(20)     NOT NULL DEFAULT('NORMAL'),
    kayitTarihi   DATETIME        NOT NULL DEFAULT(GETDATE())
);
GO

CREATE INDEX IX_fifo_StokMaliyetHavuzu_stkID
    ON bkm.fifo_StokMaliyetHavuzu(stkID, girisTarihi, kaynakTip);
GO

CREATE INDEX IX_fifo_StokMaliyetHavuzu_AktifKatman
    ON bkm.fifo_StokMaliyetHavuzu(stkID, girisTarihi, kaynakTip)
    INCLUDE (miktarKalan, birimMaliyet)
    WHERE miktarKalan > 0;
GO

-- 1.2) Stok Envanter
IF OBJECT_ID('bkm.fifo_StokEnvanter', 'U') IS NOT NULL
    DROP TABLE bkm.fifo_StokEnvanter;
GO

CREATE TABLE bkm.fifo_StokEnvanter (
    ID             INT IDENTITY(1,1) PRIMARY KEY,
    envanterTarihi DATE            NOT NULL,
    mekanID        INT             NOT NULL,
    stkID          INT             NOT NULL,
    stokMiktar     DECIMAL(18,4)   NOT NULL,
    kayitTarihi    DATETIME        NOT NULL DEFAULT(GETDATE())
);
GO

CREATE INDEX IX_fifo_StokEnvanter_TarihMekanStok
    ON bkm.fifo_StokEnvanter(envanterTarihi, mekanID, stkID);
GO

-- 1.3) Stok Maliyet Sorunlu
IF OBJECT_ID('bkm.fifo_StokMaliyetSorunlu', 'U') IS NOT NULL
    DROP TABLE bkm.fifo_StokMaliyetSorunlu;
GO

CREATE TABLE bkm.fifo_StokMaliyetSorunlu (
    ID             INT IDENTITY(1,1) PRIMARY KEY,
    stkID          INT             NOT NULL,
    envanterTarihi DATE            NOT NULL,
    stokMiktar     DECIMAL(18,4)   NOT NULL,
    sorunTip       VARCHAR(50)     NOT NULL,
    aciklama       VARCHAR(500)    NULL,
    kayitTarihi    DATETIME        NOT NULL DEFAULT(GETDATE())
);
GO

CREATE INDEX IX_fifo_StokMaliyetSorunlu_TarihStok
    ON bkm.fifo_StokMaliyetSorunlu(envanterTarihi, stkID);
GO

CREATE INDEX IX_fifo_StokMaliyetSorunlu_Tip
    ON bkm.fifo_StokMaliyetSorunlu(sorunTip, envanterTarihi)
    INCLUDE (stkID, stokMiktar);
GO

CREATE INDEX IX_fifo_StokMaliyetSorunlu_KayitTarihi
    ON bkm.fifo_StokMaliyetSorunlu(kayitTarihi, sorunTip)
    INCLUDE (envanterTarihi, stkID, stokMiktar, aciklama);
GO

-- 1.4) Sabit Fiyat (fallback)
IF OBJECT_ID('bkm.fifo_SabitFiyat', 'U') IS NOT NULL
    DROP TABLE bkm.fifo_SabitFiyat;
GO
CREATE TABLE bkm.fifo_SabitFiyat (
    stkID         INT           NOT NULL PRIMARY KEY,
    birimMaliyet  DECIMAL(18,6) NOT NULL,
    updatedAt     DATETIME      NOT NULL DEFAULT(GETDATE())
);
GO

-- 1.5) Stok Maliyet Çıkış
IF OBJECT_ID('bkm.fifo_StokMaliyetCikis', 'U') IS NOT NULL
    DROP TABLE bkm.fifo_StokMaliyetCikis;
GO

CREATE TABLE bkm.fifo_StokMaliyetCikis (
    ID              INT IDENTITY(1,1) PRIMARY KEY,
    stkID           INT             NOT NULL,
    hareketTarihi   DATE            NOT NULL,
    hareketTipi     VARCHAR(10)     NOT NULL,
    satisBelgeNo    VARCHAR(50)     NULL,
    katmanID        INT             NOT NULL,
    katmanTarihi    DATE            NOT NULL,
    katmanBelgeNo   VARCHAR(50)     NULL,
    miktar          DECIMAL(18,4)   NOT NULL,
    birimMaliyet    DECIMAL(18,6)   NOT NULL,
    cikisTutar      AS (miktar * birimMaliyet) PERSISTED,
    kayitTarihi     DATETIME        NOT NULL DEFAULT(GETDATE())
);
GO

CREATE INDEX IX_fifo_StokMaliyetCikis_StokTarih
    ON bkm.fifo_StokMaliyetCikis(stkID, hareketTarihi);
GO

CREATE INDEX IX_fifo_StokMaliyetCikis_Tarih
    ON bkm.fifo_StokMaliyetCikis(hareketTarihi) 
    INCLUDE (hareketTipi, cikisTutar);
GO

CREATE INDEX IX_fifo_StokMaliyetCikis_Tip
    ON bkm.fifo_StokMaliyetCikis(hareketTipi, hareketTarihi)
    INCLUDE (stkID, cikisTutar);
GO


-- 1.6) Calistirma Run
IF OBJECT_ID('bkm.fifo_Run', 'U') IS NOT NULL
    DROP TABLE bkm.fifo_Run;
GO

CREATE TABLE bkm.fifo_Run (
    runId       UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    runType     VARCHAR(20)      NOT NULL,
    status      VARCHAR(20)      NOT NULL,
    requestedAt DATETIME         NOT NULL DEFAULT(GETDATE()),
    startedAt   DATETIME         NULL,
    endedAt     DATETIME         NULL,
    message     VARCHAR(500)     NULL
);
GO

CREATE INDEX IX_fifo_Run_Status
    ON bkm.fifo_Run(status, requestedAt);
GO

-- 1.7) Calistirma Run Adimlari
IF OBJECT_ID('bkm.fifo_RunStep', 'U') IS NOT NULL
    DROP TABLE bkm.fifo_RunStep;
GO

CREATE TABLE bkm.fifo_RunStep (
    runId     UNIQUEIDENTIFIER NOT NULL,
    stepKey   VARCHAR(50)      NOT NULL,
    stepName  VARCHAR(100)     NOT NULL,
    stepOrder INT              NOT NULL,
    status    VARCHAR(20)      NOT NULL,
    message   VARCHAR(500)     NULL,
    startedAt DATETIME         NULL,
    endedAt   DATETIME         NULL,
    updatedAt DATETIME         NOT NULL DEFAULT(GETDATE()),
    CONSTRAINT PK_fifo_RunStep PRIMARY KEY (runId, stepKey)
);
GO

CREATE INDEX IX_fifo_RunStep_Run
    ON bkm.fifo_RunStep(runId, stepOrder);
GO

PRINT 'Tüm tablolar ve indeksler başarıyla oluşturuldu';
GO

PRINT '';

PRINT '2/6 - Acilis proseduru olusturuluyor...';
GO

-- =============================================================
-- AÇILIŞ PROSEDÜRÜ - bkm.sp_fifo_StokMaliyetAcilis
-- Transaction yönetimi ve hata kontrolü ile
-- =============================================================

CREATE OR ALTER PROCEDURE bkm.sp_fifo_StokMaliyetAcilis
(
    @envanterTarihi DATE,
    @stkID INT = NULL,
    @runId UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @stepKey VARCHAR(50) = NULL;
    DECLARE @stepName VARCHAR(100) = NULL;
    DECLARE @stepOrder INT = NULL;
    
    -- Parametre validasyonu
    IF @envanterTarihi IS NULL
    BEGIN
        RAISERROR('Envanter tarihi boş olamaz', 16, 1);
        RETURN;
    END
    
    IF @envanterTarihi > GETDATE()
    BEGIN
        RAISERROR('Envanter tarihi gelecek tarih olamaz', 16, 1);
        RETURN;
    END
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        DECLARE @baslangicTarihi DATE = DATEFROMPARTS(2021, 5, 31);

        SET @stepKey = 'envanter';
        SET @stepName = 'Envanter snapshot';
        SET @stepOrder = 1;
        IF @runId IS NOT NULL
            EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'RUNNING', NULL;

        /* 1) Envanter tarihindeki stok miktarlarını çek */
        IF OBJECT_ID('tempdb..#stoklarMekan', 'U') IS NOT NULL DROP TABLE #stoklarMekan;

        SELECT 
            d.ehMekan AS mekanID,
            d.ehstkID AS stkID,
            SUM(CONVERT(DECIMAL(18,4), d.stok)) AS stokMiktar
        INTO #stoklarMekan
        FROM dbo.stokSonAltDepo_vw d
        WHERE d.ehAltDepo = 0 
          AND d.ehMekan IN (1,4477,4478)
          AND d.stok > 0
          AND (@stkID IS NULL OR d.ehstkID = @stkID)
        GROUP BY d.ehMekan, d.ehstkID;

        CREATE INDEX IX_tmp_stoklarMekan_mekan_stkID ON #stoklarMekan(mekanID, stkID);

        IF OBJECT_ID('tempdb..#stoklar', 'U') IS NOT NULL DROP TABLE #stoklar;

        SELECT
            stkID,
            SUM(stokMiktar) AS stokMiktar
        INTO #stoklar
        FROM #stoklarMekan
        GROUP BY stkID;

        CREATE INDEX IX_tmp_stoklar_stkID ON #stoklar(stkID);

        DELETE FROM bkm.fifo_StokEnvanter
        WHERE envanterTarihi = @envanterTarihi
          AND (@stkID IS NULL OR stkID = @stkID);

        INSERT INTO bkm.fifo_StokEnvanter (envanterTarihi, mekanID, stkID, stokMiktar)
        SELECT @envanterTarihi, mekanID, stkID, stokMiktar
        FROM #stoklarMekan;

        IF @runId IS NOT NULL
            EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'DONE', NULL;

        SET @stepKey = 'alis';
        SET @stepName = 'Alislar toplanir';
        SET @stepOrder = 2;
        IF @runId IS NOT NULL
            EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'RUNNING', NULL;

        /* 2) Başlangıç–envanter arası alışları çek */
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
        FROM #stoklar s
        JOIN dbo.irs i WITH(NOLOCK)
            ON i.eTip IN (2,0,10,3,6,102,103)
           AND i.eTarih >  CONVERT(smalldatetime, @baslangicTarihi)
           AND i.eTarih <  DATEADD(DAY, 1, CONVERT(smalldatetime, @envanterTarihi))
           AND i.eMekan IN (1,4477,4478)
        JOIN dbo.irsAyr ia WITH(NOLOCK)
            ON ia.ehID = i.eID
        JOIN dbo.fatAyr a WITH(NOLOCK)
            ON a.ehIrsID   = i.eID 
           AND a.ehIrsSira = ia.ehSira 
           AND a.ehStkID   = s.stkID
        JOIN dbo.fat f WITH(NOLOCK)
            ON f.eID = a.ehID
        WHERE a.ehAdetN <> 0
          AND (@stkID IS NULL OR a.ehStkID = @stkID)
        GROUP BY a.ehstkID, i.eTarih, i.eID, f.eNo' + @groupByExtra + N'
        HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;';

        EXEC sp_executesql
            @sql,
            N'@baslangicTarihi DATE, @envanterTarihi DATE, @stkID INT',
            @baslangicTarihi = @baslangicTarihi,
            @envanterTarihi = @envanterTarihi,
            @stkID = @stkID;

        ALTER TABLE #alislar ADD birimMaliyet DECIMAL(18,6);

        UPDATE #alislar
        SET birimMaliyet = CASE WHEN miktar = 0 THEN 0 ELSE netTutar / miktar END;

        CREATE INDEX IX_tmp_alislar_stkTarih 
            ON #alislar(stkID, girisTarihi DESC, belgeNo);

        IF @runId IS NOT NULL
            EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'DONE', NULL;

        SET @stepKey = 'katman';
        SET @stepName = 'Ters FIFO katman';
        SET @stepOrder = 3;
        IF @runId IS NOT NULL
            EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'RUNNING', NULL;

        /* 3) Ters FIFO ile açılış katmanlarını hesapla */
        IF OBJECT_ID('tempdb..#katman', 'U') IS NOT NULL DROP TABLE #katman;

        ;WITH Ters AS (
            SELECT
                stkID, girisTarihi, belgeNo, belgeTarihi, firmaID, miktar, birimMaliyet, netTutar,
                SUM(miktar) OVER (
                    PARTITION BY stkID
                    ORDER BY girisTarihi DESC, belgeNo DESC
                    ROWS UNBOUNDED PRECEDING
                ) AS kumTers
            FROM #alislar
            WHERE miktar > 0 AND netTutar > 0
        ),
        Acilis AS (
            SELECT
                t.stkID, t.girisTarihi, t.belgeNo, t.belgeTarihi, t.firmaID,
                t.miktar AS satirMiktar, t.birimMaliyet,
                t.kumTers, s.stokMiktar,
                CASE 
                    WHEN t.kumTers - t.miktar >= s.stokMiktar THEN 0
                    WHEN t.kumTers <= s.stokMiktar THEN t.miktar
                    ELSE s.stokMiktar - (t.kumTers - t.miktar)
                END AS acilisMiktar
            FROM Ters t
            JOIN #stoklar s ON s.stkID = t.stkID
        )
        SELECT * INTO #katman FROM Acilis WHERE acilisMiktar > 0;

        /* 4) Gerçek açılış katmanlarını ACILIS olarak havuza yaz */
        DELETE FROM bkm.fifo_StokMaliyetHavuzu
        WHERE kaynakTip = 'ACILIS' AND girisTarihi = @envanterTarihi
          AND (@stkID IS NULL OR stkID = @stkID);

        INSERT INTO bkm.fifo_StokMaliyetHavuzu
            (stkID, girisTarihi, kaynakTip, belgeNo, belgeTarihi, firmaID,
             miktarToplam, miktarKalan, birimMaliyet, durum)
        SELECT
            stkID, @envanterTarihi, 'ACILIS', belgeNo, belgeTarihi, firmaID,
            acilisMiktar, acilisMiktar, birimMaliyet, 'NORMAL'
        FROM #katman;

        IF @runId IS NOT NULL
            EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'DONE', NULL;

        SET @stepKey = 'sorun';
        SET @stepName = 'Sorun kaydi';
        SET @stepOrder = 4;
        IF @runId IS NOT NULL
            EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'RUNNING', NULL;

        /* 5) Eksik miktarları tespit et */
        ;WITH Ozet AS (
            SELECT stkID, SUM(acilisMiktar) AS toplamAcilisMiktar
            FROM #katman GROUP BY stkID
        ),
        AlisVarMi AS (
            SELECT DISTINCT stkID FROM #alislar
        )
        SELECT
            s.stkID, s.stokMiktar,
            ISNULL(o.toplamAcilisMiktar, 0) AS toplamAcilisMiktar,
            (s.stokMiktar - ISNULL(o.toplamAcilisMiktar, 0)) AS eksikMiktar
        INTO #eksiklar
        FROM #stoklar s
        LEFT JOIN Ozet o ON o.stkID = s.stkID
        LEFT JOIN AlisVarMi v ON v.stkID = s.stkID;

        /* 6) Alışı olan ama yetmeyenleri son alışla tamamla */
        ;WITH SonAlis AS (
            SELECT
                a.stkID, a.girisTarihi, a.belgeNo, a.belgeTarihi, a.firmaID, a.birimMaliyet,
                ROW_NUMBER() OVER (
                    PARTITION BY a.stkID
                    ORDER BY a.girisTarihi DESC, a.belgeNo DESC
                ) AS rn
            FROM #alislar a
        )
        INSERT INTO bkm.fifo_StokMaliyetHavuzu
            (stkID, girisTarihi, kaynakTip, belgeNo, belgeTarihi, firmaID,
             miktarToplam, miktarKalan, birimMaliyet, durum)
        SELECT
            e.stkID, @envanterTarihi, 'ACILIS_TAMAMLA', sa.belgeNo, sa.belgeTarihi, sa.firmaID,
            e.eksikMiktar, e.eksikMiktar, sa.birimMaliyet, 'TAMAMLAMA'
        FROM #eksiklar e
        JOIN SonAlis sa ON sa.stkID = e.stkID AND sa.rn = 1
        WHERE e.eksikMiktar > 0 AND e.toplamAcilisMiktar > 0;


        /* 7) Sorunlu kayıtları oluştur */
        
        /* 6b) Merkez depo (12) alislari ile tamamlama (alis yoksa) */
        IF OBJECT_ID('tempdb..#merkezAlis', 'U') IS NOT NULL DROP TABLE #merkezAlis;
        CREATE TABLE #merkezAlis (
            stkID        INT           NOT NULL,
            girisTarihi  DATETIME      NOT NULL,
            belgeNo      VARCHAR(50)   NULL,
            belgeTarihi  DATE          NULL,
            firmaID      INT           NULL,
            miktar       DECIMAL(18,4) NOT NULL,
            netTutar     DECIMAL(18,4) NOT NULL
        );

        DECLARE @sqlMerkez NVARCHAR(MAX) = N'
        INSERT INTO #merkezAlis (stkID, girisTarihi, belgeNo, belgeTarihi, firmaID, miktar, netTutar)
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
        FROM #eksiklar e
        LEFT JOIN (SELECT DISTINCT stkID FROM #alislar) v ON v.stkID = e.stkID
        JOIN dbo.irs i WITH(NOLOCK)
            ON i.eTip IN (2,0,10,3,6,102,103)
           AND i.eTarih >  CONVERT(smalldatetime, @baslangicTarihi)
           AND i.eTarih <  DATEADD(DAY, 1, CONVERT(smalldatetime, @envanterTarihi))
           AND i.eMekan = 12
        JOIN dbo.irsAyr ia WITH(NOLOCK)
            ON ia.ehID = i.eID
        JOIN dbo.fatAyr a WITH(NOLOCK)
            ON a.ehIrsID   = i.eID
           AND a.ehIrsSira = ia.ehSira
           AND a.ehStkID   = e.stkID
        JOIN dbo.fat f WITH(NOLOCK)
            ON f.eID = a.ehID
        WHERE a.ehAdetN <> 0
          AND v.stkID IS NULL
          AND e.eksikMiktar > 0
          AND (@stkID IS NULL OR a.ehStkID = @stkID)
        GROUP BY a.ehStkID, i.eTarih, i.eID, f.eNo' + @groupByExtra + N'
        HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;';

        EXEC sp_executesql
            @sqlMerkez,
            N'@baslangicTarihi DATE, @envanterTarihi DATE, @stkID INT',
            @baslangicTarihi = @baslangicTarihi,
            @envanterTarihi = @envanterTarihi,
            @stkID = @stkID;

        ALTER TABLE #merkezAlis ADD birimMaliyet DECIMAL(18,6);

        UPDATE #merkezAlis
        SET birimMaliyet = CASE WHEN miktar = 0 THEN 0 ELSE netTutar / miktar END;

        IF OBJECT_ID('tempdb..#merkezSon', 'U') IS NOT NULL DROP TABLE #merkezSon;

        ;WITH SonMerkez AS (
            SELECT
                m.stkID, m.girisTarihi, m.belgeNo, m.belgeTarihi, m.firmaID, m.birimMaliyet,
                ROW_NUMBER() OVER (
                    PARTITION BY m.stkID
                    ORDER BY m.girisTarihi DESC, m.belgeNo DESC
                ) AS rn
            FROM #merkezAlis m
        )
        SELECT
            stkID, girisTarihi, belgeNo, belgeTarihi, firmaID, birimMaliyet
        INTO #merkezSon
        FROM SonMerkez
        WHERE rn = 1;

        INSERT INTO bkm.fifo_StokMaliyetHavuzu
            (stkID, girisTarihi, kaynakTip, belgeNo, belgeTarihi, firmaID,
             miktarToplam, miktarKalan, birimMaliyet, durum)
        SELECT
            e.stkID, @envanterTarihi, 'ACILIS_TAMAMLA', ms.belgeNo, ms.belgeTarihi, ms.firmaID,
            e.eksikMiktar, e.eksikMiktar, ms.birimMaliyet, 'MERKEZ_TAMAMLAMA'
        FROM #eksiklar e
        JOIN #merkezSon ms ON ms.stkID = e.stkID
        LEFT JOIN (SELECT DISTINCT stkID FROM #alislar) v ON v.stkID = e.stkID
        WHERE v.stkID IS NULL AND e.eksikMiktar > 0;

        /* 6c) Son gecerli fiyat ile tamamlama (alis yoksa, merkez de yoksa) */
        IF OBJECT_ID('tempdb..#sonGecerli', 'U') IS NOT NULL DROP TABLE #sonGecerli;

        ;WITH SonFiyat AS (
            SELECT
                f.fhID,
                f.fStkID AS stkID,
                f.fTarih,
                f.fTarihSon,
                f.sonrakiNet,
                ROW_NUMBER() OVER (
                    PARTITION BY f.fStkID
                    ORDER BY f.fTarihSon DESC, f.fhID DESC
                ) AS rn
            FROM bkm.fn_SonGecerliFiyat(@envanterTarihi, 1) f
            WHERE f.sonrakiNet > 0
        )
        SELECT
            stkID,
            fhID,
            fTarih,
            fTarihSon,
            sonrakiNet
        INTO #sonGecerli
        FROM SonFiyat
        WHERE rn = 1;

        INSERT INTO bkm.fifo_StokMaliyetHavuzu
            (stkID, girisTarihi, kaynakTip, belgeNo, belgeTarihi, firmaID,
             miktarToplam, miktarKalan, birimMaliyet, durum)
        SELECT
            e.stkID,
            @envanterTarihi,
            'ACILIS_TAMAMLA',
            CAST(sg.fhID AS VARCHAR(50)),
            CAST(sg.fTarihSon AS DATE),
            NULL,
            e.eksikMiktar,
            e.eksikMiktar,
            sg.sonrakiNet,
            'SART_TAMAMLAMA'
        FROM #eksiklar e
        JOIN #sonGecerli sg ON sg.stkID = e.stkID
        LEFT JOIN (SELECT DISTINCT stkID FROM #alislar) v ON v.stkID = e.stkID
        LEFT JOIN #merkezSon ms ON ms.stkID = e.stkID
        WHERE v.stkID IS NULL
          AND ms.stkID IS NULL
          AND e.eksikMiktar > 0;

        /* 6d) Aylik devir ile tamamlama (alis/merkez/sart yoksa) */
        IF OBJECT_ID('tempdb..#eksikKalan', 'U') IS NOT NULL DROP TABLE #eksikKalan;

        SELECT e.stkID, e.eksikMiktar
        INTO #eksikKalan
        FROM #eksiklar e
        LEFT JOIN (SELECT DISTINCT stkID FROM #alislar) v ON v.stkID = e.stkID
        LEFT JOIN #merkezSon ms ON ms.stkID = e.stkID
        LEFT JOIN #sonGecerli sg ON sg.stkID = e.stkID
        WHERE e.eksikMiktar > 0 AND v.stkID IS NULL AND ms.stkID IS NULL AND sg.stkID IS NULL;

        IF OBJECT_ID('tempdb..#aylikKatman', 'U') IS NOT NULL DROP TABLE #aylikKatman;
        CREATE TABLE #aylikKatman (
            stkID INT NOT NULL,
            ayBitis DATE NOT NULL,
            ayMiktar DECIMAL(18,4) NOT NULL,
            birimMaliyet DECIMAL(18,6) NULL,
            durum VARCHAR(20) NOT NULL
        );

        IF EXISTS (SELECT 1 FROM #eksikKalan)
        BEGIN
            IF OBJECT_ID('tempdb..#aylar', 'U') IS NOT NULL DROP TABLE #aylar;

            ;WITH Aylar AS (
                SELECT
                    ayBas = DATEFROMPARTS(YEAR(@envanterTarihi), MONTH(@envanterTarihi), 1),
                    ayBitis = EOMONTH(@envanterTarihi)
                UNION ALL
                SELECT
                    DATEADD(MONTH, -1, ayBas),
                    EOMONTH(DATEADD(MONTH, -1, ayBas))
                FROM Aylar
                WHERE DATEADD(MONTH, -1, ayBas) >= DATEFROMPARTS(YEAR(@baslangicTarihi), MONTH(@baslangicTarihi), 1)
            )
            SELECT ayBas, ayBitis
            INTO #aylar
            FROM Aylar
            OPTION (MAXRECURSION 0);

            IF OBJECT_ID('tempdb..#aylikStok', 'U') IS NOT NULL DROP TABLE #aylikStok;
            CREATE TABLE #aylikStok (
                stkID INT NOT NULL,
                ayBitis DATE NOT NULL,
                ayStok DECIMAL(18,4) NOT NULL
            );

            INSERT INTO #aylikStok (stkID, ayBitis, ayStok)
            SELECT
                e.stkID,
                a.ayBitis,
                ISNULL(s.ayStok, 0) AS ayStok
            FROM #eksikKalan e
            CROSS JOIN #aylar a
            OUTER APPLY (
                SELECT SUM(f.stok) AS ayStok
                FROM (
                    SELECT g.stkID, g.stok
                    FROM bkm.fn_gecmis_stok_mekan(DATEADD(DAY, 1, a.ayBitis), 1) g
                    UNION ALL
                    SELECT g.stkID, g.stok
                    FROM bkm.fn_gecmis_stok_mekan(DATEADD(DAY, 1, a.ayBitis), 4477) g
                    UNION ALL
                    SELECT g.stkID, g.stok
                    FROM bkm.fn_gecmis_stok_mekan(DATEADD(DAY, 1, a.ayBitis), 4478) g
                ) f
                WHERE f.stkID = e.stkID
            ) s
            WHERE ISNULL(s.ayStok, 0) > 0;

            IF OBJECT_ID('tempdb..#aylikAlloc', 'U') IS NOT NULL DROP TABLE #aylikAlloc;

            ;WITH Aylik AS (
                SELECT
                    s.stkID, s.ayBitis, s.ayStok,
                    SUM(s.ayStok) OVER (
                        PARTITION BY s.stkID
                        ORDER BY s.ayBitis DESC
                        ROWS UNBOUNDED PRECEDING
                    ) AS kumStok
                FROM #aylikStok s
            ),
            Alloc AS (
                SELECT
                    a.stkID, a.ayBitis,
                    CAST(
                        CASE
                            WHEN a.kumStok <= e.eksikMiktar THEN a.ayStok
                            WHEN a.kumStok - a.ayStok < e.eksikMiktar THEN e.eksikMiktar - (a.kumStok - a.ayStok)
                            ELSE 0
                        END AS DECIMAL(18,4)
                    ) AS ayMiktar
                FROM Aylik a
                JOIN #eksikKalan e ON e.stkID = a.stkID
            )
            SELECT * INTO #aylikAlloc FROM Alloc WHERE ayMiktar > 0;

            IF OBJECT_ID('tempdb..#sabitFiyat', 'U') IS NOT NULL DROP TABLE #sabitFiyat;
            CREATE TABLE #sabitFiyat (
                stkID INT NOT NULL,
                birimMaliyet DECIMAL(18,6) NOT NULL
            );

            IF OBJECT_ID('bkm.fifo_SabitFiyat', 'U') IS NOT NULL
            BEGIN
                DECLARE @sqlSabit NVARCHAR(MAX) = N'
                INSERT INTO #sabitFiyat (stkID, birimMaliyet)
                SELECT sf.stkID, sf.birimMaliyet
                FROM bkm.fifo_SabitFiyat sf
                WHERE (@stkID IS NULL OR sf.stkID = @stkID);';

                EXEC sp_executesql
                    @sqlSabit,
                    N'@stkID INT',
                    @stkID = @stkID;
            END

            INSERT INTO #aylikKatman (stkID, ayBitis, ayMiktar, birimMaliyet, durum)
            SELECT
                a.stkID,
                a.ayBitis,
                a.ayMiktar,
                COALESCE(fiyat.sonrakiNet, sf.birimMaliyet) AS birimMaliyet,
                CASE
                    WHEN COALESCE(fiyat.sonrakiNet, sf.birimMaliyet) IS NULL THEN 'FIYAT_YOK'
                    ELSE 'AYLIK_DEVIR'
                END AS durum
            FROM #aylikAlloc a
            OUTER APPLY (
                SELECT TOP (1)
                    f.sonrakiNet,
                    f.fFrmID,
                    f.fTarihSon,
                    f.fhID
                FROM bkm.fn_SonGecerliFiyat_Adv(a.ayBitis, 1, 1, 1) f
                WHERE f.fStkID = a.stkID
                  AND f.sonrakiNet > 0
                  AND (f.fTarihSon IS NULL OR f.fTarihSon >= a.ayBitis)
                ORDER BY
                    CASE WHEN f.fFrmID = 9525 THEN 0 ELSE 1 END,
                    f.fTarihSon DESC,
                    f.fhID DESC
            ) fiyat
            LEFT JOIN #sabitFiyat sf ON sf.stkID = a.stkID;

            INSERT INTO bkm.fifo_StokMaliyetHavuzu
                (stkID, girisTarihi, kaynakTip, belgeNo, belgeTarihi, firmaID,
                 miktarToplam, miktarKalan, birimMaliyet, durum)
            SELECT
                k.stkID, k.ayBitis, 'AYLIK_DEVIR', NULL, k.ayBitis, NULL,
                k.ayMiktar, k.ayMiktar, ISNULL(k.birimMaliyet, 0), k.durum
            FROM #aylikKatman k;
        END

        DELETE FROM bkm.fifo_StokMaliyetSorunlu
        WHERE envanterTarihi = @envanterTarihi
          AND (@stkID IS NULL OR stkID = @stkID);

        INSERT INTO bkm.fifo_StokMaliyetSorunlu
            (stkID, envanterTarihi, stokMiktar, sorunTip, aciklama)
        SELECT
            k.stkID, @envanterTarihi, SUM(k.ayMiktar), 'FIYAT_YOK',
            'Aylik devir katmaninda fiyat bulunamadi.'
        FROM #aylikKatman k
        WHERE k.durum = 'FIYAT_YOK'
        GROUP BY k.stkID;

        INSERT INTO bkm.fifo_StokMaliyetSorunlu
            (stkID, envanterTarihi, stokMiktar, sorunTip, aciklama)
        SELECT
            s.stkID, @envanterTarihi, s.stokMiktar, 'ALIS_YOK',
            'Bu ürüne belirtilen tarih aralığında hiç alış bulunamadı.'
        FROM #stoklar s
        LEFT JOIN (SELECT DISTINCT stkID FROM #alislar) v ON v.stkID = s.stkID
        LEFT JOIN #merkezSon ms ON ms.stkID = s.stkID
        LEFT JOIN #sonGecerli sg ON sg.stkID = s.stkID
        LEFT JOIN (SELECT DISTINCT stkID FROM #aylikKatman) ak ON ak.stkID = s.stkID
        WHERE v.stkID IS NULL AND ms.stkID IS NULL AND sg.stkID IS NULL AND ak.stkID IS NULL;


        INSERT INTO bkm.fifo_StokMaliyetSorunlu
            (stkID, envanterTarihi, stokMiktar, sorunTip, aciklama)
        SELECT
            e.stkID, @envanterTarihi, e.stokMiktar, 'ALIS_YOK_MERKEZ_TAMAMLANDI',
            'Merkez depo (12) son alis fiyati ile tamamlandi.'
        FROM #eksiklar e
        JOIN #merkezSon ms ON ms.stkID = e.stkID;

        INSERT INTO bkm.fifo_StokMaliyetSorunlu
            (stkID, envanterTarihi, stokMiktar, sorunTip, aciklama)
        SELECT
            e.stkID, @envanterTarihi, e.stokMiktar, 'ALIS_YOK_SONGECERLI_TAMAMLANDI',
            'Son gecerli satin alma fiyati (sonrakiNet) ile tamamlandi.'
        FROM #eksiklar e
        JOIN #sonGecerli sg ON sg.stkID = e.stkID
        LEFT JOIN (SELECT DISTINCT stkID FROM #alislar) v ON v.stkID = e.stkID
        LEFT JOIN #merkezSon ms ON ms.stkID = e.stkID
        WHERE v.stkID IS NULL AND ms.stkID IS NULL;

        INSERT INTO bkm.fifo_StokMaliyetSorunlu
            (stkID, envanterTarihi, stokMiktar, sorunTip, aciklama)
        SELECT DISTINCT
            e.stkID, @envanterTarihi, e.stokMiktar, 'ALIS_EKSIK_TAMAMLANDI',
            'Eksik stok son alış fiyatı ile otomatik tamamlandı.'
        FROM #eksiklar e
        WHERE e.eksikMiktar > 0 AND e.toplamAcilisMiktar > 0;

        IF @runId IS NOT NULL
            EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'DONE', NULL;

        COMMIT TRANSACTION;
        
        PRINT 'Açılış stoku başarıyla oluşturuldu. Tarih: ' + 
              CONVERT(VARCHAR(10), @envanterTarihi, 120);
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @runMessage VARCHAR(500) = SUBSTRING(CONVERT(VARCHAR(500), @ErrorMessage), 1, 500);

        IF @runId IS NOT NULL AND @stepKey IS NOT NULL
            EXEC bkm.sp_fifo_RunStep
                @runId = @runId,
                @stepKey = @stepKey,
                @stepName = @stepName,
                @stepOrder = @stepOrder,
                @status = 'ERROR',
                @message = @runMessage;
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        DECLARE @ErrorLine INT = ERROR_LINE();
        
        INSERT INTO bkm.fifo_StokMaliyetSorunlu
            (stkID, envanterTarihi, stokMiktar, sorunTip, aciklama)
        VALUES (0, @envanterTarihi, 0, 'PROSEDUR_HATASI', 
                'sp_fifo_StokMaliyetAcilis - Satır: ' + CAST(@ErrorLine AS VARCHAR(10)) + 
                ' - ' + @ErrorMessage);
        
        THROW;
    END CATCH
END
GO

PRINT 'sp_fifo_StokMaliyetAcilis prosedürü oluşturuldu';
GO

PRINT '';

PRINT '3/6 - Alis katmanlari proseduru olusturuluyor...';
GO

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

PRINT '';

PRINT '4/6 - FIFO cikis proseduru olusturuluyor...';
GO

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

PRINT '';

PRINT '5/6 - Toplu calistirma proseduru olusturuluyor...';
GO

-- =============================================================
-- TOPLU FIFO CALISTIRMA PROSEDURU
-- Amaç: Manuel ve job calistirmalari ayni SP uzerinden yapmak
-- =============================================================


CREATE OR ALTER PROCEDURE bkm.sp_fifo_RunStep
(
    @runId UNIQUEIDENTIFIER,
    @stepKey VARCHAR(50),
    @stepName VARCHAR(100),
    @stepOrder INT,
    @status VARCHAR(20),
    @message VARCHAR(500) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @runId IS NULL OR @stepKey IS NULL
        RETURN;

    IF EXISTS (SELECT 1 FROM bkm.fifo_RunStep WHERE runId = @runId AND stepKey = @stepKey)
    BEGIN
        UPDATE bkm.fifo_RunStep
        SET status = @status,
            stepName = @stepName,
            stepOrder = @stepOrder,
            message = @message,
            startedAt = CASE
                WHEN @status IN ('RUNNING','DONE','ERROR','SKIPPED') AND startedAt IS NULL THEN GETDATE()
                ELSE startedAt
            END,
            endedAt = CASE
                WHEN @status IN ('DONE','ERROR','SKIPPED') THEN GETDATE()
                ELSE endedAt
            END,
            updatedAt = GETDATE()
        WHERE runId = @runId AND stepKey = @stepKey;
    END
    ELSE
    BEGIN
        INSERT INTO bkm.fifo_RunStep
            (runId, stepKey, stepName, stepOrder, status, message, startedAt, endedAt)
        VALUES
            (@runId, @stepKey, @stepName, @stepOrder, @status, @message,
             CASE WHEN @status IN ('RUNNING','DONE','ERROR','SKIPPED') THEN GETDATE() ELSE NULL END,
             CASE WHEN @status IN ('DONE','ERROR','SKIPPED') THEN GETDATE() ELSE NULL END);
    END
END
GO

CREATE OR ALTER PROCEDURE bkm.sp_fifo_StokMaliyetCalistir
(
    @envanterTarihi  DATE = NULL,
    @alisBaslangic   DATE = NULL,
    @alisBitis       DATE = NULL,
    @satisBaslangic  DATE = NULL,
    @satisBitis      DATE = NULL,
    @stkID           INT = NULL,
    @runId           UNIQUEIDENTIFIER = NULL,
    @calistirAcilis  BIT  = 0,
    @calistirAlis    BIT  = 1,
    @calistirCikis   BIT  = 1
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @stepKey VARCHAR(50) = NULL;
    DECLARE @stepName VARCHAR(100) = NULL;
    DECLARE @stepOrder INT = NULL;

    IF @calistirAcilis = 1 AND @envanterTarihi IS NULL
    BEGIN
        RAISERROR('Envanter tarihi bos olamaz', 16, 1);
        RETURN;
    END

    IF @calistirAlis = 1 AND (@alisBaslangic IS NULL OR @alisBitis IS NULL)
    BEGIN
        RAISERROR('Alis tarihleri bos olamaz', 16, 1);
        RETURN;
    END

    IF @calistirCikis = 1 AND (@satisBaslangic IS NULL OR @satisBitis IS NULL)
    BEGIN
        RAISERROR('Satis tarihleri bos olamaz', 16, 1);
        RETURN;
    END

    IF @calistirAlis = 1 AND @alisBaslangic > @alisBitis
    BEGIN
        RAISERROR('Alis baslangic tarihi bitis tarihinden buyuk olamaz', 16, 1);
        RETURN;
    END

    IF @calistirCikis = 1 AND @satisBaslangic > @satisBitis
    BEGIN
        RAISERROR('Satis baslangic tarihi bitis tarihinden buyuk olamaz', 16, 1);
        RETURN;
    END

    BEGIN TRY
        IF @calistirAcilis = 1
        BEGIN
            EXEC bkm.sp_fifo_StokMaliyetAcilis
                @envanterTarihi = @envanterTarihi,
                @stkID = @stkID,
                @runId = @runId;
        END

        IF @calistirAlis = 1
        BEGIN
            SET @stepKey = 'alis';
            SET @stepName = 'Alis katman';
            SET @stepOrder = 1;
            IF @runId IS NOT NULL
                EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'RUNNING', NULL;

            EXEC bkm.sp_fifo_StokMaliyetAlisKatman
                @baslangicTarihi = @alisBaslangic,
                @bitisTarihi = @alisBitis,
                @stkID = @stkID,
                @runId = @runId;

            IF @runId IS NOT NULL
                EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'DONE', NULL;
        END
        ELSE IF @runId IS NOT NULL AND @calistirCikis = 1
        BEGIN
            EXEC bkm.sp_fifo_RunStep @runId, 'alis', 'Alis katman', 1, 'SKIPPED', 'CalistirAlis=0';
        END

        IF @calistirCikis = 1
        BEGIN
            SET @stepKey = 'cikis';
            SET @stepName = 'FIFO cikis';
            SET @stepOrder = 2;
            IF @runId IS NOT NULL
                EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'RUNNING', NULL;

            EXEC bkm.sp_fifo_StokMaliyetFIFOCikis
                @satisBaslangic = @satisBaslangic,
                @satisBitis = @satisBitis,
                @stkID = @stkID,
                @runId = @runId;

            IF @runId IS NOT NULL
                EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'DONE', NULL;

            SET @stepKey = 'rapor';
            SET @stepName = 'Sonuc hazirligi';
            SET @stepOrder = 3;
            IF @runId IS NOT NULL
            BEGIN
                EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'RUNNING', NULL;
                EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'DONE', NULL;
            END
        END
        ELSE IF @runId IS NOT NULL AND @calistirAlis = 1
        BEGIN
            EXEC bkm.sp_fifo_RunStep @runId, 'cikis', 'FIFO cikis', 2, 'SKIPPED', 'CalistirCikis=0';
            EXEC bkm.sp_fifo_RunStep @runId, 'rapor', 'Sonuc hazirligi', 3, 'SKIPPED', 'CalistirCikis=0';
        END
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @runMessage VARCHAR(500) = SUBSTRING(CONVERT(VARCHAR(500), @ErrorMessage), 1, 500);
        IF @runId IS NOT NULL AND @stepKey IS NOT NULL
            EXEC bkm.sp_fifo_RunStep
                @runId = @runId,
                @stepKey = @stepKey,
                @stepName = @stepName,
                @stepOrder = @stepOrder,
                @status = 'ERROR',
                @message = @runMessage;
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        THROW;
    END CATCH
END
GO

PRINT 'sp_fifo_StokMaliyetCalistir proseduru olusturuldu';
GO

PRINT '';

PRINT '6/6 - Raporlama view''lari olusturuluyor...';
GO

-- =============================================================
-- RAPORLAMA VIEW'LARI
-- =============================================================

-- Günlük SMM Raporu
CREATE OR ALTER VIEW bkm.fifo_vw_GunlukSMM
AS
SELECT
    hareketTarihi,
    SUM(CASE WHEN hareketTipi = 'SATIS' THEN cikisTutar ELSE 0 END) AS satisMaliyeti,
    SUM(CASE WHEN hareketTipi = 'IADE' THEN cikisTutar ELSE 0 END) AS iadeMaliyeti,
    SUM(cikisTutar) AS netMaliyet,
    COUNT(*) AS satirSayisi
FROM bkm.fifo_StokMaliyetCikis
GROUP BY hareketTarihi;
GO

-- Ürün Bazlı SMM
CREATE OR ALTER VIEW bkm.fifo_vw_UrunBazliSMM
AS
SELECT
    stkID,
    hareketTarihi,
    hareketTipi,
    SUM(miktar) AS toplamMiktar,
    SUM(cikisTutar) AS toplamMaliyet,
    CASE WHEN SUM(miktar) <> 0 
         THEN SUM(cikisTutar) / SUM(miktar) 
         ELSE 0 
    END AS ortalamaBirimMaliyet
FROM bkm.fifo_StokMaliyetCikis
GROUP BY stkID, hareketTarihi, hareketTipi;
GO

-- Katman Durumu Raporu
CREATE OR ALTER VIEW bkm.fifo_vw_KatmanDurumu
AS
SELECT
    stkID,
    kaynakTip,
    girisTarihi,
    COUNT(*) AS katmanSayisi,
    SUM(miktarToplam) AS toplamMiktar,
    SUM(miktarKalan) AS kalanMiktar,
    SUM(miktarToplam - miktarKalan) AS tukenenMiktar,
    AVG(birimMaliyet) AS ortalamaBirimMaliyet,
    MIN(birimMaliyet) AS minBirimMaliyet,
    MAX(birimMaliyet) AS maxBirimMaliyet
FROM bkm.fifo_StokMaliyetHavuzu
GROUP BY stkID, kaynakTip, girisTarihi;
GO

-- Sorunlu Stoklar Özeti
CREATE OR ALTER VIEW bkm.fifo_vw_SorunluStoklar
AS
SELECT
    sorunTip,
    envanterTarihi,
    COUNT(DISTINCT stkID) AS urunSayisi,
    SUM(stokMiktar) AS toplamMiktar,
    MIN(kayitTarihi) AS ilkKayit,
    MAX(kayitTarihi) AS sonKayit
FROM bkm.fifo_StokMaliyetSorunlu
GROUP BY sorunTip, envanterTarihi;
GO

PRINT 'Tüm raporlama view''ları oluşturuldu';
GO

PRINT '';


PRINT '========================================';
PRINT 'Deployment tamamlandi!';
PRINT '========================================';
PRINT '';
PRINT 'Olusturulan Objeler:';
PRINT '- 7 Tablo (fifo_StokMaliyetHavuzu, fifo_StokEnvanter, fifo_StokMaliyetSorunlu, fifo_SabitFiyat, fifo_StokMaliyetCikis, fifo_Run, fifo_RunStep)';
PRINT '- 11 Indeks';
PRINT '- 5 Prosedur (sp_fifo_RunStep, sp_fifo_StokMaliyetAcilis, sp_fifo_StokMaliyetAlisKatman, sp_fifo_StokMaliyetFIFOCikis, sp_fifo_StokMaliyetCalistir)';
PRINT '- 4 View (fifo_vw_GunlukSMM, fifo_vw_UrunBazliSMM, fifo_vw_KatmanDurumu, fifo_vw_SorunluStoklar)';
PRINT '';
PRINT 'Kullanim Ornekleri:';
PRINT '-- Acilis stoku olustur:';
PRINT 'EXEC bkm.sp_fifo_StokMaliyetAcilis @envanterTarihi = ''31.12.2025'';';
PRINT '';
PRINT '-- Alis katmanlari ekle:';
PRINT 'EXEC bkm.sp_fifo_StokMaliyetAlisKatman @baslangicTarihi = ''01.01.2026'', @bitisTarihi = ''31.01.2026'';';
PRINT '';
PRINT '-- FIFO cikis hesapla:';
PRINT 'EXEC bkm.sp_fifo_StokMaliyetFIFOCikis @satisBaslangic = ''01.01.2026'', @satisBitis = ''31.01.2026'';';
PRINT '';
PRINT '-- Gunluk SMM raporu:';
PRINT 'SELECT * FROM bkm.fifo_vw_GunlukSMM WHERE hareketTarihi >= ''01.01.2026'';';
GO




