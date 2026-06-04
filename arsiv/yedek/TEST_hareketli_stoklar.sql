-- =============================================================
-- HAREKETLİ STOKLARI TESPİT VE TEST
-- Açılış + Alış + Satış olan ürünleri bulup test edelim
-- =============================================================

-- 1) Hareketli stokları tespit et (son 3 ay)
DECLARE @testBaslangic DATE = '2025-09-01';
DECLARE @testBitis DATE = '2025-11-27';

PRINT '========================================';
PRINT 'HAREKETLİ STOK ANALİZİ';
PRINT 'Tarih Aralığı: ' + CONVERT(VARCHAR(10), @testBaslangic, 120) + ' - ' + CONVERT(VARCHAR(10), @testBitis, 120);
PRINT '========================================';
PRINT '';

-- Açılış stoku olan ürünler
IF OBJECT_ID('tempdb..#acilisStok', 'U') IS NOT NULL DROP TABLE #acilisStok;
SELECT 
    d.ehstkID AS stkID,
    SUM(CONVERT(DECIMAL(18,4), d.stok)) AS acilisMiktar
INTO #acilisStok
FROM dbo.stokSonAltDepo_vw d
WHERE d.ehAltDepo = 0 
  AND d.ehMekan IN (1,4477,4478)
  AND d.stok > 0
GROUP BY d.ehstkID;

PRINT 'Açılış stoku olan ürün sayısı: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

-- Alış olan ürünler (test dönemi)
IF OBJECT_ID('tempdb..#alisStok', 'U') IS NOT NULL DROP TABLE #alisStok;
SELECT 
    a.ehStkID AS stkID,
    COUNT(DISTINCT i.eID) AS alisBelgeSayisi,
    SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS toplamAlisMiktar
INTO #alisStok
FROM dbo.irs i WITH(NOLOCK)
JOIN dbo.irsAyr ia WITH(NOLOCK) ON ia.ehID = i.eID
JOIN dbo.fatAyr a WITH(NOLOCK) 
    ON a.ehIrsID = i.eID AND a.ehIrsSira = ia.ehSira
WHERE i.eTip IN (2,0,10)
  AND i.eTarih >= @testBaslangic
  AND i.eTarih <= @testBitis
  AND a.ehAdetN <> 0
GROUP BY a.ehStkID
HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) > 0;

PRINT 'Alış olan ürün sayısı: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

-- Satış olan ürünler (test dönemi)
IF OBJECT_ID('tempdb..#satisStok', 'U') IS NOT NULL DROP TABLE #satisStok;
SELECT 
    dt.ehStkID AS stkID,
    COUNT(DISTINCT bs.eID) AS satisBelgeSayisi,
    SUM(CONVERT(DECIMAL(18,4), dt.ehAdet)) AS toplamSatisMiktar
INTO #satisStok
FROM dbo.irs bs WITH(NOLOCK)
JOIN dbo.irsAyr dt WITH(NOLOCK) ON dt.ehID = bs.eID
WHERE bs.eTip IN (1,4,5,100,101)
  AND bs.eMekan IN (1, 4477, 4478)
  AND bs.eTarihS >= @testBaslangic
  AND bs.eTarihS <= @testBitis
GROUP BY dt.ehStkID
HAVING SUM(CONVERT(DECIMAL(18,4), dt.ehAdet)) > 0;

PRINT 'Satış olan ürün sayısı: ' + CAST(@@ROWCOUNT AS VARCHAR(10));
PRINT '';

-- Hem açılış + hem alış + hem satış olan ürünler (TAM HAREKETLİ)
IF OBJECT_ID('tempdb..#hareketliStok', 'U') IS NOT NULL DROP TABLE #hareketliStok;
SELECT 
    a.stkID,
    a.acilisMiktar,
    al.alisBelgeSayisi,
    al.toplamAlisMiktar,
    s.satisBelgeSayisi,
    s.toplamSatisMiktar
INTO #hareketliStok
FROM #acilisStok a
INNER JOIN #alisStok al ON al.stkID = a.stkID
INNER JOIN #satisStok s ON s.stkID = a.stkID;

PRINT '========================================';
PRINT 'TAM HAREKETLİ STOK SAYISI: ' + CAST(@@ROWCOUNT AS VARCHAR(10));
PRINT '(Açılış + Alış + Satış olan ürünler)';
PRINT '========================================';
PRINT '';

-- En hareketli 10 ürünü göster
SELECT TOP 10
    stkID,
    acilisMiktar,
    alisBelgeSayisi,
    toplamAlisMiktar,
    satisBelgeSayisi,
    toplamSatisMiktar,
    (toplamAlisMiktar + toplamSatisMiktar) AS toplamHareket
FROM #hareketliStok
ORDER BY (toplamAlisMiktar + toplamSatisMiktar) DESC;

PRINT '';
PRINT '========================================';
PRINT 'TEST İÇİN ÖNERİLEN ÜRÜNLER';
PRINT '========================================';

-- Test için 5 ürün seç (orta hacimli)
DECLARE @testUrun1 INT, @testUrun2 INT, @testUrun3 INT, @testUrun4 INT, @testUrun5 INT;

SELECT TOP 5
    @testUrun1 = CASE WHEN rn = 1 THEN stkID ELSE @testUrun1 END,
    @testUrun2 = CASE WHEN rn = 2 THEN stkID ELSE @testUrun2 END,
    @testUrun3 = CASE WHEN rn = 3 THEN stkID ELSE @testUrun3 END,
    @testUrun4 = CASE WHEN rn = 4 THEN stkID ELSE @testUrun4 END,
    @testUrun5 = CASE WHEN rn = 5 THEN stkID ELSE @testUrun5 END
FROM (
    SELECT 
        stkID,
        ROW_NUMBER() OVER (ORDER BY (toplamAlisMiktar + toplamSatisMiktar) DESC) AS rn
    FROM #hareketliStok
    WHERE toplamAlisMiktar BETWEEN 10 AND 1000  -- Orta hacimli
      AND toplamSatisMiktar BETWEEN 10 AND 1000
) x;

PRINT 'Test Ürün 1: ' + CAST(@testUrun1 AS VARCHAR(10));
PRINT 'Test Ürün 2: ' + CAST(@testUrun2 AS VARCHAR(10));
PRINT 'Test Ürün 3: ' + CAST(@testUrun3 AS VARCHAR(10));
PRINT 'Test Ürün 4: ' + CAST(@testUrun4 AS VARCHAR(10));
PRINT 'Test Ürün 5: ' + CAST(@testUrun5 AS VARCHAR(10));
PRINT '';

-- Bu ürünlerin detaylarını göster
SELECT 
    h.stkID,
    h.acilisMiktar,
    h.alisBelgeSayisi,
    h.toplamAlisMiktar,
    h.satisBelgeSayisi,
    h.toplamSatisMiktar
FROM #hareketliStok h
WHERE h.stkID IN (@testUrun1, @testUrun2, @testUrun3, @testUrun4, @testUrun5)
ORDER BY h.toplamSatisMiktar DESC;

PRINT '';
PRINT '========================================';
PRINT 'ŞİMDİ BU ÜRÜNLERLE TEST EDELİM';
PRINT '========================================';
GO
