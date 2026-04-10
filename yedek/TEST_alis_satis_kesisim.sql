-- =============================================================
-- ALIŞ VE SATIŞ KESİŞİMİ - Açılış olmasa da test edelim
-- =============================================================

PRINT '========================================';
PRINT 'ALIŞ + SATIŞ KESİŞİM ANALİZİ';
PRINT 'Tarih: 2025-09-01 - 2025-11-27';
PRINT '========================================';
PRINT '';

-- Alış olan ürünler
IF OBJECT_ID('tempdb..#alisStok', 'U') IS NOT NULL DROP TABLE #alisStok;
SELECT 
    a.ehStkID AS stkID,
    COUNT(DISTINCT i.eID) AS alisBelgeSayisi,
    SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS toplamAlisMiktar,
    MIN(i.eTarih) AS ilkAlis,
    MAX(i.eTarih) AS sonAlis
INTO #alisStok
FROM dbo.irs i WITH(NOLOCK)
JOIN dbo.irsAyr ia WITH(NOLOCK) ON ia.ehID = i.eID
JOIN dbo.fatAyr a WITH(NOLOCK) 
    ON a.ehIrsID = i.eID AND a.ehIrsSira = ia.ehSira
WHERE i.eTip IN (2,0,10)
  AND i.eTarih >= '2025-09-01'
  AND i.eTarih <= '2025-11-27'
  AND a.ehAdetN <> 0
GROUP BY a.ehStkID
HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) > 0;

PRINT 'Alış olan ürün sayısı: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

-- Satış olan ürünler
IF OBJECT_ID('tempdb..#satisStok', 'U') IS NOT NULL DROP TABLE #satisStok;
SELECT 
    dt.ehStkID AS stkID,
    COUNT(DISTINCT bs.eID) AS satisBelgeSayisi,
    SUM(CONVERT(DECIMAL(18,4), dt.ehAdet)) AS toplamSatisMiktar,
    MIN(bs.eTarihS) AS ilkSatis,
    MAX(bs.eTarihS) AS sonSatis
INTO #satisStok
FROM dbo.irs bs WITH(NOLOCK)
JOIN dbo.irsAyr dt WITH(NOLOCK) ON dt.ehID = bs.eID
WHERE bs.eTip IN (1,4,5,100,101)
  AND bs.eMekan IN (1, 4477, 4478)
  AND bs.eTarihS >= '2025-09-01'
  AND bs.eTarihS <= '2025-11-27'
GROUP BY dt.ehStkID
HAVING SUM(CONVERT(DECIMAL(18,4), dt.ehAdet)) > 0;

PRINT 'Satış olan ürün sayısı: ' + CAST(@@ROWCOUNT AS VARCHAR(10));
PRINT '';

-- Hem alış hem satış olan ürünler
IF OBJECT_ID('tempdb..#alisVeSatis', 'U') IS NOT NULL DROP TABLE #alisVeSatis;
SELECT 
    a.stkID,
    a.alisBelgeSayisi,
    a.toplamAlisMiktar,
    a.ilkAlis,
    a.sonAlis,
    s.satisBelgeSayisi,
    s.toplamSatisMiktar,
    s.ilkSatis,
    s.sonSatis
INTO #alisVeSatis
FROM #alisStok a
INNER JOIN #satisStok s ON s.stkID = a.stkID;

PRINT '========================================';
PRINT 'ALIŞ + SATIŞ OLAN ÜRÜN SAYISI: ' + CAST(@@ROWCOUNT AS VARCHAR(10));
PRINT '========================================';
PRINT '';

-- En hareketli 20 ürünü göster
PRINT 'En hareketli 20 ürün:';
SELECT TOP 20
    a.stkID,
    a.alisBelgeSayisi,
    a.toplamAlisMiktar,
    a.satisBelgeSayisi,
    a.toplamSatisMiktar,
    a.ilkAlis,
    a.sonAlis,
    a.ilkSatis,
    a.sonSatis
FROM #alisVeSatis a
ORDER BY (a.toplamAlisMiktar + a.toplamSatisMiktar) DESC;

PRINT '';
PRINT '========================================';
PRINT 'BU ÜRÜNLERLE TEST EDEBİLİRİZ!';
PRINT '========================================';
PRINT '';

-- Test için 5 ürün seç
DECLARE @test1 INT, @test2 INT, @test3 INT, @test4 INT, @test5 INT;

SELECT TOP 5
    @test1 = CASE WHEN rn = 1 THEN stkID END,
    @test2 = CASE WHEN rn = 2 THEN stkID END,
    @test3 = CASE WHEN rn = 3 THEN stkID END,
    @test4 = CASE WHEN rn = 4 THEN stkID END,
    @test5 = CASE WHEN rn = 5 THEN stkID END
FROM (
    SELECT 
        stkID,
        ROW_NUMBER() OVER (ORDER BY (toplamAlisMiktar + toplamSatisMiktar) DESC) AS rn
    FROM #alisVeSatis
) x;

PRINT 'Test için önerilen ürünler:';
PRINT '  stkID 1: ' + ISNULL(CAST(@test1 AS VARCHAR(10)), 'YOK');
PRINT '  stkID 2: ' + ISNULL(CAST(@test2 AS VARCHAR(10)), 'YOK');
PRINT '  stkID 3: ' + ISNULL(CAST(@test3 AS VARCHAR(10)), 'YOK');
PRINT '  stkID 4: ' + ISNULL(CAST(@test4 AS VARCHAR(10)), 'YOK');
PRINT '  stkID 5: ' + ISNULL(CAST(@test5 AS VARCHAR(10)), 'YOK');

PRINT '';
PRINT 'Bu ürünlerle test senaryosu çalıştırabilirsiniz!';
GO
