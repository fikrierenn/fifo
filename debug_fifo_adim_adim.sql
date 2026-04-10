-- =============================================================
-- FIFO ADIM ADIM DEBUG SCRIPTI
-- Her adımı ayrı ayrı çalıştırıp sonuçları görebilirsiniz
-- =============================================================

USE BKMMaliyet;
GO

DECLARE @testStkID INT = 594124;
DECLARE @satinalmaSarti VARCHAR(50) = 'SART310521';
DECLARE @envanterTarihi DATE = '02.06.2021'; -- Devir kayıt tarihinden sonra

PRINT '========================================';
PRINT 'FIFO ADIM ADIM DEBUG - ÜRÜN: ' + CAST(@testStkID AS VARCHAR(10));
PRINT '========================================';
PRINT '';

-- =============================================================
-- ADIM 1: BAŞLANGIÇ DURUMU - TABLOLAR TEMİZ Mİ?
-- =============================================================
PRINT '========================================';
PRINT 'ADIM 1: BAŞLANGIÇ DURUMU KONTROLÜ';
PRINT '========================================';
PRINT '';

PRINT '1.1 - fifo_StokMaliyetHavuzu tablosunda bu ürün var mı?';
SELECT COUNT(*) AS KayitSayisi
FROM bkm.fifo_StokMaliyetHavuzu
WHERE stkID = @testStkID;

PRINT '';
PRINT '1.2 - fifo_StokMaliyetCikis tablosunda bu ürün var mı?';
SELECT COUNT(*) AS KayitSayisi
FROM bkm.fifo_StokMaliyetCikis
WHERE stkID = @testStkID;

PRINT '';
PRINT '1.3 - fifo_StokMaliyetSorunlu tablosunda bu ürün var mı?';
SELECT COUNT(*) AS KayitSayisi
FROM bkm.fifo_StokMaliyetSorunlu
WHERE stkID = @testStkID;

PRINT '';
PRINT 'NOT: Eğer kayıt varsa, önce temizleme yapın:';
PRINT 'DELETE FROM bkm.fifo_StokMaliyetHavuzu WHERE stkID = ' + CAST(@testStkID AS VARCHAR(10)) + ';';
PRINT 'DELETE FROM bkm.fifo_StokMaliyetCikis WHERE stkID = ' + CAST(@testStkID AS VARCHAR(10)) + ';';
PRINT 'DELETE FROM bkm.fifo_StokMaliyetSorunlu WHERE stkID = ' + CAST(@testStkID AS VARCHAR(10)) + ';';
PRINT '';
PRINT '';

-- =============================================================
-- ADIM 2: ERP DEVİR FİYATI KONTROLÜ
-- =============================================================
PRINT '========================================';
PRINT 'ADIM 2: ERP DEVİR FİYATI KONTROLÜ';
PRINT '========================================';
PRINT '';

PRINT '2.1 - fifo_ErpDevirFiyatlari tablosunda bu ürün var mı?';
SELECT 
    stkID,
    satinalmaSarti,
    miktar AS DevirMiktar,
    birimMaliyet AS DevirBirimMaliyet,
    toplamTutar AS DevirToplamTutar,
    aciklama
FROM bkm.fifo_ErpDevirFiyatlari
WHERE stkID = @testStkID
  AND satinalmaSarti = @satinalmaSarti;

DECLARE @devirMiktar DECIMAL(18,4) = (
    SELECT miktar FROM bkm.fifo_ErpDevirFiyatlari 
    WHERE stkID = @testStkID AND satinalmaSarti = @satinalmaSarti
);

DECLARE @devirBirimMaliyet DECIMAL(18,6) = (
    SELECT birimMaliyet FROM bkm.fifo_ErpDevirFiyatlari 
    WHERE stkID = @testStkID AND satinalmaSarti = @satinalmaSarti
);

PRINT '';
PRINT 'Devir Miktar: ' + ISNULL(CAST(@devirMiktar AS VARCHAR(20)), 'YOK');
PRINT 'Devir Birim Maliyet: ' + ISNULL(CAST(@devirBirimMaliyet AS VARCHAR(20)), 'YOK');
PRINT '';
PRINT '';

-- =============================================================
-- ADIM 3: ENVANTER STOKU KONTROLÜ
-- =============================================================
PRINT '========================================';
PRINT 'ADIM 3: ENVANTER STOKU KONTROLÜ';
PRINT '========================================';
PRINT '';

PRINT '3.1 - Envanter tarihindeki stok miktarı (irsHrk - ehTip=99)';
PRINT '';

