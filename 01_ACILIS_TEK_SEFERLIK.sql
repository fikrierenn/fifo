-- =============================================================
-- BKM FIFO - TEK SEFERLIK ACILIS KATMANI
-- =============================================================
-- Bu script SADECE BIR KEZ calistirilir.
-- Sistem kurulumunda veya yeni envanter tarihinde acilis katmani
-- olusturmak icin kullanilir.
--
-- Calistirma takibi: fifo_Calistirma + fifo_CalistirmaAdim tablolarina
-- ilerleme yazilir.
-- Ilerlemeyi gormek icin:
--   SELECT * FROM bkm.fifo_CalistirmaAdim ORDER BY adimSirasi;
--
-- ONEMLI: Acilis tamamlandiktan sonra aylik rutin icin
--         02_AYLIK_RUTIN.sql kullanin.
-- =============================================================

SET NOCOUNT ON;
GO

PRINT '========================================';
PRINT 'BKM FIFO - TEK SEFERLIK ACILIS';
PRINT '========================================';
PRINT '';

-- =============================================================
-- PARAMETRELER - Asagidaki degerleri kendi ortaminiza gore duzenleyin
-- =============================================================

DECLARE @envanterTarihi DATE = '2025-12-31';  -- Acilis envanter tarihi (orn: donem sonu)
DECLARE @satinalmaSarti VARCHAR(50) = NULL;   -- ERP devir: CIF, FOB vb. NULL = tum sartlar
DECLARE @stkID INT = NULL;                    -- NULL = tum urunler. Test icin: belirli stkID
DECLARE @atlamaAylikDevir BIT = 0;            -- 1 = Agir aylik devir adimini atla (timeout varsa)
DECLARE @temizleLoglar BIT = 1;               -- 1 = Islem oncesi BKMMaliyet log tablolarini temizle
DECLARE @temizleTxLog BIT = 1;                -- 1 = Transaction log (LDF) sismesini onle
                                              -- BKMMaliyet SIMPLE recovery: CHECKPOINT + SHRINK yeterli

-- =============================================================
-- ISLEM ONCESI TEMIZLIK (BKMMaliyet DB + transaction log sismesini onler)
-- =============================================================

IF @temizleLoglar = 1
BEGIN
    PRINT 'Islem oncesi tablo temizligi...';
    
    IF OBJECT_ID('bkm.fifo_DegisimGunlugu', 'U') IS NOT NULL
    BEGIN
        TRUNCATE TABLE bkm.fifo_DegisimGunlugu;
        PRINT '   - fifo_DegisimGunlugu temizlendi.';
    END
    ELSE IF OBJECT_ID('bkm.fifo_AuditLog', 'U') IS NOT NULL
    BEGIN
        TRUNCATE TABLE bkm.fifo_AuditLog;
        PRINT '   - fifo_AuditLog temizlendi.';
    END
    
    DELETE FROM bkm.fifo_CalistirmaAdim WHERE calistirmaId IN (SELECT calistirmaId FROM bkm.fifo_Calistirma WHERE talepTarihi < DATEADD(DAY, -7, GETDATE()));
    DELETE FROM bkm.fifo_Calistirma WHERE talepTarihi < DATEADD(DAY, -7, GETDATE());
    PRINT '   - 7 gunden eski fifo_Calistirma/fifo_CalistirmaAdim silindi.';
    
    PRINT 'Tablo temizligi tamamlandi.';
    PRINT '';
END

IF @temizleTxLog = 1
BEGIN
    PRINT 'Transaction log (LDF) temizligi (SIMPLE recovery)...';
    
    CHECKPOINT;
    PRINT '   - CHECKPOINT calistirildi.';
    
    BEGIN TRY
        DECLARE @logName SYSNAME = (SELECT name FROM sys.database_files WHERE type_desc = 'LOG');
        DECLARE @shrinkSql NVARCHAR(200) = N'DBCC SHRINKFILE (N''' + @logName + N''', 1)';
        EXEC sp_executesql @shrinkSql;
        PRINT '   - Log dosyasi kucultuldu (SHRINKFILE).';
    END TRY
    BEGIN CATCH
        PRINT '   - SHRINKFILE atlandi: ' + ERROR_MESSAGE();
    END CATCH
    
    PRINT 'Transaction log temizligi tamamlandi.';
    PRINT '';
END

-- =============================================================
-- CALISTIRMA KAYDI OLUSTUR (takip icin - fifo_CalistirmaAdim tablosu beslenir)
-- =============================================================

DECLARE @calistirmaId UNIQUEIDENTIFIER = NEWID();

INSERT INTO bkm.fifo_Calistirma (calistirmaId, calistirmaTipi, durum, talepTarihi, baslamaTarihi, message)
VALUES (@calistirmaId, 'ACILIS', 'RUNNING', GETDATE(), GETDATE(), 
        'Acilis: ' + CONVERT(VARCHAR(10), @envanterTarihi, 120));

PRINT 'CalistirmaId: ' + CAST(@calistirmaId AS VARCHAR(36)) + ' - Ilerleme: bkm.fifo_CalistirmaAdim';
PRINT '';

-- =============================================================
-- ACILISI CALISTIR
-- =============================================================

BEGIN TRY
    EXEC bkm.sp_fifo_StokMaliyetAcilis
        @envanterTarihi    = @envanterTarihi,
        @satinalmaSarti    = @satinalmaSarti,
        @stkID             = @stkID,
        @calistirmaId      = @calistirmaId,
        @atlamaAylikDevir  = @atlamaAylikDevir;

    -- Calistirma durumunu guncelle
    UPDATE bkm.fifo_Calistirma SET durum = 'DONE', bitisTarihi = GETDATE() WHERE calistirmaId = @calistirmaId;

    PRINT '';
    PRINT 'Acilis katmani olusturuldu.';
    PRINT 'Ilerleme: SELECT * FROM bkm.fifo_CalistirmaAdim WHERE calistirmaId = ''' + CAST(@calistirmaId AS VARCHAR(36)) + ''' ORDER BY adimSirasi;';
    PRINT 'Sonraki adim: 02_AYLIK_RUTIN.sql ile aylik islemleri calistirin.';
END TRY
BEGIN CATCH
    UPDATE bkm.fifo_Calistirma SET durum = 'ERROR', bitisTarihi = GETDATE(), message = ERROR_MESSAGE() WHERE calistirmaId = @calistirmaId;
    PRINT 'HATA: ' + ERROR_MESSAGE();
    THROW;
END CATCH;
PRINT '========================================';
GO
