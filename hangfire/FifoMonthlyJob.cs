using System.Data;
using Dapper;
using Hangfire;
using Hangfire.Server;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Fifo.Hangfire;

/// <summary>
/// Hangfire job: runs FIFO costing for a given month,
/// splitting the active product list into batches.
///
/// Manual trigger example (dashboard or code):
///   BackgroundJob.Enqueue&lt;FifoMonthlyJob&gt;(j => j.Execute(2026, 1, null));
/// </summary>
public sealed class FifoMonthlyJob(
    IDbConnection db,
    IOptions<FifoJobOptions> opts,
    ILogger<FifoMonthlyJob> logger)
{
    private readonly FifoJobOptions  _opts  = opts.Value;
    private readonly FifoRetryPolicy _retry = new();

    [JobDisplayName("FIFO Monthly | {0}-{1:D2}")]
    [AutomaticRetry(Attempts = 0)] // Hangfire-level retry disabled; transient retry handled by Polly
    public async Task Execute(int year, int month, PerformContext? ctx)
    {
        if (month is < 1 or > 12)
            throw new ArgumentOutOfRangeException(nameof(month));

        var runId = Guid.NewGuid();
        logger.LogInformation("FIFO Monthly run starting. RunId={RunId} Period={Year}-{Month:D2}", runId, year, month);

        // 1) Get active product list for the period
        var stkIds = (await db.QueryAsync<int>(
            "EXEC dbo.sp_Fifo_HareketliUrunListesi @Yil, @Ay",
            new { Yil = year, Ay = month },
            commandTimeout: 300
        )).AsList();

        if (stkIds.Count == 0)
        {
            logger.LogWarning("RunId={RunId}: No active products found for {Year}-{Month:D2}. Aborting.", runId, year, month);
            return;
        }

        var batches    = StkIdTvp.Chunk(stkIds, _opts.BatchSize).ToList();
        var batchCount = batches.Count;

        // 2) Open run record
        await db.ExecuteAsync(
            "EXEC dbo.sp_Fifo_BatchRunBaslat @RunId, @DonemYil, @DonemAy, @ToplamUrun, @ToplamBatch, @BatchBoyutu",
            new { RunId = runId, DonemYil = year, DonemAy = month,
                  ToplamUrun = stkIds.Count, ToplamBatch = batchCount,
                  BatchBoyutu = _opts.BatchSize }
        );

        logger.LogInformation("RunId={RunId}: {ProductCount} products, {BatchCount} batches (size={BatchSize})",
            runId, stkIds.Count, batchCount, _opts.BatchSize);

        int totalFailed = 0;
        int batchNo     = 1;

        // Polly pipeline: deadlock / timeout / transient retry
        var pipeline = _retry.BuildBatchPipeline<BatchSummary>(logger);

        // 3) Process each batch
        foreach (var batch in batches)
        {
            logger.LogDebug("RunId={RunId} Batch={BatchNo}/{Total} starting.", runId, batchNo, batchCount);

            try
            {
                var capturedBatchNo = batchNo;

                var summary = await pipeline.ExecuteAsync(async _ =>
                {
                    var tvpParam = StkIdTvp.ToParam(batch);

                    var dp = new DynamicParameters();
                    dp.Add("@Yil",      year);
                    dp.Add("@Ay",       month);
                    dp.Add("@RunId",    runId);
                    dp.Add("@BatchNo",  capturedBatchNo);
                    dp.Add("StkIdList", tvpParam);

                    return await db.QuerySingleAsync<BatchSummary>(
                        "EXEC dbo.sp_Fifo_AylikCalistirBatch @Yil, @Ay, @StkIdList, @RunId, @BatchNo",
                        dp,
                        commandTimeout: _opts.CommandTimeoutSeconds * batch.Count
                    );
                });

                totalFailed += summary.FailedProducts;

                logger.LogInformation(
                    "RunId={RunId} Batch={BatchNo}: {Success} OK, {Failed} FAILED.",
                    runId, batchNo, summary.SuccessProducts, summary.FailedProducts);

                if (totalFailed > _opts.MaxFailedProducts)
                {
                    var msg = $"Max failed product threshold exceeded ({totalFailed} > {_opts.MaxFailedProducts}). Stopping run.";
                    logger.LogError("RunId={RunId}: {Msg}", runId, msg);
                    await CompleteRunAsync(runId, "HATA", msg);
                    throw new InvalidOperationException(msg);
                }
            }
            catch (Exception ex) when (ex is not InvalidOperationException)
            {
                var msg = $"Batch {batchNo} failed: {ex.Message}";
                logger.LogError(ex, "RunId={RunId}: {Msg}", runId, msg);
                await CompleteRunAsync(runId, "HATA", msg);
                throw;
            }

            batchNo++;
        }

        // 4) Close run
        var finalStatus = totalFailed > 0 ? "KISMEN_HATA" : "TAMAMLANDI";
        await CompleteRunAsync(runId, finalStatus, totalFailed > 0 ? $"{totalFailed} products failed" : null);

        logger.LogInformation(
            "FIFO Monthly run complete. RunId={RunId} Period={Year}-{Month:D2} Status={Status} Failed={Failed}",
            runId, year, month, finalStatus, totalFailed);
    }

    /// <summary>
    /// Recurring job entry point: computes previous month at execution time
    /// (not at registration time, avoiding the DateTime.Now serialization pitfall).
    /// </summary>
    [JobDisplayName("FIFO Monthly | previous month")]
    [AutomaticRetry(Attempts = 0)]
    public Task ExecutePreviousMonth(PerformContext? ctx)
    {
        var now  = DateTime.Now;
        var prev = now.Month == 1
            ? new DateTime(now.Year - 1, 12, 1)
            : new DateTime(now.Year, now.Month - 1, 1);
        return Execute(prev.Year, prev.Month, ctx);
    }

    private Task CompleteRunAsync(Guid runId, string status, string? errorMessage) =>
        db.ExecuteAsync(
            "EXEC dbo.sp_Fifo_BatchRunBitir @RunId, @Durum, @HataMesaji",
            new { RunId = runId, Durum = status, HataMesaji = errorMessage }
        );

    private sealed record BatchSummary(int SuccessProducts, int FailedProducts, int TotalProducts);
}
