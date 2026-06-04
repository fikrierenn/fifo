using App.Lib;
using Dapper;
using FluentAssertions;
using Fifo.Tests.Fixtures;
using Microsoft.Data.SqlClient;

namespace Fifo.Tests.Integration;

[Collection("Database")]
[Trait("Category", "Integration")]
public class DbTests
{
    private readonly DbFixture _fixture;

    public DbTests(DbFixture fixture) => _fixture = fixture;

    private Db CreateDb() => new(_fixture.Configuration);

    [Fact]
    public async Task OpenAsync_ReturnsOpenConnection()
    {
        var db = CreateDb();
        await using var conn = await db.OpenAsync();

        conn.State.Should().Be(System.Data.ConnectionState.Open);
    }

    [Fact]
    public async Task DevreDisiEkle_VeKaldir_Rollback()
    {
        var db = CreateDb();
        var testStkId = -99999; // Gerçek veriyle çakışmayacak negatif ID

        try
        {
            // Ekle
            var eklendi = await db.DevreDisiEkleAsync(testStkId, "Test");
            eklendi.Should().BeTrue();

            // Kontrol — direkt DB'den oku
            await using var conn = new SqlConnection(_fixture.ConnectionString);
            await conn.OpenAsync();
            var count = await conn.ExecuteScalarAsync<int>(
                "SELECT COUNT(*) FROM FifoDevreDisiUrunler WHERE StkId = @StkId",
                new { StkId = testStkId });
            count.Should().Be(1);

            // Cache kontrol
            Db.DevreDisiMi(testStkId).Should().BeTrue();
        }
        finally
        {
            // Temizle (rollback yerine explicit delete)
            await db.DevreDisiKaldirAsync(testStkId);
            Db.ResetDevreDisiCache();
        }
    }

    [Fact]
    public async Task GetDevreDisiListeAsync_ReturnsRecords()
    {
        var db = CreateDb();

        var liste = await db.GetDevreDisiListeAsync();

        // Liste null olmamalı (boş olabilir)
        liste.Should().NotBeNull();
    }
}
