-- =============================================================
-- 01_sp_CreateTables.sql
-- Tum tablolari ve indeksleri olusturur
-- =============================================================

IF OBJECT_ID('bkm.sp_CreateTables', 'P') IS NOT NULL
    DROP PROCEDURE bkm.sp_CreateTables;
GO

CREATE PROCEDURE bkm.sp_CreateTables
AS
BEGIN
    SET NOCOUNT ON;
    
    PRINT '========================================';
    PRINT 'TABLOLAR VE INDEKSLER OLUSTURULUYOR';
    PRINT '========================================';
    
    -- Schema olustur
    IF SCHEMA_ID('bkm') IS NULL
    BEGIN
        EXEC('CREATE SCHEMA bkm');
        PRINT 'bkm schema olusturuldu';
    END
    
    -- 1.1) Stok Maliyet Havuzu
    IF OBJECT_ID('bkm.fifo_StokMaliyetHavuzu', 'U') IS NOT NULL
        DROP TABLE bkm.fifo_StokMaliyetHavuzu;
    
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
    
    CREATE INDEX IX_fifo_StokMaliyetHavuzu_stkID
        ON bkm.fifo_StokMaliyetHavuzu(stkID, girisTarihi, kaynakTip);
    
    CREATE INDEX IX_fifo_StokMaliyetHavuzu_AktifKatman
        ON bkm.fifo_StokMaliyetHavuzu(stkID, girisTarihi, kaynakTip)
        INCLUDE (miktarKalan, birimMaliyet)
        WHERE miktarKalan > 0;
    
    PRINT 'fifo_StokMaliyetHavuzu tablosu olusturuldu';
    
    -- 1.2) Stok Envanter
    IF OBJECT_ID('bkm.fifo_StokEnvanter', 'U') IS NOT NULL
        DROP TABLE bkm.fifo_StokEnvanter;
    
    CREATE TABLE bkm.fifo_StokEnvanter (
        ID             INT IDENTITY(1,1) PRIMARY KEY,
        envanterTarihi DATE            NOT NULL,
        mekanID        INT             NOT NULL,
        stkID          INT             NOT NULL,
        stokMiktar     DECIMAL(18,4)   NOT NULL,
        kayitTarihi    DATETIME        NOT NULL DEFAULT(GETDATE())
    );
    
    CREATE INDEX IX_fifo_StokEnvanter_TarihMekanStok
        ON bkm.fifo_StokEnvanter(envanterTarihi, mekanID, stkID);
    
    PRINT 'fifo_StokEnvanter tablosu olusturuldu';
    
    -- 1.3) Stok Maliyet Sorunlu
    IF OBJECT_ID('bkm.fifo_StokMaliyetSorunlu', 'U') IS NOT NULL
        DROP TABLE bkm.fifo_StokMaliyetSorunlu;
    
    CREATE TABLE bkm.fifo_StokMaliyetSorunlu (
        ID             INT IDENTITY(1,1) PRIMARY KEY,
        stkID          INT             NOT NULL,
        envanterTarihi DATE            NOT NULL,
        stokMiktar     DECIMAL(18,4)   NOT NULL,
        sorunTip       VARCHAR(50)     NOT NULL,
        aciklama       VARCHAR(500)    NULL,
        kayitTarihi    DATETIME        NOT NULL DEFAULT(GETDATE())
    );
    
    CREATE INDEX IX_fifo_StokMaliyetSorunlu_TarihStok
        ON bkm.fifo_StokMaliyetSorunlu(envanterTarihi, stkID);
    
    CREATE INDEX IX_fifo_StokMaliyetSorunlu_Tip
        ON bkm.fifo_StokMaliyetSorunlu(sorunTip, envanterTarihi)
        INCLUDE (stkID, stokMiktar);
    
    CREATE INDEX IX_fifo_StokMaliyetSorunlu_KayitTarihi
        ON bkm.fifo_StokMaliyetSorunlu(kayitTarihi, sorunTip)
        INCLUDE (envanterTarihi, stkID, stokMiktar, aciklama);
    
    PRINT 'fifo_StokMaliyetSorunlu tablosu olusturuldu';
    
    -- 1.4) ERP Devir Fiyatlari
    IF OBJECT_ID('bkm.fifo_ErpDevirFiyatlari', 'U') IS NOT NULL
        DROP TABLE bkm.fifo_ErpDevirFiyatlari;
    
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
    
    CREATE INDEX IX_fifo_ErpDevirFiyatlari_SatinalmaSarti
        ON bkm.fifo_ErpDevirFiyatlari(satinalmaSarti)
        INCLUDE (birimMaliyet, miktar);
    
    PRINT 'fifo_ErpDevirFiyatlari tablosu olusturuldu';
    
    -- 1.5) Stok Maliyet Çıkış
    IF OBJECT_ID('bkm.fifo_StokMaliyetCikis', 'U') IS NOT NULL
        DROP TABLE bkm.fifo_StokMaliyetCikis;
    
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
    
    CREATE INDEX IX_fifo_StokMaliyetCikis_StokTarih
        ON bkm.fifo_StokMaliyetCikis(stkID, hareketTarihi);
    
    CREATE INDEX IX_fifo_StokMaliyetCikis_Tarih
        ON bkm.fifo_StokMaliyetCikis(hareketTarihi) 
        INCLUDE (hareketTipi, cikisTutar);
    
    CREATE INDEX IX_fifo_StokMaliyetCikis_Tip
        ON bkm.fifo_StokMaliyetCikis(hareketTipi, hareketTarihi)
        INCLUDE (stkID, cikisTutar);
    
    PRINT 'fifo_StokMaliyetCikis tablosu olusturuldu';
    
    -- 1.6) Calistirma Run
    IF OBJECT_ID('bkm.fifo_Run', 'U') IS NOT NULL
        DROP TABLE bkm.fifo_Run;
    
    CREATE TABLE bkm.fifo_Run (
        runId       UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
        runType     VARCHAR(20)      NOT NULL,
        status      VARCHAR(20)      NOT NULL,
        requestedAt DATETIME         NOT NULL DEFAULT(GETDATE()),
        startedAt   DATETIME         NULL,
        endedAt     DATETIME         NULL,
        message     VARCHAR(500)     NULL
    );
    
    CREATE INDEX IX_fifo_Run_Status
        ON bkm.fifo_Run(status, requestedAt);
    
    PRINT 'fifo_Run tablosu olusturuldu';
    
    -- 1.7) Calistirma Run Adimlari
    IF OBJECT_ID('bkm.fifo_RunStep', 'U') IS NOT NULL
        DROP TABLE bkm.fifo_RunStep;
    
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
    
    CREATE INDEX IX_fifo_RunStep_Run
        ON bkm.fifo_RunStep(runId, stepOrder);
    
    PRINT 'fifo_RunStep tablosu olusturuldu';
    
    PRINT '';
    PRINT 'Tum tablolar ve indeksler basariyla olusturuldu!';
    PRINT '========================================';
END
GO

PRINT 'sp_CreateTables proseduru olusturuldu';
GO
