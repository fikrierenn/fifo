/* ============================================================================
   00_V2_MASTER_FULL.sql — BKMMaliyet FIFO V2 — TEK MASTER (portable, 0→canli)
   tools/build-master.sh tarafindan uretilir (elle duzenleme). Kaynak: v2-production CURATED.
   SADECE KULLANILAN: test/benchmark(06/08/10/11), superseded(07→16,
   AcilisCalistir/AylikRutin eski→_V2/Full), local-fix(20/21) HARIC. Her obje 1 kez.
   PARAMETRIK (sqlcmd): $(MaliyetDb) hedef DB, $(ErpDb) ERP kaynak.
   Deploy: Invoke-Sqlcmd -InputFile bu -Variable "MaliyetDb=X","ErpDb=Y"
   YAPI: tablolar → SatisTutar kolonu → SP'ler → view'lar → curated seed.
   Pipeline (acilis+aylik) deploy SONRASI ayri tetiklenir (master'a dahil DEGIL).
   ============================================================================ */
-- :setvar MaliyetDb "BKMMaliyet"   (SSMS SQLCMD-modu icin yorum-disi birak)
-- :setvar ErpDb "DerinSISBkm"
GO
USE [$(MaliyetDb)];
GO
SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON; SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON; SET CONCAT_NULL_YIELDS_NULL ON; SET ARITHABORT ON; SET NUMERIC_ROUNDABORT OFF;
GO

GO
PRINT '======== 01 Tablolar ========';
GO
USE [$(MaliyetDb)];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
GO
SET NOCOUNT ON;
GO
/* ============================================================
   FIFO V2 TABLES (dbo)
   ============================================================ */
/* Child-first drop for rerunnable deploy */
IF OBJECT_ID('dbo.MaliyetIslemAdim','U') IS NOT NULL DROP TABLE dbo.MaliyetIslemAdim;
IF OBJECT_ID('dbo.FifoCikisDetay','U') IS NOT NULL DROP TABLE dbo.FifoCikisDetay;
IF OBJECT_ID('dbo.FifoSorunluStoklar','U') IS NOT NULL DROP TABLE dbo.FifoSorunluStoklar;
IF OBJECT_ID('dbo.FifoAcilisEnvanter','U') IS NOT NULL DROP TABLE dbo.FifoAcilisEnvanter;
IF OBJECT_ID('dbo.FifoKatman','U') IS NOT NULL DROP TABLE dbo.FifoKatman;
IF OBJECT_ID('dbo.FifoFallbackFiyatlari','U') IS NOT NULL DROP TABLE dbo.FifoFallbackFiyatlari;
IF OBJECT_ID('dbo.MaliyetIslem','U') IS NOT NULL DROP TABLE dbo.MaliyetIslem;
GO
CREATE TABLE dbo.FifoKatman (
    KatmanId BIGINT IDENTITY(1,1) NOT NULL,
    StkId INT NOT NULL,
    GirisTarihi DATE NOT NULL,
    KaynakTip NVARCHAR(20) NOT NULL,
    BelgeNo NVARCHAR(50) NULL,
    BelgeTarihi DATE NULL,
    FirmaId INT NULL,
    GirisMiktar DECIMAL(18,4) NOT NULL,
    KalanMiktar DECIMAL(18,4) NOT NULL,
    BirimMaliyet DECIMAL(18,6) NOT NULL,
    Durum NVARCHAR(50) NOT NULL CONSTRAINT DF_FifoKatman_Durum DEFAULT ('NORMAL'),
    KayitTarihi DATETIME2(0) NOT NULL CONSTRAINT DF_FifoKatman_Kayit DEFAULT (GETDATE()),
    CONSTRAINT PK_FifoKatman PRIMARY KEY (KatmanId),
    CONSTRAINT CK_FifoKatman_Miktar CHECK (GirisMiktar > 0 AND KalanMiktar >= 0 AND KalanMiktar <= GirisMiktar),
    CONSTRAINT CK_FifoKatman_BirimMaliyet CHECK (BirimMaliyet >= 0)
);
GO
CREATE INDEX IX_FifoKatman_Stk_Tarih
    ON dbo.FifoKatman(StkId, GirisTarihi, KaynakTip, KatmanId);
GO
CREATE INDEX IX_FifoKatman_Aktif
    ON dbo.FifoKatman(StkId, GirisTarihi, KaynakTip, KatmanId)
    INCLUDE (KalanMiktar, BirimMaliyet, BelgeNo, BelgeTarihi)
    WHERE KalanMiktar > 0;
GO
CREATE TABLE dbo.FifoAcilisEnvanter (
    EnvanterTarihi DATE NOT NULL,
    MekanId INT NOT NULL,
    StkId INT NOT NULL,
    StokMiktar DECIMAL(18,4) NOT NULL,
    KayitTarihi DATETIME2(0) NOT NULL CONSTRAINT DF_FifoAcilisEnvanter_Kayit DEFAULT (GETDATE()),
    CONSTRAINT PK_FifoAcilisEnvanter PRIMARY KEY (EnvanterTarihi, MekanId, StkId),
    CONSTRAINT CK_FifoAcilisEnvanter_Stok CHECK (StokMiktar >= 0)
);
GO
CREATE INDEX IX_FifoAcilisEnvanter_Stk
    ON dbo.FifoAcilisEnvanter(StkId, EnvanterTarihi, MekanId)
    INCLUDE (StokMiktar);
GO
CREATE TABLE dbo.FifoSorunluStoklar (
    EnvanterTarihi DATE NOT NULL,
    MekanId INT NOT NULL CONSTRAINT DF_FifoSorunluStoklar_Mekan DEFAULT (0),
    StkId INT NOT NULL,
    SorunTipi NVARCHAR(50) NOT NULL,
    StokMiktar DECIMAL(18,4) NOT NULL,
    Aciklama NVARCHAR(500) NULL,
    KayitTarihi DATETIME2(0) NOT NULL CONSTRAINT DF_FifoSorunluStoklar_Kayit DEFAULT (GETDATE()),
    CONSTRAINT PK_FifoSorunluStoklar PRIMARY KEY (EnvanterTarihi, MekanId, StkId, SorunTipi)
);
GO
CREATE INDEX IX_FifoSorunluStoklar_TarihStkMekan
    ON dbo.FifoSorunluStoklar(EnvanterTarihi, StkId, MekanId);
GO
CREATE INDEX IX_FifoSorunluStoklar_TipTarih
    ON dbo.FifoSorunluStoklar(SorunTipi, EnvanterTarihi)
    INCLUDE (StkId, MekanId, StokMiktar);
GO
CREATE TABLE dbo.FifoFallbackFiyatlari (
    StkId INT NOT NULL,
    SatinalmaSarti NVARCHAR(50) NOT NULL,
    MekanId INT NOT NULL CONSTRAINT DF_FifoFallbackFiyatlari_Mekan DEFAULT (0),
    BirimMaliyet DECIMAL(18,6) NOT NULL,
    Miktar DECIMAL(18,4) NOT NULL,
    ToplamTutar DECIMAL(18,4) NOT NULL,
    Aciklama NVARCHAR(200) NULL,
    KayitTarihi DATETIME2(0) NOT NULL CONSTRAINT DF_FifoFallbackFiyatlari_Kayit DEFAULT (GETDATE()),
    CONSTRAINT PK_FifoFallbackFiyatlari PRIMARY KEY (StkId, SatinalmaSarti, MekanId),
    CONSTRAINT CK_FifoFallbackFiyatlari_Pozitif CHECK (BirimMaliyet > 0 AND Miktar >= 0 AND ToplamTutar >= 0)
);
GO
CREATE INDEX IX_FifoFallbackFiyatlari_Satinalma
    ON dbo.FifoFallbackFiyatlari(SatinalmaSarti, StkId, MekanId)
    INCLUDE (BirimMaliyet, Miktar, ToplamTutar);
GO
CREATE TABLE dbo.FifoCikisDetay (
    CikisId BIGINT IDENTITY(1,1) NOT NULL,
    StkId INT NOT NULL,
    HareketTarihi DATE NOT NULL,
    HareketTipi NVARCHAR(10) NOT NULL,
    MekanId INT NULL,
    BelgeNo NVARCHAR(50) NULL,
    KatmanId BIGINT NOT NULL,
    KatmanTarihi DATE NOT NULL,
    KatmanBelgeNo NVARCHAR(50) NULL,
    Miktar DECIMAL(18,4) NOT NULL,
    BirimMaliyet DECIMAL(18,6) NOT NULL,
    CikisTutar AS (Miktar * BirimMaliyet) PERSISTED,
    KayitTarihi DATETIME2(0) NOT NULL CONSTRAINT DF_FifoCikisDetay_Kayit DEFAULT (GETDATE()),
    CONSTRAINT PK_FifoCikisDetay PRIMARY KEY (CikisId),
    CONSTRAINT FK_FifoCikisDetay_FifoKatman FOREIGN KEY (KatmanId) REFERENCES dbo.FifoKatman(KatmanId),
    CONSTRAINT CK_FifoCikisDetay_Miktar CHECK (Miktar > 0)
);
GO
CREATE INDEX IX_FifoCikisDetay_StkTarih
    ON dbo.FifoCikisDetay(StkId, HareketTarihi)
    INCLUDE (MekanId, HareketTipi, Miktar, CikisTutar, KatmanId);
GO
CREATE INDEX IX_FifoCikisDetay_MekanTarih
    ON dbo.FifoCikisDetay(MekanId, HareketTarihi)
    INCLUDE (StkId, HareketTipi, Miktar, CikisTutar, KatmanId);
GO
CREATE TABLE dbo.MaliyetIslem (
    IslemId UNIQUEIDENTIFIER NOT NULL,
    IslemAdi NVARCHAR(200) NULL,
    Baslangic DATETIME2(3) NOT NULL,
    Bitis DATETIME2(3) NULL,
    Durum NVARCHAR(30) NOT NULL,
    Aciklama NVARCHAR(500) NULL,
    EnvanterTarihi DATE NULL,
    MekanId INT NULL,
    StkId INT NULL,
    CONSTRAINT PK_MaliyetIslem PRIMARY KEY (IslemId)
);
GO
CREATE INDEX IX_MaliyetIslem_Durum
    ON dbo.MaliyetIslem(Durum, Baslangic DESC)
    INCLUDE (Bitis, IslemAdi, StkId, MekanId, EnvanterTarihi);
GO
CREATE TABLE dbo.MaliyetIslemAdim (
    IslemId UNIQUEIDENTIFIER NOT NULL,
    SiraNo INT NOT NULL,
    AdimKodu NVARCHAR(50) NOT NULL,
    AdimAdi NVARCHAR(200) NOT NULL,
    Durum NVARCHAR(30) NOT NULL,
    Mesaj NVARCHAR(500) NULL,
    Baslangic DATETIME2(3) NULL,
    Bitis DATETIME2(3) NULL,
    Guncelleme DATETIME2(3) NOT NULL CONSTRAINT DF_MaliyetIslemAdim_Guncelleme DEFAULT (GETDATE()),
    CONSTRAINT PK_MaliyetIslemAdim PRIMARY KEY (IslemId, AdimKodu),
    CONSTRAINT FK_MaliyetIslemAdim_Islem FOREIGN KEY (IslemId) REFERENCES dbo.MaliyetIslem(IslemId)
);
GO
CREATE INDEX IX_MaliyetIslemAdim_Sira
    ON dbo.MaliyetIslemAdim(IslemId, SiraNo)
    INCLUDE (AdimKodu, Durum, Baslangic, Bitis, Mesaj);
GO
CREATE INDEX IX_MaliyetIslemAdim_AdimKodu
    ON dbo.MaliyetIslemAdim(AdimKodu, Guncelleme DESC)
    INCLUDE (IslemId, SiraNo, Durum);
GO


GO
PRINT '======== 19 Cikis SatisTutar (computed col, SP ONCESI) ========';
GO
-- 19_V2_CikisSatisTutar.sql
-- FifoCikisDetay tablosuna SatisTutar kolonu ekle + mevcut verileri backfill
-- Satis tutari: irsHrk'dan tarih+mekan+stk eslesmesiyle, gunluk toplam uzerinden oran hesabi

-- =============================================================
-- 1) KOLON EKLE (idempotent)
-- =============================================================
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.FifoCikisDetay') AND name = 'SatisTutar'
)
BEGIN
    ALTER TABLE dbo.FifoCikisDetay ADD SatisTutar DECIMAL(18,4) NULL;
    PRINT 'FifoCikisDetay.SatisTutar kolonu eklendi.';
END
GO

-- =============================================================
-- 2) MEVCUT VERILERI GERI DOLDUR (backfill)
-- =============================================================
-- Yaklasim: irsHrk'dan tarih + mekan + StkId bazinda gunluk toplam tutar al
-- Her cikis satirina miktar oraninda dagit
-- ehTutarN = net satis tutari (indirim dusulmus, KDV haric)

;WITH hrkGunluk AS (
    SELECT
        h.ehstkID AS StkId,
        CAST(h.ehTrhS AS DATE) AS Tarih,
        h.ehMekan AS MekanId,
        SUM(h.ehAdetN) AS ToplamAdet,
        SUM(h.ehTutarN) AS ToplamTutar
    FROM $(ErpDb).dbo.irsHrk h
    WHERE h.ehstkID IN (SELECT DISTINCT StkId FROM FifoCikisDetay WHERE SatisTutar IS NULL)
      AND h.ehMekan IN (1, 12, 4477, 4478)
      AND h.ehAltDepo = 0
    GROUP BY h.ehstkID, CAST(h.ehTrhS AS DATE), h.ehMekan
)
UPDATE c
SET c.SatisTutar = CASE
    WHEN g.ToplamAdet = 0 THEN 0
    ELSE ABS(CAST(c.Miktar AS DECIMAL(18,4)) / CAST(g.ToplamAdet AS DECIMAL(18,4)) * CAST(g.ToplamTutar AS DECIMAL(18,4)))
END
FROM FifoCikisDetay c
JOIN hrkGunluk g ON g.StkId = c.StkId AND g.Tarih = c.HareketTarihi AND g.MekanId = c.MekanId
WHERE c.SatisTutar IS NULL;

PRINT 'Backfill tamamlandi: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' satir guncellendi.';
GO

GO
PRINT '======== 12 Ortalama Aylik Maliyet ========';
GO
USE [$(MaliyetDb)];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
GO
SET NOCOUNT ON;
GO

/* ============================================================
   ORTALAMA AYLIK MALIYET
   Tablo + sp_Ortalama_AylikHesapla

   FIFO ile paralel calisir:
     - Acilis: FifoAcilisEnvanter + FifoKatman agirlikli ort.
     - Aylik alislar: $(ErpDb).dbo.fat + fatAyr
     - Ay sonu stok: $(ErpDb).dbo.irsHrk
     - Formula: (AyBasiTutar + GirisTutar) / (AyBasiMiktar + GirisMiktar)

   PK: (YilAy, StkId) -- FifoKatman gibi lokasyon aggregate
   ============================================================ */

/* -------- TABLO -------- */
IF OBJECT_ID('dbo.OrtalamaAylikMaliyet', 'U') IS NOT NULL
    DROP TABLE dbo.OrtalamaAylikMaliyet;
GO

CREATE TABLE dbo.OrtalamaAylikMaliyet (
    YilAy               INT             NOT NULL,  -- YYYYMM (ornek: 202601)
    StkId               INT             NOT NULL,
    AyBasiMiktar        DECIMAL(18,4)   NOT NULL CONSTRAINT DF_OAM_AyBasiMiktar  DEFAULT 0,
    AyBasiTutar         DECIMAL(18,4)   NOT NULL CONSTRAINT DF_OAM_AyBasiTutar   DEFAULT 0,
    GirisMiktar         DECIMAL(18,4)   NOT NULL CONSTRAINT DF_OAM_GirisMiktar   DEFAULT 0,
    GirisTutar          DECIMAL(18,4)   NOT NULL CONSTRAINT DF_OAM_GirisTutar    DEFAULT 0,
    CikisMiktar         DECIMAL(18,4)   NOT NULL CONSTRAINT DF_OAM_CikisMiktar   DEFAULT 0,
    AySonuMiktar        DECIMAL(18,4)   NOT NULL CONSTRAINT DF_OAM_AySonuMiktar  DEFAULT 0,
    AySonuBirimMaliyet  DECIMAL(18,6)   NOT NULL CONSTRAINT DF_OAM_AySonuBMal   DEFAULT 0,
    AySonuTutar         DECIMAL(18,4)   NOT NULL CONSTRAINT DF_OAM_AySonuTutar   DEFAULT 0,
    CreateUtc           DATETIME2(0)    NOT NULL CONSTRAINT DF_OAM_CreateUtc     DEFAULT GETUTCDATE(),
    UpdateUtc           DATETIME2(0)    NOT NULL CONSTRAINT DF_OAM_UpdateUtc     DEFAULT GETUTCDATE(),
    CONSTRAINT PK_OrtalamaAylikMaliyet PRIMARY KEY (YilAy, StkId)
);
GO

CREATE INDEX IX_OAM_StkIdYilAy
    ON dbo.OrtalamaAylikMaliyet(StkId, YilAy)
    INCLUDE (AySonuMiktar, AySonuBirimMaliyet, AySonuTutar);
GO

PRINT 'dbo.OrtalamaAylikMaliyet olusturuldu.';
GO

