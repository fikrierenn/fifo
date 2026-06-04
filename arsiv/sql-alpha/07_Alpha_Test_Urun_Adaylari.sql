-- =============================================================
-- ALPHA TEST URUN ADAYLARI
-- Amac: Acilis + aylik + (gerekirse sentetik fallback) testleri icin
--       uygun urun adaylarini puanlayip listelemek
-- =============================================================
-- Cikti:
-- 1) Dengeli adaylar (acilis+alis+satis)
-- 2) Acilis fallback adayi (stok var, gecmis alis yok, devir fiyati var)
-- 3) Sentetik adayi (aylik satis, mevcut+alis karsilamiyor olabilir)
-- =============================================================

SET NOCOUNT ON;

DECLARE @envanterTarihi DATE = '2025-12-31';
DECLARE @yil INT = 2026;
DECLARE @ay INT = 1;
DECLARE @topN INT = 50;
DECLARE @alisGecmisBaslangic DATE = '2021-05-31'; -- acilis SP ile uyumlu tut

DECLARE @ayBas DATE = DATEFROMPARTS(@yil, @ay, 1);
DECLARE @ayBit DATE = EOMONTH(@ayBas);

PRINT 'Test urun adayi analizi basladi...';
PRINT 'Envanter Tarihi: ' + CONVERT(VARCHAR(10), @envanterTarihi, 120);
PRINT 'Aylik Donem    : ' + CONVERT(VARCHAR(10), @ayBas, 120) + ' - ' + CONVERT(VARCHAR(10), @ayBit, 120);
PRINT '';

IF OBJECT_ID('tempdb..#envanter', 'U') IS NOT NULL DROP TABLE #envanter;
IF OBJECT_ID('tempdb..#gecmisAlis', 'U') IS NOT NULL DROP TABLE #gecmisAlis;
IF OBJECT_ID('tempdb..#aylikAlis', 'U') IS NOT NULL DROP TABLE #aylikAlis;
IF OBJECT_ID('tempdb..#aylikSatis', 'U') IS NOT NULL DROP TABLE #aylikSatis;
IF OBJECT_ID('tempdb..#erpFiyat', 'U') IS NOT NULL DROP TABLE #erpFiyat;
IF OBJECT_ID('tempdb..#aday', 'U') IS NOT NULL DROP TABLE #aday;

-- 1) Envanter snapshot adaylari (acilis icin stok var mi)
SELECT
    h.ehstkID AS stkID,
    SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) AS envanterStok
INTO #envanter
FROM DerinSISBkm.dbo.irsHrk h WITH(NOLOCK)
WHERE h.ehTrhS <= DATEADD(DAY, 1, @envanterTarihi)
  AND h.ehAltDepo = 0
  AND h.ehMekan IN (1, 12, 4477, 4478)
GROUP BY h.ehstkID
HAVING SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) > 0;

CREATE INDEX IX_tmp_envanter_stkID ON #envanter(stkID);

-- 2) Acilis oncesi gecmis alis ozeti
SELECT
    a.ehStkID AS stkID,
    COUNT(*) AS satirSayisi,
    SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS toplamMiktar,
    SUM(CONVERT(DECIMAL(18,4),
        CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END
    )) AS toplamTutar,
    MAX(CAST(f.eTarihS AS DATE)) AS sonAlisTarihi
INTO #gecmisAlis
FROM DerinSISBkm.dbo.fatAyr a WITH(NOLOCK)
JOIN DerinSISBkm.dbo.fat f WITH(NOLOCK) ON f.eID = a.ehID
WHERE a.ehAdetN <> 0
  AND f.eTip IN (0, 2)
  AND f.eTarihS > CONVERT(smalldatetime, @alisGecmisBaslangic)
  AND f.eTarihS < DATEADD(DAY, 1, CONVERT(smalldatetime, @envanterTarihi))
GROUP BY a.ehStkID
HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;

CREATE INDEX IX_tmp_gecmisAlis_stkID ON #gecmisAlis(stkID);

-- 3) Aylik alis ozeti (ALIS katman testi icin)
SELECT
    a.ehStkID AS stkID,
    COUNT(*) AS satirSayisi,
    SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS toplamMiktar,
    SUM(CONVERT(DECIMAL(18,4),
        CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END
    )) AS toplamTutar
