
USE BKMMaliyet;
GO

CREATE OR ALTER PROCEDURE bkm.sp_fifo_StokMaliyetAcilis
(
    @envanterTarihi DATE,
    @stkID INT = NULL,
    @calistirmaId UNIQUEIDENTIFIER = NULL,
    @fallbackSatinalmaSarti VARCHAR(50) = NULL,   -- sadece fallback fiyatlama (acilis) icin
    @atlamaAylikDevir BIT = 0,            -- 1 = Agir aylik devir adimini atla (timeout onleme)
    @sabitFallbackBirimMaliyet DECIMAL(18,6) = NULL -- son care tek seferlik sabit fiyat
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @adimKodu VARCHAR(50) = NULL;
    DECLARE @adimAdi VARCHAR(100) = NULL;
    DECLARE @adimSirasi INT = NULL;
    
    -- Parametre validasyonu
    IF @envanterTarihi IS NULL
    BEGIN
        RAISERROR('Envanter tarihi bos olamaz', 16, 1);
        RETURN;
    END

    IF @sabitFallbackBirimMaliyet IS NOT NULL AND @sabitFallbackBirimMaliyet <= 0
    BEGIN
        RAISERROR('Sabit fallback birim maliyet 0''dan buyuk olmali', 16, 1);
        RETURN;
    END
    
    IF @envanterTarihi > GETDATE()
    BEGIN
        RAISERROR('Envanter tarihi gelecek tarih olamaz', 16, 1);
        RETURN;
    END
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        /* Audit triggeri devre disi birak - toplu INSERT log dolduruyor */
        IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'tr_fifo_StokMaliyetHavuzu_DegisimGunlugu' AND parent_id = OBJECT_ID('bkm.fifo_StokMaliyetHavuzu'))
            ALTER TABLE bkm.fifo_StokMaliyetHavuzu DISABLE TRIGGER tr_fifo_StokMaliyetHavuzu_DegisimGunlugu;
        ELSE IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'tr_fifo_StokMaliyetHavuzu_Audit' AND parent_id = OBJECT_ID('bkm.fifo_StokMaliyetHavuzu'))
            ALTER TABLE bkm.fifo_StokMaliyetHavuzu DISABLE TRIGGER tr_fifo_StokMaliyetHavuzu_Audit;
        
        DECLARE @baslangicTarihi DATE = DATEFROMPARTS(2021, 5, 31);

        SET @adimKodu = 'envanter';
        SET @adimAdi = 'Envanter snapshot';
        SET @adimSirasi = 1;
        PRINT '[1/4] Envanter snapshot - irsHrk okunuyor...';
        IF @calistirmaId IS NOT NULL
            EXEC bkm.sp_fifo_CalistirmaAdim @calistirmaId, @adimKodu, @adimAdi, @adimSirasi, 'CALISIYOR', NULL;

        /* 1) Envanter tarihindeki stok miktarlarinc cek (irsHrk - mekan bazli) */
        IF OBJECT_ID('tempdb..#stoklarMekan', 'U') IS NOT NULL DROP TABLE #stoklarMekan;

        SELECT 
            h.ehMekan AS mekanID,
            h.ehstkID AS stkID,
            SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) AS stokMiktar
        INTO #stoklarMekan
        FROM DerinSISBkm.dbo.irsHrk h WITH(NOLOCK)
        WHERE h.ehTrhS <= @envanterTarihi
          AND h.ehAltDepo = 0
          AND h.ehMekan IN (1, 12, 4477, 4478)
          AND (@stkID IS NULL OR h.ehstkID = @stkID)
        GROUP BY h.ehMekan, h.ehstkID
        HAVING SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) > 0;

        CREATE INDEX IX_tmp_stoklarMekan_mekan_stkID ON #stoklarMekan(mekanID, stkID);

        IF OBJECT_ID('tempdb..#stoklar', 'U') IS NOT NULL DROP TABLE #stoklar;

        SELECT
            stkID,
            SUM(stokMiktar) AS stokMiktar
        INTO #stoklar
        FROM #stoklarMekan
        GROUP BY stkID;

        CREATE INDEX IX_tmp_stoklar_stkID ON #stoklar(stkID);

        DELETE FROM bkm.fifo_StokEnvanter
        WHERE envanterTarihi = @envanterTarihi
          AND (@stkID IS NULL OR stkID = @stkID);

        INSERT INTO bkm.fifo_StokEnvanter (envanterTarihi, mekanID, stkID, stokMiktar)
        SELECT @envanterTarihi, mekanID, stkID, stokMiktar
        FROM #stoklarMekan;

        IF @calistirmaId IS NOT NULL
            EXEC bkm.sp_fifo_CalistirmaAdim @calistirmaId, @adimKodu, @adimAdi, @adimSirasi, 'TAMAMLANDI', NULL;
        PRINT '      Envanter tamamlandi.';

        SET @adimKodu = 'alis';
        SET @adimAdi = 'Alislar toplanir';
        SET @adimSirasi = 2;
        PRINT '[2/4] Alislar toplaniyor (fat+fatAyr)...';
        IF @calistirmaId IS NOT NULL
            EXEC bkm.sp_fifo_CalistirmaAdim @calistirmaId, @adimKodu, @adimAdi, @adimSirasi, 'CALISIYOR', NULL;

        /* 2) Baslangic-envanter arasi alislari cek (SADECE FATURA: fat + fatAyr) */
        IF OBJECT_ID('tempdb..#alislar', 'U') IS NOT NULL DROP TABLE #alislar;

        SELECT 
            a.ehStkID AS stkID,
            f.eTarihS AS girisTarihi,
            f.eNo     AS belgeNo,
            f.eTarihS AS belgeTarihi,
            f.eFirma  AS firmaID,
            SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS miktar,
            SUM(CONVERT(DECIMAL(18,4),
                CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END
            )) AS netTutar
        INTO #alislar
        FROM #stoklar s
        JOIN DerinSISBkm.dbo.fatAyr a WITH(NOLOCK)
            ON a.ehStkID = s.stkID
        JOIN DerinSISBkm.dbo.fat f WITH(NOLOCK)
            ON f.eID = a.ehID
        WHERE a.ehAdetN <> 0
          AND f.eTarihS >  CONVERT(smalldatetime, @baslangicTarihi)
          AND f.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @envanterTarihi))
          AND f.eTip IN (0, 2)
          AND (@stkID IS NULL OR a.ehStkID = @stkID)
        GROUP BY a.ehStkID, f.eTarihS, f.eID, f.eNo, f.eFirma
        HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;

        ALTER TABLE #alislar ADD birimMaliyet DECIMAL(18,6);

        UPDATE #alislar
        SET birimMaliyet = CASE WHEN miktar = 0 THEN 0 ELSE netTutar / miktar END;

        CREATE INDEX IX_tmp_alislar_stkTarih 
            ON #alislar(stkID, girisTarihi DESC, belgeNo);

        IF @calistirmaId IS NOT NULL
            EXEC bkm.sp_fifo_CalistirmaAdim @calistirmaId, @adimKodu, @adimAdi, @adimSirasi, 'TAMAMLANDI', NULL;
        PRINT '      Alislar tamamlandi.';

        SET @adimKodu = 'katman';
        SET @adimAdi = 'Ters FIFO katman';
        SET @adimSirasi = 3;
        PRINT '[3/4] Ters FIFO katman hesaplaniyor...';
        IF @calistirmaId IS NOT NULL
            EXEC bkm.sp_fifo_CalistirmaAdim @calistirmaId, @adimKodu, @adimAdi, @adimSirasi, 'CALISIYOR', NULL;

        /* 3) Ters FIFO ile acilis katmanlarini hesapla */
        IF OBJECT_ID('tempdb..#katman', 'U') IS NOT NULL DROP TABLE #katman;

        ;WITH Ters AS (
            SELECT
                stkID, girisTarihi, belgeNo, belgeTarihi, firmaID, miktar, birimMaliyet, netTutar,
                SUM(miktar) OVER (
                    PARTITION BY stkID
                    ORDER BY girisTarihi DESC, belgeNo DESC
                    ROWS UNBOUNDED PRECEDING
                ) AS kumTers
            FROM #alislar
            WHERE miktar > 0 AND netTutar > 0
        ),
        Acilis AS (
            SELECT
                t.stkID, t.girisTarihi, t.belgeNo, t.belgeTarihi, t.firmaID,
                t.miktar AS satirMiktar, t.birimMaliyet,
                t.kumTers, s.stokMiktar,
                CASE 
                    WHEN t.kumTers - t.miktar >= s.stokMiktar THEN 0
                    WHEN t.kumTers <= s.stokMiktar THEN t.miktar
                    ELSE s.stokMiktar - (t.kumTers - t.miktar)
                END AS acilisMiktar
            FROM Ters t
            JOIN #stoklar s ON s.stkID = t.stkID
        )
        SELECT * INTO #katman FROM Acilis WHERE acilisMiktar > 0;

        /* 4) Gercek alis katmanlarini ACILIS olarak havuza yaz */
        DELETE FROM bkm.fifo_StokMaliyetHavuzu
        WHERE kaynakTip = 'ACILIS' AND girisTarihi = @envanterTarihi
          AND (@stkID IS NULL OR stkID = @stkID);

        INSERT INTO bkm.fifo_StokMaliyetHavuzu
            (stkID, girisTarihi, kaynakTip, belgeNo, belgeTarihi, firmaID,
             miktarToplam, miktarKalan, birimMaliyet, durum)
        SELECT
            stkID, @envanterTarihi, 'ACILIS', belgeNo, belgeTarihi, firmaID,
            acilisMiktar, acilisMiktar, birimMaliyet, 'NORMAL'
        FROM #katman;

        IF @calistirmaId IS NOT NULL
            EXEC bkm.sp_fifo_CalistirmaAdim @calistirmaId, @adimKodu, @adimAdi, @adimSirasi, 'TAMAMLANDI', NULL;
        PRINT '      Katman hesaplamasc tamamlandi.';

        SET @adimKodu = 'sorun';
        SET @adimAdi = 'Sorun kaydi';
        SET @adimSirasi = 4;
        PRINT '[4/4] Tamamlama + sorun kayitlari (merkez, son fiyat, aylik devir)...';
        IF @calistirmaId IS NOT NULL
            EXEC bkm.sp_fifo_CalistirmaAdim @calistirmaId, @adimKodu, @adimAdi, @adimSirasi, 'CALISIYOR', NULL;

        /* 5) Eksik miktarlari tespit et */
        ;WITH Ozet AS (
            SELECT stkID, SUM(acilisMiktar) AS toplamAcilisMiktar
            FROM #katman GROUP BY stkID
        ),
        AlisVarMi AS (
            SELECT DISTINCT stkID FROM #alislar
        )
        SELECT
            s.stkID, s.stokMiktar,
            ISNULL(o.toplamAcilisMiktar, 0) AS toplamAcilisMiktar,
            (s.stokMiktar - ISNULL(o.toplamAcilisMiktar, 0)) AS eksikMiktar
        INTO #eksiklar
        FROM #stoklar s
        LEFT JOIN Ozet o ON o.stkID = s.stkID
        LEFT JOIN AlisVarMi v ON v.stkID = s.stkID;

        /* 6) Alisc olan ama yetmeyenleri son alisla tamamla */
        ;WITH SonAlis AS (
            SELECT
                a.stkID, a.girisTarihi, a.belgeNo, a.belgeTarihi, a.firmaID, a.birimMaliyet,
                ROW_NUMBER() OVER (
                    PARTITION BY a.stkID
                    ORDER BY a.girisTarihi DESC, a.belgeNo DESC
                ) AS rn
            FROM #alislar a
        )
        INSERT INTO bkm.fifo_StokMaliyetHavuzu
            (stkID, girisTarihi, kaynakTip, belgeNo, belgeTarihi, firmaID,
             miktarToplam, miktarKalan, birimMaliyet, durum)
        SELECT
            e.stkID, @envanterTarihi, 'ACILIS_TAMAMLA', sa.belgeNo, sa.belgeTarihi, sa.firmaID,
            e.eksikMiktar, e.eksikMiktar, sa.birimMaliyet, 'TAMAMLAMA'
        FROM #eksiklar e
        JOIN SonAlis sa ON sa.stkID = e.stkID AND sa.rn = 1
        WHERE e.eksikMiktar > 0 AND e.toplamAcilisMiktar > 0;


        /* 7) Sorunlu kayitlari olustur */
        
        /* 6b) Merkez depo (12) alis faturalarc ile tamamlama (alis yoksa) - fat+fatAyr+irs (mekan icin) */
        IF OBJECT_ID('tempdb..#merkezAlis', 'U') IS NOT NULL DROP TABLE #merkezAlis;

        SELECT
            a.ehStkID AS stkID,
            f.eTarihS AS girisTarihi,
            f.eNo     AS belgeNo,
            f.eTarihS AS belgeTarihi,
            f.eFirma  AS firmaID,
            SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS miktar,
            SUM(CONVERT(DECIMAL(18,4),
                CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END
            )) AS netTutar
        INTO #merkezAlis
        FROM #eksiklar e
        LEFT JOIN (SELECT DISTINCT stkID FROM #alislar) v ON v.stkID = e.stkID
        JOIN DerinSISBkm.dbo.fatAyr a WITH(NOLOCK)
            ON a.ehStkID = e.stkID
        JOIN DerinSISBkm.dbo.fat f WITH(NOLOCK)
            ON f.eID = a.ehID
        JOIN DerinSISBkm.dbo.irs i WITH(NOLOCK)
            ON i.eID = a.ehIrsID
           AND i.eMekan = 12
        WHERE a.ehAdetN <> 0
          AND v.stkID IS NULL
          AND e.eksikMiktar > 0
          AND f.eTarihS >  CONVERT(smalldatetime, @baslangicTarihi)
          AND f.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @envanterTarihi))
          AND f.eTip IN (0, 2)
          AND (@stkID IS NULL OR a.ehStkID = @stkID)
        GROUP BY a.ehStkID, f.eTarihS, f.eID, f.eNo, f.eFirma
        HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;

        ALTER TABLE #merkezAlis ADD birimMaliyet DECIMAL(18,6);
        UPDATE #merkezAlis
        SET birimMaliyet = CASE WHEN miktar = 0 THEN 0 ELSE netTutar / miktar END;

        IF OBJECT_ID('tempdb..#merkezSon', 'U') IS NOT NULL DROP TABLE #merkezSon;

        ;WITH SonMerkez AS (
            SELECT
                m.stkID, m.girisTarihi, m.belgeNo, m.belgeTarihi, m.firmaID, m.birimMaliyet,
                ROW_NUMBER() OVER (
                    PARTITION BY m.stkID
                    ORDER BY m.girisTarihi DESC, m.belgeNo DESC
                ) AS rn
            FROM #merkezAlis m
        )
        SELECT
            stkID, girisTarihi, belgeNo, belgeTarihi, firmaID, birimMaliyet
        INTO #merkezSon
        FROM SonMerkez
        WHERE rn = 1;

        INSERT INTO bkm.fifo_StokMaliyetHavuzu
            (stkID, girisTarihi, kaynakTip, belgeNo, belgeTarihi, firmaID,
             miktarToplam, miktarKalan, birimMaliyet, durum)
        SELECT
            e.stkID, @envanterTarihi, 'ACILIS_TAMAMLA', ms.belgeNo, ms.belgeTarihi, ms.firmaID,
            e.eksikMiktar, e.eksikMiktar, ms.birimMaliyet, 'MERKEZ_TAMAMLAMA'
        FROM #eksiklar e
        JOIN #merkezSon ms ON ms.stkID = e.stkID
        LEFT JOIN (SELECT DISTINCT stkID FROM #alislar) v ON v.stkID = e.stkID
        WHERE v.stkID IS NULL AND e.eksikMiktar > 0;

        /* 6c) Son gecerli fiyat ile tamamlama (alis yoksa, merkez de yoksa) */
        IF OBJECT_ID('tempdb..#sonGecerli', 'U') IS NOT NULL DROP TABLE #sonGecerli;

        ;WITH SonFiyat AS (
            SELECT
                f.fhID,
                f.fStkID AS stkID,
                f.fTarih,
                f.fTarihSon,
                f.sonrakiNet,
                ROW_NUMBER() OVER (
                    PARTITION BY f.fStkID
                    ORDER BY f.fTarihSon DESC, f.fhID DESC
                ) AS rn
            FROM DerinSISBkm.bkm.fn_SonGecerliFiyat(@envanterTarihi, 1) f
            WHERE f.sonrakiNet > 0
        )
        SELECT
            stkID,
            fhID,
            fTarih,
            fTarihSon,
            sonrakiNet
        INTO #sonGecerli
        FROM SonFiyat
        WHERE rn = 1;

        INSERT INTO bkm.fifo_StokMaliyetHavuzu
            (stkID, girisTarihi, kaynakTip, belgeNo, belgeTarihi, firmaID,
             miktarToplam, miktarKalan, birimMaliyet, durum)
        SELECT
            e.stkID,
            @envanterTarihi,
            'ACILIS_TAMAMLA',
            CAST(sg.fhID AS VARCHAR(50)),
            CAST(sg.fTarihSon AS DATE),
            NULL,
            e.eksikMiktar,
            e.eksikMiktar,
            sg.sonrakiNet,
            'SART_TAMAMLAMA'
        FROM #eksiklar e
        JOIN #sonGecerli sg ON sg.stkID = e.stkID
        LEFT JOIN (SELECT DISTINCT stkID FROM #alislar) v ON v.stkID = e.stkID
        LEFT JOIN #merkezSon ms ON ms.stkID = e.stkID
        WHERE v.stkID IS NULL
          AND ms.stkID IS NULL
          AND e.eksikMiktar > 0;

        /* 6d) Aylik devir ile tamamlama (alis/merkez/sart yoksa) - @atlamaAylikDevir=1 ise atlanAr (timeout onleme) */
        IF OBJECT_ID('tempdb..#eksikKalan', 'U') IS NOT NULL DROP TABLE #eksikKalan;

        SELECT e.stkID, e.eksikMiktar
        INTO #eksikKalan
        FROM #eksiklar e
        LEFT JOIN (SELECT DISTINCT stkID FROM #alislar) v ON v.stkID = e.stkID
        LEFT JOIN #merkezSon ms ON ms.stkID = e.stkID
        LEFT JOIN #sonGecerli sg ON sg.stkID = e.stkID
        WHERE e.eksikMiktar > 0 AND v.stkID IS NULL AND ms.stkID IS NULL AND sg.stkID IS NULL;

        IF OBJECT_ID('tempdb..#aylikKatman', 'U') IS NOT NULL DROP TABLE #aylikKatman;
        CREATE TABLE #aylikKatman (
            stkID INT NOT NULL,
            ayBitis DATE NOT NULL,
            ayMiktar DECIMAL(18,4) NOT NULL,
            birimMaliyet DECIMAL(18,6) NULL,
            durum VARCHAR(20) NOT NULL
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
                    ayBas = DATEFROMPARTS(YEAR(@envanterTarihi), MONTH(@envanterTarihi), 1),
                    ayBitis = EOMONTH(@envanterTarihi)
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
                stkID INT NOT NULL,
                ayBitis DATE NOT NULL,
                ayStok DECIMAL(18,4) NOT NULL
            );

            /* irsHrk ile gecmis stok - tek sorgu, mekan bazli toplam */
            INSERT INTO #aylikStok (stkID, ayBitis, ayStok)
            SELECT
                h.ehstkID AS stkID,
                a.ayBitis,
                SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) AS ayStok
            FROM DerinSISBkm.dbo.irsHrk h WITH(NOLOCK)
            JOIN #aylar a ON h.ehTrhS <= DATEADD(DAY, 1, a.ayBitis)
            JOIN #eksikKalan e ON e.stkID = h.ehstkID
            WHERE h.ehAltDepo = 0
              AND h.ehMekan IN (1, 12, 4477, 4478)
            GROUP BY h.ehstkID, a.ayBitis
            HAVING SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) > 0;

            IF OBJECT_ID('tempdb..#aylikAlloc', 'U') IS NOT NULL DROP TABLE #aylikAlloc;

            ;WITH Aylik AS (
                SELECT
                    s.stkID, s.ayBitis, s.ayStok,
                    SUM(s.ayStok) OVER (
                        PARTITION BY s.stkID
                        ORDER BY s.ayBitis DESC
                        ROWS UNBOUNDED PRECEDING
                    ) AS kumStok
                FROM #aylikStok s
            ),
            Alloc AS (
                SELECT
                    a.stkID, a.ayBitis,
                    CAST(
                        CASE
                            WHEN a.kumStok <= e.eksikMiktar THEN a.ayStok
                            WHEN a.kumStok - a.ayStok < e.eksikMiktar THEN e.eksikMiktar - (a.kumStok - a.ayStok)
                            ELSE 0
                        END AS DECIMAL(18,4)
                    ) AS ayMiktar
                FROM Aylik a
                JOIN #eksikKalan e ON e.stkID = a.stkID
            )
            SELECT * INTO #aylikAlloc FROM Alloc WHERE ayMiktar > 0;

            IF OBJECT_ID('tempdb..#sabitFiyat', 'U') IS NOT NULL DROP TABLE #sabitFiyat;
            CREATE TABLE #sabitFiyat (
                stkID INT NOT NULL,
                birimMaliyet DECIMAL(18,6) NOT NULL
            );

            -- ERP Devir Fiyatlari tablosundan fiyat al (satinalma serti ile)
            IF OBJECT_ID('bkm.fifo_ErpDevirFiyatlari', 'U') IS NOT NULL
            BEGIN
                DECLARE @sqlErpDevir NVARCHAR(MAX) = N'
                INSERT INTO #sabitFiyat (stkID, birimMaliyet)
                SELECT erp.stkID, erp.birimMaliyet
                FROM bkm.fifo_ErpDevirFiyatlari erp
                WHERE (@stkID IS NULL OR erp.stkID = @stkID)
                  AND (@fallbackSatinalmaSarti IS NULL OR erp.satinalmaSarti = @fallbackSatinalmaSarti);';

                EXEC sp_executesql
                    @sqlErpDevir,
                    N'@stkID INT, @fallbackSatinalmaSarti VARCHAR(50)',
                    @stkID = @stkID,
                    @fallbackSatinalmaSarti = @fallbackSatinalmaSarti;
            END

            INSERT INTO #aylikKatman (stkID, ayBitis, ayMiktar, birimMaliyet, durum)
            SELECT
                a.stkID,
                a.ayBitis,
                a.ayMiktar,
                COALESCE(fiyat.sonrakiNet, sf.birimMaliyet) AS birimMaliyet,
                CASE
                    WHEN COALESCE(fiyat.sonrakiNet, sf.birimMaliyet) IS NULL THEN 'FIYAT_YOK'
                    ELSE 'AYLIK_DEVIR'
                END AS durum
            FROM #aylikAlloc a
            OUTER APPLY (
                SELECT TOP (1)
                    f.sonrakiNet,
                    f.fFrmID,
                    f.fTarihSon,
                    f.fhID
                FROM DerinSISBkm.bkm.fn_SonGecerliFiyat_Adv(a.ayBitis, 1, 1, 1) f
                WHERE f.fStkID = a.stkID
                  AND f.sonrakiNet > 0
                  AND (f.fTarihSon IS NULL OR f.fTarihSon >= a.ayBitis)
                ORDER BY
                    CASE WHEN f.fFrmID = 9525 THEN 0 ELSE 1 END,
                    f.fTarihSon DESC,
                    f.fhID DESC
            ) fiyat
            LEFT JOIN #sabitFiyat sf ON sf.stkID = a.stkID;

            IF @sabitFallbackBirimMaliyet IS NOT NULL
            BEGIN
                UPDATE k
                SET
                    k.birimMaliyet = @sabitFallbackBirimMaliyet,
                    k.durum = 'SABIT_FIYAT_TAMAMLAMA'
                FROM #aylikKatman k
                WHERE k.durum = 'FIYAT_YOK';
            END

            INSERT INTO bkm.fifo_StokMaliyetHavuzu
            (stkID, girisTarihi, kaynakTip, belgeNo, belgeTarihi, firmaID,
                 miktarToplam, miktarKalan, birimMaliyet, durum)
            SELECT
                k.stkID, k.ayBitis, 'AYLIK_DEVIR', NULL, k.ayBitis, NULL,
                k.ayMiktar, k.ayMiktar, ISNULL(k.birimMaliyet, 0), k.durum
            FROM #aylikKatman k
            WHERE k.birimMaliyet IS NOT NULL
              AND k.birimMaliyet > 0;
        END

        DELETE FROM bkm.fifo_StokMaliyetSorunlu
        WHERE envanterTarihi = @envanterTarihi
          AND (@stkID IS NULL OR stkID = @stkID);

        INSERT INTO bkm.fifo_StokMaliyetSorunlu
            (stkID, envanterTarihi, stokMiktar, sorunTip, aciklama)
        SELECT
            k.stkID, @envanterTarihi, SUM(k.ayMiktar), 'FIYAT_YOK',
            'Aylik devir katmaninda fiyat bulunamadi.'
        FROM #aylikKatman k
        WHERE k.durum = 'FIYAT_YOK'
        GROUP BY k.stkID;

        INSERT INTO bkm.fifo_StokMaliyetSorunlu
            (stkID, envanterTarihi, stokMiktar, sorunTip, aciklama)
        SELECT
            k.stkID, @envanterTarihi, SUM(k.ayMiktar), 'SABIT_FIYAT_TAMAMLANDI',
            'Aylik devir katmani sabit fiyat ile tamamlandi. Fiyat=' +
            CONVERT(VARCHAR(30), @sabitFallbackBirimMaliyet)
        FROM #aylikKatman k
        WHERE k.durum = 'SABIT_FIYAT_TAMAMLAMA'
        GROUP BY k.stkID;

        INSERT INTO bkm.fifo_StokMaliyetSorunlu
            (stkID, envanterTarihi, stokMiktar, sorunTip, aciklama)
        SELECT
            s.stkID, @envanterTarihi, s.stokMiktar, 'ALIS_YOK',
            'Bu urune belirtilen tarih araliginda hic alis bulunamadi.'
        FROM #stoklar s
        LEFT JOIN (SELECT DISTINCT stkID FROM #alislar) v ON v.stkID = s.stkID
        LEFT JOIN #merkezSon ms ON ms.stkID = s.stkID
        LEFT JOIN #sonGecerli sg ON sg.stkID = s.stkID
        LEFT JOIN (SELECT DISTINCT stkID FROM #aylikKatman) ak ON ak.stkID = s.stkID
        WHERE v.stkID IS NULL AND ms.stkID IS NULL AND sg.stkID IS NULL AND ak.stkID IS NULL;


        INSERT INTO bkm.fifo_StokMaliyetSorunlu
            (stkID, envanterTarihi, stokMiktar, sorunTip, aciklama)
        SELECT
            e.stkID, @envanterTarihi, e.stokMiktar, 'ALIS_YOK_MERKEZ_TAMAMLANDI',
            'Merkez depo (12) son alis fiyati ile tamamlandi.'
        FROM #eksiklar e
        JOIN #merkezSon ms ON ms.stkID = e.stkID;

        INSERT INTO bkm.fifo_StokMaliyetSorunlu
            (stkID, envanterTarihi, stokMiktar, sorunTip, aciklama)
        SELECT
            e.stkID, @envanterTarihi, e.stokMiktar, 'ALIS_YOK_SONGECERLI_TAMAMLANDI',
            'Son gecerli satin alma fiyati (sonrakiNet) ile tamamlandi.'
        FROM #eksiklar e
        JOIN #sonGecerli sg ON sg.stkID = e.stkID
        LEFT JOIN (SELECT DISTINCT stkID FROM #alislar) v ON v.stkID = e.stkID
        LEFT JOIN #merkezSon ms ON ms.stkID = e.stkID
        WHERE v.stkID IS NULL AND ms.stkID IS NULL;

        INSERT INTO bkm.fifo_StokMaliyetSorunlu
            (stkID, envanterTarihi, stokMiktar, sorunTip, aciklama)
        SELECT DISTINCT
            e.stkID, @envanterTarihi, e.stokMiktar, 'ALIS_EKSIK_TAMAMLANDI',
            'Eksik stok son alis fiyati ile otomatik tamamlandi.'
        FROM #eksiklar e
        WHERE e.eksikMiktar > 0 AND e.toplamAcilisMiktar > 0;

        IF @calistirmaId IS NOT NULL
            EXEC bkm.sp_fifo_CalistirmaAdim @calistirmaId, @adimKodu, @adimAdi, @adimSirasi, 'TAMAMLANDI', NULL;

        /* Audit triggeri tekrar etkinlestir */
        IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'tr_fifo_StokMaliyetHavuzu_DegisimGunlugu' AND parent_id = OBJECT_ID('bkm.fifo_StokMaliyetHavuzu'))
            ALTER TABLE bkm.fifo_StokMaliyetHavuzu ENABLE TRIGGER tr_fifo_StokMaliyetHavuzu_DegisimGunlugu;
        ELSE IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'tr_fifo_StokMaliyetHavuzu_Audit' AND parent_id = OBJECT_ID('bkm.fifo_StokMaliyetHavuzu'))
            ALTER TABLE bkm.fifo_StokMaliyetHavuzu ENABLE TRIGGER tr_fifo_StokMaliyetHavuzu_Audit;

        COMMIT TRANSACTION;
        
        PRINT 'Acilis stoku basariyla olusturuldu. Tarih: ' + 
              CONVERT(VARCHAR(10), @envanterTarihi, 120);
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        /* Hata durumunda rollback sonrasinda triggeri tekrar etkinlestir */
        IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'tr_fifo_StokMaliyetHavuzu_DegisimGunlugu' AND parent_id = OBJECT_ID('bkm.fifo_StokMaliyetHavuzu'))
            ALTER TABLE bkm.fifo_StokMaliyetHavuzu ENABLE TRIGGER tr_fifo_StokMaliyetHavuzu_DegisimGunlugu;
        ELSE IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'tr_fifo_StokMaliyetHavuzu_Audit' AND parent_id = OBJECT_ID('bkm.fifo_StokMaliyetHavuzu'))
            ALTER TABLE bkm.fifo_StokMaliyetHavuzu ENABLE TRIGGER tr_fifo_StokMaliyetHavuzu_Audit;
            
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @runMessage VARCHAR(500) = SUBSTRING(CONVERT(VARCHAR(500), @ErrorMessage), 1, 500);

        IF @calistirmaId IS NOT NULL AND @adimKodu IS NOT NULL
            EXEC bkm.sp_fifo_CalistirmaAdim
                @calistirmaId = @calistirmaId,
                @adimKodu = @adimKodu,
                @adimAdi = @adimAdi,
                @adimSirasi = @adimSirasi,
                @durum = 'HATA',
                @mesaj = @runMessage;
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        DECLARE @ErrorLine INT = ERROR_LINE();
        
        INSERT INTO bkm.fifo_StokMaliyetSorunlu
            (stkID, envanterTarihi, stokMiktar, sorunTip, aciklama)
        VALUES (0, @envanterTarihi, 0, 'PROSEDUR_HATASI', 
                'sp_fifo_StokMaliyetAcilis - Satir: ' + CAST(@ErrorLine AS VARCHAR(10)) + 
                ' - ' + @ErrorMessage);
        
        THROW;
    END CATCH
