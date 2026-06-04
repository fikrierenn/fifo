using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Dapper;
using App.Lib;

namespace App.Features.Rapor;

public class KarsilastirmaModel : PageModel
{
    private readonly Db _db;
    public KarsilastirmaModel(Db db) => _db = db;

    [BindProperty(SupportsGet = true)]
    public int? YilAy { get; set; }

    public int PageSize { get; set; } = 50;
    public bool HasMore { get; set; }
    public List<MaliyetKarsilastirma> Satirlar { get; set; } = new();
    public List<int> MevcutDonemler { get; set; } = new();

    public async Task OnGetAsync()
    {
        await using var conn = await _db.OpenAsync();

        MevcutDonemler = (await conn.QueryAsync<int>(
            "SELECT DISTINCT YilAy FROM OrtalamaAylikMaliyet ORDER BY YilAy DESC"
        )).ToList();

        if (YilAy == null && MevcutDonemler.Count > 0)
            YilAy = MevcutDonemler[0];

        if (YilAy == null) return;

        var rows = (await conn.QueryAsync<MaliyetKarsilastirma>("""
            SELECT YilAy, StkId,
                   Ort_Miktar, Ort_BirimMaliyet, Ort_Tutar,
                   Fifo_Miktar, Fifo_BirimMaliyet, Fifo_Tutar,
                   BirimMaliyetFarki, FarkYuzdesi
            FROM vw_MaliyetKarsilastirma
            WHERE YilAy = @YilAy
            ORDER BY ABS(ISNULL(FarkYuzdesi, 0)) DESC
            OFFSET 0 ROWS FETCH NEXT @Limit ROWS ONLY
            """, new { YilAy, Limit = PageSize + 1 })).ToList();

        HasMore = rows.Count > PageSize;
        Satirlar = rows.Take(PageSize).ToList();

        await _db.GetUrunlerAsync(Satirlar.Select(s => s.StkId).Distinct());
    }

    public async Task<IActionResult> OnGetMoreAsync(int offset)
    {
        if (YilAy == null)
            return new JsonResult(new { rows = Array.Empty<object>(), hasMore = false });

        await using var conn = await _db.OpenAsync();

        var rows = (await conn.QueryAsync<MaliyetKarsilastirma>("""
            SELECT YilAy, StkId,
                   Ort_Miktar, Ort_BirimMaliyet, Ort_Tutar,
                   Fifo_Miktar, Fifo_BirimMaliyet, Fifo_Tutar,
                   BirimMaliyetFarki, FarkYuzdesi
            FROM vw_MaliyetKarsilastirma
            WHERE YilAy = @YilAy
            ORDER BY ABS(ISNULL(FarkYuzdesi, 0)) DESC
            OFFSET @Offset ROWS FETCH NEXT @Limit ROWS ONLY
            """, new { YilAy, Offset = offset, Limit = PageSize + 1 })).ToList();

        var hasMore = rows.Count > PageSize;
        var data = rows.Take(PageSize).ToList();

        await _db.GetUrunlerAsync(data.Select(s => s.StkId).Distinct());

        return new JsonResult(new
        {
            rows = data.Select(s => new
            {
                s.StkId,
                urunAdi = Db.UrunAdi(s.StkId),
                ortBirimMaliyet = s.Ort_BirimMaliyet.ToString("N4"),
                fifoBirimMaliyet = s.Fifo_BirimMaliyet?.ToString("N4") ?? "-",
                birimMaliyetFarki = s.BirimMaliyetFarki?.ToString("N4") ?? "-",
                farkYuzdesi = s.FarkYuzdesi,
                farkYuzdesiStr = s.FarkYuzdesi.HasValue
                    ? (s.FarkYuzdesi.Value > 0 ? "+" : "") + s.FarkYuzdesi.Value.ToString("N2") + "%"
                    : "-",
                devreDisi = Db.DevreDisiMi(s.StkId)
            }),
            hasMore
        });
    }

    public async Task<IActionResult> OnGetExportAsync()
    {
        await using var conn = await _db.OpenAsync();

        var mevcutDonemler = (await conn.QueryAsync<int>(
            "SELECT DISTINCT YilAy FROM OrtalamaAylikMaliyet ORDER BY YilAy DESC"
        )).ToList();

        if (YilAy == null && mevcutDonemler.Count > 0)
            YilAy = mevcutDonemler[0];

        if (YilAy == null) return RedirectToPage();

        var satirlar = (await conn.QueryAsync<MaliyetKarsilastirma>("""
            SELECT YilAy, StkId,
                   Ort_Miktar, Ort_BirimMaliyet, Ort_Tutar,
                   Fifo_Miktar, Fifo_BirimMaliyet, Fifo_Tutar,
                   BirimMaliyetFarki, FarkYuzdesi
            FROM vw_MaliyetKarsilastirma
            WHERE YilAy = @YilAy
            ORDER BY ABS(ISNULL(FarkYuzdesi, 0)) DESC
            """, new { YilAy })).ToList();

        var csv = CsvExporter.ToCsv(satirlar);
        return File(csv, "text/csv", "karsilastirma.csv");
    }
}

public class MaliyetKarsilastirma
{
    public int YilAy { get; set; }
    public int StkId { get; set; }
    public decimal Ort_Miktar { get; set; }
    public decimal Ort_BirimMaliyet { get; set; }
    public decimal Ort_Tutar { get; set; }
    public decimal? Fifo_Miktar { get; set; }
    public decimal? Fifo_BirimMaliyet { get; set; }
    public decimal? Fifo_Tutar { get; set; }
    public decimal? BirimMaliyetFarki { get; set; }
    public decimal? FarkYuzdesi { get; set; }
}