/* -------- STORED PROCEDURE -------- */
CREATE OR ALTER PROCEDURE dbo.sp_Ortalama_AylikHesapla
(
    @Yil            INT,
    @Ay             INT,
    @AcilisTarihi   DATE            = NULL,     -- Sadece ilk ay: FIFO acilis tarihi
    @StkId          INT             = NULL,     -- NULL = tum urunler
    @IslemId        UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* --- Parametre validasyonu --- */
    IF @Yil IS NULL OR @Ay IS NULL OR @Ay NOT BETWEEN 1 AND 12
    BEGIN
        RAISERROR('Gecersiz yil/ay parametresi.', 16, 1);
        RETURN;
    END

    DECLARE @YilAy       INT  = @Yil * 100 + @Ay;
    DECLARE @AyBas       DATE = DATEFROMPARTS(@Yil, @Ay, 1);
    DECLARE @AySonu      DATE = EOMONTH(@AyBas);
    DECLARE @OncekiYilAy INT  = CASE WHEN @Ay = 1
                                     THEN (@Yil - 1) * 100 + 12
                                     ELSE @YilAy - 1 END;

    IF @IslemId IS NOT NULL
        EXEC dbo.sp_MaliyetAdimYaz @IslemId, 'ort_hesapla', 'Ortalama maliyet hesaplama',
             10, 'CALISIYOR', NULL;

    BEGIN TRY
        BEGIN TRANSACTION;

        /* ================================================
           ADIM 1: Ay basi bakiyesi
           - Onceki ay kaydi varsa: OrtalamaAylikMaliyet'ten
           - Yoksa ve @AcilisTarihi verilmisse: FIFO katmanindan
           ================================================ */
        IF OBJECT_ID('tempdb..#ayBas', 'U') IS NOT NULL DROP TABLE #ayBas;
        CREATE TABLE #ayBas (StkId INT NOT NULL PRIMARY KEY,
                             Miktar DECIMAL(18,4) NOT NULL,
                             Tutar  DECIMAL(18,4) NOT NULL);

        IF EXISTS (
            SELECT 1 FROM dbo.OrtalamaAylikMaliyet
            WHERE YilAy = @OncekiYilAy
              AND (@StkId IS NULL OR StkId = @StkId)
        )
        BEGIN
            INSERT INTO #ayBas (StkId, Miktar, Tutar)
            SELECT StkId, AySonuMiktar, AySonuTutar
            FROM   dbo.OrtalamaAylikMaliyet
            WHERE  YilAy = @OncekiYilAy
              AND  (@StkId IS NULL OR StkId = @StkId)
              AND  AySonuMiktar > 0;

            PRINT CONCAT('[1/4] Ay basi: onceki ay (', @OncekiYilAy, ') kaydindan alindi. ',
                         @@ROWCOUNT, ' urun.');
        END
        ELSE IF @AcilisTarihi IS NOT NULL
        BEGIN
            /* FifoAcilisEnvanter miktar + FifoKatman agirlikli ort birim maliyet */
            INSERT INTO #ayBas (StkId, Miktar, Tutar)
            SELECT
                e.StkId,
                SUM(e.StokMiktar) AS Miktar,
                SUM(e.StokMiktar) * ISNULL(k.OrtBirimMaliyet, 0) AS Tutar
            FROM dbo.FifoAcilisEnvanter e
            LEFT JOIN (
                SELECT
                    StkId,
                    SUM(GirisMiktar * BirimMaliyet) / NULLIF(SUM(GirisMiktar), 0)
                        AS OrtBirimMaliyet
                FROM  dbo.FifoKatman
                WHERE KaynakTip IN ('ACILIS', 'ACILIS_TAMAMLA')
                  AND GirisTarihi = @AcilisTarihi
                  AND (@StkId IS NULL OR StkId = @StkId)
                GROUP BY StkId
            ) k ON k.StkId = e.StkId
            WHERE e.EnvanterTarihi = @AcilisTarihi
              AND (@StkId IS NULL OR e.StkId = @StkId)
              AND e.StokMiktar > 0
            GROUP BY e.StkId, k.OrtBirimMaliyet;

            PRINT CONCAT('[1/4] Ay basi: FIFO acilis (', @AcilisTarihi, ') katmanindan alindi. ',
                         @@ROWCOUNT, ' urun.');
        END
        ELSE
        BEGIN
            PRINT '[1/4] Ay basi: onceki ay yok, AcilisTarihi verilmedi. Sifir baslangic.';
        END

        /* ================================================
           ADIM 2: Ay ici alislar (fat + fatAyr, eTip IN 0/2)
           eGC=0 normal alis, eGC=1 alis iadesi (negatif)
           ================================================ */
        IF OBJECT_ID('tempdb..#giris', 'U') IS NOT NULL DROP TABLE #giris;
        SELECT
            a.ehStkId AS StkId,
            SUM(CONVERT(DECIMAL(18,4),
                a.ehAdetN * CASE WHEN f.eGC = 0 THEN 1 ELSE -1 END
            )) AS GirisMiktar,
            SUM(CONVERT(DECIMAL(18,4),
                a.ehTutarN * CASE WHEN f.eGC = 0 THEN 1 ELSE -1 END
            )) AS GirisTutar
        INTO #giris
        FROM $(ErpDb).dbo.fatAyr a WITH(NOLOCK)
        JOIN $(ErpDb).dbo.fat    f WITH(NOLOCK) ON f.eID = a.ehID
        WHERE f.eTip IN (0, 2)
          AND a.ehAdetN <> 0
          AND f.eTarihS >= CONVERT(smalldatetime, @AyBas)
          AND f.eTarihS <  CONVERT(smalldatetime, DATEADD(DAY, 1, @AySonu))
          AND (@StkId IS NULL OR a.ehStkId = @StkId)
        GROUP BY a.ehStkId
        HAVING SUM(CONVERT(DECIMAL(18,4),
                   a.ehAdetN * CASE WHEN f.eGC = 0 THEN 1 ELSE -1 END)) > 0;

        PRINT CONCAT('[2/4] Girisler: ', @@ROWCOUNT, ' urun icin ay ici alis alindi.');

        /* ================================================
           ADIM 3: Ay sonu stok (irsHrk kumulatif)
           ================================================ */
        IF OBJECT_ID('tempdb..#aySonu', 'U') IS NOT NULL DROP TABLE #aySonu;
        SELECT
            h.ehStkId AS StkId,
            SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) AS AySonuMiktar
        INTO #aySonu
        FROM $(ErpDb).dbo.irsHrk h WITH(NOLOCK)
        WHERE h.ehTrhS <= @AySonu
          AND h.ehMekan IN (1, 12, 4477, 4478)   -- FIX: FIFO ile ayni mekan havuzu (kural: ortak havuz)
          AND h.ehAltDepo = 0                      -- FIX: alt depo haric (FIFO acilis ile tutarli)
          AND (@StkId IS NULL OR h.ehStkId = @StkId)
        GROUP BY h.ehStkId
        HAVING SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) > 0;

        PRINT CONCAT('[3/4] Ay sonu stok: ', @@ROWCOUNT, ' urun.');

        /* ================================================
           ADIM 4: Hesapla + upsert
           Formula:
             AySonuBirimMaliyet = (AyBasiTutar + GirisTutar)
                                / NULLIF(AyBasiMiktar + GirisMiktar, 0)
             CikisMiktar        = AyBasiMiktar + GirisMiktar - AySonuMiktar
           ================================================ */
        DELETE FROM dbo.OrtalamaAylikMaliyet
        WHERE YilAy = @YilAy
          AND (@StkId IS NULL OR StkId = @StkId);

        INSERT INTO dbo.OrtalamaAylikMaliyet
            (YilAy, StkId,
             AyBasiMiktar, AyBasiTutar,
             GirisMiktar,  GirisTutar,
             CikisMiktar,
             AySonuMiktar, AySonuBirimMaliyet, AySonuTutar)
        SELECT
            @YilAy,
            StkId,
            AyBasiMiktar,
            AyBasiTutar,
            GirisMiktar,
            GirisTutar,
            /* Cikis = acilis + giris - aySonu (negatife dustugunde 0) */
            CASE WHEN AyBasiMiktar + GirisMiktar - AySonuMiktar < 0
                 THEN 0
                 ELSE AyBasiMiktar + GirisMiktar - AySonuMiktar END AS CikisMiktar,
            AySonuMiktar,
            /* Sifir bolme koruması: stok gelip tukenmisse onceki birim fiyat kalir */
            CASE
                WHEN AyBasiMiktar + GirisMiktar = 0 THEN 0
                ELSE (AyBasiTutar + GirisTutar) / (AyBasiMiktar + GirisMiktar)
            END AS AySonuBirimMaliyet,
            AySonuMiktar *
            CASE
                WHEN AyBasiMiktar + GirisMiktar = 0 THEN 0
                ELSE (AyBasiTutar + GirisTutar) / (AyBasiMiktar + GirisMiktar)
            END AS AySonuTutar
        FROM (
            SELECT
                ISNULL(b.StkId, ISNULL(g.StkId, s.StkId))   AS StkId,
                ISNULL(b.Miktar,      0)                       AS AyBasiMiktar,
                ISNULL(b.Tutar,       0)                       AS AyBasiTutar,
                ISNULL(g.GirisMiktar, 0)                       AS GirisMiktar,
                ISNULL(g.GirisTutar,  0)                       AS GirisTutar,
                ISNULL(s.AySonuMiktar,
                       ISNULL(b.Miktar, 0) + ISNULL(g.GirisMiktar, 0)
                )                                              AS AySonuMiktar
            FROM      #ayBas b
            FULL JOIN #giris g  ON g.StkId = b.StkId
            FULL JOIN #aySonu s ON s.StkId = ISNULL(b.StkId, g.StkId)
        ) calc
        WHERE AyBasiMiktar + GirisMiktar > 0;  -- kayda degmez satiri yazma

        PRINT CONCAT('[4/4] Upsert tamamlandi: ', @@ROWCOUNT, ' urun yazildi.');

        COMMIT TRANSACTION;

        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, 'ort_hesapla', 'Ortalama maliyet hesaplama',
                 10, 'TAMAMLANDI', NULL;

        PRINT CONCAT('sp_Ortalama_AylikHesapla tamamlandi. YilAy=', @YilAy);
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @HataMesaji NVARCHAR(500) = ERROR_MESSAGE();
        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, 'ort_hesapla', 'Ortalama maliyet hesaplama',
                 10, 'HATA', @HataMesaji;
        THROW;
    END CATCH
END
GO

PRINT 'dbo.sp_Ortalama_AylikHesapla olusturuldu.';
GO

/* -------- KONTROL SORGUSU -------- */
SELECT
    OBJECT_ID('dbo.OrtalamaAylikMaliyet', 'U')           AS tablo_var,
    OBJECT_ID('dbo.sp_Ortalama_AylikHesapla', 'P')       AS sp_var;
GO

GO
PRINT '======== 02 Core SP (eski AcilisCalistir+AylikRutin HARIC, AylikCalistir TUTULDU) ========';
GO
USE [$(MaliyetDb)];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
GO

