/* DerinSIS_Local — lokal demo ERP kaynak semasi (minimal, SP'lerin kullandigi kolonlar).
   Canli DerinSISBkm'den repoint edilen SP'ler buraya bakar. Sadece demo. */
USE DerinSIS_Local;
GO

/* ---- irsHrk: stok hareketleri (envanter snapshot + ay-sonu stok + satis tutar backfill) ---- */
IF OBJECT_ID('dbo.irsHrk','U') IS NOT NULL DROP TABLE dbo.irsHrk;
CREATE TABLE dbo.irsHrk (
    ehMekan   INT           NOT NULL,
    ehstkID   INT           NOT NULL,
    ehTrhS    SMALLDATETIME NOT NULL,
    ehAdetN   DECIMAL(15,3) NOT NULL,
    ehTutarN  DECIMAL(15,3) NOT NULL,
    ehAltDepo TINYINT       NOT NULL
);
CREATE INDEX IX_irsHrk_stk ON dbo.irsHrk(ehstkID, ehMekan, ehTrhS) INCLUDE(ehAdetN, ehTutarN, ehAltDepo);
GO

/* ---- fat / fatAyr: alis faturalari ---- */
IF OBJECT_ID('dbo.fat','U') IS NOT NULL DROP TABLE dbo.fat;
CREATE TABLE dbo.fat (
    eID     INT           NOT NULL PRIMARY KEY,
    eNo     VARCHAR(50)   NULL,
    eTarihS SMALLDATETIME NOT NULL,
    eTarih  SMALLDATETIME NULL,
    eTip    TINYINT       NOT NULL,
    eGC     TINYINT       NOT NULL,
    eFirma  INT           NULL
);
GO
IF OBJECT_ID('dbo.fatAyr','U') IS NOT NULL DROP TABLE dbo.fatAyr;
CREATE TABLE dbo.fatAyr (
    ehID      INT           NOT NULL,
    ehStkID   INT           NOT NULL,
    ehAdetN   DECIMAL(15,3) NOT NULL,
    ehTutarN  DECIMAL(15,2) NOT NULL,
    ehIrsID   INT           NULL,
    ehIrsSira INT           NULL
);
CREATE INDEX IX_fatAyr_stk ON dbo.fatAyr(ehStkID, ehID);
CREATE INDEX IX_fatAyr_irs ON dbo.fatAyr(ehIrsID, ehIrsSira);
GO

/* ---- irs / irsAyr: satis irsaliyeleri ---- */
IF OBJECT_ID('dbo.irs','U') IS NOT NULL DROP TABLE dbo.irs;
CREATE TABLE dbo.irs (
    eID     INT           NOT NULL PRIMARY KEY,
    eTip    TINYINT       NOT NULL,
    eTarihS SMALLDATETIME NOT NULL,
    eTarih  SMALLDATETIME NULL,
    eMekan  INT           NOT NULL
);
GO
IF OBJECT_ID('dbo.irsAyr','U') IS NOT NULL DROP TABLE dbo.irsAyr;
CREATE TABLE dbo.irsAyr (
    ehID    INT           NOT NULL,
    ehSira  INT           NOT NULL,
    ehStkID INT           NOT NULL,
    ehAdet  DECIMAL(15,3) NOT NULL
);
CREATE INDEX IX_irsAyr_id ON dbo.irsAyr(ehID, ehSira);
CREATE INDEX IX_irsAyr_stk ON dbo.irsAyr(ehStkID);
GO

/* ---- bkm sema + fn_SonGecerliFiyat STUB'lari (top-sellers'da fallback tetiklenmez; bos doner) ---- */
IF SCHEMA_ID('bkm') IS NULL EXEC('CREATE SCHEMA bkm');
GO
CREATE OR ALTER FUNCTION bkm.fn_SonGecerliFiyat(@tarih DATE, @x INT)
RETURNS TABLE AS RETURN
    SELECT CAST(NULL AS INT) AS fhID, CAST(NULL AS INT) AS fStkId,
           CAST(NULL AS DATE) AS fTarih, CAST(NULL AS DATE) AS fTarihSon,
           CAST(NULL AS DECIMAL(18,6)) AS sonrakiNet
    WHERE 1=0;
GO
CREATE OR ALTER FUNCTION bkm.fn_SonGecerliFiyat_Adv(@tarih DATE, @a INT, @b INT, @c INT)
RETURNS TABLE AS RETURN
    SELECT CAST(NULL AS INT) AS fStkID, CAST(NULL AS DECIMAL(18,6)) AS sonrakiNet,
           CAST(NULL AS INT) AS fFrmID, CAST(NULL AS DATE) AS fTarihSon, CAST(NULL AS INT) AS fhID
    WHERE 1=0;
GO
PRINT 'DerinSIS_Local semasi hazir (5 tablo + 2 TVF stub).';
GO
