-- =============================================================
-- TAM TEST SENARYOSU
-- Gerçek verilerle FIFO sistemini test et
-- =============================================================

PRINT '========================================';
PRINT 'FIFO STOK MALİYET SİSTEMİ - TAM TEST';
PRINT 'Başlangıç: ' + CONVERT(VARCHAR(20), GETDATE(), 120);
PRINT '========================================';
PRINT '';

-- Test parametreleri
DECLARE @envanterTarihi DATE = '2025-08-31';  -- Ağustos sonu açılış
DECLARE @testBaslangic DATE = '2025-09-01';   -- Eylül başı
DECLARE @testBitis DATE = '2025-11-27';       -- Bugün

-- ========================================
-- ADIM 1: AÇILIŞ STOKU OLUŞTUR
-- ========================================
PRINT '';
PRINT '========================================';
PRINT 'ADIM 1: AÇILIŞ STOKU OLUŞTURULUYOR';
PRINT 'Envanter Tarihi: ' + CONVERT(VARCHAR(10), @envanterTarihi, 120);
PRINT '========================================';

BEGIN TRY
    EXEC bkm.sp_fifo_StokMaliyetAcilis @envanterTarihi = @envanterTarihi;
    
    -- Sonuçları kontrol et
    DECLARE @acilisKatmanSayisi INT, @acilisUrunSayisi INT;
    
    SELECT 
        @acilisKatmanSayisi = COUNT(*),
        @acilisUrunSayisi = COUNT(DISTINCT stkID)
    FROM bkm.fifo_StokMaliyetHavuzu
    WHERE kaynakTip IN ('ACILIS', 'ACILIS_TAMAMLA');
    
    PRINT '';
    PRINT 'SONUÇ:';
    PRINT '  - Oluşturulan katman sayısı: ' + CAST(@acilisKatmanSayisi AS VARCHAR(10));
    PRINT '  - Ürün sayısı: ' + CAST(@acilisUrunSayisi AS VARCHAR(10));
    
    -- Sorunlu kayıtlar var mı?
    DECLARE @sorunSayisi INT;
    SELECT @sorunSayisi = COUNT(*)
    FROM bkm.fifo_StokMaliyetSorunlu
    WHERE envanterTarihi = @envanterTarihi;
    
    IF @sorunSayisi > 0
    BEGIN
        PRINT '  - UYARI: ' + CAST(@sorunSayisi AS VARCHAR(10)) + ' sorunlu kayıt var!';
        
        SELECT TOP 5
            sorunTip,
            COUNT(*) AS adet
        FROM bkm.fifo_StokMaliyetSorunlu
        WHERE envanterTarihi = @envanterTarihi
        GROUP BY sorunTip;
    END
    ELSE
    BEGIN
        PRINT '  - Sorunlu kayıt yok.';
    END
    
END TRY
BEGIN CATCH
    PRINT 'HATA: ' + ERROR_MESSAGE();
END CATCH

-- ========================================
-- ADIM 2: ALIŞ KATMANLARI EKLE
-- ========================================
PRINT '';
PRINT '========================================';
PRINT 'ADIM 2: ALIŞ KATMANLARI EKLENİYOR';
PRINT 'Tarih Aralığı: ' + CONVERT(VARCHAR(10), @testBaslangic, 120) + 
      ' - ' + CONVERT(VARCHAR(10), @testBitis, 120);
PRINT '========================================';

BEGIN TRY
    EXEC bkm.sp_fifo_StokMaliyetAlisKatman 
        @baslangicTarihi = @testBaslangic,
        @bitisTarihi = @testBitis;
    
    -- Sonuçları kontrol et
    DECLARE @alisKatmanSayisi INT, @alisUrunSayisi INT;
    
    SELECT 
        @alisKatmanSayisi = COUNT(*),
        @alisUrunSayisi = COUNT(DISTINCT stkID)
    FROM bkm.fifo_StokMaliyetHavuzu
    WHERE kaynakTip = 'ALIS'
      AND girisTarihi >= @testBaslangic
      AND girisTarihi <= @testBitis;
    
    PRINT '';
    PRINT 'SONUÇ:';
    PRINT '  - Oluşturulan alış katmanı: ' + CAST(@alisKatmanSayisi AS VARCHAR(10));
    PRINT '  - Ürün sayısı: ' + CAST(@alisUrunSayisi AS VARCHAR(10));
    
