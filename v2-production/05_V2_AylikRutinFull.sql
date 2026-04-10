USE BKMMaliyet;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE dbo.sp_Fifo_AylikRutinFull
(
    @Yil INT,
    @Ay INT,
    @StkId INT = NULL,
    @IslemId UNIQUEIDENTIFIER = NULL,
    @SentetikSatinalmaSarti VARCHAR(50) = NULL,
    @SabitFallbackBirimMaliyet DECIMAL(18,6) = NULL,
    @SentetikAktif BIT = 1
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Yil IS NULL OR @Ay IS NULL OR @Ay NOT BETWEEN 1 AND 12
    BEGIN
        RAISERROR('Gecersiz yil/ay parametresi.', 16, 1);
        RETURN;
    END

    IF @SabitFallbackBirimMaliyet IS NOT NULL AND @SabitFallbackBirimMaliyet <= 0
    BEGIN
        RAISERROR('Sabit fallback birim maliyet 0''dan buyuk olmali.', 16, 1);
        RETURN;
    END

    DECLARE @Baslangic DATE = DATEFROMPARTS(@Yil, @Ay, 1);
    DECLARE @Bitis DATE = EOMONTH(@Baslangic);
    DECLARE @YerelTrans BIT = 0;
    DECLARE @SentetikGerekli BIT = 0;

    BEGIN TRY
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @YerelTrans = 1;
        END

        EXEC dbo.sp_Fifo_AylikCalistir
            @yil = @Yil,
            @ay = @Ay,
            @StkId = @StkId,
            @IslemId = @IslemId;

        IF @SentetikAktif = 1
        BEGIN
            IF OBJECT_ID('tempdb..#sentetikDryRun', 'U') IS NOT NULL DROP TABLE #sentetikDryRun;
            CREATE TABLE #sentetikDryRun (
                StkId INT NOT NULL,
                GirisTarihi DATE NOT NULL,
                GirisMiktar DECIMAL(18,4) NOT NULL,
                BirimMaliyet DECIMAL(18,6) NULL,
                Durum VARCHAR(20) NOT NULL,
                SatinalmaSarti VARCHAR(50) NULL
            );

            INSERT INTO #sentetikDryRun
            EXEC dbo.sp_Fifo_SentetikKatmanOlustur
                @SorunTarihi = @Bitis,
                @GirisTarihi = @Bitis,
                @SentetikSatinalmaSarti = @SentetikSatinalmaSarti,
                @StkId = @StkId,
                @SabitFallbackBirimMaliyet = @SabitFallbackBirimMaliyet,
                @DryRun = 1;

            IF EXISTS (
                SELECT 1
                FROM #sentetikDryRun
                WHERE BirimMaliyet IS NOT NULL
                  AND BirimMaliyet > 0
            )
                SET @SentetikGerekli = 1;

            IF @SentetikGerekli = 1
            BEGIN
                EXEC dbo.sp_Fifo_SentetikKatmanOlustur
                    @SorunTarihi = @Bitis,
                    @GirisTarihi = @Bitis,
                    @SentetikSatinalmaSarti = @SentetikSatinalmaSarti,
                    @StkId = @StkId,
                    @SabitFallbackBirimMaliyet = @SabitFallbackBirimMaliyet,
                    @DryRun = 0;

                EXEC dbo.sp_Fifo_Calistir
                    @alisBaslangic = @Baslangic,
                    @alisBitis = @Bitis,
                    @satisBaslangic = @Baslangic,
                    @satisBitis = @Bitis,
                    @StkId = @StkId,
                    @IslemId = @IslemId,
                    @calistirAcilis = 0,
                    @calistirAlis = 0,
                    @calistirCikis = 1;
            END
        END

        IF @YerelTrans = 1 AND XACT_STATE() = 1
            COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @YerelTrans = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        DECLARE @HataMesaji NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('sp_Fifo_AylikRutinFull hatasi: %s', 16, 1, @HataMesaji);
        RETURN;
    END CATCH
END
GO