CREATE OR ALTER PROCEDURE dbo.sp_Fifo_AcilisMaliyetlendir
(
    @EnvanterTarihi DATE,
    @StkId INT = NULL,
    @IslemId UNIQUEIDENTIFIER = NULL,
    @fallbackSatinalmaSarti VARCHAR(50) = NULL,   -- sadece fallback fiyatlama (acilis) icin
    @atlamaAylikDevir BIT = 0,            -- 1 = Agir aylik devir adimini atla (timeout onleme)
    @sabitFallbackBirimMaliyet DECIMAL(18,6) = NULL -- son care tek seferlik sabit fiyat
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @AdimKodu VARCHAR(50) = NULL;
    DECLARE @AdimAdi VARCHAR(100) = NULL;
    DECLARE @SiraNo INT = NULL;
    
    -- Parametre validasyonu
    IF @EnvanterTarihi IS NULL
    BEGIN
        RAISERROR('Envanter tarihi bos olamaz', 16, 1);
        RETURN;
    END

    IF @sabitFallbackBirimMaliyet IS NOT NULL AND @sabitFallbackBirimMaliyet <= 0
    BEGIN
        RAISERROR('Sabit fallback birim maliyet 0''dan buyuk olmali', 16, 1);
        RETURN;
    END
    
    IF @EnvanterTarihi > GETDATE()
    BEGIN
        RAISERROR('Envanter tarihi gelecek tarih olamaz', 16, 1);
        RETURN;
    END
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        /* Audit triggeri devre disi birak - toplu INSERT log dolduruyor */
        IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'tr_fifo_StokMaliyetHavuzu_DegisimGunlugu' AND parent_id = OBJECT_ID('dbo.FifoKatman'))
            ALTER TABLE dbo.FifoKatman DISABLE TRIGGER tr_fifo_StokMaliyetHavuzu_DegisimGunlugu;
        ELSE IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'tr_fifo_StokMaliyetHavuzu_Audit' AND parent_id = OBJECT_ID('dbo.FifoKatman'))
            ALTER TABLE dbo.FifoKatman DISABLE TRIGGER tr_fifo_StokMaliyetHavuzu_Audit;
        
        DECLARE @baslangicTarihi DATE = DATEFROMPARTS(2021, 5, 31);

        SET @AdimKodu = 'acilis_envanter';
        SET @AdimAdi = 'Envanter snapshot';
        SET @SiraNo = 10;
        PRINT '[1/4] Envanter snapshot - irsHrk okunuyor...';
        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'CALISIYOR', NULL;

        /* 1) Envanter tarihindeki stok Miktarlarinc cek (irsHrk - mekan bazli) */
        IF OBJECT_ID('tempdb..#stoklarMekan', 'U') IS NOT NULL DROP TABLE #stoklarMekan;

        SELECT 
            h.ehMekan AS MekanId,
            h.ehStkId AS StkId,
            SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) AS StokMiktar
        INTO #stoklarMekan
        FROM $(ErpDb).dbo.irsHrk h WITH(NOLOCK)
        WHERE h.ehTrhS <= @EnvanterTarihi
          AND h.ehAltDepo = 0
          AND h.ehMekan IN (1, 12, 4477, 4478)
          AND (@StkId IS NULL OR h.ehStkId = @StkId)
        GROUP BY h.ehMekan, h.ehStkId
        HAVING SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) > 0;

        CREATE INDEX IX_tmp_stoklarMekan_mekan_StkId ON #stoklarMekan(MekanId, StkId);

        IF OBJECT_ID('tempdb..#stoklar', 'U') IS NOT NULL DROP TABLE #stoklar;

        SELECT
            StkId,
            SUM(StokMiktar) AS StokMiktar
        INTO #stoklar
        FROM #stoklarMekan
        GROUP BY StkId;

        CREATE INDEX IX_tmp_stoklar_StkId ON #stoklar(StkId);

        /* DEVRE DISI URUNLER: maliyet katmani KURULMAZ (posetler/ambalaj gibi maliyeti 0,
           alisi gider yazilan kalemler). Envanter snapshot'ta KALIR (#stoklarMekan dokunulmaz). */
        IF OBJECT_ID('dbo.FifoDevreDisiUrunler', 'U') IS NOT NULL
            DELETE FROM #stoklar
            WHERE StkId IN (SELECT StkId FROM dbo.FifoDevreDisiUrunler);

        DELETE FROM dbo.FifoAcilisEnvanter
        WHERE EnvanterTarihi = @EnvanterTarihi
          AND (@StkId IS NULL OR StkId = @StkId);

        INSERT INTO dbo.FifoAcilisEnvanter (EnvanterTarihi, MekanId, StkId, StokMiktar)
        SELECT @EnvanterTarihi, MekanId, StkId, StokMiktar
        FROM #stoklarMekan;

        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'TAMAMLANDI', NULL;
        PRINT '      Envanter tamamlandi.';

        SET @AdimKodu = 'acilis_alis';
        SET @AdimAdi = 'Alislar toplanir';
        SET @SiraNo = 20;
        PRINT '[2/4] Alislar toplaniyor (fat+fatAyr)...';
        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'CALISIYOR', NULL;

        /* 2) Baslangic-envanter arasi alislari cek (SADECE FATURA: fat + fatAyr) */
        IF OBJECT_ID('tempdb..#alislar', 'U') IS NOT NULL DROP TABLE #alislar;

        SELECT 
            a.ehStkId AS StkId,
            f.eTarihS AS GirisTarihi,
            f.eNo     AS BelgeNo,
            f.eTarihS AS BelgeTarihi,
            f.eFirma  AS FirmaId,
            SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS Miktar,
            SUM(CONVERT(DECIMAL(18,4),
                CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END
            )) AS netTutar
        INTO #alislar
        FROM #stoklar s
        JOIN $(ErpDb).dbo.fatAyr a WITH(NOLOCK)
            ON a.ehStkId = s.StkId
        JOIN $(ErpDb).dbo.fat f WITH(NOLOCK)
            ON f.eID = a.ehID
        WHERE a.ehAdetN <> 0
          AND f.eTarihS >  CONVERT(smalldatetime, @baslangicTarihi)
          AND f.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @EnvanterTarihi))
          AND f.eTip IN (0, 2)
          AND (@StkId IS NULL OR a.ehStkId = @StkId)
        GROUP BY a.ehStkId, f.eTarihS, f.eID, f.eNo, f.eFirma
        HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;

        ALTER TABLE #alislar ADD BirimMaliyet DECIMAL(18,6);

        UPDATE #alislar
        SET BirimMaliyet = CASE WHEN Miktar = 0 THEN 0 ELSE netTutar / Miktar END;

        CREATE INDEX IX_tmp_alislar_stkTarih 
            ON #alislar(StkId, GirisTarihi DESC, BelgeNo);

        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'TAMAMLANDI', NULL;
        PRINT '      Alislar tamamlandi.';

        SET @AdimKodu = 'acilis_katman';
        SET @AdimAdi = 'Ters FIFO katman';
        SET @SiraNo = 30;
        PRINT '[3/4] Ters FIFO katman hesaplaniyor...';
        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'CALISIYOR', NULL;

        /* 3) Ters FIFO ile acilis katmanlarini hesapla */
        IF OBJECT_ID('tempdb..#katman', 'U') IS NOT NULL DROP TABLE #katman;

        ;WITH Ters AS (
            SELECT
                StkId, GirisTarihi, BelgeNo, BelgeTarihi, FirmaId, Miktar, BirimMaliyet, netTutar,
                SUM(Miktar) OVER (
                    PARTITION BY StkId
                    ORDER BY GirisTarihi DESC, BelgeNo DESC
                    ROWS UNBOUNDED PRECEDING
                ) AS kumTers
            FROM #alislar
            WHERE Miktar > 0 AND netTutar > 0
        ),
        Acilis AS (
            SELECT
                t.StkId, t.GirisTarihi, t.BelgeNo, t.BelgeTarihi, t.FirmaId,
                t.Miktar AS satirMiktar, t.BirimMaliyet,
                t.kumTers, s.StokMiktar,
                CASE 
                    WHEN t.kumTers - t.Miktar >= s.StokMiktar THEN 0
                    WHEN t.kumTers <= s.StokMiktar THEN t.Miktar
                    ELSE s.StokMiktar - (t.kumTers - t.Miktar)
                END AS acilisMiktar
            FROM Ters t
            JOIN #stoklar s ON s.StkId = t.StkId
        )
        SELECT * INTO #katman FROM Acilis WHERE acilisMiktar > 0;

        /* 4) Acilis oncesi temizlik:
              - ACILIS/ACILIS_TAMAMLA: sadece envanter tarihi
              - AYLIK_DEVIR: baslangic-envanter arasi tum tarihler */
        DELETE FROM dbo.FifoKatman
        WHERE KaynakTip IN ('ACILIS', 'ACILIS_TAMAMLA')
          AND GirisTarihi = @EnvanterTarihi
          AND (@StkId IS NULL OR StkId = @StkId);

        DELETE FROM dbo.FifoKatman
        WHERE KaynakTip = 'AYLIK_DEVIR'
          AND GirisTarihi BETWEEN @baslangicTarihi AND @EnvanterTarihi
          AND (@StkId IS NULL OR StkId = @StkId);

        INSERT INTO dbo.FifoKatman
            (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
             GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
        SELECT
            StkId, @EnvanterTarihi, 'ACILIS', BelgeNo, BelgeTarihi, FirmaId,
            acilisMiktar, acilisMiktar, BirimMaliyet, 'NORMAL'
        FROM #katman;

        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'TAMAMLANDI', NULL;
        PRINT '      Katman hesaplamasc tamamlandi.';

        SET @AdimKodu = 'acilis_sorun';
        SET @AdimAdi = 'Sorun kaydi';
        SET @SiraNo = 40;
        PRINT '[4/4] Tamamlama + sorun kayitlari (merkez, son fiyat, aylik devir)...';
        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'CALISIYOR', NULL;

        /* 5) Eksik Miktarlari tespit et */
        ;WITH Ozet AS (
            SELECT StkId, SUM(acilisMiktar) AS toplamAcilisMiktar
            FROM #katman GROUP BY StkId
        ),
        AlisVarMi AS (
            SELECT DISTINCT StkId FROM #alislar
        )
        SELECT
            s.StkId, s.StokMiktar,
            ISNULL(o.toplamAcilisMiktar, 0) AS toplamAcilisMiktar,
            (s.StokMiktar - ISNULL(o.toplamAcilisMiktar, 0)) AS eksikMiktar
        INTO #eksiklar
        FROM #stoklar s
        LEFT JOIN Ozet o ON o.StkId = s.StkId
        LEFT JOIN AlisVarMi v ON v.StkId = s.StkId;

        /* 6) Alisc olan ama yetmeyenleri son alisla tamamla */
        ;WITH SonAlis AS (
            SELECT
                a.StkId, a.GirisTarihi, a.BelgeNo, a.BelgeTarihi, a.FirmaId, a.BirimMaliyet,
                ROW_NUMBER() OVER (
                    PARTITION BY a.StkId
                    ORDER BY a.GirisTarihi DESC, a.BelgeNo DESC
                ) AS rn
            FROM #alislar a
        )
        INSERT INTO dbo.FifoKatman
            (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
             GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
        SELECT
            e.StkId, @EnvanterTarihi, 'ACILIS_TAMAMLA', sa.BelgeNo, sa.BelgeTarihi, sa.FirmaId,
            e.eksikMiktar, e.eksikMiktar, sa.BirimMaliyet, 'TAMAMLAMA'
        FROM #eksiklar e
        JOIN SonAlis sa ON sa.StkId = e.StkId AND sa.rn = 1
        WHERE e.eksikMiktar > 0 AND e.toplamAcilisMiktar > 0;


        /* 7) Sorunlu kayitlari olustur */
        
        /* 6b) Merkez depo (12) alis faturalarc ile tamamlama (alis yoksa) - fat+fatAyr+irs (mekan icin) */
        IF OBJECT_ID('tempdb..#merkezAlis', 'U') IS NOT NULL DROP TABLE #merkezAlis;

        SELECT
            a.ehStkId AS StkId,
            f.eTarihS AS GirisTarihi,
            f.eNo     AS BelgeNo,
            f.eTarihS AS BelgeTarihi,
            f.eFirma  AS FirmaId,
            SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS Miktar,
            SUM(CONVERT(DECIMAL(18,4),
                CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END
            )) AS netTutar
        INTO #merkezAlis
        FROM #eksiklar e
        LEFT JOIN (SELECT DISTINCT StkId FROM #alislar) v ON v.StkId = e.StkId
        JOIN $(ErpDb).dbo.fatAyr a WITH(NOLOCK)
            ON a.ehStkId = e.StkId
        JOIN $(ErpDb).dbo.fat f WITH(NOLOCK)
            ON f.eID = a.ehID
        JOIN $(ErpDb).dbo.irs i WITH(NOLOCK)
            ON i.eID = a.ehIrsID
           AND i.eMekan = 12
        WHERE a.ehAdetN <> 0
          AND v.StkId IS NULL
          AND e.eksikMiktar > 0
          AND f.eTarihS >  CONVERT(smalldatetime, @baslangicTarihi)
          AND f.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @EnvanterTarihi))
          AND f.eTip IN (0, 2)
          AND (@StkId IS NULL OR a.ehStkId = @StkId)
        GROUP BY a.ehStkId, f.eTarihS, f.eID, f.eNo, f.eFirma
        HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;

        ALTER TABLE #merkezAlis ADD BirimMaliyet DECIMAL(18,6);
        UPDATE #merkezAlis
        SET BirimMaliyet = CASE WHEN Miktar = 0 THEN 0 ELSE netTutar / Miktar END;

        IF OBJECT_ID('tempdb..#merkezSon', 'U') IS NOT NULL DROP TABLE #merkezSon;

        ;WITH SonMerkez AS (
            SELECT
                m.StkId, m.GirisTarihi, m.BelgeNo, m.BelgeTarihi, m.FirmaId, m.BirimMaliyet,
                ROW_NUMBER() OVER (
                    PARTITION BY m.StkId
                    ORDER BY m.GirisTarihi DESC, m.BelgeNo DESC
                ) AS rn
            FROM #merkezAlis m
        )
        SELECT
            StkId, GirisTarihi, BelgeNo, BelgeTarihi, FirmaId, BirimMaliyet
        INTO #merkezSon
        FROM SonMerkez
        WHERE rn = 1;

        INSERT INTO dbo.FifoKatman
            (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
             GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
        SELECT
            e.StkId, @EnvanterTarihi, 'ACILIS_TAMAMLA', ms.BelgeNo, ms.BelgeTarihi, ms.FirmaId,
            e.eksikMiktar, e.eksikMiktar, ms.BirimMaliyet, 'MERKEZ_TAMAMLAMA'
        FROM #eksiklar e
        JOIN #merkezSon ms ON ms.StkId = e.StkId
        LEFT JOIN (SELECT DISTINCT StkId FROM #alislar) v ON v.StkId = e.StkId
        WHERE v.StkId IS NULL AND e.eksikMiktar > 0;

        /* 6c) Son gecerli fiyat ile tamamlama (alis yoksa, merkez de yoksa) */
        IF OBJECT_ID('tempdb..#sonGecerli', 'U') IS NOT NULL DROP TABLE #sonGecerli;

        ;WITH SonFiyat AS (
            SELECT
                f.fhID,
                f.fStkId AS StkId,
                f.fTarih,
                f.fTarihSon,
                f.sonrakiNet,
                ROW_NUMBER() OVER (
                    PARTITION BY f.fStkId
                    ORDER BY f.fTarihSon DESC, f.fhID DESC
                ) AS rn
            FROM $(ErpDb).bkm.fn_SonGecerliFiyat(@EnvanterTarihi, 1) f
            WHERE f.sonrakiNet > 0
        )
        SELECT
            StkId,
            fhID,
            fTarih,
            fTarihSon,
            sonrakiNet
        INTO #sonGecerli
        FROM SonFiyat
        WHERE rn = 1;

        INSERT INTO dbo.FifoKatman
            (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
             GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
        SELECT
            e.StkId,
            @EnvanterTarihi,
            'ACILIS_TAMAMLA',
            CAST(sg.fhID AS VARCHAR(50)),
            CAST(sg.fTarihSon AS DATE),
            NULL,
            e.eksikMiktar,
            e.eksikMiktar,
            sg.sonrakiNet,
            'SART_TAMAMLAMA'
        FROM #eksiklar e
        JOIN #sonGecerli sg ON sg.StkId = e.StkId
        LEFT JOIN (SELECT DISTINCT StkId FROM #alislar) v ON v.StkId = e.StkId
        LEFT JOIN #merkezSon ms ON ms.StkId = e.StkId
        WHERE v.StkId IS NULL
          AND ms.StkId IS NULL
          AND e.eksikMiktar > 0;

        /* 6d) Aylik devir ile tamamlama (alis/merkez/sart yoksa) - @atlamaAylikDevir=1 ise atlanAr (timeout onleme) */
        IF OBJECT_ID('tempdb..#eksikKalan', 'U') IS NOT NULL DROP TABLE #eksikKalan;

        SELECT e.StkId, e.eksikMiktar
        INTO #eksikKalan
        FROM #eksiklar e
        LEFT JOIN (SELECT DISTINCT StkId FROM #alislar) v ON v.StkId = e.StkId
        LEFT JOIN #merkezSon ms ON ms.StkId = e.StkId
        LEFT JOIN #sonGecerli sg ON sg.StkId = e.StkId
        WHERE e.eksikMiktar > 0 AND v.StkId IS NULL AND ms.StkId IS NULL AND sg.StkId IS NULL;

        IF OBJECT_ID('tempdb..#aylikKatman', 'U') IS NOT NULL DROP TABLE #aylikKatman;
        CREATE TABLE #aylikKatman (
            StkId INT NOT NULL,
            ayBitis DATE NOT NULL,
            ayMiktar DECIMAL(18,4) NOT NULL,
            BirimMaliyet DECIMAL(18,6) NULL,
            Durum VARCHAR(20) NOT NULL
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
                    ayBas = DATEFROMPARTS(YEAR(@EnvanterTarihi), MONTH(@EnvanterTarihi), 1),
                    ayBitis = EOMONTH(@EnvanterTarihi)
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
                StkId INT NOT NULL,
                ayBitis DATE NOT NULL,
                ayStok DECIMAL(18,4) NOT NULL
            );

            /* irsHrk ile gecmis stok - tek sorgu, mekan bazli toplam */
            INSERT INTO #aylikStok (StkId, ayBitis, ayStok)
            SELECT
                h.ehStkId AS StkId,
                a.ayBitis,
                SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) AS ayStok
            FROM $(ErpDb).dbo.irsHrk h WITH(NOLOCK)
            JOIN #aylar a ON h.ehTrhS <= DATEADD(DAY, 1, a.ayBitis)
            JOIN #eksikKalan e ON e.StkId = h.ehStkId
            WHERE h.ehAltDepo = 0
              AND h.ehMekan IN (1, 12, 4477, 4478)
            GROUP BY h.ehStkId, a.ayBitis
            HAVING SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) > 0;

            IF OBJECT_ID('tempdb..#aylikAlloc', 'U') IS NOT NULL DROP TABLE #aylikAlloc;

            ;WITH Aylik AS (
                SELECT
                    s.StkId, s.ayBitis, s.ayStok,
                    SUM(s.ayStok) OVER (
                        PARTITION BY s.StkId
                        ORDER BY s.ayBitis DESC
                        ROWS UNBOUNDED PRECEDING
                    ) AS kumStok
                FROM #aylikStok s
            ),
            Alloc AS (
                SELECT
                    a.StkId, a.ayBitis,
                    CAST(
                        CASE
                            WHEN a.kumStok <= e.eksikMiktar THEN a.ayStok
                            WHEN a.kumStok - a.ayStok < e.eksikMiktar THEN e.eksikMiktar - (a.kumStok - a.ayStok)
                            ELSE 0
                        END AS DECIMAL(18,4)
                    ) AS ayMiktar
                FROM Aylik a
                JOIN #eksikKalan e ON e.StkId = a.StkId
            )
            SELECT * INTO #aylikAlloc FROM Alloc WHERE ayMiktar > 0;

            IF OBJECT_ID('tempdb..#sabitFiyat', 'U') IS NOT NULL DROP TABLE #sabitFiyat;
            CREATE TABLE #sabitFiyat (
                StkId INT NOT NULL,
                BirimMaliyet DECIMAL(18,6) NOT NULL
            );

            -- ERP Devir Fiyatlari tablosundan fiyat al (satinalma serti ile)
            IF OBJECT_ID('dbo.FifoFallbackFiyatlari', 'U') IS NOT NULL
            BEGIN
                DECLARE @sqlErpDevir NVARCHAR(MAX) = N'
                INSERT INTO #sabitFiyat (StkId, BirimMaliyet)
                SELECT erp.StkId, erp.BirimMaliyet
                FROM dbo.FifoFallbackFiyatlari erp
                WHERE (@StkId IS NULL OR erp.StkId = @StkId)
                  AND (@fallbackSatinalmaSarti IS NULL OR erp.SatinalmaSarti = @fallbackSatinalmaSarti);';

                EXEC sp_executesql
                    @sqlErpDevir,
                    N'@StkId INT, @fallbackSatinalmaSarti VARCHAR(50)',
                    @StkId = @StkId,
                    @fallbackSatinalmaSarti = @fallbackSatinalmaSarti;
            END

            /* V2-07: fn_SonGecerliFiyat_Adv materialize
               Eski: OUTER APPLY row-by-row (urun*ay adet cagri)
               Yeni: TVF tarih basina 1 kez cagirilir → LEFT JOIN
               Kazanim: N_urun*N_ay → N_ay adet TVF cagri */
            IF OBJECT_ID('tempdb..#fiyatMaterialize', 'U') IS NOT NULL DROP TABLE #fiyatMaterialize;
            CREATE TABLE #fiyatMaterialize (
                StkId      INT            NOT NULL,
                ayBitis    DATE           NOT NULL,
                sonrakiNet DECIMAL(18,6)  NOT NULL,
                fFrmID     INT            NULL,
                fTarihSon  DATE           NULL,
                fhID       INT            NULL,
                CONSTRAINT PK_tmp_fiyatMat PRIMARY KEY (StkId, ayBitis)
            );

            DECLARE @matTarih DATE;
            DECLARE matCur CURSOR LOCAL FAST_FORWARD FOR
                SELECT DISTINCT ayBitis FROM #aylikAlloc ORDER BY ayBitis;
            OPEN matCur;
            FETCH NEXT FROM matCur INTO @matTarih;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                INSERT INTO #fiyatMaterialize (StkId, ayBitis, sonrakiNet, fFrmID, fTarihSon, fhID)
                SELECT f.fStkId, @matTarih, f.sonrakiNet, f.fFrmID, f.fTarihSon, f.fhID
                FROM (
                    SELECT
                        f.fStkId, f.sonrakiNet, f.fFrmID, f.fTarihSon, f.fhID,
                        ROW_NUMBER() OVER (
                            PARTITION BY f.fStkId
                            ORDER BY
                                CASE WHEN f.fFrmID = 9525 THEN 0 ELSE 1 END,
                                f.fTarihSon DESC,
                                f.fhID DESC
                        ) AS rn
                    FROM $(ErpDb).bkm.fn_SonGecerliFiyat_Adv(@matTarih, 1, 1, 1) f
                    WHERE f.fStkId IN (SELECT StkId FROM #aylikAlloc WHERE ayBitis = @matTarih)
                      AND f.sonrakiNet > 0
                      -- 14_V2 ile hizalandi (2026-06-06): stale fiyat KABUL edilir.
                      -- (Eski fTarihSon>=@matTarih reddi kaldirildi — iki SP ayni sonucu versin.)
                ) f WHERE f.rn = 1;
                FETCH NEXT FROM matCur INTO @matTarih;
            END
            CLOSE matCur; DEALLOCATE matCur;

            INSERT INTO #aylikKatman (StkId, ayBitis, ayMiktar, BirimMaliyet, Durum)
            SELECT
                a.StkId,
                a.ayBitis,
                a.ayMiktar,
                COALESCE(fm.sonrakiNet, sf.BirimMaliyet) AS BirimMaliyet,
                CASE
                    WHEN COALESCE(fm.sonrakiNet, sf.BirimMaliyet) IS NULL THEN 'FIYAT_YOK'
                    ELSE 'AYLIK_DEVIR'
                END AS Durum
            FROM #aylikAlloc a
            LEFT JOIN #fiyatMaterialize fm ON fm.StkId = a.StkId AND fm.ayBitis = a.ayBitis
            LEFT JOIN #sabitFiyat       sf ON sf.StkId = a.StkId;

            IF @sabitFallbackBirimMaliyet IS NOT NULL
            BEGIN
                UPDATE k
                SET
                    k.BirimMaliyet = @sabitFallbackBirimMaliyet,
                    k.Durum = 'SABIT_FIYAT_TAMAMLAMA'
                FROM #aylikKatman k
                WHERE k.Durum = 'FIYAT_YOK';
            END

            INSERT INTO dbo.FifoKatman
            (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
                 GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
            SELECT
                k.StkId, k.ayBitis, 'AYLIK_DEVIR', NULL, k.ayBitis, NULL,
                k.ayMiktar, k.ayMiktar, ISNULL(k.BirimMaliyet, 0), k.Durum
            FROM #aylikKatman k
            WHERE k.BirimMaliyet IS NOT NULL
              AND k.BirimMaliyet > 0;
        END

        DELETE FROM dbo.FifoSorunluStoklar
        WHERE EnvanterTarihi = @EnvanterTarihi
          AND (@StkId IS NULL OR StkId = @StkId);

        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT
            k.StkId, @EnvanterTarihi, SUM(k.ayMiktar), 'FIYAT_YOK',
            'Aylik devir katmaninda fiyat bulunamadi.'
        FROM #aylikKatman k
        WHERE k.Durum = 'FIYAT_YOK'
        GROUP BY k.StkId;

        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT
            k.StkId, @EnvanterTarihi, SUM(k.ayMiktar), 'SABIT_FIYAT_TAMAMLANDI',
            'Aylik devir katmani sabit fiyat ile tamamlandi. Fiyat=' +
            CONVERT(VARCHAR(30), @sabitFallbackBirimMaliyet)
        FROM #aylikKatman k
        WHERE k.Durum = 'SABIT_FIYAT_TAMAMLAMA'
        GROUP BY k.StkId;

        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT
            s.StkId, @EnvanterTarihi, s.StokMiktar, 'ALIS_YOK',
            'Bu urune belirtilen tarih araliginda hic alis bulunamadi.'
        FROM #stoklar s
        LEFT JOIN (SELECT DISTINCT StkId FROM #alislar) v ON v.StkId = s.StkId
        LEFT JOIN #merkezSon ms ON ms.StkId = s.StkId
        LEFT JOIN #sonGecerli sg ON sg.StkId = s.StkId
        LEFT JOIN (SELECT DISTINCT StkId FROM #aylikKatman) ak ON ak.StkId = s.StkId
        WHERE v.StkId IS NULL AND ms.StkId IS NULL AND sg.StkId IS NULL AND ak.StkId IS NULL;


        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT
            e.StkId, @EnvanterTarihi, e.StokMiktar, 'ALIS_YOK_MERKEZ_TAMAMLANDI',
            'Merkez depo (12) son alis fiyati ile tamamlandi.'
        FROM #eksiklar e
        JOIN #merkezSon ms ON ms.StkId = e.StkId;

        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT
            e.StkId, @EnvanterTarihi, e.StokMiktar, 'ALIS_YOK_SONGECERLI_TAMAMLANDI',
            'Son gecerli satin alma fiyati (sonrakiNet) ile tamamlandi.'
        FROM #eksiklar e
        JOIN #sonGecerli sg ON sg.StkId = e.StkId
        LEFT JOIN (SELECT DISTINCT StkId FROM #alislar) v ON v.StkId = e.StkId
        LEFT JOIN #merkezSon ms ON ms.StkId = e.StkId
        WHERE v.StkId IS NULL AND ms.StkId IS NULL;

        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT DISTINCT
            e.StkId, @EnvanterTarihi, e.StokMiktar, 'ALIS_EKSIK_TAMAMLANDI',
            'Eksik stok son alis fiyati ile otomatik tamamlandi.'
        FROM #eksiklar e
        WHERE e.eksikMiktar > 0 AND e.toplamAcilisMiktar > 0;

        /* MANUEL MALIYET OVERRIDE: kullanici elle girdigi birim maliyet hesaplanani EZER
           (ERP koli/qty hatasi vb. duzeltme). FifoManuelMaliyet en yuksek oncelikli kaynak.
           Bu run'da kurulan tum katmanlara (ACILIS/ACILIS_TAMAMLA/AYLIK_DEVIR) uygulanir.
           Ref: cost-anomali fix (2026-06-06). */
        UPDATE k SET k.BirimMaliyet = mm.BirimMaliyet
        FROM dbo.FifoKatman k
        CROSS APPLY (
            SELECT TOP 1 m.BirimMaliyet
            FROM dbo.FifoManuelMaliyet m
            WHERE m.StkId = k.StkId AND m.Aktif = 1
              AND m.GecerliBaslangic <= @EnvanterTarihi
              AND (m.GecerliBitis IS NULL OR m.GecerliBitis >= @EnvanterTarihi)
            ORDER BY m.GecerliBaslangic DESC, m.ManuelId DESC
        ) mm
        WHERE k.GirisTarihi <= @EnvanterTarihi
          AND (@StkId IS NULL OR k.StkId = @StkId);

        /* NET GUVENLIK AGI (invariant): acilis envanterine giren her StkId
           YA bir FifoKatman almali YA da bir sorun kaydi. Aylik-devir bloku
           atlanirsa (@atlamaAylikDevir=1) veya eslik/eksik kenar durumlarinda
           urun sessizce dusebiliyordu (ne katman ne FIYAT_YOK). Bu net dogrudan
           FifoKatman'a karsi dogrular — aylik-devir durumundan bagimsiz.
           Ref: sorunlu-urun-dedektif + sql-sp-reviewer CRIT-1 (2026-06-06). */
        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT s.StkId, @EnvanterTarihi, s.StokMiktar, 'FIYAT_YOK',
               'Acilis envanteri var; alis/merkez/sart/aylik-devir hicbiri katman kuramadi (net guvenlik agi).'
        FROM #stoklar s
        WHERE (@StkId IS NULL OR s.StkId = @StkId)
          AND NOT EXISTS (
              SELECT 1 FROM dbo.FifoKatman k
              WHERE k.StkId = s.StkId
                AND k.GirisTarihi BETWEEN @baslangicTarihi AND @EnvanterTarihi
          )
          AND NOT EXISTS (
              SELECT 1 FROM dbo.FifoSorunluStoklar fs
              WHERE fs.StkId = s.StkId AND fs.EnvanterTarihi = @EnvanterTarihi
                AND fs.SorunTipi IN ('FIYAT_YOK','ALIS_YOK')
          );

        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'TAMAMLANDI', NULL;

        /* Audit triggeri tekrar etkinlestir */
        IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'tr_fifo_StokMaliyetHavuzu_DegisimGunlugu' AND parent_id = OBJECT_ID('dbo.FifoKatman'))
            ALTER TABLE dbo.FifoKatman ENABLE TRIGGER tr_fifo_StokMaliyetHavuzu_DegisimGunlugu;
        ELSE IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'tr_fifo_StokMaliyetHavuzu_Audit' AND parent_id = OBJECT_ID('dbo.FifoKatman'))
            ALTER TABLE dbo.FifoKatman ENABLE TRIGGER tr_fifo_StokMaliyetHavuzu_Audit;

        COMMIT TRANSACTION;
        
        PRINT 'Acilis stoku basariyla olusturuldu. Tarih: ' + 
              CONVERT(VARCHAR(10), @EnvanterTarihi, 120);
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        /* Hata Durumunda rollback sonrasinda triggeri tekrar etkinlestir */
        IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'tr_fifo_StokMaliyetHavuzu_DegisimGunlugu' AND parent_id = OBJECT_ID('dbo.FifoKatman'))
            ALTER TABLE dbo.FifoKatman ENABLE TRIGGER tr_fifo_StokMaliyetHavuzu_DegisimGunlugu;
        ELSE IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'tr_fifo_StokMaliyetHavuzu_Audit' AND parent_id = OBJECT_ID('dbo.FifoKatman'))
            ALTER TABLE dbo.FifoKatman ENABLE TRIGGER tr_fifo_StokMaliyetHavuzu_Audit;
            
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @runMessage VARCHAR(500) = SUBSTRING(CONVERT(VARCHAR(500), @ErrorMessage), 1, 500);

        IF @IslemId IS NOT NULL AND @AdimKodu IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz
                @IslemId = @IslemId,
                @AdimKodu = @AdimKodu,
                @AdimAdi = @AdimAdi,
                @SiraNo = @SiraNo,
                @Durum = 'HATA',
                @Mesaj = @runMessage;
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        DECLARE @ErrorLine INT = ERROR_LINE();
        
        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        VALUES (0, @EnvanterTarihi, 0, 'PROSEDUR_HATASI', 
                'sp_Fifo_AcilisMaliyetlendir - Satir: ' + CAST(@ErrorLine AS VARCHAR(10)) + 
                ' - ' + @ErrorMessage);
        
        THROW;
    END CATCH
END
GO

PRINT 'sp_Fifo_AcilisMaliyetlendir proseduru olusturuldu';
GO

PRINT '';

PRINT '3/6 - Alis katmanlari proseduru olusturuluyor...';
GO

-- =============================================================
-- ALIS KATMANLARI PROSEDURU - dbo.sp_Fifo_AlisKatmanEkle
-- SADECE FATURA: fat + fatAyr (irs/irsAyr yok)
-- =============================================================

CREATE OR ALTER PROCEDURE dbo.sp_Fifo_AlisKatmanEkle
(
    @baslangicTarihi DATE,
    @bitisTarihi DATE,
    @StkId INT = NULL,
    @IslemId UNIQUEIDENTIFIER = NULL
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
            a.ehStkId AS StkId,
            f.eTarihS AS GirisTarihi,
            f.eNo     AS BelgeNo,
            f.eTarihS AS BelgeTarihi,
            f.eFirma  AS FirmaId,
            SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS Miktar,
            SUM(CONVERT(DECIMAL(18,4),
                CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END
            )) AS netTutar
        INTO #alislar
        FROM $(ErpDb).dbo.fatAyr a WITH(NOLOCK)
        JOIN $(ErpDb).dbo.fat f WITH(NOLOCK)
            ON f.eID = a.ehID
        WHERE a.ehAdetN <> 0
          AND f.eTarihS >  CONVERT(smalldatetime, @baslangicTarihi)
          AND f.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @bitisTarihi))
          AND f.eTip IN (0, 2)
          AND (@StkId IS NULL OR a.ehStkId = @StkId)
        GROUP BY a.ehStkId, f.eTarihS, f.eID, f.eNo, f.eFirma
        HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;

        /* Birim maliyet hesapla */
        ALTER TABLE #alislar ADD BirimMaliyet DECIMAL(18,6);

        UPDATE #alislar
        SET BirimMaliyet = CASE WHEN Miktar = 0 THEN 0 ELSE netTutar / Miktar END;

        -- Constraint uyumsuz (iade/ters/fiyatsiz) satirlari ALIS havuzuna yazma.
        DELETE FROM #alislar
        WHERE Miktar <= 0
           OR netTutar <= 0
           OR BirimMaliyet <= 0;

        /* Aync tarih araligindaki eski ALIS katmanlarini sil */
        DELETE FROM dbo.FifoKatman
        WHERE KaynakTip = 'ALIS'
          AND GirisTarihi >  @baslangicTarihi
          AND GirisTarihi <= @bitisTarihi
          AND (@StkId IS NULL OR StkId = @StkId);

        /* Yeni ALIS katmanlarini havuza yaz */
        INSERT INTO dbo.FifoKatman
            (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
             GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
        SELECT
            StkId, GirisTarihi, 'ALIS', BelgeNo, BelgeTarihi, FirmaId,
            Miktar, Miktar, BirimMaliyet, 'NORMAL'
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

PRINT 'sp_Fifo_AlisKatmanEkle proseduru olusturuldu';
GO

PRINT '';

PRINT '4/6 - FIFO cikis proseduru olusturuluyor...';
GO

-- =============================================================
-- FIFO CIKIS PROSEDURU - dbo.sp_Fifo_CikisMaliyetle
-- POS iade mantigi, KalanMiktar guncelleme, yetersiz stok kontrolu ile
-- =============================================================

CREATE OR ALTER PROCEDURE dbo.sp_Fifo_CikisMaliyetle
(
    @satisBaslangic DATE,
    @satisBitis DATE,
    @StkId INT = NULL,
    @IslemId UNIQUEIDENTIFIER = NULL
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

        /* RERUN-SAFE (V2): Ayni donem daha once hesaplandiysa eski cikis tuketimini havuza geri yukle.
           Not: Gec donemler hesaplandiysa gecmise donuk rerun yine risklidir; son/cari donem rerun hedeflenir. */
        UPDATE h
        SET h.KalanMiktar = h.KalanMiktar + d.toplamCikis
        FROM dbo.FifoKatman h
        JOIN (
            SELECT c.KatmanId, SUM(c.Miktar) AS toplamCikis
            FROM dbo.FifoCikisDetay c
            WHERE c.HareketTarihi >= @satisBaslangic
              AND c.HareketTarihi <= @satisBitis
              AND (@StkId IS NULL OR c.StkId = @StkId)
            GROUP BY c.KatmanId
        ) d ON d.KatmanId = h.KatmanId;

        -- RERUN-SAFE: Onceki calismadan kalan IADE katmanlarini sil (rerun'da birikmemeli)
        DELETE FROM dbo.FifoKatman
        WHERE KaynakTip = 'IADE'
          AND GirisTarihi >= @satisBaslangic
          AND GirisTarihi <= @satisBitis
          AND (@StkId IS NULL OR StkId = @StkId);

        /* 1) Havuzdaki tum katmanlari al */
        IF OBJECT_ID('tempdb..#katman', 'U') IS NOT NULL DROP TABLE #katman;

        SELECT
            h.KatmanId AS KatmanId, h.StkId, h.GirisTarihi,
            ISNULL(h.BelgeTarihi, h.GirisTarihi) AS fifoSiraTarihi,
            h.BelgeNo AS girisBelgeNo,
            TRY_CONVERT(BIGINT, h.BelgeNo) AS fifoSiraBelgeNoNum,
            h.KalanMiktar AS GirisMiktar,
            h.BirimMaliyet
        INTO #katman
        FROM dbo.FifoKatman h
        WHERE h.GirisTarihi <= @satisBitis
          -- Only include sources that are actually written by this deployment.
          AND h.KaynakTip IN ('ACILIS','ACILIS_TAMAMLA','ALIS','AYLIK_DEVIR','SENTETIK_ALIS','IADE')
          AND h.KalanMiktar > 0
          AND (@StkId IS NULL OR h.StkId = @StkId);

        CREATE INDEX IX_tmp_katman_StkId
            ON #katman(StkId, fifoSiraTarihi, fifoSiraBelgeNoNum, girisBelgeNo, KatmanId);

        /* 2) Satis hareketlerini al - POS IADE MANTIGI ILE */
        IF OBJECT_ID('tempdb..#satislar', 'U') IS NOT NULL DROP TABLE #satislar;

        SELECT
            ID = IDENTITY(INT,1,1),
            h.ehstkID AS StkId,
            h.ehMekan AS MekanId,
            CAST(h.ehTrhS AS DATE) AS satisTarihi,
            netMiktar = SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)),
            netTutar  = SUM(CONVERT(DECIMAL(18,4), h.ehTutarN))
        INTO #satislar
        FROM $(ErpDb).dbo.irsHrk h
        WHERE h.ehTip IN (1,4,5,100,101)
          AND h.ehMekan IN (1, 12, 4477, 4478)
          AND h.ehTrhS >= CONVERT(smalldatetime, @satisBaslangic)
          AND h.ehTrhS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @satisBitis))
          AND (@StkId IS NULL OR h.ehstkID = @StkId)
        GROUP BY h.ehstkID, h.ehMekan, CAST(h.ehTrhS AS DATE);

        CREATE INDEX IX_tmp_satislar_StkId
            ON #satislar(StkId, satisTarihi, MekanId, ID);

        /* 3) Katmanlar icin kumulatif */
        IF OBJECT_ID('tempdb..#katmanCum', 'U') IS NOT NULL DROP TABLE #katmanCum;

        SELECT
            k.KatmanId, k.StkId, k.GirisTarihi, k.fifoSiraTarihi, k.girisBelgeNo, k.fifoSiraBelgeNoNum,
            k.GirisMiktar, k.BirimMaliyet,
            layerCumEnd = SUM(k.GirisMiktar) OVER (
                PARTITION BY k.StkId
                ORDER BY
                    k.fifoSiraTarihi,
                    CASE WHEN k.fifoSiraBelgeNoNum IS NULL THEN 1 ELSE 0 END,
                    k.fifoSiraBelgeNoNum,
                    k.girisBelgeNo,
                    k.KatmanId
            ),
            layerCumStart = SUM(k.GirisMiktar) OVER (
                PARTITION BY k.StkId
                ORDER BY
                    k.fifoSiraTarihi,
                    CASE WHEN k.fifoSiraBelgeNoNum IS NULL THEN 1 ELSE 0 END,
                    k.fifoSiraBelgeNoNum,
                    k.girisBelgeNo,
                    k.KatmanId
            ) - k.GirisMiktar
        INTO #katmanCum
        FROM #katman k;

        CREATE INDEX IX_tmp_katmanCum_StkId
            ON #katmanCum(StkId, layerCumStart, layerCumEnd);

        /* 4) Satislar icin kumulatif (sadece net satis = netMiktar < 0) */
        IF OBJECT_ID('tempdb..#satisCum', 'U') IS NOT NULL DROP TABLE #satisCum;

        SELECT
            s.ID AS satisID, s.StkId, s.MekanId, s.satisTarihi,
            s.netMiktar AS Miktar,
            satisCumEnd = SUM(ABS(s.netMiktar)) OVER (
                PARTITION BY s.StkId
                ORDER BY s.satisTarihi, s.MekanId, s.ID
            ),
            satisCumStart = SUM(ABS(s.netMiktar)) OVER (
                PARTITION BY s.StkId
                ORDER BY s.satisTarihi, s.MekanId, s.ID
            ) - ABS(s.netMiktar)
        INTO #satisCum
        FROM #satislar s
        WHERE s.netMiktar < 0;  -- iade (netMiktar > 0) FIFO kesisimine girmiyor

        CREATE INDEX IX_tmp_satisCum_StkId
            ON #satisCum(StkId, satisCumStart, satisCumEnd);

        /* 5) FIFO kesisim */
        IF OBJECT_ID('tempdb..#cikisDetay', 'U') IS NOT NULL DROP TABLE #cikisDetay;

        SELECT
            c.StkId, c.MekanId AS satisMekanId, c.satisTarihi, c.satisID,
            c.Miktar AS satirNetMiktar,
            l.KatmanId, l.GirisTarihi AS KatmanTarihi,
            l.girisBelgeNo, l.BirimMaliyet,
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
          ON l.StkId = c.StkId
         AND l.layerCumEnd > c.satisCumStart
         AND c.satisCumEnd > l.layerCumStart;

        DELETE FROM #cikisDetay WHERE cikisMiktar <= 0;

        /* 6a) IADE KATMANI AC (netMiktar > 0 = stok geri donuyor)
               Mantik: en son satisten geriye FIFO gibi, iade miktarini karsilayana kadar.
               Her segment icin ayri FifoKatman satirı (o segmentin BirimMaliyet'i). */

        -- Iade hareketleri (gun+mekan bazinda net pozitif)
        IF OBJECT_ID('tempdb..#iade_hrk', 'U') IS NOT NULL DROP TABLE #iade_hrk;
        SELECT
            ID        = IDENTITY(INT,1,1),
            s.StkId,
            s.MekanId,
            iadeTarihi = s.satisTarihi,
            iadeMiktar = s.netMiktar
        INTO #iade_hrk
        FROM #satislar s
        WHERE s.netMiktar > 0;

        -- Iade kumulatif (StkId bazinda)
        IF OBJECT_ID('tempdb..#iade_cum', 'U') IS NOT NULL DROP TABLE #iade_cum;
        SELECT
            i.ID, i.StkId, i.MekanId, i.iadeTarihi, i.iadeMiktar,
            iadeCumEnd   = SUM(i.iadeMiktar) OVER (PARTITION BY i.StkId ORDER BY i.iadeTarihi, i.MekanId, i.ID),
            iadeCumStart = SUM(i.iadeMiktar) OVER (PARTITION BY i.StkId ORDER BY i.iadeTarihi, i.MekanId, i.ID) - i.iadeMiktar
        INTO #iade_cum
        FROM #iade_hrk i;

        -- Satis cikislari: bu SP'nin #cikisDetay'indan al (FifoCikisDetay henuz yazilmamis olabilir)
        -- Her iade icin kendi tarihine kadar, en yeniden eskiye, kumulatif
        IF OBJECT_ID('tempdb..#satis_katman', 'U') IS NOT NULL DROP TABLE #satis_katman;
        SELECT
            ic.ID AS iadeID,
            cd.StkId, cd.satisTarihi AS HareketTarihi, cd.BirimMaliyet,
            cd.cikisMiktar AS Miktar,
            layerCumEnd   = SUM(cd.cikisMiktar) OVER (
                PARTITION BY cd.StkId, ic.ID
                ORDER BY cd.satisTarihi DESC, cd.satisID DESC, cd.KatmanId DESC),
            layerCumStart = SUM(cd.cikisMiktar) OVER (
                PARTITION BY cd.StkId, ic.ID
                ORDER BY cd.satisTarihi DESC, cd.satisID DESC, cd.KatmanId DESC
            ) - cd.cikisMiktar
        INTO #satis_katman
        FROM #iade_hrk ic
        JOIN #cikisDetay cd
          ON cd.StkId        = ic.StkId
         AND cd.satisTarihi <= ic.iadeTarihi;

        -- FIFO kesisim: iade miktari <-> satis katmanlari (en yeniden, tarih filtreli)
        IF OBJECT_ID('tempdb..#iade_kesisim', 'U') IS NOT NULL DROP TABLE #iade_kesisim;
        SELECT
            ic.StkId, ic.MekanId, ic.iadeTarihi,
            sk.BirimMaliyet,
            kesisenMiktar = CAST(
                CASE
                    WHEN sk.layerCumEnd <= ic.iadeCumStart
                      OR ic.iadeCumEnd <= sk.layerCumStart THEN 0
                    ELSE
                        (CASE WHEN sk.layerCumEnd < ic.iadeCumEnd
                              THEN sk.layerCumEnd ELSE ic.iadeCumEnd END)
                      - (CASE WHEN sk.layerCumStart > ic.iadeCumStart
                              THEN sk.layerCumStart ELSE ic.iadeCumStart END)
                END AS DECIMAL(18,4))
        INTO #iade_kesisim
        FROM #iade_cum ic
        JOIN #satis_katman sk
          ON sk.StkId   = ic.StkId
         AND sk.iadeID  = ic.ID
         AND sk.layerCumEnd  > ic.iadeCumStart
         AND ic.iadeCumEnd   > sk.layerCumStart;

        DELETE FROM #iade_kesisim WHERE kesisenMiktar <= 0;

        -- Karsilanamayan iade miktari icin fallback (sifir maliyet yerine 0 koyma, log icin)
        -- TODO: FifoSorunluStoklar'a 'IADE_KARSILANAMADI' eklenebilir

        INSERT INTO dbo.FifoKatman
            (StkId, KaynakTip, GirisTarihi, BelgeTarihi, BelgeNo,
             GirisMiktar, KalanMiktar, BirimMaliyet)
        SELECT
            ik.StkId,
            'IADE',
            ik.iadeTarihi,
            ik.iadeTarihi,
            NULL,
            ik.kesisenMiktar,
            ik.kesisenMiktar,
            ik.BirimMaliyet
        FROM #iade_kesisim ik;

        /* 6) YETERSIZ STOK KONTROLU */
        DELETE FROM dbo.FifoSorunluStoklar
        WHERE SorunTipi = 'STOK_YETERSIZ'
          AND EnvanterTarihi >= @satisBaslangic
          AND EnvanterTarihi <= @satisBitis
          AND (@StkId IS NULL OR StkId = @StkId);

        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT
            s.StkId,
            @satisBitis,
            s.toplamSatisMiktar - ISNULL(d.toplamKarsilananMiktar, 0) AS eksikMiktar,
            'STOK_YETERSIZ',
            'Donem satis Miktari (' + CAST(s.toplamSatisMiktar AS VARCHAR(20)) +
            ') mevcut katmanlarla karsilanan Miktari (' + CAST(ISNULL(d.toplamKarsilananMiktar, 0) AS VARCHAR(20)) +
            ') asiyor.'
        FROM (
            SELECT
                StkId,
                SUM(ABS(netMiktar)) AS toplamSatisMiktar
            FROM #satislar
            WHERE netMiktar <> 0
            GROUP BY StkId
        ) s
        LEFT JOIN (
            SELECT
                StkId,
                SUM(ABS(cikisMiktar)) AS toplamKarsilananMiktar
            FROM #cikisDetay
            GROUP BY StkId
        ) d ON d.StkId = s.StkId
        WHERE s.toplamSatisMiktar > ISNULL(d.toplamKarsilananMiktar, 0);

        /* 7) SONUCLARI TABLOYA YAZ */
        DELETE FROM dbo.FifoCikisDetay
        WHERE HareketTarihi >= @satisBaslangic
          AND HareketTarihi <= @satisBitis
          AND (@StkId IS NULL OR StkId = @StkId);

        INSERT INTO dbo.FifoCikisDetay
            (StkId, HareketTarihi, HareketTipi, MekanId, KatmanId,
             KatmanTarihi, KatmanBelgeNo, Miktar, BirimMaliyet, SatisTutar)
        SELECT
            d.StkId, d.satisTarihi,
            'SATIS',
            d.satisMekanId,
            d.KatmanId, d.KatmanTarihi, d.girisBelgeNo,
            d.cikisMiktar, d.BirimMaliyet,
            /* Gunun satis geliri (irsHrk ehTutarN) cikis segmentine miktar oraninda dagitilir */
            CAST(d.cikisMiktar * (s.netTutar / NULLIF(ABS(s.netMiktar), 0)) AS DECIMAL(18,4))
        FROM #cikisDetay d
        JOIN #satislar s ON s.ID = d.satisID;

        /* 8) KATMAN KALAN MIKTARLARINI GUNCELLE */
        UPDATE h
        SET h.KalanMiktar = h.KalanMiktar - d.toplamCikis
        FROM dbo.FifoKatman h
        JOIN (
            SELECT KatmanId, SUM(ABS(cikisMiktar)) AS toplamCikis
            FROM #cikisDetay
            GROUP BY KatmanId
        ) d ON d.KatmanId = h.KatmanId
        WHERE h.KalanMiktar > 0;

        COMMIT TRANSACTION;
        
        SELECT
            StkId, HareketTarihi, HareketTipi, MekanId, KatmanId,
            KatmanTarihi, KatmanBelgeNo, Miktar, BirimMaliyet, CikisTutar, SatisTutar
        FROM dbo.FifoCikisDetay
        WHERE HareketTarihi >= @satisBaslangic
          AND HareketTarihi <= @satisBitis
          AND (@StkId IS NULL OR StkId = @StkId)
        ORDER BY StkId, HareketTarihi, MekanId, KatmanTarihi, KatmanId;
        
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