END TRY
BEGIN CATCH
    PRINT 'HATA: ' + ERROR_MESSAGE();
END CATCH

-- ========================================
-- ADIM 3: FIFO ÇIKIŞ HESAPLA
-- ========================================
PRINT '';
PRINT '========================================';
PRINT 'ADIM 3: FIFO ÇIKIŞ HESAPLANIYOR';
PRINT 'Tarih Aralığı: ' + CONVERT(VARCHAR(10), @testBaslangic, 120) + 
      ' - ' + CONVERT(VARCHAR(10), @testBitis, 120);
PRINT '========================================';

BEGIN TRY
    EXEC bkm.sp_fifo_StokMaliyetFIFOCikis 
        @satisBaslangic = @testBaslangic,
        @satisBitis = @testBitis;
    
    -- Sonuçları kontrol et
    DECLARE @cikisSayisi INT, @satisUrunSayisi INT, @toplamCOGS DECIMAL(18,2);
    
    SELECT 
        @cikisSayisi = COUNT(*),
        @satisUrunSayisi = COUNT(DISTINCT stkID),
        @toplamCOGS = SUM(cikisTutar)
    FROM bkm.fifo_StokMaliyetCikis
    WHERE hareketTarihi >= @testBaslangic
      AND hareketTarihi <= @testBitis;
    
    PRINT '';
    PRINT 'SONUÇ:';
    PRINT '  - Çıkış satırı sayısı: ' + CAST(@cikisSayisi AS VARCHAR(10));
    PRINT '  - Ürün sayısı: ' + CAST(@satisUrunSayisi AS VARCHAR(10));
    PRINT '  - Toplam COGS: ' + CAST(@toplamCOGS AS VARCHAR(20)) + ' TL';
    
    -- Yetersiz stok var mı?
    DECLARE @yetersizStok INT;
    SELECT @yetersizStok = COUNT(*)
    FROM bkm.fifo_StokMaliyetSorunlu
    WHERE sorunTip = 'STOK_YETERSIZ'
      AND envanterTarihi = @testBitis;
    
    IF @yetersizStok > 0
    BEGIN
        PRINT '  - UYARI: ' + CAST(@yetersizStok AS VARCHAR(10)) + ' ürün yetersiz stok!';
    END
    
END TRY
BEGIN CATCH
    PRINT 'HATA: ' + ERROR_MESSAGE();
END CATCH

-- ========================================
-- ADIM 4: RAPORLARI KONTROL ET
-- ========================================
PRINT '';
PRINT '========================================';
PRINT 'ADIM 4: RAPORLAR';
PRINT '========================================';

-- Günlük SMM özeti
PRINT '';
PRINT 'Günlük SMM Özeti (Son 7 gün):';
SELECT TOP 7
    hareketTarihi,
    satisMaliyeti,
    iadeMaliyeti,
    netMaliyet,
    satirSayisi
FROM bkm.fifo_vw_GunlukSMM
ORDER BY hareketTarihi DESC;

-- En çok satan ürünler
PRINT '';
PRINT 'En Çok Maliyet Oluşturan 10 Ürün:';
SELECT TOP 10
    stkID,
    SUM(toplamMiktar) AS toplamMiktar,
    SUM(toplamMaliyet) AS toplamMaliyet,
    AVG(ortalamaBirimMaliyet) AS ortBirimMaliyet
FROM bkm.fifo_vw_UrunBazliSMM
WHERE hareketTarihi >= @testBaslangic
GROUP BY stkID
ORDER BY SUM(toplamMaliyet) DESC;

-- Katman durumu
PRINT '';
PRINT 'Katman Durumu Özeti:';
SELECT 
    kaynakTip,
    COUNT(*) AS katmanSayisi,
    SUM(miktarKalan) AS toplamKalanMiktar,
    AVG(birimMaliyet) AS ortBirimMaliyet
FROM bkm.fifo_StokMaliyetHavuzu
WHERE miktarKalan > 0
GROUP BY kaynakTip;

PRINT '';
PRINT '========================================';
PRINT 'TEST TAMAMLANDI';
PRINT 'Bitiş: ' + CONVERT(VARCHAR(20), GETDATE(), 120);
PRINT '========================================';
GO
