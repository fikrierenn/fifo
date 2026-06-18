/* ============================================================
   21_V2_AcilisEksikMaliyet.sql
   FIYAT 0 OLAMAZ (fifo-domain §6) — KATMANSIZ acilis stogunu maliyetlendirir.

   Sorun: 619 urun acilis envanterinde stogu VAR ama hic FifoKatman'i YOK
   (FIYAT_YOK; bayat acilis SART tier'i koşmamis). Hepsinin CIKISI SIFIR
   (saf acilis stok) → re-run/Ocak GEREKMEZ; dogrudan ACILIS_TAMAMLA katmani
   eklenir. irs/irsAyr DROP edildigi icin acilis re-run zaten imkansiz.

   Fiyat oncelik (acilis SP fallback sirasiyla hizali):
     1) fatAyr son NONZERO alis (eTip 0/2, eGC=0)         → Durum TAMAMLAMA
     2) fytOzl son gecerli sart fiyati (fTur=1,fTip=1,     → Durum SART_TAMAMLAMA
        indirim kademeli sonrakiNet; fn_SonGecerliFiyat'in
        HIZLI eşdeğeri — hedef stkID'lere kisitli ROW_NUMBER)
     3) SatisFiyat × kategori-marj orani (KatAna)          → Durum KATEGORI_IMPUT
     4) kategori ortalama MUTLAK maliyet (SatisFiyat yok)  → Durum KATEGORI_ORT
     5) hicbir kaynak yok (demirbas/obsolete/UrunBilgi'siz)→ FifoDevreDisiUrunler

   Impute edilenler (3,4) FifoFallbackFiyatlari'na da yazilir (audit).
   Idempotent: katmansiz hedefler → re-run is yapmaz. 0-kalirsa ABORT.
   ============================================================ */
SET XACT_ABORT ON;
SET NOCOUNT ON;
DECLARE @EnvanterTarihi DATE = '2025-12-31';

