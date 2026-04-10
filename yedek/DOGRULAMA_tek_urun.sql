-- =============================================================
-- TEK ÜRÜN İLE DOĞRULAMA
-- Sistemin doğru çalıştığını manuel kontrol edelim
-- =============================================================

PRINT '========================================';
PRINT 'TEK ÜRÜN DOĞRULAMA TESTİ';
PRINT '========================================';
PRINT '';

-- Hem alışı hem satışı olan bir ürün seç
DECLARE @testStkID INT;
-- Test tarih araligi (guvenli literal)
DECLARE @testBaslangic DATE = DATEFROMPARTS(2025, 1, 1);
DECLARE @testBitis DATE = DATEFROMPARTS(2025, 11, 27);

SELECT TOP 1 @testStkID = a.stkID
FROM (
    SELECT DISTINCT a.ehStkID AS stkID
    FROM dbo.irs i WITH(NOLOCK)
    JOIN dbo.irsAyr ia WITH(NOLOCK) ON ia.ehID = i.eID
    JOIN dbo.fatAyr a WITH(NOLOCK) 
        ON a.ehIrsID = i.eID AND a.ehIrsSira = ia.ehSira
    WHERE i.eTip IN (2,0,10,3,6,102,103)
      AND i.eMekan IN (1, 4477, 4478)
      AND i.eTarih >= @testBaslangic
      AND i.eTarih <  DATEADD(DAY, 1, @testBitis)
) a
INNER JOIN (
    SELECT DISTINCT dt.ehStkID AS stkID
    FROM dbo.irs bs WITH(NOLOCK)
    JOIN dbo.irsAyr dt WITH(NOLOCK) ON dt.ehID = bs.eID
    WHERE bs.eTip IN (1,4,5,100,101)
      AND bs.eMekan IN (1, 4477, 4478)
      AND bs.eTarihS >= @testBaslangic
      AND bs.eTarihS <  DATEADD(DAY, 1, @testBitis)
) s ON s.stkID = a.stkID;

PRINT 'Test Ürün ID: ' + CAST(@testStkID AS VARCHAR(10));
PRINT '';

-- 1) Bu ürünün alışlarını göster
PRINT '1) ALIŞLAR:';
SELECT 
    i.eTarih AS tarih,
    f.eNo AS belgeNo,
    a.ehAdetN AS miktar,
    a.ehTutarN AS tutar,
    CASE WHEN a.ehAdetN <> 0 
         THEN a.ehTutarN / a.ehAdetN 
         ELSE 0 
    END AS birimMaliyet
FROM dbo.irs i WITH(NOLOCK)
JOIN dbo.irsAyr ia WITH(NOLOCK) ON ia.ehID = i.eID
JOIN dbo.fatAyr a WITH(NOLOCK) 
    ON a.ehIrsID = i.eID AND a.ehIrsSira = ia.ehSira
JOIN dbo.fat f WITH(NOLOCK) ON f.eID = a.ehID
WHERE i.eTip IN (2,0,10,3,6,102,103)
      AND i.eMekan IN (1, 4477, 4478)
  AND i.eTarih >= @testBaslangic
  AND i.eTarih <  DATEADD(DAY, 1, @testBitis)
  AND a.ehStkID = @testStkID
ORDER BY i.eTarih;

-- 1b) Merkez depo (mekan=12) alislari
PRINT '';
PRINT '1b) MERKEZ ALISLAR (MEKAN=12):';
SELECT 
    i.eTarih AS tarih,
    f.eNo AS belgeNo,
    a.ehAdetN AS miktar,
    a.ehTutarN AS tutar,
    CASE WHEN a.ehAdetN <> 0 
         THEN a.ehTutarN / a.ehAdetN 
         ELSE 0 
    END AS birimMaliyet
FROM dbo.irs i WITH(NOLOCK)
JOIN dbo.irsAyr ia WITH(NOLOCK) ON ia.ehID = i.eID
JOIN dbo.fatAyr a WITH(NOLOCK) 
    ON a.ehIrsID = i.eID AND a.ehIrsSira = ia.ehSira
