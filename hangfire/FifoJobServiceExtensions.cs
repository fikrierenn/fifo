using System.Data;
using Hangfire;
using Hangfire.SqlServer;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace Fifo.Hangfire;

/// <summary>
/// V2-01 / V2-10: DI kayit + Hangfire konfigurasyonu.
/// Program.cs'e tek satir eklenir: builder.Services.AddFifoJobs(builder.Configuration)
/// </summary>
public static class FifoJobServiceExtensions
{
    public static IServiceCollection AddFifoJobs(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        // --- Options ---
        services.Configure<FifoJobOptions>(
            configuration.GetSection(FifoJobOptions.SectionName));

        // --- DB baglantisi (Dapper icin scoped IDbConnection) ---
        var cs = configuration.GetConnectionString("BKMMaliyet")
                 ?? throw new InvalidOperationException(
                        "ConnectionStrings:BKMMaliyet eksik.");

        services.AddScoped<IDbConnection>(_ =>
        {
            var conn = new SqlConnection(cs);
            conn.Open();
            return conn;
        });

        // --- Register job classes ---
        services.AddScoped<FifoMonthlyJob>();
        services.AddScoped<FifoOpeningJob>();

        // --- Hangfire: SQL Server storage ---
        services.AddHangfire(cfg => cfg
            .SetDataCompatibilityLevel(CompatibilityLevel.Version_180)
            .UseSimpleAssemblyNameTypeSerializer()
            .UseRecommendedSerializerSettings()
            .UseSqlServerStorage(cs, new SqlServerStorageOptions
            {
                CommandBatchMaxTimeout       = TimeSpan.FromMinutes(5),
                SlidingInvisibilityTimeout   = TimeSpan.FromMinutes(5),
                QueuePollInterval            = TimeSpan.Zero,
                UseRecommendedIsolationLevel = true,
                DisableGlobalLocks           = true,
            }));

        // --- Hangfire server (worker) ---
        services.AddHangfireServer(opts =>
        {
            opts.WorkerCount           = 2;   // FIFO agir is - kucuk worker pool
            opts.Queues                = ["fifo", "default"];
            opts.ServerTimeout         = TimeSpan.FromMinutes(30);
            opts.ShutdownTimeout       = TimeSpan.FromSeconds(30);
        });

        return services;
    }
}
