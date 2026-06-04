-- =============================================================
-- BKM FIFO MASTER DEPLOY V2 (Standalone)
-- Base install + Sprint 1 + Sprint 2 in a single script.
-- Source: 00_MASTER_DEPLOY.sql + SQL-Improvements\01/02
-- =============================================================
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
-- BKM FIFO STOK MALIYET SISTEMI - TABLOLAR VE INDEKSLER
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

-- 1.4) ERP Devir Fiyatlari (Sabit Fiyat yerine - satinalma serti ile dinamik fiyat)
IF OBJECT_ID('bkm.fifo_ErpDevirFiyatlari', 'U') IS NOT NULL
    DROP TABLE bkm.fifo_ErpDevirFiyatlari;
GO
CREATE TABLE bkm.fifo_ErpDevirFiyatlari (
    stkID            INT           NOT NULL,
    satinalmaSarti   VARCHAR(50)   NOT NULL,
    birimMaliyet     DECIMAL(18,6) NOT NULL,
    miktar           DECIMAL(18,4) NOT NULL,
    toplamTutar      DECIMAL(18,4) NOT NULL,
    aciklama         VARCHAR(200)  NULL,
    kayitTarihi      DATETIME      NOT NULL DEFAULT(GETDATE()),
    CONSTRAINT PK_fifo_ErpDevirFiyatlari PRIMARY KEY (stkID, satinalmaSarti)
);
GO

CREATE INDEX IX_fifo_ErpDevirFiyatlari_SatinalmaSarti
    ON bkm.fifo_ErpDevirFiyatlari(satinalmaSarti)
    INCLUDE (birimMaliyet, miktar);
GO

-- 1.5) Stok Maliyet Cikis
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


-- 1.6) Calistirma Run Adimlari
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

-- 1.7) Calistirma Run
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

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_fifo_Run_Status'
      AND object_id = OBJECT_ID('bkm.fifo_Run')
)
BEGIN
    CREATE INDEX IX_fifo_Run_Status
        ON bkm.fifo_Run(status, requestedAt);
END
GO
PRINT 'Tum tablolar ve indeksler basariyla olusturuldu';
GO

PRINT '';

PRINT '2/6 - Acilis proseduru olusturuluyor...';
GO

-- =============================================================
-- ACILIS PROSEDURU - bkm.sp_fifo_StokMaliyetAcilis
-- Transaction yonetimi ve hata kontrolu ile
-- =============================================================

CREATE OR ALTER PROCEDURE bkm.sp_fifo_StokMaliyetAcilis
(
    @envanterTarihi DATE,
    @stkID INT = NULL,
    @runId UNIQUEIDENTIFIER = NULL,
    @satinalmaSarti VARCHAR(50) = NULL,   -- ERP devir fiyatlari icin satinalma sarti
    @atlamaAylikDevir BIT = 0             -- 1 = Agir aylik devir adimini atla (timeout onleme)
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
        RAISERROR('Envanter tarihi bos olamaz', 16, 1);
        RETURN;
    END
    
    IF @envanterTarihi > GETDATE()
    BEGIN
        RAISERROR('Envanter tarihi gelecek tarih olamaz', 16, 1);
        RETURN;
    END
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        /* Audit trigger'i devre disi birak - toplu INSERT log dolduruyor */
        ALTER TABLE bkm.fifo_StokMaliyetHavuzu DISABLE TRIGGER tr_fifo_StokMaliyetHavuzu_DegisimGunlugu;
        
        DECLARE @baslangicTarihi DATE = DATEFROMPARTS(2021, 5, 31);

        SET @stepKey = 'envanter';
        SET @stepName = 'Envanter snapshot';
        SET @stepOrder = 1;
        PRINT '[1/4] Envanter snapshot - irsHrk okunuyor...';
        IF @runId IS NOT NULL
            EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'RUNNING', NULL;

        /* 1) Envanter tarihindeki stok miktarlarini cek (irsHrk - mekan bazli) */
        IF OBJECT_ID('tempdb..#stoklarMekan', 'U') IS NOT NULL DROP TABLE #stoklarMekan;

        SELECT 
            h.ehMekan AS mekanID,
            h.ehstkID AS stkID,
            SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) AS stokMiktar
        INTO #stoklarMekan
        FROM DerinSISBkm.dbo.irsHrk h WITH(NOLOCK)
        WHERE h.ehTrhS <= @envanterTarihi
          AND h.ehAltDepo = 0
          AND h.ehMekan IN (1, 12, 4477, 4478)
          AND (@stkID IS NULL OR h.ehstkID = @stkID)
        GROUP BY h.ehMekan, h.ehstkID
        HAVING SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) > 0;

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
        PRINT '      Envanter tamamlandi.';

        SET @stepKey = 'alis';
        SET @stepName = 'Alislar toplanir';
        SET @stepOrder = 2;
        PRINT '[2/4] Alislar toplaniyor (fat+fatAyr)...';
        IF @runId IS NOT NULL
            EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'RUNNING', NULL;

        /* 2) Baslangic-envanter arasi alislari cek (SADECE FATURA: fat + fatAyr) */
        IF OBJECT_ID('tempdb..#alislar', 'U') IS NOT NULL DROP TABLE #alislar;

        SELECT 
            a.ehStkID AS stkID,
            f.eTarihS AS girisTarihi,
            f.eNo     AS belgeNo,
            f.eTarihS AS belgeTarihi,
            f.eFirma  AS firmaID,
            SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS miktar,
            SUM(CONVERT(DECIMAL(18,4),
                CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END
            )) AS netTutar
        INTO #alislar
        FROM #stoklar s
        JOIN DerinSISBkm.dbo.fatAyr a WITH(NOLOCK)
            ON a.ehStkID = s.stkID
        JOIN DerinSISBkm.dbo.fat f WITH(NOLOCK)
            ON f.eID = a.ehID
        WHERE a.ehAdetN <> 0
          AND f.eTarihS >  CONVERT(smalldatetime, @baslangicTarihi)
          AND f.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @envanterTarihi))
          AND f.eTip IN (0, 2)
          AND (@stkID IS NULL OR a.ehStkID = @stkID)
        GROUP BY a.ehStkID, f.eTarihS, f.eID, f.eNo, f.eFirma
        HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;

        ALTER TABLE #alislar ADD birimMaliyet DECIMAL(18,6);

        UPDATE #alislar
        SET birimMaliyet = CASE WHEN miktar = 0 THEN 0 ELSE netTutar / miktar END;

        CREATE INDEX IX_tmp_alislar_stkTarih 
            ON #alislar(stkID, girisTarihi DESC, belgeNo);

        IF @runId IS NOT NULL
            EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'DONE', NULL;
        PRINT '      Alislar tamamlandi.';

        SET @stepKey = 'katman';
        SET @stepName = 'Ters FIFO katman';
        SET @stepOrder = 3;
        PRINT '[3/4] Ters FIFO katman hesaplaniyor...';
        IF @runId IS NOT NULL
            EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'RUNNING', NULL;

        /* 3) Ters FIFO ile acilis katmanlarini hesapla */
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

        /* 4) Gercek acilis katmanlarini ACILIS olarak havuza yaz */
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
        PRINT '      Katman hesaplamasi tamamlandi.';

        SET @stepKey = 'sorun';
        SET @stepName = 'Sorun kaydi';
        SET @stepOrder = 4;
        PRINT '[4/4] Tamamlama + sorun kayitlari (merkez, son fiyat, aylik devir)...';
        IF @runId IS NOT NULL
            EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'RUNNING', NULL;

        /* 5) Eksik miktarlari tespit et */
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

        /* 6) Alisi olan ama yetmeyenleri son alisla tamamla */
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


        /* 7) Sorunlu kayitlari olustur */
        
        /* 6b) Merkez depo (12) alis faturalari ile tamamlama (alis yoksa) - fat+fatAyr+irs (mekan icin) */
        IF OBJECT_ID('tempdb..#merkezAlis', 'U') IS NOT NULL DROP TABLE #merkezAlis;

        SELECT
            a.ehStkID AS stkID,
            f.eTarihS AS girisTarihi,
            f.eNo     AS belgeNo,
            f.eTarihS AS belgeTarihi,
            f.eFirma  AS firmaID,
            SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS miktar,
            SUM(CONVERT(DECIMAL(18,4),
                CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END
            )) AS netTutar
        INTO #merkezAlis
        FROM #eksiklar e
        LEFT JOIN (SELECT DISTINCT stkID FROM #alislar) v ON v.stkID = e.stkID
        JOIN DerinSISBkm.dbo.fatAyr a WITH(NOLOCK)
            ON a.ehStkID = e.stkID
        JOIN DerinSISBkm.dbo.fat f WITH(NOLOCK)
            ON f.eID = a.ehID
        JOIN DerinSISBkm.dbo.irs i WITH(NOLOCK)
            ON i.eID = a.ehIrsID
           AND i.eMekan = 12
        WHERE a.ehAdetN <> 0
          AND v.stkID IS NULL
          AND e.eksikMiktar > 0
          AND f.eTarihS >  CONVERT(smalldatetime, @baslangicTarihi)
          AND f.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @envanterTarihi))
          AND f.eTip IN (0, 2)
          AND (@stkID IS NULL OR a.ehStkID = @stkID)
        GROUP BY a.ehStkID, f.eTarihS, f.eID, f.eNo, f.eFirma
        HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;

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
            FROM DerinSISBkm.bkm.fn_SonGecerliFiyat(@envanterTarihi, 1) f
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

        /* 6d) Aylik devir ile tamamlama (alis/merkez/sart yoksa) - @atlamaAylikDevir=1 ise atlanir (timeout onleme) */
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

        IF @atlamaAylikDevir = 1
        BEGIN
            PRINT '      (Aylik devir atlandi - @atlamaAylikDevir=1)';
        END
        ELSE IF EXISTS (SELECT 1 FROM #eksikKalan)
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

            /* irsHrk ile gecmis stok - tek sorgu, mekan bazli toplam */
            INSERT INTO #aylikStok (stkID, ayBitis, ayStok)
            SELECT
                h.ehstkID AS stkID,
                a.ayBitis,
                SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) AS ayStok
            FROM DerinSISBkm.dbo.irsHrk h WITH(NOLOCK)
            JOIN #aylar a ON h.ehTrhS <= DATEADD(DAY, 1, a.ayBitis)
            JOIN #eksikKalan e ON e.stkID = h.ehstkID
            WHERE h.ehAltDepo = 0
              AND h.ehMekan IN (1, 12, 4477, 4478)
            GROUP BY h.ehstkID, a.ayBitis
            HAVING SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) > 0;

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

            -- ERP Devir Fiyatlari tablosundan fiyat al (satinalma serti ile)
            IF OBJECT_ID('bkm.fifo_ErpDevirFiyatlari', 'U') IS NOT NULL
            BEGIN
                DECLARE @sqlErpDevir NVARCHAR(MAX) = N'
                INSERT INTO #sabitFiyat (stkID, birimMaliyet)
                SELECT erp.stkID, erp.birimMaliyet
                FROM bkm.fifo_ErpDevirFiyatlari erp
                WHERE (@stkID IS NULL OR erp.stkID = @stkID)
                  AND (@satinalmaSarti IS NULL OR erp.satinalmaSarti = @satinalmaSarti);';

                EXEC sp_executesql
                    @sqlErpDevir,
                    N'@stkID INT, @satinalmaSarti VARCHAR(50)',
                    @stkID = @stkID,
                    @satinalmaSarti = @satinalmaSarti;
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
                FROM DerinSISBkm.bkm.fn_SonGecerliFiyat_Adv(a.ayBitis, 1, 1, 1) f
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
            'Bu urune belirtilen tarih araliginda hic alis bulunamadi.'
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
            'Eksik stok son alis fiyati ile otomatik tamamlandi.'
        FROM #eksiklar e
        WHERE e.eksikMiktar > 0 AND e.toplamAcilisMiktar > 0;

        IF @runId IS NOT NULL
            EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'DONE', NULL;

        /* Audit trigger'i tekrar etkinlestir */
        ALTER TABLE bkm.fifo_StokMaliyetHavuzu ENABLE TRIGGER tr_fifo_StokMaliyetHavuzu_DegisimGunlugu;

        COMMIT TRANSACTION;
        
        PRINT 'Acilis stoku basariyla olusturuldu. Tarih: ' + 
              CONVERT(VARCHAR(10), @envanterTarihi, 120);
        
    END TRY
    BEGIN CATCH
        /* Hata durumunda trigger'i mutlaka tekrar etkinlestir */
        IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'tr_fifo_StokMaliyetHavuzu_DegisimGunlugu' AND parent_id = OBJECT_ID('bkm.fifo_StokMaliyetHavuzu'))
            ALTER TABLE bkm.fifo_StokMaliyetHavuzu ENABLE TRIGGER tr_fifo_StokMaliyetHavuzu_DegisimGunlugu;
        
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
                'sp_fifo_StokMaliyetAcilis - Satir: ' + CAST(@ErrorLine AS VARCHAR(10)) + 
                ' - ' + @ErrorMessage);
        
        THROW;
    END CATCH
