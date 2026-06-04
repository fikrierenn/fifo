-- =============================================================
-- ÜRÜN 594124 DETAYLI KONTROL SCRIPTI
-- Tüm senaryoları test etmek için kapsamlı analiz
-- =============================================================

USE BKMMaliyet;
GO

DECLARE @testStkID INT = 594124;
DECLARE @satinalmaSarti VARCHAR(50) = 'SART310521';

PRINT '========================================';
PRINT 'ÜRÜN 594124 DETAYLI ANALİZ';
PRINT '========================================';
PRINT '';

-- =============================================================
-- 1. ÜRÜN BİLGİLERİ
-- =============================================================
PRINT '1. ÜRÜN BİLGİLERİ';
PRINT '----------------------------------------------------------------';

SELECT 
    u.stkID,
    u.stkAd AS UrunAdi,
    u.stkKod AS UrunKodu
FROM DerinSISBkm.bkm.UrunBilgi u
WHERE u.stkID = @testStkID;

PRINT '';
PRINT '';

-- =============================================================
-- 2. ERP DEVİR FİYATI KONTROLÜ
-- =============================================================
PRINT '2. ERP DEVİR FİYATI (31.05.2021)';
PRINT '----------------------------------------------------------------';

SELECT 
    e.stkID,
    e.satinalmaSarti,
    e.miktar AS DevirMiktar,
    e.birimMaliyet AS DevirBirimMaliyet,
    e.toplamTutar AS DevirToplamTutar,
    e.aciklama,
    e.kayitTarihi
FROM bkm.fifo_ErpDevirFiyatlari e
WHERE e.stkID = @testStkID
  AND e.satinalmaSarti = @satinalmaSarti;

-- Eğer yoksa uyarı ver
IF NOT EXISTS (SELECT 1 FROM bkm.fifo_ErpDevirFiyatlari WHERE stkID = @testStkID AND satinalmaSarti = @satinalmaSarti)
BEGIN
    PRINT 'UYARI: Bu ürün için ERP devir fiyatı bulunamadı!';
END

PRINT '';
PRINT '';

-- =============================================================
-- 3. DEVIR HAREKET DETAYI (irsHrk - ehTip=99)
-- =============================================================
PRINT '3. DEVIR HAREKET DETAYI (irsHrk tablosundan)';
PRINT '----------------------------------------------------------------';

SELECT 
    h.ehID,
    h.ehstkID,
    h.ehMekan AS MekanID,
    h.ehTrhS AS StokGirisTarihi,
    h.hrkTarih AS EvrakKayitTarihi,
    h.ehAdetN AS Miktar,
    h.ehMlyt AS Maliyet,
    h.ehMlyt / NULLIF(h.ehAdetN, 0) AS BirimMaliyet,
    h.ehTip AS HareketTipi,
    h.hrkID AS HareketID
FROM DerinSISBkm.dbo.irsHrk h
WHERE h.ehstkID = @testStkID
  AND h.ehTip = 99 -- Devir
  AND h.ehTrhS = '31.05.2021'
ORDER BY h.ehMekan, h.hrkID;

PRINT '';
PRINT '';

-- =============================================================
-- 4. ALIŞ HAREKETLERİ (01.06.2021 - 31.12.2021)
-- =============================================================
PRINT '4. ALIŞ HAREKETLERİ (Haziran-Aralık 2021)';
PRINT '----------------------------------------------------------------';

SELECT 
    h.hrkID AS HareketID,
    h.ehMekan AS MekanID,
    h.ehTrhS AS StokGirisTarihi,
    h.hrkTarih AS EvrakKayitTarihi,
    h.ehTip AS HareketTipi,
    h.ehAdetN AS Miktar,
    h.ehMlyt AS ToplamMaliyet,
    h.ehMlyt / NULLIF(h.ehAdetN, 0) AS BirimMaliyet
FROM DerinSISBkm.dbo.irsHrk h
WHERE h.ehstkID = @testStkID
  AND h.ehTrhS BETWEEN '01.06.2021' AND '31.12.2021'
  AND h.ehTip <> 99 -- Devir hariç
  AND h.ehAdetN > 0 -- Alış (pozitif miktar)
ORDER BY h.ehTrhS, h.hrkID;

