-- =============================================================
-- BASİT ALIŞ + SATIŞ KESİŞİM TESTİ
-- =============================================================

PRINT '========================================';
PRINT 'ALIŞ + SATIŞ KESİŞİM (BASİT)';
PRINT '========================================';
PRINT '';

-- Alış olan ürünler
SELECT 
    a.ehStkID AS stkID,
    COUNT(DISTINCT i.eID) AS alisBelge,
    SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS alisMiktar
INTO #alis
FROM dbo.irs i WITH(NOLOCK)
JOIN dbo.irsAyr ia WITH(NOLOCK) ON ia.ehID = i.eID
JOIN dbo.fatAyr a WITH(NOLOCK) 
    ON a.ehIrsID = i.eID AND a.ehIrsSira = ia.ehSira
WHERE i.eTip IN (2,0,10)
  AND i.eTarih >= CAST('2025-09-01' AS DATE)
  AND i.eTarih <= CAST('2025-11-27' AS DATE)
  AND a.ehAdetN <> 0
GROUP BY a.ehStkID
HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) > 0;

PRINT 'Alış: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' ürün';

-- Satış olan ürünler
SELECT 
    dt.ehStkID AS stkID,
    COUNT(DISTINCT bs.eID) AS satisBelge,
    SUM(CONVERT(DECIMAL(18,4), dt.ehAdet)) AS satisMiktar
INTO #satis
FROM dbo.irs bs WITH(NOLOCK)
JOIN dbo.irsAyr dt WITH(NOLOCK) ON dt.ehID = bs.eID
WHERE bs.eTip IN (1,4,5,100,101)
  AND bs.eMekan IN (1, 4477, 4478)
  AND bs.eTarihS >= CAST('2025-09-01' AS DATE)
  AND bs.eTarihS <= CAST('2025-11-27' AS DATE)
GROUP BY dt.ehStkID
HAVING SUM(CONVERT(DECIMAL(18,4), dt.ehAdet)) > 0;

PRINT 'Satış: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' ürün';
PRINT '';

-- Kesişim
SELECT 
    a.stkID,
    a.alisBelge,
    a.alisMiktar,
    s.satisBelge,
    s.satisMiktar
INTO #kesisim
FROM #alis a
INNER JOIN #satis s ON s.stkID = a.stkID;

PRINT '========================================';
PRINT 'KESİŞİM: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' ÜRÜN';
PRINT '========================================';
PRINT '';

-- En hareketli 20 ürün
SELECT TOP 20 * FROM #kesisim
ORDER BY (alisMiktar + satisMiktar) DESC;

-- Test için 5 ürün
PRINT '';
PRINT 'Test için önerilen 5 ürün:';
SELECT TOP 5 
    stkID,
    alisMiktar,
    satisMiktar
FROM #kesisim
ORDER BY (alisMiktar + satisMiktar) DESC;

DROP TABLE #alis;
DROP TABLE #satis;
DROP TABLE #kesisim;
GO