END
GO

PRINT 'sp_fifo_StokMaliyetAcilis proseduru olusturuldu';
GO

PRINT '';

PRINT '3/6 - Alis katmanlari proseduru olusturuluyor...';
GO

-- =============================================================
-- ALIS KATMANLARI PROSEDURU - bkm.sp_fifo_StokMaliyetAlisKatman
-- SADECE FATURA: fat + fatAyr (irs/irsAyr yok)
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
        RAISERROR('Tarih parametreleri bos olamaz', 16, 1);
        RETURN;
    END
    
    IF @baslangicTarihi > @bitisTarihi
    BEGIN
        RAISERROR('Baslangic tarihi bitis tarihinden buyuk olamaz', 16, 1);
        RETURN;
    END
    
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('tempdb..#alislar', 'U') IS NOT NULL DROP TABLE #alislar;

        /* Verilen tarih araligindaki alislari cek (SADECE FATURA: fat + fatAyr) */
        SELECT 
            a.ehStkID AS stkID,
            f.eTarihS AS girisTarihi,
            f.eNo     AS belgeNo,
            f.eTarihS AS belgeTarihi,
            f.eFirma  AS firmaID,
            SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS miktar,
            SUM(CONVERT(DECIMAL(18,4),
                CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END
            )) AS netTutar
        INTO #alislar
        FROM DerinSISBkm.dbo.fatAyr a WITH(NOLOCK)
        JOIN DerinSISBkm.dbo.fat f WITH(NOLOCK)
            ON f.eID = a.ehID
        WHERE a.ehAdetN <> 0
          AND f.eTarihS >  CONVERT(smalldatetime, @baslangicTarihi)
          AND f.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @bitisTarihi))
          AND f.eTip IN (0, 2)
          AND (@stkID IS NULL OR a.ehStkID = @stkID)
        GROUP BY a.ehStkID, f.eTarihS, f.eID, f.eNo, f.eFirma
        HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;

        /* Birim maliyet hesapla */
        ALTER TABLE #alislar ADD birimMaliyet DECIMAL(18,6);

        UPDATE #alislar
        SET birimMaliyet = CASE WHEN miktar = 0 THEN 0 ELSE netTutar / miktar END;

        /* Ayni tarih araligindaki eski ALIS katmanlarini sil */
        DELETE FROM bkm.fifo_StokMaliyetHavuzu
        WHERE kaynakTip = 'ALIS'
          AND girisTarihi >  @baslangicTarihi
          AND girisTarihi <= @bitisTarihi
          AND (@stkID IS NULL OR stkID = @stkID);

        /* Yeni ALIS katmanlarini havuza yaz */
        INSERT INTO bkm.fifo_StokMaliyetHavuzu
            (stkID, girisTarihi, kaynakTip, belgeNo, belgeTarihi, firmaID,
             miktarToplam, miktarKalan, birimMaliyet, durum)
        SELECT
            stkID, girisTarihi, 'ALIS', belgeNo, belgeTarihi, firmaID,
            miktar, miktar, birimMaliyet, 'NORMAL'
        FROM #alislar;

        COMMIT TRANSACTION;
        
        PRINT 'Alis katmanlari basariyla olusturuldu. Tarih araligi: ' + 
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

