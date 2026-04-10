-- =============================================================
-- TEST ÜRÜNLERİ ANALİZ SCRIPTI
-- Farklı senaryoları test edebilmek için uygun ürünleri bulur
-- =============================================================

USE BKMMaliyet;
GO

PRINT '========================================';
PRINT 'TEST ÜRÜNLERİ ANALİZ RAPORU';
PRINT '========================================';
PRINT '';

-- =============================================================
-- SENARYO 1: ERP Devir Fiyatı Olan Ürünler
-- =============================================================
PRINT '1. ERP DEVIR FIYATI OLAN ÜRÜNLER (En yüksek miktarlı 10 ürün)';
PRINT '----------------------------------------------------------------';

SELECT TOP 10
    e.stkID,
    e.satinalmaSarti,
    e.miktar,
    e.birimMaliyet,
    e.toplamTutar,
    u.stkAd AS UrunAdi
FROM bkm.fifo_ErpDevirFiyatlari e
LEFT JOIN DerinSISBkm.bkm.UrunBilgi u ON u.stkID = e.stkID
WHERE e.satinalmaSarti = 'SART310521'
ORDER BY e.miktar DESC;

PRINT '';
PRINT '';

-- =============================================================
-- SENARYO 2: Hem ERP Devir Hem de Stok Hareketi Olan Ürünler
-- =============================================================
PRINT '2. ERP DEVIR + STOK HAREKETİ OLAN ÜRÜNLER (FIFO testi için ideal)';
PRINT '----------------------------------------------------------------';

SELECT TOP 10
    e.stkID,
    e.miktar AS DevirMiktar,
    e.birimMaliyet AS DevirMaliyet,
    COUNT(DISTINCT h.hrkID) AS AlisHareketSayisi,
    SUM(h.ehAdetN) AS ToplamAlisMiktar,
    u.stkAd AS UrunAdi
FROM bkm.fifo_ErpDevirFiyatlari e
LEFT JOIN DerinSISBkm.bkm.UrunBilgi u ON u.stkID = e.stkID
LEFT JOIN DerinSISBkm.dbo.irsHrk h ON h.ehstkID = e.stkID
WHERE e.satinalmaSarti = 'SART310521'
  AND h.hrkTarih > '31.05.2021'
  AND h.hrkTarih < '01.01.2022'
  AND h.ehTip NOT IN (99) -- Devir hariç tüm hareketler
  AND h.ehAdetN > 0
GROUP BY e.stkID, e.miktar, e.birimMaliyet, u.stkAd
HAVING COUNT(DISTINCT h.hrkID) > 0
ORDER BY COUNT(DISTINCT h.hrkID) DESC, e.miktar DESC;

PRINT '';
PRINT '';

-- =============================================================
-- SENARYO 3: Hem Alış Hem Satış Hareketi Olan Ürünler
-- =============================================================
PRINT '3. ALIŞ + SATIŞ HAREKETİ OLAN ÜRÜNLER (Tam FIFO döngüsü için)';
PRINT '----------------------------------------------------------------';

WITH AlisHareketleri AS (
    SELECT 
        h.ehstkID AS stkID,
        COUNT(DISTINCT h.hrkID) AS AlisAdet,
        SUM(h.ehAdetN) AS AlisMiktar
    FROM DerinSISBkm.dbo.irsHrk h
    WHERE h.hrkTarih BETWEEN '01.06.2021' AND '31.12.2021'
      AND h.ehTip NOT IN (99) -- Devir hariç
      AND h.ehAdetN > 0
    GROUP BY h.ehstkID
),
SatisHareketleri AS (
    SELECT 
        h.ehstkID AS stkID,
        COUNT(DISTINCT h.hrkID) AS SatisAdet,
        SUM(ABS(h.ehAdetN)) AS SatisMiktar
    FROM DerinSISBkm.dbo.irsHrk h
    WHERE h.hrkTarih BETWEEN '01.06.2021' AND '31.12.2021'
      AND h.ehTip NOT IN (99) -- Devir hariç
      AND h.ehAdetN < 0
    GROUP BY h.ehstkID
)
SELECT TOP 10
    e.stkID,
    e.miktar AS DevirMiktar,
    e.birimMaliyet AS DevirMaliyet,
    ISNULL(a.AlisAdet, 0) AS AlisHareketSayisi,
    ISNULL(a.AlisMiktar, 0) AS ToplamAlisMiktar,
    ISNULL(st.SatisAdet, 0) AS SatisHareketSayisi,
    ISNULL(st.SatisMiktar, 0) AS ToplamSatisMiktar,
    u.stkAd AS UrunAdi
FROM bkm.fifo_ErpDevirFiyatlari e
LEFT JOIN DerinSISBkm.bkm.UrunBilgi u ON u.stkID = e.stkID
LEFT JOIN AlisHareketleri a ON a.stkID = e.stkID
LEFT JOIN SatisHareketleri st ON st.stkID = e.stkID
WHERE e.satinalmaSarti = 'SART310521'
  AND ISNULL(a.AlisAdet, 0) > 0
  AND ISNULL(st.SatisAdet, 0) > 0