BEGIN TRY
    BEGIN TRANSACTION;

    /* 0) HEDEF — katmansiz acilis stok (devre-disi haric), stok per StkId */
    IF OBJECT_ID('tempdb..#hedef') IS NOT NULL DROP TABLE #hedef;
    SELECT a.StkId, CAST(SUM(a.StokMiktar) AS DECIMAL(18,4)) AS Stok
    INTO #hedef
    FROM dbo.FifoAcilisEnvanter a
    WHERE a.StokMiktar > 0
      AND NOT EXISTS (SELECT 1 FROM dbo.FifoKatman k WHERE k.StkId = a.StkId)
      AND NOT EXISTS (SELECT 1 FROM dbo.FifoDevreDisiUrunler d WHERE d.StkId = a.StkId)
    GROUP BY a.StkId
    HAVING SUM(a.StokMiktar) > 0;

    /* 1) Kategori marj orani (cost/satis) + mutlak ortalama maliyet — gercek-maliyetli urunlerden */
    IF OBJECT_ID('tempdb..#katOran') IS NOT NULL DROP TABLE #katOran;
    SELECT ub.KatAna,
           CAST(AVG(k.BirimMaliyet / ub.SatisFiyat) AS DECIMAL(18,6)) AS Oran,
           CAST(AVG(k.BirimMaliyet) AS DECIMAL(18,6)) AS OrtMaliyet
    INTO #katOran
    FROM dbo.FifoKatman k
    JOIN DerinSIS_Local.dbo.UrunBilgi ub ON ub.StkID = k.StkId
    WHERE k.BirimMaliyet > 0 AND k.Durum IN ('NORMAL','TAMAMLAMA')
      AND ub.SatisFiyat > 0 AND k.BirimMaliyet < ub.SatisFiyat * 3   -- outlier trim
      AND ub.KatAna IS NOT NULL
    GROUP BY ub.KatAna
    HAVING COUNT(*) >= 20;

    /* 2a) fatAyr son NONZERO alis (tier1) */
    IF OBJECT_ID('tempdb..#fat') IS NOT NULL DROP TABLE #fat;
    ;WITH al AS (
        SELECT a.ehStkID AS StkId, f.eTarih, f.eNo,
               SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN,0))) AS Miktar,
               SUM(CONVERT(DECIMAL(18,4), CASE WHEN f.eGC=0 THEN a.ehTutarN ELSE -1*a.ehTutarN END)) AS NetTutar
        FROM DerinSIS_Local.dbo.fatAyr a
        JOIN DerinSIS_Local.dbo.fat f ON f.eID = a.ehID
        WHERE f.eTip IN (0,2) AND f.eGC = 0 AND a.ehAdetN <> 0
          AND f.eTarih < DATEADD(DAY,1,CONVERT(SMALLDATETIME,@EnvanterTarihi))
          AND a.ehStkID IN (SELECT StkId FROM #hedef)
        GROUP BY a.ehStkID, f.eTarih, f.eID, f.eNo
    ),
    r AS (
        SELECT StkId, CAST(NetTutar/Miktar AS DECIMAL(18,6)) AS bm,
               ROW_NUMBER() OVER (PARTITION BY StkId ORDER BY eTarih DESC, eNo DESC) AS rn
        FROM al WHERE Miktar <> 0 AND NetTutar/Miktar > 0
    )
    SELECT StkId, bm AS BirimMaliyet INTO #fat FROM r WHERE rn = 1;

    /* 2b) fytOzl son gecerli sart fiyati (tier2) — fn_SonGecerliFiyat HIZLI esdegeri
       (hedef stkID'e kisitli; ROW_NUMBER sadece 619 satirinda, 6.5M degil) */
    IF OBJECT_ID('tempdb..#fyt') IS NOT NULL DROP TABLE #fyt;
    ;WITH A AS (
        SELECT f.fStkID, f.sonrakiFiyat, f.fInd1, f.fInd2, f.fInd3, f.fInd4, f.fInd5,
               rn = ROW_NUMBER() OVER (PARTITION BY f.fStkID
                    ORDER BY CASE WHEN f.fFrmID=9525 THEN 0 ELSE 1 END, f.fTarih DESC, f.fID DESC)
        FROM DerinSIS_Local.dbo.fytOzl f
        WHERE f.fTip = 1 AND f.fTur = 1 AND f.onay = 1
          AND f.fTarih <= CONVERT(SMALLDATETIME,@EnvanterTarihi)
          AND f.fStkID IN (SELECT StkId FROM #hedef)
    )
    SELECT fStkID AS StkId,
           CAST(sonrakiFiyat
                * (100.0-ISNULL(fInd1,0))/100.0 * (100.0-ISNULL(fInd2,0))/100.0
                * (100.0-ISNULL(fInd3,0))/100.0 * (100.0-ISNULL(fInd4,0))/100.0
                * (100.0-ISNULL(fInd5,0))/100.0 AS DECIMAL(18,6)) AS BirimMaliyet
    INTO #fyt FROM A WHERE rn = 1;
    DELETE FROM #fyt WHERE BirimMaliyet <= 0;   -- sonrakiNet>0 guard

    /* 3) FIYAT COZUMU (oncelik) */
    IF OBJECT_ID('tempdb..#cozum') IS NOT NULL DROP TABLE #cozum;
    SELECT h.StkId, h.Stok,
        Kaynak = CASE
            WHEN ff.BirimMaliyet IS NOT NULL              THEN 'TAMAMLAMA'
            WHEN fy.BirimMaliyet IS NOT NULL              THEN 'SART_TAMAMLAMA'
            WHEN ub.SatisFiyat > 0 AND ko.Oran IS NOT NULL THEN 'KATEGORI_IMPUT'
            WHEN ko.OrtMaliyet IS NOT NULL                THEN 'KATEGORI_ORT'
            ELSE 'YOK' END,
        BirimMaliyet = CAST(CASE
            WHEN ff.BirimMaliyet IS NOT NULL              THEN ff.BirimMaliyet
            WHEN fy.BirimMaliyet IS NOT NULL              THEN fy.BirimMaliyet
            WHEN ub.SatisFiyat > 0 AND ko.Oran IS NOT NULL THEN ub.SatisFiyat * ko.Oran
            WHEN ko.OrtMaliyet IS NOT NULL                THEN ko.OrtMaliyet
            ELSE 0 END AS DECIMAL(18,6))
    INTO #cozum
    FROM #hedef h
    LEFT JOIN #fat ff ON ff.StkId = h.StkId
    LEFT JOIN #fyt fy ON fy.StkId = h.StkId
    LEFT JOIN DerinSIS_Local.dbo.UrunBilgi ub ON ub.StkID = h.StkId
    LEFT JOIN #katOran ko ON ko.KatAna = ub.KatAna;

    /* 4) Kaynaksizlari (YOK) devre-disi (non-inventory/obsolete) */
    INSERT INTO dbo.FifoDevreDisiUrunler (StkId, Sebep, EkleyenKullanici, EklenmeTarihi)
    SELECT c.StkId, N'21_V2: acilis eksik maliyet - hicbir fiyat kaynagi yok (alis/fytOzl/SatisFiyat/kategori) → non-inventory/obsolete', 'claude-21V2', SYSDATETIME()
    FROM #cozum c
    WHERE c.Kaynak = 'YOK'
      AND NOT EXISTS (SELECT 1 FROM dbo.FifoDevreDisiUrunler d WHERE d.StkId = c.StkId);

    /* 5) Impute edilenleri (kategori) FifoFallbackFiyatlari'na yaz (audit) */
    INSERT INTO dbo.FifoFallbackFiyatlari (StkId, SatinalmaSarti, MekanId, BirimMaliyet, Miktar, ToplamTutar, Aciklama, KayitTarihi)
    SELECT c.StkId, 'KATEGORI_IMPUT', 0, c.BirimMaliyet, 1, c.BirimMaliyet,
           CASE c.Kaynak WHEN 'KATEGORI_IMPUT' THEN N'SatisFiyat × kategori-marj orani (21_V2)' ELSE N'Kategori ortalama mutlak maliyet (21_V2)' END,
           SYSDATETIME()
    FROM #cozum c
    WHERE c.Kaynak IN ('KATEGORI_IMPUT','KATEGORI_ORT') AND c.BirimMaliyet > 0
      AND NOT EXISTS (SELECT 1 FROM dbo.FifoFallbackFiyatlari ff
                      WHERE ff.StkId = c.StkId AND ff.SatinalmaSarti = 'KATEGORI_IMPUT' AND ff.MekanId = 0);

    /* 6) ACILIS_TAMAMLA katman INSERT (fiyatli olanlar; cikis YOK → KalanMiktar=GirisMiktar) */
    INSERT INTO dbo.FifoKatman
        (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId, GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
    SELECT c.StkId, @EnvanterTarihi, 'ACILIS_TAMAMLA', NULL, NULL, NULL,
           c.Stok, c.Stok, c.BirimMaliyet, c.Kaynak
    FROM #cozum c
    WHERE c.Kaynak <> 'YOK' AND c.BirimMaliyet > 0;

    DECLARE @katmanEklendi INT = @@ROWCOUNT;

    /* 7) GUARD — fiyatli ama maliyet<=0 KALMASIN (FIYAT 0 OLAMAZ) */
    DECLARE @ihlal INT = (SELECT COUNT(*) FROM #cozum WHERE Kaynak <> 'YOK' AND BirimMaliyet <= 0);
    IF @ihlal > 0
    BEGIN
        ROLLBACK TRANSACTION;
        RAISERROR('FIYAT 0 OLAMAZ ihlali: %d urun kaynakli ama maliyet<=0 — islem geri alindi.', 16, 1, @ihlal);
        RETURN;
    END

    COMMIT TRANSACTION;

    /* RAPOR */
    PRINT 'Katman eklendi: ' + CAST(@katmanEklendi AS VARCHAR(10));
    SELECT Kaynak, COUNT(*) AS urun, CAST(SUM(Stok) AS DECIMAL(18,2)) AS stok, CAST(AVG(BirimMaliyet) AS DECIMAL(18,2)) AS ort_maliyet
    FROM #cozum GROUP BY Kaynak ORDER BY urun DESC;

    DECLARE @k0 INT = (SELECT COUNT(*) FROM dbo.FifoKatman WHERE BirimMaliyet <= 0);
    DECLARE @kalanKatmansiz INT = (
        SELECT COUNT(DISTINCT a.StkId) FROM dbo.FifoAcilisEnvanter a
        WHERE a.StokMiktar > 0
          AND NOT EXISTS (SELECT 1 FROM dbo.FifoKatman k WHERE k.StkId = a.StkId)
          AND NOT EXISTS (SELECT 1 FROM dbo.FifoDevreDisiUrunler d WHERE d.StkId = a.StkId)
    );
    PRINT 'KONTROL — sifir-maliyet katman: ' + CAST(@k0 AS VARCHAR(10)) + ' | kalan katmansiz acilis stok urun: ' + CAST(@kalanKatmansiz AS VARCHAR(10));
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
