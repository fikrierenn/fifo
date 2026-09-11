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
SET NOCOUNT ON;
GO
/* ============================================================
   FIFO V2 TABLES (dbo)  —  IDEMPOTENT / VERI KAYBETTIRMEZ

   2026-09-10 REVIZYON:
     Eski surum bu noktada 7 cekirdek tabloyu (FifoKatman, FifoCikisDetay,
     MaliyetIslem dahil) KOSULSUZ DROP ediyordu. Master deploy dolu bir
     veritabaninda ikinci kez calistirildiginda tum maliyet defteri siliniyordu.
     Artik her nesne yalnizca YOKSA olusturulur; mevcut veri korunur.

     Bilincli sifirlama gerekiyorsa: 01a_V2_Tables_RESET.sql (master'a DAHIL DEGIL,
     acik onay degiskeni ister).
   ============================================================ */

/* ------------------------------------------------------------
   FifoKatman — FIFO maliyet katmanlari (maliyet defteri)
   ------------------------------------------------------------ */
IF OBJECT_ID('dbo.FifoKatman','U') IS NULL
BEGIN
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
        -- FIYAT 0 OLAMAZ (fifo-domain.md §6): stogu olan katman POZITIF maliyet tasir.
        -- Sifir maliyet = %100 marj = sessiz yanlis kar.
        CONSTRAINT CK_FifoKatman_BirimMaliyet CHECK (BirimMaliyet > 0)
    );
    PRINT 'dbo.FifoKatman olusturuldu.';
END
ELSE
    PRINT 'dbo.FifoKatman zaten var — korundu.';
GO

/* Mevcut kurulumlarda §6 kapisini GARANTI ALTINA AL.
   Tetikleyici olarak "eski tanim var mi" YETMEZ: constraint biri tarafindan DROP
   edilmis, WITH NOCHECK ile guvenilmez birakilmis veya disable edilmis olabilir.
   O durumda tablo hicbir maliyet kapisi olmadan kalir ve script "tamam" derdi.
   Bu yuzden kosul "DOGRU HALIYLE, ETKIN ve GUVENILIR sekilde var mi" seklinde kurulur. */
IF OBJECT_ID('dbo.FifoKatman','U') IS NOT NULL
   AND NOT EXISTS (
        SELECT 1 FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID('dbo.FifoKatman')
          AND name         = 'CK_FifoKatman_BirimMaliyet'
          AND definition   = '([BirimMaliyet]>(0))'
          AND is_disabled  = 0
          AND is_not_trusted = 0
   )
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.FifoKatman WHERE BirimMaliyet <= 0)
    BEGIN
        DECLARE @ihlal INT = (SELECT COUNT(*) FROM dbo.FifoKatman WHERE BirimMaliyet <= 0);
        PRINT '!!! UYARI: FifoKatman icinde BirimMaliyet <= 0 olan ' + CAST(@ihlal AS VARCHAR(20)) +
              ' satir var. CK_FifoKatman_BirimMaliyet KURULAMADI — §6 KAPISI ACIK.';
        PRINT '!!! Once bu satirlari fiyatlandirin (bkz. fifo-domain.md §6), sonra tekrar calistirin.';

        -- Uyari PRINT'te kalirsa otomasyonda kaybolur; kalici denetim izi birak.
        IF OBJECT_ID('dbo.FifoSorunluStoklar','U') IS NOT NULL
        BEGIN
            DELETE FROM dbo.FifoSorunluStoklar
            WHERE EnvanterTarihi = CAST('1900-01-01' AS DATE)
              AND MekanId = 0 AND StkId = 0 AND SorunTipi = 'CONSTRAINT_KURULAMADI';

            INSERT INTO dbo.FifoSorunluStoklar
                (StkId, EnvanterTarihi, MekanId, StokMiktar, SorunTipi, Aciklama)
            VALUES (0, CAST('1900-01-01' AS DATE), 0, 0, 'CONSTRAINT_KURULAMADI',
                    CONVERT(NVARCHAR(500),
                        CONCAT(N'CK_FifoKatman_BirimMaliyet kurulamadi: BirimMaliyet<=0 satir sayisi ',
                               @ihlal, N'. Deploy devam etti, §6 kapisi ACIK.')));
        END
    END
    ELSE
    BEGIN
        IF EXISTS (SELECT 1 FROM sys.check_constraints
                   WHERE parent_object_id = OBJECT_ID('dbo.FifoKatman')
                     AND name = 'CK_FifoKatman_BirimMaliyet')
            ALTER TABLE dbo.FifoKatman DROP CONSTRAINT CK_FifoKatman_BirimMaliyet;

        ALTER TABLE dbo.FifoKatman WITH CHECK
            ADD CONSTRAINT CK_FifoKatman_BirimMaliyet CHECK (BirimMaliyet > 0);
        PRINT 'CK_FifoKatman_BirimMaliyet kuruldu/sikilastirildi: BirimMaliyet > 0.';
    END
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_FifoKatman_Stk_Tarih' AND object_id = OBJECT_ID('dbo.FifoKatman'))
    CREATE INDEX IX_FifoKatman_Stk_Tarih
        ON dbo.FifoKatman(StkId, GirisTarihi, KaynakTip, KatmanId);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_FifoKatman_Aktif' AND object_id = OBJECT_ID('dbo.FifoKatman'))
    CREATE INDEX IX_FifoKatman_Aktif
        ON dbo.FifoKatman(StkId, GirisTarihi, KaynakTip, KatmanId)
        INCLUDE (KalanMiktar, BirimMaliyet, BelgeNo, BelgeTarihi)
        WHERE KalanMiktar > 0;
