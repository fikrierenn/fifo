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
