-- =============================================================
-- TEST: Urun senaryosu tespiti (alis / satis / transfer)
-- Amaç: 10/20/50 urun secip senaryo bazli test yapmak
-- =============================================================

SET NOCOUNT ON;

-- 1) Parametreler
DECLARE @baslangicTarihi DATE = '2025-01-01';
DECLARE @bitisTarihi DATE = '2025-11-27';
DECLARE @ornekSayisi INT = 10; -- 10/20/50 yapabilirsiniz
DECLARE @stokZorunlu BIT = 1; -- 1: sadece stogu olan urunler
DECLARE @merkezDahil BIT = 1; -- 1: merkez depo da dahil edilir

-- Test edilecek mekanlar (subeler)
DECLARE @Mekan TABLE (mekanID INT PRIMARY KEY);
INSERT INTO @Mekan (mekanID) VALUES (1),(4477),(4478);

-- Merkez depo mekanlari (opsiyonel)
DECLARE @MerkezMekan TABLE (mekanID INT PRIMARY KEY);
 INSERT INTO @MerkezMekan (mekanID) VALUES (12);

IF @merkezDahil = 1
BEGIN
    INSERT INTO @Mekan (mekanID)
    SELECT m.mekanID
    FROM @MerkezMekan m
    WHERE NOT EXISTS (SELECT 1 FROM @Mekan x WHERE x.mekanID = m.mekanID);
END

-- 2) Hareket tipleri (referans)
-- 0  Alis
-- 1  Satis
-- 2  Alis Iade
-- 3  Satis Iade
-- 4  Magaza Satis
-- 5  Magaza Satis Iade
-- 6  Hizmet
-- 7  Gider
-- 8  Magaza Magaza
-- 9  Magaza Depo
-- 10 Yerel Alim
-- 11 Depo Depo
-- 12 Alis Magaza Iade
-- 13 Depo Magaza
-- 14 Iade ve Imha
-- 15 Ornek Alimi
-- 16 Stok EKLE
-- 17 Merkezi Duzeltme
-- 18 Magaza Ici Islemler
-- 86 Urun Degisim
-- 88 Diger Giris
-- 89 Diger Cikis
-- 90 Urun SAY
-- 91 Rakipten Urun Alis
-- 92 Bos Paket Cikisi
-- 93 Musteriden Bozuk Iade
-- 94 SKT Nedeniyle
-- 95 Donusum
-- 96 Bozuk Urun
-- 97 Devir
-- 98 Sirket Ici Kullanim
-- 99 Sayim
-- 100 POS Satis
-- 101 POS Satis Iade

-- 3) Tip gruplari (ihtiyaca gore guncelleyin)
DECLARE @TipAlis TABLE (tipID INT PRIMARY KEY);
INSERT INTO @TipAlis (tipID) VALUES
    (0),(10),(15),(91);

DECLARE @TipSatis TABLE (tipID INT PRIMARY KEY);
INSERT INTO @TipSatis (tipID) VALUES
    (1),(4),(5),(100),(101);

DECLARE @TipTransfer TABLE (tipID INT PRIMARY KEY);
INSERT INTO @TipTransfer (tipID) VALUES
    (8),(9),(11),(13);

-- 4) Hareketleri topla
IF OBJECT_ID('tempdb..#hareket', 'U') IS NOT NULL DROP TABLE #hareket;

SELECT
    dt.ehStkID AS stkID,
    i.eTip,
    i.eMekan,
    hareketTarihi = CAST(COALESCE(i.eTarihS, i.eTarih) AS DATE),
    toplamMiktar = SUM(CONVERT(DECIMAL(18,4), dt.ehAdet))
INTO #hareket
FROM dbo.irs i WITH (NOLOCK)
JOIN dbo.irsAyr dt WITH (NOLOCK) ON dt.ehID = i.eID
JOIN @Mekan m ON m.mekanID = i.eMekan
WHERE COALESCE(i.eTarihS, i.eTarih) >= @baslangicTarihi
  AND COALESCE(i.eTarihS, i.eTarih) < DATEADD(DAY, 1, @bitisTarihi)
GROUP BY
    dt.ehStkID,
    i.eTip,
    i.eMekan,
    CAST(COALESCE(i.eTarihS, i.eTarih) AS DATE);

-- 4.a) Stok snapshot (sube bazli, mevcut stok)
IF OBJECT_ID('tempdb..#stoklar', 'U') IS NOT NULL DROP TABLE #stoklar;

SELECT
    d.ehstkID AS stkID,
    SUM(CONVERT(DECIMAL(18,4), d.stok)) AS stokMiktar
INTO #stoklar
FROM dbo.stokSonAltDepo_vw d
JOIN @Mekan m ON m.mekanID = d.ehMekan
WHERE d.ehAltDepo = 0
  AND d.stok > 0
GROUP BY d.ehstkID;

-- 5) Ozet
IF OBJECT_ID('tempdb..#ozet', 'U') IS NOT NULL DROP TABLE #ozet;