PRINT 'sp_Fifo_CikisMaliyetle proseduru olusturuldu';
GO

PRINT '';

PRINT '5/6 - Toplu calistirma proseduru olusturuluyor...';
GO

-- =============================================================
-- TOPLU FIFO CALISTIRMA PROSEDURU
-- Amac: Manuel ve job calistirmalari ayni SP uzerinden yapmak
-- Not: Acilis/aylik ayri izleme icin yeni wrapper'lar tercih edilir:
--      sp_Fifo_AcilisCalistir / sp_Fifo_AylikCalistir / sp_Fifo_AylikRutinFull
-- =============================================================


CREATE OR ALTER PROCEDURE dbo.sp_MaliyetAdimYaz
(
    @IslemId UNIQUEIDENTIFIER,
    @AdimKodu VARCHAR(50),
    @AdimAdi VARCHAR(100),
    @SiraNo INT,
    @Durum VARCHAR(20),
    @Mesaj VARCHAR(500) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @IslemId IS NULL OR @AdimKodu IS NULL
        RETURN;

    -- FK (MaliyetIslemAdim -> MaliyetIslem) icin parent kayit yoksa otomatik olustur.
    IF NOT EXISTS (SELECT 1 FROM dbo.MaliyetIslem WHERE IslemId = @IslemId)
    BEGIN
        INSERT INTO dbo.MaliyetIslem
            (IslemId, IslemAdi, Durum, Baslangic, Bitis, Aciklama)
        VALUES
            (
                @IslemId,
                'MANUEL',
                CASE
                    WHEN @Durum IN ('TAMAMLANDI', 'HATA', 'ATLANDI') THEN @Durum
                    ELSE 'BEKLIYOR'
                END,
                GETDATE(),
                CASE WHEN @Durum IN ('TAMAMLANDI', 'HATA', 'ATLANDI') THEN GETDATE() ELSE NULL END,
                NULL
            );
    END

    IF EXISTS (SELECT 1 FROM dbo.MaliyetIslemAdim WHERE IslemId = @IslemId AND AdimKodu = @AdimKodu)
    BEGIN
        UPDATE dbo.MaliyetIslemAdim
        SET Durum = @Durum,
            AdimAdi = @AdimAdi,
            SiraNo = @SiraNo,
            Mesaj = @Mesaj,
            Baslangic = CASE
                WHEN @Durum IN ('CALISIYOR','TAMAMLANDI','HATA','ATLANDI') AND Baslangic IS NULL THEN GETDATE()
                ELSE Baslangic
            END,
            Bitis = CASE
                WHEN @Durum IN ('TAMAMLANDI','HATA','ATLANDI') THEN GETDATE()
                ELSE Bitis
            END,
            Guncelleme = GETDATE()
        WHERE IslemId = @IslemId AND AdimKodu = @AdimKodu;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.MaliyetIslemAdim
            (IslemId, AdimKodu, AdimAdi, SiraNo, Durum, Mesaj, Baslangic, Bitis)
        VALUES
            (@IslemId, @AdimKodu, @AdimAdi, @SiraNo, @Durum, @Mesaj,
             CASE WHEN @Durum IN ('CALISIYOR','TAMAMLANDI','HATA','ATLANDI') THEN GETDATE() ELSE NULL END,
             CASE WHEN @Durum IN ('TAMAMLANDI','HATA','ATLANDI') THEN GETDATE() ELSE NULL END);
    END

    /* Ust kayit durumunu adimlara gore senkron tut */
    DECLARE @UstDurum NVARCHAR(30) = 'BEKLIYOR';

    IF EXISTS (
        SELECT 1
        FROM dbo.MaliyetIslemAdim
        WHERE IslemId = @IslemId
          AND Durum = 'HATA'
    )
        SET @UstDurum = 'HATA';
    ELSE IF EXISTS (
        SELECT 1
        FROM dbo.MaliyetIslemAdim
        WHERE IslemId = @IslemId
          AND Durum = 'CALISIYOR'
    )
        SET @UstDurum = 'CALISIYOR';
    ELSE IF EXISTS (
        SELECT 1
        FROM dbo.MaliyetIslemAdim
        WHERE IslemId = @IslemId
          AND Durum IN ('TAMAMLANDI', 'ATLANDI')
    )
        SET @UstDurum = 'TAMAMLANDI';

    UPDATE dbo.MaliyetIslem
    SET Durum = @UstDurum,
        Bitis = CASE
            WHEN @UstDurum IN ('TAMAMLANDI', 'HATA') THEN ISNULL(Bitis, GETDATE())
            ELSE NULL
        END,
        Aciklama = CASE
            WHEN @Durum = 'HATA' AND @Mesaj IS NOT NULL THEN @Mesaj
            ELSE Aciklama
        END
    WHERE IslemId = @IslemId;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_Fifo_Calistir
(
    @EnvanterTarihi  DATE = NULL,
    @alisBaslangic   DATE = NULL,
    @alisBitis       DATE = NULL,
    @satisBaslangic  DATE = NULL,
    @satisBitis      DATE = NULL,
    @StkId           INT = NULL,
    @IslemId           UNIQUEIDENTIFIER = NULL,
    @calistirAcilis  BIT  = 0,
    @calistirAlis    BIT  = 1,
    @calistirCikis   BIT  = 1,
    @fallbackSatinalmaSarti  VARCHAR(50) = NULL,  -- sadece acilis fallback fiyatlama icin (calistirAcilis=1)
    @sabitFallbackBirimMaliyet DECIMAL(18,6) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @AdimKodu VARCHAR(50) = NULL;
    DECLARE @AdimAdi VARCHAR(100) = NULL;
    DECLARE @SiraNo INT = NULL;

    IF ISNULL(@calistirAcilis, 0) = 0
       AND ISNULL(@calistirAlis, 0) = 0
       AND ISNULL(@calistirCikis, 0) = 0
    BEGIN
        RAISERROR('En az bir calistirma adimi secilmelidir (Acilis/Alis/Cikis).', 16, 1);
        RETURN;
    END

    IF @sabitFallbackBirimMaliyet IS NOT NULL AND @sabitFallbackBirimMaliyet <= 0
    BEGIN
        RAISERROR('Sabit fallback birim maliyet 0''dan buyuk olmali.', 16, 1);
        RETURN;
    END

    IF @calistirAcilis = 1 AND @EnvanterTarihi IS NULL
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
            EXEC dbo.sp_Fifo_AcilisMaliyetlendir
                @EnvanterTarihi = @EnvanterTarihi,
                @StkId = @StkId,
                @IslemId = @IslemId,
                @fallbackSatinalmaSarti = @fallbackSatinalmaSarti,
                @sabitFallbackBirimMaliyet = @sabitFallbackBirimMaliyet;
        END

        /* RERUN-SAFE: ALIS katmanlari silinmeden ONCE donem cikislarini geri al + sil.
           Yoksa sp_Fifo_AlisKatmanEkle'nin "DELETE FROM FifoKatman WHERE KaynakTip='ALIS'"
           ifadesi, onceki run'in FifoCikisDetay referanslarina takilir
           (FK_FifoCikisDetay_FifoKatman) ve urun atlanir. Alis(+)->Satis(-) sirasi korunur. */
        IF @calistirCikis = 1
        BEGIN
            UPDATE h SET h.KalanMiktar = h.KalanMiktar + d.toplamCikis
            FROM dbo.FifoKatman h
            JOIN (
                SELECT c.KatmanId, SUM(c.Miktar) AS toplamCikis
                FROM dbo.FifoCikisDetay c
                WHERE c.HareketTarihi >= @satisBaslangic
                  AND c.HareketTarihi <= @satisBitis
                  AND (@StkId IS NULL OR c.StkId = @StkId)
                GROUP BY c.KatmanId
            ) d ON d.KatmanId = h.KatmanId;

            DELETE FROM dbo.FifoCikisDetay
            WHERE HareketTarihi >= @satisBaslangic
              AND HareketTarihi <= @satisBitis
              AND (@StkId IS NULL OR StkId = @StkId);
        END

        IF @calistirAlis = 1
        BEGIN
            SET @AdimKodu = 'rutin_alis';
            SET @AdimAdi = 'Alis katman';
            SET @SiraNo = 110;
            IF @IslemId IS NOT NULL
                EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'CALISIYOR', NULL;

            EXEC dbo.sp_Fifo_AlisKatmanEkle
                @baslangicTarihi = @alisBaslangic,
                @bitisTarihi = @alisBitis,
                @StkId = @StkId,
                @IslemId = @IslemId;

            IF @IslemId IS NOT NULL
                EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'TAMAMLANDI', NULL;
        END
        ELSE IF @IslemId IS NOT NULL AND @calistirCikis = 1
        BEGIN
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, 'rutin_alis', 'Alis katman', 110, 'ATLANDI', 'CalistirAlis=0';
        END

        IF @calistirCikis = 1
        BEGIN
            SET @AdimKodu = 'rutin_cikis';
            SET @AdimAdi = 'FIFO cikis';
            SET @SiraNo = 120;
            IF @IslemId IS NOT NULL
                EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'CALISIYOR', NULL;

            EXEC dbo.sp_Fifo_CikisMaliyetle
                @satisBaslangic = @satisBaslangic,
                @satisBitis = @satisBitis,
                @StkId = @StkId,
                @IslemId = @IslemId;

            IF @IslemId IS NOT NULL
                EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'TAMAMLANDI', NULL;

            SET @AdimKodu = 'rutin_rapor';
            SET @AdimAdi = 'Sonuc hazirligi';
            SET @SiraNo = 130;
            IF @IslemId IS NOT NULL
            BEGIN
                EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'CALISIYOR', NULL;
                EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'TAMAMLANDI', NULL;
            END
        END
        ELSE IF @IslemId IS NOT NULL AND @calistirAlis = 1
        BEGIN
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, 'rutin_cikis', 'FIFO cikis', 120, 'ATLANDI', 'CalistirCikis=0';
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, 'rutin_rapor', 'Sonuc hazirligi', 130, 'ATLANDI', 'CalistirCikis=0';
        END
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @runMessage VARCHAR(500) = SUBSTRING(CONVERT(VARCHAR(500), @ErrorMessage), 1, 500);
        IF @IslemId IS NOT NULL AND @AdimKodu IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz
                @IslemId = @IslemId,
                @AdimKodu = @AdimKodu,
                @AdimAdi = @AdimAdi,
                @SiraNo = @SiraNo,
                @Durum = 'HATA',
                @Mesaj = @runMessage;
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        THROW;
    END CATCH
END
GO

PRINT 'sp_Fifo_Calistir proseduru olusturuldu';
GO


-- =============================================================
-- AYLIK CALISTIRMA WRAPPER - dbo.sp_Fifo_AylikCalistir
-- Aylik alis+cikis islemlerini ayri run/calismayla izlemek icin
-- =============================================================

CREATE OR ALTER PROCEDURE dbo.sp_Fifo_AylikCalistir
(
    @yil INT,
    @ay INT,
    @StkId INT = NULL,
    @IslemId UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @yil IS NULL OR @ay IS NULL OR @ay NOT BETWEEN 1 AND 12
    BEGIN
        RAISERROR('Gecersiz yil/ay parametresi.', 16, 1);
        RETURN;
    END

    DECLARE @baslangic DATE = DATEFROMPARTS(@yil, @ay, 1);
    DECLARE @bitis DATE = EOMONTH(@baslangic);

    EXEC dbo.sp_Fifo_Calistir
        @alisBaslangic = @baslangic,
        @alisBitis = @bitis,
        @satisBaslangic = @baslangic,
        @satisBitis = @bitis,
        @StkId = @StkId,
        @IslemId = @IslemId,
        @calistirAcilis = 0,
        @calistirAlis = 1,
        @calistirCikis = 1;
END
GO

PRINT 'sp_Fifo_AylikCalistir proseduru olusturuldu';
GO

GO
PRINT '======== 04 Sentetik Fallback ========';
GO
USE [$(MaliyetDb)];
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
-- V2 EKLENTI: SENTETIK GIRIS (HAYALI EVRAK) KATMANI
-- Amac: STOK_YETERSIZ sorunlarindan sentetik maliyet katmani uretmek
-- Not: Bu SP FIFO cikisi otomatik tekrar hesaplamaz.
-- =============================================================

CREATE OR ALTER PROCEDURE dbo.sp_Fifo_SentetikKatmanOlustur
(
    @SorunTarihi DATE,                              -- genelde ay sonu (satis bitis)
    @GirisTarihi DATE = NULL,                       -- sentetik katman tarihi (NULL => @SorunTarihi)
    @SentetikSatinalmaSarti VARCHAR(50) = NULL,     -- sadece sentetik fallback fiyat secimi icin
    @StkId INT = NULL,
    @SabitFallbackBirimMaliyet DECIMAL(18,6) = NULL,
    @DryRun BIT = 0
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @SorunTarihi IS NULL
    BEGIN
        RAISERROR('Sorun tarihi bos olamaz.', 16, 1);
        RETURN;
    END

    IF @SabitFallbackBirimMaliyet IS NOT NULL AND @SabitFallbackBirimMaliyet <= 0
    BEGIN
        RAISERROR('Sabit fallback birim maliyet 0''dan buyuk olmali.', 16, 1);
        RETURN;
    END

    IF @GirisTarihi IS NULL
        SET @GirisTarihi = @SorunTarihi;

    IF OBJECT_ID('tempdb..#eksik', 'U') IS NOT NULL DROP TABLE #eksik;
    IF OBJECT_ID('tempdb..#sartFiyat', 'U') IS NOT NULL DROP TABLE #sartFiyat;
    IF OBJECT_ID('tempdb..#sentetik', 'U') IS NOT NULL DROP TABLE #sentetik;

    SELECT
        s.StkId,
        SUM(CASE WHEN s.StokMiktar > 0 THEN s.StokMiktar ELSE 0 END) AS eksikMiktar
    INTO #eksik
    FROM dbo.FifoSorunluStoklar s
    WHERE s.SorunTipi = 'STOK_YETERSIZ'
      AND s.EnvanterTarihi = @SorunTarihi
      AND (@StkId IS NULL OR s.StkId = @StkId)
    GROUP BY s.StkId
    HAVING SUM(CASE WHEN s.StokMiktar > 0 THEN s.StokMiktar ELSE 0 END) > 0;

    IF NOT EXISTS (SELECT 1 FROM #eksik)
    BEGIN
        IF @DryRun = 1
        BEGIN
            SELECT
                CAST(NULL AS INT) AS StkId,
                CAST(NULL AS DATE) AS GirisTarihi,
                CAST(NULL AS DECIMAL(18,4)) AS GirisMiktar,
                CAST(NULL AS DECIMAL(18,6)) AS BirimMaliyet,
                CAST(NULL AS VARCHAR(20)) AS Durum,
                CAST(NULL AS VARCHAR(50)) AS SatinalmaSarti
            WHERE 1 = 0;
        END
        PRINT 'Sentetik katman icin STOK_YETERSIZ kaydi bulunamadi.';
        RETURN;
    END

    ;WITH FiyatKaynak AS (
        SELECT
            e.StkId,
            erp.SatinalmaSarti,
            erp.BirimMaliyet,
            ROW_NUMBER() OVER (
                PARTITION BY e.StkId
                ORDER BY
                    CASE
                        WHEN @SentetikSatinalmaSarti IS NOT NULL AND erp.SatinalmaSarti = @SentetikSatinalmaSarti THEN 0
                        ELSE 1
                    END,
                    erp.SatinalmaSarti
            ) AS rn
        FROM #eksik e
        LEFT JOIN dbo.FifoFallbackFiyatlari erp
            ON erp.StkId = e.StkId
           AND (@SentetikSatinalmaSarti IS NULL OR erp.SatinalmaSarti = @SentetikSatinalmaSarti)
    )
    SELECT
        StkId,
        SatinalmaSarti,
        BirimMaliyet
    INTO #sartFiyat
    FROM FiyatKaynak
    WHERE rn = 1;

    SELECT
        e.StkId,
        @GirisTarihi AS GirisTarihi,
        CAST(e.eksikMiktar AS DECIMAL(18,4)) AS GirisMiktar,
        CAST(e.eksikMiktar AS DECIMAL(18,4)) AS KalanMiktar,
        CAST(COALESCE(f.BirimMaliyet, @SabitFallbackBirimMaliyet) AS DECIMAL(18,6)) AS BirimMaliyet,
        CAST(
            CASE
                WHEN f.BirimMaliyet IS NOT NULL THEN 'HAYALI_SART'
                WHEN @SabitFallbackBirimMaliyet IS NOT NULL THEN 'HAYALI_SABIT'
                ELSE 'HAYALI_FIYAT_YOK'
            END AS VARCHAR(20)
        ) AS Durum,
        f.SatinalmaSarti
    INTO #sentetik
    FROM #eksik e
    LEFT JOIN #sartFiyat f ON f.StkId = e.StkId;

    IF @DryRun = 1
    BEGIN
        -- FIX: acik 6 kolon (eski SELECT * = 7 kolon/KalanMiktar dahil) → cagiranin
        -- #sentetikDryRun(6) + bos-vaka SELECT(6) ile uyumlu. INSERT-EXEC mismatch giderildi.
        SELECT StkId, GirisTarihi, GirisMiktar, BirimMaliyet, Durum, SatinalmaSarti
        FROM #sentetik
        ORDER BY StkId;
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Ayni tarih ve urunler icin eski sentetik katmanlari temizle (tekrar calistirma guvenli)
        DELETE h
        FROM dbo.FifoKatman h
        WHERE h.KaynakTip = 'SENTETIK_ALIS'
          AND h.GirisTarihi = @GirisTarihi
          AND (@StkId IS NULL OR h.StkId = @StkId);

        INSERT INTO dbo.FifoKatman
            (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
             GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
        SELECT
            s.StkId,
            s.GirisTarihi,
            'SENTETIK_ALIS',
            'SENTETIK-' + CONVERT(VARCHAR(8), @GirisTarihi, 112),
            s.GirisTarihi,
            NULL,
            s.GirisMiktar,
            s.KalanMiktar,
            ISNULL(s.BirimMaliyet, 0),
            s.Durum
        FROM #sentetik s
        WHERE s.BirimMaliyet IS NOT NULL
          AND s.BirimMaliyet > 0;

        -- Sentetik fiyatlama bilgi kayitlari (tekrar calistirmaya uygun)
        DELETE x
        FROM dbo.FifoSorunluStoklar x
        WHERE x.EnvanterTarihi = @GirisTarihi
          AND x.SorunTipi IN ('SENTETIK_FIYATLANDI', 'SENTETIK_FIYAT_YOK')
          AND (@StkId IS NULL OR x.StkId = @StkId);

        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, MekanId, StokMiktar, SorunTipi, Aciklama)
        SELECT
            s.StkId,
            @GirisTarihi,
            0,
            s.GirisMiktar,
            'SENTETIK_FIYATLANDI',
            'Kaynak=SENTETIK_ALIS; Durum=' + s.Durum +
            '; Sarti=' + ISNULL(s.SatinalmaSarti, '-') +
            '; BirimMaliyet=' + CONVERT(VARCHAR(30), s.BirimMaliyet)
        FROM #sentetik s
        WHERE s.BirimMaliyet IS NOT NULL
          AND s.BirimMaliyet > 0;

        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, MekanId, StokMiktar, SorunTipi, Aciklama)
        SELECT
            s.StkId,
            @GirisTarihi,
            0,
            s.GirisMiktar,
            'SENTETIK_FIYAT_YOK',
            'STOK_YETERSIZ bulundu ancak sart/sabit fallback fiyat bulunamadi.'
        FROM #sentetik s
        WHERE s.BirimMaliyet IS NULL OR s.BirimMaliyet <= 0;

        COMMIT TRANSACTION;

        SELECT
            StkId,
            GirisTarihi,
            GirisMiktar,
            BirimMaliyet,
            Durum,
            SatinalmaSarti
        FROM #sentetik
        ORDER BY StkId;

        PRINT 'Sentetik katmanlar olusturuldu. FIFO cikisini yeniden hesaplamak icin ayri proses gerekir.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

PRINT 'sp_Fifo_SentetikKatmanOlustur olusturuldu';
GO


GO
PRINT '======== 05 Aylik Rutin Full ========';
GO
USE [$(MaliyetDb)];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE dbo.sp_Fifo_AylikRutinFull
(
    @Yil INT,
    @Ay INT,
    @StkId INT = NULL,
    @IslemId UNIQUEIDENTIFIER = NULL,
    @SentetikSatinalmaSarti VARCHAR(50) = NULL,
    @SabitFallbackBirimMaliyet DECIMAL(18,6) = NULL,
    @SentetikAktif BIT = 1
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Yil IS NULL OR @Ay IS NULL OR @Ay NOT BETWEEN 1 AND 12
    BEGIN
        RAISERROR('Gecersiz yil/ay parametresi.', 16, 1);
        RETURN;
    END

    IF @SabitFallbackBirimMaliyet IS NOT NULL AND @SabitFallbackBirimMaliyet <= 0
    BEGIN
        RAISERROR('Sabit fallback birim maliyet 0''dan buyuk olmali.', 16, 1);
        RETURN;
    END

    DECLARE @Baslangic DATE = DATEFROMPARTS(@Yil, @Ay, 1);
    DECLARE @Bitis DATE = EOMONTH(@Baslangic);
    DECLARE @YerelTrans BIT = 0;
    DECLARE @SentetikGerekli BIT = 0;

    BEGIN TRY
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @YerelTrans = 1;
        END

        EXEC dbo.sp_Fifo_AylikCalistir
            @yil = @Yil,
            @ay = @Ay,
            @StkId = @StkId,
            @IslemId = @IslemId;

        IF @SentetikAktif = 1
        BEGIN
            IF OBJECT_ID('tempdb..#sentetikDryRun', 'U') IS NOT NULL DROP TABLE #sentetikDryRun;
            CREATE TABLE #sentetikDryRun (
                StkId INT NOT NULL,
                GirisTarihi DATE NOT NULL,
                GirisMiktar DECIMAL(18,4) NOT NULL,
                BirimMaliyet DECIMAL(18,6) NULL,
                Durum VARCHAR(20) NOT NULL,
                SatinalmaSarti VARCHAR(50) NULL
            );

            INSERT INTO #sentetikDryRun
            EXEC dbo.sp_Fifo_SentetikKatmanOlustur
                @SorunTarihi = @Bitis,
                @GirisTarihi = @Bitis,
                @SentetikSatinalmaSarti = @SentetikSatinalmaSarti,
                @StkId = @StkId,
                @SabitFallbackBirimMaliyet = @SabitFallbackBirimMaliyet,
                @DryRun = 1;

            IF EXISTS (
                SELECT 1
                FROM #sentetikDryRun
                WHERE BirimMaliyet IS NOT NULL
                  AND BirimMaliyet > 0
            )
                SET @SentetikGerekli = 1;

            IF @SentetikGerekli = 1
            BEGIN
                EXEC dbo.sp_Fifo_SentetikKatmanOlustur
                    @SorunTarihi = @Bitis,
                    @GirisTarihi = @Bitis,
                    @SentetikSatinalmaSarti = @SentetikSatinalmaSarti,
                    @StkId = @StkId,
                    @SabitFallbackBirimMaliyet = @SabitFallbackBirimMaliyet,
                    @DryRun = 0;

                EXEC dbo.sp_Fifo_Calistir
                    @alisBaslangic = @Baslangic,
                    @alisBitis = @Bitis,
                    @satisBaslangic = @Baslangic,
                    @satisBitis = @Bitis,
                    @StkId = @StkId,
                    @IslemId = @IslemId,
                    @calistirAcilis = 0,
                    @calistirAlis = 0,
                    @calistirCikis = 1;
            END
        END

        IF @YerelTrans = 1 AND XACT_STATE() = 1
            COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @YerelTrans = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        DECLARE @HataMesaji NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('sp_Fifo_AylikRutinFull hatasi: %s', 16, 1, @HataMesaji);
        RETURN;
    END CATCH
END
GO

GO
PRINT '======== 09 Batch Orchestration ========';
GO
USE [$(MaliyetDb)];
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

GO
PRINT '======== 14 Acilis Optimize + GARANTI final-tier (FIYAT 0 OLAMAZ) ========';
GO
USE [$(MaliyetDb)];
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
-- V2-14: ACILIS MALIYETLENDIRME - OPTIMIZE EDILMIS VERSIYON
--
-- Bottleneck'ler ve cozumleri:
--   1) irsHrk aylik devir: kartezyen JOIN (urun x ay x hareket)
--      => EOMONTH pre-aggregate + window SUM  (55x hiz kazanimi)
--   2) fn_SonGecerliFiyat_Adv: satir-satir OUTER APPLY
--      => Distinct ay basina 1 bulk TVF cagri + LEFT JOIN
--   3) 37 dk boyunca tek transaction / lock
--      => 3 faza bol, arada lock birak
--   4) irsHrk full scan (2021 oncesi gereksiz)
--      => @baslangicTarihi alt sinir filtresi
--
-- Schema: dbo (v2 convention)
-- =============================================================

