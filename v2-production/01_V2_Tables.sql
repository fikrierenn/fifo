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

