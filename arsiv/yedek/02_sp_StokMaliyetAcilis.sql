-- =============================================================
-- AÇILIŞ PROSEDÜRÜ - bkm.sp_fifo_StokMaliyetAcilis
-- Transaction yönetimi ve hata kontrolü ile
-- =============================================================

CREATE OR ALTER PROCEDURE bkm.sp_fifo_StokMaliyetAcilis
(
    @envanterTarihi DATE,
    @stkID INT = NULL,
    @runId UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @stepKey VARCHAR(50) = NULL;
    DECLARE @stepName VARCHAR(100) = NULL;
    DECLARE @stepOrder INT = NULL;
    
    -- Parametre validasyonu
    IF @envanterTarihi IS NULL
    BEGIN
        RAISERROR('Envanter tarihi boş olamaz', 16, 1);
        RETURN;
    END
    
    IF @envanterTarihi > GETDATE()
    BEGIN
        RAISERROR('Envanter tarihi gelecek tarih olamaz', 16, 1);
        RETURN;
    END
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        DECLARE @baslangicTarihi DATE = DATEFROMPARTS(2021, 5, 31);

        SET @stepKey = 'envanter';
        SET @stepName = 'Envanter snapshot';
        SET @stepOrder = 1;
        IF @runId IS NOT NULL
            EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'RUNNING', NULL;

        /* 1) Envanter tarihindeki stok miktarlarını çek */
        IF OBJECT_ID('tempdb..#stoklarMekan', 'U') IS NOT NULL DROP TABLE #stoklarMekan;

        SELECT 
            d.ehMekan AS mekanID,
            d.ehstkID AS stkID,
            SUM(CONVERT(DECIMAL(18,4), d.stok)) AS stokMiktar
        INTO #stoklarMekan
        FROM dbo.stokSonAltDepo_vw d
        WHERE d.ehAltDepo = 0 
          AND d.ehMekan IN (1,4477,4478)
          AND d.stok > 0
          AND (@stkID IS NULL OR d.ehstkID = @stkID)
        GROUP BY d.ehMekan, d.ehstkID;

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

        IF @runId IS NOT NULL
            EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'DONE', NULL;

        SET @stepKey = 'alis';
        SET @stepName = 'Alislar toplanir';
        SET @stepOrder = 2;
        IF @runId IS NOT NULL
            EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'RUNNING', NULL;

        /* 2) Başlangıç–envanter arası alışları çek */
        IF OBJECT_ID('tempdb..#alislar', 'U') IS NOT NULL DROP TABLE #alislar;
        CREATE TABLE #alislar (
            stkID        INT           NOT NULL,
            girisTarihi  DATETIME      NOT NULL,
            belgeNo      VARCHAR(50)   NULL,
            belgeTarihi  DATE          NULL,
            firmaID      INT           NULL,
            miktar       DECIMAL(18,4) NOT NULL,
            netTutar     DECIMAL(18,4) NOT NULL
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
        INSERT INTO #alislar (stkID, girisTarihi, belgeNo, belgeTarihi, firmaID, miktar, netTutar)
        SELECT 
            a.ehStkID AS stkID,
            i.eTarih  AS girisTarihi,
            f.eNo     AS belgeNo,
            ' + @belgeTarihExpr + N' AS belgeTarihi,
            ' + @firmaExpr + N' AS firmaID,
            SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS miktar,
            SUM(
                CONVERT(DECIMAL(18,4),
                    CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END
                )
            ) AS netTutar
        FROM #stoklar s
        JOIN dbo.irs i WITH(NOLOCK)
            ON i.eTip IN (2,0,10,3,6,102,103)
           AND i.eTarih >  CONVERT(smalldatetime, @baslangicTarihi)
           AND i.eTarih <  DATEADD(DAY, 1, CONVERT(smalldatetime, @envanterTarihi))
           AND i.eMekan IN (1,4477,4478)
        JOIN dbo.irsAyr ia WITH(NOLOCK)
            ON ia.ehID = i.eID
        JOIN dbo.fatAyr a WITH(NOLOCK)
            ON a.ehIrsID   = i.eID 
           AND a.ehIrsSira = ia.ehSira 
           AND a.ehStkID   = s.stkID
        JOIN dbo.fat f WITH(NOLOCK)
            ON f.eID = a.ehID
        WHERE a.ehAdetN <> 0
          AND (@stkID IS NULL OR a.ehStkID = @stkID)
        GROUP BY a.ehstkID, i.eTarih, i.eID, f.eNo' + @groupByExtra + N'
        HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;';

        EXEC sp_executesql
            @sql,
            N'@baslangicTarihi DATE, @envanterTarihi DATE, @stkID INT',
            @baslangicTarihi = @baslangicTarihi,
            @envanterTarihi = @envanterTarihi,
            @stkID = @stkID;

        ALTER TABLE #alislar ADD birimMaliyet DECIMAL(18,6);

        UPDATE #alislar
        SET birimMaliyet = CASE WHEN miktar = 0 THEN 0 ELSE netTutar / miktar END;

        CREATE INDEX IX_tmp_alislar_stkTarih 
            ON #alislar(stkID, girisTarihi DESC, belgeNo);

        IF @runId IS NOT NULL
            EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'DONE', NULL;

        SET @stepKey = 'katman';
        SET @stepName = 'Ters FIFO katman';
        SET @stepOrder = 3;
        IF @runId IS NOT NULL
            EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'RUNNING', NULL;

        /* 3) Ters FIFO ile açılış katmanlarını hesapla */
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

        /* 4) Gerçek açılış katmanlarını ACILIS olarak havuza yaz */
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

        IF @runId IS NOT NULL
            EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'DONE', NULL;

        SET @stepKey = 'sorun';
        SET @stepName = 'Sorun kaydi';
        SET @stepOrder = 4;
        IF @runId IS NOT NULL
            EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'RUNNING', NULL;

        /* 5) Eksik miktarları tespit et */
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

        /* 6) Alışı olan ama yetmeyenleri son alışla tamamla */
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


        /* 7) Sorunlu kayıtları oluştur */
        
        /* 6b) Merkez depo (12) alislari ile tamamlama (alis yoksa) */
        IF OBJECT_ID('tempdb..#merkezAlis', 'U') IS NOT NULL DROP TABLE #merkezAlis;
        CREATE TABLE #merkezAlis (
            stkID        INT           NOT NULL,
            girisTarihi  DATETIME      NOT NULL,
            belgeNo      VARCHAR(50)   NULL,
            belgeTarihi  DATE          NULL,
            firmaID      INT           NULL,
            miktar       DECIMAL(18,4) NOT NULL,
            netTutar     DECIMAL(18,4) NOT NULL
        );

        DECLARE @sqlMerkez NVARCHAR(MAX) = N'
        INSERT INTO #merkezAlis (stkID, girisTarihi, belgeNo, belgeTarihi, firmaID, miktar, netTutar)
        SELECT
            a.ehStkID AS stkID,
            i.eTarih  AS girisTarihi,
            f.eNo     AS belgeNo,
            ' + @belgeTarihExpr + N' AS belgeTarihi,
            ' + @firmaExpr + N' AS firmaID,
            SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS miktar,
            SUM(
                CONVERT(DECIMAL(18,4),
                    CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END
                )
            ) AS netTutar
        FROM #eksiklar e
        LEFT JOIN (SELECT DISTINCT stkID FROM #alislar) v ON v.stkID = e.stkID
        JOIN dbo.irs i WITH(NOLOCK)
            ON i.eTip IN (2,0,10,3,6,102,103)
           AND i.eTarih >  CONVERT(smalldatetime, @baslangicTarihi)
           AND i.eTarih <  DATEADD(DAY, 1, CONVERT(smalldatetime, @envanterTarihi))
           AND i.eMekan = 12
        JOIN dbo.irsAyr ia WITH(NOLOCK)
            ON ia.ehID = i.eID
        JOIN dbo.fatAyr a WITH(NOLOCK)
            ON a.ehIrsID   = i.eID
           AND a.ehIrsSira = ia.ehSira
           AND a.ehStkID   = e.stkID
        JOIN dbo.fat f WITH(NOLOCK)
            ON f.eID = a.ehID
        WHERE a.ehAdetN <> 0
          AND v.stkID IS NULL
          AND e.eksikMiktar > 0
          AND (@stkID IS NULL OR a.ehStkID = @stkID)
        GROUP BY a.ehStkID, i.eTarih, i.eID, f.eNo' + @groupByExtra + N'
        HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;';

        EXEC sp_executesql
            @sqlMerkez,
            N'@baslangicTarihi DATE, @envanterTarihi DATE, @stkID INT',
            @baslangicTarihi = @baslangicTarihi,
            @envanterTarihi = @envanterTarihi,
            @stkID = @stkID;

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
            FROM bkm.fn_SonGecerliFiyat(@envanterTarihi, 1) f
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

        /* 6d) Aylik devir ile tamamlama (alis/merkez/sart yoksa) */
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

        IF EXISTS (SELECT 1 FROM #eksikKalan)
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

            INSERT INTO #aylikStok (stkID, ayBitis, ayStok)
            SELECT
                e.stkID,
                a.ayBitis,
                ISNULL(s.ayStok, 0) AS ayStok
            FROM #eksikKalan e
            CROSS JOIN #aylar a
            OUTER APPLY (
                SELECT SUM(f.stok) AS ayStok
                FROM (
                    SELECT g.stkID, g.stok
                    FROM bkm.fn_gecmis_stok_mekan(DATEADD(DAY, 1, a.ayBitis), 1) g
                    UNION ALL
                    SELECT g.stkID, g.stok
                    FROM bkm.fn_gecmis_stok_mekan(DATEADD(DAY, 1, a.ayBitis), 4477) g
                    UNION ALL
                    SELECT g.stkID, g.stok
                    FROM bkm.fn_gecmis_stok_mekan(DATEADD(DAY, 1, a.ayBitis), 4478) g
                ) f
                WHERE f.stkID = e.stkID
            ) s
            WHERE ISNULL(s.ayStok, 0) > 0;

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

            IF OBJECT_ID('bkm.fifo_SabitFiyat', 'U') IS NOT NULL
            BEGIN
                DECLARE @sqlSabit NVARCHAR(MAX) = N'
                INSERT INTO #sabitFiyat (stkID, birimMaliyet)
                SELECT sf.stkID, sf.birimMaliyet
                FROM bkm.fifo_SabitFiyat sf
                WHERE (@stkID IS NULL OR sf.stkID = @stkID);';

                EXEC sp_executesql
                    @sqlSabit,
                    N'@stkID INT',
                    @stkID = @stkID;
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
                FROM bkm.fn_SonGecerliFiyat_Adv(a.ayBitis, 1, 1, 1) f
                WHERE f.fStkID = a.stkID
                  AND f.sonrakiNet > 0
                  AND (f.fTarihSon IS NULL OR f.fTarihSon >= a.ayBitis)
                ORDER BY
                    CASE WHEN f.fFrmID = 9525 THEN 0 ELSE 1 END,
                    f.fTarihSon DESC,
                    f.fhID DESC
            ) fiyat
            LEFT JOIN #sabitFiyat sf ON sf.stkID = a.stkID;

            INSERT INTO bkm.fifo_StokMaliyetHavuzu
                (stkID, girisTarihi, kaynakTip, belgeNo, belgeTarihi, firmaID,
                 miktarToplam, miktarKalan, birimMaliyet, durum)
            SELECT
                k.stkID, k.ayBitis, 'AYLIK_DEVIR', NULL, k.ayBitis, NULL,
                k.ayMiktar, k.ayMiktar, ISNULL(k.birimMaliyet, 0), k.durum
            FROM #aylikKatman k;
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
            s.stkID, @envanterTarihi, s.stokMiktar, 'ALIS_YOK',
            'Bu ürüne belirtilen tarih aralığında hiç alış bulunamadı.'
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
            'Eksik stok son alış fiyatı ile otomatik tamamlandı.'
        FROM #eksiklar e
        WHERE e.eksikMiktar > 0 AND e.toplamAcilisMiktar > 0;

        IF @runId IS NOT NULL
            EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'DONE', NULL;

        COMMIT TRANSACTION;
        
        PRINT 'Açılış stoku başarıyla oluşturuldu. Tarih: ' + 
              CONVERT(VARCHAR(10), @envanterTarihi, 120);
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @runMessage VARCHAR(500) = SUBSTRING(CONVERT(VARCHAR(500), @ErrorMessage), 1, 500);

        IF @runId IS NOT NULL AND @stepKey IS NOT NULL
            EXEC bkm.sp_fifo_RunStep
                @runId = @runId,
                @stepKey = @stepKey,
                @stepName = @stepName,
                @stepOrder = @stepOrder,
                @status = 'ERROR',
                @message = @runMessage;
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        DECLARE @ErrorLine INT = ERROR_LINE();
        
        INSERT INTO bkm.fifo_StokMaliyetSorunlu
            (stkID, envanterTarihi, stokMiktar, sorunTip, aciklama)
        VALUES (0, @envanterTarihi, 0, 'PROSEDUR_HATASI', 
                'sp_fifo_StokMaliyetAcilis - Satır: ' + CAST(@ErrorLine AS VARCHAR(10)) + 
                ' - ' + @ErrorMessage);
        
        THROW;
    END CATCH
END
GO

PRINT 'sp_fifo_StokMaliyetAcilis prosedürü oluşturuldu';
GO


