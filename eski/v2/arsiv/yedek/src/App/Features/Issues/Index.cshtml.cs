using Dapper;
using App.Lib;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace App.Features.Issues;

public class IndexModel : PageModel
{
    private readonly Db _db;

    public IndexModel(Db db)
    {
        _db = db;
    }

    [BindProperty(SupportsGet = true)]
    public DateTime? Baslangic { get; set; }

    [BindProperty(SupportsGet = true)]
    public DateTime? Bitis { get; set; }

    public List<IssueRow> Rows { get; } = [];
    public List<IssueSummary> Summary { get; } = [];

    public void OnGet()
    {
        var today = DateTime.Today;
        Baslangic ??= today.AddDays(-30);
        Bitis ??= today;

        using var connection = _db.Open();

        Rows.AddRange(connection.Query<IssueRow>(
            """
            SELECT TOP 200
                stkID AS StkId,
                envanterTarihi AS EnvanterTarihi,
                stokMiktar AS StokMiktar,
                sorunTip AS SorunTip,
                aciklama AS Aciklama,
                kayitTarihi AS KayitTarihi
            FROM bkm.fifo_StokMaliyetSorunlu
            WHERE kayitTarihi >= @Baslangic
              AND kayitTarihi < DATEADD(DAY, 1, @Bitis)
            ORDER BY kayitTarihi DESC;
            """,
            new { Baslangic, Bitis }));

        Summary.AddRange(connection.Query<IssueSummary>(
            """
            SELECT
                sorunTip AS SorunTip,
                COUNT(*) AS Adet
            FROM bkm.fifo_StokMaliyetSorunlu
            WHERE kayitTarihi >= @Baslangic
              AND kayitTarihi < DATEADD(DAY, 1, @Bitis)
            GROUP BY sorunTip
            ORDER BY COUNT(*) DESC;
            """,
            new { Baslangic, Bitis }));
    }

    public sealed class IssueRow
    {
        public int StkId { get; init; }
        public DateTime EnvanterTarihi { get; init; }
        public decimal StokMiktar { get; init; }
        public string SorunTip { get; init; } = string.Empty;
        public string? Aciklama { get; init; }
        public DateTime KayitTarihi { get; init; }
    }

    public sealed class IssueSummary
    {
        public string SorunTip { get; init; } = string.Empty;
        public int Adet { get; init; }
    }
}
