USE BKMMaliyet;
GO

-- =============================================================
-- ALPHA EKLENTI: SENTETIK GIRIS (HAYALI EVRAK) KATMANI
-- Amac: STOK_YETERSIZ sorunlarindan sentetik maliyet katmani uretmek
-- Not: Bu SP FIFO cikisi otomatik tekrar hesaplamaz.
-- =============================================================

CREATE OR ALTER PROCEDURE bkm.sp_fifo_SentetikAlisKatmanOlustur
(
    @sorunTarihi DATE,                              -- genelde ay sonu (satis bitis)
    @girisTarihi DATE = NULL,                       -- sentetik katman tarihi (NULL => @sorunTarihi)
    @sentetikSatinalmaSarti VARCHAR(50) = NULL,     -- sadece sentetik fallback fiyat secimi icin
    @stkID INT = NULL,
    @sabitFallbackBirimMaliyet DECIMAL(18,6) = NULL,
    @dryRun BIT = 0
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @sorunTarihi IS NULL
    BEGIN
        RAISERROR('Sorun tarihi bos olamaz.', 16, 1);
        RETURN;
    END

    IF @sabitFallbackBirimMaliyet IS NOT NULL AND @sabitFallbackBirimMaliyet <= 0
    BEGIN
        RAISERROR('Sabit fallback birim maliyet 0''dan buyuk olmali.', 16, 1);
        RETURN;
    END

    IF @girisTarihi IS NULL
        SET @girisTarihi = @sorunTarihi;

    IF OBJECT_ID('tempdb..#eksik', 'U') IS NOT NULL DROP TABLE #eksik;
    IF OBJECT_ID('tempdb..#sartFiyat', 'U') IS NOT NULL DROP TABLE #sartFiyat;
    IF OBJECT_ID('tempdb..#sentetik', 'U') IS NOT NULL DROP TABLE #sentetik;

    SELECT
        s.stkID,
        SUM(CASE WHEN s.stokMiktar > 0 THEN s.stokMiktar ELSE 0 END) AS eksikMiktar
    INTO #eksik
    FROM bkm.fifo_StokMaliyetSorunlu s
    WHERE s.sorunTip = 'STOK_YETERSIZ'
      AND s.envanterTarihi = @sorunTarihi
      AND (@stkID IS NULL OR s.stkID = @stkID)
    GROUP BY s.stkID
    HAVING SUM(CASE WHEN s.stokMiktar > 0 THEN s.stokMiktar ELSE 0 END) > 0;

    IF NOT EXISTS (SELECT 1 FROM #eksik)
    BEGIN
        IF @dryRun = 1
        BEGIN
            SELECT
                CAST(NULL AS INT) AS stkID,
                CAST(NULL AS DATE) AS girisTarihi,
                CAST(NULL AS DECIMAL(18,4)) AS miktarToplam,
                CAST(NULL AS DECIMAL(18,6)) AS birimMaliyet,
                CAST(NULL AS VARCHAR(20)) AS durum,
                CAST(NULL AS VARCHAR(50)) AS satinalmaSarti
            WHERE 1 = 0;
        END
        PRINT 'Sentetik katman icin STOK_YETERSIZ kaydi bulunamadi.';
        RETURN;
    END

    ;WITH FiyatKaynak AS (
        SELECT
            e.stkID,
            erp.satinalmaSarti,
            erp.birimMaliyet,
            ROW_NUMBER() OVER (
                PARTITION BY e.stkID
                ORDER BY
                    CASE
                        WHEN @sentetikSatinalmaSarti IS NOT NULL AND erp.satinalmaSarti = @sentetikSatinalmaSarti THEN 0
                        ELSE 1
                    END,
                    erp.satinalmaSarti
            ) AS rn
        FROM #eksik e
        LEFT JOIN bkm.fifo_ErpDevirFiyatlari erp
            ON erp.stkID = e.stkID
           AND (@sentetikSatinalmaSarti IS NULL OR erp.satinalmaSarti = @sentetikSatinalmaSarti)
    )
    SELECT
        stkID,
        satinalmaSarti,
        birimMaliyet
    INTO #sartFiyat
    FROM FiyatKaynak
    WHERE rn = 1;

    SELECT
        e.stkID,
        @girisTarihi AS girisTarihi,
        CAST(e.eksikMiktar AS DECIMAL(18,4)) AS miktarToplam,
        CAST(e.eksikMiktar AS DECIMAL(18,4)) AS miktarKalan,
        CAST(COALESCE(f.birimMaliyet, @sabitFallbackBirimMaliyet) AS DECIMAL(18,6)) AS birimMaliyet,
        CAST(
            CASE
                WHEN f.birimMaliyet IS NOT NULL THEN 'HAYALI_SART'
                WHEN @sabitFallbackBirimMaliyet IS NOT NULL THEN 'HAYALI_SABIT'
                ELSE 'HAYALI_FIYAT_YOK'
            END AS VARCHAR(20)
        ) AS durum,
        f.satinalmaSarti
    INTO #sentetik
    FROM #eksik e
    LEFT JOIN #sartFiyat f ON f.stkID = e.stkID;

    IF @dryRun = 1
    BEGIN
        SELECT *
        FROM #sentetik
        ORDER BY stkID;
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Ayni tarih ve urunler icin eski sentetik katmanlari temizle (alpha tekrar calistirma)
        DELETE h
        FROM bkm.fifo_StokMaliyetHavuzu h
        WHERE h.kaynakTip = 'SENTETIK_ALIS'
          AND h.girisTarihi = @girisTarihi
          AND (@stkID IS NULL OR h.stkID = @stkID);

        INSERT INTO bkm.fifo_StokMaliyetHavuzu
            (stkID, girisTarihi, kaynakTip, belgeNo, belgeTarihi, firmaID,
             miktarToplam, miktarKalan, birimMaliyet, durum)
        SELECT
            s.stkID,
            s.girisTarihi,
            'SENTETIK_ALIS',
            'SENTETIK-' + CONVERT(VARCHAR(8), @girisTarihi, 112),
            s.girisTarihi,
            NULL,
            s.miktarToplam,
            s.miktarKalan,
            ISNULL(s.birimMaliyet, 0),
            s.durum
        FROM #sentetik s
        WHERE s.birimMaliyet IS NOT NULL
          AND s.birimMaliyet > 0;

        -- Sentetik fiyatlama bilgi kayitlari (tekrar calistirmaya uygun)
        DELETE x
        FROM bkm.fifo_StokMaliyetSorunlu x
        WHERE x.envanterTarihi = @girisTarihi
          AND x.sorunTip IN ('SENTETIK_FIYATLANDI', 'SENTETIK_FIYAT_YOK')
          AND (@stkID IS NULL OR x.stkID = @stkID);

        INSERT INTO bkm.fifo_StokMaliyetSorunlu
            (stkID, envanterTarihi, stokMiktar, sorunTip, aciklama)
        SELECT
            s.stkID,
            @girisTarihi,
            s.miktarToplam,
            'SENTETIK_FIYATLANDI',
            'Kaynak=SENTETIK_ALIS; Durum=' + s.durum +
            '; Sarti=' + ISNULL(s.satinalmaSarti, '-') +
            '; BirimMaliyet=' + CONVERT(VARCHAR(30), s.birimMaliyet)
        FROM #sentetik s
        WHERE s.birimMaliyet IS NOT NULL
          AND s.birimMaliyet > 0;

        INSERT INTO bkm.fifo_StokMaliyetSorunlu
            (stkID, envanterTarihi, stokMiktar, sorunTip, aciklama)
        SELECT
            s.stkID,
            @girisTarihi,
            s.miktarToplam,
            'SENTETIK_FIYAT_YOK',
            'STOK_YETERSIZ bulundu ancak sart/sabit fallback fiyat bulunamadi.'
        FROM #sentetik s
        WHERE s.birimMaliyet IS NULL OR s.birimMaliyet <= 0;

        COMMIT TRANSACTION;

        SELECT
            stkID,
            girisTarihi,
            miktarToplam,
            birimMaliyet,
            durum,
            satinalmaSarti
        FROM #sentetik
        ORDER BY stkID;

        PRINT 'Sentetik katmanlar olusturuldu. FIFO cikisini yeniden hesaplamak icin ayri proses gerekir.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

PRINT 'sp_fifo_SentetikAlisKatmanOlustur olusturuldu';
GO
