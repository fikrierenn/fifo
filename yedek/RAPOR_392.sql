-- =============================================================
-- ÜRÜN 392 - DETAYLI RAPOR
-- =============================================================

PRINT '========================================'
PRINT 'ÜRÜN 392 - FIFO MALİYET RAPORU'
PRINT '========================================'
PRINT ''

-- 1) Özet İstatistikler
PRINT '1) ÖZET İSTATİSTİKLER:'
PRINT '---------------------'
SELECT
    COUNT(*) AS toplamIslem,
    SUM(c.miktar) AS toplamMiktar,
    SUM(c.cikisTutar) AS toplamMaliyet,
    MIN(c.hareketTarihi) AS ilkTarih,
    MAX(c.hareketTarihi) AS sonTarih
FROM bkm.fifo_StokMaliyetCikis c
WHERE c.stkID = 392

-- 2) Katman Bazlı Dağılım
PRINT ''
PRINT '2) KATMAN BAZLI DAĞILIM:'
PRINT '------------------------'
SELECT
    c.katmanID,
    c.katmanTarihi,
    c.birimMaliyet,
    COUNT(*) AS kullanimSayisi,
    SUM(c.miktar) AS kullanilanMiktar,
    SUM(c.cikisTutar) AS toplamMaliyet
FROM bkm.fifo_StokMaliyetCikis c
WHERE c.stkID = 392
GROUP BY c.katmanID, c.katmanTarihi, c.birimMaliyet
ORDER BY c.katmanTarihi

-- 3) Günlük Detay
PRINT ''
PRINT '3) GÜNLÜK DETAY:'
PRINT '----------------'
SELECT
    c.hareketTarihi,
    c.hareketTipi,
    COUNT(*) AS islemSayisi,
    SUM(c.miktar) AS gunlukMiktar,
    SUM(c.cikisTutar) AS gunlukMaliyet,
    AVG(c.birimMaliyet) AS ortBirimMaliyet
FROM bkm.fifo_StokMaliyetCikis c
WHERE c.stkID = 392
GROUP BY c.hareketTarihi, c.hareketTipi
ORDER BY c.hareketTarihi

-- 4) Katman Kalan Durumu
PRINT ''
PRINT '4) KATMAN KALAN DURUMU:'
PRINT '----------------------'
SELECT
    h.ID AS katmanID,
    h.girisTarihi,
    h.miktarToplam AS baslangicMiktar,
    h.miktarKalan AS kalanMiktar,
    h.miktarToplam - h.miktarKalan AS kullanilanMiktar,
    h.birimMaliyet,
    (h.miktarToplam - h.miktarKalan) * h.birimMaliyet AS kullanilanMaliyet
FROM bkm.fifo_StokMaliyetHavuzu h
WHERE h.stkID = 392
  AND h.kaynakTip IN ('ACILIS','ACILIS_TAMAMLA','ALIS')
ORDER BY h.girisTarihi

-- 5) Tüm Detaylar
PRINT ''
PRINT '5) TÜM HAREKETLER (İLK 20):'
PRINT '---------------------------'
SELECT TOP 20
    c.hareketTarihi,
    c.hareketTipi,
    c.katmanTarihi,
    c.miktar,
    c.birimMaliyet,
    c.cikisTutar
FROM bkm.fifo_StokMaliyetCikis c
WHERE c.stkID = 392
ORDER BY c.hareketTarihi, c.katmanTarihi

PRINT ''
PRINT '========================================'
PRINT 'RAPOR TAMAMLANDI'
PRINT '========================================'
