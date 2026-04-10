/* =========================================================
   test_devir_stoku.sql
   31/12/2025 Devir Stoku Test Senaryosu (Ortak Maliyet)
   Mekanlar: 1, 4477, 4478 (mağazalar), 12 (merkez depo)
   ========================================================= */

USE BKMMaliyet;
GO

PRINT '=== 31/12/2025 DEVİR STOKU TEST SENARYOSU (ORTAK MALİYET) ===';
PRINT '';

-- Test parametreleri
DECLARE @EnvanterTarihi DATE = '2025-12-31';
DECLARE @BaslangicTarihi DATE = '2025-01-01';

PRINT 'Envanter Tarihi: ' + CONVERT(VARCHAR(10), @EnvanterTarihi, 104);
PRINT 'Maliyet Arama Başlangıcı: ' + CONVERT(VARCHAR(10), @BaslangicTarihi, 104);
PRINT 'Test Mekanları: 1, 4477, 4478, 12';
PRINT 'Yaklaşım: Ortak Maliyet Katmanı (Mekan Bağımsız)';
PRINT '';

-- Ortak maliyet katmanı oluştur (tek çağrı)
PRINT '--- ORTAK MALİYET KATMANI OLUŞTURMA ---';
EXEC dbo.sp_Fifo_AcilisStoklariniMaliyetlendir 
    @EnvanterTarihi = @EnvanterTarihi,
    @BaslangicTarihi = @BaslangicTarihi;

PRINT '';
PRINT '=== SONUÇLAR ===';

-- Toplam stok miktarları (mekan detaylı)
PRINT '';
PRINT '--- STOK MİKTARLARI (Mekan Detaylı) ---';
SELECT 
    MekanId,
    COUNT(*) AS StokKalemSayisi,
    SUM(StokMiktar) AS ToplamStokMiktar
FROM drn.GecmisStokMekan 
WHERE EnvanterTarihi = @EnvanterTarihi
  AND MekanId IN (1, 4477, 4478, 12)
  AND StokMiktar <> 0
GROUP BY MekanId
ORDER BY MekanId;

-- FIFO katmanları (ortak - mekan bağımsız) - Kademeli maliyet dağılımı
PRINT '';
PRINT '--- FIFO KATMANLARI (Kademeli Maliyet Dağılımı) ---';
SELECT 
    Durum AS MaliyetKaynagi,
    COUNT(*) AS KatmanSayisi,
    COUNT(DISTINCT StkId) AS StokKodSayisi,
    SUM(KalanMiktar) AS ToplamMiktar,
    SUM(KalanMiktar * BirimMaliyet) AS ToplamTutar,
    AVG(BirimMaliyet) AS OrtalamaBirimMaliyet,
    MIN(BirimMaliyet) AS MinBirimMaliyet,
    MAX(BirimMaliyet) AS MaxBirimMaliyet
FROM dbo.FifoKatman 
WHERE EnvanterTarihi = @EnvanterTarihi
GROUP BY Durum
ORDER BY 
    CASE Durum
        WHEN 'ACILIS_TERS_FIFO' THEN 1
        WHEN 'ACILIS_ILAVE_HESAP' THEN 2
        WHEN 'ACILIS_SON_CARE' THEN 3
        ELSE 4
    END;

-- Genel toplam
PRINT '';
PRINT '--- GENEL TOPLAM (Tüm Maliyet Kaynakları) ---';
SELECT 
    COUNT(*) AS ToplamKatmanSayisi,
    COUNT(DISTINCT StkId) AS ToplamStokKodSayisi,
    SUM(KalanMiktar) AS ToplamMiktar,
    SUM(KalanMiktar * BirimMaliyet) AS ToplamTutar,
    AVG(BirimMaliyet) AS OrtalamaBirimMaliyet
FROM dbo.FifoKatman 
WHERE EnvanterTarihi = @EnvanterTarihi;

-- Sorunlu stoklar (ortak)
PRINT '';
PRINT '--- SORUNLU STOKLAR (Ortak) ---';
SELECT 
    COUNT(*) AS SorunluStokSayisi,
    SUM(ToplamStokMiktar) AS SorunluToplamMiktar,
    SorunTipi
FROM dbo.FifoSorunluStoklar 
WHERE EnvanterTarihi = @EnvanterTarihi
GROUP BY SorunTipi;

