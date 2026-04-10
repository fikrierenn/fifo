using System.Data;
using Fifo.Hangfire;
using FluentAssertions;

namespace Fifo.Tests.Unit;

public class StkIdTvpTests
{
    [Fact]
    public void ToParam_ReturnsStructuredParameter()
    {
        var param = StkIdTvp.ToParam(new[] { 1, 2, 3 });

        param.SqlDbType.Should().Be(SqlDbType.Structured);
        param.TypeName.Should().Be("dbo.StkIdListType");
        param.ParameterName.Should().Be("@StkIdList");
    }

    [Fact]
    public void ToParam_DataTableContainsAllIds()
    {
        var ids = new[] { 100, 200, 300 };
        var param = StkIdTvp.ToParam(ids);
        var dt = (DataTable)param.Value!;

        dt.Rows.Count.Should().Be(3);
        dt.Rows[0]["StkId"].Should().Be(100);
        dt.Rows[2]["StkId"].Should().Be(300);
    }

    [Fact]
    public void Chunk_SplitsCorrectly()
    {
        var ids = new[] { 1, 2, 3, 4, 5, 6, 7 };
        var chunks = StkIdTvp.Chunk(ids, 3).ToList();

        chunks.Should().HaveCount(3);
        chunks[0].Should().HaveCount(3);
        chunks[1].Should().HaveCount(3);
        chunks[2].Should().HaveCount(1);
    }

    [Fact]
    public void Chunk_EmptyInput_ReturnsNothing()
    {
        var chunks = StkIdTvp.Chunk(Array.Empty<int>(), 500).ToList();

        chunks.Should().BeEmpty();
    }
}
