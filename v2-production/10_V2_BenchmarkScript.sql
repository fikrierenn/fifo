USE BKMMaliyet;
GO
SET NOCOUNT ON;
GO

-- =============================================================
-- V2-12: Tum Urun Batch Benchmark
-- Sure / IO / CPU karsilastirma scripti.
-- Deploy sonrasi, gercek veri uzerinde calistirilir.
--
-- PARAMETRELER: asagidaki DECLARE blogunu ortama gore ayarla.
-- CALISTIRMA: Her blogu ayri ayri ya da birlesik calistir.
-- =============================================================

DECLARE @TestYil  INT  = 2026;
DECLARE @TestAy   INT  = 1;
DECLARE @StkIdOrnek INT = 1672852;  -- Tek urun testi icin ornek StkId

-- ============================================================
-- 1) URUN SAYISI VE HAREKET DAGILIMI
-- ============================================================
PRINT '========================================';
PRINT '1) Hareketli urun sayisi ve dagilimi';
PRINT '========================================';

-- HareketliUrunListesi SP test
DECLARE @t1 DATETIME2 = SYSDATETIME();

EXEC dbo.sp_Fifo_HareketliUrunListesi @Yil = @TestYil, @Ay = @TestAy;

SELECT
    DATEDIFF(MILLISECOND, @t1, SYSDATETIME()) AS HareketliUrunListesiMs,
    SYSDATETIME() AS OlcumZamani;
GO

-- ============================================================
-- 2) TEK URUN - sp_Fifo_AylikCalistir
-- ============================================================
DECLARE @TestYil  INT  = 2026;
DECLARE @TestAy   INT  = 1;
DECLARE @StkIdOrnek INT = 1672852;

PRINT '';
PRINT '========================================';
PRINT '2) Tek urun: sp_Fifo_AylikCalistir';
PRINT '========================================';

DECLARE @t2 DATETIME2 = SYSDATETIME();

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

EXEC dbo.sp_Fifo_AylikCalistir
    @yil   = @TestYil,
    @ay    = @TestAy,
    @StkId = @StkIdOrnek;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

SELECT
    @StkIdOrnek AS StkId,
    DATEDIFF(MILLISECOND, @t2, SYSDATETIME()) AS TekUrunMs;
GO

-- ============================================================
-- 3) BATCH BOYUTU KARSILASTIRMASI
--    250 / 500 / 1000 urunluk batch surelerini karsilastir
-- ============================================================
DECLARE @TestYil INT = 2026;
DECLARE @TestAy  INT = 1;

PRINT '';
PRINT '========================================';
PRINT '3) Batch boyutu karsilastirmasi (ilk N urun)';
PRINT '========================================';

IF OBJECT_ID('tempdb..#benchmarkSonuc', 'U') IS NOT NULL DROP TABLE #benchmarkSonuc;
CREATE TABLE #benchmarkSonuc (
    BatchBoyutu  INT NOT NULL,
    UrunSayisi   INT NOT NULL,
    SureMs       INT NOT NULL,
    UrunBasiMs   DECIMAL(10,2) NOT NULL,
    OlcumZamani  DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);

-- Hareketli urun listesini al
IF OBJECT_ID('tempdb..#benchUrunler', 'U') IS NOT NULL DROP TABLE #benchUrunler;
SELECT StkId, ROW_NUMBER() OVER (ORDER BY StkId) AS Sira
INTO #benchUrunler
FROM (
    SELECT DISTINCT dt.ehStkId AS StkId
    FROM DerinSISBkm.dbo.irsAyr dt WITH(NOLOCK)
    JOIN DerinSISBkm.dbo.irs bs  WITH(NOLOCK) ON dt.ehID = bs.eID
    WHERE bs.eTip   IN (1, 4, 5, 100, 101)
      AND bs.eMekan IN (1, 12, 4477, 4478)
      AND bs.eTarihS >= DATEFROMPARTS(@TestYil, @TestAy, 1)
      AND bs.eTarihS <  DATEADD(DAY, 1, EOMONTH(DATEFROMPARTS(@TestYil, @TestAy, 1)))
) u;

