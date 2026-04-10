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