END
GO

PRINT 'sp_fifo_StokMaliyetAcilis proseduru olusturuldu';
GO

PRINT '';

PRINT '3/6 - Alis katmanlari proseduru olusturuluyor...';
GO

-- =============================================================
-- ALIS KATMANLARI PROSEDURU - bkm.sp_fifo_StokMaliyetAlisKatman
-- SADECE FATURA: fat + fatAyr (irs/irsAyr yok)
-- =============================================================

CREATE OR ALTER PROCEDURE bkm.sp_fifo_StokMaliyetAlisKatman
(
    @baslangicTarihi DATE,
    @bitisTarihi DATE,
    @stkID INT = NULL,
    @calistirmaId UNIQUEIDENTIFIER = NULL
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
            a.ehStkID AS stkID,
            f.eTarihS AS girisTarihi,
            f.eNo     AS belgeNo,
            f.eTarihS AS belgeTarihi,
            f.eFirma  AS firmaID,
            SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS miktar,
            SUM(CONVERT(DECIMAL(18,4),
                CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END
            )) AS netTutar
        INTO #alislar
        FROM DerinSISBkm.dbo.fatAyr a WITH(NOLOCK)
        JOIN DerinSISBkm.dbo.fat f WITH(NOLOCK)
            ON f.eID = a.ehID
        WHERE a.ehAdetN <> 0
          AND f.eTarihS >  CONVERT(smalldatetime, @baslangicTarihi)
          AND f.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @bitisTarihi))
          AND f.eTip IN (0, 2)
          AND (@stkID IS NULL OR a.ehStkID = @stkID)
        GROUP BY a.ehStkID, f.eTarihS, f.eID, f.eNo, f.eFirma
        HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;

        /* Birim maliyet hesapla */
        ALTER TABLE #alislar ADD birimMaliyet DECIMAL(18,6);

        UPDATE #alislar
        SET birimMaliyet = CASE WHEN miktar = 0 THEN 0 ELSE netTutar / miktar END;

        -- Constraint uyumsuz (iade/ters/fiyatsiz) satirlari ALIS havuzuna yazma.
        DELETE FROM #alislar
        WHERE miktar <= 0
           OR netTutar <= 0
           OR birimMaliyet <= 0;

        /* Aync tarih araligindaki eski ALIS katmanlarini sil */
        DELETE FROM bkm.fifo_StokMaliyetHavuzu
        WHERE kaynakTip = 'ALIS'
          AND girisTarihi >  @baslangicTarihi
          AND girisTarihi <= @bitisTarihi
          AND (@stkID IS NULL OR stkID = @stkID);

        /* Yeni ALIS katmanlarini havuza yaz */
        INSERT INTO bkm.fifo_StokMaliyetHavuzu
            (stkID, girisTarihi, kaynakTip, belgeNo, belgeTarihi, firmaID,
             miktarToplam, miktarKalan, birimMaliyet, durum)
        SELECT
            stkID, girisTarihi, 'ALIS', belgeNo, belgeTarihi, firmaID,
            miktar, miktar, birimMaliyet, 'NORMAL'
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

