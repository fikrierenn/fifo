USE BKMMaliyet;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
GO

-- =============================================================
-- V2-04 + V2-05: Batch Orchestration - SQL Katmani
--
-- TVP tipi, observability tablolari ve batch SP'leri.
-- .NET Hangfire job bu SP'leri Dapper + TVP ile cagirır.
--
-- Sozlesme:
--   RunId     : Hangfire'in urettigi GUID (her aylık calisma = 1 run)
--   BatchNo   : 1-bazli batch sırası (1, 2, 3, ...)
--   BatchBoyutu: .NET tarafinda konfigüre edilir (default 500)
-- =============================================================

-- ============================================================
-- 1) TVP: StkId listesi .NET -> SQL aktarimi icin
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.types WHERE name = 'StkIdListType' AND is_table_type = 1)
BEGIN
    CREATE TYPE dbo.StkIdListType AS TABLE (StkId INT NOT NULL PRIMARY KEY);
    PRINT 'StkIdListType TVP olusturuldu';
END
ELSE
    PRINT 'StkIdListType TVP zaten var - atlanıyor';
GO

-- ============================================================
-- 2) Observability tablolari (idempotent)
-- ============================================================

-- 2a) Run ust seviye kayit
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'FifoBatchRun' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.FifoBatchRun
    (
        RunId            UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
        DonemYil         INT              NOT NULL,
        DonemAy          INT              NOT NULL,
        RunBaslangic     DATETIME2(0)     NOT NULL DEFAULT SYSDATETIME(),
        RunBitis         DATETIME2(0)     NULL,
        ToplamUrun       INT              NULL,
        ToplamBatch      INT              NULL,
        TamamlananBatch  INT              NOT NULL DEFAULT 0,
        BatchBoyutu      INT              NOT NULL DEFAULT 500,
        Durum            VARCHAR(20)      NOT NULL DEFAULT 'CALISIYOR',
        -- CALISIYOR | TAMAMLANDI | KISMEN_HATA | HATA
        HataMesaji       NVARCHAR(2000)   NULL,
        CONSTRAINT PK_FifoBatchRun PRIMARY KEY (RunId)
    );
    CREATE INDEX IX_FifoBatchRun_Donem ON dbo.FifoBatchRun(DonemYil, DonemAy, RunBaslangic DESC);
    PRINT 'FifoBatchRun tablosu olusturuldu';
END
ELSE
    PRINT 'FifoBatchRun tablosu zaten var - atlanıyor';
GO

-- 2b) Batch (alt birim) takibi
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'FifoBatchDetay' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.FifoBatchDetay
    (
        DetayId         INT IDENTITY(1,1) NOT NULL,
        RunId           UNIQUEIDENTIFIER  NOT NULL,
        BatchNo         INT               NOT NULL,
        UrunSayisi      INT               NOT NULL,
        BaslangicZamani DATETIME2(0)      NOT NULL DEFAULT SYSDATETIME(),
        BitisZamani     DATETIME2(0)      NULL,
        Durum           VARCHAR(20)       NOT NULL DEFAULT 'BEKLIYOR',
        -- BEKLIYOR | CALISIYOR | TAMAMLANDI | HATA
        BasariliUrun    INT               NULL,
        HataliUrun      INT               NULL,
        CONSTRAINT PK_FifoBatchDetay      PRIMARY KEY (DetayId),
        CONSTRAINT FK_FifoBatchDetay_Run  FOREIGN KEY (RunId) REFERENCES dbo.FifoBatchRun(RunId),
        CONSTRAINT UQ_FifoBatchDetay_RunBatch UNIQUE (RunId, BatchNo)
    );
    PRINT 'FifoBatchDetay tablosu olusturuldu';
END
ELSE
    PRINT 'FifoBatchDetay tablosu zaten var - atlanıyor';
GO

-- 2c) Urun bazli hata logu
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'FifoBatchHata' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.FifoBatchHata
    (
        HataId      INT IDENTITY(1,1) NOT NULL,
        RunId       UNIQUEIDENTIFIER  NULL,
        BatchNo     INT               NULL,
        StkId       INT               NOT NULL,
        HataMesaji  NVARCHAR(2000)    NOT NULL,
        HataZamani  DATETIME2(0)      NOT NULL DEFAULT SYSDATETIME(),
        CONSTRAINT PK_FifoBatchHata PRIMARY KEY (HataId)
    );
    CREATE INDEX IX_FifoBatchHata_RunId ON dbo.FifoBatchHata(RunId, BatchNo);
    PRINT 'FifoBatchHata tablosu olusturuldu';
END
ELSE
    PRINT 'FifoBatchHata tablosu zaten var - atlanıyor';
GO

-- ============================================================
-- 3) Yardimci SP: Run acma / kapama
-- ============================================================

