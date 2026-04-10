-- 18_V2_DonemKontrol.sql
-- Donem kilidi, snapshot, cascade re-run ve degisim raporu altyapisi

-- =============================================================
-- 1) SNAPSHOT TABLOLARI
-- =============================================================

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'FifoDonemSnapshot' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.FifoDonemSnapshot (
        SnapshotId        INT IDENTITY(1,1) NOT NULL,
        RunId             UNIQUEIDENTIFIER  NOT NULL,
        DonemYil          INT               NOT NULL,
        DonemAy           INT               NOT NULL,
        SnapshotTarihi    DATETIME2(0)      NOT NULL DEFAULT GETDATE(),
        ToplamKatman      INT               NULL,
        ToplamKalanMiktar DECIMAL(18,4)     NULL,
        ToplamCikisMiktar DECIMAL(18,4)     NULL,
        ToplamCikisTutar  DECIMAL(18,4)     NULL,
        OrtBirimMaliyet   DECIMAL(18,6)     NULL,
        CONSTRAINT PK_FifoDonemSnapshot PRIMARY KEY (SnapshotId)
    );
    CREATE INDEX IX_FifoDonemSnapshot_Donem ON dbo.FifoDonemSnapshot (DonemYil, DonemAy, SnapshotTarihi DESC);
    PRINT 'FifoDonemSnapshot tablosu olusturuldu.';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'FifoDonemSnapshotDetay' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.FifoDonemSnapshotDetay (
        DetayId           BIGINT IDENTITY(1,1) NOT NULL,
        SnapshotId        INT               NOT NULL,
        StkId             INT               NOT NULL,
        KatmanSayisi      INT               NOT NULL DEFAULT 0,
        ToplamKalan       DECIMAL(18,4)     NOT NULL DEFAULT 0,
        AgirlikliMaliyet  DECIMAL(18,6)     NOT NULL DEFAULT 0,
        CikisMiktar       DECIMAL(18,4)     NOT NULL DEFAULT 0,
        CikisTutar        DECIMAL(18,4)     NOT NULL DEFAULT 0,
        CONSTRAINT PK_FifoDonemSnapshotDetay PRIMARY KEY (DetayId),
        CONSTRAINT FK_FifoDonemSnapshotDetay_Snapshot FOREIGN KEY (SnapshotId)
            REFERENCES dbo.FifoDonemSnapshot(SnapshotId)
    );
    CREATE INDEX IX_FifoDonemSnapshotDetay_Snap ON dbo.FifoDonemSnapshotDetay (SnapshotId, StkId);
    PRINT 'FifoDonemSnapshotDetay tablosu olusturuldu.';
END
GO

-- =============================================================
-- 2) sp_Fifo_DonemKontrol — Sonraki donemleri kontrol et
-- =============================================================
CREATE OR ALTER PROCEDURE dbo.sp_Fifo_DonemKontrol
    @Yil INT,
    @Ay  INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Sonraki aylarda veri var mi?
    DECLARE @sonrakiBaslangic DATE = DATEADD(MONTH, 1, DATEFROMPARTS(@Yil, @Ay, 1));

    -- FifoKatman'da sonraki aylardan ALIS katmani var mi
    SELECT DISTINCT
        YEAR(k.GirisTarihi) AS DonemYil,
        MONTH(k.GirisTarihi) AS DonemAy,
        YEAR(k.GirisTarihi) * 100 + MONTH(k.GirisTarihi) AS YilAy,
        'KATMAN' AS Kaynak,
        COUNT(*) AS KayitSayisi
    INTO #sonraki
    FROM dbo.FifoKatman k
    WHERE k.KaynakTip = 'ALIS'
      AND k.GirisTarihi >= @sonrakiBaslangic
    GROUP BY YEAR(k.GirisTarihi), MONTH(k.GirisTarihi);

    -- FifoCikisDetay'da sonraki aylardan cikis var mi
    INSERT INTO #sonraki (DonemYil, DonemAy, YilAy, Kaynak, KayitSayisi)
    SELECT DISTINCT
        YEAR(c.HareketTarihi), MONTH(c.HareketTarihi),
        YEAR(c.HareketTarihi) * 100 + MONTH(c.HareketTarihi),
        'CIKIS', COUNT(*)
    FROM dbo.FifoCikisDetay c
    WHERE c.HareketTarihi >= @sonrakiBaslangic
    GROUP BY YEAR(c.HareketTarihi), MONTH(c.HareketTarihi);

    -- OrtalamaAylikMaliyet'te sonraki ay var mi
    DECLARE @sonrakiYilAy INT = (@Yil * 100 + @Ay) + 1;
    IF @Ay = 12 SET @sonrakiYilAy = (@Yil + 1) * 100 + 1;

    INSERT INTO #sonraki (DonemYil, DonemAy, YilAy, Kaynak, KayitSayisi)
    SELECT
        o.YilAy / 100, o.YilAy % 100, o.YilAy, 'ORTALAMA', COUNT(*)
    FROM dbo.OrtalamaAylikMaliyet o
    WHERE o.YilAy >= @sonrakiYilAy
    GROUP BY o.YilAy;

    -- Sonuc: benzersiz donemler + toplam kayit
    SELECT
        YilAy,
        DonemYil,
        DonemAy,
        SUM(KayitSayisi) AS ToplamKayit,
        STRING_AGG(Kaynak + ':' + CAST(KayitSayisi AS VARCHAR), ', ') AS Detay
    FROM #sonraki
    GROUP BY YilAy, DonemYil, DonemAy
    ORDER BY YilAy;

    DROP TABLE #sonraki;
