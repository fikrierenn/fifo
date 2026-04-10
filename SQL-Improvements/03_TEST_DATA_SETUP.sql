-- =============================================================
-- FIFO SISTEMI - TEST VERI SETUP (REAL DATA)
-- Versiyon: 2.0
-- Tarih: 2025-01-19
-- Amac: 31.12.2025 acilis + 01.01.2026-31.01.2026 isletme senaryosu
-- NOT: Maliyetler mekan bagimsiz, tum subeler icin ortak
-- =============================================================
-- UYARI: Sprint 1 + Sprint 2 uygulandiktan sonra calistirin!
-- Bu script GERCEK veri ile calisir ve manual dummy veri eklemez.
-- =============================================================

SET NOCOUNT ON;
SET DATEFORMAT dmy;

PRINT '=============================================================';
PRINT 'FIFO TEST VERI SETUP - REAL DATA (MEKAN BAGIMSIZ)';
PRINT '=============================================================';
PRINT '';

DECLARE @envanterTarihi DATE = '31.12.2025';
DECLARE @alisBaslangic DATE = '01.01.2026';
DECLARE @alisBitis DATE = '31.01.2026';
DECLARE @satisBaslangic DATE = '01.01.2026';
DECLARE @satisBitis DATE = '31.01.2026';
DECLARE @satinalmaSarti VARCHAR(50) = 'YIL_SONU_2025_TEST';

PRINT 'Parametreler:';
PRINT '- Envanter Tarihi: ' + CONVERT(VARCHAR(10), @envanterTarihi, 104);
PRINT '- Alis Araligi: ' + CONVERT(VARCHAR(10), @alisBaslangic, 104) + ' - ' + CONVERT(VARCHAR(10), @alisBitis, 104);
PRINT '- Satis Araligi: ' + CONVERT(VARCHAR(10), @satisBaslangic, 104) + ' - ' + CONVERT(VARCHAR(10), @satisBitis, 104);
PRINT '- Satinalma Sarti: ' + @satinalmaSarti;
PRINT '';

-- =============================================================
-- FAZE 0: COK HAREKETLI URUNLERI SEC
-- =============================================================

DECLARE @topUrunCount INT = 5;

IF OBJECT_ID('tempdb..#topUrun', 'U') IS NOT NULL DROP TABLE #topUrun;

;WITH Satis AS (
    SELECT
        ia.ehStkID AS stkID,
        COUNT(*) AS satisHareket,
        SUM(ABS(ia.ehAdet)) AS satisMiktar
    FROM DerinSISBkm.dbo.irs i
    JOIN DerinSISBkm.dbo.irsAyr ia ON ia.ehID = i.eID
    WHERE i.eTip IN (1, 4, 5, 100, 101)
      AND i.eTarihS >= CONVERT(smalldatetime, @satisBaslangic)
      AND i.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @satisBitis))
      AND i.eMekan IN (1, 12, 4477, 4478)
    GROUP BY ia.ehStkID
),
Alis AS (
    SELECT
        ia.ehStkID AS stkID,
        COUNT(*) AS alisHareket,
        SUM(ABS(ia.ehAdet)) AS alisMiktar
    FROM DerinSISBkm.dbo.irs i
    JOIN DerinSISBkm.dbo.irsAyr ia ON ia.ehID = i.eID
    WHERE i.eTip IN (2, 0, 10, 3, 6, 102, 103)
      AND i.eTarih >  CONVERT(smalldatetime, @alisBaslangic)
      AND i.eTarih <  DATEADD(DAY, 1, CONVERT(smalldatetime, @alisBitis))
      AND i.eMekan IN (1, 12, 4477, 4478)
    GROUP BY ia.ehStkID
),
Birlesik AS (
    SELECT
        s.stkID,
        s.satisHareket,
        s.satisMiktar,
        a.alisHareket,
        a.alisMiktar,
        (s.satisHareket + a.alisHareket) AS hareketSayisi,
        (s.satisMiktar + a.alisMiktar) AS toplamMiktar
    FROM Satis s
    JOIN Alis a ON a.stkID = s.stkID
)
SELECT TOP (@topUrunCount)
    stkID,
    hareketSayisi,
    toplamMiktar,
    satisHareket,
    alisHareket,
    satisMiktar,
    alisMiktar
