using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Dapper;
using App.Lib;

namespace App.Features.Rapor;

public class CikisRaporuModel : PageModel
{
    private readonly Db _db;
    public CikisRaporuModel(Db db) => _db = db;

    [BindProperty(SupportsGet = true)]
    public DateTime? Baslangic { get; set; }

    [BindProperty(SupportsGet = true)]
    public DateTime? Bitis { get; set; }

    [BindProperty(SupportsGet = true)]
    public int? StkId { get; set; }

    [BindProperty(SupportsGet = true)]
    public int? MekanId { get; set; }

    [BindProperty(SupportsGet = true)]
    public string? HareketTipi { get; set; }

    public int PageSize { get; set; } = 50;
    public bool HasMore { get; set; }
    public List<CikisSatir> Satirlar { get; set; } = new();
    public CikisOzet Ozet { get; set; } = new();

    private const string BaseSql = """
        SELECT CikisId, StkId, HareketTarihi, HareketTipi, MekanId, BelgeNo,
               KatmanId, KatmanTarihi, KatmanBelgeNo, Miktar, BirimMaliyet, CikisTutar, KayitTarihi
        FROM FifoCikisDetay
        WHERE HareketTarihi BETWEEN @Baslangic AND @Bitis
          AND (@StkId IS NULL OR StkId = @StkId)
          AND (@MekanId IS NULL OR MekanId = @MekanId)
          AND (@HareketTipi IS NULL OR HareketTipi = @HareketTipi)
        ORDER BY HareketTarihi DESC, CikisId DESC
        """;

    public async Task OnGetAsync()
    {
        Baslangic ??= DateTime.Today.AddDays(-30);
        Bitis ??= DateTime.Today;

        var param = new { Baslangic, Bitis, StkId, MekanId, HareketTipi, Limit = PageSize + 1 };

        await using var conn = await _db.OpenAsync();

        var rows = (await conn.QueryAsync<CikisSatir>(
            BaseSql + "\nOFFSET 0 ROWS FETCH NEXT @Limit ROWS ONLY", param)).ToList();

        HasMore = rows.Count > PageSize;
        Satirlar = rows.Take(PageSize).ToList();

        Ozet = await conn.QuerySingleAsync<CikisOzet>("""
            SELECT COUNT(CikisId) AS ToplamSatir,
                   COUNT(DISTINCT StkId) AS UrunSayisi,
                   SUM(CikisTutar) AS ToplamTutar,
                   SUM(CASE WHEN HareketTipi='SATIS' THEN CikisTutar ELSE 0 END) AS SatisTutar,
                   SUM(CASE WHEN HareketTipi='IADE' THEN CikisTutar ELSE 0 END) AS IadeTutar
            FROM FifoCikisDetay
            WHERE HareketTarihi BETWEEN @Baslangic AND @Bitis
              AND (@StkId IS NULL OR StkId = @StkId)
              AND (@MekanId IS NULL OR MekanId = @MekanId)
              AND (@HareketTipi IS NULL OR HareketTipi = @HareketTipi)
            """, new { Baslangic, Bitis, StkId, MekanId, HareketTipi });

        await _db.GetUrunlerAsync(Satirlar.Select(s => s.StkId).Distinct());
    }

    public async Task<IActionResult> OnGetMoreAsync(int offset)
    {
        Baslangic ??= DateTime.Today.AddDays(-30);
        Bitis ??= DateTime.Today;

        var param = new { Baslangic, Bitis, StkId, MekanId, HareketTipi, Offset = offset, Limit = PageSize + 1 };

        await using var conn = await _db.OpenAsync();

        var rows = (await conn.QueryAsync<CikisSatir>(
            BaseSql + "\nOFFSET @Offset ROWS FETCH NEXT @Limit ROWS ONLY", param)).ToList();

        var hasMore = rows.Count > PageSize;
        var data = rows.Take(PageSize).ToList();

        await _db.GetUrunlerAsync(data.Select(s => s.StkId).Distinct());

        return new JsonResult(new
        {
            rows = data.Select(s => new
            {
                s.CikisId,
                s.StkId,
                urunAdi = Db.UrunAdi(s.StkId),
                hareketTarihi = s.HareketTarihi.ToString("yyyy-MM-dd"),
                s.HareketTipi,
                s.MekanId,
                mekanAdi = Db.MekanAdi(s.MekanId),
                belgeNo = s.BelgeNo ?? "-",
                katmanId = s.KatmanId?.ToString() ?? "-",
                miktar = s.Miktar.ToString("N4"),
                birimMaliyet = s.BirimMaliyet.ToString("N4"),
                cikisTutar = s.CikisTutar.ToString("N2")
            }),
            hasMore
        });
    }

    public async Task<IActionResult> OnGetExportAsync()
    {
        Baslangic ??= DateTime.Today.AddDays(-30);
        Bitis ??= DateTime.Today;

        var param = new { Baslangic, Bitis, StkId, MekanId, HareketTipi };

        await using var conn = await _db.OpenAsync();

        var satirlar = (await conn.QueryAsync<CikisSatir>(
            BaseSql, param)).ToList();

        var csv = CsvExporter.ToCsv(satirlar);
        return File(csv, "text/csv", "cikis_raporu.csv");
    }
}

public class CikisSatir
{
    public long CikisId { get; set; }
    public int StkId { get; set; }
    public DateTime HareketTarihi { get; set; }
    public string HareketTipi { get; set; } = "";
    public int MekanId { get; set; }
    public string? BelgeNo { get; set; }
    public long? KatmanId { get; set; }
    public DateTime? KatmanTarihi { get; set; }
    public string? KatmanBelgeNo { get; set; }
    public decimal Miktar { get; set; }
    public decimal BirimMaliyet { get; set; }
    public decimal CikisTutar { get; set; }
    public DateTime KayitTarihi { get; set; }
}

public class CikisOzet
{
    public int ToplamSatir { get; set; }
    public int UrunSayisi { get; set; }
    public decimal ToplamTutar { get; set; }
    public decimal SatisTutar { get; set; }
    public decimal IadeTutar { get; set; }
}