END
GO
PRINT 'sp_Fifo_DonemKontrol olusturuldu.';
GO

-- =============================================================
-- 3) sp_Fifo_DonemSnapshotAl — Mevcut durumu snapshot'a kaydet
-- =============================================================
CREATE OR ALTER PROCEDURE dbo.sp_Fifo_DonemSnapshotAl
    @Yil   INT,
    @Ay    INT,
    @RunId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @donemBaslangic DATE = DATEFROMPARTS(@Yil, @Ay, 1);
    DECLARE @donemBitis     DATE = EOMONTH(@donemBaslangic);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1) Ozet hesapla
        DECLARE @toplamKatman INT, @toplamKalan DECIMAL(18,4),
                @toplamCikisMiktar DECIMAL(18,4), @toplamCikisTutar DECIMAL(18,4),
                @ortMaliyet DECIMAL(18,6);

        SELECT
            @toplamKatman = COUNT(*),
            @toplamKalan  = ISNULL(SUM(k.KalanMiktar), 0),
            @ortMaliyet   = CASE WHEN SUM(k.KalanMiktar) = 0 THEN 0
                                 ELSE SUM(k.KalanMiktar * k.BirimMaliyet) / SUM(k.KalanMiktar)
                            END
        FROM dbo.FifoKatman k
        WHERE k.GirisTarihi <= @donemBitis;

        SELECT
            @toplamCikisMiktar = ISNULL(SUM(c.Miktar), 0),
            @toplamCikisTutar  = ISNULL(SUM(c.CikisTutar), 0)
        FROM dbo.FifoCikisDetay c
        WHERE c.HareketTarihi BETWEEN @donemBaslangic AND @donemBitis;

        -- 2) Snapshot baslik
        DECLARE @snapshotId INT;
        INSERT INTO dbo.FifoDonemSnapshot
            (RunId, DonemYil, DonemAy, ToplamKatman, ToplamKalanMiktar,
             ToplamCikisMiktar, ToplamCikisTutar, OrtBirimMaliyet)
        VALUES
            (@RunId, @Yil, @Ay, @toplamKatman, @toplamKalan,
             @toplamCikisMiktar, @toplamCikisTutar, @ortMaliyet);

        SET @snapshotId = SCOPE_IDENTITY();

        -- 3) Urun bazli detay
        INSERT INTO dbo.FifoDonemSnapshotDetay
            (SnapshotId, StkId, KatmanSayisi, ToplamKalan, AgirlikliMaliyet, CikisMiktar, CikisTutar)
        SELECT
            @snapshotId,
            x.StkId,
            x.KatmanSayisi,
            x.ToplamKalan,
            x.AgirlikliMaliyet,
            ISNULL(c.CikisMiktar, 0),
            ISNULL(c.CikisTutar, 0)
        FROM (
            SELECT
                k.StkId,
                COUNT(*) AS KatmanSayisi,
                SUM(k.KalanMiktar) AS ToplamKalan,
                CASE WHEN SUM(k.KalanMiktar) = 0 THEN 0
                     ELSE SUM(k.KalanMiktar * k.BirimMaliyet) / SUM(k.KalanMiktar)
                END AS AgirlikliMaliyet
            FROM dbo.FifoKatman k
            WHERE k.GirisTarihi <= @donemBitis
            GROUP BY k.StkId
        ) x
        LEFT JOIN (
            SELECT
                c2.StkId,
                SUM(c2.Miktar) AS CikisMiktar,
                SUM(c2.CikisTutar) AS CikisTutar
            FROM dbo.FifoCikisDetay c2
            WHERE c2.HareketTarihi BETWEEN @donemBaslangic AND @donemBitis
            GROUP BY c2.StkId
        ) c ON c.StkId = x.StkId;

        COMMIT TRANSACTION;

        SELECT @snapshotId AS SnapshotId;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @err NVARCHAR(2000) = LEFT(ERROR_MESSAGE(), 2000);
        RAISERROR(@err, 16, 1);
    END CATCH