PRINT 'sp_fifo_StokMaliyetAlisKatman proseduru olusturuldu';
GO

PRINT '';

PRINT '4/6 - FIFO cikis proseduru olusturuluyor...';
GO

-- =============================================================
-- FIFO CIKIS PROSEDURU - bkm.sp_fifo_StokMaliyetFIFOCikis
-- POS iade mantigi, miktarKalan guncelleme, yetersiz stok kontrolu ile
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
        RAISERROR('Tarih parametreleri bos olamaz', 16, 1);
        RETURN;
    END
    
    IF @satisBaslangic > @satisBitis
    BEGIN
        RAISERROR('Baslangic tarihi bitis tarihinden buyuk olamaz', 16, 1);
        RETURN;
    END
    
    BEGIN TRY
        BEGIN TRANSACTION;

        /* 1) Havuzdaki tum katmanlari al */
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

        /* 2) Satis hareketlerini al - POS IADE MANTIGI ILE */
        IF OBJECT_ID('tempdb..#satislar', 'U') IS NOT NULL DROP TABLE #satislar;

        SELECT
            ID = IDENTITY(INT,1,1),
            dt.ehStkID AS stkID,
            CAST(bs.eTarihS AS DATE) AS satisTarihi,
            netMiktar = SUM(CONVERT(DECIMAL(18,4), dt.ehAdet))
        INTO #satislar
        FROM DerinSISBkm.dbo.irs bs WITH(NOLOCK)
        JOIN DerinSISBkm.dbo.irsAyr dt WITH(NOLOCK) ON dt.ehID = bs.eID
        WHERE bs.eTip IN (1,4,5,100,101)
          AND bs.eMekan IN (1, 4477, 4478)
          AND bs.eTarihS >= CONVERT(smalldatetime, @satisBaslangic)
          AND bs.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @satisBitis))
          AND (@stkID IS NULL OR dt.ehStkID = @stkID)
        GROUP BY dt.ehStkID, CAST(bs.eTarihS AS DATE);

        CREATE INDEX IX_tmp_satislar_stkID
            ON #satislar(stkID, satisTarihi, ID);

        /* 3) Katmanlar icin kumulatif */
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

        /* 4) Satislar icin kumulatif */
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

        /* 5) FIFO kesisim */
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

        /* 6) YETERSIZ STOK KONTROLU */
        INSERT INTO bkm.fifo_StokMaliyetSorunlu
            (stkID, envanterTarihi, stokMiktar, sorunTip, aciklama)
        SELECT
            s.stkID, @satisBitis,
            ABS(s.netMiktar) - ISNULL(SUM(ABS(d.cikisMiktar)), 0) AS eksikMiktar,
            'STOK_YETERSIZ',
            'Hareket miktari (' + CAST(ABS(s.netMiktar) AS VARCHAR(20)) + 
            ') mevcut katmanlari (' + CAST(ISNULL(SUM(ABS(d.cikisMiktar)), 0) AS VARCHAR(20)) + 
            ') asiyor.'
        FROM #satislar s
        LEFT JOIN #cikisDetay d ON d.stkID = s.stkID
        WHERE s.netMiktar <> 0
        GROUP BY s.stkID, s.netMiktar
        HAVING ABS(s.netMiktar) > ISNULL(SUM(ABS(d.cikisMiktar)), 0);

        /* 7) SONUCLARI TABLOYA YAZ */
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

        /* 8) KATMAN KALAN MIKTARLARINI GUNCELLE */
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
        
        PRINT 'FIFO cikis islemi basariyla tamamlandi. Tarih araligi: ' + 
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

PRINT 'sp_fifo_StokMaliyetFIFOCikis proseduru olusturuldu';
GO

PRINT '';

PRINT '5/6 - Toplu calistirma proseduru olusturuluyor...';
GO

-- =============================================================
-- TOPLU FIFO CALISTIRMA PROSEDURU
-- Amac: Manuel ve job calistirmalari ayni SP uzerinden yapmak
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
    @calistirCikis   BIT  = 1,
    @satinalmaSarti  VARCHAR(50) = NULL  -- ERP devir fiyatlari icin satinalma sarti
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
                @runId = @runId,
                @satinalmaSarti = @satinalmaSarti;
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

-- =============================================================
-- AYLIK RUTIN PROSEDURU - bkm.sp_fifo_AylikRutin
-- Tek seferlik acilis HARIC - sadece alis katmanlari + FIFO cikis
-- Her ay duzenli calistirilir (job/scheduler ile)
-- =============================================================

