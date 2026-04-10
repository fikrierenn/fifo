-- 19_V2_CikisSatisTutar.sql
-- FifoCikisDetay tablosuna SatisTutar kolonu ekle + mevcut verileri backfill
-- Satis tutari: irsHrk'dan tarih+mekan+stk eslesmesiyle, gunluk toplam uzerinden oran hesabi

-- =============================================================
-- 1) KOLON EKLE (idempotent)
-- =============================================================
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.FifoCikisDetay') AND name = 'SatisTutar'
)
BEGIN
    ALTER TABLE dbo.FifoCikisDetay ADD SatisTutar DECIMAL(18,4) NULL;
    PRINT 'FifoCikisDetay.SatisTutar kolonu eklendi.';
END
GO

-- =============================================================
-- 2) MEVCUT VERILERI GERI DOLDUR (backfill)
-- =============================================================
-- Yaklasim: irsHrk'dan tarih + mekan + StkId bazinda gunluk toplam tutar al
-- Her cikis satirina miktar oraninda dagit
-- ehTutarN = net satis tutari (indirim dusulmus, KDV haric)

;WITH hrkGunluk AS (
    SELECT
        h.ehstkID AS StkId,
        CAST(h.ehTrhS AS DATE) AS Tarih,
        h.ehMekan AS MekanId,
        SUM(h.ehAdetN) AS ToplamAdet,
        SUM(h.ehTutarN) AS ToplamTutar
    FROM DerinSISBkm.dbo.irsHrk h
    WHERE h.ehstkID IN (SELECT DISTINCT StkId FROM FifoCikisDetay WHERE SatisTutar IS NULL)
      AND h.ehMekan IN (1, 12, 4477, 4478)
      AND h.ehAltDepo = 0
    GROUP BY h.ehstkID, CAST(h.ehTrhS AS DATE), h.ehMekan
)
UPDATE c
SET c.SatisTutar = CASE
    WHEN g.ToplamAdet = 0 THEN 0
    ELSE ABS(CAST(c.Miktar AS DECIMAL(18,4)) / CAST(g.ToplamAdet AS DECIMAL(18,4)) * CAST(g.ToplamTutar AS DECIMAL(18,4)))
END
FROM FifoCikisDetay c
JOIN hrkGunluk g ON g.StkId = c.StkId AND g.Tarih = c.HareketTarihi AND g.MekanId = c.MekanId
WHERE c.SatisTutar IS NULL;

PRINT 'Backfill tamamlandi: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' satir guncellendi.';
GO
