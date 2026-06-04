using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Dapper;
using App.Lib;

namespace App.Features.Rapor;

public class BrutKarModel : PageModel
{
    private readonly Db _db;
    public BrutKarModel(Db db) => _db = db;

    [BindProperty(SupportsGet = true)]
    public int? Yil { get; set; }

    [BindProperty(SupportsGet = true)]
    public int? Ay { get; set; }

    public List<MekanBrutKar> Mekanlar { get; set; } = new();
    public BrutKarToplam Toplam { get; set; } = new();
    public List<int> MevcutDonemler { get; set; } = new();

    public async Task OnGetAsync()
    {
        await using var conn = await _db.OpenAsync();

        MevcutDonemler = (await conn.QueryAsync<int>(
            "SELECT DISTINCT YilAy FROM OrtalamaAylikMaliyet ORDER BY YilAy DESC"
        )).ToList();

        if (Yil == null && MevcutDonemler.Count > 0)
        {
            var sonDonem = MevcutDonemler[0];
            Yil = sonDonem / 100;
            Ay = sonDonem % 100;
        }

        if (Yil == null || Ay == null) return;

        var gelirler = (await conn.QueryAsync<MekanGelir>("""
            SELECT
                h.ehMekan AS MekanId,
                SUM(CONVERT(DECIMAL(18,4), ABS(h.ehTutarN))) AS SatisGeliri
            FROM DerinSISBkm.dbo.irsHrk h
            WHERE h.ehMekan IN (1, 12, 4477, 4478)
              AND h.ehAdetN < 0
              AND YEAR(h.ehTrhS) = @Yil AND MONTH(h.ehTrhS) = @Ay
            GROUP BY h.ehMekan
            """, new { Yil, Ay })).ToDictionary(g => g.MekanId);

        var smmler = (await conn.QueryAsync<MekanSmmSatir>("""
            SELECT
                MekanId,
                SUM(CASE WHEN HareketTipi = 'SATIS' THEN CikisTutar ELSE 0 END) AS SMM
            FROM FifoCikisDetay
            WHERE YEAR(HareketTarihi) = @Yil AND MONTH(HareketTarihi) = @Ay
            GROUP BY MekanId
            """, new { Yil, Ay })).ToDictionary(s => s.MekanId);

        foreach (var mekanId in Db.Mekanlar.Keys)
        {
            var gelir = gelirler.GetValueOrDefault(mekanId)?.SatisGeliri ?? 0;
            var smm = smmler.GetValueOrDefault(mekanId)?.SMM ?? 0;
            var brutKar = gelir - smm;
            var marj = gelir > 0 ? brutKar / gelir * 100 : 0;

            Mekanlar.Add(new MekanBrutKar
            {
                MekanId = mekanId,
                MekanAdi = Db.MekanAdi(mekanId),
                SatisGeliri = gelir,
                SMM = smm,
                BrutKar = brutKar,
                BrutKarMarji = marj
            });
        }

        var topGelir = Mekanlar.Sum(m => m.SatisGeliri);
        var topSmm = Mekanlar.Sum(m => m.SMM);
        var topBrutKar = topGelir - topSmm;
        Toplam = new BrutKarToplam
        {
            SatisGeliri = topGelir,
            SMM = topSmm,
            BrutKar = topBrutKar,
            BrutKarMarji = topGelir > 0 ? topBrutKar / topGelir * 100 : 0
        };
    }

    public async Task<IActionResult> OnGetExportAsync()
    {
        await OnGetAsync();

        if (Mekanlar.Count == 0) return RedirectToPage();

        var csv = CsvExporter.ToCsv(Mekanlar);
        return File(csv, "text/csv", $"brutkar_{Yil}_{Ay:D2}.csv");
    }
}

public class MekanGelir
{
    public int MekanId { get; set; }
    public decimal SatisGeliri { get; set; }
}

public class MekanSmmSatir
{
    public int MekanId { get; set; }
    public decimal SMM { get; set; }
}

public class MekanBrutKar
{
    public int MekanId { get; set; }
    public string MekanAdi { get; set; } = "";
    public decimal SatisGeliri { get; set; }
    public decimal SMM { get; set; }
    public decimal BrutKar { get; set; }
    public decimal BrutKarMarji { get; set; }
}

public class BrutKarToplam
{
    public decimal SatisGeliri { get; set; }
    public decimal SMM { get; set; }
    public decimal BrutKar { get; set; }
    public decimal BrutKarMarji { get; set; }
}
