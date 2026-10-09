USE BKMMaliyet;
GO
SET NOCOUNT ON;
GO

-- =============================================================
-- V2-02: FIFO Cikis "Ilk Fatura" Sira Dogrulama
-- BelgeTarihi + sayisal BelgeNo siralama dogrulama sorgu seti.
-- Bu script SALT OKUNUR analizdir, veri degistirmez.
-- Calistirmadan once @StkIdFiltre ve donem degiskenlerini ayarla.
-- =============================================================

DECLARE @StkIdFiltre INT        = NULL;   -- NULL = tum urunler
DECLARE @BaslangicTarihi DATE   = '2026-01-01';
DECLARE @BitisTarihi DATE       = '2026-01-31';

-- ============================================================
-- 1) BelgeNo FORMAT ANALIZI (FifoKatman)
-- Sayisal mi, alfanumerik mi? TRY_CONVERT(BIGINT) NULL donuyor mu?
-- ============================================================
PRINT '========================================';
PRINT '1) BelgeNo format analizi (FifoKatman)';
PRINT '========================================';

-- Ozet: kaynaktip bazli format dagilimi
SELECT
    KaynakTip,
    CASE
        WHEN TRY_CONVERT(BIGINT, BelgeNo) IS NOT NULL THEN 'SAYISAL'
        WHEN BelgeNo IS NULL                          THEN 'NULL'
        ELSE 'ALFANUMERIK'
    END AS BelgeNoFormat,
    COUNT(*) AS KatmanSayisi,
    MIN(BelgeNo) AS OrnekMin,
    MAX(BelgeNo) AS OrnekMax
FROM dbo.FifoKatman
WHERE (@StkIdFiltre IS NULL OR StkId = @StkIdFiltre)
GROUP BY
    KaynakTip,
    CASE
        WHEN TRY_CONVERT(BIGINT, BelgeNo) IS NOT NULL THEN 'SAYISAL'
        WHEN BelgeNo IS NULL                          THEN 'NULL'
        ELSE 'ALFANUMERIK'
    END
ORDER BY KaynakTip, BelgeNoFormat;

-- Alfanumerik belge numaralarinin ilk 20 ornegi (FIFO siralamasinda NULL)
PRINT '';
PRINT '--- Alfanumerik BelgeNo ornekleri (FIFO siralamada en sona gider) ---';
SELECT TOP 20
    KatmanId, KaynakTip, GirisTarihi, BelgeTarihi, BelgeNo,
    TRY_CONVERT(BIGINT, BelgeNo) AS BelgeNoNum_NULL_beklenir
FROM dbo.FifoKatman
WHERE TRY_CONVERT(BIGINT, BelgeNo) IS NULL
  AND BelgeNo IS NOT NULL
  AND (@StkIdFiltre IS NULL OR StkId = @StkIdFiltre)
ORDER BY KatmanId DESC;
GO

-- ============================================================
-- 2) FIFO SIRA DOGRULAMA: Gelecek katman kullanimi var mi?
-- Beklenti: KatmanTarihi <= HareketTarihi olmali.
-- ============================================================
DECLARE @StkIdFiltre INT        = NULL;
DECLARE @BaslangicTarihi DATE   = '2026-01-01';
DECLARE @BitisTarihi DATE       = '2026-01-31';

PRINT '';
PRINT '========================================';
PRINT '2) Gelecek katman kullanimi kontrolu';
PRINT '   Beklenti: KatmanTarihi <= HareketTarihi';
PRINT '========================================';

SELECT
    c.StkId,
    c.HareketTarihi,
    c.KatmanTarihi,
    c.KatmanBelgeNo,
    c.Miktar,
    c.BirimMaliyet,
    DATEDIFF(DAY, c.HareketTarihi, c.KatmanTarihi) AS GunFarki_GecerlisiNegativOlmali
FROM dbo.FifoCikisDetay c
WHERE c.HareketTarihi >= @BaslangicTarihi
  AND c.HareketTarihi <= @BitisTarihi
  AND c.KatmanTarihi  >  c.HareketTarihi      -- Hata: gelecek tarihli katman kullanilmis
  AND (@StkIdFiltre IS NULL OR c.StkId = @StkIdFiltre)
ORDER BY c.StkId, c.HareketTarihi, c.KatmanTarihi
OPTION (MAXDOP 4);

-- Ozet
PRINT '';
SELECT
    CASE WHEN COUNT(*) = 0 THEN 'OK: Gelecek katman yok' ELSE 'HATA: Gelecek katman var' END AS Sonuc,
    COUNT(*) AS HataSatirSayisi
FROM dbo.FifoCikisDetay c
WHERE c.HareketTarihi >= @BaslangicTarihi
  AND c.HareketTarihi <= @BitisTarihi
  AND c.KatmanTarihi  >  c.HareketTarihi
  AND (@StkIdFiltre IS NULL OR c.StkId = @StkIdFiltre);
GO

-- ============================================================
-- 3) AYNI SATIS ICIN KATMAN SIRA DOGRULAMA
-- Bir satisda birden fazla katman kullanildiysa,
-- katmanlar BelgeTarihi ASC, sayisal BelgeNo ASC sirasinda
-- olmali (eski once = FIFO).
-- ============================================================
DECLARE @StkIdFiltre INT        = NULL;
DECLARE @BaslangicTarihi DATE   = '2026-01-01';
DECLARE @BitisTarihi DATE       = '2026-01-31';