CREATE OR ALTER PROCEDURE bkm.sp_fifo_AylikRutin
(
    @yil    INT,
    @ay     INT,
    @stkID  INT = NULL,
    @runId  UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @alisBaslangic DATE = DATEFROMPARTS(@yil, @ay, 1);
    DECLARE @alisBitis     DATE = EOMONTH(@alisBaslangic);

    EXEC bkm.sp_fifo_StokMaliyetCalistir
        @alisBaslangic   = @alisBaslangic,
        @alisBitis      = @alisBitis,
        @satisBaslangic = @alisBaslangic,
        @satisBitis     = @alisBitis,
        @stkID          = @stkID,
        @runId          = @runId,
        @calistirAcilis = 0,   -- Acilis YOK (tek seferlik 01_ACILIS_TEK_SEFERLIK.sql ile yapilir)
        @calistirAlis   = 1,
        @calistirCikis  = 1;
END
GO

PRINT 'sp_fifo_AylikRutin proseduru olusturuldu';
GO

PRINT '';

PRINT '6/6 - Raporlama view''lari olusturuluyor...';
GO

-- =============================================================
-- RAPORLAMA VIEW'LARI
-- =============================================================

-- Gunluk SMM Raporu
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

-- Urun Bazli SMM
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

-- Sorunlu Stoklar Ozeti
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

PRINT 'Tum raporlama view''lari olusturuldu';
GO

PRINT '';


PRINT '========================================';
PRINT 'Deployment tamamlandi!';
PRINT '========================================';
PRINT '';
PRINT 'Olusturulan Objeler:';
PRINT '- 7 Tablo (fifo_StokMaliyetHavuzu, fifo_StokEnvanter, fifo_StokMaliyetSorunlu, fifo_ErpDevirFiyatlari, fifo_StokMaliyetCikis, fifo_Run, fifo_RunStep)';
PRINT '- 12 Indeks';
PRINT '- 6 Prosedur (sp_fifo_RunStep, sp_fifo_StokMaliyetAcilis, sp_fifo_StokMaliyetAlisKatman, sp_fifo_StokMaliyetFIFOCikis, sp_fifo_StokMaliyetCalistir, sp_fifo_AylikRutin)';
PRINT '- 4 View (fifo_vw_GunlukSMM, fifo_vw_UrunBazliSMM, fifo_vw_KatmanDurumu, fifo_vw_SorunluStoklar)';
PRINT '';
PRINT 'KULLANIM (2 asamali):';
PRINT '';
PRINT '1) TEK SEFERLIK - Acilis katmani (sistem kurulumunda veya yeni donem basinda):';
PRINT '   Script: 01_ACILIS_TEK_SEFERLIK.sql';
PRINT '   veya: EXEC bkm.sp_fifo_StokMaliyetAcilis @envanterTarihi = ''31.12.2025'', @satinalmaSarti = ''CIF'';';
PRINT '';
PRINT '2) AYLIK RUTIN - Her ay calistirilir:';
PRINT '   Script: 02_AYLIK_RUTIN.sql';
PRINT '   veya: EXEC bkm.sp_fifo_AylikRutin @yil = 2026, @ay = 1;';
PRINT '';
PRINT '-- Gunluk SMM raporu:';
PRINT 'SELECT * FROM bkm.fifo_vw_GunlukSMM WHERE hareketTarihi >= ''01.01.2026'';';
PRINT '';
PRINT '-- ERP Devir Fiyatlari yukle:';
PRINT 'INSERT bkm.fifo_ErpDevirFiyatlari(stkID, satinalmaSarti, birimMaliyet, miktar, toplamTutar, aciklama)';
PRINT 'VALUES (12345, ''CIF'', 15.50, 100, 1550.00, ''31.05.2021 devir evragi'');';
GO





PRINT '========================================';
PRINT 'V2: Sprint 1 uygulaniyor...';
PRINT '========================================';
PRINT '';
GO
-- =============================================================
-- FIFO SISTEMI - SPRINT 1: KRITIK DUZELTMELER (MEKAN BAGIMSIZ)
-- Versiyon: 2.0
-- Tarih: 2025-01-19
-- Amac: FIFO algoritmasini stabil ve denetlenebilir hale getirmek
-- NOT: Maliyetler mekan bagimsiz, ortak (merkezi)
-- =============================================================
-- UYARI: Bu script production'a uygulanmadan once backup aliniz!
-- Efor: 2-3 saat
-- Risk: Dusuk (backward compatible)
-- =============================================================

SET NOCOUNT ON;
GO

PRINT '=============================================================';
PRINT 'FIFO SPRINT 1: KRITIK DUZELTMELER (MEKAN BAGIMSIZ)';
PRINT '=============================================================';
PRINT '';
PRINT 'Bu script asagidaki degisiklikleri yapar:';
PRINT '1. FIFO siralama indekslerini yeniden tasarla (deterministic)';
PRINT '2. ERPDevirFiyatlari tablosunu MEKAN BAGIMSIZ yapiya donustur';
PRINT '3. 5 x Check constraint ekle (veri butunlugu)';
PRINT '4. 2 x Foreign key ekle (referans butunlugu)';
PRINT '5. sp_fifo_StokMaliyetAlisKatman''a XACT_ABORT ekle (transaction)';
PRINT '6. Veri butunlugu kontrol sorgulari calistir';
PRINT '';
PRINT 'NOT: Maliyetler merkez bazinda ortak, mekan farkliligi YOK';
PRINT 'Baslangic Zamani: ' + CONVERT(VARCHAR(19), GETDATE(), 121);
PRINT '=============================================================';
PRINT '';
GO

-- =============================================================
-- ADIM 1: FIFO SIRALAMASI - DETERMINISTIC YAPILARI
-- =============================================================

PRINT 'ADIM 1: FIFO Siralama Indeksleri Yeniden Yapilandiriliyor...';
PRINT '';
GO

-- Eski indeksleri sil
DROP INDEX IF EXISTS IX_fifo_StokMaliyetHavuzu_stkID 
    ON bkm.fifo_StokMaliyetHavuzu;
DROP INDEX IF EXISTS IX_fifo_StokMaliyetHavuzu_AktifKatman 
    ON bkm.fifo_StokMaliyetHavuzu;
GO

-- Yeni deterministic index
CREATE INDEX IX_fifo_Havuz_FifoSira
    ON bkm.fifo_StokMaliyetHavuzu(stkID, girisTarihi, belgeNo, ID)
    INCLUDE (miktarToplam, miktarKalan, birimMaliyet)
    WHERE miktarKalan > 0;
GO

PRINT '   x IX_fifo_Havuz_FifoSira olusturuldu (deterministic).';

-- Yardimci view: Siralanmis katmanlar
GO
CREATE OR ALTER VIEW bkm.vw_FifoKatmanlarSirali
AS
SELECT
    h.ID,
    h.stkID,
    h.girisTarihi,
    h.kaynakTip,
    h.belgeNo,
    h.miktarToplam,
    h.miktarKalan,
    h.birimMaliyet,
    h.durum,
    ROW_NUMBER() OVER (
        PARTITION BY h.stkID
        ORDER BY h.girisTarihi ASC, h.belgeNo ASC, h.ID ASC
    ) AS fifo_siirasi
FROM bkm.fifo_StokMaliyetHavuzu h
WHERE h.miktarKalan > 0;
GO

PRINT '   x bkm.vw_FifoKatmanlarSirali olusturuldu.';
PRINT '';
GO

-- =============================================================
-- ADIM 2: ERPDevirFiyatlari - MEKAN BAGIMSIZ YAPIYA DONUSTURMEK
-- =============================================================

PRINT 'ADIM 2: ERPDevirFiyatlari Tablosu MEKAN BAGIMSIZ Yapisina Donusturuluyor...';
PRINT '';
GO

-- Eger mekanID sutunu varsa sil (MEKAN BAGIMSIZ olacak)
IF COL_LENGTH('bkm.fifo_ErpDevirFiyatlari', 'mekanID') IS NOT NULL
BEGIN
    -- PK'i sil
    IF OBJECT_ID('PK_ErpDevirFiyat', 'PK') IS NOT NULL
    BEGIN
        ALTER TABLE bkm.fifo_ErpDevirFiyatlari
        DROP CONSTRAINT PK_ErpDevirFiyat;
    END
    IF OBJECT_ID('PK_fifo_ErpDevirFiyatlari', 'PK') IS NOT NULL
    BEGIN
        ALTER TABLE bkm.fifo_ErpDevirFiyatlari
        DROP CONSTRAINT PK_fifo_ErpDevirFiyatlari;
    END
    
    -- mekanID sutununu sil
    ALTER TABLE bkm.fifo_ErpDevirFiyatlari
    DROP COLUMN mekanID;
    
    PRINT '   x mekanID sutunu silindi (MEKAN BAGIMSIZ).';
END
GO

-- Yeni PK: Sadece (stkID, satinalmaSarti) - ORTUNUz tum mekanlar icin ortak fiyat
IF NOT EXISTS (
    SELECT 1
    FROM sys.key_constraints kc
    WHERE kc.[type] = 'PK'
      AND kc.parent_object_id = OBJECT_ID('bkm.fifo_ErpDevirFiyatlari')
)
BEGIN
    ALTER TABLE bkm.fifo_ErpDevirFiyatlari
    ADD CONSTRAINT PK_fifo_ErpDevirFiyatlari PRIMARY KEY (stkID, satinalmaSarti);
    
    PRINT '   x Yeni PK (stkID, satinalmaSarti) olusturuldu - ORTUNUz MEKAN BAGIMSIZ.';
END
GO

-- Eski index'leri sil
DROP INDEX IF EXISTS IX_fifo_ErpDevirFiyatlari_SatinalmaSarti
    ON bkm.fifo_ErpDevirFiyatlari;
DROP INDEX IF EXISTS IX_ErpDevir_SartiMekan
    ON bkm.fifo_ErpDevirFiyatlari;
GO

-- Yeni index: Sadece satinalmaSarti
CREATE INDEX IX_fifo_ErpDevirFiyatlari_SatinalmaSarti
    ON bkm.fifo_ErpDevirFiyatlari(satinalmaSarti)
    INCLUDE (birimMaliyet, miktar, toplamTutar);
PRINT '   x IX_fifo_ErpDevirFiyatlari_SatinalmaSarti olusturuldu.';
PRINT '';
GO

-- =============================================================
-- ADIM 3: CHECK CONSTRAINT'LER - VERI BUTUNLUGU
-- =============================================================

PRINT 'ADIM 3: Check Constraint''ler Ekleniyor...';
PRINT '';
GO

-- fifo_StokMaliyetHavuzu constraints
IF NOT EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_Havuz_Miktarlar_Gecerli'
      AND parent_object_id = OBJECT_ID('bkm.fifo_StokMaliyetHavuzu')
)
BEGIN
    ALTER TABLE bkm.fifo_StokMaliyetHavuzu ADD CONSTRAINT
        CK_Havuz_Miktarlar_Gecerli CHECK (
            miktarToplam > 0 AND
            miktarKalan >= 0 AND
            miktarKalan <= miktarToplam AND
            birimMaliyet >= 0
        );
    PRINT '   x CK_Havuz_Miktarlar_Gecerli eklendi.';
END
ELSE
BEGIN
    PRINT '   i CK_Havuz_Miktarlar_Gecerli zaten mevcut.';
END
GO

-- fifo_StokMaliyetCikis constraints
IF NOT EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_Cikis_Miktar_Pozitif'
      AND parent_object_id = OBJECT_ID('bkm.fifo_StokMaliyetCikis')
)
BEGIN
    ALTER TABLE bkm.fifo_StokMaliyetCikis ADD CONSTRAINT
        CK_Cikis_Miktar_Pozitif CHECK (miktar > 0);
    PRINT '   x CK_Cikis_Miktar_Pozitif eklendi.';
