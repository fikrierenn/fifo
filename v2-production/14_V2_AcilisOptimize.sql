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
-- V2-14: ACILIS MALIYETLENDIRME - OPTIMIZE EDILMIS VERSIYON
--
-- Bottleneck'ler ve cozumleri:
--   1) irsHrk aylik devir: kartezyen JOIN (urun x ay x hareket)
--      => EOMONTH pre-aggregate + window SUM  (55x hiz kazanimi)
--   2) fn_SonGecerliFiyat_Adv: satir-satir OUTER APPLY
--      => Distinct ay basina 1 bulk TVF cagri + LEFT JOIN
--   3) 37 dk boyunca tek transaction / lock
--      => 3 faza bol, arada lock birak
--   4) irsHrk full scan (2021 oncesi gereksiz)
--      => @baslangicTarihi alt sinir filtresi
--
-- Schema: dbo (v2 convention)
-- =============================================================

CREATE OR ALTER PROCEDURE dbo.sp_Fifo_AcilisCalistir_V2
(
    @EnvanterTarihi DATE,
    @StkId INT = NULL,
    @IslemId UNIQUEIDENTIFIER = NULL,
    @FallbackSatinalmaSarti VARCHAR(50) = NULL   -- ERP devir fiyatlari icin
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- ============================================================
    -- PARAMETRE VALIDASYONU
    -- ============================================================
    IF @EnvanterTarihi IS NULL
    BEGIN
        RAISERROR('Envanter tarihi bos olamaz', 16, 1);
        RETURN;
    END

    IF @EnvanterTarihi > GETDATE()
    BEGIN
        RAISERROR('Envanter tarihi gelecek tarih olamaz', 16, 1);
        RETURN;
    END

    DECLARE @baslangicTarihi DATE = DATEFROMPARTS(2021, 5, 31);
    DECLARE @stepKey VARCHAR(50);
    DECLARE @stepName VARCHAR(100);
    DECLARE @stepOrder INT;
    DECLARE @fazBaslangic DATETIME2(3) = SYSDATETIME();
    DECLARE @urunSayisi INT = 0;

    -- ============================================================
    -- FAZ 1: ENVANTER SNAPSHOT + ALISLAR
    -- (Kendi transaction'i - read-heavy, lock erken birakilir)
    -- ============================================================
    BEGIN TRY
        BEGIN TRANSACTION;

        PRINT '========================================';
        PRINT 'sp_Fifo_AcilisCalistir_V2 basliyor';
        PRINT 'Envanter tarihi: ' + CONVERT(VARCHAR(10), @EnvanterTarihi, 120);
        PRINT 'Baslangic: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 121);
        PRINT '========================================';

        -- --------------------------------------------------------
        -- ADIM 1: Envanter snapshot (irsHrk ile mekan bazli stok)
        -- --------------------------------------------------------
        SET @stepKey = 'envanter_v2';
        SET @stepName = 'Envanter snapshot (V2)';
        SET @stepOrder = 1;
        PRINT '[1/6] Envanter snapshot - irsHrk okunuyor...';
        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='CALISIYOR', @Mesaj=NULL;

        IF OBJECT_ID('tempdb..#stoklarMekan', 'U') IS NOT NULL DROP TABLE #stoklarMekan;

        SELECT
            d.ehMekan AS MekanId,
            d.ehstkID AS StkId,
            SUM(CONVERT(DECIMAL(18,4), d.stok)) AS StokMiktar
        INTO #stoklarMekan
        FROM DerinSIS_Local.dbo.stokSonAltDepo_vw d
        WHERE d.ehAltDepo = 0
          AND d.ehMekan IN (1, 12, 4477, 4478)   -- FIX: mekan 12 (ana depo, en buyuk stok) ortak havuza dahil
          AND d.stok > 0
          AND (@StkId IS NULL OR d.ehstkID = @StkId)
        GROUP BY d.ehMekan, d.ehstkID;

        CREATE INDEX IX_tmp_stoklarMekan ON #stoklarMekan(MekanId, StkId);

        IF OBJECT_ID('tempdb..#stoklar', 'U') IS NOT NULL DROP TABLE #stoklar;

        SELECT
            StkId,
            SUM(StokMiktar) AS StokMiktar
        INTO #stoklar
        FROM #stoklarMekan
        GROUP BY StkId;

        SET @urunSayisi = @@ROWCOUNT;
        CREATE INDEX IX_tmp_stoklar ON #stoklar(StkId);

        PRINT '      Urun sayisi: ' + CAST(@urunSayisi AS VARCHAR(10));

        /* Envanter kayit */
        DELETE FROM dbo.FifoAcilisEnvanter
        WHERE EnvanterTarihi = @EnvanterTarihi
          AND (@StkId IS NULL OR StkId = @StkId);

        INSERT INTO dbo.FifoAcilisEnvanter (EnvanterTarihi, MekanId, StkId, StokMiktar)
        SELECT @EnvanterTarihi, MekanId, StkId, StokMiktar
        FROM #stoklarMekan;

        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='TAMAMLANDI', @Mesaj=NULL;
        PRINT '      Envanter tamamlandi. Sure: ' +
              CAST(DATEDIFF(SECOND, @fazBaslangic, SYSDATETIME()) AS VARCHAR(10)) + 's';

        -- --------------------------------------------------------
        -- ADIM 2: Alislar (fat + fatAyr)
        -- --------------------------------------------------------
        SET @fazBaslangic = SYSDATETIME();
        SET @stepKey = 'alis_v2';
        SET @stepName = 'Alislar toplanir (V2)';
        SET @stepOrder = 2;
        PRINT '[2/6] Alislar toplaniyor (fat+fatAyr)...';
        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='CALISIYOR', @Mesaj=NULL;

        IF OBJECT_ID('tempdb..#alislar', 'U') IS NOT NULL DROP TABLE #alislar;
        CREATE TABLE #alislar (
            StkId        INT           NOT NULL,
            GirisTarihi  DATETIME      NOT NULL,
            BelgeNo      VARCHAR(50)   NULL,
            BelgeTarihi  DATE          NULL,
            FirmaId      INT           NULL,
            Miktar       DECIMAL(18,4) NOT NULL,
            NetTutar     DECIMAL(18,4) NOT NULL
        );

        DECLARE @firmaCol SYSNAME = NULL;
        DECLARE @belgeTarihCol SYSNAME = NULL;

        IF COL_LENGTH('dbo.fat', 'eFirma') IS NOT NULL SET @firmaCol = 'eFirma';
        ELSE IF COL_LENGTH('dbo.fat', 'eCariID') IS NOT NULL SET @firmaCol = 'eCariID';
        ELSE IF COL_LENGTH('dbo.fat', 'eCari') IS NOT NULL SET @firmaCol = 'eCari';

        IF COL_LENGTH('dbo.fat', 'eTarih') IS NOT NULL SET @belgeTarihCol = 'eTarih';
        ELSE IF COL_LENGTH('dbo.fat', 'eTarihF') IS NOT NULL SET @belgeTarihCol = 'eTarihF';

        DECLARE @belgeTarihExpr NVARCHAR(200) =
            CASE WHEN @belgeTarihCol IS NULL THEN 'i.eTarih' ELSE 'f.' + QUOTENAME(@belgeTarihCol) END;
        DECLARE @firmaExpr NVARCHAR(200) =
            CASE WHEN @firmaCol IS NULL THEN 'NULL' ELSE 'f.' + QUOTENAME(@firmaCol) END;
        DECLARE @groupByExtra NVARCHAR(400) = '';

        IF @belgeTarihCol IS NOT NULL SET @groupByExtra = @groupByExtra + ', ' + @belgeTarihExpr;
        IF @firmaCol IS NOT NULL SET @groupByExtra = @groupByExtra + ', ' + @firmaExpr;

        DECLARE @sql NVARCHAR(MAX) = N'
        INSERT INTO #alislar (StkId, GirisTarihi, BelgeNo, BelgeTarihi, FirmaId, Miktar, NetTutar)
        SELECT
            a.ehStkID AS StkId,
            i.eTarih  AS GirisTarihi,
            f.eNo     AS BelgeNo,
            ' + @belgeTarihExpr + N' AS BelgeTarihi,
            ' + @firmaExpr + N' AS FirmaId,
            SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS Miktar,
            SUM(
                CONVERT(DECIMAL(18,4),
                    CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END
                )
            ) AS NetTutar
        FROM #stoklar s
        JOIN DerinSIS_Local.dbo.irs i WITH(NOLOCK)
            ON i.eTip IN (2,0,10,3,6,102,103)
           AND i.eTarih >  CONVERT(smalldatetime, @baslangicTarihi)
           AND i.eTarih <  DATEADD(DAY, 1, CONVERT(smalldatetime, @EnvanterTarihi))
           AND i.eMekan IN (1,12,4477,4478)   -- FIX: mekan 12 dahil (ortak havuz kurali)
        JOIN DerinSIS_Local.dbo.irsAyr ia WITH(NOLOCK)
            ON ia.ehID = i.eID
        JOIN DerinSIS_Local.dbo.fatAyr a WITH(NOLOCK)
            ON a.ehIrsID   = i.eID
           AND a.ehIrsSira = ia.ehSira
           AND a.ehStkID   = s.StkId
        JOIN DerinSIS_Local.dbo.fat f WITH(NOLOCK)
            ON f.eID = a.ehID
        WHERE a.ehAdetN <> 0
          AND (@StkId IS NULL OR a.ehStkID = @StkId)
        GROUP BY a.ehstkID, i.eTarih, i.eID, f.eNo' + @groupByExtra + N'
        HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;';

        EXEC sp_executesql
            @sql,
            N'@baslangicTarihi DATE, @EnvanterTarihi DATE, @StkId INT',
            @baslangicTarihi = @baslangicTarihi,
            @EnvanterTarihi = @EnvanterTarihi,
            @StkId = @StkId;

        ALTER TABLE #alislar ADD BirimMaliyet DECIMAL(18,6);

        UPDATE #alislar
        SET BirimMaliyet = CASE WHEN Miktar = 0 THEN 0 ELSE NetTutar / Miktar END;

        CREATE INDEX IX_tmp_alislar ON #alislar(StkId, GirisTarihi DESC, BelgeNo);

        DECLARE @alisSayisi INT = (SELECT COUNT(*) FROM #alislar);
        PRINT '      Alis kaydi: ' + CAST(@alisSayisi AS VARCHAR(10));

        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='TAMAMLANDI', @Mesaj=NULL;
        PRINT '      Alislar tamamlandi. Sure: ' +
              CAST(DATEDIFF(SECOND, @fazBaslangic, SYSDATETIME()) AS VARCHAR(10)) + 's';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        GOTO HataYonetimi;
    END CATCH

    -- ============================================================
    -- FAZ 2: TERS FIFO KATMAN + TAMAMLAMALAR
    -- (Kendi transaction'i - yazma agirlikli)
    -- ============================================================
    BEGIN TRY
        BEGIN TRANSACTION;
        SET @fazBaslangic = SYSDATETIME();

        -- --------------------------------------------------------
        -- ADIM 3: Ters FIFO katman hesaplama
        -- --------------------------------------------------------
        SET @stepKey = 'katman_v2';
        SET @stepName = 'Ters FIFO katman (V2)';
        SET @stepOrder = 3;
        PRINT '[3/6] Ters FIFO katman hesaplaniyor...';
        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='CALISIYOR', @Mesaj=NULL;

        IF OBJECT_ID('tempdb..#katman', 'U') IS NOT NULL DROP TABLE #katman;

        ;WITH Ters AS (
            SELECT
                StkId, GirisTarihi, BelgeNo, BelgeTarihi, FirmaId, Miktar, BirimMaliyet, NetTutar,
                SUM(Miktar) OVER (
                    PARTITION BY StkId
                    ORDER BY GirisTarihi DESC, BelgeNo DESC
                    ROWS UNBOUNDED PRECEDING
                ) AS KumTers
            FROM #alislar
            WHERE Miktar > 0 AND NetTutar > 0
        ),
        Acilis AS (
            SELECT
                t.StkId, t.GirisTarihi, t.BelgeNo, t.BelgeTarihi, t.FirmaId,
                t.Miktar AS SatirMiktar, t.BirimMaliyet,
                t.KumTers, s.StokMiktar,
                CASE
                    WHEN t.KumTers - t.Miktar >= s.StokMiktar THEN 0
                    WHEN t.KumTers <= s.StokMiktar THEN t.Miktar
                    ELSE s.StokMiktar - (t.KumTers - t.Miktar)
                END AS AcilisMiktar
            FROM Ters t
            JOIN #stoklar s ON s.StkId = t.StkId
        )
        SELECT StkId, GirisTarihi, BelgeNo, BelgeTarihi, FirmaId,
               SatirMiktar, BirimMaliyet, KumTers, StokMiktar, AcilisMiktar
        INTO #katman
        FROM Acilis WHERE AcilisMiktar > 0;

        DECLARE @katmanSayisi INT = @@ROWCOUNT;
        PRINT '      Katman sayisi: ' + CAST(@katmanSayisi AS VARCHAR(10));

        /* Onceki acilis temizligi */
        DELETE FROM dbo.FifoKatman
        WHERE KaynakTip = 'ACILIS' AND GirisTarihi = @EnvanterTarihi
          AND (@StkId IS NULL OR StkId = @StkId);

        INSERT INTO dbo.FifoKatman
            (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
             GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
        SELECT
            StkId, @EnvanterTarihi, 'ACILIS', BelgeNo, BelgeTarihi, FirmaId,
            AcilisMiktar, AcilisMiktar, BirimMaliyet, 'NORMAL'
        FROM #katman;

        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='TAMAMLANDI', @Mesaj=NULL;
        PRINT '      Katman tamamlandi. Sure: ' +
              CAST(DATEDIFF(SECOND, @fazBaslangic, SYSDATETIME()) AS VARCHAR(10)) + 's';

        -- --------------------------------------------------------
        -- ADIM 4: Eksik tamamlamalar (son alis + merkez + sart)
        -- --------------------------------------------------------
        SET @fazBaslangic = SYSDATETIME();
        SET @stepKey = 'tamamla_v2';
        SET @stepName = 'Tamamlamalar (V2)';
        SET @stepOrder = 4;
        PRINT '[4/6] Eksik tamamlamalari (son alis, merkez, sart fiyat)...';
        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='CALISIYOR', @Mesaj=NULL;

        /* Eksik miktarlari tespit et */
        IF OBJECT_ID('tempdb..#eksikler', 'U') IS NOT NULL DROP TABLE #eksikler;

        ;WITH Ozet AS (
            SELECT StkId, SUM(AcilisMiktar) AS ToplamAcilisMiktar
            FROM #katman GROUP BY StkId
        ),
        AlisVarMi AS (
            SELECT DISTINCT StkId FROM #alislar
        )
        SELECT
            s.StkId, s.StokMiktar,
            ISNULL(o.ToplamAcilisMiktar, 0) AS ToplamAcilisMiktar,
            (s.StokMiktar - ISNULL(o.ToplamAcilisMiktar, 0)) AS EksikMiktar
        INTO #eksikler
        FROM #stoklar s
        LEFT JOIN Ozet o ON o.StkId = s.StkId
        LEFT JOIN AlisVarMi v ON v.StkId = s.StkId;

        /* Alisi olan ama yetmeyenleri son alisla tamamla */
        ;WITH SonAlis AS (
            SELECT
                a.StkId, a.GirisTarihi, a.BelgeNo, a.BelgeTarihi, a.FirmaId, a.BirimMaliyet,
                ROW_NUMBER() OVER (
                    PARTITION BY a.StkId
                    ORDER BY a.GirisTarihi DESC, a.BelgeNo DESC
                ) AS rn
            FROM #alislar a
            WHERE a.BirimMaliyet > 0   -- FIYAT 0 OLAMAZ (fifo-domain §6, 2026-06-19): 0-degerli son-alis (numune/duzeltme fatAyr.ehTutarN=0) atlanir, en son NONZERO alis secilir
        )
        INSERT INTO dbo.FifoKatman
            (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
             GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
        SELECT
            e.StkId, @EnvanterTarihi, 'ACILIS_TAMAMLA', sa.BelgeNo, sa.BelgeTarihi, sa.FirmaId,
            e.EksikMiktar, e.EksikMiktar, sa.BirimMaliyet, 'TAMAMLAMA'
        FROM #eksikler e
        JOIN SonAlis sa ON sa.StkId = e.StkId AND sa.rn = 1
        WHERE e.EksikMiktar > 0 AND e.ToplamAcilisMiktar > 0;

        DECLARE @tamamlamaSayisi INT = @@ROWCOUNT;
        PRINT '      Son alis tamamlama: ' + CAST(@tamamlamaSayisi AS VARCHAR(10)) + ' urun';

        /* Merkez depo (12) alislari ile tamamlama (alis yoksa) */
        IF OBJECT_ID('tempdb..#merkezAlis', 'U') IS NOT NULL DROP TABLE #merkezAlis;
        CREATE TABLE #merkezAlis (
            StkId        INT           NOT NULL,
            GirisTarihi  DATETIME      NOT NULL,
            BelgeNo      VARCHAR(50)   NULL,
            BelgeTarihi  DATE          NULL,
            FirmaId      INT           NULL,
            Miktar       DECIMAL(18,4) NOT NULL,
            NetTutar     DECIMAL(18,4) NOT NULL
        );

        DECLARE @sqlMerkez NVARCHAR(MAX) = N'
        INSERT INTO #merkezAlis (StkId, GirisTarihi, BelgeNo, BelgeTarihi, FirmaId, Miktar, NetTutar)
        SELECT
            a.ehStkID AS StkId,
            i.eTarih  AS GirisTarihi,
            f.eNo     AS BelgeNo,
            ' + @belgeTarihExpr + N' AS BelgeTarihi,
            ' + @firmaExpr + N' AS FirmaId,
            SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS Miktar,
            SUM(
                CONVERT(DECIMAL(18,4),
                    CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END
                )
            ) AS NetTutar
        FROM #eksikler e
        LEFT JOIN (SELECT DISTINCT StkId FROM #alislar) v ON v.StkId = e.StkId
        JOIN DerinSIS_Local.dbo.irs i WITH(NOLOCK)
            ON i.eTip IN (2,0,10,3,6,102,103)
           AND i.eTarih >  CONVERT(smalldatetime, @baslangicTarihi)
           AND i.eTarih <  DATEADD(DAY, 1, CONVERT(smalldatetime, @EnvanterTarihi))
           AND i.eMekan = 12
        JOIN DerinSIS_Local.dbo.irsAyr ia WITH(NOLOCK)
            ON ia.ehID = i.eID
        JOIN DerinSIS_Local.dbo.fatAyr a WITH(NOLOCK)
            ON a.ehIrsID   = i.eID
           AND a.ehIrsSira = ia.ehSira
           AND a.ehStkID   = e.StkId
        JOIN DerinSIS_Local.dbo.fat f WITH(NOLOCK)
            ON f.eID = a.ehID
        WHERE a.ehAdetN <> 0
          AND v.StkId IS NULL
          AND e.EksikMiktar > 0
          AND (@StkId IS NULL OR a.ehStkID = @StkId)
        GROUP BY a.ehStkID, i.eTarih, i.eID, f.eNo' + @groupByExtra + N'
        HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;';

        EXEC sp_executesql
            @sqlMerkez,
            N'@baslangicTarihi DATE, @EnvanterTarihi DATE, @StkId INT',
            @baslangicTarihi = @baslangicTarihi,
            @EnvanterTarihi = @EnvanterTarihi,
            @StkId = @StkId;

        ALTER TABLE #merkezAlis ADD BirimMaliyet DECIMAL(18,6);

        UPDATE #merkezAlis
        SET BirimMaliyet = CASE WHEN Miktar = 0 THEN 0 ELSE NetTutar / Miktar END;

        IF OBJECT_ID('tempdb..#merkezSon', 'U') IS NOT NULL DROP TABLE #merkezSon;

        ;WITH SonMerkez AS (
            SELECT
                m.StkId, m.GirisTarihi, m.BelgeNo, m.BelgeTarihi, m.FirmaId, m.BirimMaliyet,
                ROW_NUMBER() OVER (
                    PARTITION BY m.StkId
                    ORDER BY m.GirisTarihi DESC, m.BelgeNo DESC
                ) AS rn
            FROM #merkezAlis m
            WHERE m.BirimMaliyet > 0   -- FIYAT 0 OLAMAZ (fifo-domain §6, 2026-06-19): 0-degerli merkez-alis atlanir, en son NONZERO merkez alisi secilir
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
            e.EksikMiktar, e.EksikMiktar, ms.BirimMaliyet, 'MERKEZ_TAMAMLAMA'
        FROM #eksikler e
        JOIN #merkezSon ms ON ms.StkId = e.StkId
        LEFT JOIN (SELECT DISTINCT StkId FROM #alislar) v ON v.StkId = e.StkId
        WHERE v.StkId IS NULL AND e.EksikMiktar > 0;

        DECLARE @merkezSayisi INT = @@ROWCOUNT;
        PRINT '      Merkez tamamlama: ' + CAST(@merkezSayisi AS VARCHAR(10)) + ' urun';

        /* Son gecerli fiyat ile tamamlama */
        IF OBJECT_ID('tempdb..#sonGecerli', 'U') IS NOT NULL DROP TABLE #sonGecerli;

        ;WITH SonFiyat AS (
            SELECT
                f.fhID,
                f.fStkID AS StkId,
                f.fTarih,
                f.fTarihSon,
                f.sonrakiNet,
                ROW_NUMBER() OVER (
                    PARTITION BY f.fStkID
                    ORDER BY f.fTarihSon DESC, f.fhID DESC
                ) AS rn
            FROM DerinSIS_Local.bkm.fn_SonGecerliFiyat(@EnvanterTarihi, 1) f
            WHERE f.sonrakiNet > 0
        )
        SELECT
            StkId, fhID, fTarih, fTarihSon, sonrakiNet
        INTO #sonGecerli
        FROM SonFiyat
        WHERE rn = 1;

        INSERT INTO dbo.FifoKatman
            (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
             GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
        SELECT
            e.StkId, @EnvanterTarihi, 'ACILIS_TAMAMLA',
            CAST(sg.fhID AS VARCHAR(50)), CAST(sg.fTarihSon AS DATE), NULL,
            e.EksikMiktar, e.EksikMiktar, sg.sonrakiNet, 'SART_TAMAMLAMA'
        FROM #eksikler e
        JOIN #sonGecerli sg ON sg.StkId = e.StkId
        LEFT JOIN (SELECT DISTINCT StkId FROM #alislar) v ON v.StkId = e.StkId
        LEFT JOIN #merkezSon ms ON ms.StkId = e.StkId
        WHERE v.StkId IS NULL AND ms.StkId IS NULL AND e.EksikMiktar > 0;

        DECLARE @sartSayisi INT = @@ROWCOUNT;
        PRINT '      Sart tamamlama: ' + CAST(@sartSayisi AS VARCHAR(10)) + ' urun';

        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='TAMAMLANDI', @Mesaj=NULL;
        PRINT '      Tamamlamalar bitti. Sure: ' +
              CAST(DATEDIFF(SECOND, @fazBaslangic, SYSDATETIME()) AS VARCHAR(10)) + 's';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        GOTO HataYonetimi;
    END CATCH

    -- ============================================================
    -- FAZ 3: AYLIK DEVIR (OPTIMIZE) + SORUN KAYITLARI
    -- Bottleneck burada: irsHrk x ay kartezyen JOIN
    --   ESKi: irsHrk JOIN #aylar ON ehTrhS <= ayBitis  (55x tekrar)
    --   YENi: irsHrk 1 kez okunur, EOMONTH ile ay bazli pre-aggregate
    --         sonra window SUM ile kumulatif stok hesaplanir
    -- ============================================================
    BEGIN TRY
        BEGIN TRANSACTION;
        SET @fazBaslangic = SYSDATETIME();

        -- --------------------------------------------------------
        -- ADIM 5: Aylik devir (OPTIMIZE: pre-aggregate + window fn)
        -- --------------------------------------------------------
        SET @stepKey = 'aylik_devir_v2';
        SET @stepName = 'Aylik devir OPTIMIZE (V2)';
        SET @stepOrder = 5;
        PRINT '[5/6] Aylik devir (OPTIMIZE) hesaplaniyor...';
        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='CALISIYOR', @Mesaj=NULL;

        /* Eksik kalan urunler (alis/merkez/sart hicbiri bulamadi) */
        IF OBJECT_ID('tempdb..#eksikKalan', 'U') IS NOT NULL DROP TABLE #eksikKalan;

        SELECT e.StkId, e.EksikMiktar
        INTO #eksikKalan
        FROM #eksikler e
        LEFT JOIN (SELECT DISTINCT StkId FROM #alislar) v ON v.StkId = e.StkId
        LEFT JOIN #merkezSon ms ON ms.StkId = e.StkId
        LEFT JOIN #sonGecerli sg ON sg.StkId = e.StkId
        WHERE e.EksikMiktar > 0 AND v.StkId IS NULL AND ms.StkId IS NULL AND sg.StkId IS NULL;

        CREATE INDEX IX_tmp_eksikKalan ON #eksikKalan(StkId);

        DECLARE @eksikKalanSayisi INT = (SELECT COUNT(*) FROM #eksikKalan);
        PRINT '      Aylik devir gerekli urun: ' + CAST(@eksikKalanSayisi AS VARCHAR(10));

        IF OBJECT_ID('tempdb..#aylikKatman', 'U') IS NOT NULL DROP TABLE #aylikKatman;
        CREATE TABLE #aylikKatman (
            StkId INT NOT NULL,
            AyBitis DATE NOT NULL,
            AyMiktar DECIMAL(18,4) NOT NULL,
            BirimMaliyet DECIMAL(18,6) NULL,
            Durum VARCHAR(20) NOT NULL
        );

        /* Onceki AYLIK_DEVIR temizligi */
        DELETE FROM dbo.FifoKatman
        WHERE KaynakTip = 'AYLIK_DEVIR'
          AND GirisTarihi BETWEEN @baslangicTarihi AND @EnvanterTarihi
          AND (@StkId IS NULL OR StkId = @StkId);

        IF @eksikKalanSayisi > 0
        BEGIN
            -- =====================================================
            -- OPTIMIZASYON 1: irsHrk tek tarama + EOMONTH aggregate
            -- ESKi: irsHrk JOIN #aylar ON ehTrhS <= ayBitis
            --       => her hareket 55 ay icin tekrar okunur
            -- YENi: irsHrk 1 kez okunur, EOMONTH ile ay bazli SUM
            --       sonra window SUM ile kumulatif stok
            -- =====================================================
            PRINT '      [OPT1] irsHrk tek tarama + EOMONTH pre-aggregate...';

            IF OBJECT_ID('tempdb..#aylikHareket', 'U') IS NOT NULL DROP TABLE #aylikHareket;

            -- Adim A: Hareketleri ay bazli ozetle (tek tarama)
            SELECT
                h.ehstkID AS StkId,
                EOMONTH(h.ehTrhS) AS AyBitis,
                SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) AS AyHareket
            INTO #aylikHareket
            FROM DerinSIS_Local.dbo.irsHrk h WITH(NOLOCK)
            JOIN #eksikKalan e ON e.StkId = h.ehstkID
            WHERE h.ehAltDepo = 0
              AND h.ehMekan IN (1, 12, 4477, 4478)
              AND h.ehTrhS <= @EnvanterTarihi
              AND h.ehTrhS >= @baslangicTarihi        -- OPT4: alt sinir filtresi
            GROUP BY h.ehstkID, EOMONTH(h.ehTrhS);

            DECLARE @aylikHareketSayisi INT = @@ROWCOUNT;
            PRINT '      Aylik hareket ozet satiri: ' + CAST(@aylikHareketSayisi AS VARCHAR(10));

            -- Adim B: Kumulatif stok hesapla (window function - O(n))
            IF OBJECT_ID('tempdb..#aylikStok', 'U') IS NOT NULL DROP TABLE #aylikStok;

            SELECT
                StkId,
                AyBitis,
                SUM(AyHareket) OVER (
                    PARTITION BY StkId
                    ORDER BY AyBitis
                    ROWS UNBOUNDED PRECEDING
                ) AS AyStok
            INTO #aylikStok
            FROM #aylikHareket;

            -- Sadece pozitif stok olan aylari tut
            DELETE FROM #aylikStok WHERE AyStok <= 0;

            CREATE INDEX IX_tmp_aylikStok ON #aylikStok(StkId, AyBitis);

            PRINT '      [OPT1] Kumulatif stok hesaplandi.';

            -- Ters kumulatif allokasyon (en son aydan geriye)
            IF OBJECT_ID('tempdb..#aylikAlloc', 'U') IS NOT NULL DROP TABLE #aylikAlloc;

            ;WITH Aylik AS (
                SELECT
                    s.StkId, s.AyBitis, s.AyStok,
                    SUM(s.AyStok) OVER (
                        PARTITION BY s.StkId
                        ORDER BY s.AyBitis DESC
                        ROWS UNBOUNDED PRECEDING
                    ) AS KumStok
                FROM #aylikStok s
            ),
            Alloc AS (
                SELECT
                    a.StkId, a.AyBitis,
                    CAST(
                        CASE
                            WHEN a.KumStok <= e.EksikMiktar THEN a.AyStok
                            WHEN a.KumStok - a.AyStok < e.EksikMiktar THEN e.EksikMiktar - (a.KumStok - a.AyStok)
                            ELSE 0
                        END AS DECIMAL(18,4)
                    ) AS AyMiktar
                FROM Aylik a
                JOIN #eksikKalan e ON e.StkId = a.StkId
            )
            SELECT StkId, AyBitis, AyMiktar
            INTO #aylikAlloc
            FROM Alloc WHERE AyMiktar > 0;

            DECLARE @allocSayisi INT = @@ROWCOUNT;
            PRINT '      Alloc kaydi: ' + CAST(@allocSayisi AS VARCHAR(10));

            -- =====================================================
            -- OPTIMIZASYON 2: fn_SonGecerliFiyat_Adv pre-compute
            -- ESKi: OUTER APPLY row-by-row (urun*ay adet cagri)
            -- YENi: Distinct ay basina 1 TVF cagri + LEFT JOIN
            -- =====================================================
            PRINT '      [OPT2] fn_SonGecerliFiyat_Adv pre-compute (ay bazli bulk)...';

            IF OBJECT_ID('tempdb..#sabitFiyat', 'U') IS NOT NULL DROP TABLE #sabitFiyat;
            CREATE TABLE #sabitFiyat (
                StkId INT NOT NULL,
                BirimMaliyet DECIMAL(18,6) NOT NULL
            );

            -- ERP Devir Fiyatlari tablosundan fiyat al
            IF OBJECT_ID('dbo.FifoFallbackFiyatlari', 'U') IS NOT NULL
            BEGIN
                DECLARE @sqlErpDevir NVARCHAR(MAX) = N'
                INSERT INTO #sabitFiyat (StkId, BirimMaliyet)
                SELECT erp.StkId, erp.BirimMaliyet
                FROM dbo.FifoFallbackFiyatlari erp
                WHERE (@StkId IS NULL OR erp.StkId = @StkId)
                  AND (@FallbackSatinalmaSarti IS NULL OR erp.SatinalmaSarti = @FallbackSatinalmaSarti);';

                EXEC sp_executesql
                    @sqlErpDevir,
                    N'@StkId INT, @FallbackSatinalmaSarti VARCHAR(50)',
                    @StkId = @StkId,
                    @FallbackSatinalmaSarti = @FallbackSatinalmaSarti;
            END

            -- =====================================================
            -- FIYAT: TEK CAGRI STRATEJISI
            -- Eski: 55 ay x cursor x fn_SonGecerliFiyat_Adv = 55 dakika
            -- Yeni: 1 cagri (envanter tarihi) = ~60 saniye
            --       Fiyat bulunamayanlar icin 1 ek cagri (6 ay oncesi)
            -- =====================================================
            IF OBJECT_ID('tempdb..#fiyatMaterialize', 'U') IS NOT NULL DROP TABLE #fiyatMaterialize;
            CREATE TABLE #fiyatMaterialize (
                StkId      INT            NOT NULL PRIMARY KEY,
                SonrakiNet DECIMAL(18,6)  NOT NULL
            );

            PRINT '      [OPT2] fn_SonGecerliFiyat_Adv TEK CAGRI...';
            DECLARE @fiyatBaslangic DATETIME2(3) = SYSDATETIME();

            -- 1) Envanter tarihindeki fiyat (tum urunler, ~60sn)
            INSERT INTO #fiyatMaterialize (StkId, SonrakiNet)
            SELECT f.fStkID, f.sonrakiNet
            FROM (
                SELECT
                    f.fStkID, f.sonrakiNet,
                    ROW_NUMBER() OVER (
                        PARTITION BY f.fStkID
                        ORDER BY
                            CASE WHEN f.fFrmID = 9525 THEN 0 ELSE 1 END,
                            f.fTarihSon DESC,
                            f.fhID DESC
                    ) AS rn
                FROM DerinSIS_Local.bkm.fn_SonGecerliFiyat_Adv(@EnvanterTarihi, 1, 1, 1) f
                WHERE f.sonrakiNet > 0
            ) f
            WHERE f.rn = 1;

            DECLARE @fiyatBulunan INT = @@ROWCOUNT;
            PRINT '      Fiyat bulunan (envanter tarihi): ' + CAST(@fiyatBulunan AS VARCHAR(10)) +
                  ' - Sure: ' + CAST(DATEDIFF(SECOND, @fiyatBaslangic, SYSDATETIME()) AS VARCHAR(10)) + 's';

            -- 2) Fiyat bulunamayan urunler icin 6 ay oncesine bak
            DECLARE @eksikFiyatSayisi INT = (
                SELECT COUNT(*) FROM #aylikAlloc a
                WHERE NOT EXISTS (SELECT 1 FROM #fiyatMaterialize fm WHERE fm.StkId = a.StkId)
            );

            PRINT '      Fiyat eksik urun: ' + CAST(@eksikFiyatSayisi AS VARCHAR(10)) + ' (FIYAT_YOK olarak kaydedilecek)';

            -- Ek fiyat arama: sadece eksik cok fazlaysa (>5000) dene, yoksa 48sn bosuna harcanir
            IF @eksikFiyatSayisi > 5000
            BEGIN
                DECLARE @eskiTarih DATE = DATEADD(MONTH, -6, @EnvanterTarihi);
                PRINT '      Fiyat eksik: ' + CAST(@eksikFiyatSayisi AS VARCHAR(10)) + ' urun, 6 ay oncesi deneniyor...';
                SET @fiyatBaslangic = SYSDATETIME();

                INSERT INTO #fiyatMaterialize (StkId, SonrakiNet)
                SELECT f.fStkID, f.sonrakiNet
                FROM (
                    SELECT
                        f.fStkID, f.sonrakiNet,
                        ROW_NUMBER() OVER (
                            PARTITION BY f.fStkID
                            ORDER BY
                                CASE WHEN f.fFrmID = 9525 THEN 0 ELSE 1 END,
                                f.fTarihSon DESC,
                                f.fhID DESC
                        ) AS rn
                    FROM DerinSIS_Local.bkm.fn_SonGecerliFiyat_Adv(@eskiTarih, 1, 1, 1) f
                    WHERE f.sonrakiNet > 0
                      AND f.fStkID NOT IN (SELECT StkId FROM #fiyatMaterialize)
                ) f
                WHERE f.rn = 1;

                DECLARE @ekFiyat INT = @@ROWCOUNT;
                PRINT '      Ek fiyat bulunan (6 ay oncesi): ' + CAST(@ekFiyat AS VARCHAR(10)) +
                      ' - Sure: ' + CAST(DATEDIFF(SECOND, @fiyatBaslangic, SYSDATETIME()) AS VARCHAR(10)) + 's';
            END

            PRINT '      [OPT2] Fiyat materialize tamamlandi.';

            /* Aylik katman fiyatlandirma */
            INSERT INTO #aylikKatman (StkId, AyBitis, AyMiktar, BirimMaliyet, Durum)
            SELECT
                a.StkId,
                a.AyBitis,
                a.AyMiktar,
                COALESCE(fm.SonrakiNet, sf.BirimMaliyet) AS BirimMaliyet,
                CASE
                    WHEN COALESCE(fm.SonrakiNet, sf.BirimMaliyet) IS NULL THEN 'FIYAT_YOK'
                    ELSE 'AYLIK_DEVIR'
                END AS Durum
            FROM #aylikAlloc a
            LEFT JOIN #fiyatMaterialize fm ON fm.StkId = a.StkId
            LEFT JOIN #sabitFiyat       sf ON sf.StkId = a.StkId;

            /* Havuza yaz */
            INSERT INTO dbo.FifoKatman
                (StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
                 GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
            SELECT
                k.StkId, k.AyBitis, 'AYLIK_DEVIR', NULL, k.AyBitis, NULL,
                k.AyMiktar, k.AyMiktar, ISNULL(k.BirimMaliyet, 0), k.Durum
            FROM #aylikKatman k;

            DECLARE @aylikDevir INT = @@ROWCOUNT;
            PRINT '      Aylik devir katman: ' + CAST(@aylikDevir AS VARCHAR(10));
        END

        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='TAMAMLANDI', @Mesaj=NULL;
        PRINT '      Aylik devir tamamlandi. Sure: ' +
              CAST(DATEDIFF(SECOND, @fazBaslangic, SYSDATETIME()) AS VARCHAR(10)) + 's';

        -- --------------------------------------------------------
        -- ADIM 6: Sorun kayitlari
        -- --------------------------------------------------------
        SET @fazBaslangic = SYSDATETIME();
        SET @stepKey = 'sorun_v2';
        SET @stepName = 'Sorun kaydi (V2)';
        SET @stepOrder = 6;
        PRINT '[6/6] Sorun kayitlari yaziliyor...';
        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='CALISIYOR', @Mesaj=NULL;

        DELETE FROM dbo.FifoSorunluStoklar
        WHERE EnvanterTarihi = @EnvanterTarihi
          AND (@StkId IS NULL OR StkId = @StkId);

        /* FIYAT_YOK - aylik devir katmaninda fiyat bulunamadi */
        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT
            k.StkId, @EnvanterTarihi, SUM(k.AyMiktar), 'FIYAT_YOK',
            'Aylik devir katmaninda fiyat bulunamadi.'
        FROM #aylikKatman k
        WHERE k.Durum = 'FIYAT_YOK'
        GROUP BY k.StkId;

        /* ALIS_YOK - hicbir kaynaktan fiyat bulunamadi */
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

        /* ALIS_YOK_MERKEZ_TAMAMLANDI */
        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT
            e.StkId, @EnvanterTarihi, e.StokMiktar, 'ALIS_YOK_MERKEZ_TAMAMLANDI',
            'Merkez depo (12) son alis fiyati ile tamamlandi.'
        FROM #eksikler e
        JOIN #merkezSon ms ON ms.StkId = e.StkId;

        /* ALIS_YOK_SONGECERLI_TAMAMLANDI */
        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT
            e.StkId, @EnvanterTarihi, e.StokMiktar, 'ALIS_YOK_SONGECERLI_TAMAMLANDI',
            'Son gecerli satin alma fiyati (sonrakiNet) ile tamamlandi.'
        FROM #eksikler e
        JOIN #sonGecerli sg ON sg.StkId = e.StkId
        LEFT JOIN (SELECT DISTINCT StkId FROM #alislar) v ON v.StkId = e.StkId
        LEFT JOIN #merkezSon ms ON ms.StkId = e.StkId
        WHERE v.StkId IS NULL AND ms.StkId IS NULL;

        /* ALIS_EKSIK_TAMAMLANDI */
        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT DISTINCT
            e.StkId, @EnvanterTarihi, e.StokMiktar, 'ALIS_EKSIK_TAMAMLANDI',
            'Eksik stok son alis fiyati ile otomatik tamamlandi.'
        FROM #eksikler e
        WHERE e.EksikMiktar > 0 AND e.ToplamAcilisMiktar > 0;

        /* NET GUVENLIK AGI (invariant) — 02_V2 ile ayni: acilis envanterine
           giren her StkId YA FifoKatman YA sorun kaydi almali. Aylik-devir
           bloku atlanir/kenar durumda urun sessizce dusebiliyordu.
           Dogrudan FifoKatman'a karsi dogrular, idempotent.
           Ref: sql-sp-reviewer CRIT-1 (2026-06-06). */
        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        SELECT s.StkId, @EnvanterTarihi, s.StokMiktar, 'FIYAT_YOK',
               'Acilis envanteri var; hicbir kaynak katman kuramadi (net guvenlik agi V2).'
        FROM #stoklar s
        WHERE (@StkId IS NULL OR s.StkId = @StkId)
          AND NOT EXISTS (
              SELECT 1 FROM dbo.FifoKatman k
              WHERE k.StkId = s.StkId AND k.GirisTarihi <= @EnvanterTarihi
          )
          AND NOT EXISTS (
              SELECT 1 FROM dbo.FifoSorunluStoklar fs
              WHERE fs.StkId = s.StkId AND fs.EnvanterTarihi = @EnvanterTarihi
                AND fs.SorunTipi IN ('FIYAT_YOK','ALIS_YOK')
          );

        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu=@stepKey, @AdimAdi=@stepName, @SiraNo=@stepOrder, @Durum='TAMAMLANDI', @Mesaj=NULL;
        PRINT '      Sorun kayitlari tamamlandi. Sure: ' +
              CAST(DATEDIFF(SECOND, @fazBaslangic, SYSDATETIME()) AS VARCHAR(10)) + 's';

        COMMIT TRANSACTION;

        PRINT '========================================';
        PRINT 'sp_Fifo_AcilisCalistir_V2 tamamlandi';
        PRINT 'Tarih: ' + CONVERT(VARCHAR(10), @EnvanterTarihi, 120);
        PRINT 'Bitis: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 121);
        PRINT '========================================';

        RETURN; -- Basarili cikis

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        GOTO HataYonetimi;
    END CATCH

    -- ============================================================
    -- HATA YONETIMI (tum fazlardan ortak)
    -- ============================================================
    HataYonetimi:
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        DECLARE @ErrorLine INT = ERROR_LINE();
        DECLARE @runMessage VARCHAR(500) = SUBSTRING(CONVERT(VARCHAR(500), @ErrorMessage), 1, 500);

        IF @IslemId IS NOT NULL AND @stepKey IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz
                @IslemId = @IslemId,
                @AdimKodu = @stepKey,
                @AdimAdi = @stepName,
                @SiraNo = @stepOrder,
                @Durum = 'HATA',
                @Mesaj = @runMessage;

        INSERT INTO dbo.FifoSorunluStoklar
            (StkId, EnvanterTarihi, StokMiktar, SorunTipi, Aciklama)
        VALUES (0, @EnvanterTarihi, 0, 'PROSEDUR_HATASI',
                'sp_Fifo_AcilisCalistir_V2 - Satir: ' + CAST(@ErrorLine AS VARCHAR(10)) +
                ' - ' + @ErrorMessage);

        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
END
GO

PRINT 'dbo.sp_Fifo_AcilisCalistir_V2 olusturuldu';
GO
