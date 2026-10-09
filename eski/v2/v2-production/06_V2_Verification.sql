-- =============================================================
-- FIFO V2 - VERIFICATION SCRIPT
-- File: v2-production/06_V2_Verification.sql
-- NOTE: Requires SQLCMD mode in SSMS because of :r includes.
-- =============================================================

USE BKMMaliyet;
GO
SET NOCOUNT ON;
GO

PRINT '========================================';
PRINT 'FIFO V2 verification basliyor...';
PRINT '========================================';
GO

-- 1) Fresh deploy
:r .\00_V2_Master_Deploy.sql
GO

-- 2) Idempotency deploy (second run)
:r .\00_V2_Master_Deploy.sql
GO

DECLARE @StkId INT = 1672852;
DECLARE @EnvanterTarihi DATE = '2025-12-31';
DECLARE @Yil INT = 2026;
DECLARE @Ay INT = 1;
DECLARE @SorunTarihi DATE = '2026-01-31';

-- 3) Acilis test
DECLARE @IslemId1 UNIQUEIDENTIFIER = NEWID();
PRINT 'Acilis test run: ' + CAST(@IslemId1 AS VARCHAR(36));

EXEC dbo.sp_Fifo_AcilisCalistir
    @EnvanterTarihi = @EnvanterTarihi,
    @StkId = @StkId,
    @IslemId = @IslemId1;

SELECT TOP 20 *
FROM dbo.FifoKatman
WHERE StkId = @StkId
ORDER BY KatmanId;

SELECT TOP 20 *
FROM dbo.FifoAcilisEnvanter
WHERE StkId = @StkId
ORDER BY EnvanterTarihi, MekanId;

-- 4) Aylik test
DECLARE @IslemId2 UNIQUEIDENTIFIER = NEWID();
PRINT 'Aylik test run: ' + CAST(@IslemId2 AS VARCHAR(36));

EXEC dbo.sp_Fifo_AylikCalistir
    @yil = @Yil,
    @ay = @Ay,
    @StkId = @StkId,
    @IslemId = @IslemId2;

SELECT TOP 50 *
FROM dbo.FifoCikisDetay
WHERE StkId = @StkId
ORDER BY HareketTarihi, KatmanId;

-- 5) View kontrolu
SELECT *
FROM dbo.vw_Fifo_AySonuBirimMaliyet
WHERE StkId = @StkId;

-- 6) Sentetik dry-run
EXEC dbo.sp_Fifo_SentetikKatmanOlustur
    @SorunTarihi = @SorunTarihi,
    @StkId = @StkId,
    @DryRun = 1;

-- 7) Go-live checklist ozet
PRINT '--- Go-live checklist ozet ---';

SELECT
    Aciklama = 'FifoKatman satir sayisi',
    Deger = COUNT_BIG(*)
FROM dbo.FifoKatman;

SELECT
    Aciklama = 'FifoAcilisEnvanter satir sayisi',
    Deger = COUNT_BIG(*)
FROM dbo.FifoAcilisEnvanter;

SELECT
    Aciklama = 'FifoCikisDetay satir sayisi',
    Deger = COUNT_BIG(*)
FROM dbo.FifoCikisDetay;

SELECT
    Aciklama = 'FifoCikisDetay pozitif tutar satiri',
    Deger = COUNT_BIG(*)
FROM dbo.FifoCikisDetay
WHERE CikisTutar > 0;

SELECT TOP 20 *
FROM dbo.MaliyetIslem
ORDER BY Baslangic DESC;

SELECT TOP 50 *
FROM dbo.MaliyetIslemAdim
ORDER BY Guncelleme DESC;

PRINT '========================================';
PRINT 'FIFO V2 verification tamamlandi.';
PRINT '========================================';
GO