DECLARE @ToplamUrun INT = (SELECT COUNT(*) FROM #benchUrunler);
PRINT '  Toplam hareketli urun: ' + CAST(@ToplamUrun AS VARCHAR);

-- Her batch boyutu icin ilk N urunu test et
DECLARE @boyut   INT;
DECLARE @bas     DATETIME2;
DECLARE @stkId   INT;
DECLARE @sayac   INT;

DECLARE boyutCur CURSOR LOCAL FAST_FORWARD FOR
    SELECT v FROM (VALUES (50), (250), (500)) t(v)
    WHERE v <= @ToplamUrun;

OPEN boyutCur;
FETCH NEXT FROM boyutCur INTO @boyut;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @bas   = SYSDATETIME();
    SET @sayac = 0;

    DECLARE urunCur CURSOR LOCAL FAST_FORWARD FOR
        SELECT StkId FROM #benchUrunler WHERE Sira <= @boyut ORDER BY Sira;

    OPEN urunCur;
    FETCH NEXT FROM urunCur INTO @stkId;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC dbo.sp_Fifo_AylikCalistir
            @yil   = @TestYil,
            @ay    = @TestAy,
            @StkId = @stkId;
        SET @sayac += 1;
        FETCH NEXT FROM urunCur INTO @stkId;
    END
    CLOSE urunCur; DEALLOCATE urunCur;

    DECLARE @sureMs INT = DATEDIFF(MILLISECOND, @bas, SYSDATETIME());

    INSERT INTO #benchmarkSonuc (BatchBoyutu, UrunSayisi, SureMs, UrunBasiMs)
    VALUES (@boyut, @sayac, @sureMs, CAST(@sureMs AS DECIMAL(10,2)) / NULLIF(@sayac, 0));

    PRINT '  BatchBoyutu=' + CAST(@boyut AS VARCHAR)
        + '  Sure=' + CAST(@sureMs AS VARCHAR) + 'ms'
        + '  UrunBasi=' + CAST(CAST(@sureMs AS DECIMAL(10,2)) / NULLIF(@sayac, 0) AS VARCHAR(10)) + 'ms';

    FETCH NEXT FROM boyutCur INTO @boyut;
END
CLOSE boyutCur; DEALLOCATE boyutCur;

SELECT * FROM #benchmarkSonuc ORDER BY BatchBoyutu;
GO

-- ============================================================
-- 4) FIFO KATMAN VE CIKIS DETAY BUYUKLUGU (deploy sonrasi)
-- ============================================================
PRINT '';
PRINT '========================================';
PRINT '4) Tablo buyukluk ozeti';
PRINT '========================================';

SELECT
    t.name                                          AS Tablo,
    p.rows                                          AS SatirSayisi,
    CAST(SUM(a.total_pages) * 8 / 1024.0 AS DECIMAL(10,1)) AS ToplamMB,
    CAST(SUM(a.used_pages)  * 8 / 1024.0 AS DECIMAL(10,1)) AS KullanilanMB
FROM sys.tables t
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
JOIN sys.allocation_units a ON a.container_id = p.partition_id
WHERE t.schema_id = SCHEMA_ID('dbo')
  AND t.name IN ('FifoKatman','FifoCikisDetay','FifoBatchRun','FifoBatchDetay',
                 'FifoBatchHata','FifoAcilisEnvanter','FifoSorunluStoklar')
GROUP BY t.name, p.rows
ORDER BY ToplamMB DESC;
GO

-- ============================================================
-- 5) SON RUN OZETI (FifoBatchRun)
-- ============================================================
PRINT '';
PRINT '========================================';
PRINT '5) Son 10 batch run ozeti';
PRINT '========================================';

SELECT TOP 10 * FROM dbo.vw_FifoBatchRunOzet
ORDER BY RunBaslangic DESC;
GO
