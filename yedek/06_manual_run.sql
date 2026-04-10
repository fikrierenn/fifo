-- =============================================================
-- MANUEL FIFO CALISTIRMA
-- Amaç: Acilis -> Alis Katman -> FIFO Cikis sirasiyla calistir
-- =============================================================

SET NOCOUNT ON;

-- Parametreler
DECLARE @envanterTarihi DATE = '31.12.2024';
DECLARE @alisBaslangic DATE = '01.01.2025';
DECLARE @alisBitis DATE = '27.11.2025';
DECLARE @satisBaslangic DATE = '01.01.2025';
DECLARE @satisBitis DATE = '27.11.2025';
DECLARE @stkID INT = NULL; -- tek urun icin ID girin
DECLARE @calistirAcilis BIT = 1; -- gece job icin 0 yapin
DECLARE @calistirAlis BIT = 1;
DECLARE @calistirCikis BIT = 1;

EXEC bkm.sp_fifo_StokMaliyetCalistir
    @envanterTarihi = @envanterTarihi,
    @alisBaslangic = @alisBaslangic,
    @alisBitis = @alisBitis,
    @satisBaslangic = @satisBaslangic,
    @satisBitis = @satisBitis,
    @stkID = @stkID,
    @calistirAcilis = @calistirAcilis,
    @calistirAlis = @calistirAlis,
    @calistirCikis = @calistirCikis;

-- Opsiyonel: urun senaryo tespitini calistirmak icin asagidaki satiri acin
-- :r TEST_urun_senaryo_tespit.sql
