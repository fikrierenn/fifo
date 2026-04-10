using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Dapper;
using App.Lib;

namespace App.Features.Rapor;

public class DonemDegisimModel : PageModel
{
    private readonly Db _db;
    public DonemDegisimModel(Db db) => _db = db;

    [BindProperty(SupportsGet = true)]
    public int? SnapshotId { get; set; }

    public List<SnapshotOzet> Snapshotlar { get; set; } = new();
    public SnapshotOzet? SeciliSnapshot { get; set; }
    public List<DegisimSatir> Degisimler { get; set; } = new();

    public async Task OnGetAsync()
    {
        await using var conn = await _db.OpenAsync();

        if (SnapshotId.HasValue)
        {
            SeciliSnapshot = await conn.QuerySingleOrDefaultAsync<SnapshotOzet>("""
                SELECT SnapshotId, RunId, DonemYil, DonemAy, SnapshotTarihi,
                       ToplamKatman, ToplamKalanMiktar, ToplamCikisMiktar,
                       ToplamCikisTutar, OrtBirimMaliyet
                FROM FifoDonemSnapshot
                WHERE SnapshotId = @SnapshotId
                """, new { SnapshotId });

            if (SeciliSnapshot != null)
            {
                Degisimler = (await conn.QueryAsync<DegisimSatir>("""
                    SELECT StkId,
                           OncekiKatmanSayisi, OncekiKalan, OncekiMaliyet, OncekiCikisMiktar, OncekiCikisTutar,
                           MevcutKatmanSayisi, MevcutKalan, MevcutMaliyet, MevcutCikisMiktar, MevcutCikisTutar,
                           MaliyetFark, MaliyetFarkYuzde, CikisTutarFark
                    FROM vw_Fifo_DonemDegisim
                    WHERE SnapshotId = @SnapshotId
                    ORDER BY ABS(MaliyetFarkYuzde) DESC
                    """, new { SnapshotId }, commandTimeout: 30)).AsList();

                if (Degisimler.Count > 0)
                    await _db.GetUrunlerAsync(Degisimler.Select(d => d.StkId).Distinct());
            }
        }
        else
        {
            Snapshotlar = (await conn.QueryAsync<SnapshotOzet>("""
                SELECT SnapshotId, RunId, DonemYil, DonemAy, SnapshotTarihi,
                       ToplamKatman, ToplamKalanMiktar, ToplamCikisMiktar,
                       ToplamCikisTutar, OrtBirimMaliyet
                FROM FifoDonemSnapshot
                ORDER BY SnapshotTarihi DESC
                """)).AsList();
        }
    }

    public async Task<IActionResult> OnGetExportAsync()
    {
        if (!SnapshotId.HasValue) return RedirectToPage();
        await using var conn = await _db.OpenAsync();
        var rows = await conn.QueryAsync<DegisimSatir>("""
            SELECT StkId, OncekiMaliyet, MevcutMaliyet, MaliyetFark, MaliyetFarkYuzde,
                   OncekiCikisTutar, MevcutCikisTutar, CikisTutarFark
            FROM vw_Fifo_DonemDegisim
            WHERE SnapshotId = @SnapshotId
            ORDER BY ABS(MaliyetFarkYuzde) DESC
            """, new { SnapshotId }, commandTimeout: 30);
        var csv = CsvExporter.ToCsv(rows);
        return File(csv, "text/csv", $"DonemDegisim_Snap{SnapshotId}_{DateTime.Now:yyyyMMdd}.csv");
    }
}

public class SnapshotOzet
{
    public int SnapshotId { get; set; }
    public Guid RunId { get; set; }
    public int DonemYil { get; set; }
    public int DonemAy { get; set; }
    public DateTime SnapshotTarihi { get; set; }
    public int ToplamKatman { get; set; }
    public decimal ToplamKalanMiktar { get; set; }
    public decimal ToplamCikisMiktar { get; set; }
    public decimal ToplamCikisTutar { get; set; }
    public decimal OrtBirimMaliyet { get; set; }

    public string DonemStr => $"{DonemYil}-{DonemAy:D2}";
}

public class DegisimSatir
{
    public int StkId { get; set; }
    public int OncekiKatmanSayisi { get; set; }
    public decimal OncekiKalan { get; set; }
    public decimal OncekiMaliyet { get; set; }
    public decimal OncekiCikisMiktar { get; set; }
    public decimal OncekiCikisTutar { get; set; }
    public int MevcutKatmanSayisi { get; set; }
    public decimal MevcutKalan { get; set; }
    public decimal MevcutMaliyet { get; set; }
    public decimal MevcutCikisMiktar { get; set; }
    public decimal MevcutCikisTutar { get; set; }
    public decimal MaliyetFark { get; set; }
    public decimal MaliyetFarkYuzde { get; set; }
    public decimal CikisTutarFark { get; set; }
}