PRINT '';
PRINT '========================================';
PRINT '3) Ayni satis - katman kronoloji kontrolu';
PRINT '   Eski katman once tuketilmeli (FIFO)';
PRINT '========================================';

WITH siralama AS (
    SELECT
        c.StkId,
        c.HareketTarihi,
        c.MekanId,
        c.KatmanId,
        c.KatmanTarihi,
        c.KatmanBelgeNo,
        ISNULL(c.KatmanTarihi, c.HareketTarihi) AS fifoSiraTarihi,
        TRY_CONVERT(BIGINT, c.KatmanBelgeNo)    AS fifoSiraBelgeNoNum,
        -- Beklenen sira: bu katman oncekinden daha yeni olmali (>= kabul)
        LAG(ISNULL(c.KatmanTarihi, c.HareketTarihi)) OVER (
            PARTITION BY c.StkId, c.HareketTarihi, c.MekanId
            ORDER BY
                ISNULL(c.KatmanTarihi, c.HareketTarihi),
                CASE WHEN TRY_CONVERT(BIGINT, c.KatmanBelgeNo) IS NULL THEN 1 ELSE 0 END,
                TRY_CONVERT(BIGINT, c.KatmanBelgeNo),
                c.KatmanBelgeNo,
                c.KatmanId
        ) AS oncekiKatmanTarihi
    FROM dbo.FifoCikisDetay c
    WHERE c.HareketTarihi >= @BaslangicTarihi
      AND c.HareketTarihi <= @BitisTarihi
      AND (@StkIdFiltre IS NULL OR c.StkId = @StkIdFiltre)
)
SELECT
    StkId, HareketTarihi, MekanId,
    KatmanTarihi, KatmanBelgeNo, fifoSiraTarihi, fifoSiraBelgeNoNum,
    oncekiKatmanTarihi,
    'HATA: Eski katman gerekiyordu' AS Aciklama
FROM siralama
WHERE oncekiKatmanTarihi IS NOT NULL         -- ilk katman degil
  AND fifoSiraTarihi < oncekiKatmanTarihi    -- bu katman oncekinden DAHA ESKIyse hata
ORDER BY StkId, HareketTarihi, MekanId
OPTION (MAXDOP 4);

-- Ozet
SELECT
    CASE WHEN COUNT(*) = 0 THEN 'OK: FIFO sira dogru' ELSE 'HATA: FIFO sira ihlali var' END AS Sonuc,
    COUNT(*) AS HataSatirSayisi
FROM (
    WITH siralama2 AS (
        SELECT
            c.StkId, c.HareketTarihi, c.MekanId, c.KatmanId,
            ISNULL(c.KatmanTarihi, c.HareketTarihi) AS fifoSiraTarihi,
            LAG(ISNULL(c.KatmanTarihi, c.HareketTarihi)) OVER (
                PARTITION BY c.StkId, c.HareketTarihi, c.MekanId
                ORDER BY
                    ISNULL(c.KatmanTarihi, c.HareketTarihi),
                    CASE WHEN TRY_CONVERT(BIGINT, c.KatmanBelgeNo) IS NULL THEN 1 ELSE 0 END,
                    TRY_CONVERT(BIGINT, c.KatmanBelgeNo),
                    c.KatmanBelgeNo, c.KatmanId
            ) AS oncekiKatmanTarihi
        FROM dbo.FifoCikisDetay c
        WHERE c.HareketTarihi >= @BaslangicTarihi
          AND c.HareketTarihi <= @BitisTarihi
          AND (@StkIdFiltre IS NULL OR c.StkId = @StkIdFiltre)
    )
    SELECT 1 AS x
    FROM siralama2
    WHERE oncekiKatmanTarihi IS NOT NULL
      AND fifoSiraTarihi < oncekiKatmanTarihi
) t;
GO

-- ============================================================
-- 4) KATMAN TUKETIM HIZI: Hangi urunlerde katman siralama
--    karmasikligi var? (Ayni gun coklu katman - inceleme listesi)
-- ============================================================
DECLARE @StkIdFiltre INT      = NULL;
DECLARE @BaslangicTarihi DATE = '2026-01-01';
DECLARE @BitisTarihi DATE     = '2026-01-31';

PRINT '';
PRINT '========================================';
PRINT '4) Coklu katman kullanan satislar (inceleme listesi)';
PRINT '========================================';

SELECT TOP 50
    c.StkId,
    c.HareketTarihi,
    c.MekanId,
    COUNT(*)                        AS KatmanAdedi,
    MIN(c.KatmanTarihi)             AS EnEskiKatman,
    MAX(c.KatmanTarihi)             AS EnYeniKatman,
    SUM(c.Miktar)                   AS ToplamMiktar,
    SUM(c.CikisTutar)               AS ToplamTutar
FROM dbo.FifoCikisDetay c
WHERE c.HareketTarihi >= @BaslangicTarihi
  AND c.HareketTarihi <= @BitisTarihi
  AND (@StkIdFiltre IS NULL OR c.StkId = @StkIdFiltre)
GROUP BY c.StkId, c.HareketTarihi, c.MekanId
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC, c.StkId, c.HareketTarihi
OPTION (MAXDOP 4);
GO
