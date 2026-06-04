-- =============================================================
-- DEVİR STOKU ANALİZİ - ÜRÜN 594124
-- =============================================================

USE BKMMaliyet;
GO

DECLARE @testStkID INT = 594124;

PRINT '========================================';
PRINT 'DEVİR STOKU ANALİZİ - ÜRÜN: ' + CAST(@testStkID AS VARCHAR(10));
PRINT '========================================';
PRINT '';

-- 1. ERP Devir kaydı (irsHrk'dan)
PRINT '1. ERP Devir Kaydı (irsHrk - ehTip=99):';
SELECT 
    ehID,
    ehstkID AS UrunID,
    ehMekan AS MekanID,
    ehTrhS AS StokGirisTarihi,
    hrkTarih AS KayitTarihi,
    ehAdetN AS Miktar,
    ehTutarN AS ToplamTutar,
    ehMlyt AS BirimMaliyet,
    ehTip AS HareketTipi
FROM DerinSISBkm.dbo.irsHrk
WHERE ehstkID = @testStkID
  AND ehTip = 99
  AND ehTrhS = '31.05.2021';

PRINT '';
PRINT '';

-- 2. Mekan bazında devir stoku
PRINT '2. Mekan Bazında Devir Stoku:';
SELECT 
    ehMekan AS MekanID,
    SUM(ehAdetN) AS ToplamMiktar,
    SUM(ehTutarN) AS ToplamTutar
FROM DerinSISBkm.dbo.irsHrk
WHERE ehstkID = @testStkID
  AND ehTip = 99
  AND ehTrhS = '31.05.2021'
GROUP BY ehMekan;

PRINT '';
PRINT '';

-- 3. fn_gecmis_stok_mekan fonksiyonu test (01.06.2021)
PRINT '3. fn_gecmis_stok_mekan Fonksiyonu Test (01.06.2021):';
SELECT 
    f.stkID,
    f.stok,
    1 AS mekanID
FROM DerinSISBkm.bkm.fn_gecmis_stok_mekan('01.06.2021', 1) f
WHERE f.stkID = @testStkID
UNION ALL
SELECT 
    f.stkID,
    f.stok,
    12 AS mekanID
FROM DerinSISBkm.bkm.fn_gecmis_stok_mekan('01.06.2021', 12) f
WHERE f.stkID = @testStkID
UNION ALL
SELECT 
    f.stkID,
    f.stok,
    4477 AS mekanID
FROM DerinSISBkm.bkm.fn_gecmis_stok_mekan('01.06.2021', 4477) f
WHERE f.stkID = @testStkID
UNION ALL
SELECT 
    f.stkID,
    f.stok,
    4478 AS mekanID
FROM DerinSISBkm.bkm.fn_gecmis_stok_mekan('01.06.2021', 4478) f
WHERE f.stkID = @testStkID;

PRINT '';
PRINT '';

-- 4. Haziran 2021 ilk hareketler
PRINT '4. Haziran 2021 İlk Hareketler (irsHrk):';
SELECT TOP 10
    hrkID,
    ehTrhS AS StokGirisTarihi,
    hrkTarih AS KayitTarihi,
    ehMekan AS MekanID,
    ehTip AS HareketTipi,
    ehAdetN AS Miktar,
    ehTutarN AS ToplamTutar
FROM DerinSISBkm.dbo.irsHrk
WHERE ehstkID = @testStkID
  AND ehTrhS >= '01.06.2021'
  AND ehTrhS < '01.07.2021'
ORDER BY ehTrhS, hrkID;

PRINT '';
PRINT 'Analiz tamamlandı!';
GO