CREATE OR ALTER PROCEDURE dbo.sp_Fifo_BatchRunBaslat
(
    @RunId       UNIQUEIDENTIFIER,
    @DonemYil    INT,
    @DonemAy     INT,
    @ToplamUrun  INT,
    @ToplamBatch INT,
    @BatchBoyutu INT = 500
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Ayni donemde CALISIYOR run varsa uyar (çakisma koruması)
    IF EXISTS (
        SELECT 1 FROM dbo.FifoBatchRun
        WHERE DonemYil = @DonemYil AND DonemAy = @DonemAy AND Durum = 'CALISIYOR'
    )
    BEGIN
        RAISERROR('Bu donem icin zaten calisan bir run var. Onceki run tamamlanmadan yeni run baslatılamaz.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.FifoBatchRun
        (RunId, DonemYil, DonemAy, ToplamUrun, ToplamBatch, BatchBoyutu, Durum)
    VALUES
        (@RunId, @DonemYil, @DonemAy, @ToplamUrun, @ToplamBatch, @BatchBoyutu, 'CALISIYOR');
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_Fifo_BatchRunBitir
(
    @RunId     UNIQUEIDENTIFIER,
    @Durum     VARCHAR(20),        -- TAMAMLANDI | KISMEN_HATA | HATA
    @HataMesaji NVARCHAR(2000) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.FifoBatchRun
    SET
        Durum            = @Durum,
        HataMesaji       = @HataMesaji,
        RunBitis         = SYSDATETIME(),
        TamamlananBatch  = (
            SELECT COUNT(*) FROM dbo.FifoBatchDetay
            WHERE RunId = @RunId AND Durum = 'TAMAMLANDI'
        )
    WHERE RunId = @RunId;
END
GO

PRINT 'sp_Fifo_BatchRunBaslat + sp_Fifo_BatchRunBitir olusturuldu';
GO

-- ============================================================
-- 4) Ana batch islemci: sp_Fifo_AylikCalistirBatch
--    TVP alır, urun basına sp_Fifo_AylikCalistir cagirir.
--    Urun hatasi tum batch'i durdurmaz - FifoBatchHata'ya yazar.
-- ============================================================

CREATE OR ALTER PROCEDURE dbo.sp_Fifo_AylikCalistirBatch
(
    @Yil       INT,
    @Ay        INT,
    @StkIdList dbo.StkIdListType READONLY,
    @RunId     UNIQUEIDENTIFIER = NULL,
    @BatchNo   INT              = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @Yil IS NULL OR @Ay IS NULL OR @Ay NOT BETWEEN 1 AND 12
    BEGIN
        RAISERROR('Gecersiz yil/ay parametresi.', 16, 1);
        RETURN;
    END

    DECLARE @StkId       INT;
    DECLARE @BasariliCount INT = 0;
    DECLARE @HataCount     INT = 0;
    DECLARE @UrunSayisi    INT = (SELECT COUNT(*) FROM @StkIdList);

    -- Batch baslangic logu
    IF @RunId IS NOT NULL AND @BatchNo IS NOT NULL
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM dbo.FifoBatchDetay WHERE RunId = @RunId AND BatchNo = @BatchNo)
            INSERT INTO dbo.FifoBatchDetay (RunId, BatchNo, UrunSayisi, Durum)
            VALUES (@RunId, @BatchNo, @UrunSayisi, 'CALISIYOR');
        ELSE
            UPDATE dbo.FifoBatchDetay
            SET Durum = 'CALISIYOR', BaslangicZamani = SYSDATETIME()
            WHERE RunId = @RunId AND BatchNo = @BatchNo;
    END

    -- Urun basina calistir
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT StkId FROM @StkIdList ORDER BY StkId;

    OPEN cur;
    FETCH NEXT FROM cur INTO @StkId;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            EXEC dbo.sp_Fifo_AylikCalistir
                @yil    = @Yil,
                @ay     = @Ay,
                @StkId  = @StkId,
                @IslemId = @RunId;

            SET @BasariliCount += 1;
        END TRY
        BEGIN CATCH
            SET @HataCount += 1;

            IF @RunId IS NOT NULL
                INSERT INTO dbo.FifoBatchHata (RunId, BatchNo, StkId, HataMesaji)
                VALUES (@RunId, @BatchNo, @StkId, LEFT(ERROR_MESSAGE(), 2000));
        END CATCH

        FETCH NEXT FROM cur INTO @StkId;
    END

    CLOSE cur;
    DEALLOCATE cur;

    -- Batch bitis logu
    IF @RunId IS NOT NULL AND @BatchNo IS NOT NULL
        UPDATE dbo.FifoBatchDetay
        SET
            Durum        = CASE WHEN @HataCount = 0 THEN 'TAMAMLANDI' ELSE 'KISMEN_HATA' END,
            BitisZamani  = SYSDATETIME(),
            BasariliUrun = @BasariliCount,
            HataliUrun   = @HataCount
        WHERE RunId = @RunId AND BatchNo = @BatchNo;

    -- Cagırana ozet donut
    SELECT
        @BasariliCount AS BasariliUrun,
        @HataCount     AS HataliUrun,
        @UrunSayisi    AS ToplamUrun;
END
GO

PRINT 'sp_Fifo_AylikCalistirBatch proseduru olusturuldu';
GO

-- ============================================================
-- 5) Kontrol view: son 20 run ozeti
-- ============================================================

CREATE OR ALTER VIEW dbo.vw_FifoBatchRunOzet AS
SELECT
    r.RunId,
    r.DonemYil,
    r.DonemAy,
    r.RunBaslangic,
    r.RunBitis,
    DATEDIFF(SECOND, r.RunBaslangic, ISNULL(r.RunBitis, SYSDATETIME())) AS SureSaniye,
    r.ToplamUrun,
    r.ToplamBatch,
    r.TamamlananBatch,
    r.BatchBoyutu,
    r.Durum,
    (SELECT COUNT(*) FROM dbo.FifoBatchHata h WHERE h.RunId = r.RunId) AS ToplamHataUrun,
    r.HataMesaji
FROM dbo.FifoBatchRun r;
GO

PRINT 'vw_FifoBatchRunOzet view olusturuldu';
GO
