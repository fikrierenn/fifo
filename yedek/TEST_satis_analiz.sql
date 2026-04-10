-- =============================================================
-- SATIŞ VERİLERİNİ DETAYLI ANALİZ ET
-- =============================================================

PRINT '========================================';
PRINT 'SATIŞ VERİLERİ ANALİZİ';
PRINT '========================================';
PRINT '';

-- Son 1 yıldaki satışları kontrol et
DECLARE @sonYil DATE = DATEADD(YEAR, -1, GETDATE());

PRINT '1) Son 1 yıldaki satış dağılımı:';
SELECT 
    YEAR(bs.eTarihS) AS yil,
    MONTH(bs.eTarihS) AS ay,
    COUNT(DISTINCT bs.eID) AS belgeSayisi,
    COUNT(DISTINCT dt.ehStkID) AS urunSayisi,
    SUM(CONVERT(DECIMAL(18,4), dt.ehAdet)) AS toplamMiktar
FROM dbo.irs bs WITH(NOLOCK)
JOIN dbo.irsAyr dt WITH(NOLOCK) ON dt.ehID = bs.eID
WHERE bs.eTip IN (1,4,5,100,101)
  AND bs.eMekan IN (1, 4477, 4478)
  AND bs.eTarihS >= @sonYil
GROUP BY YEAR(bs.eTarihS), MONTH(bs.eTarihS)
ORDER BY yil DESC, ay DESC;

PRINT '';
PRINT '2) Satış tiplerine göre dağılım (son 3 ay):';
SELECT 
    bs.eTip,
    COUNT(DISTINCT bs.eID) AS belgeSayisi,
    COUNT(DISTINCT dt.ehStkID) AS urunSayisi,
    SUM(CONVERT(DECIMAL(18,4), dt.ehAdet)) AS toplamMiktar
FROM dbo.irs bs WITH(NOLOCK)
JOIN dbo.irsAyr dt WITH(NOLOCK) ON dt.ehID = bs.eID
WHERE bs.eTip IN (1,4,5,100,101)
  AND bs.eMekan IN (1, 4477, 4478)
  AND bs.eTarihS >= '2025-09-01'
GROUP BY bs.eTip
ORDER BY bs.eTip;

PRINT '';
PRINT '3) Lokasyonlara göre dağılım (son 3 ay):';
SELECT 
    bs.eMekan,
    COUNT(DISTINCT bs.eID) AS belgeSayisi,
    COUNT(DISTINCT dt.ehStkID) AS urunSayisi,
    SUM(CONVERT(DECIMAL(18,4), dt.ehAdet)) AS toplamMiktar
FROM dbo.irs bs WITH(NOLOCK)
JOIN dbo.irsAyr dt WITH(NOLOCK) ON dt.ehID = bs.eID
WHERE bs.eTip IN (1,4,5,100,101)
  AND bs.eMekan IN (1, 4477, 4478)
  AND bs.eTarihS >= '2025-09-01'
GROUP BY bs.eMekan
ORDER BY bs.eMekan;

PRINT '';
PRINT '4) En çok satan 20 ürün (son 3 ay):';
SELECT TOP 20
    dt.ehStkID AS stkID,
    COUNT(DISTINCT bs.eID) AS belgeSayisi,
    SUM(CONVERT(DECIMAL(18,4), dt.ehAdet)) AS toplamSatisMiktar
FROM dbo.irs bs WITH(NOLOCK)
JOIN dbo.irsAyr dt WITH(NOLOCK) ON dt.ehID = bs.eID
WHERE bs.eTip IN (1,4,5,100,101)
  AND bs.eMekan IN (1, 4477, 4478)
  AND bs.eTarihS >= '2025-09-01'
GROUP BY dt.ehStkID
ORDER BY SUM(CONVERT(DECIMAL(18,4), dt.ehAdet)) DESC;

PRINT '';
PRINT '5) Tüm satış tiplerini göster:';
SELECT DISTINCT 
    eTip,
    COUNT(*) AS adet
FROM dbo.irs WITH(NOLOCK)
WHERE eTarihS >= '2025-09-01'
GROUP BY eTip
ORDER BY eTip;

PRINT '';
PRINT '6) Tüm lokasyonları göster:';
SELECT DISTINCT 
    eMekan,
    COUNT(*) AS adet
FROM dbo.irs WITH(NOLOCK)
WHERE eTarihS >= '2025-09-01'
GROUP BY eMekan
ORDER BY eMekan;

PRINT '';
PRINT '========================================';
PRINT 'ÖNERİ: Yukarıdaki sonuçlara göre';
PRINT 'doğru eTip ve eMekan değerlerini belirleyin';
PRINT '========================================';
GO
