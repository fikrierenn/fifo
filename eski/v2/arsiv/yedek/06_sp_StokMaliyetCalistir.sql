-- =============================================================
-- TOPLU FIFO CALISTIRMA PROSEDURU
-- Amaç: Manuel ve job calistirmalari ayni SP uzerinden yapmak
-- =============================================================


CREATE OR ALTER PROCEDURE bkm.sp_fifo_RunStep
(
    @runId UNIQUEIDENTIFIER,
    @stepKey VARCHAR(50),
    @stepName VARCHAR(100),
    @stepOrder INT,
    @status VARCHAR(20),
    @message VARCHAR(500) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @runId IS NULL OR @stepKey IS NULL
        RETURN;

    IF EXISTS (SELECT 1 FROM bkm.fifo_RunStep WHERE runId = @runId AND stepKey = @stepKey)
    BEGIN
        UPDATE bkm.fifo_RunStep
        SET status = @status,
            stepName = @stepName,
            stepOrder = @stepOrder,
            message = @message,
            startedAt = CASE
                WHEN @status IN ('RUNNING','DONE','ERROR','SKIPPED') AND startedAt IS NULL THEN GETDATE()
                ELSE startedAt
            END,
            endedAt = CASE
                WHEN @status IN ('DONE','ERROR','SKIPPED') THEN GETDATE()
                ELSE endedAt
            END,
            updatedAt = GETDATE()
        WHERE runId = @runId AND stepKey = @stepKey;
    END
    ELSE
    BEGIN
        INSERT INTO bkm.fifo_RunStep
            (runId, stepKey, stepName, stepOrder, status, message, startedAt, endedAt)
        VALUES
            (@runId, @stepKey, @stepName, @stepOrder, @status, @message,
             CASE WHEN @status IN ('RUNNING','DONE','ERROR','SKIPPED') THEN GETDATE() ELSE NULL END,
             CASE WHEN @status IN ('DONE','ERROR','SKIPPED') THEN GETDATE() ELSE NULL END);
    END
END
GO

CREATE OR ALTER PROCEDURE bkm.sp_fifo_StokMaliyetCalistir
(
    @envanterTarihi  DATE = NULL,
    @alisBaslangic   DATE = NULL,
    @alisBitis       DATE = NULL,
    @satisBaslangic  DATE = NULL,
    @satisBitis      DATE = NULL,
    @stkID           INT = NULL,
    @runId           UNIQUEIDENTIFIER = NULL,
    @calistirAcilis  BIT  = 0,
    @calistirAlis    BIT  = 1,
    @calistirCikis   BIT  = 1
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @stepKey VARCHAR(50) = NULL;
    DECLARE @stepName VARCHAR(100) = NULL;
    DECLARE @stepOrder INT = NULL;

    IF @calistirAcilis = 1 AND @envanterTarihi IS NULL
    BEGIN
        RAISERROR('Envanter tarihi bos olamaz', 16, 1);
        RETURN;
    END

    IF @calistirAlis = 1 AND (@alisBaslangic IS NULL OR @alisBitis IS NULL)
    BEGIN
        RAISERROR('Alis tarihleri bos olamaz', 16, 1);
        RETURN;
    END

    IF @calistirCikis = 1 AND (@satisBaslangic IS NULL OR @satisBitis IS NULL)
    BEGIN
        RAISERROR('Satis tarihleri bos olamaz', 16, 1);
        RETURN;
    END

    IF @calistirAlis = 1 AND @alisBaslangic > @alisBitis
    BEGIN
        RAISERROR('Alis baslangic tarihi bitis tarihinden buyuk olamaz', 16, 1);
        RETURN;
    END

    IF @calistirCikis = 1 AND @satisBaslangic > @satisBitis
    BEGIN
        RAISERROR('Satis baslangic tarihi bitis tarihinden buyuk olamaz', 16, 1);
        RETURN;
    END

    BEGIN TRY
        IF @calistirAcilis = 1
        BEGIN
            EXEC bkm.sp_fifo_StokMaliyetAcilis
                @envanterTarihi = @envanterTarihi,
                @stkID = @stkID,
                @runId = @runId;
        END

        IF @calistirAlis = 1
        BEGIN
            SET @stepKey = 'alis';
            SET @stepName = 'Alis katman';
            SET @stepOrder = 1;
            IF @runId IS NOT NULL
                EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'RUNNING', NULL;

            EXEC bkm.sp_fifo_StokMaliyetAlisKatman
                @baslangicTarihi = @alisBaslangic,
                @bitisTarihi = @alisBitis,
                @stkID = @stkID,
                @runId = @runId;

            IF @runId IS NOT NULL
                EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'DONE', NULL;
        END
        ELSE IF @runId IS NOT NULL AND @calistirCikis = 1
        BEGIN
            EXEC bkm.sp_fifo_RunStep @runId, 'alis', 'Alis katman', 1, 'SKIPPED', 'CalistirAlis=0';
        END

        IF @calistirCikis = 1
        BEGIN
            SET @stepKey = 'cikis';
            SET @stepName = 'FIFO cikis';
            SET @stepOrder = 2;
            IF @runId IS NOT NULL
                EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'RUNNING', NULL;

            EXEC bkm.sp_fifo_StokMaliyetFIFOCikis
                @satisBaslangic = @satisBaslangic,
                @satisBitis = @satisBitis,
                @stkID = @stkID,
                @runId = @runId;

            IF @runId IS NOT NULL
                EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'DONE', NULL;

            SET @stepKey = 'rapor';
            SET @stepName = 'Sonuc hazirligi';
            SET @stepOrder = 3;
            IF @runId IS NOT NULL
            BEGIN
                EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'RUNNING', NULL;
                EXEC bkm.sp_fifo_RunStep @runId, @stepKey, @stepName, @stepOrder, 'DONE', NULL;
            END
        END
        ELSE IF @runId IS NOT NULL AND @calistirAlis = 1
        BEGIN
            EXEC bkm.sp_fifo_RunStep @runId, 'cikis', 'FIFO cikis', 2, 'SKIPPED', 'CalistirCikis=0';
            EXEC bkm.sp_fifo_RunStep @runId, 'rapor', 'Sonuc hazirligi', 3, 'SKIPPED', 'CalistirCikis=0';
        END
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @runMessage VARCHAR(500) = SUBSTRING(CONVERT(VARCHAR(500), @ErrorMessage), 1, 500);
        IF @runId IS NOT NULL AND @stepKey IS NOT NULL
            EXEC bkm.sp_fifo_RunStep
                @runId = @runId,
                @stepKey = @stepKey,
                @stepName = @stepName,
                @stepOrder = @stepOrder,
                @status = 'ERROR',
                @message = @runMessage;
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        THROW;
    END CATCH
END
GO

PRINT 'sp_fifo_StokMaliyetCalistir proseduru olusturuldu';
GO

