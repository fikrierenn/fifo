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

-- =============================================================
-- V2 EKLENTI: SENTETIK GIRIS (HAYALI EVRAK) KATMANI
-- Amac: STOK_YETERSIZ sorunlarindan sentetik maliyet katmani uretmek
-- Not: Bu SP FIFO cikisi otomatik tekrar hesaplamaz.
-- =============================================================

CREATE OR ALTER PROCEDURE dbo.sp_Fifo_SentetikKatmanOlustur
(
    @SorunTarihi DATE,                              -- genelde ay sonu (satis bitis)
    @GirisTarihi DATE = NULL,                       -- sentetik katman tarihi (NULL => @SorunTarihi)
    @SentetikSatinalmaSarti VARCHAR(50) = NULL,     -- sadece sentetik fallback fiyat secimi icin
    @StkId INT = NULL,
    @SabitFallbackBirimMaliyet DECIMAL(18,6) = NULL,
    @DryRun BIT = 0
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @SorunTarihi IS NULL
    BEGIN
        RAISERROR('Sorun tarihi bos olamaz.', 16, 1);
        RETURN;
    END

    IF @SabitFallbackBirimMaliyet IS NOT NULL AND @SabitFallbackBirimMaliyet <= 0
    BEGIN
        RAISERROR('Sabit fallback birim maliyet 0''dan buyuk olmali.', 16, 1);
        RETURN;
    END

    IF @GirisTarihi IS NULL
        SET @GirisTarihi = @SorunTarihi;

    IF OBJECT_ID('tempdb..#eksik', 'U') IS NOT NULL DROP TABLE #eksik;
    IF OBJECT_ID('tempdb..#sartFiyat', 'U') IS NOT NULL DROP TABLE #sartFiyat;
    IF OBJECT_ID('tempdb..#sentetik', 'U') IS NOT NULL DROP TABLE #sentetik;

    SELECT
        s.StkId,
        SUM(CASE WHEN s.StokMiktar > 0 THEN s.StokMiktar ELSE 0 END) AS eksikMiktar
    INTO #eksik
    FROM dbo.FifoSorunluStoklar s
    WHERE s.SorunTipi = 'STOK_YETERSIZ'
      AND s.EnvanterTarihi = @SorunTarihi
      AND (@StkId IS NULL OR s.StkId = @StkId)
    GROUP BY s.StkId
    HAVING SUM(CASE WHEN s.StokMiktar > 0 THEN s.StokMiktar ELSE 0 END) > 0;

    IF NOT EXISTS (SELECT 1 FROM #eksik)
    BEGIN
        IF @DryRun = 1
        BEGIN
            SELECT
                CAST(NULL AS INT) AS StkId,
                CAST(NULL AS DATE) AS GirisTarihi,
                CAST(NULL AS DECIMAL(18,4)) AS GirisMiktar,
                CAST(NULL AS DECIMAL(18,6)) AS BirimMaliyet,
                CAST(NULL AS VARCHAR(20)) AS Durum,
                CAST(NULL AS VARCHAR(50)) AS SatinalmaSarti
            WHERE 1 = 0;
        END
        PRINT 'Sentetik katman icin STOK_YETERSIZ kaydi bulunamadi.';
        RETURN;
    END

    ;WITH FiyatKaynak AS (
        SELECT
            e.StkId,
            erp.SatinalmaSarti,
            erp.BirimMaliyet,
            ROW_NUMBER() OVER (
                PARTITION BY e.StkId
                ORDER BY
                    CASE
                        WHEN @SentetikSatinalmaSarti IS NOT NULL AND erp.SatinalmaSarti = @SentetikSatinalmaSarti THEN 0
                        ELSE 1
                    END,
                    erp.SatinalmaSarti
            ) AS rn
        FROM #eksik e
        LEFT JOIN dbo.FifoFallbackFiyatlari erp
            ON erp.StkId = e.StkId
           AND (@SentetikSatinalmaSarti IS NULL OR erp.SatinalmaSarti = @SentetikSatinalmaSarti)
    )
    SELECT
        StkId,
        SatinalmaSarti,
        BirimMaliyet
    INTO #sartFiyat
    FROM FiyatKaynak
    WHERE rn = 1;

    SELECT
        e.StkId,
        @GirisTarihi AS GirisTarihi,
        CAST(e.eksikMiktar AS DECIMAL(18,4)) AS GirisMiktar,
        CAST(e.eksikMiktar AS DECIMAL(18,4)) AS KalanMiktar,
        CAST(COALESCE(f.BirimMaliyet, @SabitFallbackBirimMaliyet) AS DECIMAL(18,6)) AS BirimMaliyet,
        CAST(
            CASE
                WHEN f.BirimMaliyet IS NOT NULL THEN 'HAYALI_SART'
                WHEN @SabitFallbackBirimMaliyet IS NOT NULL THEN 'HAYALI_SABIT'
                ELSE 'HAYALI_FIYAT_YOK'
            END AS VARCHAR(20)
        ) AS Durum,
        f.SatinalmaSarti
    INTO #sentetik
    FROM #eksik e
    LEFT JOIN #sartFiyat f ON f.StkId = e.StkId;

    IF @DryRun = 1
    BEGIN
        -- FIX: acik 6 kolon (eski SELECT * = 7 kolon/KalanMiktar dahil) → cagiranin
        -- #sentetikDryRun(6) + bos-vaka SELECT(6) ile uyumlu. INSERT-EXEC mismatch giderildi.
        SELECT StkId, GirisTarihi, GirisMiktar, BirimMaliyet, Durum, SatinalmaSarti
        FROM #sentetik
        ORDER BY StkId;
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Ayni tarih ve urunler icin eski sentetik katmanlari temizle (tekrar calistirma guvenli)
        DELETE h
        FROM dbo.FifoKatman h
        WHERE h.KaynakTip = 'SENTETIK_ALIS'
          AND h.GirisTarihi = @GirisTarihi
          AND (@StkId IS NULL OR h.StkId = @StkId);

        INSERT INTO dbo.FifoKatman
            (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
             GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
        SELECT
            s.StkId,
            s.GirisTarihi,
            'SENTETIK_ALIS',
            'SENTETIK-' + CONVERT(VARCHAR(8), @GirisTarihi, 112),
            s.GirisTarihi,
            NULL,
            s.GirisMiktar,
            s.KalanMiktar,
            ISNULL(s.BirimMaliyet, 0),
            s.Durum
        FROM #sentetik s
        WHERE s.BirimMaliyet IS NOT NULL
          AND s.BirimMaliyet > 0;

        -- Sentetik fiyatlama bilgi kayitlari (tekrar calistirmaya uygun)
        DELETE x
        FROM dbo.FifoSorunluStoklar x
        WHERE x.EnvanterTarihi = @GirisTarihi
          AND x.SorunTipi IN ('SENTETIK_FIYATLANDI', 'SENTETIK_FIYAT_YOK')
          AND (@StkId IS NULL OR x.StkId = @StkId);

        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, MekanId, StokMiktar, SorunTipi, Aciklama)
        SELECT
            s.StkId,
            @GirisTarihi,
            0,
            s.GirisMiktar,
            'SENTETIK_FIYATLANDI',
            'Kaynak=SENTETIK_ALIS; Durum=' + s.Durum +
            '; Sarti=' + ISNULL(s.SatinalmaSarti, '-') +
            '; BirimMaliyet=' + CONVERT(VARCHAR(30), s.BirimMaliyet)
        FROM #sentetik s
        WHERE s.BirimMaliyet IS NOT NULL
          AND s.BirimMaliyet > 0;

        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, MekanId, StokMiktar, SorunTipi, Aciklama)
        SELECT
            s.StkId,
            @GirisTarihi,
            0,
            s.GirisMiktar,
            'SENTETIK_FIYAT_YOK',
            'STOK_YETERSIZ bulundu ancak sart/sabit fallback fiyat bulunamadi.'
        FROM #sentetik s
        WHERE s.BirimMaliyet IS NULL OR s.BirimMaliyet <= 0;

        COMMIT TRANSACTION;

        SELECT
            StkId,
            GirisTarihi,
            GirisMiktar,
            BirimMaliyet,
            Durum,
            SatinalmaSarti
        FROM #sentetik
        ORDER BY StkId;

        PRINT 'Sentetik katmanlar olusturuldu. FIFO cikisini yeniden hesaplamak icin ayri proses gerekir.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

PRINT 'sp_Fifo_SentetikKatmanOlustur olusturuldu';
GO

