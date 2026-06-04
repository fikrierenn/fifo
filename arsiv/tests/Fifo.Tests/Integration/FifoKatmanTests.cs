using Dapper;
using FluentAssertions;
using Fifo.Tests.Fixtures;
using Microsoft.Data.SqlClient;

namespace Fifo.Tests.Integration;

[Collection("Database")]
[Trait("Category", "Integration")]
public class FifoKatmanTests
{
    private readonly DbFixture _fixture;

    public FifoKatmanTests(DbFixture fixture) => _fixture = fixture;

    [Fact]
    public async Task Insert_ValidKatman_CanReadBack()
    {
        await using var conn = new SqlConnection(_fixture.ConnectionString);
        await conn.OpenAsync();
        long katmanId = 0;

        try
        {
            katmanId = await conn.ExecuteScalarAsync<long>("""
                INSERT INTO FifoKatman (StkId, GirisTarihi, KaynakTip, GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
                OUTPUT INSERTED.KatmanId
                VALUES (-99999, '2026-01-01', 'FATURA', 100, 100, 56.50, 'NORMAL')
                """);

            katmanId.Should().BeGreaterThan(0);

            var birimMaliyet = await conn.ExecuteScalarAsync<decimal>(
                "SELECT BirimMaliyet FROM FifoKatman WHERE KatmanId = @Id",
                new { Id = katmanId });
            birimMaliyet.Should().Be(56.50m);
        }
        finally
        {
            if (katmanId > 0)
                await conn.ExecuteAsync("DELETE FROM FifoKatman WHERE KatmanId = @Id", new { Id = katmanId });
        }
    }

    [Fact]
    public async Task Insert_NegativeGirisMiktar_FailsCheckConstraint()
    {
        await using var conn = new SqlConnection(_fixture.ConnectionString);
        await conn.OpenAsync();

        var act = async () => await conn.ExecuteAsync("""
            INSERT INTO FifoKatman (StkId, GirisTarihi, KaynakTip, GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
            VALUES (-99999, '2026-01-01', 'FATURA', -10, -10, 56.50, 'NORMAL')
            """);

        await act.Should().ThrowAsync<SqlException>();
    }

    [Fact]
    public async Task Insert_KalanGreaterThanGiris_FailsCheckConstraint()
    {
        await using var conn = new SqlConnection(_fixture.ConnectionString);
        await conn.OpenAsync();

        var act = async () => await conn.ExecuteAsync("""
            INSERT INTO FifoKatman (StkId, GirisTarihi, KaynakTip, GirisMiktar, KalanMiktar, BirimMaliyet, Durum)
            VALUES (-99999, '2026-01-01', 'FATURA', 100, 200, 56.50, 'NORMAL')
            """);

        await act.Should().ThrowAsync<SqlException>();
    }
}
