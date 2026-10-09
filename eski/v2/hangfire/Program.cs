using Fifo.Hangfire;
using Hangfire;
using Serilog;
using Serilog.Events;

// Bootstrap logger — captures startup errors before full Serilog config loads
Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
    .MinimumLevel.Override("Hangfire",  LogEventLevel.Information)
    .Enrich.FromLogContext()
    .Enrich.WithThreadId()
    .WriteTo.Console(
        outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj} {Properties}{NewLine}{Exception}")
    .WriteTo.File(
        path: "logs/fifo-.log",
        rollingInterval: RollingInterval.Day,
        retainedFileCountLimit: 30,
        outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] {Message:lj} {Properties}{NewLine}{Exception}")
    .CreateBootstrapLogger();

try
{
    Log.Information("FIFO Hangfire host starting...");

    var builder = WebApplication.CreateBuilder(args);

    // Two-stage Serilog: bootstrap → full config read from appsettings
    builder.Host.UseSerilog((ctx, services, cfg) => cfg
        .ReadFrom.Configuration(ctx.Configuration)
        .ReadFrom.Services(services)
        .MinimumLevel.Override("Microsoft",                    LogEventLevel.Warning)
        .MinimumLevel.Override("Microsoft.Hosting.Lifetime",   LogEventLevel.Information)
        .MinimumLevel.Override("Hangfire",                     LogEventLevel.Information)
        .Enrich.FromLogContext()
        .Enrich.WithThreadId()
        .WriteTo.Console(
            outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj}{NewLine}{Exception}")
        .WriteTo.File(
            path: "logs/fifo-.log",
            rollingInterval: RollingInterval.Day,
            retainedFileCountLimit: 30));

    // DI: FIFO jobs + Hangfire + DB connection
    builder.Services.AddFifoJobs(builder.Configuration);

    var app = builder.Build();

    // Hangfire dashboard — restrict to local/internal network in production
    // (add an IDashboardAuthorizationFilter implementation for prod)
    app.UseHangfireDashboard("/hangfire", new DashboardOptions
    {
        DashboardTitle = "FIFO Cost — Hangfire",
        Authorization  = [],
    });

    // Recurring job: 1st of each month at 01:00, processes previous month.
    // ExecutePreviousMonth computes DateTime.Now at execution time, not registration time.
    RecurringJob.AddOrUpdate<FifoMonthlyJob>(
        "fifo-monthly",
        "fifo",
        job => job.ExecutePreviousMonth(null),
        Cron.Monthly(1, 1));

    app.MapGet("/health", () => "OK");

    app.Run();
}
catch (Exception ex)
{
    Log.Fatal(ex, "FIFO Hangfire host stopped unexpectedly.");
}
finally
{
    Log.CloseAndFlush();
}
