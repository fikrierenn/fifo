using Dapper;
using App.Lib;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace App.Features.Home;

public class IndexModel : PageModel
{
    private readonly Db _db;

    public IndexModel(Db db)
    {
        _db = db;
    }

    public SummaryModel Summary { get; private set; } = new();
    public List<IssueCount> IssueSummary { get; } = [];
    public string? ErrorMessage { get; private set; }

    public void OnGet()
    {
        var since = DateTime.Today.AddDays(-30);

        try
        {
            using var connection = _db.Open();

            Summary = connection.QuerySingleOrDefault<SummaryModel>(
                """
                SELECT
                    COUNT(*) AS LineCount,
                    COUNT(DISTINCT stkID) AS ProductCount,
                    ISNULL(SUM(cikisTutar), 0) AS TotalCost
                FROM bkm.fifo_StokMaliyetCikis
                WHERE hareketTarihi >= @since;
                """,
                new { since }) ?? new SummaryModel();

            IssueSummary.AddRange(connection.Query<IssueCount>(
                """
                SELECT TOP 6
                    sorunTip AS SorunTip,
                    COUNT(*) AS Adet
                FROM bkm.fifo_StokMaliyetSorunlu
                WHERE kayitTarihi >= @since
                GROUP BY sorunTip
                ORDER BY COUNT(*) DESC;
                """,
                new { since }));
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
    }

    public sealed class SummaryModel
    {
        public int LineCount { get; init; }
        public int ProductCount { get; init; }
        public decimal TotalCost { get; init; }
    }

    public sealed class IssueCount
    {
        public string SorunTip { get; init; } = string.Empty;
        public int Adet { get; init; }
    }
}
