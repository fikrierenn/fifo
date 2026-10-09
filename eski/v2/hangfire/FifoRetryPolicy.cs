using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using Polly;
using Polly.Retry;

namespace Fifo.Hangfire;

/// <summary>
/// V2-09: FIFO batch operasyonlari icin Polly retry matrix.
///
/// Hata tipleri ve strateji:
///   Deadlock    (1205)   → 3x retry, 1-2-4s exponential
///   Timeout     (-2)     → 2x retry, 5-15s linear
///   Transient   (IsTransient) → 3x retry, 2-4-8s exponential
///   Uygulama / veri hatasi (>=50000 veya 50000'in altı RAISERROR) → RETRY YOK
/// </summary>
public sealed class FifoRetryPolicy
{
    // SQL Server hata numaralari
    private const int DeadlockNumber  = 1205;
    private const int TimeoutNumber   = -2;

    public ResiliencePipeline<T> BuildBatchPipeline<T>(ILogger logger) =>
        new ResiliencePipelineBuilder<T>()
            // 1) Deadlock: 3x, exponential 1-2-4s
            .AddRetry(new RetryStrategyOptions<T>
            {
                ShouldHandle = new PredicateBuilder<T>()
                    .Handle<SqlException>(ex => ex.Number == DeadlockNumber),
                MaxRetryAttempts = 3,
                Delay            = TimeSpan.FromSeconds(1),
                BackoffType      = DelayBackoffType.Exponential,
                UseJitter        = true,
                OnRetry = args =>
                {
                    logger.LogWarning(
                        "Deadlock yakalandı (deneme {AttemptNumber}). {Delay}s sonra yeniden deneniyor.",
                        args.AttemptNumber + 1, args.RetryDelay.TotalSeconds);
                    return ValueTask.CompletedTask;
                }
            })
            // 2) Command timeout: 2x, linear 5-15s
            .AddRetry(new RetryStrategyOptions<T>
            {
                ShouldHandle = new PredicateBuilder<T>()
                    .Handle<SqlException>(ex => ex.Number == TimeoutNumber),
                MaxRetryAttempts = 2,
                DelayGenerator = args => new ValueTask<TimeSpan?>(
                    args.AttemptNumber == 0 ? TimeSpan.FromSeconds(5) : TimeSpan.FromSeconds(15)
                ),
                OnRetry = args =>
                {
                    logger.LogWarning(
                        "SQL timeout (deneme {AttemptNumber}). {Delay}s sonra yeniden deneniyor.",
                        args.AttemptNumber + 1, args.RetryDelay.TotalSeconds);
                    return ValueTask.CompletedTask;
                }
            })
            // 3) SQL Server transient hatalar (baglanti, ag vb.)
            .AddRetry(new RetryStrategyOptions<T>
            {
                ShouldHandle = new PredicateBuilder<T>()
                    .Handle<SqlException>(ex =>
                        ex.IsTransient &&
                        ex.Number != DeadlockNumber &&
                        ex.Number != TimeoutNumber),
                MaxRetryAttempts = 3,
                Delay            = TimeSpan.FromSeconds(2),
                BackoffType      = DelayBackoffType.Exponential,
                UseJitter        = true,
                OnRetry = args =>
                {
                    logger.LogWarning(
                        "Transient SQL hatasi ({Number}, deneme {AttemptNumber}). Yeniden deneniyor.",
                        ((SqlException)args.Outcome.Exception!).Number, args.AttemptNumber + 1);
                    return ValueTask.CompletedTask;
                }
            })
            .Build();

    /// <summary>Verilen exception'in retry yapilmamasi gereken bir uygulama/veri hatasi olup olmadigini kontrol eder.</summary>
    public static bool IsApplicationError(Exception ex) =>
        ex is SqlException sql && sql.Number >= 50000;
}
