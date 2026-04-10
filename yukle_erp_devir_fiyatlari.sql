-- =============================================================
-- ERP DEVİR FİYATLARINI YÜKLE VE KATMAN OLUŞTUR
-- =============================================================

USE BKMMaliyet;
GO

DECLARE @satinalmaSarti VARCHAR(50) = 'SART310521';
DECLARE @envanterTarihi DATE = '31.05.2021';

PRINT '========================================';
PRINT 'ERP DEVİR FİYATLARINI YÜKLE';
PRINT '========================================';
PRINT '';

-- =============================================================
-- ADIM 1: ERP DEVIR FIYATLARINI YÜKLE
-- =============================================================
PRINT 'ADIM 1: ERP Devir Fiyatlarını Yükle';
PRINT '';

-- Önce temizle
DELETE FROM bkm.fifo_ErpDevirFiyatlari WHERE satinalmaSarti = @satinalmaSarti;

-- ERP'den yükle
INSERT INTO bkm.fifo_ErpDevirFiyatlari (stkID, satinalmaSarti, miktar, birimMaliyet, toplamTutar, aciklama)
SELECT 
    ehstkID AS stkID,
    @satinalmaSarti AS satinalmaSarti,
    SUM(ehAdetN) AS miktar,
    CASE 
        WHEN SUM(ehAdetN) > 0 THEN SUM(ehTutarN) / SUM(ehAdetN)
        ELSE 0
    END AS birimMaliyet,
    SUM(ehTutarN) AS toplamTutar,
    'ERP devir - ' + CONVERT(VARCHAR(10), @envanterTarihi, 104) AS aciklama
FROM DerinSISBkm.dbo.irsHrk
WHERE ehTip = 99
  AND ehTrhS = @envanterTarihi
  AND ehMekan IN (1, 12, 4477, 4478)  -- Sadece sistem içi mekanlar
GROUP BY ehstkID
HAVING SUM(ehAdetN) > 0;

DECLARE @yuklenenAdet INT = @@ROWCOUNT;

PRINT 'Yüklenen ürün sayısı: ' + CAST(@yuklenenAdet AS VARCHAR(10));
PRINT '';

-- Kontrol
SELECT TOP 10
    stkID,
    satinalmaSarti,
    miktar,
    birimMaliyet,
    toplamTutar,
    aciklama
FROM bkm.fifo_ErpDevirFiyatlari
WHERE satinalmaSarti = @satinalmaSarti
ORDER BY stkID;

PRINT '';
PRINT '';

-- =============================================================
-- ADIM 2: AÇILIŞ KATMANLARINI OLUŞTUR
-- =============================================================
PRINT 'ADIM 2: Açılış Katmanlarını Oluştur';
PRINT '';

-- Önce temizle
DELETE FROM bkm.fifo_StokMaliyetHavuzu 
WHERE kaynakTip = 'ACILIS' 
  AND girisTarihi = @envanterTarihi;

-- ERP devir fiyatlarından katman oluştur
INSERT INTO bkm.fifo_StokMaliyetHavuzu
    (stkID, girisTarihi, kaynakTip, belgeNo, belgeTarihi, firmaID,
     miktarToplam, miktarKalan, birimMaliyet, durum)
SELECT
    stkID,
    @envanterTarihi AS girisTarihi,
    'ACILIS' AS kaynakTip,
    'ERP_' + satinalmaSarti AS belgeNo,
    @envanterTarihi AS belgeTarihi,
    NULL AS firmaID,
    miktar AS miktarToplam,
    miktar AS miktarKalan,
    birimMaliyet,
    'NORMAL' AS durum
FROM bkm.fifo_ErpDevirFiyatlari
WHERE satinalmaSarti = @satinalmaSarti
  AND miktar > 0
  AND birimMaliyet > 0;

DECLARE @katmanAdet INT = @@ROWCOUNT;

PRINT 'Oluşturulan katman sayısı: ' + CAST(@katmanAdet AS VARCHAR(10));
PRINT '';

-- Kontrol
SELECT TOP 10
    ID AS KatmanID,
    stkID,
    girisTarihi,
    kaynakTip,
    belgeNo,
    miktarToplam,
    miktarKalan,
    birimMaliyet,
    miktarKalan * birimMaliyet AS ToplamMaliyet,
    durum
FROM bkm.fifo_StokMaliyetHavuzu
WHERE kaynakTip = 'ACILIS'
  AND girisTarihi = @envanterTarihi
ORDER BY stkID;

PRINT '';
PRINT '';

-- =============================================================
-- ÖZET
-- =============================================================
PRINT '========================================';
PRINT 'ÖZET';
PRINT '========================================';
PRINT '';

DECLARE @toplamMiktar DECIMAL(18,4) = (
    SELECT SUM(miktarKalan) 
    FROM bkm.fifo_StokMaliyetHavuzu 
    WHERE kaynakTip = 'ACILIS' AND girisTarihi = @envanterTarihi
);

DECLARE @toplamTutar DECIMAL(18,2) = (
    SELECT SUM(miktarKalan * birimMaliyet) 
    FROM bkm.fifo_StokMaliyetHavuzu 
    WHERE kaynakTip = 'ACILIS' AND girisTarihi = @envanterTarihi
);

PRINT 'Satınalma Şartı: ' + @satinalmaSarti;
PRINT 'Envanter Tarihi: ' + CONVERT(VARCHAR(10), @envanterTarihi, 104);
PRINT '';
PRINT 'Yüklenen Ürün Sayısı: ' + CAST(@yuklenenAdet AS VARCHAR(10));
PRINT 'Oluşturulan Katman Sayısı: ' + CAST(@katmanAdet AS VARCHAR(10));
PRINT 'Toplam Miktar: ' + CAST(@toplamMiktar AS VARCHAR(20));
PRINT 'Toplam Tutar: ' + CAST(@toplamTutar AS VARCHAR(20));
PRINT '';
PRINT 'İşlem tamamlandı!';
GO
