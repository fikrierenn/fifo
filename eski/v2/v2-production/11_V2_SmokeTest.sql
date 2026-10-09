USE BKMMaliyet;
GO
SET NOCOUNT ON;
GO

-- =============================================================
-- FIFO V2 - Smoke Test & Go-Live Checklist
-- Amac: Deploy sonrasi tum V2 nesnelerini ve temel akilislari dogrula.
-- Calistirma: SSMS / sqlcmd - tek seferlik, READ-ONLY (yazma yapan
--             adimlar BEGIN TRAN / ROLLBACK ile korunur).
-- =============================================================

PRINT '=========================================';
PRINT 'FIFO V2 Smoke Test basliyor...';
PRINT '=========================================';

-- ============================================================
-- 1) NESNE VARLIK KONTROLU
-- ============================================================
PRINT '';
PRINT '[1] DB nesne varlik kontrolleri';
PRINT '-------------------------------------------';

DECLARE @eksik INT = 0;

-- Tablolar
DECLARE @tablolar TABLE (isim SYSNAME);
INSERT INTO @tablolar VALUES
    ('FifoKatman'),('FifoCikisDetay'),('FifoBatchRun'),
    ('FifoBatchDetay'),('FifoBatchHata'),('FifoAcilisEnvanter'),('FifoSorunluStoklar');

SELECT
    tablo = t.isim,
    durum = CASE WHEN OBJECT_ID('dbo.' + t.isim, 'U') IS NOT NULL THEN 'OK' ELSE '*** EKSIK ***' END
FROM @tablolar t;

SELECT @eksik += COUNT(*)
FROM @tablolar t
WHERE OBJECT_ID('dbo.' + t.isim, 'U') IS NULL;

-- Stored Procedures
DECLARE @splar TABLE (isim SYSNAME);
INSERT INTO @splar VALUES
    ('sp_Fifo_HareketliUrunListesi'),
    ('sp_Fifo_AylikCalistir'),
    ('sp_Fifo_AylikCalistirBatch'),
    ('sp_Fifo_BatchRunBaslat'),
    ('sp_Fifo_BatchRunBitir'),
    ('sp_Fifo_AcilisMaliyetlendir'),
    ('sp_Fifo_SentetikKatmanOlustur');

SELECT
    sp    = s.isim,
    durum = CASE WHEN OBJECT_ID('dbo.' + s.isim, 'P') IS NOT NULL THEN 'OK' ELSE '*** EKSIK ***' END
FROM @splar s;

SELECT @eksik += COUNT(*)
FROM @splar s
WHERE OBJECT_ID('dbo.' + s.isim, 'P') IS NULL;

-- Viewlar
SELECT
    view_name = 'vw_FifoBatchRunOzet',
    durum     = CASE WHEN OBJECT_ID('dbo.vw_FifoBatchRunOzet', 'V') IS NOT NULL THEN 'OK' ELSE '*** EKSIK ***' END;

IF OBJECT_ID('dbo.vw_FifoBatchRunOzet', 'V') IS NULL SET @eksik += 1;

-- TVP
SELECT
    tvp_name  = 'StkIdListType',
    durum     = CASE WHEN EXISTS (
                    SELECT 1 FROM sys.types WHERE name='StkIdListType' AND is_table_type=1
                ) THEN 'OK' ELSE '*** EKSIK ***' END;

IF NOT EXISTS (SELECT 1 FROM sys.types WHERE name='StkIdListType' AND is_table_type=1)
    SET @eksik += 1;

IF @eksik > 0
BEGIN
    PRINT '!!! ' + CAST(@eksik AS VARCHAR) + ' eksik nesne var. Deploy tamamlanmamis olabilir.';
    RAISERROR('Nesne varlik kontrolu basarisiz. Eksik nesne sayisi: %d', 16, 1, @eksik);
    RETURN;
END
PRINT '  Tum nesneler mevcut.';
GO

-- ============================================================
-- 2) DEPLOY IDEMPOTENCY KONTROLU
--    Master deploy ikinci kez calisitirildiginda hata vermemeli
-- ============================================================
PRINT '';
PRINT '[2] Idempotency: master deploy 2. kez calistiriliyor...';

:r .\00_V2_Master_Deploy.sql
GO

PRINT '  Idempotency OK.';
GO

