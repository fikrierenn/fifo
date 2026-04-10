using System.Data;
using Microsoft.Data.SqlClient;

namespace Fifo.Hangfire;

/// <summary>
/// dbo.StkIdListType TVP'sini Dapper ile kullanmak icin yardimci.
/// </summary>
internal static class StkIdTvp
{
    /// <summary>
    /// StkId listesini SqlParameter'a donusturur.
    /// Dapper'da parametre olarak dogrudan kullanilabilir:
    ///   new { StkIdList = StkIdTvp.ToParam(ids) }
    /// </summary>
    public static SqlParameter ToParam(IEnumerable<int> stkIds)
    {
        var dt = new DataTable();
        dt.Columns.Add("StkId", typeof(int));

        foreach (var id in stkIds)
            dt.Rows.Add(id);

        return new SqlParameter
        {
            ParameterName = "@StkIdList",
            SqlDbType     = SqlDbType.Structured,
            TypeName      = "dbo.StkIdListType",
            Value         = dt
        };
    }

    /// <summary>StkId listesini N'lik gruplara boler.</summary>
    public static IEnumerable<IReadOnlyList<int>> Chunk(IEnumerable<int> source, int boyut)
    {
        var batch = new List<int>(boyut);
        foreach (var id in source)
        {
            batch.Add(id);
            if (batch.Count == boyut)
            {
                yield return batch.AsReadOnly();
                batch = new List<int>(boyut);
            }
        }
        if (batch.Count > 0)
            yield return batch.AsReadOnly();
    }
}
