-- =============================================================
-- ERP DEVİR ENTEGRASYONU TEST
-- =============================================================

USE BKMMaliyet;
GO

DECLARE @testStkID INT = 594124;
DECLARE @satinalmaSarti VARCHAR(50) = 'SART310521';

PRINT '========================================';
PRINT 'ERP DEVİR ENTEGRASYONU TEST';
PRINT '========================================';
PRINT '';

-- 1. fifo_ErpDevirFiyatlari tablosunda kayıt var mı?
PRINT '1. fifo_ErpDevirFiyatlari tablosunda kayıt kontrolü:';
SELECT 
    stkID,
    satinalmaSarti,
    miktar,
    birimMaliyet,
    toplamTutar,
    aciklama,
    kayitTarihi
FROM bkm.fifo_ErpDevirFiyatlari
WHERE stkID = @testStkID
  AND satinalmaSarti = @satinalmaSarti;

PRINT '';
PRINT '';

-- 2. Eğer yoksa, yükleyelim
IF NOT EXISTS (
    SELECT 1 FROM bkm.fifo_ErpDevirFiyatlari 
    WHERE stkID = @testStkID AND satinalmaSarti = @satinalmaSarti
)
BEGIN
    PRINT '2. Kayıt yok, ERP devirden yükleniyor...';
    PRINT '';
    
    -- ERP devir hareketlerinden hesapla
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
        'ERP devir - 31.05.2021' AS aciklama
    FROM DerinSISBkm.dbo.irsHrk
    WHERE ehstkID = @testStkID
      AND ehTip = 99
      AND ehTrhS = '31.05.2021'
      AND ehMekan IN (1, 12, 4477, 4478)
    GROUP BY ehstkID
    HAVING SUM(ehAdetN) > 0;
    
    PRINT 'Kayıt eklendi.';
    PRINT '';
    
    -- Kontrol
    SELECT 
        stkID,
        satinalmaSarti,
        miktar,
        birimMaliyet,
        toplamTutar,
        aciklama
    FROM bkm.fifo_ErpDevirFiyatlari
    WHERE stkID = @testStkID
      AND satinalmaSarti = @satinalmaSarti;
END
ELSE
BEGIN
    PRINT '2. Kayıt zaten var.';
END

PRINT '';
PRINT '';

-- 3. Şimdi açılış SP'sini çalıştır
PRINT '3. Açılış SP çalıştırılıyor...';
PRINT '';

-- Önce temizle
DELETE FROM bkm.fifo_StokMaliyetHavuzu WHERE stkID = @testStkID;

-- SP'yi çağır
EXEC bkm.sp_fifo_StokMaliyetAcilis 
    @envanterTarihi = '31.05.2021',
    @satinalmaSarti = @satinalmaSarti,
    @stkID = @testStkID;

PRINT '';
PRINT '4. Oluşan katmanlar:';
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
    durum
FROM bkm.fifo_StokMaliyetHavuzu
WHERE stkID = @testStkID
ORDER BY ID;

PRINT '';
PRINT 'Test tamamlandı!';
GO