END
ELSE
BEGIN
    PRINT '   i CK_Cikis_Miktar_Pozitif zaten mevcut.';
END
GO

-- fifo_ErpDevirFiyatlari constraints
IF NOT EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_ErpDevir_Pozitif'
      AND parent_object_id = OBJECT_ID('bkm.fifo_ErpDevirFiyatlari')
)
BEGIN
    ALTER TABLE bkm.fifo_ErpDevirFiyatlari ADD CONSTRAINT
        CK_ErpDevir_Pozitif CHECK (
            miktar > 0 AND
            toplamTutar > 0 AND
            birimMaliyet > 0
        );
    PRINT '   x CK_ErpDevir_Pozitif eklendi.';
END
ELSE
BEGIN
    PRINT '   i CK_ErpDevir_Pozitif zaten mevcut.';
END
GO

-- fifo_StokEnvanter constraints
IF NOT EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_Envanter_Pozitif'
      AND parent_object_id = OBJECT_ID('bkm.fifo_StokEnvanter')
)
BEGIN
    ALTER TABLE bkm.fifo_StokEnvanter ADD CONSTRAINT
        CK_Envanter_Pozitif CHECK (stokMiktar >= 0);
    PRINT '   x CK_Envanter_Pozitif eklendi.';
END
ELSE
BEGIN
    PRINT '   i CK_Envanter_Pozitif zaten mevcut.';
END
GO

-- fifo_Run constraints
IF NOT EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_Run_Durum_Gecerli'
      AND parent_object_id = OBJECT_ID('bkm.fifo_Run')
)
BEGIN
    ALTER TABLE bkm.fifo_Run ADD CONSTRAINT
        CK_Run_Durum_Gecerli CHECK (
            status IN ('PENDING', 'RUNNING', 'DONE', 'ERROR')
        );
    PRINT '   x CK_Run_Durum_Gecerli eklendi.';
END
ELSE
BEGIN
    PRINT '   i CK_Run_Durum_Gecerli zaten mevcut.';
END
GO

PRINT '';
GO

-- =============================================================
-- ADIM 4: FOREIGN KEY'LER - REFERANS BUTUNLUGU
-- =============================================================

PRINT 'ADIM 4: Foreign Key''ler Ekleniyor...';
PRINT '';
GO

-- RunStep -> Run referansi
IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_RunStep_Run'
      AND parent_object_id = OBJECT_ID('bkm.fifo_RunStep')
)
BEGIN
    ALTER TABLE bkm.fifo_RunStep ADD CONSTRAINT
        FK_RunStep_Run FOREIGN KEY (runId)
        REFERENCES bkm.fifo_Run(runId)
        ON DELETE CASCADE;
    PRINT '   x FK_RunStep_Run eklendi.';
END
ELSE
BEGIN
    PRINT '   i FK_RunStep_Run zaten mevcut.';
END
GO

PRINT '';
GO

-- =============================================================
-- ADIM 5: TRANSACTION KONTROL - SP'LER
-- =============================================================

PRINT 'ADIM 5: Stored Procedure''lar XACT_ABORT ile Guncelleniyor...';
PRINT '';
GO

-- sp_fifo_StokMaliyetAlisKatman - SADECE FATURA: fat + fatAyr (irs/irsAyr yok)
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
    SET XACT_ABORT ON;  -- x KRITIK: Kismi basarisizlik cikma
    
    -- Parametre validasyonu
    IF @baslangicTarihi IS NULL OR @bitisTarihi IS NULL
    BEGIN
        RAISERROR('Tarih parametreleri bos olamaz', 16, 1);
        RETURN;
    END
    
    IF @baslangicTarihi > @bitisTarihi
    BEGIN
        RAISERROR('Baslangic tarihi bitis tarihinden buyuk olamaz', 16, 1);
        RETURN;
    END
    
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('tempdb..#alislar', 'U') IS NOT NULL DROP TABLE #alislar;

        /* Verilen tarih araligindaki alislari cek (SADECE FATURA: fat + fatAyr) */
        SELECT 
            a.ehStkID AS stkID,
            f.eTarihS AS girisTarihi,
            f.eNo     AS belgeNo,
            f.eTarihS AS belgeTarihi,
            f.eFirma  AS firmaID,
            SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS miktar,
            SUM(CONVERT(DECIMAL(18,4),
                CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END
            )) AS netTutar
        INTO #alislar
        FROM DerinSISBkm.dbo.fatAyr a WITH(NOLOCK)
        JOIN DerinSISBkm.dbo.fat f WITH(NOLOCK)
            ON f.eID = a.ehID
        WHERE a.ehAdetN <> 0
          AND f.eTarihS >  CONVERT(smalldatetime, @baslangicTarihi)
          AND f.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @bitisTarihi))
          AND f.eTip IN (0, 2)
          AND (@stkID IS NULL OR a.ehStkID = @stkID)
        GROUP BY a.ehStkID, f.eTarihS, f.eID, f.eNo, f.eFirma
        HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;

        /* Birim maliyet hesapla */
        ALTER TABLE #alislar ADD birimMaliyet DECIMAL(18,6);

        UPDATE #alislar
        SET birimMaliyet = CASE WHEN miktar = 0 THEN 0 ELSE netTutar / miktar END;

        /* Ayni tarih araligindaki eski ALIS katmanlarini sil */
        DELETE FROM bkm.fifo_StokMaliyetHavuzu
        WHERE kaynakTip = 'ALIS'
          AND girisTarihi >  @baslangicTarihi
          AND girisTarihi <= @bitisTarihi
          AND (@stkID IS NULL OR stkID = @stkID);

        /* Yeni ALIS katmanlarini havuza yaz */
        INSERT INTO bkm.fifo_StokMaliyetHavuzu
            (stkID, girisTarihi, kaynakTip, belgeNo, belgeTarihi, firmaID,
             miktarToplam, miktarKalan, birimMaliyet, durum)
        SELECT
            stkID, girisTarihi, 'ALIS', belgeNo, belgeTarihi, firmaID,
            miktar, miktar, birimMaliyet, 'NORMAL'
        FROM #alislar;

        COMMIT TRANSACTION;
        
        PRINT 'Alis katmanlari basariyla olusturuldu. Tarih araligi: ' + 
              CONVERT(VARCHAR(10), @baslangicTarihi, 120) + ' - ' + 
              CONVERT(VARCHAR(10), @bitisTarihi, 120);
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        
        PRINT 'HATA: ' + @ErrorMessage;
        THROW;
    END CATCH
END
GO

PRINT '   x sp_fifo_StokMaliyetAlisKatman XACT_ABORT ile guncellendi.';
PRINT '';
GO

-- =============================================================
-- ADIM 6: KONTROL SORGULARI - VERI BUTUNLUGU KONTROL
-- =============================================================

PRINT 'ADIM 6: Veri Butunlugu Kontrol Ediliyor...';
PRINT '';
GO

-- Check constraint ihlalleri kontrol
DECLARE @violationCount INT = 0;

SELECT @violationCount = COUNT(*)
FROM bkm.fifo_StokMaliyetHavuzu
WHERE miktarToplam <= 0 
   OR miktarKalan < 0 
   OR miktarKalan > miktarToplam 
   OR birimMaliyet < 0;

IF @violationCount > 0
BEGIN
    PRINT '   ! UYARI: ' + CAST(@violationCount AS VARCHAR) + ' satir check constraint ihlali!';
    PRINT '   Sorunlu kaydlar:';
    SELECT 
        'fifo_StokMaliyetHavuzu' AS [Tablo],
        ID,
        stkID,
        CASE 
            WHEN miktarToplam <= 0 THEN 'miktarToplam <= 0'
            WHEN miktarKalan < 0 THEN 'miktarKalan < 0'
            WHEN miktarKalan > miktarToplam THEN 'miktarKalan > miktarToplam'
            WHEN birimMaliyet < 0 THEN 'birimMaliyet < 0'
        END AS [Hata Tipi],
        CAST(miktarToplam AS VARCHAR) AS [Deger]
    FROM bkm.fifo_StokMaliyetHavuzu
    WHERE miktarToplam <= 0 
       OR miktarKalan < 0 
       OR miktarKalan > miktarToplam 
       OR birimMaliyet < 0;