-- Kademeli maliyet başarı oranları
PRINT '';
PRINT '--- KADEMELİ MALİYET BAŞARI ORANLARI ---';
;WITH MaliyetDagilim AS (
    SELECT 
        'FİZİKSEL STOK' AS Kategori,
        COUNT(DISTINCT StkId) AS StokKodSayisi,
        SUM(StokMiktar) AS ToplamMiktar,
        0 AS ToplamTutar
    FROM drn.GecmisStokMekan 
    WHERE EnvanterTarihi = @EnvanterTarihi
      AND MekanId IN (1, 4477, 4478, 12)
      AND StokMiktar > 0

    UNION ALL

    SELECT 
        'TERS FIFO (Fatura)' AS Kategori,
        COUNT(DISTINCT StkId) AS StokKodSayisi,
        SUM(KalanMiktar) AS ToplamMiktar,
        SUM(KalanMiktar * BirimMaliyet) AS ToplamTutar
    FROM dbo.FifoKatman 
    WHERE EnvanterTarihi = @EnvanterTarihi
      AND Durum = 'ACILIS_TERS_FIFO'

    UNION ALL

    SELECT 
        'İLAVE HESAPLAMA' AS Kategori,
        COUNT(DISTINCT StkId) AS StokKodSayisi,
        SUM(KalanMiktar) AS ToplamMiktar,
        SUM(KalanMiktar * BirimMaliyet) AS ToplamTutar
    FROM dbo.FifoKatman 
    WHERE EnvanterTarihi = @EnvanterTarihi
      AND Durum = 'ACILIS_ILAVE_HESAP'

    UNION ALL

    SELECT 
        'SON ÇARE MALİYET' AS Kategori,
        COUNT(DISTINCT StkId) AS StokKodSayisi,
        SUM(KalanMiktar) AS ToplamMiktar,
        SUM(KalanMiktar * BirimMaliyet) AS ToplamTutar
    FROM dbo.FifoKatman 
    WHERE EnvanterTarihi = @EnvanterTarihi
      AND Durum = 'ACILIS_SON_CARE'

    UNION ALL

    SELECT 
        'SORUNLU STOK' AS Kategori,
        COUNT(DISTINCT StkId) AS StokKodSayisi,
        SUM(ToplamStokMiktar) AS ToplamMiktar,
        0 AS ToplamTutar
    FROM dbo.FifoSorunluStoklar 
    WHERE EnvanterTarihi = @EnvanterTarihi
)
SELECT 
    Kategori,
    StokKodSayisi,
    ToplamMiktar,
    ToplamTutar,
    CASE 
        WHEN (SELECT SUM(StokMiktar) FROM drn.GecmisStokMekan WHERE EnvanterTarihi = @EnvanterTarihi AND MekanId IN (1, 4477, 4478, 12) AND StokMiktar > 0) > 0
        THEN CAST(ToplamMiktar * 100.0 / (SELECT SUM(StokMiktar) FROM drn.GecmisStokMekan WHERE EnvanterTarihi = @EnvanterTarihi AND MekanId IN (1, 4477, 4478, 12) AND StokMiktar > 0) AS DECIMAL(5,2))
        ELSE 0
    END AS YuzdeOrani
FROM MaliyetDagilim
ORDER BY 
    CASE Kategori
        WHEN 'FİZİKSEL STOK' THEN 1
        WHEN 'TERS FIFO (Fatura)' THEN 2
        WHEN 'İLAVE HESAPLAMA' THEN 3
        WHEN 'SON ÇARE MALİYET' THEN 4
        WHEN 'SORUNLU STOK' THEN 5
        ELSE 6
    END;

-- En yüksek maliyetli stoklar
PRINT '';
PRINT '--- EN YÜKSEK MALİYETLİ STOKLAR (İlk 10) ---';
SELECT TOP 10
    f.StkId,
    f.KalanMiktar,
    f.BirimMaliyet,
    f.KalanMiktar * f.BirimMaliyet AS ToplamTutar,
    f.GirisTarihi,
    f.BelgeNo
FROM dbo.FifoKatman f
WHERE f.EnvanterTarihi = @EnvanterTarihi
ORDER BY f.BirimMaliyet DESC;

PRINT '';
PRINT '=== TEST TAMAMLANDI ===';