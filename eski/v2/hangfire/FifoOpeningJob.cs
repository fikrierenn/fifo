using System.Data;
using Dapper;
using Hangfire;
using Hangfire.Server;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Fifo.Hangfire;

/// <summary>
/// Opening inventory costing job — 2-phase pipeline (V2-06).
///
/// Phase 1 (Fast Pass): calls sp_Fifo_AcilisMaliyetlendir with @atlamaAylikDevir=1,
///   pricing all products quickly via purchase/central/condition fallbacks.
///   The heavy "monthly carryover" step is skipped; NO_PURCHASE products are
///   written to FifoSorunluStoklar for the tail pass.
///
/// Phase 2 (Tail Pass): processes NO_PURCHASE products one-by-one with
///   @atlamaAylikDevir=0 and a longer per-product timeout.
///
/// Trigger example:
///   BackgroundJob.Enqueue&lt;FifoOpeningJob&gt;(j => j.Execute("2025-05-31", null));
/// </summary>
public sealed class FifoOpeningJob(
    IDbConnection db,
    IOptions<FifoJobOptions> opts,
    ILogger<FifoOpeningJob> logger)
{
    private readonly FifoJobOptions  _opts  = opts.Value;
    private readonly FifoRetryPolicy _retry = new();

    // Tail pass: longer timeout per product (monthly carryover is expensive)
    private const int TailTimeoutSeconds = 600;

    [JobDisplayName("FIFO Opening | {0}")]
    [AutomaticRetry(Attempts = 0)]
    public async Task Execute(string inventoryDateStr, PerformContext? ctx)
    {
        if (!DateOnly.TryParse(inventoryDateStr, out var parsed))
            throw new ArgumentException($"Invalid inventory date: {inventoryDateStr}", nameof(inventoryDateStr));

        var inventoryDate = parsed.ToDateTime(TimeOnly.MinValue);

        logger.LogInformation("FIFO Opening starting. InventoryDate={Date}", inventoryDateStr);

        var pipeline = _retry.BuildBatchPipeline<int>(logger);

        // ====================================================
        // PHASE 1: Fast Pass — atlamaAylikDevir = 1
        // ====================================================
        logger.LogInformation("Phase 1: Fast pass (atlamaAylikDevir=1) starting...");

        try
        {
            await pipeline.ExecuteAsync(async _ =>
            {
                await db.ExecuteAsync(
                    @"EXEC dbo.sp_Fifo_AcilisMaliyetlendir
                        @EnvanterTarihi       = @Date,
                        @atlamaAylikDevir     = 1",
                    new { Date = inventoryDate },
                    commandTimeout: 1800  // 30 min — all products, heavy step skipped
                );
                return 0;
            });
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Phase 1 failed. Tail pass will not run.");
            throw;
        }

        logger.LogInformation("Phase 1 complete.");

        // ====================================================
        // PHASE 2: Tail Pass — NO_PURCHASE products one-by-one
        // ====================================================
        var tailStkIds = (await db.QueryAsync<int>(
            @"SELECT DISTINCT StkId
              FROM dbo.FifoSorunluStoklar
              WHERE EnvanterTarihi = @Date
                AND SorunTipi     = 'ALIS_YOK'
              ORDER BY StkId",
            new { Date = inventoryDate }
        )).AsList();

        if (tailStkIds.Count == 0)
        {
            logger.LogInformation("Phase 2: No NO_PURCHASE products. Done.");
            return;
        }

        logger.LogInformation(
            "Phase 2: {Count} NO_PURCHASE products queued (timeout={Timeout}s/product).",
            tailStkIds.Count, TailTimeoutSeconds);

        int succeeded = 0, failed = 0;

        foreach (var stkId in tailStkIds)
        {
            try
            {
                await pipeline.ExecuteAsync(async _ =>
                {
                    await db.ExecuteAsync(
                        @"EXEC dbo.sp_Fifo_AcilisMaliyetlendir
                            @EnvanterTarihi   = @Date,
                            @StkId            = @StkId,
                            @atlamaAylikDevir = 0",
                        new { Date = inventoryDate, StkId = stkId },
                        commandTimeout: TailTimeoutSeconds
                    );
                    return 0;
                });

                succeeded++;

                if (succeeded % 50 == 0)
                    logger.LogDebug("Phase 2 progress: {Succeeded}/{Total}", succeeded, tailStkIds.Count);
            }
            catch (Exception ex) when (!FifoRetryPolicy.IsApplicationError(ex))
            {
                // All retries exhausted for this product — skip and continue
                failed++;
                logger.LogWarning(ex,
                    "Phase 2: StkId={StkId} monthly carryover failed (total failures: {Failed}).",
                    stkId, failed);

                if (failed > _opts.MaxFailedProducts)
                {
                    var msg = $"Tail pass max failure threshold exceeded ({failed} > {_opts.MaxFailedProducts}).";
                    logger.LogError("Opening tail pass stopping: {Msg}", msg);
                    throw new InvalidOperationException(msg);
                }
            }
        }

        logger.LogInformation(
            "FIFO Opening complete. Phase2: {Succeeded} OK, {Failed} FAILED (total queued: {Total}).",
            succeeded, failed, tailStkIds.Count);
    }
}