DECLARE @alisAdet INT = (
    SELECT COUNT(DISTINCT h.hrkID)
    FROM DerinSISBkm.dbo.irsHrk h
    WHERE h.ehstkID = @testStkID
      AND h.ehTrhS BETWEEN '01.06.2021' AND '31.12.2021'
      AND h.ehTip <> 99
      AND h.ehAdetN > 0
);

PRINT '';
PRINT 'Toplam Alış Hareket Sayısı: ' + CAST(ISNULL(@alisAdet, 0) AS VARCHAR(10));
PRINT '';
PRINT '';

-- =============================================================
-- 5. SATIŞ HAREKETLERİ (01.06.2021 - 31.12.2021)
-- =============================================================
PRINT '5. SATIŞ HAREKETLERİ (Haziran-Aralık 2021)';
PRINT '----------------------------------------------------------------';

SELECT 
    h.hrkID AS HareketID,
    h.ehMekan AS MekanID,
    h.ehTrhS AS StokGirisTarihi,
    h.hrkTarih AS EvrakKayitTarihi,
    h.ehTip AS HareketTipi,
    h.ehAdetN AS Miktar,
    ABS(h.ehMlyt) AS ToplamMaliyet,
    ABS(h.ehMlyt) / NULLIF(ABS(h.ehAdetN), 0) AS BirimMaliyet
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
PRINT 'Toplam Satış Hareket Sayısı: ' + CAST(ISNULL(@satisAdet, 0) AS VARCHAR(10));
PRINT '';
PRINT '';

-- =============================================================
-- 6. TÜM HAREKETLERİN ÖZETİ
-- =============================================================
PRINT '6. TÜM HAREKETLERİN ÖZETİ';
PRINT '----------------------------------------------------------------';

SELECT 
    HareketTuru,
    COUNT(DISTINCT hrkID) AS HareketSayisi,
    SUM(ehAdetN) AS ToplamMiktar,
    SUM(ehMlyt) AS ToplamMaliyet,
    AVG(BirimMaliyet) AS OrtalamaBirimMaliyet,
    MIN(ehTrhS) AS IlkHareketTarihi,
    MAX(ehTrhS) AS SonHareketTarihi
FROM (
    SELECT 
        h.hrkID,
        h.ehAdetN,
        h.ehMlyt,
        h.ehTrhS,
        h.ehMlyt / NULLIF(ABS(h.ehAdetN), 0) AS BirimMaliyet,
        CASE 
            WHEN h.ehTip = 99 THEN 'DEVIR'
            WHEN h.ehAdetN > 0 THEN 'ALIŞ'
            WHEN h.ehAdetN < 0 THEN 'SATIŞ'
            ELSE 'DİĞER'
        END AS HareketTuru,
        CASE 
            WHEN h.ehTip = 99 THEN 1
            WHEN h.ehAdetN > 0 THEN 2
            WHEN h.ehAdetN < 0 THEN 3
            ELSE 4
        END AS SiraNo
    FROM DerinSISBkm.dbo.irsHrk h
    WHERE h.ehstkID = @testStkID
      AND h.ehTrhS BETWEEN '31.05.2021' AND '31.12.2021'
) AS Hareketler
GROUP BY HareketTuru, SiraNo
ORDER BY SiraNo;

PRINT '';
PRINT '';

-- =============================================================
-- 7. MEKAN BAZINDA ÖZET
-- =============================================================
PRINT '7. MEKAN BAZINDA HAREKET ÖZETİ';
PRINT '----------------------------------------------------------------';

SELECT 
    h.ehMekan AS MekanID,
    COUNT(DISTINCT h.hrkID) AS ToplamHareketSayisi,
    SUM(CASE WHEN h.ehAdetN > 0 AND h.ehTip <> 99 THEN 1 ELSE 0 END) AS AlisHareketSayisi,
    SUM(CASE WHEN h.ehAdetN < 0 THEN 1 ELSE 0 END) AS SatisHareketSayisi,
    SUM(CASE WHEN h.ehTip = 99 THEN 1 ELSE 0 END) AS DevirHareketSayisi,
    SUM(h.ehAdetN) AS NetMiktar
FROM DerinSISBkm.dbo.irsHrk h
WHERE h.ehstkID = @testStkID
  AND h.ehTrhS BETWEEN '31.05.2021' AND '31.12.2021'
