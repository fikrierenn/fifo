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