SELECT
    h.stkID,
    alis_var = MAX(CASE WHEN ta.tipID IS NOT NULL THEN 1 ELSE 0 END),
    satis_var = MAX(CASE WHEN ts.tipID IS NOT NULL THEN 1 ELSE 0 END),
    transfer_var = MAX(CASE WHEN tt.tipID IS NOT NULL THEN 1 ELSE 0 END),
    alis_satir = SUM(CASE WHEN ta.tipID IS NOT NULL THEN 1 ELSE 0 END),
    satis_satir = SUM(CASE WHEN ts.tipID IS NOT NULL THEN 1 ELSE 0 END),
    transfer_satir = SUM(CASE WHEN tt.tipID IS NOT NULL THEN 1 ELSE 0 END),
    stok_var = MAX(CASE WHEN s.stkID IS NOT NULL THEN 1 ELSE 0 END),
    stokMiktar = MAX(COALESCE(s.stokMiktar, 0))
INTO #ozet
FROM #hareket h
LEFT JOIN @TipAlis ta ON ta.tipID = h.eTip
LEFT JOIN @TipSatis ts ON ts.tipID = h.eTip
LEFT JOIN @TipTransfer tt ON tt.tipID = h.eTip
LEFT JOIN #stoklar s ON s.stkID = h.stkID
WHERE @stokZorunlu = 0 OR s.stkID IS NOT NULL
GROUP BY h.stkID;

-- 6) Merkez depoda alis var mi? (opsiyonel)
IF OBJECT_ID('tempdb..#merkezAlis', 'U') IS NOT NULL DROP TABLE #merkezAlis;

SELECT DISTINCT
    dt.ehStkID AS stkID
INTO #merkezAlis
FROM dbo.irs i WITH (NOLOCK)
JOIN dbo.irsAyr dt WITH (NOLOCK) ON dt.ehID = i.eID
JOIN @MerkezMekan m ON m.mekanID = i.eMekan
JOIN @TipAlis ta ON ta.tipID = i.eTip
WHERE COALESCE(i.eTarihS, i.eTarih) >= @baslangicTarihi
  AND COALESCE(i.eTarihS, i.eTarih) < DATEADD(DAY, 1, @bitisTarihi)
;

-- 7) Senaryo sayilari
SELECT
    SUM(CASE WHEN alis_var = 1 AND satis_var = 1 THEN 1 ELSE 0 END) AS senaryo_alis_satis,
    SUM(CASE WHEN transfer_var = 1 AND alis_var = 0 AND satis_var = 1 THEN 1 ELSE 0 END) AS senaryo_transfer_satis_alis_yok,
    SUM(CASE WHEN transfer_var = 1 AND alis_var = 0 AND satis_var = 0 THEN 1 ELSE 0 END) AS senaryo_transfer_only,
    SUM(CASE WHEN alis_var = 1 AND satis_var = 0 THEN 1 ELSE 0 END) AS senaryo_alis_only,
    SUM(CASE WHEN alis_var = 0 AND satis_var = 1 AND transfer_var = 0 THEN 1 ELSE 0 END) AS senaryo_satis_only
FROM #ozet;

-- 8) Ornek urun listeleri
SELECT TOP (@ornekSayisi)
    'ALIS_SATIS' AS senaryo,
    o.stkID
FROM #ozet o
WHERE o.alis_var = 1 AND o.satis_var = 1
ORDER BY NEWID();

SELECT TOP (@ornekSayisi)
    'TRANSFER_SATIS_ALIS_YOK' AS senaryo,
    o.stkID
FROM #ozet o
WHERE o.transfer_var = 1 AND o.alis_var = 0 AND o.satis_var = 1
ORDER BY NEWID();

SELECT TOP (@ornekSayisi)
    'TRANSFER_ONLY' AS senaryo,
    o.stkID
FROM #ozet o
WHERE o.transfer_var = 1 AND o.alis_var = 0 AND o.satis_var = 0
ORDER BY NEWID();

SELECT TOP (@ornekSayisi)
    'ALIS_ONLY' AS senaryo,
    o.stkID
FROM #ozet o
WHERE o.alis_var = 1 AND o.satis_var = 0
ORDER BY NEWID();

SELECT TOP (@ornekSayisi)
    'SATIS_ONLY' AS senaryo,
    o.stkID
FROM #ozet o
WHERE o.alis_var = 0 AND o.satis_var = 1 AND o.transfer_var = 0
ORDER BY NEWID();

SELECT TOP (@ornekSayisi)
    'TRANSFER_SATIS_ALIS_YOK_MERKEZ_ALIS_VAR' AS senaryo,
    o.stkID
FROM #ozet o
JOIN #merkezAlis m ON m.stkID = o.stkID
WHERE o.transfer_var = 1 AND o.alis_var = 0 AND o.satis_var = 1
ORDER BY NEWID();