-- Mekan bazında devir stoku (direkt irsHrk'dan)
SELECT 
    ehMekan AS mekanID,
    SUM(ehAdetN) AS StokMiktar
FROM DerinSISBkm.dbo.irsHrk
WHERE ehstkID = @testStkID
  AND ehTip = 99
  AND ehTrhS = '31.05.2021'
  AND ehMekan IN (1, 12, 4477, 4478) -- Sadece sistem içi mekanlar
GROUP BY ehMekan;

DECLARE @toplamEnvanter DECIMAL(18,4) = (
    SELECT ISNULL(SUM(ehAdetN), 0)
    FROM DerinSISBkm.dbo.irsHrk
    WHERE ehstkID = @testStkID
      AND ehTip = 99
      AND ehTrhS = '31.05.2021'
      AND ehMekan IN (1, 12, 4477, 4478)
);

PRINT '';
PRINT 'Toplam Envanter Miktar: ' + CAST(@toplamEnvanter AS VARCHAR(20));
PRINT '';
PRINT '';

-- =============================================================
-- ADIM 4: AÇILIŞ STOKU OLUŞTURMA (ÖNIZLEME)
-- =============================================================
PRINT '========================================';
PRINT 'ADIM 4: AÇILIŞ STOKU ÖNİZLEME';
PRINT '========================================';
PRINT '';

PRINT '4.1 - ERP devir fiyatı ile oluşturulacak açılış katmanı';
PRINT 'NOT: Bu sadece önizleme, tabloya INSERT yapılmıyor';
PRINT '';

IF @devirMiktar IS NOT NULL AND @devirBirimMaliyet IS NOT NULL
BEGIN
    -- Oluşturulacak katmanı göster
    SELECT 
        @testStkID AS stkID,
        @envanterTarihi AS girisTarihi,
        'ACILIS' AS kaynakTip,
        'ERP_' + @satinalmaSarti AS belgeNo,
        @envanterTarihi AS belgeTarihi,
        NULL AS firmaID,
        @devirMiktar AS miktarToplam,
        @devirMiktar AS miktarKalan,
        @devirBirimMaliyet AS birimMaliyet,
        'NORMAL' AS durum;
    
    PRINT '';
    PRINT 'Bu katman sp_fifo_StokMaliyetAcilis ile oluşturulacak';
END
ELSE
BEGIN
    PRINT 'HATA: ERP devir fiyatı bulunamadı!';
END

PRINT '';
PRINT '';

-- =============================================================
-- ADIM 5: ENVANTER FARKI KONTROLÜ
-- =============================================================
PRINT '========================================';
PRINT 'ADIM 5: ENVANTER FARKI KONTROLÜ';
PRINT '========================================';
PRINT '';

DECLARE @katmanToplam DECIMAL(18,4) = ISNULL(@devirMiktar, 0);

PRINT 'Katman Toplam Miktar (ERP Devir): ' + CAST(@katmanToplam AS VARCHAR(20));
PRINT 'Envanter Miktar: ' + CAST(@toplamEnvanter AS VARCHAR(20));
PRINT 'Fark: ' + CAST((@toplamEnvanter - @katmanToplam) AS VARCHAR(20));
PRINT '';

IF @toplamEnvanter > @katmanToplam
BEGIN
    PRINT 'UYARI: Envanter fazlası var! Tamamlama katmanı gerekli.';
    PRINT '';
    
    DECLARE @fark DECIMAL(18,4) = @toplamEnvanter - @katmanToplam;
    
    -- Son geçerli fiyat kontrolü
    PRINT '5.1 - Son geçerli fiyat kontrolü';
    DECLARE @sonFiyat DECIMAL(18,6);
    
    -- fn_SonGecerliFiyat fonksiyonu varsa kullan
    BEGIN TRY
        SET @sonFiyat = DerinSISBkm.bkm.fn_SonGecerliFiyat(@testStkID, @envanterTarihi);
    END TRY
    BEGIN CATCH
        SET @sonFiyat = NULL;
        PRINT 'UYARI: fn_SonGecerliFiyat fonksiyonu bulunamadı';
    END CATCH
    
    PRINT 'Son Geçerli Fiyat: ' + ISNULL(CAST(@sonFiyat AS VARCHAR(20)), 'YOK');
    PRINT '';
    
    IF @sonFiyat IS NOT NULL AND @sonFiyat > 0
    BEGIN
        -- Oluşturulacak tamamlama katmanını göster
        PRINT '5.2 - Oluşturulacak tamamlama katmanı (ÖNİZLEME):';
        SELECT 
            @testStkID AS stkID,
            @envanterTarihi AS girisTarihi,
            'ACILIS_TAMAMLA' AS kaynakTip,
            'TAMAMLA' AS belgeNo,
            @envanterTarihi AS belgeTarihi,
            NULL AS firmaID,
            @fark AS miktarToplam,
            @fark AS miktarKalan,
            @sonFiyat AS birimMaliyet,
            'NORMAL' AS durum;
        
        PRINT '';
        PRINT 'Bu katman sp_fifo_StokMaliyetAcilis ile oluşturulacak';
    END
    ELSE
    BEGIN
        PRINT 'HATA: Son geçerli fiyat bulunamadı veya sıfır!';
        PRINT 'Bu ürün sorunlu stok olarak kaydedilecek:';
        SELECT 
            @testStkID AS stkID,
            @envanterTarihi AS envanterTarihi,
            @fark AS stokMiktar,
            'MALIYET_YOK' AS sorunTip,
            'Son geçerli fiyat bulunamadı' AS aciklama;
    END
END
ELSE IF @toplamEnvanter < @katmanToplam
BEGIN
    PRINT 'UYARI: Envanter eksiği var! Katman miktarı fazla.';
END
ELSE
BEGIN
    PRINT 'OK: Envanter ve katman miktarları eşit.';
END

PRINT '';
PRINT '';

-- =============================================================
-- ADIM 6: OLUŞACAK KATMANLARIN ÖNİZLEMESİ
-- =============================================================
PRINT '========================================';
PRINT 'ADIM 6: OLUŞACAK KATMANLAR (ÖNİZLEME)';
PRINT '========================================';
PRINT '';

PRINT 'NOT: Bu sadece önizleme, gerçek katmanlar sp_fifo_StokMaliyetAcilis ile oluşturulacak';
PRINT '';

-- Mevcut katmanları göster (varsa)
IF EXISTS (SELECT 1 FROM bkm.fifo_StokMaliyetHavuzu WHERE stkID = @testStkID)
BEGIN
    PRINT 'MEVCUT KATMANLAR (Tabloda):';
    SELECT 
        ID AS KatmanID,
        stkID,
        girisTarihi,
        kaynakTip,
        belgeNo,
        miktarToplam,
        miktarKalan,
        birimMaliyet,
        miktarKalan * birimMaliyet AS ToplamMaliyet,
        durum,
        kayitTarihi
    FROM bkm.fifo_StokMaliyetHavuzu
    WHERE stkID = @testStkID
    ORDER BY ID;
END
ELSE
BEGIN
    PRINT 'Tabloda henüz katman yok.';
END

PRINT '';
PRINT '';

-- =============================================================
-- ADIM 7: ALIŞ HAREKETLERİ (Haziran-Aralık 2021)
-- =============================================================
PRINT '========================================';
PRINT 'ADIM 7: ALIŞ HAREKETLERİ KONTROLÜ';
PRINT '========================================';
PRINT '';

PRINT '7.1 - Alış hareketleri (İrsaliye + Fatura eşleştirmesi)';
PRINT 'NOT: İrsaliye ile fatura eşleştirilir (irs + irsAyr + fatAyr + fat)';
PRINT '';

SELECT 
    i.eID AS IrsaliyeID,
    i.eNo AS IrsaliyeNo,
    i.eTarih AS IrsaliyeTarihi,
    i.eTip AS IrsaliyeTipi,
    f.eID AS FaturaID,
    f.eNo AS FaturaNo,
    f.eTarih AS FaturaTarihi,
    f.eFirma AS TedarikciID,
    a.ehStkID AS UrunID,
    a.ehAdetN AS Miktar,
    a.ehTutarN AS ToplamTutar,
    a.ehTutarN / NULLIF(a.ehAdetN, 0) AS BirimMaliyet
FROM DerinSISBkm.dbo.irs i
JOIN DerinSISBkm.dbo.irsAyr ia ON ia.ehID = i.eID
JOIN DerinSISBkm.dbo.fatAyr a 
    ON a.ehIrsID = i.eID 
   AND a.ehIrsSira = ia.ehSira 
   AND a.ehStkID = @testStkID
JOIN DerinSISBkm.dbo.fat f ON f.eID = a.ehID
WHERE i.eTip IN (2, 0, 10, 3, 6, 102, 103) -- Alış tipleri
  AND i.eTarih BETWEEN '01.06.2021' AND '31.12.2021'
  AND i.eMekan IN (1, 12, 4477, 4478)
  AND a.ehAdetN <> 0
ORDER BY i.eTarih, i.eID;

DECLARE @alisAdet INT = (
    SELECT COUNT(DISTINCT i.eID)
    FROM DerinSISBkm.dbo.irs i
    JOIN DerinSISBkm.dbo.irsAyr ia ON ia.ehID = i.eID
    JOIN DerinSISBkm.dbo.fatAyr a 
        ON a.ehIrsID = i.eID 
       AND a.ehIrsSira = ia.ehSira 
       AND a.ehStkID = @testStkID
    JOIN DerinSISBkm.dbo.fat f ON f.eID = a.ehID
    WHERE i.eTip IN (2, 0, 10, 3, 6, 102, 103)
      AND i.eTarih BETWEEN '01.06.2021' AND '31.12.2021'
      AND i.eMekan IN (1, 12, 4477, 4478)
      AND a.ehAdetN <> 0
);

PRINT '';
PRINT 'Toplam Alış Sayısı (İrsaliye-Fatura eşleşmesi): ' + CAST(ISNULL(@alisAdet, 0) AS VARCHAR(10));
PRINT '';
PRINT 'NOT: Bu hareketler sp_fifo_StokMaliyetAlisKatman ile katman olarak eklenecek';
PRINT 'NOT: Sadece faturası olan irsaliyeler katman oluşturur (maliyet bilinir)';
PRINT '';
PRINT '';

-- =============================================================
-- ADIM 8: SATIŞ HAREKETLERİ (Haziran-Aralık 2021)
-- =============================================================
PRINT '========================================';
PRINT 'ADIM 8: SATIŞ HAREKETLERİ KONTROLÜ (İRSALİYEDEN)';
PRINT '========================================';
PRINT '';

PRINT '8.1 - Satış irsaliyeleri (irsHrk tablosundan)';
PRINT 'NOT: Satışlar irsaliyeden alınır (çıkış anında maliyetlendirme)';
PRINT '';

SELECT 
    h.hrkID,
    h.ehTrhS AS StokCikisTarihi,
    h.ehMekan AS MekanID,
    h.ehTip AS HareketTipi,
    ABS(h.ehAdetN) AS Miktar,
    ABS(h.ehMlyt) AS ToplamTutar,
    ABS(h.ehMlyt) / NULLIF(ABS(h.ehAdetN), 0) AS BirimSatisFiyati
FROM DerinSISBkm.dbo.irsHrk h
WHERE h.ehstkID = @testStkID
  AND h.ehTrhS BETWEEN '01.06.2021' AND '31.12.2021'
  AND h.ehTip <> 99 -- Devir hariç
  AND h.ehAdetN < 0 -- Satış (negatif miktar)
ORDER BY h.ehTrhS, h.hrkID;

DECLARE @satisAdet INT = (
    SELECT COUNT(DISTINCT h.hrkID)
    FROM DerinSISBkm.dbo.irsHrk h
    WHERE h.ehstkID = @testStkID
      AND h.ehTrhS BETWEEN '01.06.2021' AND '31.12.2021'
      AND h.ehTip <> 99
      AND h.ehAdetN < 0
);

PRINT '';
PRINT 'Toplam Satış İrsaliye Sayısı: ' + CAST(ISNULL(@satisAdet, 0) AS VARCHAR(10));
PRINT '';
PRINT 'NOT: Bu satışlar sp_fifo_StokMaliyetFIFOCikis ile FIFO mantığıyla maliyetlendirilecek';
PRINT '';
PRINT '';

-- =============================================================
-- ÖZET
-- =============================================================
PRINT '========================================';
PRINT 'ÖZET';
PRINT '========================================';
PRINT '';
PRINT 'Ürün ID: ' + CAST(@testStkID AS VARCHAR(10));
PRINT 'Satınalma Şartı: ' + @satinalmaSarti;
PRINT 'Envanter Tarihi: ' + CAST(@envanterTarihi AS VARCHAR(10));
PRINT '';
PRINT 'SONRAKİ ADIMLAR:';
PRINT '1. sp_fifo_StokMaliyetAlisKatman - Alış katmanlarını ekle';
PRINT '2. sp_fifo_StokMaliyetFIFOCikis - Satışları FIFO ile maliyetlendir';
PRINT '3. Sonuçları kontrol et';
PRINT '';
PRINT 'Debug tamamlandı!';
GO