CREATE OR ALTER PROCEDURE dbo.sp_Fifo_AcilisCalistir_V2
(
    @EnvanterTarihi DATE,
    @StkId INT = NULL,
    @IslemId UNIQUEIDENTIFIER = NULL,
    @FallbackSatinalmaSarti VARCHAR(50) = NULL   -- ERP devir fiyatlari icin
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- ============================================================
    -- PARAMETRE VALIDASYONU
    -- ============================================================
    IF @EnvanterTarihi IS NULL
    BEGIN
        RAISERROR('Envanter tarihi bos olamaz', 16, 1);
        RETURN;
    END

    IF @EnvanterTarihi > GETDATE()
    BEGIN
        RAISERROR('Envanter tarihi gelecek tarih olamaz', 16, 1);
        RETURN;
    END


    DECLARE @baslangicTarihi DATE = DATEFROMPARTS(2021, 5, 31);
    DECLARE @stepKey VARCHAR(50);
    DECLARE @stepName VARCHAR(100);
    DECLARE @stepOrder INT;
    DECLARE @fazBaslangic DATETIME2(3) = SYSDATETIME();
    DECLARE @urunSayisi INT = 0;

    -- ============================================================
    -- FAZ 1: ENVANTER SNAPSHOT + ALISLAR
    -- (Kendi transaction'i - read-heavy, lock erken birakilir)
    -- ============================================================
    BEGIN TRY
        BEGIN TRANSACTION;

        PRINT '========================================';
        PRINT 'sp_Fifo_AcilisCalistir_V2 basliyor';
        PRINT 'Envanter tarihi: ' + CONVERT(VARCHAR(10), @EnvanterTarihi, 120);
        PRINT 'Baslangic: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 121);
        PRINT '========================================';

        -- --------------------------------------------------------
        -- ADIM 1: Envanter snapshot (irsHrk ile mekan bazli stok)
        -- --------------------------------------------------------
        SET @stepKey = 'envanter_v2';
        SET @stepName = 'Envanter snapshot (V2)';
        SET @stepOrder = 1;
        PRINT '[1/6] Envanter snapshot - irsHrk okunuyor...';
        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='CALISIYOR', @Mesaj=NULL;

        IF OBJECT_ID('tempdb..#stoklarMekan', 'U') IS NOT NULL DROP TABLE #stoklarMekan;

        -- DUZELTME (2026-06-19): GECMIS-DOGRU acilis snapshot'i. Eski V2 stokSonAltDepo_vw
        -- (ANLIK stok) kullaniyordu → 2025-12-31 acilisini BUGUNKU stokla kuruyordu (yanlis).
        -- 02_V2 (kanit-dogru, 508K) gibi irsHrk KUMULATIF (ehTrhS <= @EnvanterTarihi) — hem
        -- gecmise-dogru hem stokSonAltDepo_vw bagimliligini kaldirir (sadece irsHrk).
        SELECT
            h.ehMekan AS MekanId,
            h.ehStkId AS StkId,
            SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) AS StokMiktar
        INTO #stoklarMekan
        FROM $(ErpDb).dbo.irsHrk h WITH(NOLOCK)
        WHERE h.ehTrhS <= @EnvanterTarihi
          AND h.ehAltDepo = 0
          AND h.ehMekan IN (1, 12, 4477, 4478)   -- mekan 12 (ana depo) ortak havuza dahil
          AND (@StkId IS NULL OR h.ehStkId = @StkId)
          AND NOT EXISTS (SELECT 1 FROM dbo.FifoDevreDisiUrunler d WHERE d.StkId = h.ehStkId)  -- non-inventory devre-disi: envanterde kalir, katman kurulMAZ (fifo-domain §2)
        GROUP BY h.ehMekan, h.ehStkId
        HAVING SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) > 0;

        CREATE INDEX IX_tmp_stoklarMekan ON #stoklarMekan(MekanId, StkId);

        IF OBJECT_ID('tempdb..#stoklar', 'U') IS NOT NULL DROP TABLE #stoklar;

        SELECT
            StkId,
            SUM(StokMiktar) AS StokMiktar
        INTO #stoklar
        FROM #stoklarMekan
        GROUP BY StkId;

        SET @urunSayisi = @@ROWCOUNT;
        CREATE INDEX IX_tmp_stoklar ON #stoklar(StkId);

        PRINT '      Urun sayisi: ' + CAST(@urunSayisi AS VARCHAR(10));

        /* Envanter kayit */
        DELETE FROM dbo.FifoAcilisEnvanter
        WHERE EnvanterTarihi = @EnvanterTarihi
          AND (@StkId IS NULL OR StkId = @StkId);

        INSERT INTO dbo.FifoAcilisEnvanter (EnvanterTarihi, MekanId, StkId, StokMiktar)
        SELECT @EnvanterTarihi, MekanId, StkId, StokMiktar
        FROM #stoklarMekan;

        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='TAMAMLANDI', @Mesaj=NULL;
        PRINT '      Envanter tamamlandi. Sure: ' +
              CAST(DATEDIFF(SECOND, @fazBaslangic, SYSDATETIME()) AS VARCHAR(10)) + 's';

        -- --------------------------------------------------------
        -- ADIM 2: Alislar (fat + fatAyr)
        -- --------------------------------------------------------
        SET @fazBaslangic = SYSDATETIME();
        SET @stepKey = 'alis_v2';
        SET @stepName = 'Alislar toplanir (V2)';
        SET @stepOrder = 2;
        PRINT '[2/6] Alislar toplaniyor (fat+fatAyr)...';
        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='CALISIYOR', @Mesaj=NULL;

        IF OBJECT_ID('tempdb..#alislar', 'U') IS NOT NULL DROP TABLE #alislar;
        CREATE TABLE #alislar (
            StkId        INT           NOT NULL,
            GirisTarihi  DATETIME      NOT NULL,
            BelgeNo      VARCHAR(50)   NULL,
            BelgeTarihi  DATE          NULL,
            FirmaId      INT           NULL,
            Miktar       DECIMAL(18,4) NOT NULL,
            NetTutar     DECIMAL(18,4) NOT NULL
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
        INSERT INTO #alislar (StkId, GirisTarihi, BelgeNo, BelgeTarihi, FirmaId, Miktar, NetTutar)
        SELECT
            a.ehStkID AS StkId,
            i.eTarih  AS GirisTarihi,
            f.eNo     AS BelgeNo,
            ' + @belgeTarihExpr + N' AS BelgeTarihi,
            ' + @firmaExpr + N' AS FirmaId,
            SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS Miktar,
            SUM(
                CONVERT(DECIMAL(18,4),
                    CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END
                )
            ) AS NetTutar
        FROM #stoklar s
        JOIN $(ErpDb).dbo.irs i WITH(NOLOCK)
            ON i.eTip IN (2,0,10,3,6,102,103)
           AND i.eTarih >  CONVERT(smalldatetime, @baslangicTarihi)
           AND i.eTarih <  DATEADD(DAY, 1, CONVERT(smalldatetime, @EnvanterTarihi))
           AND i.eMekan IN (1,12,4477,4478)   -- FIX: mekan 12 dahil (ortak havuz kurali)
        JOIN $(ErpDb).dbo.irsAyr ia WITH(NOLOCK)
            ON ia.ehID = i.eID
        JOIN $(ErpDb).dbo.fatAyr a WITH(NOLOCK)
            ON a.ehIrsID   = i.eID
           AND a.ehIrsSira = ia.ehSira
           AND a.ehStkID   = s.StkId
        JOIN $(ErpDb).dbo.fat f WITH(NOLOCK)
            ON f.eID = a.ehID
        WHERE a.ehAdetN <> 0
          AND (@StkId IS NULL OR a.ehStkID = @StkId)
        GROUP BY a.ehstkID, i.eTarih, i.eID, f.eNo' + @groupByExtra + N'
        HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;';

        EXEC sp_executesql
            @sql,
            N'@baslangicTarihi DATE, @EnvanterTarihi DATE, @StkId INT',
            @baslangicTarihi = @baslangicTarihi,
            @EnvanterTarihi = @EnvanterTarihi,
            @StkId = @StkId;

        ALTER TABLE #alislar ADD BirimMaliyet DECIMAL(18,6);

        UPDATE #alislar
        SET BirimMaliyet = CASE WHEN Miktar = 0 THEN 0 ELSE NetTutar / Miktar END;

        CREATE INDEX IX_tmp_alislar ON #alislar(StkId, GirisTarihi DESC, BelgeNo);

        DECLARE @alisSayisi INT = (SELECT COUNT(*) FROM #alislar);
        PRINT '      Alis kaydi: ' + CAST(@alisSayisi AS VARCHAR(10));

        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='TAMAMLANDI', @Mesaj=NULL;
        PRINT '      Alislar tamamlandi. Sure: ' +
              CAST(DATEDIFF(SECOND, @fazBaslangic, SYSDATETIME()) AS VARCHAR(10)) + 's';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        GOTO HataYonetimi;
    END CATCH

    -- ============================================================
    -- FAZ 2: TERS FIFO KATMAN + TAMAMLAMALAR
    -- (Kendi transaction'i - yazma agirlikli)
    -- ============================================================
    BEGIN TRY
        BEGIN TRANSACTION;
        SET @fazBaslangic = SYSDATETIME();

        -- --------------------------------------------------------
        -- ADIM 3: Ters FIFO katman hesaplama
        -- --------------------------------------------------------
        SET @stepKey = 'katman_v2';
        SET @stepName = 'Ters FIFO katman (V2)';
        SET @stepOrder = 3;
        PRINT '[3/6] Ters FIFO katman hesaplaniyor...';
        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='CALISIYOR', @Mesaj=NULL;

        IF OBJECT_ID('tempdb..#katman', 'U') IS NOT NULL DROP TABLE #katman;

        ;WITH Ters AS (
            SELECT
                StkId, GirisTarihi, BelgeNo, BelgeTarihi, FirmaId, Miktar, BirimMaliyet, NetTutar,
                SUM(Miktar) OVER (
                    PARTITION BY StkId
                    ORDER BY GirisTarihi DESC, BelgeNo DESC
                    ROWS UNBOUNDED PRECEDING
                ) AS KumTers
            FROM #alislar
            WHERE Miktar > 0 AND NetTutar > 0
        ),
        Acilis AS (
            SELECT
                t.StkId, t.GirisTarihi, t.BelgeNo, t.BelgeTarihi, t.FirmaId,
                t.Miktar AS SatirMiktar, t.BirimMaliyet,
                t.KumTers, s.StokMiktar,
                CASE
                    WHEN t.KumTers - t.Miktar >= s.StokMiktar THEN 0
                    WHEN t.KumTers <= s.StokMiktar THEN t.Miktar
                    ELSE s.StokMiktar - (t.KumTers - t.Miktar)
                END AS AcilisMiktar
            FROM Ters t
            JOIN #stoklar s ON s.StkId = t.StkId
        )
        SELECT StkId, GirisTarihi, BelgeNo, BelgeTarihi, FirmaId,
               SatirMiktar, BirimMaliyet, KumTers, StokMiktar, AcilisMiktar
        INTO #katman
        FROM Acilis WHERE AcilisMiktar > 0;

        DECLARE @katmanSayisi INT = @@ROWCOUNT;
        PRINT '      Katman sayisi: ' + CAST(@katmanSayisi AS VARCHAR(10));

        /* Onceki acilis temizligi */
        DELETE FROM dbo.FifoKatman
        WHERE KaynakTip = 'ACILIS' AND GirisTarihi = @EnvanterTarihi
          AND (@StkId IS NULL OR StkId = @StkId);

        INSERT INTO dbo.FifoKatman
            (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
             GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
        SELECT
            StkId, @EnvanterTarihi, 'ACILIS', BelgeNo, BelgeTarihi, FirmaId,
            AcilisMiktar, AcilisMiktar, BirimMaliyet, 'NORMAL'
        FROM #katman;

        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='TAMAMLANDI', @Mesaj=NULL;
        PRINT '      Katman tamamlandi. Sure: ' +
              CAST(DATEDIFF(SECOND, @fazBaslangic, SYSDATETIME()) AS VARCHAR(10)) + 's';

        -- --------------------------------------------------------
        -- ADIM 4: Eksik tamamlamalar (son alis + merkez + sart)
        -- --------------------------------------------------------
        SET @fazBaslangic = SYSDATETIME();
        SET @stepKey = 'tamamla_v2';
        SET @stepName = 'Tamamlamalar (V2)';
        SET @stepOrder = 4;
        PRINT '[4/6] Eksik tamamlamalari (son alis, merkez, sart fiyat)...';
        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='CALISIYOR', @Mesaj=NULL;

        /* Eksik miktarlari tespit et */
        IF OBJECT_ID('tempdb..#eksikler', 'U') IS NOT NULL DROP TABLE #eksikler;

        ;WITH Ozet AS (
            SELECT StkId, SUM(AcilisMiktar) AS ToplamAcilisMiktar
            FROM #katman GROUP BY StkId
        ),
        AlisVarMi AS (
            SELECT DISTINCT StkId FROM #alislar
        )
        SELECT
            s.StkId, s.StokMiktar,
            ISNULL(o.ToplamAcilisMiktar, 0) AS ToplamAcilisMiktar,
            (s.StokMiktar - ISNULL(o.ToplamAcilisMiktar, 0)) AS EksikMiktar
        INTO #eksikler
        FROM #stoklar s
        LEFT JOIN Ozet o ON o.StkId = s.StkId
        LEFT JOIN AlisVarMi v ON v.StkId = s.StkId;

        /* Alisi olan ama yetmeyenleri son alisla tamamla */
        ;WITH SonAlis AS (
            SELECT
                a.StkId, a.GirisTarihi, a.BelgeNo, a.BelgeTarihi, a.FirmaId, a.BirimMaliyet,
                ROW_NUMBER() OVER (
                    PARTITION BY a.StkId
                    ORDER BY a.GirisTarihi DESC, a.BelgeNo DESC
                ) AS rn
            FROM #alislar a
            WHERE a.BirimMaliyet > 0   -- FIYAT 0 OLAMAZ (fifo-domain §6, 2026-06-19): 0-degerli son-alis (numune/duzeltme fatAyr.ehTutarN=0) atlanir, en son NONZERO alis secilir
        )
        INSERT INTO dbo.FifoKatman
            (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
             GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
        SELECT
            e.StkId, @EnvanterTarihi, 'ACILIS_TAMAMLA', sa.BelgeNo, sa.BelgeTarihi, sa.FirmaId,
            e.EksikMiktar, e.EksikMiktar, sa.BirimMaliyet, 'TAMAMLAMA'
        FROM #eksikler e
        JOIN SonAlis sa ON sa.StkId = e.StkId AND sa.rn = 1
        WHERE e.EksikMiktar > 0 AND e.ToplamAcilisMiktar > 0;

        DECLARE @tamamlamaSayisi INT = @@ROWCOUNT;
        PRINT '      Son alis tamamlama: ' + CAST(@tamamlamaSayisi AS VARCHAR(10)) + ' urun';

        /* Merkez depo (12) alislari ile tamamlama (alis yoksa) */
        IF OBJECT_ID('tempdb..#merkezAlis', 'U') IS NOT NULL DROP TABLE #merkezAlis;
        CREATE TABLE #merkezAlis (
            StkId        INT           NOT NULL,
            GirisTarihi  DATETIME      NOT NULL,
            BelgeNo      VARCHAR(50)   NULL,
            BelgeTarihi  DATE          NULL,
            FirmaId      INT           NULL,
            Miktar       DECIMAL(18,4) NOT NULL,
            NetTutar     DECIMAL(18,4) NOT NULL
        );

        DECLARE @sqlMerkez NVARCHAR(MAX) = N'
        INSERT INTO #merkezAlis (StkId, GirisTarihi, BelgeNo, BelgeTarihi, FirmaId, Miktar, NetTutar)
        SELECT
            a.ehStkID AS StkId,
            i.eTarih  AS GirisTarihi,
            f.eNo     AS BelgeNo,
            ' + @belgeTarihExpr + N' AS BelgeTarihi,
            ' + @firmaExpr + N' AS FirmaId,
            SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS Miktar,
            SUM(
                CONVERT(DECIMAL(18,4),
                    CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END
                )
            ) AS NetTutar
        FROM #eksikler e
        LEFT JOIN (SELECT DISTINCT StkId FROM #alislar) v ON v.StkId = e.StkId
        JOIN $(ErpDb).dbo.irs i WITH(NOLOCK)
            ON i.eTip IN (2,0,10,3,6,102,103)
           AND i.eTarih >  CONVERT(smalldatetime, @baslangicTarihi)
           AND i.eTarih <  DATEADD(DAY, 1, CONVERT(smalldatetime, @EnvanterTarihi))
           AND i.eMekan = 12
        JOIN $(ErpDb).dbo.irsAyr ia WITH(NOLOCK)
            ON ia.ehID = i.eID
        JOIN $(ErpDb).dbo.fatAyr a WITH(NOLOCK)
            ON a.ehIrsID   = i.eID
           AND a.ehIrsSira = ia.ehSira
           AND a.ehStkID   = e.StkId
        JOIN $(ErpDb).dbo.fat f WITH(NOLOCK)
            ON f.eID = a.ehID
        WHERE a.ehAdetN <> 0
          AND v.StkId IS NULL
          AND e.EksikMiktar > 0
          AND (@StkId IS NULL OR a.ehStkID = @StkId)
        GROUP BY a.ehStkID, i.eTarih, i.eID, f.eNo' + @groupByExtra + N'
        HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;';

        EXEC sp_executesql
            @sqlMerkez,
            N'@baslangicTarihi DATE, @EnvanterTarihi DATE, @StkId INT',
            @baslangicTarihi = @baslangicTarihi,
            @EnvanterTarihi = @EnvanterTarihi,
            @StkId = @StkId;

        ALTER TABLE #merkezAlis ADD BirimMaliyet DECIMAL(18,6);

        UPDATE #merkezAlis
        SET BirimMaliyet = CASE WHEN Miktar = 0 THEN 0 ELSE NetTutar / Miktar END;

        IF OBJECT_ID('tempdb..#merkezSon', 'U') IS NOT NULL DROP TABLE #merkezSon;

        ;WITH SonMerkez AS (
            SELECT
                m.StkId, m.GirisTarihi, m.BelgeNo, m.BelgeTarihi, m.FirmaId, m.BirimMaliyet,
                ROW_NUMBER() OVER (
                    PARTITION BY m.StkId
                    ORDER BY m.GirisTarihi DESC, m.BelgeNo DESC
                ) AS rn
            FROM #merkezAlis m
            WHERE m.BirimMaliyet > 0   -- FIYAT 0 OLAMAZ (fifo-domain §6, 2026-06-19): 0-degerli merkez-alis atlanir, en son NONZERO merkez alisi secilir
        )
        SELECT
            StkId, GirisTarihi, BelgeNo, BelgeTarihi, FirmaId, BirimMaliyet
        INTO #merkezSon
        FROM SonMerkez
        WHERE rn = 1;

        INSERT INTO dbo.FifoKatman
            (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
             GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
        SELECT
            e.StkId, @EnvanterTarihi, 'ACILIS_TAMAMLA', ms.BelgeNo, ms.BelgeTarihi, ms.FirmaId,
            e.EksikMiktar, e.EksikMiktar, ms.BirimMaliyet, 'MERKEZ_TAMAMLAMA'
        FROM #eksikler e
        JOIN #merkezSon ms ON ms.StkId = e.StkId
        LEFT JOIN (SELECT DISTINCT StkId FROM #alislar) v ON v.StkId = e.StkId
        WHERE v.StkId IS NULL AND e.EksikMiktar > 0;

        DECLARE @merkezSayisi INT = @@ROWCOUNT;
        PRINT '      Merkez tamamlama: ' + CAST(@merkezSayisi AS VARCHAR(10)) + ' urun';

        /* Son gecerli fiyat ile tamamlama */
        IF OBJECT_ID('tempdb..#sonGecerli', 'U') IS NOT NULL DROP TABLE #sonGecerli;

        ;WITH SonFiyat AS (
            SELECT
                f.fhID,
                f.fStkID AS StkId,
                f.fTarih,
                f.fTarihSon,
                f.sonrakiNet,
                ROW_NUMBER() OVER (
                    PARTITION BY f.fStkID
                    ORDER BY f.fTarihSon DESC, f.fhID DESC
                ) AS rn
            FROM $(ErpDb).bkm.fn_SonGecerliFiyat(@EnvanterTarihi, 1) f
            WHERE f.sonrakiNet > 0
        )
        SELECT
            StkId, fhID, fTarih, fTarihSon, sonrakiNet
        INTO #sonGecerli
        FROM SonFiyat
        WHERE rn = 1;

        INSERT INTO dbo.FifoKatman
            (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
             GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
        SELECT
            e.StkId, @EnvanterTarihi, 'ACILIS_TAMAMLA',
            CAST(sg.fhID AS VARCHAR(50)), CAST(sg.fTarihSon AS DATE), NULL,
            e.EksikMiktar, e.EksikMiktar, sg.sonrakiNet, 'SART_TAMAMLAMA'
        FROM #eksikler e
        JOIN #sonGecerli sg ON sg.StkId = e.StkId
        LEFT JOIN (SELECT DISTINCT StkId FROM #alislar) v ON v.StkId = e.StkId
        LEFT JOIN #merkezSon ms ON ms.StkId = e.StkId
        WHERE v.StkId IS NULL AND ms.StkId IS NULL AND e.EksikMiktar > 0;

        DECLARE @sartSayisi INT = @@ROWCOUNT;
        PRINT '      Sart tamamlama: ' + CAST(@sartSayisi AS VARCHAR(10)) + ' urun';

        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='TAMAMLANDI', @Mesaj=NULL;
        PRINT '      Tamamlamalar bitti. Sure: ' +
              CAST(DATEDIFF(SECOND, @fazBaslangic, SYSDATETIME()) AS VARCHAR(10)) + 's';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        GOTO HataYonetimi;
    END CATCH

    -- ============================================================
    -- FAZ 3: AYLIK DEVIR (OPTIMIZE) + SORUN KAYITLARI
    -- Bottleneck burada: irsHrk x ay kartezyen JOIN
    --   ESKi: irsHrk JOIN #aylar ON ehTrhS <= ayBitis  (55x tekrar)
    --   YENi: irsHrk 1 kez okunur, EOMONTH ile ay bazli pre-aggregate
    --         sonra window SUM ile kumulatif stok hesaplanir
    -- ============================================================
    BEGIN TRY
        BEGIN TRANSACTION;
        SET @fazBaslangic = SYSDATETIME();

        -- --------------------------------------------------------
        -- ADIM 5: Aylik devir (OPTIMIZE: pre-aggregate + window fn)
        -- --------------------------------------------------------
        SET @stepKey = 'aylik_devir_v2';
        SET @stepName = 'Aylik devir OPTIMIZE (V2)';
        SET @stepOrder = 5;
        PRINT '[5/6] Aylik devir (OPTIMIZE) hesaplaniyor...';
        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='CALISIYOR', @Mesaj=NULL;

        /* Eksik kalan urunler (alis/merkez/sart hicbiri bulamadi) */
        IF OBJECT_ID('tempdb..#eksikKalan', 'U') IS NOT NULL DROP TABLE #eksikKalan;

        SELECT e.StkId, e.EksikMiktar
        INTO #eksikKalan
        FROM #eksikler e
        LEFT JOIN (SELECT DISTINCT StkId FROM #alislar) v ON v.StkId = e.StkId
        LEFT JOIN #merkezSon ms ON ms.StkId = e.StkId
        LEFT JOIN #sonGecerli sg ON sg.StkId = e.StkId
        WHERE e.EksikMiktar > 0 AND v.StkId IS NULL AND ms.StkId IS NULL AND sg.StkId IS NULL;

        CREATE INDEX IX_tmp_eksikKalan ON #eksikKalan(StkId);

        DECLARE @eksikKalanSayisi INT = (SELECT COUNT(*) FROM #eksikKalan);
        PRINT '      Aylik devir gerekli urun: ' + CAST(@eksikKalanSayisi AS VARCHAR(10));

        IF OBJECT_ID('tempdb..#aylikKatman', 'U') IS NOT NULL DROP TABLE #aylikKatman;
        CREATE TABLE #aylikKatman (
            StkId INT NOT NULL,
            AyBitis DATE NOT NULL,
            AyMiktar DECIMAL(18,4) NOT NULL,
            BirimMaliyet DECIMAL(18,6) NULL,
            Durum VARCHAR(20) NOT NULL
        );

        /* Onceki AYLIK_DEVIR temizligi */
        DELETE FROM dbo.FifoKatman
        WHERE KaynakTip = 'AYLIK_DEVIR'
          AND GirisTarihi BETWEEN @baslangicTarihi AND @EnvanterTarihi
          AND (@StkId IS NULL OR StkId = @StkId);

        IF @eksikKalanSayisi > 0
        BEGIN
            -- =====================================================
            -- OPTIMIZASYON 1: irsHrk tek tarama + EOMONTH aggregate
            -- ESKi: irsHrk JOIN #aylar ON ehTrhS <= ayBitis
            --       => her hareket 55 ay icin tekrar okunur
            -- YENi: irsHrk 1 kez okunur, EOMONTH ile ay bazli SUM
            --       sonra window SUM ile kumulatif stok
            -- =====================================================
            PRINT '      [OPT1] irsHrk tek tarama + EOMONTH pre-aggregate...';

            IF OBJECT_ID('tempdb..#aylikHareket', 'U') IS NOT NULL DROP TABLE #aylikHareket;

            -- Adim A: Hareketleri ay bazli ozetle (tek tarama)
            SELECT
                h.ehstkID AS StkId,
                EOMONTH(h.ehTrhS) AS AyBitis,
                SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) AS AyHareket
            INTO #aylikHareket
            FROM $(ErpDb).dbo.irsHrk h WITH(NOLOCK)
            JOIN #eksikKalan e ON e.StkId = h.ehstkID
            WHERE h.ehAltDepo = 0
              AND h.ehMekan IN (1, 12, 4477, 4478)
              AND h.ehTrhS <= @EnvanterTarihi
              AND h.ehTrhS >= @baslangicTarihi        -- OPT4: alt sinir filtresi
            GROUP BY h.ehstkID, EOMONTH(h.ehTrhS);

            DECLARE @aylikHareketSayisi INT = @@ROWCOUNT;
            PRINT '      Aylik hareket ozet satiri: ' + CAST(@aylikHareketSayisi AS VARCHAR(10));

            -- Adim B: Kumulatif stok hesapla (window function - O(n))
            IF OBJECT_ID('tempdb..#aylikStok', 'U') IS NOT NULL DROP TABLE #aylikStok;

            SELECT
                StkId,
                AyBitis,
                SUM(AyHareket) OVER (
                    PARTITION BY StkId
                    ORDER BY AyBitis
                    ROWS UNBOUNDED PRECEDING
                ) AS AyStok
            INTO #aylikStok
            FROM #aylikHareket;

            -- Sadece pozitif stok olan aylari tut
            DELETE FROM #aylikStok WHERE AyStok <= 0;

            CREATE INDEX IX_tmp_aylikStok ON #aylikStok(StkId, AyBitis);

            PRINT '      [OPT1] Kumulatif stok hesaplandi.';

            -- Ters kumulatif allokasyon (en son aydan geriye)
            IF OBJECT_ID('tempdb..#aylikAlloc', 'U') IS NOT NULL DROP TABLE #aylikAlloc;

            ;WITH Aylik AS (
                SELECT
                    s.StkId, s.AyBitis, s.AyStok,
                    SUM(s.AyStok) OVER (
                        PARTITION BY s.StkId
                        ORDER BY s.AyBitis DESC
                        ROWS UNBOUNDED PRECEDING
                    ) AS KumStok
                FROM #aylikStok s
            ),
            Alloc AS (
                SELECT
                    a.StkId, a.AyBitis,
                    CAST(
                        CASE
                            WHEN a.KumStok <= e.EksikMiktar THEN a.AyStok
                            WHEN a.KumStok - a.AyStok < e.EksikMiktar THEN e.EksikMiktar - (a.KumStok - a.AyStok)
                            ELSE 0
                        END AS DECIMAL(18,4)
                    ) AS AyMiktar
                FROM Aylik a
                JOIN #eksikKalan e ON e.StkId = a.StkId
            )
            SELECT StkId, AyBitis, AyMiktar
            INTO #aylikAlloc
            FROM Alloc WHERE AyMiktar > 0;

            DECLARE @allocSayisi INT = @@ROWCOUNT;
            PRINT '      Alloc kaydi: ' + CAST(@allocSayisi AS VARCHAR(10));

            -- =====================================================
            -- OPTIMIZASYON 2: fn_SonGecerliFiyat_Adv pre-compute
            -- ESKi: OUTER APPLY row-by-row (urun*ay adet cagri)
            -- YENi: Distinct ay basina 1 TVF cagri + LEFT JOIN
            -- =====================================================
            PRINT '      [OPT2] fn_SonGecerliFiyat_Adv pre-compute (ay bazli bulk)...';

            IF OBJECT_ID('tempdb..#sabitFiyat', 'U') IS NOT NULL DROP TABLE #sabitFiyat;
            CREATE TABLE #sabitFiyat (
                StkId INT NOT NULL,
                BirimMaliyet DECIMAL(18,6) NOT NULL
            );

            -- ERP Devir Fiyatlari tablosundan fiyat al
            IF OBJECT_ID('dbo.FifoFallbackFiyatlari', 'U') IS NOT NULL
            BEGIN
                DECLARE @sqlErpDevir NVARCHAR(MAX) = N'
                INSERT INTO #sabitFiyat (StkId, BirimMaliyet)
                SELECT erp.StkId, erp.BirimMaliyet
                FROM dbo.FifoFallbackFiyatlari erp
                WHERE (@StkId IS NULL OR erp.StkId = @StkId)
                  AND (@FallbackSatinalmaSarti IS NULL OR erp.SatinalmaSarti = @FallbackSatinalmaSarti);';

                EXEC sp_executesql
                    @sqlErpDevir,
                    N'@StkId INT, @FallbackSatinalmaSarti VARCHAR(50)',
                    @StkId = @StkId,
                    @FallbackSatinalmaSarti = @FallbackSatinalmaSarti;
            END

            -- =====================================================
            -- FIYAT: TEK CAGRI STRATEJISI
            -- Eski: 55 ay x cursor x fn_SonGecerliFiyat_Adv = 55 dakika
            -- Yeni: 1 cagri (envanter tarihi) = ~60 saniye
            --       Fiyat bulunamayanlar icin 1 ek cagri (6 ay oncesi)
            -- =====================================================
            IF OBJECT_ID('tempdb..#fiyatMaterialize', 'U') IS NOT NULL DROP TABLE #fiyatMaterialize;
            CREATE TABLE #fiyatMaterialize (
                StkId      INT            NOT NULL PRIMARY KEY,
                SonrakiNet DECIMAL(18,6)  NOT NULL
            );

            PRINT '      [OPT2] fn_SonGecerliFiyat_Adv TEK CAGRI...';
            DECLARE @fiyatBaslangic DATETIME2(3) = SYSDATETIME();

            -- 1) Envanter tarihindeki fiyat (tum urunler, ~60sn)
            INSERT INTO #fiyatMaterialize (StkId, SonrakiNet)
            SELECT f.fStkID, f.sonrakiNet
            FROM (
                SELECT
                    f.fStkID, f.sonrakiNet,
                    ROW_NUMBER() OVER (
                        PARTITION BY f.fStkID
                        ORDER BY
                            CASE WHEN f.fFrmID = 9525 THEN 0 ELSE 1 END,
                            f.fTarihSon DESC,
                            f.fhID DESC
                    ) AS rn
                FROM $(ErpDb).bkm.fn_SonGecerliFiyat_Adv(@EnvanterTarihi, 1, 1, 1) f
                WHERE f.sonrakiNet > 0
            ) f
            WHERE f.rn = 1;

            DECLARE @fiyatBulunan INT = @@ROWCOUNT;
            PRINT '      Fiyat bulunan (envanter tarihi): ' + CAST(@fiyatBulunan AS VARCHAR(10)) +
                  ' - Sure: ' + CAST(DATEDIFF(SECOND, @fiyatBaslangic, SYSDATETIME()) AS VARCHAR(10)) + 's';

            -- 2) Fiyat bulunamayan urunler icin 6 ay oncesine bak
            DECLARE @eksikFiyatSayisi INT = (
                SELECT COUNT(*) FROM #aylikAlloc a
                WHERE NOT EXISTS (SELECT 1 FROM #fiyatMaterialize fm WHERE fm.StkId = a.StkId)
            );

            PRINT '      Fiyat eksik urun: ' + CAST(@eksikFiyatSayisi AS VARCHAR(10)) + ' (FIYAT_YOK olarak kaydedilecek)';

            -- Ek fiyat arama: sadece eksik cok fazlaysa (>5000) dene, yoksa 48sn bosuna harcanir
            IF @eksikFiyatSayisi > 5000
            BEGIN
                DECLARE @eskiTarih DATE = DATEADD(MONTH, -6, @EnvanterTarihi);
                PRINT '      Fiyat eksik: ' + CAST(@eksikFiyatSayisi AS VARCHAR(10)) + ' urun, 6 ay oncesi deneniyor...';
                SET @fiyatBaslangic = SYSDATETIME();

                INSERT INTO #fiyatMaterialize (StkId, SonrakiNet)
                SELECT f.fStkID, f.sonrakiNet
                FROM (
                    SELECT
                        f.fStkID, f.sonrakiNet,
                        ROW_NUMBER() OVER (
                            PARTITION BY f.fStkID
                            ORDER BY
                                CASE WHEN f.fFrmID = 9525 THEN 0 ELSE 1 END,
                                f.fTarihSon DESC,
                                f.fhID DESC
                        ) AS rn
                    FROM $(ErpDb).bkm.fn_SonGecerliFiyat_Adv(@eskiTarih, 1, 1, 1) f
                    WHERE f.sonrakiNet > 0
                      AND f.fStkID NOT IN (SELECT StkId FROM #fiyatMaterialize)
                ) f
                WHERE f.rn = 1;

                DECLARE @ekFiyat INT = @@ROWCOUNT;
                PRINT '      Ek fiyat bulunan (6 ay oncesi): ' + CAST(@ekFiyat AS VARCHAR(10)) +
                      ' - Sure: ' + CAST(DATEDIFF(SECOND, @fiyatBaslangic, SYSDATETIME()) AS VARCHAR(10)) + 's';
            END

            PRINT '      [OPT2] Fiyat materialize tamamlandi.';

            /* Aylik katman fiyatlandirma */
            INSERT INTO #aylikKatman (StkId, AyBitis, AyMiktar, BirimMaliyet, Durum)
            SELECT
                a.StkId,
                a.AyBitis,
                a.AyMiktar,
                COALESCE(fm.SonrakiNet, sf.BirimMaliyet) AS BirimMaliyet,
                CASE
                    WHEN COALESCE(fm.SonrakiNet, sf.BirimMaliyet) IS NULL THEN 'FIYAT_YOK'
                    ELSE 'AYLIK_DEVIR'
                END AS Durum
            FROM #aylikAlloc a
            LEFT JOIN #fiyatMaterialize fm ON fm.StkId = a.StkId
            LEFT JOIN #sabitFiyat       sf ON sf.StkId = a.StkId;

            /* Havuza yaz */
            INSERT INTO dbo.FifoKatman
                (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
                 GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
            SELECT
                k.StkId, k.AyBitis, 'AYLIK_DEVIR', NULL, k.AyBitis, NULL,
                k.AyMiktar, k.AyMiktar, ISNULL(k.BirimMaliyet, 0), k.Durum
            FROM #aylikKatman k;

            DECLARE @aylikDevir INT = @@ROWCOUNT;
            PRINT '      Aylik devir katman: ' + CAST(@aylikDevir AS VARCHAR(10));
        END

        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='TAMAMLANDI', @Mesaj=NULL;
        PRINT '      Aylik devir tamamlandi. Sure: ' +
              CAST(DATEDIFF(SECOND, @fazBaslangic, SYSDATETIME()) AS VARCHAR(10)) + 's';

        -- --------------------------------------------------------
        -- ADIM 5.5: GARANTI FINAL-TIER — kategori-imputation; impute EDILEMEYEN → DEVRE DISI
        -- Tum tier'lardan (NORMAL→TAMAMLAMA→MERKEZ→SART→AYLIK_DEVIR) sonra hala maliyetsiz
        -- (BirimMaliyet<=0) / katmansiz acilis stogu:
        --   kategori-marj imputation (SatisFiyat × KatAna oran) → kategori ort. maliyet.
        --   Impute EDILEMEYEN (gercek alis/fytOzl YOK + SatisFiyat/kategori YOK = non-inventory
        --   /obsolete) → FifoDevreDisiUrunler (1-TL SABIT YOK → sahte ~%100 marj uretmez).
        -- Sonuc: maliyetsiz katman=0 (impute edilenler) + impute-edilemez stok devre-disi.
        -- fifo-domain §2 (non-inventory devre-disi) + §6 (fiyat 0 olamaz). 19.06 sabit-tier kaldirildi.
        -- --------------------------------------------------------
        PRINT '[5.5] GARANTI final-tier (kategori-imputation + impute-edilemez→devre-disi)...';

        IF OBJECT_ID('tempdb..#katOran', 'U') IS NOT NULL DROP TABLE #katOran;
        SELECT ub.KatAna,
               CAST(AVG(k.BirimMaliyet / ub.SatisFiyat) AS DECIMAL(18,6)) AS Oran,
               CAST(AVG(k.BirimMaliyet)                 AS DECIMAL(18,6)) AS OrtMaliyet
        INTO #katOran
        FROM dbo.FifoKatman k
        JOIN $(ErpDb).bkm.UrunBilgi ub ON ub.stkID = k.StkId
        WHERE k.GirisTarihi = @EnvanterTarihi AND k.BirimMaliyet > 0
          AND k.Durum IN ('NORMAL','TAMAMLAMA','MERKEZ_TAMAMLAMA','SART_TAMAMLAMA')
          AND ub.SatisFiyat > 0 AND k.BirimMaliyet < ub.SatisFiyat * 3 AND ub.KatAna IS NOT NULL
          AND (@StkId IS NULL OR k.StkId = @StkId)
        GROUP BY ub.KatAna HAVING COUNT(*) >= 20;

        /* Impute edilebilir cozum (StkId → maliyet). bm NULL = fiyatlanamaz → devre-disi. */
        IF OBJECT_ID('tempdb..#imp', 'U') IS NOT NULL DROP TABLE #imp;
        SELECT s.StkId,
               CAST(COALESCE(
                   NULLIF(ub.SonAlis, 0),                                  -- 1) GERCEK son alis (UrunBilgi.SonAlis) = gercek-urun ayraci
                   NULLIF(CASE WHEN ub.SatisFiyat > 0 AND ko.Oran IS NOT NULL
                               THEN ub.SatisFiyat * ko.Oran END, 0),       -- 2) kategori-marj imputation
                   ko.OrtMaliyet) AS DECIMAL(18,6)) AS bm,                 -- 3) kategori ort. mutlak
               CASE WHEN ub.SonAlis > 0                            THEN 'TAMAMLAMA'      -- gercek son alis
                    WHEN ub.SatisFiyat > 0 AND ko.Oran IS NOT NULL THEN 'KATEGORI_IMPUT'
                    ELSE 'KATEGORI_ORT' END AS durum
        INTO #imp
        FROM #stoklar s
        LEFT JOIN $(ErpDb).bkm.UrunBilgi ub ON ub.stkID = s.StkId
        LEFT JOIN #katOran ko ON ko.KatAna = ub.KatAna
        WHERE (@StkId IS NULL OR s.StkId = @StkId);
        CREATE INDEX IX_tmp_imp ON #imp(StkId);

        /* (a) Maliyetsiz acilis katmanlarini imputable ise reprice (aylik-devir FIYAT_YOK=0 dahil) */
        UPDATE k SET k.BirimMaliyet = i.bm, k.Durum = i.durum
        FROM dbo.FifoKatman k
        JOIN #imp i ON i.StkId = k.StkId
        WHERE k.GirisTarihi <= @EnvanterTarihi AND k.BirimMaliyet <= 0 AND i.bm > 0
          AND (@StkId IS NULL OR k.StkId = @StkId);
        DECLARE @garantiUpdate INT = @@ROWCOUNT;

        /* (b) Katmansiz acilis stoguna imputable ise ACILIS_TAMAMLA katman */
        INSERT INTO dbo.FifoKatman
            (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
             GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
        SELECT s.StkId, @EnvanterTarihi, 'ACILIS_TAMAMLA', NULL, NULL, NULL,
               s.StokMiktar, s.StokMiktar, i.bm, i.durum
        FROM #stoklar s
        JOIN #imp i ON i.StkId = s.StkId
        WHERE i.bm > 0 AND (@StkId IS NULL OR s.StkId = @StkId)
          AND NOT EXISTS (SELECT 1 FROM dbo.FifoKatman k
                          WHERE k.StkId = s.StkId AND k.GirisTarihi <= @EnvanterTarihi);
        DECLARE @garantiInsert INT = @@ROWCOUNT;

        /* (c) Impute EDILEMEYEN (bm NULL/<=0) acilis-stok urunleri → DEVRE DISI (non-inventory/obsolete) */
        INSERT INTO dbo.FifoDevreDisiUrunler (StkId, Sebep, EkleyenKullanici, EklenmeTarihi)
        SELECT DISTINCT i.StkId,
               N'GARANTI: fiyatlanamaz (alis/fytOzl/SatisFiyat/kategori yok) → non-inventory/obsolete',
               'acilis-v2-garanti', SYSDATETIME()
        FROM #imp i
        WHERE (i.bm IS NULL OR i.bm <= 0)
          AND NOT EXISTS (SELECT 1 FROM dbo.FifoDevreDisiUrunler d WHERE d.StkId = i.StkId);
        DECLARE @garantiDevreDisi INT = @@ROWCOUNT;

        /* Devre-disi yapilanlarin sifir-maliyet katmanlarini sil (henuz cikis yok → FK guvenli) */
        DELETE k FROM dbo.FifoKatman k
        WHERE k.GirisTarihi <= @EnvanterTarihi AND k.BirimMaliyet <= 0
          AND (@StkId IS NULL OR k.StkId = @StkId)
          AND EXISTS (SELECT 1 FROM dbo.FifoDevreDisiUrunler d WHERE d.StkId = k.StkId);

        PRINT '      GARANTI: ' + CAST(@garantiUpdate AS VARCHAR(10)) + ' reprice + ' +
              CAST(@garantiInsert AS VARCHAR(10)) + ' yeni katman + ' +
              CAST(@garantiDevreDisi AS VARCHAR(10)) + ' devre-disi (fiyatlanamaz)';

        -- --------------------------------------------------------
        -- ADIM 6: Sorun kayitlari
        -- --------------------------------------------------------
        SET @fazBaslangic = SYSDATETIME();
        SET @stepKey = 'sorun_v2';
        SET @stepName = 'Sorun kaydi (V2)';
        SET @stepOrder = 6;
        PRINT '[6/6] Sorun kayitlari yaziliyor...';
        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='CALISIYOR', @Mesaj=NULL;

        DELETE FROM dbo.FifoSorunluStoklar
        WHERE EnvanterTarihi = @EnvanterTarihi
          AND (@StkId IS NULL OR StkId = @StkId);

        /* KATEGORI_IMPUT_TAMAMLANDI - aylik devirde gercek fiyat yoktu, ADIM 5.5
           GARANTI tier'i kategori-marj/sabit ile fiyatlandirdi (FIYAT_YOK=0 KALMADI). */
        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT
            k.StkId, @EnvanterTarihi, SUM(k.AyMiktar), 'KATEGORI_IMPUT_TAMAMLANDI',
            'Gercek kaynak fiyat yok; kategori-marj imputation/sabit ile tamamlandi (ADIM 5.5).'
        FROM #aylikKatman k
        WHERE k.Durum = 'FIYAT_YOK'
        GROUP BY k.StkId;

        /* ALIS_YOK - hicbir kaynaktan fiyat bulunamadi */
        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT
            s.StkId, @EnvanterTarihi, s.StokMiktar, 'ALIS_YOK',
            'Bu urune belirtilen tarih araliginda hic alis bulunamadi.'
        FROM #stoklar s
        LEFT JOIN (SELECT DISTINCT StkId FROM #alislar) v ON v.StkId = s.StkId
        LEFT JOIN #merkezSon ms ON ms.StkId = s.StkId
        LEFT JOIN #sonGecerli sg ON sg.StkId = s.StkId
        LEFT JOIN (SELECT DISTINCT StkId FROM #aylikKatman) ak ON ak.StkId = s.StkId
        WHERE v.StkId IS NULL AND ms.StkId IS NULL AND sg.StkId IS NULL AND ak.StkId IS NULL;

        /* ALIS_YOK_MERKEZ_TAMAMLANDI */
        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT
            e.StkId, @EnvanterTarihi, e.StokMiktar, 'ALIS_YOK_MERKEZ_TAMAMLANDI',
            'Merkez depo (12) son alis fiyati ile tamamlandi.'
        FROM #eksikler e
        JOIN #merkezSon ms ON ms.StkId = e.StkId;

        /* ALIS_YOK_SONGECERLI_TAMAMLANDI */
        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT
            e.StkId, @EnvanterTarihi, e.StokMiktar, 'ALIS_YOK_SONGECERLI_TAMAMLANDI',
            'Son gecerli satin alma fiyati (sonrakiNet) ile tamamlandi.'
        FROM #eksikler e
        JOIN #sonGecerli sg ON sg.StkId = e.StkId
        LEFT JOIN (SELECT DISTINCT StkId FROM #alislar) v ON v.StkId = e.StkId
        LEFT JOIN #merkezSon ms ON ms.StkId = e.StkId
        WHERE v.StkId IS NULL AND ms.StkId IS NULL;

        /* ALIS_EKSIK_TAMAMLANDI */
        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT DISTINCT
            e.StkId, @EnvanterTarihi, e.StokMiktar, 'ALIS_EKSIK_TAMAMLANDI',
            'Eksik stok son alis fiyati ile otomatik tamamlandi.'
        FROM #eksikler e
        WHERE e.EksikMiktar > 0 AND e.ToplamAcilisMiktar > 0;

        /* NET GUVENLIK AGI (invariant) — 02_V2 ile ayni: acilis envanterine
           giren her StkId YA FifoKatman YA sorun kaydi almali. Aylik-devir
           bloku atlanir/kenar durumda urun sessizce dusebiliyordu.
           Dogrudan FifoKatman'a karsi dogrular, idempotent.
           Ref: sql-sp-reviewer CRIT-1 (2026-06-06). */
        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT s.StkId, @EnvanterTarihi, s.StokMiktar, 'FIYAT_YOK',
               'Acilis envanteri var; hicbir kaynak katman kuramadi (net guvenlik agi V2).'
        FROM #stoklar s
        WHERE (@StkId IS NULL OR s.StkId = @StkId)
          AND NOT EXISTS (
              SELECT 1 FROM dbo.FifoKatman k
              WHERE k.StkId = s.StkId AND k.GirisTarihi <= @EnvanterTarihi
          )
          AND NOT EXISTS (
              SELECT 1 FROM dbo.FifoSorunluStoklar fs
              WHERE fs.StkId = s.StkId AND fs.EnvanterTarihi = @EnvanterTarihi
                AND fs.SorunTipi IN ('FIYAT_YOK','ALIS_YOK')
          );

        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='TAMAMLANDI', @Mesaj=NULL;
        PRINT '      Sorun kayitlari tamamlandi. Sure: ' +
              CAST(DATEDIFF(SECOND, @fazBaslangic, SYSDATETIME()) AS VARCHAR(10)) + 's';

        COMMIT TRANSACTION;

        PRINT '========================================';
        PRINT 'sp_Fifo_AcilisCalistir_V2 tamamlandi';
        PRINT 'Tarih: ' + CONVERT(VARCHAR(10), @EnvanterTarihi, 120);
        PRINT 'Bitis: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 121);
        PRINT '========================================';

        RETURN; -- Basarili cikis

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        GOTO HataYonetimi;
    END CATCH

    -- ============================================================
    -- HATA YONETIMI (tum fazlardan ortak)
    -- ============================================================
    HataYonetimi:
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        DECLARE @ErrorLine INT = ERROR_LINE();
        DECLARE @runMessage VARCHAR(500) = SUBSTRING(CONVERT(VARCHAR(500), @ErrorMessage), 1, 500);

        IF @IslemId IS NOT NULL AND @stepKey IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz
                @IslemId = @IslemId,
                @AdimKodu = @stepKey,
                @AdimAdi = @stepName,
                @SiraNo = @stepOrder,
                @Durum = 'HATA',
                @Mesaj = @runMessage;

        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        VALUES (0, @EnvanterTarihi, 0, 'PROSEDUR_HATASI',
                'sp_Fifo_AcilisCalistir_V2 - Satir: ' + CAST(@ErrorLine AS VARCHAR(10)) +
                ' - ' + @ErrorMessage);

        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
END
GO

PRINT 'dbo.sp_Fifo_AcilisCalistir_V2 olusturuldu';
GO

GO
PRINT '======== 16 HareketliUrunListesi FINAL (07 yerine) ========';
GO
-- 16_V2_DevreDisiFiltre.sql
-- Devre disi urunleri tum FIFO islemlerinden haric tut
-- FifoDevreDisiUrunler tablosu 15_V2'de olusturuldu

-- ============================================================
-- 1) sp_Fifo_HareketliUrunListesi — son SELECT'e filtre ekle
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_Fifo_HareketliUrunListesi
(
    @Yil               INT,
    @Ay                INT,
    @DahilSatis        BIT = 1,
    @DahilAlis         BIT = 1,
    @DahilAktifKatman  BIT = 0
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @Yil IS NULL OR @Ay IS NULL OR @Ay NOT BETWEEN 1 AND 12
    BEGIN
        RAISERROR('Gecersiz yil/ay parametresi.', 16, 1);
        RETURN;
    END

    IF @DahilSatis = 0 AND @DahilAlis = 0 AND @DahilAktifKatman = 0
    BEGIN
        RAISERROR('En az bir dahil etme parametresi 1 olmali.', 16, 1);
        RETURN;
    END

    DECLARE @Baslangic DATE = DATEFROMPARTS(@Yil, @Ay, 1);
    DECLARE @Bitis     DATE = EOMONTH(@Baslangic);

    IF OBJECT_ID('tempdb..#hareketliUrunler', 'U') IS NOT NULL DROP TABLE #hareketliUrunler;
    CREATE TABLE #hareketliUrunler (StkId INT NOT NULL);
    CREATE INDEX IX_tmp_hareketli_StkId ON #hareketliUrunler(StkId);

    /* 1) Satis */
    IF @DahilSatis = 1
        INSERT INTO #hareketliUrunler (StkId)
        SELECT DISTINCT dt.ehStkId
        FROM $(ErpDb).dbo.irsAyr dt WITH(NOLOCK)
        JOIN $(ErpDb).dbo.irs bs  WITH(NOLOCK) ON dt.ehID = bs.eID
        WHERE bs.eTip   IN (1, 4, 5, 100, 101)
          AND bs.eMekan IN (1, 12, 4477, 4478)
          AND bs.eTarihS >= CONVERT(smalldatetime, @Baslangic)
          AND bs.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @Bitis));

    /* 2) Alis */
    IF @DahilAlis = 1
        INSERT INTO #hareketliUrunler (StkId)
        SELECT DISTINCT a.ehStkId
        FROM $(ErpDb).dbo.fatAyr a WITH(NOLOCK)
        JOIN $(ErpDb).dbo.fat   f WITH(NOLOCK) ON f.eID = a.ehID
        WHERE f.eTip   IN (0, 2)
          AND a.ehAdetN <> 0
          AND f.eTarihS >= CONVERT(smalldatetime, @Baslangic)
          AND f.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @Bitis));

    /* 3) Aktif katman */
    IF @DahilAktifKatman = 1
        INSERT INTO #hareketliUrunler (StkId)
        SELECT DISTINCT StkId
        FROM dbo.FifoKatman
        WHERE KalanMiktar > 0;

    /* DEVRE DISI FILTRE: tek tarama — filtreli set #sonuc'a materialize, sayimlar ucuz temp'ten */
    IF OBJECT_ID('tempdb..#sonuc', 'U') IS NOT NULL DROP TABLE #sonuc;
    SELECT DISTINCT h.StkId
    INTO #sonuc
    FROM #hareketliUrunler h
    WHERE NOT EXISTS (SELECT 1 FROM dbo.FifoDevreDisiUrunler dd WHERE dd.StkId = h.StkId);

    DECLARE @UrunSayisi      INT = (SELECT COUNT(*) FROM #sonuc);
    DECLARE @ToplamHareketli INT = (SELECT COUNT(DISTINCT StkId) FROM #hareketliUrunler);
    DECLARE @DevreDisiSayisi INT = @ToplamHareketli - @UrunSayisi;

    SELECT StkId FROM #sonuc ORDER BY StkId;
    PRINT 'sp_Fifo_HareketliUrunListesi: '
        + CAST(@Yil AS VARCHAR) + '-' + RIGHT('0' + CAST(@Ay AS VARCHAR), 2)
        + ' donemi icin '
        + CAST(@UrunSayisi AS VARCHAR) + ' hareketli urun bulundu'
        + CASE WHEN @DevreDisiSayisi > 0
            THEN ' (' + CAST(@DevreDisiSayisi AS VARCHAR) + ' devre disi urun haric tutuldu)'
            ELSE ''
          END + '.';

    DROP TABLE #hareketliUrunler;
END
GO
PRINT 'sp_Fifo_HareketliUrunListesi guncellendi (devre disi filtre).';
GO

-- ============================================================
-- 2) sp_Fifo_AylikCalistir — devre disi kontrolu
-- Mevcut SP'ye dokunmadan, App tarafinda filtreleniyor.
-- Ama guvenlik icin SP'ye de WHERE ekleyelim.
-- ============================================================
-- NOT: sp_Fifo_AylikCalistir tek StkId aliyor, App zaten
-- devre disi olanlari gondermeyecek. Ek filtre gereksiz.

-- ============================================================
-- 3) Snapshot (App tarafinda) — devre disi urunler snapshot'a
-- alinir (envanter dogrulugu icin) ama hesaplamadan atlanir.
-- Bu zaten HareketliUrunListesi filtresinde saglanir.
-- ============================================================

-- ============================================================
-- 4) V2 Acilis SP — devre disi urunleri haric tut
-- bkm.sp_fifo_StokMaliyetAcilis_V2 icindeki envanter sorgusuna
-- devre disi filtre ekle
-- ============================================================
-- NOT: V2 Acilis SP'si cok buyuk — sadece #stoklar olusturulduktan
-- sonra devre disi olanlari silmek en temiz yol.
-- App tarafinda (Wizard) da filtrelenecek.

PRINT 'Devre disi filtre uygulamasi tamamlandi.';
PRINT 'HareketliUrunListesi SP guncellendi.';
PRINT 'Diger SP''ler App tarafinda filtreleniyor (Wizard, Batch).';
GO

GO
PRINT '======== 15 Devre Disi Urunler ========';
GO
-- 15_V2_DevreDisiUrunler.sql
-- Devre disi birakilan urunler tablosu
-- FIFO hesaplamasinda haric tutulacak urunler

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'FifoDevreDisiUrunler' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.FifoDevreDisiUrunler (
        StkId INT NOT NULL,
        Sebep NVARCHAR(200) NULL,
        EkleyenKullanici NVARCHAR(50) NULL,
        EklenmeTarihi DATETIME2 NOT NULL DEFAULT GETDATE(),
        CONSTRAINT PK_FifoDevreDisiUrunler PRIMARY KEY (StkId)
    );
    PRINT 'FifoDevreDisiUrunler tablosu olusturuldu.';
END
GO

-- DevreDisi kontrolu icin view
CREATE OR ALTER VIEW dbo.vw_Fifo_DevreDisiUrunler
AS
SELECT
    d.StkId,
    d.Sebep,
    d.EkleyenKullanici,
    d.EklenmeTarihi
FROM dbo.FifoDevreDisiUrunler d;
GO
PRINT 'vw_Fifo_DevreDisiUrunler view olusturuldu.';

GO
PRINT '======== 17 Manuel Maliyet ========';
GO
-- 17_V2_ManuelMaliyet.sql
-- Manuel maliyet girisi tablosu
-- Kullanici tarafindan elle girilen birim maliyet degerleri
-- FIFO katmani olusturulmadan, raporlarda override olarak kullanilir

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'FifoManuelMaliyet' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.FifoManuelMaliyet (
        ManuelId     INT IDENTITY(1,1) NOT NULL,
        StkId        INT            NOT NULL,
        BirimMaliyet DECIMAL(18,6)  NOT NULL,
        GecerliBaslangic DATE      NOT NULL,
        GecerliBitis     DATE      NULL,   -- NULL = surekli gecerli
        Aciklama     NVARCHAR(200)  NULL,
        EkleyenKullanici NVARCHAR(50) NULL,
        EklenmeTarihi DATETIME2(0)  NOT NULL DEFAULT GETDATE(),
        Aktif        BIT            NOT NULL DEFAULT 1,
        CONSTRAINT PK_FifoManuelMaliyet PRIMARY KEY (ManuelId),
        CONSTRAINT CK_FifoManuelMaliyet_Maliyet CHECK (BirimMaliyet > 0),
        CONSTRAINT CK_FifoManuelMaliyet_Tarih CHECK (GecerliBitis IS NULL OR GecerliBitis >= GecerliBaslangic)
    );

    CREATE INDEX IX_FifoManuelMaliyet_StkId ON dbo.FifoManuelMaliyet (StkId, GecerliBaslangic)
        INCLUDE (BirimMaliyet, Aktif) WHERE Aktif = 1;

    PRINT 'FifoManuelMaliyet tablosu olusturuldu.';
END
GO

-- Aktif manuel maliyetleri gosteren view
CREATE OR ALTER VIEW dbo.vw_Fifo_ManuelMaliyet
AS
SELECT
    m.ManuelId,
    m.StkId,
    m.BirimMaliyet,
    m.GecerliBaslangic,
    m.GecerliBitis,
    m.Aciklama,
    m.EkleyenKullanici,
    m.EklenmeTarihi
FROM dbo.FifoManuelMaliyet m
WHERE m.Aktif = 1;
GO
PRINT 'vw_Fifo_ManuelMaliyet view olusturuldu.';

GO
PRINT '======== 18 Donem Kontrol + Snapshot ========';
GO
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

GO
PRINT '======== 03 Temel Viewlar ========';
GO
USE [$(MaliyetDb)];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER VIEW dbo.vw_Fifo_GunlukSMM
AS
SELECT
    HareketTarihi,
    MekanId,
    SUM(CASE WHEN HareketTipi = 'SATIS' THEN CikisTutar ELSE 0 END) AS SatisMaliyeti,
    SUM(CASE WHEN HareketTipi = 'IADE' THEN CikisTutar ELSE 0 END) AS IadeMaliyeti,
    SUM(CikisTutar) AS NetMaliyet,
    COUNT_BIG(*) AS SatirSayisi
FROM dbo.FifoCikisDetay
GROUP BY HareketTarihi, MekanId;
GO

CREATE OR ALTER VIEW dbo.vw_Fifo_UrunBazliSMM
AS
SELECT
    StkId,
    HareketTarihi,
    HareketTipi,
    MekanId,
    SUM(Miktar) AS ToplamMiktar,
    SUM(CikisTutar) AS ToplamMaliyet,
    CASE WHEN SUM(Miktar) = 0 THEN CAST(0 AS DECIMAL(18,6))
         ELSE CAST(SUM(CikisTutar) / SUM(Miktar) AS DECIMAL(18,6))
    END AS OrtalamaBirimMaliyet
FROM dbo.FifoCikisDetay
GROUP BY StkId, HareketTarihi, HareketTipi, MekanId;
GO

CREATE OR ALTER VIEW dbo.vw_Fifo_KatmanDurumu
AS
SELECT
    StkId,
    KaynakTip,
    GirisTarihi,
    COUNT_BIG(*) AS KatmanSayisi,
    SUM(GirisMiktar) AS ToplamMiktar,
    SUM(KalanMiktar) AS KalanMiktar,
    SUM(GirisMiktar - KalanMiktar) AS TuketilenMiktar,
    -- FIX: miktar-agirlikli ortalama (eski AVG(BirimMaliyet) = anlamsiz duz ortalama)
    CASE WHEN SUM(GirisMiktar) = 0 THEN CAST(0 AS DECIMAL(18,6))
         ELSE CAST(SUM(GirisMiktar * BirimMaliyet) / SUM(GirisMiktar) AS DECIMAL(18,6)) END AS OrtalamaBirimMaliyet,
    MIN(BirimMaliyet) AS MinBirimMaliyet,
    MAX(BirimMaliyet) AS MaxBirimMaliyet
FROM dbo.FifoKatman
GROUP BY StkId, KaynakTip, GirisTarihi;
GO

CREATE OR ALTER VIEW dbo.vw_Fifo_SorunluStoklar
AS
SELECT
    SorunTipi,
    EnvanterTarihi,
    MekanId,
    COUNT(DISTINCT StkId) AS UrunSayisi,
    SUM(StokMiktar) AS ToplamMiktar,
    MIN(KayitTarihi) AS IlkKayit,
    MAX(KayitTarihi) AS SonKayit
FROM dbo.FifoSorunluStoklar
GROUP BY SorunTipi, EnvanterTarihi, MekanId;
GO

CREATE OR ALTER VIEW dbo.vw_Fifo_AySonuBirimMaliyet
AS
SELECT
    GirisTarihi AS EnvanterTarihi,
    StkId,
    SUM(KalanMiktar) AS StokMiktar,
    CASE WHEN SUM(KalanMiktar) = 0 THEN CAST(0 AS DECIMAL(18,6))
         ELSE CAST(SUM(KalanMiktar * BirimMaliyet) / SUM(KalanMiktar) AS DECIMAL(18,6))
    END AS BirimMaliyet,
    CAST(SUM(KalanMiktar * BirimMaliyet) AS DECIMAL(18,4)) AS Tutar
FROM dbo.FifoKatman
GROUP BY GirisTarihi, StkId;
GO

GO
PRINT '======== 13 Eksik Viewlar ========';
GO
USE [$(MaliyetDb)];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
GO
SET NOCOUNT ON;
GO

-- =============================================================
-- vw_Ortalama_AySonuBirimMaliyet
-- OrtalamaAylikMaliyet tablosundan ay sonu birim maliyet ozeti.
-- FIFO tarafindaki vw_Fifo_AySonuBirimMaliyet'in Ortalama karsiligi.
-- =============================================================
CREATE OR ALTER VIEW dbo.vw_Ortalama_AySonuBirimMaliyet
AS
SELECT
    YilAy,
    StkId,
    AyBasiMiktar,
    AyBasiTutar,
    GirisMiktar,
    GirisTutar,
    CikisMiktar,
    AySonuMiktar,
    AySonuBirimMaliyet,
    AySonuTutar,
    CreateUtc,
    UpdateUtc
FROM dbo.OrtalamaAylikMaliyet;
GO

PRINT 'vw_Ortalama_AySonuBirimMaliyet olusturuldu';
GO

-- =============================================================
-- vw_MaliyetKarsilastirma
-- FIFO vs Ortalama maliyet yan yana karsilastirma.
--
-- FIFO tarafi: vw_Fifo_AySonuBirimMaliyet (katman bazli agirlikli ort)
--   GirisTarihi = envanter tarihi, StkId bazinda grup
-- Ortalama tarafi: OrtalamaAylikMaliyet (YilAy, StkId)
--
-- Join mantigi: FIFO'nun GirisTarihi ay sonu tarihine denk gelir
--   (ornek: 2025-12-31 acilis → YilAy 202601 ile eslesir)
--   Bu yuzden FIFO EnvanterTarihi'nden YilAy turetilir.
-- =============================================================
CREATE OR ALTER VIEW dbo.vw_MaliyetKarsilastirma
AS
SELECT
    o.YilAy,
    o.StkId,
    -- Ortalama Maliyet
    o.AySonuMiktar          AS Ort_Miktar,
    o.AySonuBirimMaliyet    AS Ort_BirimMaliyet,
    o.AySonuTutar           AS Ort_Tutar,
    -- FIFO Maliyet
    f.StokMiktar            AS Fifo_Miktar,
    f.BirimMaliyet          AS Fifo_BirimMaliyet,
    f.Tutar                 AS Fifo_Tutar,
    -- Fark
    CASE
        WHEN o.AySonuBirimMaliyet = 0 OR f.BirimMaliyet IS NULL THEN NULL
        ELSE CAST(f.BirimMaliyet - o.AySonuBirimMaliyet AS DECIMAL(18,6))
    END AS BirimMaliyetFarki,
    CASE
        WHEN o.AySonuBirimMaliyet = 0 OR f.BirimMaliyet IS NULL THEN NULL
        ELSE CAST(
            (f.BirimMaliyet - o.AySonuBirimMaliyet)
            / o.AySonuBirimMaliyet * 100
        AS DECIMAL(18,2))
    END AS FarkYuzdesi
FROM dbo.OrtalamaAylikMaliyet o
-- FIX: FIFO tarafi StkId basina TEK satira toplanir (eski hali GirisTarihi'ne grupluydu
--      -> StkId basina N satir -> StkId-only JOIN kartezyen carpim yapiyordu).
LEFT JOIN (
    SELECT
        StkId,
        SUM(KalanMiktar) AS StokMiktar,
        CASE WHEN SUM(KalanMiktar) = 0 THEN CAST(0 AS DECIMAL(18,6))
             ELSE CAST(SUM(KalanMiktar * BirimMaliyet) / SUM(KalanMiktar) AS DECIMAL(18,6)) END AS BirimMaliyet,
        CAST(SUM(KalanMiktar * BirimMaliyet) AS DECIMAL(18,4)) AS Tutar
    FROM dbo.FifoKatman
    WHERE KalanMiktar > 0
    GROUP BY StkId
) f ON f.StkId = o.StkId;
-- NOT: FIFO aylik snapshot tutmuyor -> her YilAy, GUNCEL FIFO stok maliyetiyle karsilastirilir.
GO

PRINT 'vw_MaliyetKarsilastirma olusturuldu';
GO

GO
PRINT '======== SEED Devre-disi + Fallback + ManuelMaliyet ========';
GO
/* =====================================================================
   19_V2_DevreDisi_Fallback_Seed.sql
   Ocak 2026 sorunlu urun temizligi — idempotent seed (rerun-safe).
   Kaynak: 2026-06-06 sorunlu urun tam taramasi (sorunlu-urun-dedektif).

   1) Non-inventory urunler FifoDevreDisiUrunler'e (gozle dogrulanmis, additive).
   2) Fiyatsiz gercek urunlere FifoFallbackFiyatlari (SonAlis veya SatisFiyat*0.65).

   NOT: FifoFallbackFiyatlari fallback'i acilis SP'sinde
        @fallbackSatinalmaSarti='DEVIR_FALLBACK' ile devreye girer.
   ===================================================================== */
SET XACT_ABORT ON;
SET NOCOUNT ON;

/* ---------- 1) NON-INVENTORY (additive, WHERE NOT EXISTS) ---------- */
INSERT INTO dbo.FifoDevreDisiUrunler (StkId, Sebep, EkleyenKullanici, EklenmeTarihi)
SELECT v.StkId, v.Sebep, 'claude-dedektif', SYSDATETIME()
FROM (VALUES
  -- gelir/gider kalemleri + hediye ceki + teshir/stand (SatisFiyat=0)
  (107911,  N'STAND BEDELSIZ - teshir/non-inventory'),
  (432001,  N'ALIS KARGO GIDERI TEVKIFATLI - gider/non-inventory'),
  (1596966, N'Bkmkitap 750TL Hediye Ceki - non-inventory'),
  (144860,  N'KARGO GELIRI - gelir kalemi/non-inventory'),
  (144963,  N'KAPIDA ODEME GELIRI - gelir kalemi/non-inventory'),
  (436306,  N'KOMISYON BEDELI - gelir kalemi/non-inventory'),
  -- demirbas / sabit kiymet (SatisFiyat=0)
  (275486,  N'ISYERI DEMIRBASLARI - sabit kiymet'),
  (248339,  N'ISYERI DEMIRBASLARI - sabit kiymet'),
  (269485,  N'ISYERI MOBILYALARI - sabit kiymet'),
  (105512,  N'KAFETERYA DEMIRBASLARI - sabit kiymet'),
  (431951,  N'KLIMA - sabit kiymet'),
  (438548,  N'FOTOGRAF MAKINESI - sabit kiymet'),
  (179941,  N'YAZARKASA - sabit kiymet'),
  (105513,  N'YENI NESIL YAZAR KASA - sabit kiymet')
) v(StkId, Sebep)
WHERE NOT EXISTS (SELECT 1 FROM dbo.FifoDevreDisiUrunler d WHERE d.StkId = v.StkId);

/* ---------- 2) FALLBACK FIYAT (fiyatsiz gercek urunler) ----------
   FIYAT_YOK + kaynakta (fytOzl) fiyat yok + devre-disi degil + (SonAlis>0 OR SatisFiyat>0).
   BirimMaliyet = SonAlis (varsa) yoksa SatisFiyat*0.65 (%35 marj tahmini).
   UYARI: SatisFiyat*0.65 = TAHMIN, gercek fatura gelince override edilmeli. */
;WITH fy AS (
  SELECT DISTINCT s.StkId FROM dbo.FifoSorunluStoklar s
  WHERE s.SorunTipi = 'FIYAT_YOK'
    AND NOT EXISTS (SELECT 1 FROM $(ErpDb).dbo.fytOzl f
                    WHERE f.fStkID = s.StkId AND f.fTarih <= '2025-12-31')
    AND NOT EXISTS (SELECT 1 FROM dbo.FifoDevreDisiUrunler d WHERE d.StkId = s.StkId)
)
INSERT INTO dbo.FifoFallbackFiyatlari
    (StkId, SatinalmaSarti, MekanId, BirimMaliyet, Miktar, ToplamTutar, Aciklama, KayitTarihi)
SELECT fy.StkId, 'DEVIR_FALLBACK', 0,
  CASE WHEN u.SonAlis > 0 THEN u.SonAlis ELSE CAST(u.SatisFiyat * 0.65 AS DECIMAL(18,6)) END,
  1,
  CASE WHEN u.SonAlis > 0 THEN u.SonAlis ELSE CAST(u.SatisFiyat * 0.65 AS DECIMAL(18,6)) END,
  CASE WHEN u.SonAlis > 0 THEN N'SonAlis fallback' ELSE N'SatisFiyat*0.65 tahmini' END,
  SYSDATETIME()
FROM fy
JOIN $(ErpDb).dbo.UrunBilgi u ON u.stkID = fy.StkId
WHERE (u.SonAlis > 0 OR u.SatisFiyat > 0)
  AND NOT EXISTS (SELECT 1 FROM dbo.FifoFallbackFiyatlari ff
                  WHERE ff.StkId = fy.StkId AND ff.SatinalmaSarti = 'DEVIR_FALLBACK' AND ff.MekanId = 0);

/* ---------- 3) COST ANOMALI — MANUEL MALIYET OVERRIDE ----------
   ERP SonAlis koli/qty hatasi olan urunler (BirimMaliyet >> SatisFiyat).
   Acilis SP'si FifoManuelMaliyet'i en yuksek oncelikli kaynak olarak ezer.
   Tahmin = SatisFiyat*0.65; gercek fatura koli teyidi sonrasi guncellenecek.
   Karne Hediyesi (200772) HARIC — anomalisi gelir tarafi (SatisFiyat=0.01 kasitli). */
;WITH anomali AS (
  SELECT v.StkId FROM (VALUES
    (1690718),(1690719),(1690720),(1690721), -- Okapi Kalem Cantasi x4
    (1559504),(1627067),(500233),(259297),(1607635),
    (1628142),(1648583),(175537),(203436),(153251)
  ) v(StkId)
)
INSERT INTO dbo.FifoManuelMaliyet (StkId, BirimMaliyet, GecerliBaslangic, GecerliBitis, Aciklama, EkleyenKullanici, Aktif)
SELECT a.StkId, CAST(u.SatisFiyat * 0.65 AS DECIMAL(18,6)), '2025-12-31', NULL,
       N'Cost anomali (ERP SonAlis koli/qty hatasi). Tahmin=SatisFiyat*0.65, fatura teyidi sonrasi guncelle.',
       'claude-dedektif', 1
FROM anomali a
JOIN $(ErpDb).dbo.UrunBilgi u ON u.stkID = a.StkId
WHERE u.SatisFiyat > 0
  AND NOT EXISTS (SELECT 1 FROM dbo.FifoManuelMaliyet m WHERE m.StkId = a.StkId AND m.Aktif = 1);

PRINT 'Devre-disi + fallback + manuel-maliyet seed tamamlandi. Acilis re-run: @fallbackSatinalmaSarti=''DEVIR_FALLBACK''.';

GO
PRINT '### FIFO V2 MASTER bitti';
GO