JOIN dbo.fat f WITH(NOLOCK) ON f.eID = a.ehID
WHERE i.eTip IN (2,0,10,3,6,102,103)
  AND i.eMekan = 12
  AND i.eTarih >= @testBaslangic
  AND i.eTarih <  DATEADD(DAY, 1, @testBitis)
  AND a.ehStkID = @testStkID
ORDER BY i.eTarih;

-- 2) Bu ürünün satışlarını göster
PRINT '';
PRINT '2) SATIŞLAR:';
SELECT 
    CAST(bs.eTarihS AS DATE) AS tarih,
    bs.eNo AS belgeNo,
    dt.ehAdet AS miktar
FROM dbo.irs bs WITH(NOLOCK)
JOIN dbo.irsAyr dt WITH(NOLOCK) ON dt.ehID = bs.eID
WHERE bs.eTip IN (1,4,5,100,101)
  AND bs.eMekan IN (1, 4477, 4478)
  AND bs.eTarihS >= @testBaslangic
  AND bs.eTarihS <  DATEADD(DAY, 1, @testBitis)
  AND dt.ehStkID = @testStkID
ORDER BY bs.eTarihS;

-- 3) Sistemdeki katmanları göster
PRINT '';
PRINT '3) SİSTEMDEKİ KATMANLAR:';
SELECT 
    ID,
    girisTarihi,
    kaynakTip,
    belgeNo,
    miktarToplam,
    miktarKalan,
    birimMaliyet,
    durum
FROM bkm.fifo_StokMaliyetHavuzu
WHERE stkID = @testStkID
ORDER BY girisTarihi, ID;

-- 3b) Merkez/sart tamamlama katmanlari
PRINT '';
PRINT '3b) TAMAMLAMA KATMANLARI (MERKEZ/SART):';
SELECT 
    ID,
    girisTarihi,
    kaynakTip,
    belgeNo,
    miktarToplam,
    miktarKalan,
    birimMaliyet,
    durum
FROM bkm.fifo_StokMaliyetHavuzu
WHERE stkID = @testStkID
  AND kaynakTip = 'ACILIS_TAMAMLA'
  AND durum IN ('MERKEZ_TAMAMLAMA', 'SART_TAMAMLAMA')
ORDER BY girisTarihi, ID;

-- 4) FIFO çıkışları göster
PRINT '';
PRINT '4) FIFO ÇIKIŞLARI:';
SELECT 
    hareketTarihi,
    hareketTipi,
    katmanID,
    katmanTarihi,
    miktar,
    birimMaliyet,
    cikisTutar
FROM bkm.fifo_StokMaliyetCikis
WHERE stkID = @testStkID
ORDER BY hareketTarihi, katmanTarihi;

-- 5) Özet hesaplama
PRINT '';
PRINT '5) ÖZET:';
SELECT 
    'Toplam Alış' AS aciklama,
    SUM(miktarToplam) AS miktar,
    AVG(birimMaliyet) AS ortMaliyet
FROM bkm.fifo_StokMaliyetHavuzu
WHERE stkID = @testStkID AND kaynakTip IN ('ALIS', 'ACILIS', 'ACILIS_TAMAMLA', 'AYLIK_DEVIR')
UNION ALL
SELECT 
    'Toplam Satış',
    SUM(miktar),
    AVG(birimMaliyet)
FROM bkm.fifo_StokMaliyetCikis
WHERE stkID = @testStkID AND hareketTipi = 'SATIS'
UNION ALL
SELECT 
    'Kalan Stok',
    SUM(miktarKalan),
    AVG(birimMaliyet)
FROM bkm.fifo_StokMaliyetHavuzu
WHERE stkID = @testStkID AND miktarKalan > 0;

-- 6) Manuel doğrulama
PRINT '';
PRINT '========================================';
PRINT 'MANUEL DOĞRULAMA:';
PRINT '========================================';
PRINT '1. Alış miktarları ile katman miktarları eşleşiyor mu?';
PRINT '2. Satış miktarları ile FIFO çıkış miktarları eşleşiyor mu?';
PRINT '3. FIFO çıkışları en eski katmanlardan mı başlıyor?';
PRINT '4. Kalan stok = Toplam Alış - Toplam Satış mı?';
PRINT '';
PRINT 'Bu soruları yukarıdaki verilere bakarak kontrol edin!';
PRINT '========================================';
GO

