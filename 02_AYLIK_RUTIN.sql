-- =============================================================
-- BKM FIFO - AYLIK RUTIN
-- =============================================================
-- Bu script her ay düzenli olarak çalıştırılır.
-- Alış katmanları + FIFO çıkış hesaplaması yapar.
--
-- ÖN KOŞUL: 01_ACILIS_TEK_SEFERLIK.sql daha önce çalıştırılmış olmalı.
-- =============================================================

SET NOCOUNT ON;
GO

PRINT '========================================';
PRINT 'BKM FIFO - AYLIK RUTIN';
PRINT '========================================';
PRINT '';

-- =============================================================
-- PARAMETRELER - İşlenecek ayı belirleyin
-- =============================================================

DECLARE @yil INT = 2026;
DECLARE @ay INT = 1;

DECLARE @alisBaslangic DATE = DATEFROMPARTS(@yil, @ay, 1);
DECLARE @stkID INT = NULL;  -- NULL = tüm ürünler

-- =============================================================
-- AYLIK RUTIN ÇALIŞTIR (Açılış YOK - sadece alış + çıkış)
-- =============================================================

EXEC bkm.sp_fifo_AylikRutin
    @yil   = @yil,
    @ay    = @ay,
    @stkID = @stkID;

PRINT '';
PRINT 'Aylık rutin tamamlandı: ' + FORMAT(@alisBaslangic, 'yyyy-MM') + ' ayı işlendi.';
PRINT '========================================';
GO
