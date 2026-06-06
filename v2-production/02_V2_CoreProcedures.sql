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

CREATE OR ALTER PROCEDURE dbo.sp_Fifo_AcilisMaliyetlendir
(
    @EnvanterTarihi DATE,
    @StkId INT = NULL,
    @IslemId UNIQUEIDENTIFIER = NULL,
    @fallbackSatinalmaSarti VARCHAR(50) = NULL,   -- sadece fallback fiyatlama (acilis) icin
    @atlamaAylikDevir BIT = 0,            -- 1 = Agir aylik devir adimini atla (timeout onleme)
    @sabitFallbackBirimMaliyet DECIMAL(18,6) = NULL -- son care tek seferlik sabit fiyat
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @AdimKodu VARCHAR(50) = NULL;
    DECLARE @AdimAdi VARCHAR(100) = NULL;
    DECLARE @SiraNo INT = NULL;
    
    -- Parametre validasyonu
    IF @EnvanterTarihi IS NULL
    BEGIN
        RAISERROR('Envanter tarihi bos olamaz', 16, 1);
        RETURN;
    END

    IF @sabitFallbackBirimMaliyet IS NOT NULL AND @sabitFallbackBirimMaliyet <= 0
    BEGIN
        RAISERROR('Sabit fallback birim maliyet 0''dan buyuk olmali', 16, 1);
        RETURN;
    END
    
    IF @EnvanterTarihi > GETDATE()
    BEGIN
        RAISERROR('Envanter tarihi gelecek tarih olamaz', 16, 1);
        RETURN;
    END
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        /* Audit triggeri devre disi birak - toplu INSERT log dolduruyor */
        IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'tr_fifo_StokMaliyetHavuzu_DegisimGunlugu' AND parent_id = OBJECT_ID('dbo.FifoKatman'))
            ALTER TABLE dbo.FifoKatman DISABLE TRIGGER tr_fifo_StokMaliyetHavuzu_DegisimGunlugu;
        ELSE IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'tr_fifo_StokMaliyetHavuzu_Audit' AND parent_id = OBJECT_ID('dbo.FifoKatman'))
            ALTER TABLE dbo.FifoKatman DISABLE TRIGGER tr_fifo_StokMaliyetHavuzu_Audit;
        
        DECLARE @baslangicTarihi DATE = DATEFROMPARTS(2021, 5, 31);

        SET @AdimKodu = 'acilis_envanter';
        SET @AdimAdi = 'Envanter snapshot';
        SET @SiraNo = 10;
        PRINT '[1/4] Envanter snapshot - irsHrk okunuyor...';
        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'CALISIYOR', NULL;

        /* 1) Envanter tarihindeki stok Miktarlarinc cek (irsHrk - mekan bazli) */
        IF OBJECT_ID('tempdb..#stoklarMekan', 'U') IS NOT NULL DROP TABLE #stoklarMekan;

        SELECT 
            h.ehMekan AS MekanId,
            h.ehStkId AS StkId,
            SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) AS StokMiktar
        INTO #stoklarMekan
        FROM DerinSIS_Local.dbo.irsHrk h WITH(NOLOCK)
        WHERE h.ehTrhS <= @EnvanterTarihi
          AND h.ehAltDepo = 0
          AND h.ehMekan IN (1, 12, 4477, 4478)
          AND (@StkId IS NULL OR h.ehStkId = @StkId)
        GROUP BY h.ehMekan, h.ehStkId
        HAVING SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) > 0;

        CREATE INDEX IX_tmp_stoklarMekan_mekan_StkId ON #stoklarMekan(MekanId, StkId);

        IF OBJECT_ID('tempdb..#stoklar', 'U') IS NOT NULL DROP TABLE #stoklar;

        SELECT
            StkId,
            SUM(StokMiktar) AS StokMiktar
        INTO #stoklar
        FROM #stoklarMekan
        GROUP BY StkId;

        CREATE INDEX IX_tmp_stoklar_StkId ON #stoklar(StkId);

        /* DEVRE DISI URUNLER: maliyet katmani KURULMAZ (posetler/ambalaj gibi maliyeti 0,
           alisi gider yazilan kalemler). Envanter snapshot'ta KALIR (#stoklarMekan dokunulmaz). */
        IF OBJECT_ID('dbo.FifoDevreDisiUrunler', 'U') IS NOT NULL
            DELETE FROM #stoklar
            WHERE StkId IN (SELECT StkId FROM dbo.FifoDevreDisiUrunler);

        DELETE FROM dbo.FifoAcilisEnvanter
        WHERE EnvanterTarihi = @EnvanterTarihi
          AND (@StkId IS NULL OR StkId = @StkId);

        INSERT INTO dbo.FifoAcilisEnvanter (EnvanterTarihi, MekanId, StkId, StokMiktar)
        SELECT @EnvanterTarihi, MekanId, StkId, StokMiktar
        FROM #stoklarMekan;

        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'TAMAMLANDI', NULL;
        PRINT '      Envanter tamamlandi.';

        SET @AdimKodu = 'acilis_alis';
        SET @AdimAdi = 'Alislar toplanir';
        SET @SiraNo = 20;
        PRINT '[2/4] Alislar toplaniyor (fat+fatAyr)...';
        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'CALISIYOR', NULL;

        /* 2) Baslangic-envanter arasi alislari cek (SADECE FATURA: fat + fatAyr) */
        IF OBJECT_ID('tempdb..#alislar', 'U') IS NOT NULL DROP TABLE #alislar;

        SELECT 
            a.ehStkId AS StkId,
            f.eTarihS AS GirisTarihi,
            f.eNo     AS BelgeNo,
            f.eTarihS AS BelgeTarihi,
            f.eFirma  AS FirmaId,
            SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS Miktar,
            SUM(CONVERT(DECIMAL(18,4),
                CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END
            )) AS netTutar
        INTO #alislar
        FROM #stoklar s
        JOIN DerinSIS_Local.dbo.fatAyr a WITH(NOLOCK)
            ON a.ehStkId = s.StkId
        JOIN DerinSIS_Local.dbo.fat f WITH(NOLOCK)
            ON f.eID = a.ehID
        WHERE a.ehAdetN <> 0
          AND f.eTarihS >  CONVERT(smalldatetime, @baslangicTarihi)
          AND f.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @EnvanterTarihi))
          AND f.eTip IN (0, 2)
          AND (@StkId IS NULL OR a.ehStkId = @StkId)
        GROUP BY a.ehStkId, f.eTarihS, f.eID, f.eNo, f.eFirma
        HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;

        ALTER TABLE #alislar ADD BirimMaliyet DECIMAL(18,6);

        UPDATE #alislar
        SET BirimMaliyet = CASE WHEN Miktar = 0 THEN 0 ELSE netTutar / Miktar END;

        CREATE INDEX IX_tmp_alislar_stkTarih 
            ON #alislar(StkId, GirisTarihi DESC, BelgeNo);

        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'TAMAMLANDI', NULL;
        PRINT '      Alislar tamamlandi.';

        SET @AdimKodu = 'acilis_katman';
        SET @AdimAdi = 'Ters FIFO katman';
        SET @SiraNo = 30;
        PRINT '[3/4] Ters FIFO katman hesaplaniyor...';
        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'CALISIYOR', NULL;

        /* 3) Ters FIFO ile acilis katmanlarini hesapla */
        IF OBJECT_ID('tempdb..#katman', 'U') IS NOT NULL DROP TABLE #katman;

        ;WITH Ters AS (
            SELECT
                StkId, GirisTarihi, BelgeNo, BelgeTarihi, FirmaId, Miktar, BirimMaliyet, netTutar,
                SUM(Miktar) OVER (
                    PARTITION BY StkId
                    ORDER BY GirisTarihi DESC, BelgeNo DESC
                    ROWS UNBOUNDED PRECEDING
                ) AS kumTers
            FROM #alislar
            WHERE Miktar > 0 AND netTutar > 0
        ),
        Acilis AS (
            SELECT
                t.StkId, t.GirisTarihi, t.BelgeNo, t.BelgeTarihi, t.FirmaId,
                t.Miktar AS satirMiktar, t.BirimMaliyet,
                t.kumTers, s.StokMiktar,
                CASE 
                    WHEN t.kumTers - t.Miktar >= s.StokMiktar THEN 0
                    WHEN t.kumTers <= s.StokMiktar THEN t.Miktar
                    ELSE s.StokMiktar - (t.kumTers - t.Miktar)
                END AS acilisMiktar
            FROM Ters t
            JOIN #stoklar s ON s.StkId = t.StkId
        )
        SELECT * INTO #katman FROM Acilis WHERE acilisMiktar > 0;

        /* 4) Acilis oncesi temizlik:
              - ACILIS/ACILIS_TAMAMLA: sadece envanter tarihi
              - AYLIK_DEVIR: baslangic-envanter arasi tum tarihler */
        DELETE FROM dbo.FifoKatman
        WHERE KaynakTip IN ('ACILIS', 'ACILIS_TAMAMLA')
          AND GirisTarihi = @EnvanterTarihi
          AND (@StkId IS NULL OR StkId = @StkId);

        DELETE FROM dbo.FifoKatman
        WHERE KaynakTip = 'AYLIK_DEVIR'
          AND GirisTarihi BETWEEN @baslangicTarihi AND @EnvanterTarihi
          AND (@StkId IS NULL OR StkId = @StkId);

        INSERT INTO dbo.FifoKatman
            (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
             GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
        SELECT
            StkId, @EnvanterTarihi, 'ACILIS', BelgeNo, BelgeTarihi, FirmaId,
            acilisMiktar, acilisMiktar, BirimMaliyet, 'NORMAL'
        FROM #katman;

        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'TAMAMLANDI', NULL;
        PRINT '      Katman hesaplamasc tamamlandi.';

        SET @AdimKodu = 'acilis_sorun';
        SET @AdimAdi = 'Sorun kaydi';
        SET @SiraNo = 40;
        PRINT '[4/4] Tamamlama + sorun kayitlari (merkez, son fiyat, aylik devir)...';
        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'CALISIYOR', NULL;

        /* 5) Eksik Miktarlari tespit et */
        ;WITH Ozet AS (
            SELECT StkId, SUM(acilisMiktar) AS toplamAcilisMiktar
            FROM #katman GROUP BY StkId
        ),
        AlisVarMi AS (
            SELECT DISTINCT StkId FROM #alislar
        )
        SELECT
            s.StkId, s.StokMiktar,
            ISNULL(o.toplamAcilisMiktar, 0) AS toplamAcilisMiktar,
            (s.StokMiktar - ISNULL(o.toplamAcilisMiktar, 0)) AS eksikMiktar
        INTO #eksiklar
        FROM #stoklar s
        LEFT JOIN Ozet o ON o.StkId = s.StkId
        LEFT JOIN AlisVarMi v ON v.StkId = s.StkId;

        /* 6) Alisc olan ama yetmeyenleri son alisla tamamla */
        ;WITH SonAlis AS (
            SELECT
                a.StkId, a.GirisTarihi, a.BelgeNo, a.BelgeTarihi, a.FirmaId, a.BirimMaliyet,
                ROW_NUMBER() OVER (
                    PARTITION BY a.StkId
                    ORDER BY a.GirisTarihi DESC, a.BelgeNo DESC
                ) AS rn
            FROM #alislar a
        )
        INSERT INTO dbo.FifoKatman
            (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
             GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
        SELECT
            e.StkId, @EnvanterTarihi, 'ACILIS_TAMAMLA', sa.BelgeNo, sa.BelgeTarihi, sa.FirmaId,
            e.eksikMiktar, e.eksikMiktar, sa.BirimMaliyet, 'TAMAMLAMA'
        FROM #eksiklar e
        JOIN SonAlis sa ON sa.StkId = e.StkId AND sa.rn = 1
        WHERE e.eksikMiktar > 0 AND e.toplamAcilisMiktar > 0;


        /* 7) Sorunlu kayitlari olustur */
        
        /* 6b) Merkez depo (12) alis faturalarc ile tamamlama (alis yoksa) - fat+fatAyr+irs (mekan icin) */
        IF OBJECT_ID('tempdb..#merkezAlis', 'U') IS NOT NULL DROP TABLE #merkezAlis;

        SELECT
            a.ehStkId AS StkId,
            f.eTarihS AS GirisTarihi,
            f.eNo     AS BelgeNo,
            f.eTarihS AS BelgeTarihi,
            f.eFirma  AS FirmaId,
            SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS Miktar,
            SUM(CONVERT(DECIMAL(18,4),
                CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END
            )) AS netTutar
        INTO #merkezAlis
        FROM #eksiklar e
        LEFT JOIN (SELECT DISTINCT StkId FROM #alislar) v ON v.StkId = e.StkId
        JOIN DerinSIS_Local.dbo.fatAyr a WITH(NOLOCK)
            ON a.ehStkId = e.StkId
        JOIN DerinSIS_Local.dbo.fat f WITH(NOLOCK)
            ON f.eID = a.ehID
        JOIN DerinSIS_Local.dbo.irs i WITH(NOLOCK)
            ON i.eID = a.ehIrsID
           AND i.eMekan = 12
        WHERE a.ehAdetN <> 0
          AND v.StkId IS NULL
          AND e.eksikMiktar > 0
          AND f.eTarihS >  CONVERT(smalldatetime, @baslangicTarihi)
          AND f.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @EnvanterTarihi))
          AND f.eTip IN (0, 2)
          AND (@StkId IS NULL OR a.ehStkId = @StkId)
        GROUP BY a.ehStkId, f.eTarihS, f.eID, f.eNo, f.eFirma
        HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;

        ALTER TABLE #merkezAlis ADD BirimMaliyet DECIMAL(18,6);
        UPDATE #merkezAlis
        SET BirimMaliyet = CASE WHEN Miktar = 0 THEN 0 ELSE netTutar / Miktar END;

        IF OBJECT_ID('tempdb..#merkezSon', 'U') IS NOT NULL DROP TABLE #merkezSon;

        ;WITH SonMerkez AS (
            SELECT
                m.StkId, m.GirisTarihi, m.BelgeNo, m.BelgeTarihi, m.FirmaId, m.BirimMaliyet,
                ROW_NUMBER() OVER (
                    PARTITION BY m.StkId
                    ORDER BY m.GirisTarihi DESC, m.BelgeNo DESC
                ) AS rn
            FROM #merkezAlis m
        )
        SELECT
            StkId, GirisTarihi, BelgeNo, BelgeTarihi, FirmaId, BirimMaliyet
        INTO #merkezSon
        FROM SonMerkez
        WHERE rn = 1;

        INSERT INTO dbo.FifoKatman
            (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
             GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
        SELECT
            e.StkId, @EnvanterTarihi, 'ACILIS_TAMAMLA', ms.BelgeNo, ms.BelgeTarihi, ms.FirmaId,
            e.eksikMiktar, e.eksikMiktar, ms.BirimMaliyet, 'MERKEZ_TAMAMLAMA'
        FROM #eksiklar e
        JOIN #merkezSon ms ON ms.StkId = e.StkId
        LEFT JOIN (SELECT DISTINCT StkId FROM #alislar) v ON v.StkId = e.StkId
        WHERE v.StkId IS NULL AND e.eksikMiktar > 0;

        /* 6c) Son gecerli fiyat ile tamamlama (alis yoksa, merkez de yoksa) */
        IF OBJECT_ID('tempdb..#sonGecerli', 'U') IS NOT NULL DROP TABLE #sonGecerli;

        ;WITH SonFiyat AS (
            SELECT
                f.fhID,
                f.fStkId AS StkId,
                f.fTarih,
                f.fTarihSon,
                f.sonrakiNet,
                ROW_NUMBER() OVER (
                    PARTITION BY f.fStkId
                    ORDER BY f.fTarihSon DESC, f.fhID DESC
                ) AS rn
            FROM DerinSIS_Local.bkm.fn_SonGecerliFiyat(@EnvanterTarihi, 1) f
            WHERE f.sonrakiNet > 0
        )
        SELECT
            StkId,
            fhID,
            fTarih,
            fTarihSon,
            sonrakiNet
        INTO #sonGecerli
        FROM SonFiyat
        WHERE rn = 1;

        INSERT INTO dbo.FifoKatman
            (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
             GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
        SELECT
            e.StkId,
            @EnvanterTarihi,
            'ACILIS_TAMAMLA',
            CAST(sg.fhID AS VARCHAR(50)),
            CAST(sg.fTarihSon AS DATE),
            NULL,
            e.eksikMiktar,
            e.eksikMiktar,
            sg.sonrakiNet,
            'SART_TAMAMLAMA'
        FROM #eksiklar e
        JOIN #sonGecerli sg ON sg.StkId = e.StkId
        LEFT JOIN (SELECT DISTINCT StkId FROM #alislar) v ON v.StkId = e.StkId
        LEFT JOIN #merkezSon ms ON ms.StkId = e.StkId
        WHERE v.StkId IS NULL
          AND ms.StkId IS NULL
          AND e.eksikMiktar > 0;

        /* 6d) Aylik devir ile tamamlama (alis/merkez/sart yoksa) - @atlamaAylikDevir=1 ise atlanAr (timeout onleme) */
        IF OBJECT_ID('tempdb..#eksikKalan', 'U') IS NOT NULL DROP TABLE #eksikKalan;

        SELECT e.StkId, e.eksikMiktar
        INTO #eksikKalan
        FROM #eksiklar e
        LEFT JOIN (SELECT DISTINCT StkId FROM #alislar) v ON v.StkId = e.StkId
        LEFT JOIN #merkezSon ms ON ms.StkId = e.StkId
        LEFT JOIN #sonGecerli sg ON sg.StkId = e.StkId
        WHERE e.eksikMiktar > 0 AND v.StkId IS NULL AND ms.StkId IS NULL AND sg.StkId IS NULL;

        IF OBJECT_ID('tempdb..#aylikKatman', 'U') IS NOT NULL DROP TABLE #aylikKatman;
        CREATE TABLE #aylikKatman (
            StkId INT NOT NULL,
            ayBitis DATE NOT NULL,
            ayMiktar DECIMAL(18,4) NOT NULL,
            BirimMaliyet DECIMAL(18,6) NULL,
            Durum VARCHAR(20) NOT NULL
        );

        IF @atlamaAylikDevir = 1
        BEGIN
            PRINT '      (Aylik devir atlandi - @atlamaAylikDevir=1)';
        END
        ELSE IF EXISTS (SELECT 1 FROM #eksikKalan)
        BEGIN
            IF OBJECT_ID('tempdb..#aylar', 'U') IS NOT NULL DROP TABLE #aylar;

            ;WITH Aylar AS (
                SELECT
                    ayBas = DATEFROMPARTS(YEAR(@EnvanterTarihi), MONTH(@EnvanterTarihi), 1),
                    ayBitis = EOMONTH(@EnvanterTarihi)
                UNION ALL
                SELECT
                    DATEADD(MONTH, -1, ayBas),
                    EOMONTH(DATEADD(MONTH, -1, ayBas))
                FROM Aylar
                WHERE DATEADD(MONTH, -1, ayBas) >= DATEFROMPARTS(YEAR(@baslangicTarihi), MONTH(@baslangicTarihi), 1)
            )
            SELECT ayBas, ayBitis
            INTO #aylar
            FROM Aylar
            OPTION (MAXRECURSION 0);

            IF OBJECT_ID('tempdb..#aylikStok', 'U') IS NOT NULL DROP TABLE #aylikStok;
            CREATE TABLE #aylikStok (
                StkId INT NOT NULL,
                ayBitis DATE NOT NULL,
                ayStok DECIMAL(18,4) NOT NULL
            );

            /* irsHrk ile gecmis stok - tek sorgu, mekan bazli toplam */
            INSERT INTO #aylikStok (StkId, ayBitis, ayStok)
            SELECT
                h.ehStkId AS StkId,
                a.ayBitis,
                SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) AS ayStok
            FROM DerinSIS_Local.dbo.irsHrk h WITH(NOLOCK)
            JOIN #aylar a ON h.ehTrhS <= DATEADD(DAY, 1, a.ayBitis)
            JOIN #eksikKalan e ON e.StkId = h.ehStkId
            WHERE h.ehAltDepo = 0
              AND h.ehMekan IN (1, 12, 4477, 4478)
            GROUP BY h.ehStkId, a.ayBitis
            HAVING SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) > 0;

            IF OBJECT_ID('tempdb..#aylikAlloc', 'U') IS NOT NULL DROP TABLE #aylikAlloc;

            ;WITH Aylik AS (
                SELECT
                    s.StkId, s.ayBitis, s.ayStok,
                    SUM(s.ayStok) OVER (
                        PARTITION BY s.StkId
                        ORDER BY s.ayBitis DESC
                        ROWS UNBOUNDED PRECEDING
                    ) AS kumStok
                FROM #aylikStok s
            ),
            Alloc AS (
                SELECT
                    a.StkId, a.ayBitis,
                    CAST(
                        CASE
                            WHEN a.kumStok <= e.eksikMiktar THEN a.ayStok
                            WHEN a.kumStok - a.ayStok < e.eksikMiktar THEN e.eksikMiktar - (a.kumStok - a.ayStok)
                            ELSE 0
                        END AS DECIMAL(18,4)
                    ) AS ayMiktar
                FROM Aylik a
                JOIN #eksikKalan e ON e.StkId = a.StkId
            )
            SELECT * INTO #aylikAlloc FROM Alloc WHERE ayMiktar > 0;

            IF OBJECT_ID('tempdb..#sabitFiyat', 'U') IS NOT NULL DROP TABLE #sabitFiyat;
            CREATE TABLE #sabitFiyat (
                StkId INT NOT NULL,
                BirimMaliyet DECIMAL(18,6) NOT NULL
            );

            -- ERP Devir Fiyatlari tablosundan fiyat al (satinalma serti ile)
            IF OBJECT_ID('dbo.FifoFallbackFiyatlari', 'U') IS NOT NULL
            BEGIN
                DECLARE @sqlErpDevir NVARCHAR(MAX) = N'
                INSERT INTO #sabitFiyat (StkId, BirimMaliyet)
                SELECT erp.StkId, erp.BirimMaliyet
                FROM dbo.FifoFallbackFiyatlari erp
                WHERE (@StkId IS NULL OR erp.StkId = @StkId)
                  AND (@fallbackSatinalmaSarti IS NULL OR erp.SatinalmaSarti = @fallbackSatinalmaSarti);';

                EXEC sp_executesql
                    @sqlErpDevir,
                    N'@StkId INT, @fallbackSatinalmaSarti VARCHAR(50)',
                    @StkId = @StkId,
                    @fallbackSatinalmaSarti = @fallbackSatinalmaSarti;
            END

            /* V2-07: fn_SonGecerliFiyat_Adv materialize
               Eski: OUTER APPLY row-by-row (urun*ay adet cagri)
               Yeni: TVF tarih basina 1 kez cagirilir → LEFT JOIN
               Kazanim: N_urun*N_ay → N_ay adet TVF cagri */
            IF OBJECT_ID('tempdb..#fiyatMaterialize', 'U') IS NOT NULL DROP TABLE #fiyatMaterialize;
            CREATE TABLE #fiyatMaterialize (
                StkId      INT            NOT NULL,
                ayBitis    DATE           NOT NULL,
                sonrakiNet DECIMAL(18,6)  NOT NULL,
                fFrmID     INT            NULL,
                fTarihSon  DATE           NULL,
                fhID       INT            NULL,
                CONSTRAINT PK_tmp_fiyatMat PRIMARY KEY (StkId, ayBitis)
            );

            DECLARE @matTarih DATE;
            DECLARE matCur CURSOR LOCAL FAST_FORWARD FOR
                SELECT DISTINCT ayBitis FROM #aylikAlloc ORDER BY ayBitis;
            OPEN matCur;
            FETCH NEXT FROM matCur INTO @matTarih;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                INSERT INTO #fiyatMaterialize (StkId, ayBitis, sonrakiNet, fFrmID, fTarihSon, fhID)
                SELECT f.fStkId, @matTarih, f.sonrakiNet, f.fFrmID, f.fTarihSon, f.fhID
                FROM (
                    SELECT
                        f.fStkId, f.sonrakiNet, f.fFrmID, f.fTarihSon, f.fhID,
                        ROW_NUMBER() OVER (
                            PARTITION BY f.fStkId
                            ORDER BY
                                CASE WHEN f.fFrmID = 9525 THEN 0 ELSE 1 END,
                                f.fTarihSon DESC,
                                f.fhID DESC
                        ) AS rn
                    FROM DerinSIS_Local.bkm.fn_SonGecerliFiyat_Adv(@matTarih, 1, 1, 1) f
                    WHERE f.fStkId IN (SELECT StkId FROM #aylikAlloc WHERE ayBitis = @matTarih)
                      AND f.sonrakiNet > 0
                      -- 14_V2 ile hizalandi (2026-06-06): stale fiyat KABUL edilir.
                      -- (Eski fTarihSon>=@matTarih reddi kaldirildi — iki SP ayni sonucu versin.)
                ) f WHERE f.rn = 1;
                FETCH NEXT FROM matCur INTO @matTarih;
            END
            CLOSE matCur; DEALLOCATE matCur;

            INSERT INTO #aylikKatman (StkId, ayBitis, ayMiktar, BirimMaliyet, Durum)
            SELECT
                a.StkId,
                a.ayBitis,
                a.ayMiktar,
                COALESCE(fm.sonrakiNet, sf.BirimMaliyet) AS BirimMaliyet,
                CASE
                    WHEN COALESCE(fm.sonrakiNet, sf.BirimMaliyet) IS NULL THEN 'FIYAT_YOK'
                    ELSE 'AYLIK_DEVIR'
                END AS Durum
            FROM #aylikAlloc a
            LEFT JOIN #fiyatMaterialize fm ON fm.StkId = a.StkId AND fm.ayBitis = a.ayBitis
            LEFT JOIN #sabitFiyat       sf ON sf.StkId = a.StkId;

            IF @sabitFallbackBirimMaliyet IS NOT NULL
            BEGIN
                UPDATE k
                SET
                    k.BirimMaliyet = @sabitFallbackBirimMaliyet,
                    k.Durum = 'SABIT_FIYAT_TAMAMLAMA'
                FROM #aylikKatman k
                WHERE k.Durum = 'FIYAT_YOK';
            END

            INSERT INTO dbo.FifoKatman
            (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
                 GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
            SELECT
                k.StkId, k.ayBitis, 'AYLIK_DEVIR', NULL, k.ayBitis, NULL,
                k.ayMiktar, k.ayMiktar, ISNULL(k.BirimMaliyet, 0), k.Durum
            FROM #aylikKatman k
            WHERE k.BirimMaliyet IS NOT NULL
              AND k.BirimMaliyet > 0;
        END

        DELETE FROM dbo.FifoSorunluStoklar
        WHERE EnvanterTarihi = @EnvanterTarihi
          AND (@StkId IS NULL OR StkId = @StkId);

        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT
            k.StkId, @EnvanterTarihi, SUM(k.ayMiktar), 'FIYAT_YOK',
            'Aylik devir katmaninda fiyat bulunamadi.'
        FROM #aylikKatman k
        WHERE k.Durum = 'FIYAT_YOK'
        GROUP BY k.StkId;

        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT
            k.StkId, @EnvanterTarihi, SUM(k.ayMiktar), 'SABIT_FIYAT_TAMAMLANDI',
            'Aylik devir katmani sabit fiyat ile tamamlandi. Fiyat=' +
            CONVERT(VARCHAR(30), @sabitFallbackBirimMaliyet)
        FROM #aylikKatman k
        WHERE k.Durum = 'SABIT_FIYAT_TAMAMLAMA'
        GROUP BY k.StkId;

        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT
            s.StkId, @EnvanterTarihi, s.StokMiktar, 'ALIS_YOK',
            'Bu urune belirtilen tarih araliginda hic alis bulunamadi.'
        FROM #stoklar s
        LEFT JOIN (SELECT DISTINCT StkId FROM #alislar) v ON v.StkId = s.StkId
        LEFT JOIN #merkezSon ms ON ms.StkId = s.StkId
        LEFT JOIN #sonGecerli sg ON sg.StkId = s.StkId
        LEFT JOIN (SELECT DISTINCT StkId FROM #aylikKatman) ak ON ak.StkId = s.StkId
        WHERE v.StkId IS NULL AND ms.StkId IS NULL AND sg.StkId IS NULL AND ak.StkId IS NULL;


        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT
            e.StkId, @EnvanterTarihi, e.StokMiktar, 'ALIS_YOK_MERKEZ_TAMAMLANDI',
            'Merkez depo (12) son alis fiyati ile tamamlandi.'
        FROM #eksiklar e
        JOIN #merkezSon ms ON ms.StkId = e.StkId;

        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT
            e.StkId, @EnvanterTarihi, e.StokMiktar, 'ALIS_YOK_SONGECERLI_TAMAMLANDI',
            'Son gecerli satin alma fiyati (sonrakiNet) ile tamamlandi.'
        FROM #eksiklar e
        JOIN #sonGecerli sg ON sg.StkId = e.StkId
        LEFT JOIN (SELECT DISTINCT StkId FROM #alislar) v ON v.StkId = e.StkId
        LEFT JOIN #merkezSon ms ON ms.StkId = e.StkId
        WHERE v.StkId IS NULL AND ms.StkId IS NULL;

        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT DISTINCT
            e.StkId, @EnvanterTarihi, e.StokMiktar, 'ALIS_EKSIK_TAMAMLANDI',
            'Eksik stok son alis fiyati ile otomatik tamamlandi.'
        FROM #eksiklar e
        WHERE e.eksikMiktar > 0 AND e.toplamAcilisMiktar > 0;

        /* NET GUVENLIK AGI (invariant): acilis envanterine giren her StkId
           YA bir FifoKatman almali YA da bir sorun kaydi. Aylik-devir bloku
           atlanirsa (@atlamaAylikDevir=1) veya eslik/eksik kenar durumlarinda
           urun sessizce dusebiliyordu (ne katman ne FIYAT_YOK). Bu net dogrudan
           FifoKatman'a karsi dogrular — aylik-devir durumundan bagimsiz.
           Ref: sorunlu-urun-dedektif + sql-sp-reviewer CRIT-1 (2026-06-06). */
        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT s.StkId, @EnvanterTarihi, s.StokMiktar, 'FIYAT_YOK',
               'Acilis envanteri var; alis/merkez/sart/aylik-devir hicbiri katman kuramadi (net guvenlik agi).'
        FROM #stoklar s
        WHERE (@StkId IS NULL OR s.StkId = @StkId)
          AND NOT EXISTS (
              SELECT 1 FROM dbo.FifoKatman k
              WHERE k.StkId = s.StkId
                AND k.GirisTarihi BETWEEN @baslangicTarihi AND @EnvanterTarihi
          )
          AND NOT EXISTS (
              SELECT 1 FROM dbo.FifoSorunluStoklar fs
              WHERE fs.StkId = s.StkId AND fs.EnvanterTarihi = @EnvanterTarihi
                AND fs.SorunTipi IN ('FIYAT_YOK','ALIS_YOK')
          );

        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'TAMAMLANDI', NULL;

        /* Audit triggeri tekrar etkinlestir */
        IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'tr_fifo_StokMaliyetHavuzu_DegisimGunlugu' AND parent_id = OBJECT_ID('dbo.FifoKatman'))
            ALTER TABLE dbo.FifoKatman ENABLE TRIGGER tr_fifo_StokMaliyetHavuzu_DegisimGunlugu;
        ELSE IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'tr_fifo_StokMaliyetHavuzu_Audit' AND parent_id = OBJECT_ID('dbo.FifoKatman'))
            ALTER TABLE dbo.FifoKatman ENABLE TRIGGER tr_fifo_StokMaliyetHavuzu_Audit;

        COMMIT TRANSACTION;
        
        PRINT 'Acilis stoku basariyla olusturuldu. Tarih: ' + 
              CONVERT(VARCHAR(10), @EnvanterTarihi, 120);
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        /* Hata Durumunda rollback sonrasinda triggeri tekrar etkinlestir */
        IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'tr_fifo_StokMaliyetHavuzu_DegisimGunlugu' AND parent_id = OBJECT_ID('dbo.FifoKatman'))
            ALTER TABLE dbo.FifoKatman ENABLE TRIGGER tr_fifo_StokMaliyetHavuzu_DegisimGunlugu;
        ELSE IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'tr_fifo_StokMaliyetHavuzu_Audit' AND parent_id = OBJECT_ID('dbo.FifoKatman'))
            ALTER TABLE dbo.FifoKatman ENABLE TRIGGER tr_fifo_StokMaliyetHavuzu_Audit;
            
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @runMessage VARCHAR(500) = SUBSTRING(CONVERT(VARCHAR(500), @ErrorMessage), 1, 500);

        IF @IslemId IS NOT NULL AND @AdimKodu IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz
                @IslemId = @IslemId,
                @AdimKodu = @AdimKodu,
                @AdimAdi = @AdimAdi,
                @SiraNo = @SiraNo,
                @Durum = 'HATA',
                @Mesaj = @runMessage;
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        DECLARE @ErrorLine INT = ERROR_LINE();
        
        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        VALUES (0, @EnvanterTarihi, 0, 'PROSEDUR_HATASI', 
                'sp_Fifo_AcilisMaliyetlendir - Satir: ' + CAST(@ErrorLine AS VARCHAR(10)) + 
                ' - ' + @ErrorMessage);
        
        THROW;
    END CATCH
END
GO

PRINT 'sp_Fifo_AcilisMaliyetlendir proseduru olusturuldu';
GO

PRINT '';

PRINT '3/6 - Alis katmanlari proseduru olusturuluyor...';
GO

-- =============================================================
-- ALIS KATMANLARI PROSEDURU - dbo.sp_Fifo_AlisKatmanEkle
-- SADECE FATURA: fat + fatAyr (irs/irsAyr yok)
-- =============================================================

CREATE OR ALTER PROCEDURE dbo.sp_Fifo_AlisKatmanEkle
(
    @baslangicTarihi DATE,
    @bitisTarihi DATE,
    @StkId INT = NULL,
    @IslemId UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    -- Parametre validasyonu
    IF @baslangicTarihi IS NULL OR @bitisTarihi IS NULL
    BEGIN
        RAISERROR('Tarih parametreleri bos olamaz', 16, 1);
        RETURN;
    END
    
    IF @baslangicTarihi > @bitisTarihi
    BEGIN
        RAISERROR('Baslangic tarihi bitis tarihinden buyuk olamaz', 16, 1);
        RETURN;
    END
    
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('tempdb..#alislar', 'U') IS NOT NULL DROP TABLE #alislar;

        /* Verilen tarih araligindaki alislari cek (SADECE FATURA: fat + fatAyr) */
        SELECT 
            a.ehStkId AS StkId,
            f.eTarihS AS GirisTarihi,
            f.eNo     AS BelgeNo,
            f.eTarihS AS BelgeTarihi,
            f.eFirma  AS FirmaId,
            SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS Miktar,
            SUM(CONVERT(DECIMAL(18,4),
                CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END
            )) AS netTutar
        INTO #alislar
        FROM DerinSIS_Local.dbo.fatAyr a WITH(NOLOCK)
        JOIN DerinSIS_Local.dbo.fat f WITH(NOLOCK)
            ON f.eID = a.ehID
        WHERE a.ehAdetN <> 0
          AND f.eTarihS >  CONVERT(smalldatetime, @baslangicTarihi)
          AND f.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @bitisTarihi))
          AND f.eTip IN (0, 2)
          AND (@StkId IS NULL OR a.ehStkId = @StkId)
        GROUP BY a.ehStkId, f.eTarihS, f.eID, f.eNo, f.eFirma
        HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;

        /* Birim maliyet hesapla */
        ALTER TABLE #alislar ADD BirimMaliyet DECIMAL(18,6);

        UPDATE #alislar
        SET BirimMaliyet = CASE WHEN Miktar = 0 THEN 0 ELSE netTutar / Miktar END;

        -- Constraint uyumsuz (iade/ters/fiyatsiz) satirlari ALIS havuzuna yazma.
        DELETE FROM #alislar
        WHERE Miktar <= 0
           OR netTutar <= 0
           OR BirimMaliyet <= 0;

        /* Aync tarih araligindaki eski ALIS katmanlarini sil */
        DELETE FROM dbo.FifoKatman
        WHERE KaynakTip = 'ALIS'
          AND GirisTarihi >  @baslangicTarihi
          AND GirisTarihi <= @bitisTarihi
          AND (@StkId IS NULL OR StkId = @StkId);

        /* Yeni ALIS katmanlarini havuza yaz */
        INSERT INTO dbo.FifoKatman
            (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
             GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
        SELECT
            StkId, GirisTarihi, 'ALIS', BelgeNo, BelgeTarihi, FirmaId,
            Miktar, Miktar, BirimMaliyet, 'NORMAL'
        FROM #alislar;

        COMMIT TRANSACTION;
        
        PRINT 'Alis katmanlari basariyla olusturuldu. Tarih araligi: ' + 
              CONVERT(VARCHAR(10), @baslangicTarihi, 120) + ' - ' + 
              CONVERT(VARCHAR(10), @bitisTarihi, 120);
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @runMessage VARCHAR(500) = SUBSTRING(CONVERT(VARCHAR(500), @ErrorMessage), 1, 500);
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        
        THROW;
    END CATCH
END
GO

PRINT 'sp_Fifo_AlisKatmanEkle proseduru olusturuldu';
GO

PRINT '';

PRINT '4/6 - FIFO cikis proseduru olusturuluyor...';
GO

-- =============================================================
-- FIFO CIKIS PROSEDURU - dbo.sp_Fifo_CikisMaliyetle
-- POS iade mantigi, KalanMiktar guncelleme, yetersiz stok kontrolu ile
-- =============================================================

CREATE OR ALTER PROCEDURE dbo.sp_Fifo_CikisMaliyetle
(
    @satisBaslangic DATE,
    @satisBitis DATE,
    @StkId INT = NULL,
    @IslemId UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    -- Parametre validasyonu
    IF @satisBaslangic IS NULL OR @satisBitis IS NULL
    BEGIN
        RAISERROR('Tarih parametreleri bos olamaz', 16, 1);
        RETURN;
    END
    
    IF @satisBaslangic > @satisBitis
    BEGIN
        RAISERROR('Baslangic tarihi bitis tarihinden buyuk olamaz', 16, 1);
        RETURN;
    END
    
    BEGIN TRY
        BEGIN TRANSACTION;

        /* RERUN-SAFE (V2): Ayni donem daha once hesaplandiysa eski cikis tuketimini havuza geri yukle.
           Not: Gec donemler hesaplandiysa gecmise donuk rerun yine risklidir; son/cari donem rerun hedeflenir. */
        UPDATE h
        SET h.KalanMiktar = h.KalanMiktar + d.toplamCikis
        FROM dbo.FifoKatman h
        JOIN (
            SELECT c.KatmanId, SUM(c.Miktar) AS toplamCikis
            FROM dbo.FifoCikisDetay c
            WHERE c.HareketTarihi >= @satisBaslangic
              AND c.HareketTarihi <= @satisBitis
              AND (@StkId IS NULL OR c.StkId = @StkId)
            GROUP BY c.KatmanId
        ) d ON d.KatmanId = h.KatmanId;

        -- RERUN-SAFE: Onceki calismadan kalan IADE katmanlarini sil (rerun'da birikmemeli)
        DELETE FROM dbo.FifoKatman
        WHERE KaynakTip = 'IADE'
          AND GirisTarihi >= @satisBaslangic
          AND GirisTarihi <= @satisBitis
          AND (@StkId IS NULL OR StkId = @StkId);

        /* 1) Havuzdaki tum katmanlari al */
        IF OBJECT_ID('tempdb..#katman', 'U') IS NOT NULL DROP TABLE #katman;

        SELECT
            h.KatmanId AS KatmanId, h.StkId, h.GirisTarihi,
            ISNULL(h.BelgeTarihi, h.GirisTarihi) AS fifoSiraTarihi,
            h.BelgeNo AS girisBelgeNo,
            TRY_CONVERT(BIGINT, h.BelgeNo) AS fifoSiraBelgeNoNum,
            h.KalanMiktar AS GirisMiktar,
            h.BirimMaliyet
        INTO #katman
        FROM dbo.FifoKatman h
        WHERE h.GirisTarihi <= @satisBitis
          -- Only include sources that are actually written by this deployment.
          AND h.KaynakTip IN ('ACILIS','ACILIS_TAMAMLA','ALIS','AYLIK_DEVIR','SENTETIK_ALIS','IADE')
          AND h.KalanMiktar > 0
          AND (@StkId IS NULL OR h.StkId = @StkId);

        CREATE INDEX IX_tmp_katman_StkId
            ON #katman(StkId, fifoSiraTarihi, fifoSiraBelgeNoNum, girisBelgeNo, KatmanId);

        /* 2) Satis hareketlerini al - POS IADE MANTIGI ILE */
        IF OBJECT_ID('tempdb..#satislar', 'U') IS NOT NULL DROP TABLE #satislar;

        SELECT
            ID = IDENTITY(INT,1,1),
            h.ehstkID AS StkId,
            h.ehMekan AS MekanId,
            CAST(h.ehTrhS AS DATE) AS satisTarihi,
            netMiktar = SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)),
            netTutar  = SUM(CONVERT(DECIMAL(18,4), h.ehTutarN))
        INTO #satislar
        FROM DerinSIS_Local.dbo.irsHrk h
        WHERE h.ehTip IN (1,4,5,100,101)
          AND h.ehMekan IN (1, 12, 4477, 4478)
          AND h.ehTrhS >= CONVERT(smalldatetime, @satisBaslangic)
          AND h.ehTrhS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @satisBitis))
          AND (@StkId IS NULL OR h.ehstkID = @StkId)
        GROUP BY h.ehstkID, h.ehMekan, CAST(h.ehTrhS AS DATE);

        CREATE INDEX IX_tmp_satislar_StkId
            ON #satislar(StkId, satisTarihi, MekanId, ID);

        /* 3) Katmanlar icin kumulatif */
        IF OBJECT_ID('tempdb..#katmanCum', 'U') IS NOT NULL DROP TABLE #katmanCum;

        SELECT
            k.KatmanId, k.StkId, k.GirisTarihi, k.fifoSiraTarihi, k.girisBelgeNo, k.fifoSiraBelgeNoNum,
            k.GirisMiktar, k.BirimMaliyet,
            layerCumEnd = SUM(k.GirisMiktar) OVER (
                PARTITION BY k.StkId
                ORDER BY
                    k.fifoSiraTarihi,
                    CASE WHEN k.fifoSiraBelgeNoNum IS NULL THEN 1 ELSE 0 END,
                    k.fifoSiraBelgeNoNum,
                    k.girisBelgeNo,
                    k.KatmanId
            ),
            layerCumStart = SUM(k.GirisMiktar) OVER (
                PARTITION BY k.StkId
                ORDER BY
                    k.fifoSiraTarihi,
                    CASE WHEN k.fifoSiraBelgeNoNum IS NULL THEN 1 ELSE 0 END,
                    k.fifoSiraBelgeNoNum,
                    k.girisBelgeNo,
                    k.KatmanId
            ) - k.GirisMiktar
        INTO #katmanCum
        FROM #katman k;

        CREATE INDEX IX_tmp_katmanCum_StkId
            ON #katmanCum(StkId, layerCumStart, layerCumEnd);

        /* 4) Satislar icin kumulatif (sadece net satis = netMiktar < 0) */
        IF OBJECT_ID('tempdb..#satisCum', 'U') IS NOT NULL DROP TABLE #satisCum;

        SELECT
            s.ID AS satisID, s.StkId, s.MekanId, s.satisTarihi,
            s.netMiktar AS Miktar,
            satisCumEnd = SUM(ABS(s.netMiktar)) OVER (
                PARTITION BY s.StkId
                ORDER BY s.satisTarihi, s.MekanId, s.ID
            ),
            satisCumStart = SUM(ABS(s.netMiktar)) OVER (
                PARTITION BY s.StkId
                ORDER BY s.satisTarihi, s.MekanId, s.ID
            ) - ABS(s.netMiktar)
        INTO #satisCum
        FROM #satislar s
        WHERE s.netMiktar < 0;  -- iade (netMiktar > 0) FIFO kesisimine girmiyor

        CREATE INDEX IX_tmp_satisCum_StkId
            ON #satisCum(StkId, satisCumStart, satisCumEnd);

        /* 5) FIFO kesisim */
        IF OBJECT_ID('tempdb..#cikisDetay', 'U') IS NOT NULL DROP TABLE #cikisDetay;

        SELECT
            c.StkId, c.MekanId AS satisMekanId, c.satisTarihi, c.satisID,
            c.Miktar AS satirNetMiktar,
            l.KatmanId, l.GirisTarihi AS KatmanTarihi,
            l.girisBelgeNo, l.BirimMaliyet,
            cikisMiktar = CAST(
                CASE 
                    WHEN l.layerCumEnd <= c.satisCumStart 
                      OR c.satisCumEnd <= l.layerCumStart THEN 0
                    ELSE
                        (CASE WHEN l.layerCumEnd < c.satisCumEnd 
                              THEN l.layerCumEnd ELSE c.satisCumEnd END)
                      - (CASE WHEN l.layerCumStart > c.satisCumStart 
                              THEN l.layerCumStart ELSE c.satisCumStart END)
                END
            AS DECIMAL(18,4))
        INTO #cikisDetay
        FROM #satisCum c
        JOIN #katmanCum l
          ON l.StkId = c.StkId
         AND l.layerCumEnd > c.satisCumStart
         AND c.satisCumEnd > l.layerCumStart;

        DELETE FROM #cikisDetay WHERE cikisMiktar <= 0;

        /* 6a) IADE KATMANI AC (netMiktar > 0 = stok geri donuyor)
               Mantik: en son satisten geriye FIFO gibi, iade miktarini karsilayana kadar.
               Her segment icin ayri FifoKatman satirı (o segmentin BirimMaliyet'i). */

        -- Iade hareketleri (gun+mekan bazinda net pozitif)
        IF OBJECT_ID('tempdb..#iade_hrk', 'U') IS NOT NULL DROP TABLE #iade_hrk;
        SELECT
            ID        = IDENTITY(INT,1,1),
            s.StkId,
            s.MekanId,
            iadeTarihi = s.satisTarihi,
            iadeMiktar = s.netMiktar
        INTO #iade_hrk
        FROM #satislar s
        WHERE s.netMiktar > 0;

        -- Iade kumulatif (StkId bazinda)
        IF OBJECT_ID('tempdb..#iade_cum', 'U') IS NOT NULL DROP TABLE #iade_cum;
        SELECT
            i.ID, i.StkId, i.MekanId, i.iadeTarihi, i.iadeMiktar,
            iadeCumEnd   = SUM(i.iadeMiktar) OVER (PARTITION BY i.StkId ORDER BY i.iadeTarihi, i.MekanId, i.ID),
            iadeCumStart = SUM(i.iadeMiktar) OVER (PARTITION BY i.StkId ORDER BY i.iadeTarihi, i.MekanId, i.ID) - i.iadeMiktar
        INTO #iade_cum
        FROM #iade_hrk i;

        -- Satis cikislari: bu SP'nin #cikisDetay'indan al (FifoCikisDetay henuz yazilmamis olabilir)
        -- Her iade icin kendi tarihine kadar, en yeniden eskiye, kumulatif
        IF OBJECT_ID('tempdb..#satis_katman', 'U') IS NOT NULL DROP TABLE #satis_katman;
        SELECT
            ic.ID AS iadeID,
            cd.StkId, cd.satisTarihi AS HareketTarihi, cd.BirimMaliyet,
            cd.cikisMiktar AS Miktar,
            layerCumEnd   = SUM(cd.cikisMiktar) OVER (
                PARTITION BY cd.StkId, ic.ID
                ORDER BY cd.satisTarihi DESC, cd.satisID DESC, cd.KatmanId DESC),
            layerCumStart = SUM(cd.cikisMiktar) OVER (
                PARTITION BY cd.StkId, ic.ID
                ORDER BY cd.satisTarihi DESC, cd.satisID DESC, cd.KatmanId DESC
            ) - cd.cikisMiktar
        INTO #satis_katman
        FROM #iade_hrk ic
        JOIN #cikisDetay cd
          ON cd.StkId        = ic.StkId
         AND cd.satisTarihi <= ic.iadeTarihi;

        -- FIFO kesisim: iade miktari <-> satis katmanlari (en yeniden, tarih filtreli)
        IF OBJECT_ID('tempdb..#iade_kesisim', 'U') IS NOT NULL DROP TABLE #iade_kesisim;
        SELECT
            ic.StkId, ic.MekanId, ic.iadeTarihi,
            sk.BirimMaliyet,
            kesisenMiktar = CAST(
                CASE
                    WHEN sk.layerCumEnd <= ic.iadeCumStart
                      OR ic.iadeCumEnd <= sk.layerCumStart THEN 0
                    ELSE
                        (CASE WHEN sk.layerCumEnd < ic.iadeCumEnd
                              THEN sk.layerCumEnd ELSE ic.iadeCumEnd END)
                      - (CASE WHEN sk.layerCumStart > ic.iadeCumStart
                              THEN sk.layerCumStart ELSE ic.iadeCumStart END)
                END AS DECIMAL(18,4))
        INTO #iade_kesisim
        FROM #iade_cum ic
        JOIN #satis_katman sk
          ON sk.StkId   = ic.StkId
         AND sk.iadeID  = ic.ID
         AND sk.layerCumEnd  > ic.iadeCumStart
         AND ic.iadeCumEnd   > sk.layerCumStart;

        DELETE FROM #iade_kesisim WHERE kesisenMiktar <= 0;

        -- Karsilanamayan iade miktari icin fallback (sifir maliyet yerine 0 koyma, log icin)
        -- TODO: FifoSorunluStoklar'a 'IADE_KARSILANAMADI' eklenebilir

        INSERT INTO dbo.FifoKatman
            (StkId, KaynakTip, GirisTarihi, BelgeTarihi, BelgeNo,
             GirisMiktar, KalanMiktar, BirimMaliyet)
        SELECT
            ik.StkId,
            'IADE',
            ik.iadeTarihi,
            ik.iadeTarihi,
            NULL,
            ik.kesisenMiktar,
            ik.kesisenMiktar,
            ik.BirimMaliyet
        FROM #iade_kesisim ik;

        /* 6) YETERSIZ STOK KONTROLU */
        DELETE FROM dbo.FifoSorunluStoklar
        WHERE SorunTipi = 'STOK_YETERSIZ'
          AND EnvanterTarihi >= @satisBaslangic
          AND EnvanterTarihi <= @satisBitis
          AND (@StkId IS NULL OR StkId = @StkId);

        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT
            s.StkId,
            @satisBitis,
            s.toplamSatisMiktar - ISNULL(d.toplamKarsilananMiktar, 0) AS eksikMiktar,
            'STOK_YETERSIZ',
            'Donem satis Miktari (' + CAST(s.toplamSatisMiktar AS VARCHAR(20)) +
            ') mevcut katmanlarla karsilanan Miktari (' + CAST(ISNULL(d.toplamKarsilananMiktar, 0) AS VARCHAR(20)) +
            ') asiyor.'
        FROM (
            SELECT
                StkId,
                SUM(ABS(netMiktar)) AS toplamSatisMiktar
            FROM #satislar
            WHERE netMiktar <> 0
            GROUP BY StkId
        ) s
        LEFT JOIN (
            SELECT
                StkId,
                SUM(ABS(cikisMiktar)) AS toplamKarsilananMiktar
            FROM #cikisDetay
            GROUP BY StkId
        ) d ON d.StkId = s.StkId
        WHERE s.toplamSatisMiktar > ISNULL(d.toplamKarsilananMiktar, 0);

        /* 7) SONUCLARI TABLOYA YAZ */
        DELETE FROM dbo.FifoCikisDetay
        WHERE HareketTarihi >= @satisBaslangic
          AND HareketTarihi <= @satisBitis
          AND (@StkId IS NULL OR StkId = @StkId);

        INSERT INTO dbo.FifoCikisDetay
            (StkId, HareketTarihi, HareketTipi, MekanId, KatmanId,
             KatmanTarihi, KatmanBelgeNo, Miktar, BirimMaliyet, SatisTutar)
        SELECT
            d.StkId, d.satisTarihi,
            'SATIS',
            d.satisMekanId,
            d.KatmanId, d.KatmanTarihi, d.girisBelgeNo,
            d.cikisMiktar, d.BirimMaliyet,
            /* Gunun satis geliri (irsHrk ehTutarN) cikis segmentine miktar oraninda dagitilir */
            CAST(d.cikisMiktar * (s.netTutar / NULLIF(ABS(s.netMiktar), 0)) AS DECIMAL(18,4))
        FROM #cikisDetay d
        JOIN #satislar s ON s.ID = d.satisID;

        /* 8) KATMAN KALAN MIKTARLARINI GUNCELLE */
        UPDATE h
        SET h.KalanMiktar = h.KalanMiktar - d.toplamCikis
        FROM dbo.FifoKatman h
        JOIN (
            SELECT KatmanId, SUM(ABS(cikisMiktar)) AS toplamCikis
            FROM #cikisDetay
            GROUP BY KatmanId
        ) d ON d.KatmanId = h.KatmanId
        WHERE h.KalanMiktar > 0;

        COMMIT TRANSACTION;
        
        SELECT
            StkId, HareketTarihi, HareketTipi, MekanId, KatmanId,
            KatmanTarihi, KatmanBelgeNo, Miktar, BirimMaliyet, CikisTutar, SatisTutar
        FROM dbo.FifoCikisDetay
        WHERE HareketTarihi >= @satisBaslangic
          AND HareketTarihi <= @satisBitis
          AND (@StkId IS NULL OR StkId = @StkId)
        ORDER BY StkId, HareketTarihi, MekanId, KatmanTarihi, KatmanId;
        
        PRINT 'FIFO cikis islemi basariyla tamamlandi. Tarih araligi: ' + 
              CONVERT(VARCHAR(10), @satisBaslangic, 120) + ' - ' + 
              CONVERT(VARCHAR(10), @satisBitis, 120);
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @runMessage VARCHAR(500) = SUBSTRING(CONVERT(VARCHAR(500), @ErrorMessage), 1, 500);
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        
        THROW;
    END CATCH
