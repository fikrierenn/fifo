-- =============================================================
-- RAPORLAMA VIEW'LARI
-- =============================================================

-- Günlük SMM Raporu
CREATE OR ALTER VIEW bkm.fifo_vw_GunlukSMM
AS
SELECT
    hareketTarihi,
    SUM(CASE WHEN hareketTipi = 'SATIS' THEN cikisTutar ELSE 0 END) AS satisMaliyeti,
    SUM(CASE WHEN hareketTipi = 'IADE' THEN cikisTutar ELSE 0 END) AS iadeMaliyeti,
    SUM(cikisTutar) AS netMaliyet,
    COUNT(*) AS satirSayisi
FROM bkm.fifo_StokMaliyetCikis
GROUP BY hareketTarihi;
GO

-- Ürün Bazlı SMM
CREATE OR ALTER VIEW bkm.fifo_vw_UrunBazliSMM
AS
SELECT
    stkID,
    hareketTarihi,
    hareketTipi,
    SUM(miktar) AS toplamMiktar,
    SUM(cikisTutar) AS toplamMaliyet,
    CASE WHEN SUM(miktar) <> 0 
         THEN SUM(cikisTutar) / SUM(miktar) 
         ELSE 0 
    END AS ortalamaBirimMaliyet
FROM bkm.fifo_StokMaliyetCikis
GROUP BY stkID, hareketTarihi, hareketTipi;
GO

-- Katman Durumu Raporu
CREATE OR ALTER VIEW bkm.fifo_vw_KatmanDurumu
AS
SELECT
    stkID,
    kaynakTip,
    girisTarihi,
    COUNT(*) AS katmanSayisi,
    SUM(miktarToplam) AS toplamMiktar,
    SUM(miktarKalan) AS kalanMiktar,
    SUM(miktarToplam - miktarKalan) AS tukenenMiktar,
    AVG(birimMaliyet) AS ortalamaBirimMaliyet,
    MIN(birimMaliyet) AS minBirimMaliyet,
    MAX(birimMaliyet) AS maxBirimMaliyet
FROM bkm.fifo_StokMaliyetHavuzu
GROUP BY stkID, kaynakTip, girisTarihi;
GO

-- Sorunlu Stoklar Özeti
CREATE OR ALTER VIEW bkm.fifo_vw_SorunluStoklar
AS
SELECT
    sorunTip,
    envanterTarihi,
    COUNT(DISTINCT stkID) AS urunSayisi,
    SUM(stokMiktar) AS toplamMiktar,
    MIN(kayitTarihi) AS ilkKayit,
    MAX(kayitTarihi) AS sonKayit
FROM bkm.fifo_StokMaliyetSorunlu
GROUP BY sorunTip, envanterTarihi;
GO

PRINT 'Tüm raporlama view''ları oluşturuldu';
GO

