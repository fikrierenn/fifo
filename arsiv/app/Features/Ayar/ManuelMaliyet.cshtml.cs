using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Dapper;
using App.Lib;

namespace App.Features.Ayar;

[IgnoreAntiforgeryToken]
public class ManuelMaliyetModel : PageModel
{
    private readonly Db _db;
    public ManuelMaliyetModel(Db db) => _db = db;

    public List<ManuelMaliyetSatir> Kayitlar { get; set; } = new();

    public async Task OnGetAsync()
    {
        await using var conn = await _db.OpenAsync();
        Kayitlar = (await conn.QueryAsync<ManuelMaliyetSatir>("""
            SELECT ManuelId, StkId, BirimMaliyet, GecerliBaslangic, GecerliBitis,
                   Aciklama, EkleyenKullanici, EklenmeTarihi
            FROM vw_Fifo_ManuelMaliyet
            ORDER BY EklenmeTarihi DESC
            """, commandTimeout: 10)).AsList();

        if (Kayitlar.Count > 0)
            await _db.GetUrunlerAsync(Kayitlar.Select(k => k.StkId).Distinct());
    }

    public async Task<IActionResult> OnPostEkleAsync(int stkId, decimal birimMaliyet,
        DateTime gecerliBaslangic, DateTime? gecerliBitis, string? aciklama)
    {
        if (stkId <= 0 || birimMaliyet <= 0)
            return new JsonResult(new { ok = false, error = "StkId ve BirimMaliyet > 0 olmali." })
                { StatusCode = 400 };

        await using var conn = await _db.OpenAsync();
        await conn.ExecuteAsync("""
            INSERT INTO FifoManuelMaliyet (StkId, BirimMaliyet, GecerliBaslangic, GecerliBitis, Aciklama)
            VALUES (@StkId, @BirimMaliyet, @GecerliBaslangic, @GecerliBitis, @Aciklama)
            """, new { StkId = stkId, BirimMaliyet = birimMaliyet,
                       GecerliBaslangic = gecerliBaslangic, GecerliBitis = gecerliBitis,
                       Aciklama = aciklama }, commandTimeout: 10);

        return new JsonResult(new { ok = true });
    }

    public async Task<IActionResult> OnPostSilAsync(int manuelId)
    {
        await using var conn = await _db.OpenAsync();
        await conn.ExecuteAsync(
            "UPDATE FifoManuelMaliyet SET Aktif = 0 WHERE ManuelId = @Id",
            new { Id = manuelId }, commandTimeout: 10);

        return new JsonResult(new { ok = true });
    }

    public async Task<IActionResult> OnGetExportAsync()
    {
        await using var conn = await _db.OpenAsync();
        var rows = await conn.QueryAsync<ManuelMaliyetSatir>("""
            SELECT ManuelId, StkId, BirimMaliyet, GecerliBaslangic, GecerliBitis,
                   Aciklama, EkleyenKullanici, EklenmeTarihi
            FROM vw_Fifo_ManuelMaliyet
            ORDER BY EklenmeTarihi DESC
            """, commandTimeout: 10);
        var csv = CsvExporter.ToCsv(rows);
        return File(csv, "text/csv", $"ManuelMaliyet_{DateTime.Now:yyyyMMdd}.csv");
    }
}

public class ManuelMaliyetSatir
{
    public int ManuelId { get; set; }
    public int StkId { get; set; }
    public decimal BirimMaliyet { get; set; }
    public DateTime GecerliBaslangic { get; set; }
    public DateTime? GecerliBitis { get; set; }
    public string? Aciklama { get; set; }
    public string? EkleyenKullanici { get; set; }
    public DateTime EklenmeTarihi { get; set; }
}
