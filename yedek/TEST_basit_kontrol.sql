-- =============================================================
-- BASİT KONTROL - Satış verilerini doğrudan kontrol et
-- =============================================================

PRINT '========================================';
PRINT 'BASİT SATIŞ KONTROLÜ';
PRINT '========================================';
PRINT '';

-- 1) Son 3 aydaki TÜM satış kayıtları (filtre yok)
PRINT '1) Son 3 aydaki TÜM irs kayıtları:';
SELECT 
    COUNT(*) AS toplamKayit,
    COUNT(DISTINCT eID) AS belgeSayisi,
    MIN(eTarihS) AS ilkTarih,
    MAX(eTarihS) AS sonTarih
FROM dbo.irs WITH(NOLOCK)
WHERE eTarihS >= '2025-09-01'
  AND eTarihS <= '2025-11-27';

-- 2) Sadece belirtilen tiplerde
PRINT '';
PRINT '2) eTip IN (1,4,5,100,101) olanlar:';
SELECT 
    COUNT(*) AS toplamKayit,
    COUNT(DISTINCT eID) AS belgeSayisi
FROM dbo.irs WITH(NOLOCK)
WHERE eTarihS >= '2025-09-01'
  AND eTarihS <= '2025-11-27'
  AND eTip IN (1,4,5,100,101);

-- 3) Tip + Lokasyon filtresi
PRINT '';
PRINT '3) eTip IN (1,4,5,100,101) VE eMekan IN (1,4477,4478):';
SELECT 
    COUNT(*) AS toplamKayit,
    COUNT(DISTINCT eID) AS belgeSayisi
FROM dbo.irs WITH(NOLOCK)
WHERE eTarihS >= '2025-09-01'
  AND eTarihS <= '2025-11-27'
  AND eTip IN (1,4,5,100,101)
  AND eMekan IN (1, 4477, 4478);

-- 4) irsAyr ile join sonrası
PRINT '';
PRINT '4) irsAyr ile join sonrası ürün sayısı:';
SELECT 
    COUNT(DISTINCT dt.ehStkID) AS urunSayisi,
    COUNT(*) AS satirSayisi,
    SUM(CONVERT(DECIMAL(18,4), dt.ehAdet)) AS toplamMiktar
FROM dbo.irs bs WITH(NOLOCK)
JOIN dbo.irsAyr dt WITH(NOLOCK) ON dt.ehID = bs.eID
WHERE bs.eTarihS >= '2025-09-01'
  AND bs.eTarihS <= '2025-11-27'
  AND bs.eTip IN (1,4,5,100,101)
  AND bs.eMekan IN (1, 4477, 4478);

-- 5) Hangi tipler var?
PRINT '';
PRINT '5) Son 3 ayda hangi eTip değerleri var?';
SELECT 
    eTip,
    COUNT(*) AS adet,
    COUNT(DISTINCT eID) AS belgeSayisi
FROM dbo.irs WITH(NOLOCK)
WHERE eTarihS >= '2025-09-01'
  AND eTarihS <= '2025-11-27'
GROUP BY eTip
ORDER BY COUNT(*) DESC;

-- 6) Hangi lokasyonlar var?
PRINT '';
PRINT '6) Son 3 ayda hangi eMekan değerleri var?';
SELECT 
    eMekan,
    COUNT(*) AS adet,
    COUNT(DISTINCT eID) AS belgeSayisi
FROM dbo.irs WITH(NOLOCK)
WHERE eTarihS >= '2025-09-01'
  AND eTarihS <= '2025-11-27'
GROUP BY eMekan
ORDER BY COUNT(*) DESC;

-- 7) Örnek 10 satış kaydı göster
PRINT '';
PRINT '7) Örnek 10 satış kaydı:';
SELECT TOP 10
    bs.eID,
    bs.eTip,
    bs.eMekan,
    bs.eTarihS,
    bs.eNo,
    dt.ehStkID,
    dt.ehAdet
FROM dbo.irs bs WITH(NOLOCK)
JOIN dbo.irsAyr dt WITH(NOLOCK) ON dt.ehID = bs.eID
WHERE bs.eTarihS >= '2025-09-01'
  AND bs.eTarihS <= '2025-11-27'
ORDER BY bs.eTarihS DESC;

PRINT '';
PRINT '========================================';
PRINT 'KONTROL TAMAMLANDI';
PRINT '========================================';
GO