INTO #topUrun
FROM Birlesik
ORDER BY hareketSayisi DESC, toplamMiktar DESC;

IF NOT EXISTS (SELECT 1 FROM #topUrun)
BEGIN
    RAISERROR('Hedef urun bulunamadi. Tarih araligini kontrol edin.', 16, 1);
    RETURN;
END

PRINT 'Secilen urunler (en hareketli):';
SELECT * FROM #topUrun ORDER BY hareketSayisi DESC, toplamMiktar DESC;
PRINT '';

-- =============================================================
-- FAZE 1: SADECE SECILI URUNLER ICIN TEMIZLIK
-- =============================================================

PRINT 'FAZE 1: Secilen urunler icin temizlik yapiliyor.';
PRINT '';

DELETE c
FROM bkm.fifo_StokMaliyetCikis c
WHERE c.hareketTarihi >= @satisBaslangic
  AND c.hareketTarihi <= @satisBitis
  AND EXISTS (SELECT 1 FROM #topUrun t WHERE t.stkID = c.stkID);

DELETE h
FROM bkm.fifo_StokMaliyetHavuzu h
WHERE h.girisTarihi >= @alisBaslangic
  AND h.girisTarihi <= @alisBitis
  AND EXISTS (SELECT 1 FROM #topUrun t WHERE t.stkID = h.stkID);

DELETE h
FROM bkm.fifo_StokMaliyetHavuzu h
WHERE h.girisTarihi = @envanterTarihi
  AND h.kaynakTip IN ('ACILIS', 'ACILIS_TAMAMLA', 'TAMAMLAMA', 'MERKEZ_TAMAMLAMA', 'SART_TAMAMLAMA', 'AYLIK_DEVIR')
  AND EXISTS (SELECT 1 FROM #topUrun t WHERE t.stkID = h.stkID);

DELETE s
FROM bkm.fifo_StokMaliyetSorunlu s
WHERE s.envanterTarihi IN (@envanterTarihi, @satisBitis)
  AND EXISTS (SELECT 1 FROM #topUrun t WHERE t.stkID = s.stkID);

DELETE e
FROM bkm.fifo_StokEnvanter e
WHERE e.envanterTarihi = @envanterTarihi
  AND EXISTS (SELECT 1 FROM #topUrun t WHERE t.stkID = e.stkID);

PRINT '   OK: Temizlik tamamlandi.';
PRINT '';

-- =============================================================
-- FAZE 2: ERP DEVIR FIYATLARI (31.12.2025) - MEKAN BAGIMSIZ
-- =============================================================

PRINT 'FAZE 2: ERP Devir Fiyatlari Yukleniyor (31.12.2025 - MEKAN BAGIMSIZ)...';
PRINT '';

MERGE bkm.fifo_ErpDevirFiyatlari AS target
USING (
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
      AND ehMekan IN (1, 12, 4477, 4478)
      AND ehstkID IN (SELECT stkID FROM #topUrun)
    GROUP BY ehstkID
    HAVING SUM(ehAdetN) > 0
) AS source
ON target.stkID = source.stkID AND target.satinalmaSarti = source.satinalmaSarti
WHEN MATCHED THEN
    UPDATE SET
        target.birimMaliyet = source.birimMaliyet,
        target.miktar = source.miktar,
        target.toplamTutar = source.toplamTutar,
        target.aciklama = source.aciklama
WHEN NOT MATCHED THEN
    INSERT (stkID, satinalmaSarti, birimMaliyet, miktar, toplamTutar, aciklama)
    VALUES (source.stkID, source.satinalmaSarti, source.birimMaliyet, source.miktar, source.toplamTutar, source.aciklama);

PRINT '   OK: ERP devir fiyatlari yuklendi.';
PRINT '';

-- =============================================================
-- FAZE 2B: MEKAN BAZLI ENVANTER KONTROLU (31.12.2025)
-- =============================================================

PRINT 'FAZE 2B: Mekan Bazli Envanter Kontrolu (1, 4477, 4478 magaza + 12 merkez)...';
PRINT '';

PRINT '   Mekan Envanter Ozeti:';
SELECT
    ehMekan AS mekanID,
    COUNT(DISTINCT ehstkID) AS [Urun Sayisi],
    SUM(ehAdetN) AS [Toplam Miktar]
FROM DerinSISBkm.dbo.irsHrk
WHERE ehTip = 99
  AND ehTrhS = @envanterTarihi
  AND ehMekan IN (1, 12, 4477, 4478)
  AND ehstkID IN (SELECT stkID FROM #topUrun)
GROUP BY ehMekan
ORDER BY ehMekan;

PRINT '';

-- =============================================================
-- FAZE 3: ACILIS STOKU SNAPSHOT (31.12.2025)
-- =============================================================

PRINT 'FAZE 3: Acilis Stoku (31.12.2025) Olusturuluyor...';
PRINT '';

DECLARE @curStkID INT;
DECLARE curAcilis CURSOR LOCAL FAST_FORWARD FOR
    SELECT stkID FROM #topUrun ORDER BY hareketSayisi DESC, toplamMiktar DESC;
OPEN curAcilis;
FETCH NEXT FROM curAcilis INTO @curStkID;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC bkm.sp_fifo_StokMaliyetAcilis
        @envanterTarihi = @envanterTarihi,
        @stkID = @curStkID,
        @satinalmaSarti = @satinalmaSarti;
    FETCH NEXT FROM curAcilis INTO @curStkID;
END
CLOSE curAcilis;
DEALLOCATE curAcilis;

PRINT '';
PRINT '   Acilis Katmanlari Ozeti:';
SELECT 
    'ACILIS' AS [Rapor],
    COUNT(*) AS [Katman Sayisi],
    SUM(miktarToplam) AS [Toplam Miktar],
    CAST(SUM(miktarToplam * birimMaliyet) AS NUMERIC(18,2)) AS [Toplam Tutar]
FROM bkm.fifo_StokMaliyetHavuzu
WHERE girisTarihi = @envanterTarihi
  AND kaynakTip IN ('ACILIS', 'ACILIS_TAMAMLA')
  AND EXISTS (SELECT 1 FROM #topUrun t WHERE t.stkID = bkm.fifo_StokMaliyetHavuzu.stkID);

PRINT '';
PRINT '   OK: Acilis katmanlari olusturuldu.';
PRINT '';

-- =============================================================
-- FAZE 4: OCAK ALISLARI (01.01.2026 ~ 31.01.2026)
-- =============================================================

PRINT 'FAZE 4: Ocak Alislari Ekleniyor (01.01.2026 ~ 31.01.2026)...';
PRINT '';

DECLARE curAlis CURSOR LOCAL FAST_FORWARD FOR
    SELECT stkID FROM #topUrun ORDER BY hareketSayisi DESC, toplamMiktar DESC;
OPEN curAlis;
FETCH NEXT FROM curAlis INTO @curStkID;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC bkm.sp_fifo_StokMaliyetAlisKatman
        @baslangicTarihi = @alisBaslangic,
        @bitisTarihi = @alisBitis,
        @stkID = @curStkID;
    FETCH NEXT FROM curAlis INTO @curStkID;
END
CLOSE curAlis;
DEALLOCATE curAlis;

PRINT '   OK: Alis katmanlari eklendi.';
PRINT '';

PRINT '   Ocak Alislari Ozeti:';
SELECT 
    COUNT(*) AS [Alis Sayisi],
    SUM(miktarToplam) AS [Toplam Miktar],
    CAST(SUM(miktarToplam * birimMaliyet) AS NUMERIC(18,2)) AS [Toplam Tutar]
FROM bkm.fifo_StokMaliyetHavuzu
WHERE kaynakTip = 'ALIS'
  AND girisTarihi >= @alisBaslangic
  AND girisTarihi <= @alisBitis
  AND EXISTS (SELECT 1 FROM #topUrun t WHERE t.stkID = bkm.fifo_StokMaliyetHavuzu.stkID);

PRINT '';
PRINT '   OK: Alislar eklendi.';
PRINT '';

-- =============================================================
-- FAZE 5: FIFO CIKISLARI (SATISLAR)
-- =============================================================

PRINT 'FAZE 5: FIFO Cikis Hesaplamasi Yapiliyor (01.01.2026 ~ 31.01.2026)...';
PRINT '';

DECLARE curCikis CURSOR LOCAL FAST_FORWARD FOR
    SELECT stkID FROM #topUrun ORDER BY hareketSayisi DESC, toplamMiktar DESC;
OPEN curCikis;
FETCH NEXT FROM curCikis INTO @curStkID;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC bkm.sp_fifo_StokMaliyetFIFOCikis
        @satisBaslangic = @satisBaslangic,
        @satisBitis = @satisBitis,
        @stkID = @curStkID;
    FETCH NEXT FROM curCikis INTO @curStkID;
END
CLOSE curCikis;
DEALLOCATE curCikis;

PRINT '';
PRINT '   OK: FIFO cikis hesaplamasi tamamlandi.';
PRINT '';

-- =============================================================
-- FAZE 6: TEST RAPORLARI
-- =============================================================

PRINT '=============================================================';
PRINT 'TEST RAPORLARI';
PRINT '=============================================================';
PRINT '';

PRINT 'RAPOR 1: ACILIS KATMANLARI OZETI';
PRINT '-------------------------------------------';
SELECT 
    stkID,
    COUNT(*) AS [Katman Sayisi],
    SUM(miktarToplam) AS [Toplam Miktar],
    CAST(AVG(birimMaliyet) AS NUMERIC(10,2)) AS [Ort. Birim Maliyet],
    CAST(SUM(miktarToplam * birimMaliyet) AS NUMERIC(18,2)) AS [Toplam Tutar]
FROM bkm.fifo_StokMaliyetHavuzu
WHERE girisTarihi = @envanterTarihi
  AND kaynakTip IN ('ACILIS', 'ACILIS_TAMAMLA')
  AND EXISTS (SELECT 1 FROM #topUrun t WHERE t.stkID = bkm.fifo_StokMaliyetHavuzu.stkID)
GROUP BY stkID
ORDER BY stkID;

PRINT '';

PRINT 'RAPOR 2: OCAK ALISLARI DETAY';
PRINT '-------------------------------------------';
SELECT 
    girisTarihi AS [Alis Tarihi],
    COUNT(*) AS [Fatura Sayisi],
    SUM(miktarToplam) AS [Toplam Miktar],
    CAST(MIN(birimMaliyet) AS NUMERIC(10,2)) AS [Min. Fiyat],
    CAST(MAX(birimMaliyet) AS NUMERIC(10,2)) AS [Max. Fiyat],
    CAST(AVG(birimMaliyet) AS NUMERIC(10,2)) AS [Ort. Fiyat],
    CAST(SUM(miktarToplam * birimMaliyet) AS NUMERIC(18,2)) AS [Tutar]
FROM bkm.fifo_StokMaliyetHavuzu
WHERE kaynakTip = 'ALIS'
  AND girisTarihi >= @alisBaslangic
  AND girisTarihi <= @alisBitis
  AND EXISTS (SELECT 1 FROM #topUrun t WHERE t.stkID = bkm.fifo_StokMaliyetHavuzu.stkID)
GROUP BY girisTarihi
ORDER BY girisTarihi;

PRINT '';

PRINT 'RAPOR 3: FIFO CIKISLAR OZETI';
PRINT '-------------------------------------------';
SELECT 
    hareketTarihi AS [Tarih],
    COUNT(*) AS [Satir Sayisi],
    SUM(CASE WHEN hareketTipi = 'SATIS' THEN miktar ELSE 0 END) AS [Satis Miktari],
    SUM(CASE WHEN hareketTipi = 'IADE' THEN miktar ELSE 0 END) AS [Iade Miktari],
    CAST(SUM(CASE WHEN hareketTipi = 'SATIS' THEN cikisTutar ELSE 0 END) AS NUMERIC(18,2)) AS [Satis Maliyeti],
    CAST(SUM(CASE WHEN hareketTipi = 'IADE' THEN cikisTutar ELSE 0 END) AS NUMERIC(18,2)) AS [Iade Maliyeti],
    CAST(SUM(cikisTutar) AS NUMERIC(18,2)) AS [Toplam Maliyet]
FROM bkm.fifo_StokMaliyetCikis
WHERE hareketTarihi >= @satisBaslangic
  AND hareketTarihi <= @satisBitis
  AND EXISTS (SELECT 1 FROM #topUrun t WHERE t.stkID = bkm.fifo_StokMaliyetCikis.stkID)
GROUP BY hareketTarihi
ORDER BY hareketTarihi;

PRINT '';

PRINT 'RAPOR 4: URUN BAZLI FIFO DETAY';
PRINT '-------------------------------------------';
SELECT 
    stkID,
    COUNT(*) AS [Satir Sayisi],
    COUNT(DISTINCT katmanID) AS [Kullanilan Katman Sayisi],
    SUM(miktar) AS [Toplam Satis Miktari],
    CAST(MIN(birimMaliyet) AS NUMERIC(10,2)) AS [Min. Maliyet],
    CAST(MAX(birimMaliyet) AS NUMERIC(10,2)) AS [Max. Maliyet],
    CAST(AVG(birimMaliyet) AS NUMERIC(10,2)) AS [Ort. Maliyet],
    CAST(SUM(cikisTutar) AS NUMERIC(18,2)) AS [Toplam Maliyet]
FROM bkm.fifo_StokMaliyetCikis
WHERE hareketTarihi >= @satisBaslangic
  AND hareketTarihi <= @satisBitis
  AND EXISTS (SELECT 1 FROM #topUrun t WHERE t.stkID = bkm.fifo_StokMaliyetCikis.stkID)
GROUP BY stkID
ORDER BY stkID;

PRINT '';

PRINT 'RAPOR 5: GUNLUK SMM OZETI';
PRINT '-------------------------------------------';
SELECT
    hareketTarihi,
    COUNT(DISTINCT stkID) AS urunSayisi,
    SUM(CASE WHEN hareketTipi = 'SATIS' THEN miktar ELSE 0 END) AS satisMiktari,
    SUM(CASE WHEN hareketTipi = 'IADE' THEN miktar ELSE 0 END) AS iadeMiktari,
    SUM(CASE WHEN hareketTipi = 'SATIS' THEN cikisTutar ELSE 0 END) AS satisMaliyeti,
    SUM(CASE WHEN hareketTipi = 'IADE' THEN cikisTutar ELSE 0 END) AS iadeMaliyeti,
    SUM(cikisTutar) AS toplamMaliyet,
    COUNT(*) AS satirSayisi
FROM bkm.fifo_StokMaliyetCikis
WHERE hareketTarihi >= @satisBaslangic
  AND hareketTarihi <= @satisBitis
  AND EXISTS (SELECT 1 FROM #topUrun t WHERE t.stkID = bkm.fifo_StokMaliyetCikis.stkID)
GROUP BY hareketTarihi
ORDER BY hareketTarihi;

PRINT '';

PRINT 'RAPOR 6: KATMAN TUKETIM KONTROL';
PRINT '-------------------------------------------';
SELECT 
    stkID,
    girisTarihi,
    kaynakTip,
    miktarToplam AS [Toplam Miktar],
    miktarKalan AS [Kalan Miktar],
    (miktarToplam - miktarKalan) AS [Tuketilen Miktar],
    CAST(CAST(100.0 * (miktarToplam - miktarKalan) AS NUMERIC(10,2)) / NULLIF(miktarToplam, 0) AS NUMERIC(5,1)) AS [Tuketim Yuzde]
FROM bkm.fifo_StokMaliyetHavuzu
WHERE girisTarihi >= @envanterTarihi
  AND EXISTS (SELECT 1 FROM #topUrun t WHERE t.stkID = bkm.fifo_StokMaliyetHavuzu.stkID)
ORDER BY stkID, girisTarihi;

PRINT '';

-- =============================================================
-- FAZE 7: MUHASEBE KONTROL
-- =============================================================

PRINT '=============================================================';
PRINT 'MUHASEBE KONTROL';
PRINT '=============================================================';
PRINT '';

PRINT 'KONTROL 1: SORUNLU STOKLAR';
PRINT '-------------------------------------------';
DECLARE @sorunluCount INT = (
    SELECT COUNT(*) FROM bkm.fifo_StokMaliyetSorunlu
    WHERE envanterTarihi IN (@envanterTarihi, @satisBitis)
      AND EXISTS (SELECT 1 FROM #topUrun t WHERE t.stkID = bkm.fifo_StokMaliyetSorunlu.stkID)
);

PRINT 'Sorunlu Kayit Sayisi: ' + CAST(@sorunluCount AS VARCHAR);

IF @sorunluCount = 0
    PRINT 'OK: Sorunlu stok yok - KONTROL GECTI'
ELSE
BEGIN
    PRINT 'UYARI: ' + CAST(@sorunluCount AS VARCHAR) + ' sorunlu kayit var - inceleme gerekli';
    SELECT * FROM bkm.fifo_StokMaliyetSorunlu
    WHERE envanterTarihi IN (@envanterTarihi, @satisBitis)
      AND EXISTS (SELECT 1 FROM #topUrun t WHERE t.stkID = bkm.fifo_StokMaliyetSorunlu.stkID);
END

PRINT '';

PRINT 'KONTROL 2: KATMAN UYUMSUZLUGU';
PRINT '-------------------------------------------';
DECLARE @uyumsuzlukCount INT = (
    SELECT COUNT(*) FROM bkm.vw_KatmanTuketimRaporu
    WHERE kontrolDurumu = 'UYUSMAZLIK'
      AND EXISTS (SELECT 1 FROM #topUrun t WHERE t.stkID = bkm.vw_KatmanTuketimRaporu.stkID)
);

PRINT 'Uyumsuzluk Sayisi: ' + CAST(@uyumsuzlukCount AS VARCHAR);

IF @uyumsuzlukCount = 0
    PRINT 'OK: Katman tuketimi tutarli - KONTROL GECTI'
ELSE
BEGIN
    PRINT 'UYARI: ' + CAST(@uyumsuzlukCount AS VARCHAR) + ' uyumsuzluk var - inceleme gerekli';
    SELECT * FROM bkm.vw_KatmanTuketimRaporu
    WHERE kontrolDurumu = 'UYUSMAZLIK'
      AND EXISTS (SELECT 1 FROM #topUrun t WHERE t.stkID = bkm.vw_KatmanTuketimRaporu.stkID);
END

PRINT '';

-- =============================================================
-- FAZE 8: MUHASEBE KAPANIS RAPORU
-- =============================================================

PRINT '=============================================================';
PRINT 'MUHASEBE KAPANIS RAPORU (MEKAN BAGIMSIZ/ORTAK MALIYET)';
PRINT '=============================================================';
PRINT '';

PRINT 'ACILIS:';
PRINT '------------------';
SELECT 
    CAST(SUM(miktarToplam) AS NUMERIC(18,2)) AS [Toplam Miktar],
    CAST(SUM(miktarToplam * birimMaliyet) AS NUMERIC(18,2)) AS [Toplam Tutar],
    CAST(SUM(miktarToplam * birimMaliyet) / NULLIF(SUM(miktarToplam), 0) AS NUMERIC(10,4)) AS [Ort. Birim Maliyet]
FROM bkm.fifo_StokMaliyetHavuzu
WHERE girisTarihi = @envanterTarihi
  AND kaynakTip IN ('ACILIS', 'ACILIS_TAMAMLA')
  AND EXISTS (SELECT 1 FROM #topUrun t WHERE t.stkID = bkm.fifo_StokMaliyetHavuzu.stkID);

PRINT '';
PRINT 'OCAK ALISLARI:';
PRINT '---------------';
SELECT 
    CAST(SUM(miktarToplam) AS NUMERIC(18,2)) AS [Toplam Miktar],
    CAST(SUM(miktarToplam * birimMaliyet) AS NUMERIC(18,2)) AS [Toplam Tutar],
    CAST(SUM(miktarToplam * birimMaliyet) / NULLIF(SUM(miktarToplam), 0) AS NUMERIC(10,4)) AS [Ort. Birim Maliyet]
FROM bkm.fifo_StokMaliyetHavuzu
WHERE kaynakTip = 'ALIS'
  AND girisTarihi >= @alisBaslangic
  AND girisTarihi <= @alisBitis
  AND EXISTS (SELECT 1 FROM #topUrun t WHERE t.stkID = bkm.fifo_StokMaliyetHavuzu.stkID);

PRINT '';
PRINT 'OCAK SATISLARI (MALIYET):';
PRINT '------------------------';
SELECT 
    CAST(SUM(miktar) AS NUMERIC(18,2)) AS [Toplam Miktar],
    CAST(SUM(cikisTutar) AS NUMERIC(18,2)) AS [Toplam Maliyet],
    CAST(SUM(cikisTutar) / NULLIF(SUM(miktar), 0) AS NUMERIC(10,4)) AS [Ort. Birim Maliyet]
FROM bkm.fifo_StokMaliyetCikis
WHERE hareketTarihi >= @satisBaslangic
  AND hareketTarihi <= @satisBitis
  AND hareketTipi = 'SATIS'
  AND EXISTS (SELECT 1 FROM #topUrun t WHERE t.stkID = bkm.fifo_StokMaliyetCikis.stkID);

PRINT '';
PRINT 'KAPANIS ENVANTERI (Kalan Katmanlar):';
PRINT '-----------------------------------';
SELECT 
    CAST(SUM(miktarKalan) AS NUMERIC(18,2)) AS [Toplam Miktar],
    CAST(SUM(miktarKalan * birimMaliyet) AS NUMERIC(18,2)) AS [Toplam Tutar],
    CAST(SUM(miktarKalan * birimMaliyet) / NULLIF(SUM(miktarKalan), 0) AS NUMERIC(10,4)) AS [Ort. Birim Maliyet]
FROM bkm.fifo_StokMaliyetHavuzu
WHERE miktarKalan > 0
  AND girisTarihi <= @satisBitis
  AND EXISTS (SELECT 1 FROM #topUrun t WHERE t.stkID = bkm.fifo_StokMaliyetHavuzu.stkID);

PRINT '';

-- =============================================================
-- SONLANDIRMA
-- =============================================================

PRINT '=============================================================';
PRINT 'TEST SETUP TAMAMLANDI (MEKAN BAGIMSIZ)';
PRINT '=============================================================';
PRINT '';
PRINT 'Bitis Zamani: ' + CONVERT(VARCHAR(19), GETDATE(), 121);
PRINT '';
PRINT 'Notlar:';
PRINT '- Maliyetler (birimMaliyet) MEKAN BAGIMSIZDIR';
PRINT '- Tum subeler (1, 4477, 4478) ORTAK/MERKEZ FIYATA calisir';
PRINT '- FIFO siralamasi: giris tarihi -> belge no -> ID';
PRINT '';
PRINT 'Sonraki Adimlar:';
PRINT '1. Raporlari muhasebede kontrol ettirin';
PRINT '2. Audit trail kontrolu (SELECT * FROM bkm.vw_SonDegisiklikler)';
PRINT '3. C# uygulamasini test edin';
PRINT '4. Go-Live planini yapin';
PRINT '=============================================================';
