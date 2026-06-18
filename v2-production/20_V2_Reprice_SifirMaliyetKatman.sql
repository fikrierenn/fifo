/* ============================================================
   20_V2_Reprice_SifirMaliyetKatman.sql
   FIYAT 0 OLAMAZ (fifo-domain §6, 2026-06-19) — mevcut artigi temizler.

   Sorun: ACILIS_TAMAMLA / Durum=TAMAMLAMA katmanlarinda BirimMaliyet=0
   (acilis SP'sinin SonAlis CTE'si 0-degerli fatAyr satirini secmis — bkz
   14_V2_AcilisOptimize.sql SonAlis/SonMerkez guard fix'i). irs/irsAyr disk
   temizliginde DROP edildigi icin acilis re-run su an mumkun degil; bu script
   mevcut 13 katmani gercek son-NONZERO alis fiyatiyla repriceler (fatAyr+fat
   direkt, standart alis filtresi eTip IN (0,2)+eGC=0).

   Idempotent: BirimMaliyet<=0 hedefler → tekrar calistirilirsa is yapmaz.
   Guard: bir katmana nonzero alis bulunamazsa TUM islem geri alinir (0 birakmaz).
   ============================================================ */
SET XACT_ABORT ON;
SET NOCOUNT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID('tempdb..#fix') IS NOT NULL DROP TABLE #fix;

    ;WITH z AS (
        SELECT KatmanId, StkId
        FROM dbo.FifoKatman
        WHERE BirimMaliyet <= 0
    ),
    al AS (
        SELECT a.ehStkID AS StkId, f.eTarih, f.eNo,
               SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS Miktar,
               SUM(CONVERT(DECIMAL(18,4),
                   CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END)) AS NetTutar
        FROM DerinSIS_Local.dbo.fatAyr a
        JOIN DerinSIS_Local.dbo.fat f ON f.eID = a.ehID
        WHERE f.eTip IN (0, 2) AND f.eGC = 0 AND a.ehAdetN <> 0
          AND f.eTarih < DATEADD(DAY, 1, CONVERT(SMALLDATETIME, '2025-12-31'))
          AND a.ehStkID IN (SELECT StkId FROM z)
        GROUP BY a.ehStkID, f.eTarih, f.eID, f.eNo
    ),
    r AS (
        SELECT StkId,
               CAST(NetTutar / Miktar AS DECIMAL(18,6)) AS bm,
               ROW_NUMBER() OVER (PARTITION BY StkId ORDER BY eTarih DESC, eNo DESC) AS rn
        FROM al
        WHERE Miktar <> 0 AND NetTutar / Miktar > 0   -- FIYAT 0 OLAMAZ: sadece NONZERO alis aday
    )
    SELECT z.KatmanId, z.StkId, r.bm AS YeniMaliyet
    INTO #fix
    FROM z
    JOIN r ON r.StkId = z.StkId AND r.rn = 1;

    /* Guard — nonzero alis bulunamayan katman varsa ABORT (0 BIRAKMA) */
    DECLARE @fiyatsiz INT = (
        SELECT COUNT(*)
        FROM dbo.FifoKatman k
        WHERE k.BirimMaliyet <= 0
          AND NOT EXISTS (SELECT 1 FROM #fix x WHERE x.KatmanId = k.KatmanId)
    );
    IF @fiyatsiz > 0
    BEGIN
        ROLLBACK TRANSACTION;
        RAISERROR('FIYAT 0 OLAMAZ ihlali: %d katman icin nonzero alis bulunamadi — merkez/sart/ManuelMaliyet gerekli, islem geri alindi.', 16, 1, @fiyatsiz);
        RETURN;
    END

    /* Katman reprice */
    UPDATE k SET k.BirimMaliyet = x.YeniMaliyet
    FROM dbo.FifoKatman k
    JOIN #fix x ON x.KatmanId = k.KatmanId;
    PRINT 'Katman repriced: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    /* Cikis detay propagate (tuketilmis katmanlarin SMM'i) — CikisTutar COMPUTED (Miktar*BirimMaliyet),
       BirimMaliyet guncellenince otomatik yeniden hesaplanir. SatisTutar (gelir) DOKUNULMAZ. */
    UPDATE c SET c.BirimMaliyet = x.YeniMaliyet
    FROM dbo.FifoCikisDetay c
    JOIN #fix x ON x.KatmanId = c.KatmanId;
    PRINT 'Cikis repriced: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    COMMIT TRANSACTION;

    /* Dogrulama — ikisi de 0 donmeli */
    DECLARE @k0 INT = (SELECT COUNT(*) FROM dbo.FifoKatman     WHERE BirimMaliyet <= 0);
    DECLARE @c0 INT = (SELECT COUNT(*) FROM dbo.FifoCikisDetay WHERE BirimMaliyet <= 0);
    PRINT 'KONTROL — sifir-maliyet katman: ' + CAST(@k0 AS VARCHAR(10)) + ' | sifir-maliyet cikis: ' + CAST(@c0 AS VARCHAR(10));
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
