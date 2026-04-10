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