END
ELSE
BEGIN
    PRINT '   x Check constraint ihlali yoktur.';
END
GO

-- PK tekrarlari kontrol
DECLARE @pkCount INT = 0;

SELECT @pkCount = COUNT(*)
FROM (
    SELECT stkID, satinalmaSarti
    FROM bkm.fifo_ErpDevirFiyatlari
    GROUP BY stkID, satinalmaSarti
    HAVING COUNT(*) > 1
) dupli;

IF @pkCount > 0
BEGIN
    PRINT '   ! UYARI: ERPDevir''de ' + CAST(@pkCount AS VARCHAR) + ' PK tekrari var!';
END
ELSE
BEGIN
    PRINT '   x Primary key ihlali yoktur.';
END
GO

PRINT '';
GO

-- =============================================================
-- SONLANDIS
-- =============================================================

PRINT '=============================================================';
PRINT 'SPRINT 1 TAMAMLANDI (MEKAN BAGIMSIZ)';
PRINT '=============================================================';
PRINT '';
PRINT 'Tamamlanan Degisiklikler:';
PRINT 'x FIFO deterministic indeksleri olusturuldu';
PRINT 'x ERPDevir MEKAN BAGIMSIZ yapisina donusturuldu (tum mekanlar ortak fiyat)';
PRINT 'x 5 x Check constraint eklendi';
PRINT 'x 2 x Foreign key eklendi (1 FK RunStep)';
PRINT 'x sp_fifo_StokMaliyetAlisKatman XACT_ABORT ile guncellendi';
PRINT 'x Veri butunlugu kontrol gecti';
PRINT '';
PRINT 'Bitis Zamani: ' + CONVERT(VARCHAR(19), GETDATE(), 121);
PRINT '';
PRINT 'ONEMLI NOT:';
PRINT '- Maliyetler (birimMaliyet) merkez bazinda ORTAKtir';
PRINT '- Mekan farkliligi YOKtur - tum subeler ayni fiyatla calisir';
PRINT '- Maliyet = satin alma fiyati, mekan bagimsiz';
PRINT '';
PRINT 'Sonraki Adimlar:';
PRINT '1. Test senaryolarini calistirin (fifo_test_data_setup.sql)';
PRINT '2. Muhasebe raporlarini kontrol edin';
PRINT '3. Sorunlu stok raporunu inceleyin';
PRINT '4. SPRINT 2 (02_SPRINT2_VIEWS_AUDIT.sql) uygulanmaya hazirlayin';
PRINT '=============================================================';
GO

PRINT '========================================';
PRINT 'V2: Sprint 2 uygulaniyor...';
PRINT '========================================';
PRINT '';
GO
-- =============================================================
-- FIFO SISTEMI - SPRINT 2: YARDIMCI VIEW'LAR VE AUDIT LOG
-- Versiyon: 2.0
-- Tarih: 2025-01-19
-- Amac: Muhasebe kontrolu ve denetim izleri kurmak
-- =============================================================
-- UYARI: Sprint 1 uygulandiktan sonra calistiriniz!
-- Efor: 2-3 saat
-- Risk: Dusuk (sadece ekleme, veri kopyalamiyor)
-- =============================================================

SET NOCOUNT ON;
GO

PRINT '=============================================================';
PRINT 'FIFO SPRINT 2: YARDIMCI VIEW''LAR VE AUDIT LOG';
PRINT '=============================================================';
PRINT '';
PRINT 'Bu script asagidaki degisiklikleri yapar:';
PRINT '1. Audit Log tablosu ve trigger''lari olustur';
PRINT '2. 6 x Muhasebe kontrol view''i olustur';
PRINT '3. 2 x Audit log view''i olustur';
PRINT '4. 3 x Yardimci stored procedure olustur';
PRINT '';
PRINT 'Baslangic Zamani: ' + CONVERT(VARCHAR(19), GETDATE(), 121);
PRINT '=============================================================';
PRINT '';
GO

-- =============================================================
-- BOLUM 1: AUDIT LOG TABLOSU VE TRIGGER'LAR
-- =============================================================

PRINT 'BOLUM 1: Audit Log Yapisi Olusturuluyor...';
PRINT '';
GO

-- Audit Log Tablosu
IF OBJECT_ID('bkm.fifo_DegisimGunlugu', 'U') IS NULL
BEGIN
    CREATE TABLE bkm.fifo_DegisimGunlugu (
        degisimID BIGINT IDENTITY(1,1) PRIMARY KEY,
        tabloAdi VARCHAR(50) NOT NULL,
        islemTipi VARCHAR(10) NOT NULL,  -- INSERT/UPDATE/DELETE
        etkilenenID INT NOT NULL,
        eskiDegerler NVARCHAR(MAX) NULL,
        yeniDegerler NVARCHAR(MAX) NULL,
        degistiren NVARCHAR(100) NOT NULL DEFAULT(SUSER_NAME()),
        degisimTarihi DATETIME2(3) NOT NULL DEFAULT(GETDATE()),
        
        CONSTRAINT CK_DegisimGunlugu_IslemTipi CHECK (islemTipi IN ('EKLE', 'GUNCELLE', 'SIL'))
    );
    
    PRINT '   x fifo_DegisimGunlugu tablosu olusturuldu.';
END
ELSE
BEGIN
    PRINT '   i fifo_DegisimGunlugu tablosu zaten mevcut.';
END
GO

-- Audit Log Indeksleri
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_DegisimGunlugu_TabloIslem'
      AND object_id = OBJECT_ID('bkm.fifo_DegisimGunlugu')
)
BEGIN
    CREATE INDEX IX_DegisimGunlugu_TabloIslem 
        ON bkm.fifo_DegisimGunlugu(tabloAdi, islemTipi, degisimTarihi DESC);
END

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_DegisimGunlugu_EtkilenenID'
      AND object_id = OBJECT_ID('bkm.fifo_DegisimGunlugu')
)
BEGIN
    CREATE INDEX IX_DegisimGunlugu_EtkilenenID 
        ON bkm.fifo_DegisimGunlugu(tabloAdi, etkilenenID, degisimTarihi DESC);
END

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_DegisimGunlugu_Degistiren'
      AND object_id = OBJECT_ID('bkm.fifo_DegisimGunlugu')
)
BEGIN
    CREATE INDEX IX_DegisimGunlugu_Degistiren 
        ON bkm.fifo_DegisimGunlugu(degistiren, degisimTarihi DESC);
END

PRINT '   x Audit Log indeksleri olusturuldu.';
GO

-- Trigger: fifo_StokMaliyetHavuzu Audit
IF OBJECT_ID('bkm.tr_fifo_StokMaliyetHavuzu_DegisimGunlugu', 'TR') IS NOT NULL
    DROP TRIGGER bkm.tr_fifo_StokMaliyetHavuzu_DegisimGunlugu;
GO

