USE BKMMaliyet;
GO

PRINT '6/6 - Raporlama view''lari olusturuluyor...';
GO

-- =============================================================
-- RAPORLAMA VIEW'LARI
-- =============================================================

-- Gunluk SMM Raporu
CREATE OR ALTER VIEW bkm.fifo_vw_GunlukSMM
AS
SELECT
    hareketTarihi,
    hareketMekanID,
    SUM(CASE WHEN hareketTipi = 'SATIS' THEN cikisTutar ELSE 0 END) AS satisMaliyeti,
    SUM(CASE WHEN hareketTipi = 'IADE' THEN cikisTutar ELSE 0 END) AS iadeMaliyeti,
    SUM(cikisTutar) AS netMaliyet,
    COUNT(*) AS satirSayisi
FROM bkm.fifo_StokMaliyetCikis
GROUP BY hareketTarihi, hareketMekanID;
GO

-- Urun Bazli SMM
CREATE OR ALTER VIEW bkm.fifo_vw_UrunBazliSMM
AS
SELECT
    stkID,
    hareketTarihi,
    hareketTipi,
    hareketMekanID,
    SUM(miktar) AS toplamMiktar,
    SUM(cikisTutar) AS toplamMaliyet,
    CASE WHEN SUM(miktar) <> 0 
         THEN SUM(cikisTutar) / SUM(miktar) 
         ELSE 0 
    END AS ortalamaBirimMaliyet
FROM bkm.fifo_StokMaliyetCikis
GROUP BY stkID, hareketTarihi, hareketTipi, hareketMekanID;
GO

-- Katman Durumu Raporu
CREATE OR ALTER VIEW bkm.fifo_vw_KatmanDurumu
AS
SELECT
    stkID,
    kaynakTip,
    girisTarihi,
    COUNT(*) AS katmanSayisi,
    SUM(miktarToplam) AS toplamMiktar,
    SUM(miktarKalan) AS kalanMiktar,
    SUM(miktarToplam - miktarKalan) AS tukenenMiktar,
    AVG(birimMaliyet) AS ortalamaBirimMaliyet,
    MIN(birimMaliyet) AS minBirimMaliyet,
    MAX(birimMaliyet) AS maxBirimMaliyet
FROM bkm.fifo_StokMaliyetHavuzu
GROUP BY stkID, kaynakTip, girisTarihi;
GO

-- Sorunlu Stoklar Azeti
CREATE OR ALTER VIEW bkm.fifo_vw_SorunluStoklar
AS
SELECT
    sorunTip,
    envanterTarihi,
    COUNT(DISTINCT stkID) AS urunSayisi,
    SUM(stokMiktar) AS toplamMiktar,
    MIN(kayitTarihi) AS ilkKayit,
    MAX(kayitTarihi) AS sonKayit
FROM bkm.fifo_StokMaliyetSorunlu
GROUP BY sorunTip, envanterTarihi;
GO

PRINT 'Tum raporlama view''lari olusturuldu';
GO

PRINT '';


PRINT '========================================';
PRINT 'Deployment tamamlandi!';
PRINT '========================================';
PRINT '';
PRINT 'Olusturulan Objeler:';
PRINT '- 7 Tablo (fifo_StokMaliyetHavuzu, fifo_StokEnvanter, fifo_StokMaliyetSorunlu, fifo_ErpDevirFiyatlari, fifo_StokMaliyetCikis, fifo_Calistirma, fifo_CalistirmaAdim)';
PRINT '- 12 Indeks';
PRINT '- 6 Prosedur (sp_fifo_CalistirmaAdim, sp_fifo_StokMaliyetAcilis, sp_fifo_StokMaliyetAlisKatman, sp_fifo_StokMaliyetFIFOCikis, sp_fifo_StokMaliyetCalistir, sp_fifo_AylikRutin)';
PRINT '- 4 View (fifo_vw_GunlukSMM, fifo_vw_UrunBazliSMM, fifo_vw_KatmanDurumu, fifo_vw_SorunluStoklar)';
PRINT '';
PRINT 'KULLANIM (2 asamali):';
PRINT '';
PRINT '1) TEK SEFERLIK - Acilis katmani (sistem kurulumunda veya yeni donem basinda):';
PRINT '   Script: 01_ACILIS_TEK_SEFERLIK.sql';
PRINT '   veya: EXEC bkm.sp_fifo_StokMaliyetAcilis @envanterTarihi = ''31.12.2025'', @satinalmaSarti = ''CIF'';';
PRINT '';
PRINT '2) AYLIK RUTIN - Her ay calistirilir:';
PRINT '   Script: 02_AYLIK_RUTIN.sql';
PRINT '   veya: EXEC bkm.sp_fifo_AylikRutin @yil = 2026, @ay = 1;';
PRINT '';
PRINT '-- Gunluk SMM raporu:';
PRINT 'SELECT * FROM bkm.fifo_vw_GunlukSMM WHERE hareketTarihi >= ''01.01.2026'';';
PRINT '';
PRINT '-- ERP Devir Fiyatlari yukle:';
PRINT 'INSERT bkm.fifo_ErpDevirFiyatlari(stkID, satinalmaSarti, birimMaliyet, miktar, toplamTutar, aciklama)';
PRINT 'VALUES (12345, ''CIF'', 15.50, 100, 1550.00, ''31.05.2021 devir evragi'');';
GO





