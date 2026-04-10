using App.Lib;
using Dapper;
using FluentAssertions;
using Fifo.Tests.Fixtures;
using Microsoft.Data.SqlClient;

namespace Fifo.Tests.Integration;

[Collection("Database")]
[Trait("Category", "Integration")]
public class MaliyetLoggerTests
{
    private readonly DbFixture _fixture;

    public MaliyetLoggerTests(DbFixture fixture) => _fixture = fixture;

    private MaliyetLogger CreateLogger() => new(new Db(_fixture.Configuration));

    [Fact]
    public async Task FullLifecycle_BaslatAdimBitir_DurumOkuTamamlandi()
    {
        var logger = CreateLogger();
        Guid islemId = Guid.Empty;

        try
        {
            // Başlat
            islemId = await logger.BaslatAsync("Test Islem", aciklama: "xUnit test");
            islemId.Should().NotBe(Guid.Empty);

            // Adım yaz
            await logger.AdimYazAsync(islemId, "TEST_ADIM", "Test Adimi", 1, "TAMAMLANDI", "OK");

            // Bitir
            await logger.BitirAsync(islemId, "TAMAMLANDI");

            // Durum oku
            var durum = await logger.DurumOkuAsync(islemId);
            durum.Should().NotBeNull();
            durum!.Durum.Should().Be("TAMAMLANDI");
            durum.Adimlar.Should().NotBeEmpty();
        }
        finally
        {
            // Temizle
            if (islemId != Guid.Empty)
            {
                await using var conn = new SqlConnection(_fixture.ConnectionString);
                await conn.OpenAsync();
                await conn.ExecuteAsync("DELETE FROM MaliyetIslemAdim WHERE IslemId = @Id", new { Id = islemId });
                await conn.ExecuteAsync("DELETE FROM MaliyetIslem WHERE IslemId = @Id", new { Id = islemId });
            }
        }
    }

    [Fact]
    public async Task DurumOkuAsync_NonExistentId_ReturnsNull()
    {
        var logger = CreateLogger();

        var durum = await logger.DurumOkuAsync(Guid.NewGuid());

        durum.Should().BeNull();
    }
}