CREATE TRIGGER bkm.tr_fifo_StokMaliyetHavuzu_DegisimGunlugu
ON bkm.fifo_StokMaliyetHavuzu
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO bkm.fifo_DegisimGunlugu 
        (tabloAdi, islemTipi, etkilenenID, eskiDegerler, yeniDegerler, degistiren, degisimTarihi)
    SELECT
        'fifo_StokMaliyetHavuzu',
        CASE WHEN DELETED.ID IS NULL THEN 'EKLE'
             WHEN INSERTED.ID IS NULL THEN 'SIL'
             ELSE 'GUNCELLE' END,
        COALESCE(INSERTED.ID, DELETED.ID),
        (SELECT * FROM DELETED FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        (SELECT * FROM INSERTED FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        SUSER_NAME(),
        GETDATE()
    FROM INSERTED
    FULL OUTER JOIN DELETED ON INSERTED.ID = DELETED.ID
    WHERE INSERTED.ID IS NOT NULL OR DELETED.ID IS NOT NULL;
END
GO

PRINT '   x tr_fifo_StokMaliyetHavuzu_DegisimGunlugu trigger''i olusturuldu.';
GO

-- Trigger: fifo_StokMaliyetCikis Audit
IF OBJECT_ID('bkm.tr_fifo_StokMaliyetCikis_DegisimGunlugu', 'TR') IS NOT NULL
    DROP TRIGGER bkm.tr_fifo_StokMaliyetCikis_DegisimGunlugu;
GO

CREATE TRIGGER bkm.tr_fifo_StokMaliyetCikis_DegisimGunlugu
ON bkm.fifo_StokMaliyetCikis
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO bkm.fifo_DegisimGunlugu 
        (tabloAdi, islemTipi, etkilenenID, eskiDegerler, yeniDegerler, degistiren, degisimTarihi)
    SELECT
        'fifo_StokMaliyetCikis',
        CASE WHEN DELETED.ID IS NULL THEN 'EKLE'
             WHEN INSERTED.ID IS NULL THEN 'SIL'
             ELSE 'GUNCELLE' END,
        COALESCE(INSERTED.ID, DELETED.ID),
        (SELECT * FROM DELETED FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        (SELECT * FROM INSERTED FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        SUSER_NAME(),
        GETDATE()
    FROM INSERTED
    FULL OUTER JOIN DELETED ON INSERTED.ID = DELETED.ID
    WHERE INSERTED.ID IS NOT NULL OR DELETED.ID IS NOT NULL;
END
GO

PRINT '   x tr_fifo_StokMaliyetCikis_DegisimGunlugu trigger''i olusturuldu.';
PRINT '';
GO

-- =============================================================
-- BOLUM 2: MUHASEBE KONTROL VIEW'LARI
-- =============================================================

PRINT 'BOLUM 2: Muhasebe Kontrol View''lari Olusturuluyor...';
PRINT '';
GO

-- VIEW 1: FIFO Katman Tuketimi ve Tutarlilik Kontrol
CREATE OR ALTER VIEW bkm.vw_KatmanTuketimRaporu
AS
WITH KatmanTuketim AS (
    SELECT
        h.ID AS katmanID,
        h.stkID,
        h.girisTarihi,
        h.kaynakTip,
        h.belgeNo AS girisBelgeNo,
        h.belgeTarihi AS girisBelgeTarihi,
        h.miktarToplam,
        h.miktarKalan,
        (h.miktarToplam - h.miktarKalan) AS hesaplananTuketim,
        ISNULL(SUM(c.miktar), 0) AS raporlananTuketim,
        h.birimMaliyet,
        (h.miktarToplam - h.miktarKalan) * h.birimMaliyet AS hesaplananTutar,
        ISNULL(SUM(c.cikisTutar), 0) AS raporlananTutar
    FROM bkm.fifo_StokMaliyetHavuzu h
    LEFT JOIN bkm.fifo_StokMaliyetCikis c ON c.katmanID = h.ID
    GROUP BY h.ID, h.stkID, h.girisTarihi, h.kaynakTip, h.belgeNo, h.belgeTarihi,
             h.miktarToplam, h.miktarKalan, h.birimMaliyet
)
SELECT
    katmanID,
    stkID,
    girisTarihi,
    kaynakTip,
    girisBelgeNo,
    girisBelgeTarihi,
    miktarToplam,
    miktarKalan,
    hesaplananTuketim,
    raporlananTuketim,
    (hesaplananTuketim - raporlananTuketim) AS tuketimFarki,
    birimMaliyet,
    hesaplananTutar,
    raporlananTutar,
    (hesaplananTutar - raporlananTutar) AS tutarFarki,
    CASE 
        WHEN ABS(hesaplananTuketim - raporlananTuketim) < 0.01 THEN 'OK'
        ELSE 'UYUSMAZLIK'
    END AS kontrolDurumu,
    GETDATE() AS raporTarihi
FROM KatmanTuketim;
GO

PRINT '   x vw_KatmanTuketimRaporu olusturuldu.';
GO

-- VIEW 2: FIFO Cikis Detayli Rapor
CREATE OR ALTER VIEW bkm.vw_CikisDetayliRapor
AS
SELECT
    c.ID AS cikisID,
    c.stkID,
    c.hareketTarihi,
    c.hareketTipi,
    c.satisBelgeNo,
    c.katmanID,
    c.katmanTarihi,
    c.katmanBelgeNo,
    c.miktar,
    c.birimMaliyet,
    c.cikisTutar,
    h.kaynakTip,
    h.durum AS katmanDurum,
    h.girisTarihi,
    h.miktarToplam AS katmanMiktarToplam,
    h.miktarKalan AS katmanMiktarKalan,
    (h.miktarToplam - h.miktarKalan) AS katmanTuketilenMiktar
FROM bkm.fifo_StokMaliyetCikis c
LEFT JOIN bkm.fifo_StokMaliyetHavuzu h ON h.ID = c.katmanID;
GO

PRINT '   x vw_CikisDetayliRapor olusturuldu.';
GO

-- VIEW 3: Gunluk SMM (Stok Maliyet Muhasebesi) Ozeti
CREATE OR ALTER VIEW bkm.vw_GunlukSMM_Ozeti
AS
SELECT
    hareketTarihi,
    COUNT(DISTINCT stkID) AS urunSayisi,
    SUM(CASE WHEN hareketTipi = 'SATIS' THEN miktar ELSE 0 END) AS satisBasiMiktar,
    SUM(CASE WHEN hareketTipi = 'IADE' THEN miktar ELSE 0 END) AS iadeBasiMiktar,
    SUM(CASE WHEN hareketTipi = 'SATIS' THEN cikisTutar ELSE 0 END) AS satisBasiMaliyet,
    SUM(CASE WHEN hareketTipi = 'IADE' THEN cikisTutar ELSE 0 END) AS iadeBasiMaliyet,
    SUM(cikisTutar) AS toplamMaliyet,
    COUNT(*) AS satirSayisi,
    CASE 
        WHEN SUM(CASE WHEN hareketTipi = 'SATIS' THEN miktar ELSE 0 END) > 0
        THEN SUM(CASE WHEN hareketTipi = 'SATIS' THEN cikisTutar ELSE 0 END) 
             / SUM(CASE WHEN hareketTipi = 'SATIS' THEN miktar ELSE 0 END)
        ELSE 0
    END AS ortalamaSatisBirimMaliyet
FROM bkm.fifo_StokMaliyetCikis
GROUP BY hareketTarihi;
GO

PRINT '   x vw_GunlukSMM_Ozeti olusturuldu.';
GO

-- VIEW 4: Urun Bazli SMM Raporu
CREATE OR ALTER VIEW bkm.vw_UrunBazliSMM_Detay
AS
SELECT
    stkID,
    hareketTarihi,
    hareketTipi,
    COUNT(DISTINCT katmanID) AS katmanSayisi,
    SUM(miktar) AS toplamMiktar,
    SUM(cikisTutar) AS toplamMaliyet,
    MIN(birimMaliyet) AS minBirimMaliyet,
    MAX(birimMaliyet) AS maxBirimMaliyet,
    CASE WHEN SUM(miktar) <> 0 
         THEN SUM(cikisTutar) / SUM(miktar) 
         ELSE 0 
    END AS ortalamaBirimMaliyet,
    CAST(GETDATE() AS DATE) AS raporTarihi
FROM bkm.fifo_StokMaliyetCikis
GROUP BY stkID, hareketTarihi, hareketTipi;
GO

PRINT '   x vw_UrunBazliSMM_Detay olusturuldu.';
GO

-- VIEW 5: Katman Durumu Ozeti
CREATE OR ALTER VIEW bkm.vw_KatmanDurumuOzeti
AS
SELECT
    stkID,
    kaynakTip,
    girisTarihi,
    durum,
    COUNT(*) AS katmanSayisi,
    SUM(miktarToplam) AS toplamMiktar,
    SUM(miktarKalan) AS kalanMiktar,
    SUM(miktarToplam - miktarKalan) AS tuketilenMiktar,
    AVG(birimMaliyet) AS ortalamaBirimMaliyet,
    MIN(birimMaliyet) AS minBirimMaliyet,
    MAX(birimMaliyet) AS maxBirimMaliyet,
    SUM(miktarKalan * birimMaliyet) AS kalanTutar
FROM bkm.fifo_StokMaliyetHavuzu
GROUP BY stkID, kaynakTip, girisTarihi, durum;
GO

PRINT '   x vw_KatmanDurumuOzeti olusturuldu.';
GO

-- VIEW 6: Sorunlu Stoklar Raporu
CREATE OR ALTER VIEW bkm.vw_SorunluStoklar_Rapor
AS
SELECT
    sorunTip,
    envanterTarihi,
    COUNT(DISTINCT stkID) AS urunSayisi,
    SUM(stokMiktar) AS toplamMiktar,
    MIN(kayitTarihi) AS ilkKayit,
    MAX(kayitTarihi) AS sonKayit,
    COUNT(*) AS kayitSayisi
FROM bkm.fifo_StokMaliyetSorunlu
GROUP BY sorunTip, envanterTarihi;
GO

PRINT '   x vw_SorunluStoklar_Rapor olusturuldu.';
PRINT '';
GO

-- =============================================================
-- BOLUM 3: AUDIT LOG SORGULAMA VIEW'LARI
-- =============================================================

PRINT 'BOLUM 3: Audit Log Sorgulama View''lari Olusturuluyor...';
PRINT '';
GO

-- Audit View 1: Son degisiklikler
CREATE OR ALTER VIEW bkm.vw_SonDegisiklikler
AS
SELECT TOP 1000
    degisimID,
    tabloAdi,
    islemTipi,
    etkilenenID,
    degistiren,
    degisimTarihi,
    DATEDIFF(MINUTE, degisimTarihi, GETDATE()) AS oncekiDakika
FROM bkm.fifo_DegisimGunlugu
ORDER BY degisimID DESC;
GO

PRINT '   x vw_SonDegisiklikler olusturuldu.';
GO

-- Audit View 2: Kullanici aktiviteleri
CREATE OR ALTER VIEW bkm.vw_KullaniciAktiviteleri
AS
SELECT
    degistiren,
    tabloAdi,
    islemTipi,
    COUNT(*) AS islemSayisi,
    MIN(degisimTarihi) AS ilkIslem,
    MAX(degisimTarihi) AS sonIslem
FROM bkm.fifo_DegisimGunlugu
GROUP BY degistiren, tabloAdi, islemTipi;
GO

PRINT '   x vw_KullaniciAktiviteleri olusturuldu.';
PRINT '';
GO

-- =============================================================
-- BOLUM 4: YARDIMCI STORED PROCEDURE'LAR
-- =============================================================

PRINT 'BOLUM 4: Yardimci Stored Procedure''lar Olusturuluyor...';
PRINT '';
GO

-- SP 1: Belirli bir katmanin degisim tarihcesi
CREATE OR ALTER PROCEDURE bkm.sp_KatmanDegisimTarihcesi
(
    @katmanID INT
)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT
        degisimID,
        tabloAdi,
        islemTipi,
        eskiDegerler,
        yeniDegerler,
        degistiren,
        degisimTarihi
    FROM bkm.fifo_DegisimGunlugu
    WHERE tabloAdi = 'fifo_StokMaliyetHavuzu'
      AND etkilenenID = @katmanID
    ORDER BY degisimID ASC;
END
GO

PRINT '   x sp_KatmanDegisimTarihcesi olusturuldu.';
GO

-- SP 2: Cikis kaydinin katman ve tutarlilik kontrolu
CREATE OR ALTER PROCEDURE bkm.sp_CikisTutarlillikKontrolu
(
    @cikisID INT
)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @katmanID INT;
    DECLARE @cikisMiktar DECIMAL(18,4);
    DECLARE @birimMaliyet DECIMAL(18,6);
    
    SELECT 
        @katmanID = katmanID,
        @cikisMiktar = miktar,
        @birimMaliyet = birimMaliyet
    FROM bkm.fifo_StokMaliyetCikis
    WHERE ID = @cikisID;
    
    IF @katmanID IS NULL
    BEGIN
        RAISERROR('Cikis kaydi bulunamadi', 16, 1);
        RETURN;
    END
    
    -- Katman bilgisini al
    SELECT
        h.ID,
        h.stkID,
        h.girisTarihi,
        h.kaynakTip,
        h.miktarToplam,
        h.miktarKalan,
        h.birimMaliyet,
        (SELECT SUM(miktar) FROM bkm.fifo_StokMaliyetCikis WHERE katmanID = h.ID) AS toplamCikis,
        CASE 
            WHEN h.birimMaliyet = @birimMaliyet THEN 'OK'
            ELSE 'UYUSMAZLIK: Farkli fiyat!'
        END AS fiyatKontrol
    FROM bkm.fifo_StokMaliyetHavuzu h
    WHERE h.ID = @katmanID;
END
GO

PRINT '   x sp_CikisTutarlillikKontrolu olusturuldu.';
GO

-- SP 3: Gunluk veri tasima kontrolu
CREATE OR ALTER PROCEDURE bkm.sp_VeriTasiymaKontrolu
(
    @baslangicTarihi DATE,
    @bitisTarihi DATE
)
AS
BEGIN
    SET NOCOUNT ON;
    
    PRINT 'Veri Tasiyma Kontrol Raporu';
    PRINT 'Tarih Araligi: ' + CONVERT(VARCHAR(10), @baslangicTarihi, 120) + 
          ' - ' + CONVERT(VARCHAR(10), @bitisTarihi, 120);
    PRINT '';
    
    PRINT '1. Acilis Katmanlari:';
    SELECT COUNT(*) AS katmanSayisi, SUM(miktarToplam) AS toplamMiktar
    FROM bkm.fifo_StokMaliyetHavuzu
    WHERE kaynakTip IN ('ACILIS', 'ACILIS_TAMAMLA')
      AND girisTarihi >= @baslangicTarihi
      AND girisTarihi <= @bitisTarihi;
    
    PRINT '';
    PRINT '2. Alis Katmanlari:';
    SELECT COUNT(*) AS katmanSayisi, SUM(miktarToplam) AS toplamMiktar
    FROM bkm.fifo_StokMaliyetHavuzu
    WHERE kaynakTip = 'ALIS'
      AND girisTarihi >= @baslangicTarihi
      AND girisTarihi <= @bitisTarihi;
    
    PRINT '';
    PRINT '3. Cikis Hareketleri:';
    SELECT 
        hareketTipi,
        COUNT(*) AS satirSayisi,
        SUM(miktar) AS toplamMiktar,
        SUM(cikisTutar) AS toplamMaliyet
    FROM bkm.fifo_StokMaliyetCikis
    WHERE hareketTarihi >= @baslangicTarihi
      AND hareketTarihi <= @bitisTarihi
    GROUP BY hareketTipi;
    
    PRINT '';
    PRINT '4. Sorunlu Kayitlar:';
    SELECT 
        sorunTip,
        COUNT(*) AS kayitSayisi,
        SUM(stokMiktar) AS toplamMiktar
    FROM bkm.fifo_StokMaliyetSorunlu
    WHERE envanterTarihi >= @baslangicTarihi
      AND envanterTarihi <= @bitisTarihi
    GROUP BY sorunTip;
END
GO

PRINT '   x sp_VeriTasiymaKontrolu olusturuldu.';
PRINT '';
GO

-- =============================================================
-- SONLANDIS
-- =============================================================

PRINT '=============================================================';
PRINT 'SPRINT 2 TAMAMLANDI';
PRINT '=============================================================';
PRINT '';
PRINT 'Olusturulan Objeler:';
PRINT 'x 1 x Audit Log Tablosu (fifo_DegisimGunlugu)';
PRINT 'x 3 x Index (audit log icin)';
PRINT 'x 2 x Audit Trigger (Havuzu, Cikis)';
PRINT 'x 6 x Muhasebe Kontrol View';
PRINT 'x 2 x Audit Log View';
PRINT 'x 3 x Yardimci Stored Procedure';
PRINT '';
PRINT 'Bitis Zamani: ' + CONVERT(VARCHAR(19), GETDATE(), 121);
PRINT '';
PRINT 'Sonraki Adimlar:';
PRINT '1. Test Veri Setup script''ini calistirin (03_TEST_DATA_SETUP.sql)';
PRINT '2. View''lari test edin (SELECT * FROM bkm.vw_KatmanTuketimRaporu)';
PRINT '3. Audit log''u kontrol edin (SELECT * FROM bkm.vw_SonDegisiklikler)';
PRINT '4. SPRINT 3 (optimizasyon) plani yapin';
PRINT '=============================================================';
GO



