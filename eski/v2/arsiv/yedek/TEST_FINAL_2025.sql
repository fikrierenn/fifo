-- =============================================================
-- FİNAL TEST SENARYOSU - 2025 YILI
-- 99,953 ürünle tam test
-- =============================================================

PRINT '========================================';
PRINT 'FIFO SİSTEMİ - FİNAL TEST';
PRINT 'Tarih: 2025 Yılı';
PRINT 'Başlangıç: ' + CONVERT(VARCHAR(20), GETDATE(), 120);
PRINT '========================================';
PRINT '';

-- Test parametreleri
DECLARE @envanterTarihi DATE = '2024-12-31';  -- 2024 sonu açılış
DECLARE @testBaslangic DATE = '2025-01-01';   -- 2025 başı
DECLARE @testBitis DATE = '2025-11-27';       -- Bugün

-- ========================================
-- ADIM 1: AÇILIŞ STOKU
-- ========================================
PRINT 'ADIM 1: Açılış stoku oluşturuluyor...';
PRINT 'Envanter Tarihi: ' + CONVERT(VARCHAR(10), @envanterTarihi, 120);

BEGIN TRY
    EXEC bkm.sp_fifo_StokMaliyetAcilis @envanterTarihi = @envanterTarihi;
    
    DECLARE @acilisKatman INT, @acilisUrun INT;
    SELECT 
        @acilisKatman = COUNT(*),
        @acilisUrun = COUNT(DISTINCT stkID)
    FROM bkm.fifo_StokMaliyetHavuzu
    WHERE kaynakTip IN ('ACILIS', 'ACILIS_TAMAMLA');
    
    PRINT '  ✓ Katman sayısı: ' + CAST(@acilisKatman AS VARCHAR(10));
    PRINT '  ✓ Ürün sayısı: ' + CAST(@acilisUrun AS VARCHAR(10));
END TRY
BEGIN CATCH
    PRINT '  ✗ HATA: ' + ERROR_MESSAGE();
END CATCH

-- ========================================
-- ADIM 2: ALIŞ KATMANLARI
-- ========================================
PRINT '';
PRINT 'ADIM 2: Alış katmanları ekleniyor...';
PRINT 'Tarih: ' + CONVERT(VARCHAR(10), @testBaslangic, 120) + 
      ' - ' + CONVERT(VARCHAR(10), @testBitis, 120);

BEGIN TRY
    EXEC bkm.sp_fifo_StokMaliyetAlisKatman 
        @baslangicTarihi = @testBaslangic,
        @bitisTarihi = @testBitis;
    
    DECLARE @alisKatman INT, @alisUrun INT;
    SELECT 
        @alisKatman = COUNT(*),
        @alisUrun = COUNT(DISTINCT stkID)
    FROM bkm.fifo_StokMaliyetHavuzu
    WHERE kaynakTip = 'ALIS'
      AND girisTarihi >= @testBaslangic;
    
    PRINT '  ✓ Katman sayısı: ' + CAST(@alisKatman AS VARCHAR(10));
    PRINT '  ✓ Ürün sayısı: ' + CAST(@alisUrun AS VARCHAR(10));
END TRY
BEGIN CATCH
    PRINT '  ✗ HATA: ' + ERROR_MESSAGE();
END CATCH

-- ========================================
-- ADIM 3: FIFO ÇIKIŞ
-- ========================================
PRINT '';
PRINT 'ADIM 3: FIFO çıkış hesaplanıyor...';

BEGIN TRY
    EXEC bkm.sp_fifo_StokMaliyetFIFOCikis 
        @satisBaslangic = @testBaslangic,
        @satisBitis = @testBitis;
    
    DECLARE @cikisSatir INT, @cikisUrun INT, @toplamCOGS DECIMAL(18,2);
    SELECT 
        @cikisSatir = COUNT(*),
        @cikisUrun = COUNT(DISTINCT stkID),
        @toplamCOGS = SUM(cikisTutar)
    FROM bkm.fifo_StokMaliyetCikis
    WHERE hareketTarihi >= @testBaslangic;
    
    PRINT '  ✓ Çıkış satırı: ' + CAST(@cikisSatir AS VARCHAR(10));
    PRINT '  ✓ Ürün sayısı: ' + CAST(@cikisUrun AS VARCHAR(10));
    PRINT '  ✓ Toplam COGS: ' + FORMAT(@toplamCOGS, 'N2') + ' TL';
END TRY
BEGIN CATCH
    PRINT '  ✗ HATA: ' + ERROR_MESSAGE();
END CATCH

-- ========================================
-- ADIM 4: SONUÇLAR
-- ========================================
PRINT '';
PRINT '========================================';
PRINT 'SONUÇLAR';
PRINT '========================================';

-- Katman durumu
PRINT '';
PRINT 'Katman Durumu:';
SELECT 
    kaynakTip,
    COUNT(*) AS katmanSayisi,
    COUNT(DISTINCT stkID) AS urunSayisi,
    SUM(miktarKalan) AS kalanMiktar,
    AVG(birimMaliyet) AS ortMaliyet
FROM bkm.fifo_StokMaliyetHavuzu
WHERE miktarKalan > 0
GROUP BY kaynakTip;

-- Aylık COGS
PRINT '';
PRINT 'Aylık COGS (2025):';
SELECT 
    YEAR(hareketTarihi) AS yil,
    MONTH(hareketTarihi) AS ay,
    SUM(CASE WHEN hareketTipi = 'SATIS' THEN cikisTutar ELSE 0 END) AS satisCOGS,
    SUM(CASE WHEN hareketTipi = 'IADE' THEN cikisTutar ELSE 0 END) AS iadeCOGS,
    SUM(cikisTutar) AS netCOGS
FROM bkm.fifo_StokMaliyetCikis
WHERE hareketTarihi >= @testBaslangic
GROUP BY YEAR(hareketTarihi), MONTH(hareketTarihi)
ORDER BY yil, ay;

-- En çok maliyet oluşturan 10 ürün
PRINT '';
PRINT 'En Yüksek Maliyetli 10 Ürün:';
SELECT TOP 10
    stkID,
    SUM(miktar) AS toplamMiktar,
    SUM(cikisTutar) AS toplamMaliyet,
    AVG(birimMaliyet) AS ortBirimMaliyet
FROM bkm.fifo_StokMaliyetCikis
WHERE hareketTarihi >= @testBaslangic
GROUP BY stkID
ORDER BY SUM(cikisTutar) DESC;

-- Sorunlar
DECLARE @sorunSayisi INT;
SELECT @sorunSayisi = COUNT(*) FROM bkm.fifo_StokMaliyetSorunlu;

PRINT '';
IF @sorunSayisi > 0
BEGIN
    PRINT 'SORUNLAR (' + CAST(@sorunSayisi AS VARCHAR(10)) + ' kayıt):';
    SELECT 
        sorunTip,
        COUNT(*) AS adet
    FROM bkm.fifo_StokMaliyetSorunlu
    GROUP BY sorunTip;
END
ELSE
BEGIN
    PRINT '✓ Sorun yok!';
END

PRINT '';
PRINT '========================================';
PRINT 'TEST TAMAMLANDI';
PRINT 'Bitiş: ' + CONVERT(VARCHAR(20), GETDATE(), 120);
PRINT '========================================';
GO