GO

/* ------------------------------------------------------------
   FifoAcilisEnvanter — acilis stok snapshot
   ------------------------------------------------------------ */
IF OBJECT_ID('dbo.FifoAcilisEnvanter','U') IS NULL
BEGIN
    CREATE TABLE dbo.FifoAcilisEnvanter (
        EnvanterTarihi DATE NOT NULL,
        MekanId INT NOT NULL,
        StkId INT NOT NULL,
        StokMiktar DECIMAL(18,4) NOT NULL,
        KayitTarihi DATETIME2(0) NOT NULL CONSTRAINT DF_FifoAcilisEnvanter_Kayit DEFAULT (GETDATE()),
        CONSTRAINT PK_FifoAcilisEnvanter PRIMARY KEY (EnvanterTarihi, MekanId, StkId),
        CONSTRAINT CK_FifoAcilisEnvanter_Stok CHECK (StokMiktar >= 0)
    );
    PRINT 'dbo.FifoAcilisEnvanter olusturuldu.';
END
ELSE
    PRINT 'dbo.FifoAcilisEnvanter zaten var — korundu.';
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_FifoAcilisEnvanter_Stk' AND object_id = OBJECT_ID('dbo.FifoAcilisEnvanter'))
    CREATE INDEX IX_FifoAcilisEnvanter_Stk
        ON dbo.FifoAcilisEnvanter(StkId, EnvanterTarihi, MekanId)
        INCLUDE (StokMiktar);
GO

/* ------------------------------------------------------------
   FifoSorunluStoklar — sorun kayitlari
   ------------------------------------------------------------ */
IF OBJECT_ID('dbo.FifoSorunluStoklar','U') IS NULL
BEGIN
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
    PRINT 'dbo.FifoSorunluStoklar olusturuldu.';
END
ELSE
    PRINT 'dbo.FifoSorunluStoklar zaten var — korundu.';
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_FifoSorunluStoklar_TarihStkMekan' AND object_id = OBJECT_ID('dbo.FifoSorunluStoklar'))
    CREATE INDEX IX_FifoSorunluStoklar_TarihStkMekan
        ON dbo.FifoSorunluStoklar(EnvanterTarihi, StkId, MekanId);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_FifoSorunluStoklar_TipTarih' AND object_id = OBJECT_ID('dbo.FifoSorunluStoklar'))
    CREATE INDEX IX_FifoSorunluStoklar_TipTarih
        ON dbo.FifoSorunluStoklar(SorunTipi, EnvanterTarihi)
        INCLUDE (StkId, MekanId, StokMiktar);
GO

/* ------------------------------------------------------------
   FifoFallbackFiyatlari — fallback fiyat kaynagi
   ------------------------------------------------------------ */
IF OBJECT_ID('dbo.FifoFallbackFiyatlari','U') IS NULL
BEGIN
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
    PRINT 'dbo.FifoFallbackFiyatlari olusturuldu.';
END
ELSE
    PRINT 'dbo.FifoFallbackFiyatlari zaten var — korundu.';
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_FifoFallbackFiyatlari_Satinalma' AND object_id = OBJECT_ID('dbo.FifoFallbackFiyatlari'))
    CREATE INDEX IX_FifoFallbackFiyatlari_Satinalma
        ON dbo.FifoFallbackFiyatlari(SatinalmaSarti, StkId, MekanId)
        INCLUDE (BirimMaliyet, Miktar, ToplamTutar);
GO

/* ------------------------------------------------------------
   FifoCikisDetay — FIFO cikis (SMM) detayi
   ------------------------------------------------------------ */
IF OBJECT_ID('dbo.FifoCikisDetay','U') IS NULL
BEGIN
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
        CONSTRAINT CK_FifoCikisDetay_Miktar CHECK (Miktar > 0),
        -- FIYAT 0 OLAMAZ (§6) cikis tarafinda da zorlanir. Cikis birim maliyeti
        -- katmandan KOPYALANIR; katman > 0 ise cikis da > 0 olmak zorundadir.
        CONSTRAINT CK_FifoCikisDetay_BirimMaliyet CHECK (BirimMaliyet > 0)
    );
    PRINT 'dbo.FifoCikisDetay olusturuldu.';
