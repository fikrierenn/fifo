using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Dapper;
using App.Lib;

namespace App.Features.Rapor;

public class TrendModel : PageModel
{
    private readonly Db _db;
    public TrendModel(Db db) => _db = db;

    [BindProperty(SupportsGet = true)]
    public int DonemSayisi { get; set; } = 6;

    public List<DonemOzet> Donemler { get; set; } = new();
    public List<AylikSmm> SmmVerileri { get; set; } = new();

    public async Task OnGetAsync()
    {
        if (DonemSayisi is not (3 or 6 or 12)) DonemSayisi = 6;

        await using var conn = await _db.OpenAsync();

        Donemler = (await conn.QueryAsync<DonemOzet>("""
            SELECT TOP (@DonemSayisi) YilAy,
                   COUNT(DISTINCT StkId) AS UrunSayisi,
                   SUM(AySonuMiktar) AS ToplamMiktar,
                   SUM(AySonuTutar) AS ToplamDeger,
                   SUM(GirisMiktar) AS ToplamGiris,
                   SUM(GirisTutar) AS ToplamGirisTutar,
                   SUM(CikisMiktar) AS ToplamCikis
            FROM OrtalamaAylikMaliyet
            GROUP BY YilAy
            ORDER BY YilAy DESC
            """, new { DonemSayisi })).ToList();

        SmmVerileri = (await conn.QueryAsync<AylikSmm>("""
            SELECT TOP (@DonemSayisi)
                   YEAR(HareketTarihi) * 100 + MONTH(HareketTarihi) AS YilAy,
                   SUM(CASE WHEN HareketTipi = 'SATIS' THEN CikisTutar ELSE 0 END) AS SatisSMM,
                   SUM(CASE WHEN HareketTipi = 'IADE' THEN CikisTutar ELSE 0 END) AS IadeSMM,
                   SUM(CikisTutar) AS NetSMM,
                   COUNT(DISTINCT StkId) AS HareketliUrun
            FROM FifoCikisDetay
            GROUP BY YEAR(HareketTarihi) * 100 + MONTH(HareketTarihi)
            ORDER BY YilAy DESC
            """, new { DonemSayisi })).ToList();
    }

    public async Task<IActionResult> OnGetExportAsync()
    {
        if (DonemSayisi is not (3 or 6 or 12)) DonemSayisi = 6;

        await using var conn = await _db.OpenAsync();

        var satirlar = (await conn.QueryAsync<TrendExportSatir>("""
            SELECT d.YilAy,
                   d.UrunSayisi,
                   d.ToplamDeger,
                   d.ToplamGirisTutar,
                   s.SatisSMM,
                   s.IadeSMM,
                   s.NetSMM,
                   s.HareketliUrun
            FROM (
                SELECT TOP (@DonemSayisi) YilAy,
                       COUNT(DISTINCT StkId) AS UrunSayisi,
                       SUM(AySonuTutar) AS ToplamDeger,
                       SUM(GirisTutar) AS ToplamGirisTutar
                FROM OrtalamaAylikMaliyet
                GROUP BY YilAy
                ORDER BY YilAy DESC
            ) d
            LEFT JOIN (
                SELECT TOP (@DonemSayisi)
                       YEAR(HareketTarihi) * 100 + MONTH(HareketTarihi) AS YilAy,
                       SUM(CASE WHEN HareketTipi = 'SATIS' THEN CikisTutar ELSE 0 END) AS SatisSMM,
                       SUM(CASE WHEN HareketTipi = 'IADE' THEN CikisTutar ELSE 0 END) AS IadeSMM,
                       SUM(CikisTutar) AS NetSMM,
                       COUNT(DISTINCT StkId) AS HareketliUrun
                FROM FifoCikisDetay
                GROUP BY YEAR(HareketTarihi) * 100 + MONTH(HareketTarihi)
                ORDER BY YilAy DESC
            ) s ON s.YilAy = d.YilAy
            ORDER BY d.YilAy DESC
            """, new { DonemSayisi })).ToList();

        var csv = CsvExporter.ToCsv(satirlar);
        return File(csv, "text/csv", $"trend_{DonemSayisi}ay.csv");
    }
}

public class DonemOzet
{
    public int YilAy { get; set; }
    public int UrunSayisi { get; set; }
    public decimal ToplamMiktar { get; set; }
    public decimal ToplamDeger { get; set; }
    public decimal ToplamGiris { get; set; }
    public decimal ToplamGirisTutar { get; set; }
    public decimal ToplamCikis { get; set; }
}

public class AylikSmm
{
    public int YilAy { get; set; }
    public decimal SatisSMM { get; set; }
    public decimal IadeSMM { get; set; }
    public decimal NetSMM { get; set; }
    public int HareketliUrun { get; set; }
}

public class TrendExportSatir
{
    public int YilAy { get; set; }
    public int UrunSayisi { get; set; }
    public decimal ToplamDeger { get; set; }
    public decimal ToplamGirisTutar { get; set; }
    public decimal SatisSMM { get; set; }
    public decimal IadeSMM { get; set; }
    public decimal NetSMM { get; set; }
    public int HareketliUrun { get; set; }
}
