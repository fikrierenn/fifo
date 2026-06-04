-- =============================================================
-- 02_sp_RunStep.sql
-- Run adimlarini yoneten helper SP
-- =============================================================

IF OBJECT_ID('bkm.sp_fifo_CalistirmaAdim', 'P') IS NOT NULL
    DROP PROCEDURE bkm.sp_fifo_CalistirmaAdim;
GO

CREATE PROCEDURE bkm.sp_fifo_CalistirmaAdim
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

PRINT 'sp_fifo_CalistirmaAdim proseduru olusturuldu';
GO

