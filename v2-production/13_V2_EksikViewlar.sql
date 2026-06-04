USE BKMMaliyet;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
GO
SET NOCOUNT ON;
GO

-- =============================================================
-- vw_Ortalama_AySonuBirimMaliyet
-- OrtalamaAylikMaliyet tablosundan ay sonu birim maliyet ozeti.
-- FIFO tarafindaki vw_Fifo_AySonuBirimMaliyet'in Ortalama karsiligi.
-- =============================================================
CREATE OR ALTER VIEW dbo.vw_Ortalama_AySonuBirimMaliyet
AS
SELECT
    YilAy,
    StkId,
    AyBasiMiktar,
    AyBasiTutar,
    GirisMiktar,
    GirisTutar,
    CikisMiktar,
    AySonuMiktar,
    AySonuBirimMaliyet,
    AySonuTutar,
    CreateUtc,
    UpdateUtc
FROM dbo.OrtalamaAylikMaliyet;
GO

PRINT 'vw_Ortalama_AySonuBirimMaliyet olusturuldu';
GO

-- =============================================================
-- vw_MaliyetKarsilastirma
-- FIFO vs Ortalama maliyet yan yana karsilastirma.
--
-- FIFO tarafi: vw_Fifo_AySonuBirimMaliyet (katman bazli agirlikli ort)
--   GirisTarihi = envanter tarihi, StkId bazinda grup
-- Ortalama tarafi: OrtalamaAylikMaliyet (YilAy, StkId)
--
-- Join mantigi: FIFO'nun GirisTarihi ay sonu tarihine denk gelir
--   (ornek: 2025-12-31 acilis → YilAy 202601 ile eslesir)
--   Bu yuzden FIFO EnvanterTarihi'nden YilAy turetilir.
-- =============================================================
CREATE OR ALTER VIEW dbo.vw_MaliyetKarsilastirma
AS
SELECT
    o.YilAy,
    o.StkId,
    -- Ortalama Maliyet
    o.AySonuMiktar          AS Ort_Miktar,
    o.AySonuBirimMaliyet    AS Ort_BirimMaliyet,
    o.AySonuTutar           AS Ort_Tutar,
    -- FIFO Maliyet
    f.StokMiktar            AS Fifo_Miktar,
    f.BirimMaliyet          AS Fifo_BirimMaliyet,
    f.Tutar                 AS Fifo_Tutar,
    -- Fark
    CASE
        WHEN o.AySonuBirimMaliyet = 0 OR f.BirimMaliyet IS NULL THEN NULL
        ELSE CAST(f.BirimMaliyet - o.AySonuBirimMaliyet AS DECIMAL(18,6))
    END AS BirimMaliyetFarki,
    CASE
        WHEN o.AySonuBirimMaliyet = 0 OR f.BirimMaliyet IS NULL THEN NULL
        ELSE CAST(
            (f.BirimMaliyet - o.AySonuBirimMaliyet)
            / o.AySonuBirimMaliyet * 100
        AS DECIMAL(18,2))
    END AS FarkYuzdesi
FROM dbo.OrtalamaAylikMaliyet o
-- FIX: FIFO tarafi StkId basina TEK satira toplanir (eski hali GirisTarihi'ne grupluydu
--      -> StkId basina N satir -> StkId-only JOIN kartezyen carpim yapiyordu).
LEFT JOIN (
    SELECT
        StkId,
        SUM(KalanMiktar) AS StokMiktar,
        CASE WHEN SUM(KalanMiktar) = 0 THEN CAST(0 AS DECIMAL(18,6))
             ELSE CAST(SUM(KalanMiktar * BirimMaliyet) / SUM(KalanMiktar) AS DECIMAL(18,6)) END AS BirimMaliyet,
        CAST(SUM(KalanMiktar * BirimMaliyet) AS DECIMAL(18,4)) AS Tutar
    FROM dbo.FifoKatman
    WHERE KalanMiktar > 0
    GROUP BY StkId
) f ON f.StkId = o.StkId;
-- NOT: FIFO aylik snapshot tutmuyor -> her YilAy, GUNCEL FIFO stok maliyetiyle karsilastirilir.
GO

PRINT 'vw_MaliyetKarsilastirma olusturuldu';
GO
