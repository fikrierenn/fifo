-- =============================================================
-- TERS FİFO ANALİZ - ÜRÜN 594124
-- SP'leri çalıştırıp sonuçları kontrol edelim
-- =============================================================

USE BKMMaliyet;
GO

DECLARE @testStkID INT = 594124;
DECLARE @satinalmaSarti VARCHAR(50) = 'SART310521';

PRINT '========================================';
PRINT 'TERS FİFO ANALİZ - ÜRÜN: ' + CAST(@testStkID AS VARCHAR(10));
PRINT '========================================';
PRINT '';

-- =============================================================
-- ADIM 0: TEMİZLİK
-- =============================================================
PRINT '========================================';
PRINT 'ADIM 0: TEMİZLİK';
PRINT '========================================';
PRINT '';

DELETE FROM bkm.fifo_StokMaliyetHavuzu WHERE stkID = @testStkID;
DELETE FROM bkm.fifo_StokMaliyetCikis WHERE stkID = @testStkID;
DELETE FROM bkm.fifo_StokMaliyetSorunlu WHERE stkID = @testStkID;

PRINT 'Tablolar temizlendi.';
PRINT '';
PRINT '';

-- =============================================================
-- ADIM 1: AÇILIŞ KATMANI OLUŞTUR
-- =============================================================
PRINT '========================================';
PRINT 'ADIM 1: AÇILIŞ KATMANI OLUŞTUR';
PRINT '========================================';
PRINT '';

EXEC bkm.sp_fifo_StokMaliyetAcilis 
    @envanterTarihi = '31.05.2021',
    @satinalmaSarti = @satinalmaSarti,
    @stkID = @testStkID;

PRINT '';
PRINT '1.1 - Oluşan katmanlar:';
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
PRINT '';

-- =============================================================
-- ADIM 2: ALIŞ KATMANLARINI EKLE (TÜM ALIŞLAR)
-- =============================================================
PRINT '========================================';
PRINT 'ADIM 2: ALIŞ KATMANLARINI EKLE';
PRINT '========================================';
PRINT '';

-- SP'yi çağır (Haziran-Aralık 2021)
EXEC bkm.sp_fifo_StokMaliyetAlisKatman
    @baslangicTarihi = '01.06.2021',
    @bitisTarihi = '31.12.2021',
    @stkID = @testStkID;

PRINT 'Alış katmanları eklendi.';
PRINT '';
PRINT '2.1 - Güncel katmanlar (tüm alışlar sonrası):';
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
PRINT '';

-- =============================================================
-- ADIM 3: TÜM SATIŞLARI FİFO İLE MALİYETLENDİR
-- =============================================================
PRINT '========================================';
PRINT 'ADIM 3: TÜM SATIŞLARI FİFO İLE MALİYETLENDİR';
PRINT '========================================';
PRINT '';

-- SP'yi çağır (Haziran-Aralık 2021)
EXEC bkm.sp_fifo_StokMaliyetFIFOCikis
    @satisBaslangic = '01.06.2021',
    @satisBitis = '31.12.2021',
    @stkID = @testStkID;

PRINT 'Satışlar FIFO ile maliyetlendirildi.';
PRINT '';
PRINT '3.1 - Güncel katmanlar (tüm satışlar sonrası):';
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
PRINT '3.2 - Çıkış kayıtları özeti:';
SELECT 
    COUNT(*) AS ToplamCikisKaydi,
    SUM(miktar) AS ToplamCikisMiktar,
    SUM(cikisTutar) AS ToplamMaliyet,
    MIN(hareketTarihi) AS IlkCikis,
    MAX(hareketTarihi) AS SonCikis
FROM bkm.fifo_StokMaliyetCikis
WHERE stkID = @testStkID;

PRINT '';
PRINT '';

-- =============================================================
-- ÖZET
-- =============================================================
PRINT '========================================';
PRINT 'ÖZET';
PRINT '========================================';
PRINT '';

DECLARE @toplamKatman DECIMAL(18,4) = (SELECT SUM(miktarKalan) FROM bkm.fifo_StokMaliyetHavuzu WHERE stkID = @testStkID);
DECLARE @toplamCikis DECIMAL(18,4) = (SELECT SUM(miktar) FROM bkm.fifo_StokMaliyetCikis WHERE stkID = @testStkID);
DECLARE @toplamMaliyet DECIMAL(18,2) = (SELECT SUM(cikisTutar) FROM bkm.fifo_StokMaliyetCikis WHERE stkID = @testStkID);
DECLARE @katmanSayisi INT = (SELECT COUNT(*) FROM bkm.fifo_StokMaliyetHavuzu WHERE stkID = @testStkID);
DECLARE @cikisSayisi INT = (SELECT COUNT(*) FROM bkm.fifo_StokMaliyetCikis WHERE stkID = @testStkID);

PRINT 'Toplam Katman Sayısı: ' + CAST(@katmanSayisi AS VARCHAR(20));
PRINT 'Kalan Stok (Katmanlarda): ' + CAST(@toplamKatman AS VARCHAR(20));
PRINT '';
PRINT 'Toplam Çıkış Kaydı: ' + CAST(@cikisSayisi AS VARCHAR(20));
PRINT 'Toplam Çıkış Miktarı: ' + CAST(@toplamCikis AS VARCHAR(20));
PRINT 'Toplam Çıkış Maliyeti: ' + CAST(@toplamMaliyet AS VARCHAR(20));
PRINT '';
PRINT 'Analiz tamamlandı!';
GO
