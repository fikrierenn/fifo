-- =============================================================
-- ÜRÜN 392 - BASİT TEST
-- =============================================================

PRINT '========================================'
PRINT 'ÜRÜN 392 - BASİT TEST'
PRINT '========================================'
PRINT ''

-- 1) Katmanlar
PRINT '1) KATMANLAR:'
SELECT 
    h.ID,
    h.girisTarihi,
    h.miktarKalan,
    h.birimMaliyet
FROM bkm.fifo_StokMaliyetHavuzu h
WHERE h.stkID = 392
  AND h.miktarKalan > 0
ORDER BY h.girisTarihi

-- 2) FIFO Prosedürünü Çalıştır
PRINT ''
PRINT '2) FIFO PROSEDÜRÜ ÇALIŞTIRILIYOR...'
EXEC bkm.sp_fifo_StokMaliyetFIFOCikis 
    @satisBaslangic = '2025-01-01',
    @satisBitis = '2025-11-27'

-- 3) Sonuçlar
PRINT ''
PRINT '3) FIFO SONUÇLARI:'
SELECT 
    c.hareketTarihi,
    c.hareketTipi,
    c.katmanID,
    c.katmanTarihi,
    c.miktar,
    c.birimMaliyet,
    c.cikisTutar
FROM bkm.fifo_StokMaliyetCikis c
WHERE c.stkID = 392
ORDER BY c.hareketTarihi, c.katmanTarihi

IF @@ROWCOUNT = 0
    PRINT 'UYARI: Hiç kayıt oluşmadı!'
ELSE
    PRINT 'BAŞARILI: Kayıtlar oluşturuldu'

-- 4) Sorunlu kayıtlar
PRINT ''
PRINT '4) SORUNLU KAYITLAR:'
SELECT * FROM bkm.fifo_StokMaliyetSorunlu WHERE stkID = 392

IF @@ROWCOUNT = 0
    PRINT 'Sorunlu kayıt yok'

PRINT ''
PRINT '========================================'