END
GO
PRINT 'sp_Fifo_DonemSnapshotAl olusturuldu.';
GO

-- =============================================================
-- 4) vw_Fifo_DonemDegisim — Snapshot vs mevcut karsilastirma
-- =============================================================
CREATE OR ALTER VIEW dbo.vw_Fifo_DonemDegisim
AS
SELECT
    s.SnapshotId,
    s.RunId,
    s.DonemYil,
    s.DonemAy,
    s.SnapshotTarihi,
    d.StkId,
    -- Onceki (snapshot)
    d.KatmanSayisi   AS OncekiKatmanSayisi,
    d.ToplamKalan    AS OncekiKalan,
    d.AgirlikliMaliyet AS OncekiMaliyet,
    d.CikisMiktar    AS OncekiCikisMiktar,
    d.CikisTutar     AS OncekiCikisTutar,
    -- Mevcut
    ISNULL(m.KatmanSayisi, 0) AS MevcutKatmanSayisi,
    ISNULL(m.ToplamKalan, 0)  AS MevcutKalan,
    ISNULL(m.AgirlikliMaliyet, 0) AS MevcutMaliyet,
    ISNULL(c.CikisMiktar, 0) AS MevcutCikisMiktar,
    ISNULL(c.CikisTutar, 0)  AS MevcutCikisTutar,
    -- Farklar
    ISNULL(m.AgirlikliMaliyet, 0) - d.AgirlikliMaliyet AS MaliyetFark,
    CASE WHEN d.AgirlikliMaliyet = 0 THEN 0
         ELSE (ISNULL(m.AgirlikliMaliyet, 0) - d.AgirlikliMaliyet) / d.AgirlikliMaliyet * 100
    END AS MaliyetFarkYuzde,
    ISNULL(c.CikisTutar, 0) - d.CikisTutar AS CikisTutarFark
FROM dbo.FifoDonemSnapshot s
JOIN dbo.FifoDonemSnapshotDetay d ON d.SnapshotId = s.SnapshotId
LEFT JOIN (
    SELECT
        k.StkId,
        COUNT(*) AS KatmanSayisi,
        SUM(k.KalanMiktar) AS ToplamKalan,
        CASE WHEN SUM(k.KalanMiktar) = 0 THEN 0
             ELSE SUM(k.KalanMiktar * k.BirimMaliyet) / SUM(k.KalanMiktar)
        END AS AgirlikliMaliyet
    FROM dbo.FifoKatman k
    GROUP BY k.StkId
) m ON m.StkId = d.StkId
LEFT JOIN (
    SELECT
        c2.StkId,
        SUM(c2.Miktar) AS CikisMiktar,
        SUM(c2.CikisTutar) AS CikisTutar
    FROM dbo.FifoCikisDetay c2
    GROUP BY c2.StkId
) c ON c.StkId = d.StkId;
GO
PRINT 'vw_Fifo_DonemDegisim olusturuldu.';
