-- =============================================================
-- ALPHA E2E SMOKE TEMPLATE
-- Amac: Acilis + aylik rutin (sentetik fallback dahil) akisini tek script ile denemek
-- On kosul:
--   1) sql-alpha/01..05 scriptleri calistirilmis olmali
--   2) SQL-Improvements/01 ve 02 uygulanmis olmali (onerilir)
-- =============================================================

USE BKMMaliyet;
GO

IF DB_NAME() <> 'BKMMaliyet'
BEGIN
    RAISERROR('Yanlis veritabanindasiniz. BKMMaliyet uzerinde calistirin.', 16, 1);
    RETURN;
END
GO

SET NOCOUNT ON;
GO

DECLARE @envanterTarihi DATE = '2025-12-31';
DECLARE @yil INT = 2026;
DECLARE @ay INT = 1;
DECLARE @stkID INT = NULL; -- smoke icin tek urun vermek isterseniz doldurun
DECLARE @fallbackSatinalmaSarti VARCHAR(50) = 'YIL_SONU_2025_TEST'; -- acilis fallback fiyat secimi
DECLARE @sentetikSatinalmaSarti VARCHAR(50) = 'YIL_SONU_2025_TEST'; -- sentetik katman fiyat secimi
DECLARE @sabitFallbackBirimMaliyet DECIMAL(18,6) = 10.000000;
DECLARE @atlamaAylikDevir BIT = 1; -- ilk smoke icin 1 onerilir (agir fallback adimini atlar)
DECLARE @acilisCalistirmaId UNIQUEIDENTIFIER = NEWID();
DECLARE @aylikCalistirmaId UNIQUEIDENTIFIER = NEWID();

PRINT 'AcilisCalistirmaId: ' + CAST(@acilisCalistirmaId AS VARCHAR(36));
PRINT '1) ACILIS calisiyor...';

EXEC bkm.sp_fifo_AcilisCalistir
    @envanterTarihi = @envanterTarihi,
    @stkID = @stkID,
    @calistirmaId = @acilisCalistirmaId,
    @fallbackSatinalmaSarti = @fallbackSatinalmaSarti,
    @atlamaAylikDevir = @atlamaAylikDevir,
    @sabitFallbackBirimMaliyet = @sabitFallbackBirimMaliyet;

PRINT 'AylikCalistirmaId: ' + CAST(@aylikCalistirmaId AS VARCHAR(36));
PRINT '2) AYLIK ALPHA RUTIN (sentetik fallback aktif) calisiyor...';

EXEC bkm.sp_fifo_AylikRutinAlpha
    @yil = @yil,
    @ay = @ay,
    @stkID = @stkID,
    @calistirmaId = @aylikCalistirmaId,
    @sentetikSatinalmaSarti = @sentetikSatinalmaSarti,
    @sabitFallbackBirimMaliyet = @sabitFallbackBirimMaliyet,
    @sentetikAktif = 1;

PRINT '3) KONTROL OZETI - ACILIS';

SELECT TOP 20 *
FROM bkm.fifo_CalistirmaAdim
WHERE calistirmaId = @acilisCalistirmaId
ORDER BY adimSirasi, guncellemeTarihi;

PRINT '4) KONTROL OZETI - AYLIK';

SELECT TOP 20 *
FROM bkm.fifo_CalistirmaAdim
WHERE calistirmaId = @aylikCalistirmaId
ORDER BY adimSirasi, guncellemeTarihi;

SELECT TOP 20 *
FROM bkm.fifo_StokMaliyetSorunlu
WHERE envanterTarihi IN (@envanterTarihi, EOMONTH(DATEFROMPARTS(@yil, @ay, 1)))
  AND (@stkID IS NULL OR stkID = @stkID)
ORDER BY kayitTarihi DESC;

SELECT TOP 50 *
FROM bkm.fifo_StokMaliyetCikis
WHERE hareketTarihi >= DATEFROMPARTS(@yil, @ay, 1)
  AND hareketTarihi <= EOMONTH(DATEFROMPARTS(@yil, @ay, 1))
  AND (@stkID IS NULL OR stkID = @stkID)
ORDER BY hareketTarihi, stkID, katmanTarihi, katmanID;
GO
