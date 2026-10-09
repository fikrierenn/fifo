using Dapper;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace App.Lib;

public sealed class RunWorker : BackgroundService
{
    private const int LongTimeoutSeconds = 1800;
    private readonly RunQueue _queue;
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<RunWorker> _logger;

    public RunWorker(RunQueue queue, IServiceScopeFactory scopeFactory, ILogger<RunWorker> logger)
    {
        _queue = queue;
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var run in _queue.DequeueAllAsync(stoppingToken))
        {
            try
            {
                using var scope = _scopeFactory.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<Db>();
                using var connection = db.Open();

                await connection.ExecuteAsync(
                    """
                    UPDATE bkm.fifo_Run
                    SET status = 'RUNNING',
                        startedAt = GETDATE()
                    WHERE runId = @RunId;
                    """,
                    new { run.RunId });

                await connection.ExecuteAsync(
                    """
                    EXEC bkm.sp_fifo_StokMaliyetCalistir
                        @envanterTarihi = @EnvanterTarihi,
                        @alisBaslangic = @AlisBaslangic,
                        @alisBitis = @AlisBitis,
                        @satisBaslangic = @SatisBaslangic,
                        @satisBitis = @SatisBitis,
                        @stkID = @StkId,
                        @runId = @RunId,
                        @calistirAcilis = @CalistirAcilis,
                        @calistirAlis = @CalistirAlis,
                        @calistirCikis = @CalistirCikis;
                    """,
                    new
                    {
                        run.EnvanterTarihi,
                        run.AlisBaslangic,
                        run.AlisBitis,
                        run.SatisBaslangic,
                        run.SatisBitis,
                        run.StkId,
                        run.RunId,
                        run.CalistirAcilis,
                        run.CalistirAlis,
                        run.CalistirCikis
                    },
                    commandTimeout: LongTimeoutSeconds);

                await connection.ExecuteAsync(
                    """
                    UPDATE bkm.fifo_Run
                    SET status = 'DONE',
                        endedAt = GETDATE()
                    WHERE runId = @RunId;
                    """,
                    new { run.RunId });
            }
            catch (Exception ex)
            {
                await MarkFailedAsync(run.RunId, ex);
                _logger.LogError(ex, "FIFO run failed {RunId}", run.RunId);
            }
        }
    }

    private async Task MarkFailedAsync(Guid runId, Exception exception)
    {
        try
        {
            var message = exception.Message ?? string.Empty;
            if (message.Length > 500)
            {
                message = message[..500];
            }

            using var scope = _scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<Db>();
            using var connection = db.Open();

            await connection.ExecuteAsync(
                """
                UPDATE bkm.fifo_Run
                SET status = 'ERROR',
                    endedAt = GETDATE(),
                    message = @Message
                WHERE runId = @RunId;
                """,
                new { RunId = runId, Message = message });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "FIFO run status update failed {RunId}", runId);
        }
    }
}
