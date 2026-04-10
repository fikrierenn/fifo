-- =============================================================
-- BKM FIFO MASTER DEPLOY V2 (Standalone)
-- Base install + Sprint 1 + Sprint 2 in a single script.
-- Source: 00_MASTER_DEPLOY.sql + SQL-Improvements\01/02
-- =============================================================
-- =============================================================
-- BKM FIFO STOK MALIYET SISTEMI - MASTER DEPLOYMENT SCRIPT
-- Tum bilesenleri sirayla calistirir
-- =============================================================
USE BKMMaliyet;

GO
PRINT '========================================';
PRINT 'BKM FIFO STOK MALIYET SISTEMI';
PRINT 'Deployment basliyor...';
PRINT '========================================';
PRINT '';

PRINT '1/6 - Tablolar ve indeksler olusturuluyor...';

-- =============================================================
-- BKM FIFO STOK MALAYET SASTEMA - TABLOLAR VE ANDEKSLER
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
    hareketMekanID  INT             NULL,
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

CREATE INDEX IX_fifo_StokMaliyetCikis_MekanTarih
    ON bkm.fifo_StokMaliyetCikis(hareketMekanID, hareketTarihi)
    INCLUDE (stkID, hareketTipi, miktar, cikisTutar);
GO


-- 1.6) Calistirma Run Adimlari
IF OBJECT_ID('bkm.fifo_CalistirmaAdim', 'U') IS NOT NULL
    DROP TABLE bkm.fifo_CalistirmaAdim;
GO

CREATE TABLE bkm.fifo_CalistirmaAdim (
    calistirmaId     UNIQUEIDENTIFIER NOT NULL,
    adimKodu   VARCHAR(50)      NOT NULL,
    adimAdi  VARCHAR(100)     NOT NULL,
    adimSirasi INT              NOT NULL,
    durum    VARCHAR(20)      NOT NULL,
    mesaj     VARCHAR(500)     NULL,
    baslamaTarihi DATETIME         NULL,
    bitisTarihi   DATETIME         NULL,
    guncellemeTarihi DATETIME         NOT NULL DEFAULT(GETDATE()),
    CONSTRAINT PK_fifo_CalistirmaAdim PRIMARY KEY (calistirmaId, adimKodu)
);
GO

CREATE INDEX IX_fifo_CalistirmaAdim_Run
    ON bkm.fifo_CalistirmaAdim(calistirmaId, adimSirasi);
GO

-- 1.7) Calistirma Run
IF OBJECT_ID('bkm.fifo_Calistirma', 'U') IS NOT NULL
    DROP TABLE bkm.fifo_Calistirma;
GO

CREATE TABLE bkm.fifo_Calistirma (
    calistirmaId       UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    calistirmaTipi     VARCHAR(20)      NOT NULL,
    durum      VARCHAR(20)      NOT NULL,
    talepTarihi DATETIME         NOT NULL DEFAULT(GETDATE()),
    baslamaTarihi   DATETIME         NULL,
    bitisTarihi     DATETIME         NULL,
    mesaj       VARCHAR(500)     NULL
);
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_fifo_Calistirma_Status'
      AND object_id = OBJECT_ID('bkm.fifo_Calistirma')
)
BEGIN
    CREATE INDEX IX_fifo_Calistirma_Status
        ON bkm.fifo_Calistirma(durum, talepTarihi);
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