INTO #aylikAlis
FROM DerinSISBkm.dbo.fatAyr a WITH(NOLOCK)
JOIN DerinSISBkm.dbo.fat f WITH(NOLOCK) ON f.eID = a.ehID
WHERE a.ehAdetN <> 0
  AND f.eTip IN (0, 2)
  AND f.eTarihS >= CONVERT(smalldatetime, @ayBas)
  AND f.eTarihS < DATEADD(DAY, 1, CONVERT(smalldatetime, @ayBit))
GROUP BY a.ehStkID
HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;

CREATE INDEX IX_tmp_aylikAlis_stkID ON #aylikAlis(stkID);

-- 4) Aylik satis ozeti (FIFO cikis testi icin)
SELECT
    dt.ehStkID AS stkID,
    COUNT(*) AS satirSayisi,
    SUM(CONVERT(DECIMAL(18,4), dt.ehAdet)) AS netMiktar,
    COUNT(DISTINCT CAST(bs.eTarihS AS DATE)) AS gunSayisi
INTO #aylikSatis
FROM DerinSISBkm.dbo.irs bs WITH(NOLOCK)
JOIN DerinSISBkm.dbo.irsAyr dt WITH(NOLOCK) ON dt.ehID = bs.eID
WHERE bs.eTip IN (1,4,5,100,101)
  AND bs.eMekan IN (1, 12, 4477, 4478)
  AND bs.eTarihS >= CONVERT(smalldatetime, @ayBas)
  AND bs.eTarihS < DATEADD(DAY, 1, CONVERT(smalldatetime, @ayBit))
GROUP BY dt.ehStkID
HAVING SUM(CONVERT(DECIMAL(18,4), dt.ehAdet)) <> 0;

CREATE INDEX IX_tmp_aylikSatis_stkID ON #aylikSatis(stkID);

-- 5) ERP / sart fiyati var mi (fallback testi icin)
CREATE TABLE #erpFiyat (
    stkID INT NOT NULL PRIMARY KEY,
    fiyatSatirSayisi INT NOT NULL,
    sartSayisi INT NOT NULL,
    minBirimMaliyet DECIMAL(18,6) NULL,
    maxBirimMaliyet DECIMAL(18,6) NULL
);

IF OBJECT_ID('bkm.fifo_ErpDevirFiyatlari', 'U') IS NOT NULL
BEGIN
    INSERT INTO #erpFiyat (stkID, fiyatSatirSayisi, sartSayisi, minBirimMaliyet, maxBirimMaliyet)
    SELECT
        stkID,
        COUNT(*) AS fiyatSatirSayisi,
        COUNT(DISTINCT satinalmaSarti) AS sartSayisi,
        MIN(birimMaliyet) AS minBirimMaliyet,
        MAX(birimMaliyet) AS maxBirimMaliyet
    FROM bkm.fifo_ErpDevirFiyatlari
    GROUP BY stkID;
END

-- 6) Aday puanlama
;WITH UrunEvreni AS (
    SELECT stkID FROM #envanter
    UNION
    SELECT stkID FROM #gecmisAlis
    UNION
    SELECT stkID FROM #aylikAlis
    UNION
    SELECT stkID FROM #aylikSatis
),
Ozet AS (
    SELECT
        u.stkID,
        ISNULL(e.envanterStok, 0) AS envanterStok,
        ISNULL(ga.satirSayisi, 0) AS gecmisAlisSatir,
        ISNULL(ga.toplamMiktar, 0) AS gecmisAlisMiktar,
        ga.sonAlisTarihi,
        ISNULL(aa.satirSayisi, 0) AS aylikAlisSatir,
        ISNULL(aa.toplamMiktar, 0) AS aylikAlisMiktar,
        ISNULL(asat.satirSayisi, 0) AS aylikSatisSatir,
        ISNULL(asat.netMiktar, 0) AS aylikSatisNetMiktar,
        ISNULL(asat.gunSayisi, 0) AS aylikSatisGunSayisi,
        ISNULL(ef.fiyatSatirSayisi, 0) AS erpFiyatSatir,
        ISNULL(ef.sartSayisi, 0) AS erpSartSayisi,
        ef.minBirimMaliyet,
        ef.maxBirimMaliyet
    FROM UrunEvreni u
    LEFT JOIN #envanter e ON e.stkID = u.stkID
    LEFT JOIN #gecmisAlis ga ON ga.stkID = u.stkID
    LEFT JOIN #aylikAlis aa ON aa.stkID = u.stkID
    LEFT JOIN #aylikSatis asat ON asat.stkID = u.stkID
    LEFT JOIN #erpFiyat ef ON ef.stkID = u.stkID
),
Skor AS (
    SELECT
        o.*,
        CASE WHEN o.envanterStok > 0 THEN 1 ELSE 0 END AS k_acilisStok,
        CASE WHEN o.gecmisAlisSatir > 0 AND o.gecmisAlisMiktar > 0 THEN 1 ELSE 0 END AS k_gecmisAlis,
        CASE WHEN o.aylikAlisSatir > 0 AND o.aylikAlisMiktar > 0 THEN 1 ELSE 0 END AS k_aylikAlis,
        CASE WHEN o.aylikSatisSatir > 0 AND ABS(o.aylikSatisNetMiktar) > 0 THEN 1 ELSE 0 END AS k_aylikSatis,
        CASE WHEN o.erpFiyatSatir > 0 THEN 1 ELSE 0 END AS k_erpFiyat,
        CASE WHEN o.envanterStok > 0 AND o.gecmisAlisSatir = 0 AND o.erpFiyatSatir > 0 THEN 1 ELSE 0 END AS k_acilisFallbackAday,
        CASE WHEN o.aylikSatisSatir > 0
                  AND ABS(o.aylikSatisNetMiktar) > (CASE WHEN o.envanterStok > 0 THEN o.envanterStok ELSE 0 END)
                                             + (CASE WHEN o.aylikAlisMiktar > 0 THEN o.aylikAlisMiktar ELSE 0 END)
             THEN 1 ELSE 0 END AS k_sentetikAday
    FROM Ozet o
)
SELECT
    s.*,
    (
        s.k_acilisStok * 25 +
        s.k_gecmisAlis * 20 +
        s.k_aylikAlis * 20 +
        s.k_aylikSatis * 25 +
        s.k_erpFiyat * 10
    ) AS testSkoru