ORDER BY (ISNULL(a.AlisAdet, 0) + ISNULL(st.SatisAdet, 0)) DESC;

PRINT '';
PRINT '';

-- =============================================================
-- SENARYO 4: Sadece ERP Devir Olan (Hareket Olmayan) Ürünler
-- =============================================================
PRINT '4. SADECE ERP DEVIR OLAN ÜRÜNLER (Hareket yok - basit test için)';
PRINT '----------------------------------------------------------------';

SELECT TOP 10
    e.stkID,
    e.miktar AS DevirMiktar,
    e.birimMaliyet AS DevirMaliyet,
    e.toplamTutar,
    u.stkAd AS UrunAdi
FROM bkm.fifo_ErpDevirFiyatlari e
LEFT JOIN DerinSISBkm.bkm.UrunBilgi u ON u.stkID = e.stkID
WHERE e.satinalmaSarti = 'SART310521'
  AND NOT EXISTS (
      SELECT 1 
      FROM DerinSISBkm.dbo.irsHrk h
      WHERE h.ehstkID = e.stkID
        AND h.hrkTarih > '31.05.2021'
        AND h.hrkTarih < '01.01.2022'
        AND h.ehTip <> 99 -- Devir hariç
  )
ORDER BY e.miktar DESC;

PRINT '';
PRINT '';

-- =============================================================
-- SENARYO 5: Yüksek Hacimli Ürünler (Performans testi için)
-- =============================================================
PRINT '5. YÜKSEK HACİMLİ ÜRÜNLER (Performans testi için)';
PRINT '----------------------------------------------------------------';

SELECT TOP 10
    e.stkID,
    e.miktar AS DevirMiktar,
    COUNT(DISTINCT h.hrkID) AS ToplamHareketSayisi,
    SUM(ABS(h.ehAdetN)) AS ToplamHareketMiktar,
    u.stkAd AS UrunAdi
FROM bkm.fifo_ErpDevirFiyatlari e
LEFT JOIN DerinSISBkm.bkm.UrunBilgi u ON u.stkID = e.stkID
LEFT JOIN DerinSISBkm.dbo.irsHrk h ON h.ehstkID = e.stkID
WHERE e.satinalmaSarti = 'SART310521'
  AND h.hrkTarih BETWEEN '01.06.2021' AND '31.12.2021'
  AND h.ehTip <> 99 -- Devir hariç
  AND h.ehAdetN <> 0
GROUP BY e.stkID, e.miktar, u.stkAd
HAVING COUNT(DISTINCT h.hrkID) > 10
ORDER BY COUNT(DISTINCT h.hrkID) DESC;

PRINT '';
PRINT '';

-- =============================================================
-- ÖZET İSTATİSTİKLER
-- =============================================================
PRINT '========================================';
PRINT 'ÖZET İSTATİSTİKLER';
PRINT '========================================';

SELECT 
    'Toplam ERP Devir Ürün Sayısı' AS Metrik,
    COUNT(*) AS Deger
FROM bkm.fifo_ErpDevirFiyatlari
WHERE satinalmaSarti = 'SART310521'

UNION ALL

SELECT 
    'Hareket Olan Ürün Sayısı' AS Metrik,
    COUNT(DISTINCT e.stkID) AS Deger
FROM bkm.fifo_ErpDevirFiyatlari e
WHERE e.satinalmaSarti = 'SART310521'
  AND EXISTS (
      SELECT 1 
      FROM DerinSISBkm.dbo.irsHrk h
      WHERE h.ehstkID = e.stkID
        AND h.hrkTarih > '31.05.2021'
        AND h.hrkTarih < '01.01.2022'
        AND h.ehTip <> 99 -- Devir hariç
  )

UNION ALL

SELECT 
    'Satış Olan Ürün Sayısı' AS Metrik,
    COUNT(DISTINCT e.stkID) AS Deger
FROM bkm.fifo_ErpDevirFiyatlari e
WHERE e.satinalmaSarti = 'SART310521'
  AND EXISTS (
      SELECT 1 
      FROM DerinSISBkm.dbo.irsHrk h
      WHERE h.ehstkID = e.stkID
        AND h.hrkTarih > '31.05.2021'
        AND h.hrkTarih < '01.01.2022'
        AND h.ehTip <> 99 -- Devir hariç
        AND h.ehAdetN < 0 -- Satış (negatif miktar)
  );

PRINT '';
PRINT 'Analiz tamamlandi!';
PRINT '';
PRINT 'ÖNERİLER:';
PRINT '- Senaryo 1: Basit açılış stoku testi için';
PRINT '- Senaryo 2: FIFO katman ekleme testi için';
PRINT '- Senaryo 3: Tam FIFO döngüsü (alış + satış) testi için';
PRINT '- Senaryo 4: Sadece devir stoku testi için';
PRINT '- Senaryo 5: Performans ve yüksek hacim testi için';
GO