GROUP BY h.ehMekan
ORDER BY h.ehMekan;

PRINT '';
PRINT '';

-- =============================================================
-- 8. KRONOLOJIK HAREKET AKIŞI (İlk 20 hareket)
-- =============================================================
PRINT '8. KRONOLOJIK HAREKET AKIŞI (İlk 20 hareket)';
PRINT '----------------------------------------------------------------';

SELECT TOP 20
    ROW_NUMBER() OVER (ORDER BY h.ehTrhS, h.hrkID) AS SiraNo,
    h.hrkID AS HareketID,
    h.ehTrhS AS StokGirisTarihi,
    h.hrkTarih AS EvrakKayitTarihi,
    h.ehMekan AS MekanID,
    CASE 
        WHEN h.ehTip = 99 THEN 'DEVIR'
        WHEN h.ehAdetN > 0 THEN 'ALIŞ'
        WHEN h.ehAdetN < 0 THEN 'SATIŞ'
        ELSE 'DİĞER'
    END AS HareketTuru,
    h.ehTip AS HareketTipi,
    h.ehAdetN AS Miktar,
    h.ehMlyt AS Maliyet,
    h.ehMlyt / NULLIF(ABS(h.ehAdetN), 0) AS BirimMaliyet
FROM DerinSISBkm.dbo.irsHrk h
WHERE h.ehstkID = @testStkID
  AND h.ehTrhS BETWEEN '31.05.2021' AND '31.12.2021'
ORDER BY h.ehTrhS, h.hrkID;

PRINT '';
PRINT '';

-- =============================================================
-- 9. TEST SONUÇ ÖZETİ
-- =============================================================
PRINT '========================================';
PRINT 'TEST SONUÇ ÖZETİ';
PRINT '========================================';

DECLARE @devirVar BIT = 0;
DECLARE @alisVar BIT = 0;
DECLARE @satisVar BIT = 0;

IF EXISTS (SELECT 1 FROM bkm.fifo_ErpDevirFiyatlari WHERE stkID = @testStkID AND satinalmaSarti = @satinalmaSarti)
    SET @devirVar = 1;

IF EXISTS (SELECT 1 FROM DerinSISBkm.dbo.irsHrk WHERE ehstkID = @testStkID AND ehTrhS BETWEEN '01.06.2021' AND '31.12.2021' AND ehTip <> 99 AND ehAdetN > 0)
    SET @alisVar = 1;

IF EXISTS (SELECT 1 FROM DerinSISBkm.dbo.irsHrk WHERE ehstkID = @testStkID AND ehTrhS BETWEEN '01.06.2021' AND '31.12.2021' AND ehTip <> 99 AND ehAdetN < 0)
    SET @satisVar = 1;

PRINT 'Ürün ID: ' + CAST(@testStkID AS VARCHAR(10));
PRINT 'Satınalma Şartı: ' + @satinalmaSarti;
PRINT '';
PRINT 'ERP Devir Fiyatı: ' + CASE WHEN @devirVar = 1 THEN 'VAR ✓' ELSE 'YOK ✗' END;
PRINT 'Alış Hareketleri: ' + CASE WHEN @alisVar = 1 THEN 'VAR ✓' ELSE 'YOK ✗' END;
PRINT 'Satış Hareketleri: ' + CASE WHEN @satisVar = 1 THEN 'VAR ✓' ELSE 'YOK ✗' END;
PRINT '';

IF @devirVar = 1 AND @alisVar = 1 AND @satisVar = 1
BEGIN
    PRINT 'SONUÇ: Bu ürün TAM FIFO DÖNGÜSÜ testi için idealdir! ✓✓✓';
END
ELSE IF @devirVar = 1 AND @alisVar = 1
BEGIN
    PRINT 'SONUÇ: Bu ürün FIFO KATMAN EKLEME testi için uygundur! ✓✓';
END
ELSE IF @devirVar = 1
BEGIN
    PRINT 'SONUÇ: Bu ürün BASİT AÇILIŞ STOKU testi için uygundur! ✓';
END
ELSE
BEGIN
    PRINT 'SONUÇ: Bu ürün test için uygun değil! ✗';
END

PRINT '';
PRINT 'Analiz tamamlandı!';
GO
