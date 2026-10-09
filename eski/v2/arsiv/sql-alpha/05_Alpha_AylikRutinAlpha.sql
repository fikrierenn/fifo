USE BKMMaliyet;
GO

-- =============================================================
-- ALPHA WRAPPER: AYLIK RUTIN + SENTETIK FALLBACK + FIFO RERUN
-- Amac: Tek cagrida aylik alis/cikis, sentetik katman ve tekrar FIFO
-- Not: FIFO rerun-safe iyilestirmesi ayni/cari donem rerun icin tasarlanmistir.
-- =============================================================

CREATE OR ALTER PROCEDURE bkm.sp_fifo_AylikRutinAlpha
(
    @yil INT,
    @ay INT,
    @stkID INT = NULL,
    @calistirmaId UNIQUEIDENTIFIER = NULL,
    @sentetikSatinalmaSarti VARCHAR(50) = NULL, -- sadece sentetik fallback fiyat secimi icin
    @sabitFallbackBirimMaliyet DECIMAL(18,6) = NULL,
    @sentetikAktif BIT = 1
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @yil IS NULL OR @ay IS NULL OR @ay NOT BETWEEN 1 AND 12
    BEGIN
        RAISERROR('Gecersiz yil/ay parametresi.', 16, 1);
        RETURN;
    END

    IF @sabitFallbackBirimMaliyet IS NOT NULL AND @sabitFallbackBirimMaliyet <= 0
    BEGIN
        RAISERROR('Sabit fallback birim maliyet 0''dan buyuk olmali.', 16, 1);
        RETURN;
    END

    DECLARE @baslangic DATE = DATEFROMPARTS(@yil, @ay, 1);
    DECLARE @bitis DATE = EOMONTH(@baslangic);
    DECLARE @yerelTrans BIT = 0;
    DECLARE @sentetikGerekli BIT = 0;

    BEGIN TRY
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @yerelTrans = 1;
        END

        -- 1) Normal aylik alis + fifo cikis
        EXEC bkm.sp_fifo_AylikCalistir
            @yil = @yil,
            @ay = @ay,
            @stkID = @stkID,
            @calistirmaId = @calistirmaId;

        IF @sentetikAktif = 1
        BEGIN
            IF OBJECT_ID('tempdb..#sentetikDryRun', 'U') IS NOT NULL DROP TABLE #sentetikDryRun;
            CREATE TABLE #sentetikDryRun (
                stkID INT NOT NULL,
                girisTarihi DATE NOT NULL,
                miktarToplam DECIMAL(18,4) NOT NULL,
                birimMaliyet DECIMAL(18,6) NULL,
                durum VARCHAR(20) NOT NULL,
                satinalmaSarti VARCHAR(50) NULL
            );

            INSERT INTO #sentetikDryRun
            EXEC bkm.sp_fifo_SentetikAlisKatmanOlustur
                @sorunTarihi = @bitis,
                @girisTarihi = @bitis,
                @sentetikSatinalmaSarti = @sentetikSatinalmaSarti,
                @stkID = @stkID,
                @sabitFallbackBirimMaliyet = @sabitFallbackBirimMaliyet,
                @dryRun = 1;

            IF EXISTS (
                SELECT 1
                FROM #sentetikDryRun
                WHERE birimMaliyet IS NOT NULL
                  AND birimMaliyet > 0
            )
                SET @sentetikGerekli = 1;

            IF @sentetikGerekli = 1
            BEGIN
                -- 2) STOK_YETERSIZ sorunlarindan sentetik katman uret
                EXEC bkm.sp_fifo_SentetikAlisKatmanOlustur
                    @sorunTarihi = @bitis,
                    @girisTarihi = @bitis,
                    @sentetikSatinalmaSarti = @sentetikSatinalmaSarti,
                    @stkID = @stkID,
                    @sabitFallbackBirimMaliyet = @sabitFallbackBirimMaliyet,
                    @dryRun = 0;

                -- 3) Ayni ay FIFO cikisini sentetik katmanlari da dahil ederek tekrar hesapla
                EXEC bkm.sp_fifo_StokMaliyetCalistir
                    @alisBaslangic = @baslangic,
                    @alisBitis = @bitis,
                    @satisBaslangic = @baslangic,
                    @satisBitis = @bitis,
                    @stkID = @stkID,
                    @calistirmaId = @calistirmaId,
                    @calistirAcilis = 0,
                    @calistirAlis = 0,
                    @calistirCikis = 1;
            END
            ELSE
            BEGIN
                PRINT 'Sentetik katman gerekmiyor veya fiyat bulunamadi; ikinci FIFO rerun atlandi.';
            END
        END

        IF @yerelTrans = 1 AND XACT_STATE() = 1
            COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @yerelTrans = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        DECLARE @hataMesaji NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @hataNumarasi INT = ERROR_NUMBER();
        DECLARE @hataDurumu INT = ERROR_STATE();

        RAISERROR('sp_fifo_AylikRutinAlpha hatasi: %s', 16, 1, @hataMesaji);
        RETURN;
    END CATCH
END
GO

PRINT 'sp_fifo_AylikRutinAlpha olusturuldu';
GO