END
ELSE
    PRINT 'dbo.FifoCikisDetay zaten var — korundu.';
GO

/* Mevcut kurulumlara cikis-tarafi §6 kapisini ekle. Ihlal varsa PATLAMAZ, uyarir. */
IF OBJECT_ID('dbo.FifoCikisDetay','U') IS NOT NULL
   AND NOT EXISTS (
        SELECT 1 FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID('dbo.FifoCikisDetay')
          AND name           = 'CK_FifoCikisDetay_BirimMaliyet'
          AND definition     = '([BirimMaliyet]>(0))'
          AND is_disabled    = 0
          AND is_not_trusted = 0
   )
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.FifoCikisDetay WHERE BirimMaliyet <= 0)
    BEGIN
        DECLARE @ihlalCikis INT = (SELECT COUNT(*) FROM dbo.FifoCikisDetay WHERE BirimMaliyet <= 0);
        PRINT '!!! UYARI: FifoCikisDetay icinde BirimMaliyet <= 0 olan ' + CAST(@ihlalCikis AS VARCHAR(20)) +
              ' satir var. CK_FifoCikisDetay_BirimMaliyet KURULAMADI — §6 kapisi cikis tarafinda ACIK.';
    END
    ELSE
    BEGIN
        IF EXISTS (SELECT 1 FROM sys.check_constraints
                   WHERE parent_object_id = OBJECT_ID('dbo.FifoCikisDetay')
                     AND name = 'CK_FifoCikisDetay_BirimMaliyet')
            ALTER TABLE dbo.FifoCikisDetay DROP CONSTRAINT CK_FifoCikisDetay_BirimMaliyet;

        ALTER TABLE dbo.FifoCikisDetay WITH CHECK
            ADD CONSTRAINT CK_FifoCikisDetay_BirimMaliyet CHECK (BirimMaliyet > 0);
        PRINT 'CK_FifoCikisDetay_BirimMaliyet kuruldu: BirimMaliyet > 0.';
    END
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_FifoCikisDetay_StkTarih' AND object_id = OBJECT_ID('dbo.FifoCikisDetay'))
    CREATE INDEX IX_FifoCikisDetay_StkTarih
        ON dbo.FifoCikisDetay(StkId, HareketTarihi)
        INCLUDE (MekanId, HareketTipi, Miktar, CikisTutar, KatmanId);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_FifoCikisDetay_MekanTarih' AND object_id = OBJECT_ID('dbo.FifoCikisDetay'))
    CREATE INDEX IX_FifoCikisDetay_MekanTarih
        ON dbo.FifoCikisDetay(MekanId, HareketTarihi)
        INCLUDE (StkId, HareketTipi, Miktar, CikisTutar, KatmanId);
GO

/* ------------------------------------------------------------
   MaliyetIslem / MaliyetIslemAdim — islem log (denetim izi)
   ------------------------------------------------------------ */
IF OBJECT_ID('dbo.MaliyetIslem','U') IS NULL
BEGIN
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
    PRINT 'dbo.MaliyetIslem olusturuldu.';
END
ELSE
    PRINT 'dbo.MaliyetIslem zaten var — korundu.';
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_MaliyetIslem_Durum' AND object_id = OBJECT_ID('dbo.MaliyetIslem'))
    CREATE INDEX IX_MaliyetIslem_Durum
        ON dbo.MaliyetIslem(Durum, Baslangic DESC)
        INCLUDE (Bitis, IslemAdi, StkId, MekanId, EnvanterTarihi);
GO

IF OBJECT_ID('dbo.MaliyetIslemAdim','U') IS NULL
BEGIN
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
    PRINT 'dbo.MaliyetIslemAdim olusturuldu.';
END
ELSE
    PRINT 'dbo.MaliyetIslemAdim zaten var — korundu.';
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_MaliyetIslemAdim_Sira' AND object_id = OBJECT_ID('dbo.MaliyetIslemAdim'))
    CREATE INDEX IX_MaliyetIslemAdim_Sira
        ON dbo.MaliyetIslemAdim(IslemId, SiraNo)
        INCLUDE (AdimKodu, Durum, Baslangic, Bitis, Mesaj);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_MaliyetIslemAdim_AdimKodu' AND object_id = OBJECT_ID('dbo.MaliyetIslemAdim'))
    CREATE INDEX IX_MaliyetIslemAdim_AdimKodu
        ON dbo.MaliyetIslemAdim(AdimKodu, Guncelleme DESC)
        INCLUDE (IslemId, SiraNo, Durum);
GO

PRINT '01_V2_Tables tamamlandi (idempotent — mevcut veri korundu).';
GO