PRINT 'sp_fifo_StokMaliyetAlisKatman proseduru olusturuldu';
GO

PRINT '';

PRINT '4/6 - FIFO cikis proseduru olusturuluyor...';
GO

-- =============================================================
-- FIFO CIKIS PROSEDURU - bkm.sp_fifo_StokMaliyetFIFOCikis
-- POS iade mantigi, miktarKalan guncelleme, yetersiz stok kontrolu ile
-- =============================================================

CREATE OR ALTER PROCEDURE bkm.sp_fifo_StokMaliyetFIFOCikis
(
    @satisBaslangic DATE,
    @satisBitis DATE,
    @stkID INT = NULL,
    @calistirmaId UNIQUEIDENTIFIER = NULL
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

        /* RERUN-SAFE (alpha): Ayni donem daha once hesaplandiysa eski cikis tuketimini havuza geri yukle.
           Not: Gec donemler hesaplandiysa gecmise donuk rerun yine risklidir; son/cari donem rerun hedeflenir. */
        UPDATE h
        SET h.miktarKalan = h.miktarKalan + d.toplamCikis
        FROM bkm.fifo_StokMaliyetHavuzu h
        JOIN (
            SELECT c.katmanID, SUM(c.miktar) AS toplamCikis
            FROM bkm.fifo_StokMaliyetCikis c
            WHERE c.hareketTarihi >= @satisBaslangic
              AND c.hareketTarihi <= @satisBitis
              AND (@stkID IS NULL OR c.stkID = @stkID)
            GROUP BY c.katmanID
        ) d ON d.katmanID = h.ID;

        /* 1) Havuzdaki tum katmanlari al */
        IF OBJECT_ID('tempdb..#katman', 'U') IS NOT NULL DROP TABLE #katman;

        SELECT
            h.ID AS katmanID, h.stkID, h.girisTarihi,
            ISNULL(h.belgeTarihi, h.girisTarihi) AS fifoSiraTarihi,
            h.belgeNo AS girisBelgeNo,
            TRY_CONVERT(BIGINT, h.belgeNo) AS fifoSiraBelgeNoNum,
            h.miktarKalan AS miktarToplam,
            h.birimMaliyet
        INTO #katman
        FROM bkm.fifo_StokMaliyetHavuzu h
        WHERE h.girisTarihi <= @satisBitis
          -- Only include sources that are actually written by this deployment.
          AND h.kaynakTip IN ('ACILIS','ACILIS_TAMAMLA','ALIS','AYLIK_DEVIR','SENTETIK_ALIS')
          AND h.miktarKalan > 0
          AND (@stkID IS NULL OR h.stkID = @stkID);

        CREATE INDEX IX_tmp_katman_stkID
            ON #katman(stkID, fifoSiraTarihi, fifoSiraBelgeNoNum, girisBelgeNo, katmanID);

        /* 2) Satis hareketlerini al - POS IADE MANTIGI ILE */
        IF OBJECT_ID('tempdb..#satislar', 'U') IS NOT NULL DROP TABLE #satislar;

        SELECT
            ID = IDENTITY(INT,1,1),
            dt.ehStkID AS stkID,
            bs.eMekan AS mekanID,
            CAST(bs.eTarihS AS DATE) AS satisTarihi,
            netMiktar = SUM(CONVERT(DECIMAL(18,4), dt.ehAdet))
        INTO #satislar
        FROM DerinSISBkm.dbo.irs bs WITH(NOLOCK)
        JOIN DerinSISBkm.dbo.irsAyr dt WITH(NOLOCK) ON dt.ehID = bs.eID
        WHERE bs.eTip IN (1,4,5,100,101)
          AND bs.eMekan IN (1, 12, 4477, 4478)
          AND bs.eTarihS >= CONVERT(smalldatetime, @satisBaslangic)
          AND bs.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @satisBitis))
          AND (@stkID IS NULL OR dt.ehStkID = @stkID)
        GROUP BY dt.ehStkID, bs.eMekan, CAST(bs.eTarihS AS DATE);

        CREATE INDEX IX_tmp_satislar_stkID
            ON #satislar(stkID, satisTarihi, mekanID, ID);

        /* 3) Katmanlar icin kumulatif */
        IF OBJECT_ID('tempdb..#katmanCum', 'U') IS NOT NULL DROP TABLE #katmanCum;

        SELECT
            k.katmanID, k.stkID, k.girisTarihi, k.fifoSiraTarihi, k.girisBelgeNo, k.fifoSiraBelgeNoNum,
            k.miktarToplam, k.birimMaliyet,
            layerCumEnd = SUM(k.miktarToplam) OVER (
                PARTITION BY k.stkID
                ORDER BY
                    k.fifoSiraTarihi,
                    CASE WHEN k.fifoSiraBelgeNoNum IS NULL THEN 1 ELSE 0 END,
                    k.fifoSiraBelgeNoNum,
                    k.girisBelgeNo,
                    k.katmanID
            ),
            layerCumStart = SUM(k.miktarToplam) OVER (
                PARTITION BY k.stkID
                ORDER BY
                    k.fifoSiraTarihi,
                    CASE WHEN k.fifoSiraBelgeNoNum IS NULL THEN 1 ELSE 0 END,
                    k.fifoSiraBelgeNoNum,
                    k.girisBelgeNo,
                    k.katmanID
            ) - k.miktarToplam
        INTO #katmanCum
        FROM #katman k;

        CREATE INDEX IX_tmp_katmanCum_stkID
            ON #katmanCum(stkID, layerCumStart, layerCumEnd);

        /* 4) Satislar icin kumulatif */
        IF OBJECT_ID('tempdb..#satisCum', 'U') IS NOT NULL DROP TABLE #satisCum;

        SELECT
            s.ID AS satisID, s.stkID, s.mekanID, s.satisTarihi,
            s.netMiktar AS miktar,
            satisCumEnd = SUM(ABS(s.netMiktar)) OVER (
                PARTITION BY s.stkID
                ORDER BY s.satisTarihi, s.mekanID, s.ID
            ),
            satisCumStart = SUM(ABS(s.netMiktar)) OVER (
                PARTITION BY s.stkID
                ORDER BY s.satisTarihi, s.mekanID, s.ID
            ) - ABS(s.netMiktar)
        INTO #satisCum
        FROM #satislar s
        WHERE s.netMiktar <> 0;

        CREATE INDEX IX_tmp_satisCum_stkID
            ON #satisCum(stkID, satisCumStart, satisCumEnd);

        /* 5) FIFO kesisim */
        IF OBJECT_ID('tempdb..#cikisDetay', 'U') IS NOT NULL DROP TABLE #cikisDetay;

        SELECT
            c.stkID, c.mekanID AS satisMekanID, c.satisTarihi, c.satisID,
            c.miktar AS satirNetMiktar,
            l.katmanID, l.girisTarihi AS katmanTarihi,
            l.girisBelgeNo, l.birimMaliyet,
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
          ON l.stkID = c.stkID
         AND l.layerCumEnd > c.satisCumStart
         AND c.satisCumEnd > l.layerCumStart;

        DELETE FROM #cikisDetay WHERE cikisMiktar <= 0;

        /* 6) YETERSIZ STOK KONTROLU */
        DELETE FROM bkm.fifo_StokMaliyetSorunlu
        WHERE sorunTip = 'STOK_YETERSIZ'
          AND envanterTarihi >= @satisBaslangic
          AND envanterTarihi <= @satisBitis
          AND (@stkID IS NULL OR stkID = @stkID);

        INSERT INTO bkm.fifo_StokMaliyetSorunlu
            (stkID, envanterTarihi, stokMiktar, sorunTip, aciklama)
        SELECT
            s.stkID,
            @satisBitis,
            s.toplamSatisMiktar - ISNULL(d.toplamKarsilananMiktar, 0) AS eksikMiktar,
            'STOK_YETERSIZ',
            'Donem satis miktari (' + CAST(s.toplamSatisMiktar AS VARCHAR(20)) +
            ') mevcut katmanlarla karsilanan miktari (' + CAST(ISNULL(d.toplamKarsilananMiktar, 0) AS VARCHAR(20)) +
            ') asiyor.'
        FROM (
            SELECT
                stkID,
                SUM(ABS(netMiktar)) AS toplamSatisMiktar
            FROM #satislar
            WHERE netMiktar <> 0
            GROUP BY stkID
        ) s
        LEFT JOIN (
            SELECT
                stkID,
                SUM(ABS(cikisMiktar)) AS toplamKarsilananMiktar
            FROM #cikisDetay
            GROUP BY stkID
        ) d ON d.stkID = s.stkID
        WHERE s.toplamSatisMiktar > ISNULL(d.toplamKarsilananMiktar, 0);

        /* 7) SONUCLARI TABLOYA YAZ */
        DELETE FROM bkm.fifo_StokMaliyetCikis
        WHERE hareketTarihi >= @satisBaslangic
          AND hareketTarihi <= @satisBitis
          AND (@stkID IS NULL OR stkID = @stkID);

        INSERT INTO bkm.fifo_StokMaliyetCikis
            (stkID, hareketTarihi, hareketTipi, hareketMekanID, katmanID, 
             katmanTarihi, katmanBelgeNo, miktar, birimMaliyet)
        SELECT
            d.stkID, d.satisTarihi,
            CASE WHEN d.satirNetMiktar < 0 THEN 'SATIS' ELSE 'IADE' END,
            d.satisMekanID,
            d.katmanID, d.katmanTarihi, d.girisBelgeNo,
            d.cikisMiktar, d.birimMaliyet
        FROM #cikisDetay d;

        /* 8) KATMAN KALAN MIKTARLARINI GUNCELLE */
        UPDATE h
        SET h.miktarKalan = h.miktarKalan - d.toplamCikis
        FROM bkm.fifo_StokMaliyetHavuzu h
        JOIN (
            SELECT katmanID, SUM(ABS(cikisMiktar)) AS toplamCikis
            FROM #cikisDetay
            GROUP BY katmanID
        ) d ON d.katmanID = h.ID
        WHERE h.miktarKalan > 0;

        COMMIT TRANSACTION;
        
        SELECT
            stkID, hareketTarihi, hareketTipi, hareketMekanID, katmanID,
            katmanTarihi, katmanBelgeNo, miktar, birimMaliyet, cikisTutar
        FROM bkm.fifo_StokMaliyetCikis
        WHERE hareketTarihi >= @satisBaslangic
          AND hareketTarihi <= @satisBitis
          AND (@stkID IS NULL OR stkID = @stkID)
        ORDER BY stkID, hareketTarihi, hareketMekanID, katmanTarihi, katmanID;
        
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

