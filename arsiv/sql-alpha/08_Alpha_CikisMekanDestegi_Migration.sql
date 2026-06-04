-- =============================================================
-- ALPHA MIGRATION: FIFO CIKIS TABLOSUNA LOKASYON (MEKAN) DESTEGI
-- Amac: fifo_StokMaliyetCikis icinde satis lokasyonunu saklamak
-- =============================================================
-- Sonrasi:
--   1) sql-alpha/02_Baseline_CoreProcedures.sql  (SP guncelle)
--   2) sql-alpha/03_Baseline_BasicViews.sql      (view guncelle)
--   3) SQL-Improvements/02_SPRINT2_VIEWS_AUDIT.sql (view/proc guncelle)
-- =============================================================

USE BKMMaliyet;
GO

SET NOCOUNT ON;
GO

IF COL_LENGTH('bkm.fifo_StokMaliyetCikis', 'hareketMekanID') IS NULL
BEGIN
    ALTER TABLE bkm.fifo_StokMaliyetCikis
        ADD hareketMekanID INT NULL;

    PRINT 'x bkm.fifo_StokMaliyetCikis.hareketMekanID eklendi.';
END
ELSE
BEGIN
    PRINT 'i bkm.fifo_StokMaliyetCikis.hareketMekanID zaten mevcut.';
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_fifo_StokMaliyetCikis_MekanTarih'
      AND object_id = OBJECT_ID('bkm.fifo_StokMaliyetCikis')
)
BEGIN
    CREATE INDEX IX_fifo_StokMaliyetCikis_MekanTarih
        ON bkm.fifo_StokMaliyetCikis(hareketMekanID, hareketTarihi)
        INCLUDE (stkID, hareketTipi, miktar, cikisTutar);

    PRINT 'x IX_fifo_StokMaliyetCikis_MekanTarih olusturuldu.';
END
ELSE
BEGIN
    PRINT 'i IX_fifo_StokMaliyetCikis_MekanTarih zaten mevcut.';
END
GO

PRINT 'MIGRATION TAMAMLANDI: Cikis lokasyon (mekan) destegi hazir.';
PRINT 'Siradaki adim: SP ve view scriptlerini tekrar calistirin.';
GO

