-- Mesru kullanim: hicbir uyari CIKMAMALI.
IF OBJECT_ID('tempdb..#gecici','U') IS NOT NULL DROP TABLE #gecici;
DROP TABLE IF EXISTS #digeri;
SELECT StkId, BirimMaliyet INTO #katman FROM dbo.FifoKatman WHERE BirimMaliyet > 0;
INSERT INTO dbo.FifoKatman (StkId, BirimMaliyet)
SELECT k.StkId, k.BirimMaliyet FROM #katman k WHERE k.BirimMaliyet > 0;
SELECT SUM(a) / NULLIF(SUM(b), 0) AS oran FROM t;
SELECT x FROM h WHERE h.ehMekan IN (1, 12, 4477, 4478) AND h.ehAltDepo = 0;
CREATE OR ALTER PROCEDURE dbo.sp_Iyi AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        SELECT 1;
    END TRY
    BEGIN CATCH
        DECLARE @m NVARCHAR(4000) = ERROR_MESSAGE();
        THROW;
    END CATCH
END