PRINT 'sp_fifo_StokMaliyetFIFOCikis proseduru olusturuldu';
GO

PRINT '';

PRINT '5/6 - Toplu calistirma proseduru olusturuluyor...';
GO

-- =============================================================
-- TOPLU FIFO CALISTIRMA PROSEDURU
-- Amac: Manuel ve job calistirmalari ayni SP uzerinden yapmak
-- Not: Acilis/aylik ayri izleme icin yeni wrapper'lar tercih edilir:
--      sp_fifo_AcilisCalistir / sp_fifo_AylikCalistir / sp_fifo_AylikRutinAlpha
-- =============================================================


CREATE OR ALTER PROCEDURE bkm.sp_fifo_CalistirmaAdim
(
    @calistirmaId UNIQUEIDENTIFIER,
    @adimKodu VARCHAR(50),
    @adimAdi VARCHAR(100),
    @adimSirasi INT,
    @durum VARCHAR(20),
    @mesaj VARCHAR(500) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @calistirmaId IS NULL OR @adimKodu IS NULL
        RETURN;

    -- FK (fifo_CalistirmaAdim -> fifo_Calistirma) icin parent kayit yoksa otomatik olustur.
    IF NOT EXISTS (SELECT 1 FROM bkm.fifo_Calistirma WHERE calistirmaId = @calistirmaId)
    BEGIN
        INSERT INTO bkm.fifo_Calistirma
            (calistirmaId, calistirmaTipi, durum, talepTarihi, baslamaTarihi, bitisTarihi, mesaj)
        VALUES
            (
                @calistirmaId,
                'MANUEL',
                CASE
                    WHEN @durum IN ('TAMAMLANDI', 'HATA', 'ATLANDI') THEN @durum
                    ELSE 'BEKLIYOR'
                END,
                GETDATE(),
                CASE WHEN @durum IN ('CALISIYOR', 'TAMAMLANDI', 'HATA', 'ATLANDI') THEN GETDATE() ELSE NULL END,
                CASE WHEN @durum IN ('TAMAMLANDI', 'HATA', 'ATLANDI') THEN GETDATE() ELSE NULL END,
                NULL
            );
    END

    IF EXISTS (SELECT 1 FROM bkm.fifo_CalistirmaAdim WHERE calistirmaId = @calistirmaId AND adimKodu = @adimKodu)
    BEGIN
        UPDATE bkm.fifo_CalistirmaAdim
        SET durum = @durum,
            adimAdi = @adimAdi,
            adimSirasi = @adimSirasi,
            mesaj = @mesaj,
            baslamaTarihi = CASE
                WHEN @durum IN ('CALISIYOR','TAMAMLANDI','HATA','ATLANDI') AND baslamaTarihi IS NULL THEN GETDATE()
                ELSE baslamaTarihi
            END,
            bitisTarihi = CASE
                WHEN @durum IN ('TAMAMLANDI','HATA','ATLANDI') THEN GETDATE()
                ELSE bitisTarihi
            END,
            guncellemeTarihi = GETDATE()
        WHERE calistirmaId = @calistirmaId AND adimKodu = @adimKodu;
    END
    ELSE
    BEGIN
        INSERT INTO bkm.fifo_CalistirmaAdim
            (calistirmaId, adimKodu, adimAdi, adimSirasi, durum, mesaj, baslamaTarihi, bitisTarihi)
        VALUES
            (@calistirmaId, @adimKodu, @adimAdi, @adimSirasi, @durum, @mesaj,
             CASE WHEN @durum IN ('CALISIYOR','TAMAMLANDI','HATA','ATLANDI') THEN GETDATE() ELSE NULL END,
             CASE WHEN @durum IN ('TAMAMLANDI','HATA','ATLANDI') THEN GETDATE() ELSE NULL END);
    END
END
GO

CREATE OR ALTER PROCEDURE bkm.sp_fifo_StokMaliyetCalistir
(
    @envanterTarihi  DATE = NULL,
    @alisBaslangic   DATE = NULL,
    @alisBitis       DATE = NULL,
    @satisBaslangic  DATE = NULL,
    @satisBitis      DATE = NULL,
    @stkID           INT = NULL,
    @calistirmaId           UNIQUEIDENTIFIER = NULL,
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

    DECLARE @adimKodu VARCHAR(50) = NULL;
    DECLARE @adimAdi VARCHAR(100) = NULL;
    DECLARE @adimSirasi INT = NULL;

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

    IF @calistirAcilis = 1 AND @envanterTarihi IS NULL
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
            EXEC bkm.sp_fifo_StokMaliyetAcilis
                @envanterTarihi = @envanterTarihi,
                @stkID = @stkID,
                @calistirmaId = @calistirmaId,
                @fallbackSatinalmaSarti = @fallbackSatinalmaSarti,
                @sabitFallbackBirimMaliyet = @sabitFallbackBirimMaliyet;
        END

        IF @calistirAlis = 1
        BEGIN
            SET @adimKodu = 'alis';
            SET @adimAdi = 'Alis katman';
            SET @adimSirasi = 1;
            IF @calistirmaId IS NOT NULL
                EXEC bkm.sp_fifo_CalistirmaAdim @calistirmaId, @adimKodu, @adimAdi, @adimSirasi, 'CALISIYOR', NULL;

            EXEC bkm.sp_fifo_StokMaliyetAlisKatman
                @baslangicTarihi = @alisBaslangic,
                @bitisTarihi = @alisBitis,
                @stkID = @stkID,
                @calistirmaId = @calistirmaId;

            IF @calistirmaId IS NOT NULL
                EXEC bkm.sp_fifo_CalistirmaAdim @calistirmaId, @adimKodu, @adimAdi, @adimSirasi, 'TAMAMLANDI', NULL;
        END
        ELSE IF @calistirmaId IS NOT NULL AND @calistirCikis = 1
        BEGIN
            EXEC bkm.sp_fifo_CalistirmaAdim @calistirmaId, 'alis', 'Alis katman', 1, 'ATLANDI', 'CalistirAlis=0';
        END

        IF @calistirCikis = 1
        BEGIN
            SET @adimKodu = 'cikis';
            SET @adimAdi = 'FIFO cikis';
            SET @adimSirasi = 2;
            IF @calistirmaId IS NOT NULL
                EXEC bkm.sp_fifo_CalistirmaAdim @calistirmaId, @adimKodu, @adimAdi, @adimSirasi, 'CALISIYOR', NULL;

            EXEC bkm.sp_fifo_StokMaliyetFIFOCikis
                @satisBaslangic = @satisBaslangic,
                @satisBitis = @satisBitis,
                @stkID = @stkID,
                @calistirmaId = @calistirmaId;

            IF @calistirmaId IS NOT NULL
                EXEC bkm.sp_fifo_CalistirmaAdim @calistirmaId, @adimKodu, @adimAdi, @adimSirasi, 'TAMAMLANDI', NULL;

            SET @adimKodu = 'rapor';
            SET @adimAdi = 'Sonuc hazirligi';
            SET @adimSirasi = 3;
            IF @calistirmaId IS NOT NULL
            BEGIN
                EXEC bkm.sp_fifo_CalistirmaAdim @calistirmaId, @adimKodu, @adimAdi, @adimSirasi, 'CALISIYOR', NULL;
                EXEC bkm.sp_fifo_CalistirmaAdim @calistirmaId, @adimKodu, @adimAdi, @adimSirasi, 'TAMAMLANDI', NULL;
            END
        END
        ELSE IF @calistirmaId IS NOT NULL AND @calistirAlis = 1
        BEGIN
            EXEC bkm.sp_fifo_CalistirmaAdim @calistirmaId, 'cikis', 'FIFO cikis', 2, 'ATLANDI', 'CalistirCikis=0';
            EXEC bkm.sp_fifo_CalistirmaAdim @calistirmaId, 'rapor', 'Sonuc hazirligi', 3, 'ATLANDI', 'CalistirCikis=0';
        END
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @runMessage VARCHAR(500) = SUBSTRING(CONVERT(VARCHAR(500), @ErrorMessage), 1, 500);
        IF @calistirmaId IS NOT NULL AND @adimKodu IS NOT NULL
            EXEC bkm.sp_fifo_CalistirmaAdim
                @calistirmaId = @calistirmaId,
                @adimKodu = @adimKodu,
                @adimAdi = @adimAdi,
                @adimSirasi = @adimSirasi,
                @durum = 'HATA',
                @mesaj = @runMessage;
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        THROW;
    END CATCH
END
GO

PRINT 'sp_fifo_StokMaliyetCalistir proseduru olusturuldu';
GO

-- =============================================================
-- ACILIS CALISTIRMA WRAPPER - bkm.sp_fifo_AcilisCalistir
-- Acilis islemini ayri run/calismayla izlemek icin
-- =============================================================

CREATE OR ALTER PROCEDURE bkm.sp_fifo_AcilisCalistir
(
    @envanterTarihi DATE,
    @stkID INT = NULL,
    @calistirmaId UNIQUEIDENTIFIER = NULL,
    @fallbackSatinalmaSarti VARCHAR(50) = NULL,
    @atlamaAylikDevir BIT = 0,
    @sabitFallbackBirimMaliyet DECIMAL(18,6) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    EXEC bkm.sp_fifo_StokMaliyetAcilis
        @envanterTarihi = @envanterTarihi,
        @stkID = @stkID,
        @calistirmaId = @calistirmaId,
        @fallbackSatinalmaSarti = @fallbackSatinalmaSarti,
        @atlamaAylikDevir = @atlamaAylikDevir,
        @sabitFallbackBirimMaliyet = @sabitFallbackBirimMaliyet;
END
GO

PRINT 'sp_fifo_AcilisCalistir proseduru olusturuldu';
GO

-- =============================================================
-- AYLIK CALISTIRMA WRAPPER - bkm.sp_fifo_AylikCalistir
-- Aylik alis+cikis islemlerini ayri run/calismayla izlemek icin
-- =============================================================

CREATE OR ALTER PROCEDURE bkm.sp_fifo_AylikCalistir
(
    @yil INT,
    @ay INT,
    @stkID INT = NULL,
    @calistirmaId UNIQUEIDENTIFIER = NULL
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

    EXEC bkm.sp_fifo_StokMaliyetCalistir
        @alisBaslangic = @baslangic,
        @alisBitis = @bitis,
        @satisBaslangic = @baslangic,
        @satisBitis = @bitis,
        @stkID = @stkID,
        @calistirmaId = @calistirmaId,
        @calistirAcilis = 0,
        @calistirAlis = 1,
        @calistirCikis = 1;
END
GO

PRINT 'sp_fifo_AylikCalistir proseduru olusturuldu';
GO

-- =============================================================
-- AYLIK RUTIN PROSEDURU - bkm.sp_fifo_AylikRutin
-- Tek seferlik acilis HARIC - sadece alis katmanlari + FIFO cikis
-- Her ay duzenli calistirilir (job/scheduler ile)
-- =============================================================

CREATE OR ALTER PROCEDURE bkm.sp_fifo_AylikRutin
(
    @yil    INT,
    @ay     INT,
    @stkID  INT = NULL,
    @calistirmaId  UNIQUEIDENTIFIER = NULL
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

    EXEC bkm.sp_fifo_StokMaliyetCalistir
        @alisBaslangic   = @alisBaslangic,
        @alisBitis      = @alisBitis,
        @satisBaslangic = @alisBaslangic,
        @satisBitis     = @alisBitis,
        @stkID          = @stkID,
        @calistirmaId          = @calistirmaId,
        @calistirAcilis = 0,   -- Acilis YOK (tek seferlik 01_ACILIS_TEK_SEFERLIK.sql ile yapilir)
        @calistirAlis   = 1,
        @calistirCikis  = 1;
END
GO

PRINT 'sp_fifo_AylikRutin proseduru olusturuldu';
GO