INTO #aday
FROM Skor s;

CREATE INDEX IX_tmp_aday_skor ON #aday(testSkoru DESC, stkID);

PRINT '1) DENGELI ADAYLAR (acilis + aylik alis + aylik satis)';
SELECT TOP (@topN)
    stkID,
    testSkoru,
    envanterStok,
    gecmisAlisSatir,
    gecmisAlisMiktar,
    sonAlisTarihi,
    aylikAlisSatir,
    aylikAlisMiktar,
    aylikSatisSatir,
    aylikSatisNetMiktar,
    aylikSatisGunSayisi,
    erpFiyatSatir,
    erpSartSayisi,
    k_acilisFallbackAday,
    k_sentetikAday
FROM #aday
WHERE k_acilisStok = 1
  AND k_gecmisAlis = 1
  AND k_aylikAlis = 1
  AND k_aylikSatis = 1
ORDER BY testSkoru DESC, ABS(aylikSatisNetMiktar) DESC, stkID;

PRINT '';
PRINT '2) ACILIS FALLBACK ADAYLARI (stok var + gecmis alis yok + ERP fiyat var)';
SELECT TOP (@topN)
    stkID,
    envanterStok,
    gecmisAlisSatir,
    erpFiyatSatir,
    erpSartSayisi,
    minBirimMaliyet,
    maxBirimMaliyet
FROM #aday
WHERE k_acilisFallbackAday = 1
ORDER BY envanterStok DESC, erpFiyatSatir DESC, stkID;

PRINT '';
PRINT '3) SENTETIK ADAYLARI (aylik satis > envanter+aylik alis tahmini)';
SELECT TOP (@topN)
    stkID,
    envanterStok,
    aylikAlisMiktar,
    aylikSatisNetMiktar,
    erpFiyatSatir,
    erpSartSayisi,
    minBirimMaliyet,
    maxBirimMaliyet
FROM #aday
WHERE k_sentetikAday = 1
ORDER BY ABS(aylikSatisNetMiktar) DESC, envanterStok ASC, stkID;

PRINT '';
PRINT '4) EN IYI TEK URUN ONERISI (genel smoke test icin)';
SELECT TOP (1)
    stkID,
    testSkoru,
    envanterStok,
    gecmisAlisSatir,
    aylikAlisSatir,
    aylikSatisSatir,
    aylikSatisGunSayisi,
    erpFiyatSatir,
    k_acilisFallbackAday,
    k_sentetikAday
FROM #aday
WHERE k_acilisStok = 1
  AND k_gecmisAlis = 1
  AND k_aylikAlis = 1
  AND k_aylikSatis = 1
ORDER BY testSkoru DESC, ABS(aylikSatisNetMiktar) DESC, stkID;
GO
