using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

namespace Fifo.Tests.Fixtures;

/// <summary>
/// Remote BKMMaliyet DB'ye bağlanan fixture.
/// Integration testler bu fixture'ı kullanır.
/// VPN bağlı olmalı (192.168.40.201).
/// </summary>
public sealed class DbFixture : IAsyncLifetime
{
    public string ConnectionString { get; private set; } = "";
    public IConfiguration Configuration { get; private set; } = null!;

    public async Task InitializeAsync()
    {
        // appsettings + Development overlay'den connection string oku
        var appDir = Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "app");
        Configuration = new ConfigurationBuilder()
            .SetBasePath(appDir)
            .AddJsonFile("appsettings.json", optional: false)
            .AddJsonFile("appsettings.Development.json", optional: true)
            .Build();

        ConnectionString = Configuration.GetConnectionString("BKMMaliyet")!;

        // Bağlantı testi
        await using var conn = new SqlConnection(ConnectionString);
        await conn.OpenAsync();
    }

    public Task DisposeAsync() => Task.CompletedTask;
}

[CollectionDefinition("Database")]
public class DatabaseCollection : ICollectionFixture<DbFixture> { }