END
GO

PRINT 'sp_Fifo_CikisMaliyetle proseduru olusturuldu';
GO

PRINT '';

PRINT '5/6 - Toplu calistirma proseduru olusturuluyor...';
GO

-- =============================================================
-- TOPLU FIFO CALISTIRMA PROSEDURU
-- Amac: Manuel ve job calistirmalari ayni SP uzerinden yapmak
-- Not: Acilis/aylik ayri izleme icin yeni wrapper'lar tercih edilir:
--      sp_Fifo_AcilisCalistir / sp_Fifo_AylikCalistir / sp_Fifo_AylikRutinFull
-- =============================================================


CREATE OR ALTER PROCEDURE dbo.sp_MaliyetAdimYaz
(
    @IslemId UNIQUEIDENTIFIER,
    @AdimKodu VARCHAR(50),
    @AdimAdi VARCHAR(100),
    @SiraNo INT,
    @Durum VARCHAR(20),
    @Mesaj VARCHAR(500) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @IslemId IS NULL OR @AdimKodu IS NULL
        RETURN;

    -- FK (MaliyetIslemAdim -> MaliyetIslem) icin parent kayit yoksa otomatik olustur.
    IF NOT EXISTS (SELECT 1 FROM dbo.MaliyetIslem WHERE IslemId = @IslemId)
    BEGIN
        INSERT INTO dbo.MaliyetIslem
            (IslemId, IslemAdi, Durum, Baslangic, Bitis, Aciklama)
        VALUES
            (
                @IslemId,
                'MANUEL',
                CASE
                    WHEN @Durum IN ('TAMAMLANDI', 'HATA', 'ATLANDI') THEN @Durum
                    ELSE 'BEKLIYOR'
                END,
                GETDATE(),
                CASE WHEN @Durum IN ('TAMAMLANDI', 'HATA', 'ATLANDI') THEN GETDATE() ELSE NULL END,
                NULL
            );
    END

    IF EXISTS (SELECT 1 FROM dbo.MaliyetIslemAdim WHERE IslemId = @IslemId AND AdimKodu = @AdimKodu)
    BEGIN
        UPDATE dbo.MaliyetIslemAdim
        SET Durum = @Durum,
            AdimAdi = @AdimAdi,
            SiraNo = @SiraNo,
            Mesaj = @Mesaj,
            Baslangic = CASE
                WHEN @Durum IN ('CALISIYOR','TAMAMLANDI','HATA','ATLANDI') AND Baslangic IS NULL THEN GETDATE()
                ELSE Baslangic
            END,
            Bitis = CASE
                WHEN @Durum IN ('TAMAMLANDI','HATA','ATLANDI') THEN GETDATE()
                ELSE Bitis
            END,
            Guncelleme = GETDATE()
        WHERE IslemId = @IslemId AND AdimKodu = @AdimKodu;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.MaliyetIslemAdim
            (IslemId, AdimKodu, AdimAdi, SiraNo, Durum, Mesaj, Baslangic, Bitis)
        VALUES
            (@IslemId, @AdimKodu, @AdimAdi, @SiraNo, @Durum, @Mesaj,
             CASE WHEN @Durum IN ('CALISIYOR','TAMAMLANDI','HATA','ATLANDI') THEN GETDATE() ELSE NULL END,
             CASE WHEN @Durum IN ('TAMAMLANDI','HATA','ATLANDI') THEN GETDATE() ELSE NULL END);
    END

    /* Ust kayit durumunu adimlara gore senkron tut */
    DECLARE @UstDurum NVARCHAR(30) = 'BEKLIYOR';

    IF EXISTS (
        SELECT 1
        FROM dbo.MaliyetIslemAdim
        WHERE IslemId = @IslemId
          AND Durum = 'HATA'
    )
        SET @UstDurum = 'HATA';
    ELSE IF EXISTS (
        SELECT 1
        FROM dbo.MaliyetIslemAdim
        WHERE IslemId = @IslemId
          AND Durum = 'CALISIYOR'
    )
        SET @UstDurum = 'CALISIYOR';
    ELSE IF EXISTS (
        SELECT 1
        FROM dbo.MaliyetIslemAdim
        WHERE IslemId = @IslemId
          AND Durum IN ('TAMAMLANDI', 'ATLANDI')
    )
        SET @UstDurum = 'TAMAMLANDI';

    UPDATE dbo.MaliyetIslem
    SET Durum = @UstDurum,
        Bitis = CASE
            WHEN @UstDurum IN ('TAMAMLANDI', 'HATA') THEN ISNULL(Bitis, GETDATE())
            ELSE NULL
        END,
        Aciklama = CASE
            WHEN @Durum = 'HATA' AND @Mesaj IS NOT NULL THEN @Mesaj
            ELSE Aciklama
        END
    WHERE IslemId = @IslemId;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_Fifo_Calistir
(
    @EnvanterTarihi  DATE = NULL,
    @alisBaslangic   DATE = NULL,
    @alisBitis       DATE = NULL,
    @satisBaslangic  DATE = NULL,
    @satisBitis      DATE = NULL,
    @StkId           INT = NULL,
    @IslemId           UNIQUEIDENTIFIER = NULL,
    @calistirAcilis  BIT  = 0,
    @calistirAlis    BIT  = 1,
    @calistirCikis   BIT  = 1,
    @fallbackSatinalmaSarti  VARCHAR(50) = NULL,  -- sadece acilis fallback fiyatlama icin (calistirAcilis=1)
    @sabitFallbackBirimMaliyet DECIMAL(18,6) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @AdimKodu VARCHAR(50) = NULL;
    DECLARE @AdimAdi VARCHAR(100) = NULL;
    DECLARE @SiraNo INT = NULL;

    IF ISNULL(@calistirAcilis, 0) = 0
       AND ISNULL(@calistirAlis, 0) = 0
       AND ISNULL(@calistirCikis, 0) = 0
    BEGIN
        RAISERROR('En az bir calistirma adimi secilmelidir (Acilis/Alis/Cikis).', 16, 1);
        RETURN;
    END

    IF @sabitFallbackBirimMaliyet IS NOT NULL AND @sabitFallbackBirimMaliyet <= 0
    BEGIN
        RAISERROR('Sabit fallback birim maliyet 0''dan buyuk olmali.', 16, 1);
        RETURN;
    END

    IF @calistirAcilis = 1 AND @EnvanterTarihi IS NULL
    BEGIN
        RAISERROR('Envanter tarihi bos olamaz', 16, 1);
        RETURN;
    END

    IF @calistirAlis = 1 AND (@alisBaslangic IS NULL OR @alisBitis IS NULL)
    BEGIN
        RAISERROR('Alis tarihleri bos olamaz', 16, 1);
        RETURN;
    END

    IF @calistirCikis = 1 AND (@satisBaslangic IS NULL OR @satisBitis IS NULL)
    BEGIN
        RAISERROR('Satis tarihleri bos olamaz', 16, 1);
        RETURN;
    END

    IF @calistirAlis = 1 AND @alisBaslangic > @alisBitis
    BEGIN
        RAISERROR('Alis baslangic tarihi bitis tarihinden buyuk olamaz', 16, 1);
        RETURN;
    END

    IF @calistirCikis = 1 AND @satisBaslangic > @satisBitis
    BEGIN
        RAISERROR('Satis baslangic tarihi bitis tarihinden buyuk olamaz', 16, 1);
        RETURN;
    END

    BEGIN TRY
        IF @calistirAcilis = 1
        BEGIN
            EXEC dbo.sp_Fifo_AcilisMaliyetlendir
                @EnvanterTarihi = @EnvanterTarihi,
                @StkId = @StkId,
                @IslemId = @IslemId,
                @fallbackSatinalmaSarti = @fallbackSatinalmaSarti,
                @sabitFallbackBirimMaliyet = @sabitFallbackBirimMaliyet;
        END

        /* RERUN-SAFE: ALIS katmanlari silinmeden ONCE donem cikislarini geri al + sil.
           Yoksa sp_Fifo_AlisKatmanEkle'nin "DELETE FROM FifoKatman WHERE KaynakTip='ALIS'"
           ifadesi, onceki run'in FifoCikisDetay referanslarina takilir
           (FK_FifoCikisDetay_FifoKatman) ve urun atlanir. Alis(+)->Satis(-) sirasi korunur. */
        IF @calistirCikis = 1
        BEGIN
            UPDATE h SET h.KalanMiktar = h.KalanMiktar + d.toplamCikis
            FROM dbo.FifoKatman h
            JOIN (
                SELECT c.KatmanId, SUM(c.Miktar) AS toplamCikis
                FROM dbo.FifoCikisDetay c
                WHERE c.HareketTarihi >= @satisBaslangic
                  AND c.HareketTarihi <= @satisBitis
                  AND (@StkId IS NULL OR c.StkId = @StkId)
                GROUP BY c.KatmanId
            ) d ON d.KatmanId = h.KatmanId;

            DELETE FROM dbo.FifoCikisDetay
            WHERE HareketTarihi >= @satisBaslangic
              AND HareketTarihi <= @satisBitis
              AND (@StkId IS NULL OR StkId = @StkId);
        END

        IF @calistirAlis = 1
        BEGIN
            SET @AdimKodu = 'rutin_alis';
            SET @AdimAdi = 'Alis katman';
            SET @SiraNo = 110;
            IF @IslemId IS NOT NULL
                EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'CALISIYOR', NULL;

            EXEC dbo.sp_Fifo_AlisKatmanEkle
                @baslangicTarihi = @alisBaslangic,
                @bitisTarihi = @alisBitis,
                @StkId = @StkId,
                @IslemId = @IslemId;

            IF @IslemId IS NOT NULL
                EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'TAMAMLANDI', NULL;
        END
        ELSE IF @IslemId IS NOT NULL AND @calistirCikis = 1
        BEGIN
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, 'rutin_alis', 'Alis katman', 110, 'ATLANDI', 'CalistirAlis=0';
        END

        IF @calistirCikis = 1
        BEGIN
            SET @AdimKodu = 'rutin_cikis';
            SET @AdimAdi = 'FIFO cikis';
            SET @SiraNo = 120;
            IF @IslemId IS NOT NULL
                EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'CALISIYOR', NULL;

            EXEC dbo.sp_Fifo_CikisMaliyetle
                @satisBaslangic = @satisBaslangic,
                @satisBitis = @satisBitis,
                @StkId = @StkId,
                @IslemId = @IslemId;

            IF @IslemId IS NOT NULL
                EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'TAMAMLANDI', NULL;

            SET @AdimKodu = 'rutin_rapor';
            SET @AdimAdi = 'Sonuc hazirligi';
            SET @SiraNo = 130;
            IF @IslemId IS NOT NULL
            BEGIN
                EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'CALISIYOR', NULL;
                EXEC dbo.sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, 'TAMAMLANDI', NULL;
            END
        END
        ELSE IF @IslemId IS NOT NULL AND @calistirAlis = 1
        BEGIN
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, 'rutin_cikis', 'FIFO cikis', 120, 'ATLANDI', 'CalistirCikis=0';
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, 'rutin_rapor', 'Sonuc hazirligi', 130, 'ATLANDI', 'CalistirCikis=0';
        END
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @runMessage VARCHAR(500) = SUBSTRING(CONVERT(VARCHAR(500), @ErrorMessage), 1, 500);
        IF @IslemId IS NOT NULL AND @AdimKodu IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz
                @IslemId = @IslemId,
                @AdimKodu = @AdimKodu,
                @AdimAdi = @AdimAdi,
                @SiraNo = @SiraNo,
                @Durum = 'HATA',
                @Mesaj = @runMessage;
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        THROW;
    END CATCH
END
GO

PRINT 'sp_Fifo_Calistir proseduru olusturuldu';
GO

-- =============================================================
-- ACILIS CALISTIRMA WRAPPER - dbo.sp_Fifo_AcilisCalistir
-- Acilis islemini ayri run/calismayla izlemek icin
-- =============================================================

CREATE OR ALTER PROCEDURE dbo.sp_Fifo_AcilisCalistir
(
    @EnvanterTarihi DATE,
    @StkId INT = NULL,
    @IslemId UNIQUEIDENTIFIER = NULL,
    @fallbackSatinalmaSarti VARCHAR(50) = NULL,
    @atlamaAylikDevir BIT = 0,
    @sabitFallbackBirimMaliyet DECIMAL(18,6) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.sp_Fifo_AcilisMaliyetlendir
        @EnvanterTarihi = @EnvanterTarihi,
        @StkId = @StkId,
        @IslemId = @IslemId,
        @fallbackSatinalmaSarti = @fallbackSatinalmaSarti,
        @atlamaAylikDevir = @atlamaAylikDevir,
        @sabitFallbackBirimMaliyet = @sabitFallbackBirimMaliyet;
END
GO

PRINT 'sp_Fifo_AcilisCalistir proseduru olusturuldu';
GO

-- =============================================================
-- AYLIK CALISTIRMA WRAPPER - dbo.sp_Fifo_AylikCalistir
-- Aylik alis+cikis islemlerini ayri run/calismayla izlemek icin
-- =============================================================

CREATE OR ALTER PROCEDURE dbo.sp_Fifo_AylikCalistir
(
    @yil INT,
    @ay INT,
    @StkId INT = NULL,
    @IslemId UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @yil IS NULL OR @ay IS NULL OR @ay NOT BETWEEN 1 AND 12
    BEGIN
        RAISERROR('Gecersiz yil/ay parametresi.', 16, 1);
        RETURN;
    END

    DECLARE @baslangic DATE = DATEFROMPARTS(@yil, @ay, 1);
    DECLARE @bitis DATE = EOMONTH(@baslangic);

    EXEC dbo.sp_Fifo_Calistir
        @alisBaslangic = @baslangic,
        @alisBitis = @bitis,
        @satisBaslangic = @baslangic,
        @satisBitis = @bitis,
        @StkId = @StkId,
        @IslemId = @IslemId,
        @calistirAcilis = 0,
        @calistirAlis = 1,
        @calistirCikis = 1;
END
GO

PRINT 'sp_Fifo_AylikCalistir proseduru olusturuldu';
GO

-- =============================================================
-- AYLIK RUTIN PROSEDURU - dbo.sp_Fifo_AylikRutin
-- Tek seferlik acilis HARIC - sadece alis katmanlari + FIFO cikis
-- Her ay duzenli calistirilir (job/scheduler ile)
-- =============================================================

CREATE OR ALTER PROCEDURE dbo.sp_Fifo_AylikRutin
(
    @yil    INT,
    @ay     INT,
    @StkId  INT = NULL,
    @IslemId  UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @yil IS NULL OR @ay IS NULL OR @ay NOT BETWEEN 1 AND 12
    BEGIN
        RAISERROR('Gecersiz yil/ay parametresi.', 16, 1);
        RETURN;
    END

    DECLARE @alisBaslangic DATE = DATEFROMPARTS(@yil, @ay, 1);
    DECLARE @alisBitis     DATE = EOMONTH(@alisBaslangic);

    EXEC dbo.sp_Fifo_Calistir
        @alisBaslangic   = @alisBaslangic,
        @alisBitis      = @alisBitis,
        @satisBaslangic = @alisBaslangic,
        @satisBitis     = @alisBitis,
        @StkId          = @StkId,
        @IslemId          = @IslemId,
        @calistirAcilis = 0,   -- Acilis YOK (tek seferlik acilis: sp_Fifo_AcilisCalistir)
        @calistirAlis   = 1,
        @calistirCikis  = 1;
END
GO

PRINT 'sp_Fifo_AylikRutin proseduru olusturuldu';
GO