-- ============================================================
-- 3) sp_Fifo_HareketliUrunListesi CAGRI TESTI
-- ============================================================
PRINT '';
PRINT '[3] sp_Fifo_HareketliUrunListesi cagri testi';
PRINT '-------------------------------------------';

DECLARE @TestYil INT = 2026, @TestAy INT = 1;

EXEC dbo.sp_Fifo_HareketliUrunListesi
    @Yil = @TestYil,
    @Ay  = @TestAy;

SELECT
    Aciklama = 'HareketliUrunListesi - satir sayisi',
    Deger    = @@ROWCOUNT;
GO

-- ============================================================
-- 4) BATCH RUN ROUNDTRIP (BEGIN TRAN + ROLLBACK)
--    FifoBatchRun / FifoBatchDetay / vw_FifoBatchRunOzet test
-- ============================================================
PRINT '';
PRINT '[4] Batch run roundtrip (BEGIN TRAN / ROLLBACK)';
PRINT '-------------------------------------------';

BEGIN TRANSACTION;

DECLARE @runId UNIQUEIDENTIFIER = NEWID();

EXEC dbo.sp_Fifo_BatchRunBaslat
    @RunId       = @runId,
    @DonemYil    = 2026,
    @DonemAy     = 1,
    @ToplamUrun  = 10,
    @ToplamBatch = 1,
    @BatchBoyutu = 10;

PRINT '  BatchRunBaslat OK. RunId=' + CAST(@runId AS VARCHAR(36));

EXEC dbo.sp_Fifo_BatchRunBitir
    @RunId      = @runId,
    @Durum      = 'TAMAMLANDI',
    @HataMesaji = NULL;

PRINT '  BatchRunBitir OK.';

SELECT
    RunId, DonemYil, DonemAy, Durum, ToplamUrun, SureSaniye
FROM dbo.vw_FifoBatchRunOzet
WHERE RunId = @runId;

ROLLBACK TRANSACTION;
PRINT '  ROLLBACK yapildi (iz kalmadi).';
GO

-- ============================================================
-- 5) TEK URUN FIFO TESTI (BEGIN TRAN + ROLLBACK)
-- ============================================================
PRINT '';
PRINT '[5] Tek urun sp_Fifo_AylikCalistir (BEGIN TRAN / ROLLBACK)';
PRINT '-------------------------------------------';

BEGIN TRANSACTION;

DECLARE @StkId INT = 1672852;

EXEC dbo.sp_Fifo_AylikCalistir
    @yil   = 2026,
    @ay    = 1,
    @StkId = @StkId;

SELECT
    Aciklama = 'FifoCikisDetay - StkId=' + CAST(@StkId AS VARCHAR),
    Deger    = COUNT(*)
FROM dbo.FifoCikisDetay
WHERE StkId = @StkId;

ROLLBACK TRANSACTION;
PRINT '  ROLLBACK yapildi.';
GO

-- ============================================================
-- 6) TABLO BOYUT OZETI
-- ============================================================
PRINT '';
PRINT '[6] V2 tablo boyut ozeti';
PRINT '-------------------------------------------';

SELECT
    t.name                                                  AS Tablo,
    p.rows                                                  AS SatirSayisi,
    CAST(SUM(a.total_pages)*8/1024.0 AS DECIMAL(10,1))     AS ToplamMB,
    CAST(SUM(a.used_pages) *8/1024.0 AS DECIMAL(10,1))     AS KullanilanMB
FROM sys.tables t
JOIN sys.partitions p
    ON p.object_id = t.object_id AND p.index_id IN (0,1)
JOIN sys.allocation_units a
    ON a.container_id = p.partition_id
WHERE t.schema_id = SCHEMA_ID('dbo')
  AND t.name IN (
      'FifoKatman','FifoCikisDetay','FifoBatchRun',
      'FifoBatchDetay','FifoBatchHata',
      'FifoAcilisEnvanter','FifoSorunluStoklar')
GROUP BY t.name, p.rows
ORDER BY ToplamMB DESC;
GO

-- ============================================================
-- 7) SON 5 BATCH RUN OZETI
-- ============================================================
PRINT '';
PRINT '[7] Son 5 batch run';
PRINT '-------------------------------------------';

SELECT TOP 5 * FROM dbo.vw_FifoBatchRunOzet ORDER BY RunBaslangic DESC;
GO

PRINT '';
PRINT '=========================================';
PRINT 'FIFO V2 Smoke Test TAMAMLANDI.';
PRINT '=========================================';
GO
