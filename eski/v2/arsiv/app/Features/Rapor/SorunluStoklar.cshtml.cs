using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Dapper;
using App.Lib;


namespace App.Features.Rapor;

public class SorunluStoklarModel : PageModel
{
    private readonly Db _db;
    public SorunluStoklarModel(Db db) => _db = db;

    [BindProperty(SupportsGet = true)]
    public DateTime? EnvanterTarihi { get; set; }

    [BindProperty(SupportsGet = true)]
    public string? SorunTipi { get; set; }

    public int PageSize { get; set; } = 50;
    public bool HasMore { get; set; }
    public List<SorunOzet> OzetListesi { get; set; } = new();
    public List<SorunluStokSatir> Satirlar { get; set; } = new();
    public List<DateTime> MevcutTarihler { get; set; } = new();

    private const string BaseSql = """
        SELECT EnvanterTarihi, MekanId, StkId, SorunTipi, StokMiktar,
               Aciklama, KayitTarihi
        FROM FifoSorunluStoklar
        WHERE (@EnvanterTarihi IS NULL OR EnvanterTarihi = @EnvanterTarihi)
          AND (@SorunTipi IS NULL OR SorunTipi = @SorunTipi)
        ORDER BY KayitTarihi DESC
        """;

    public async Task OnGetAsync()
    {
        await using var conn = await _db.OpenAsync();

        MevcutTarihler = (await conn.QueryAsync<DateTime>(
            "SELECT DISTINCT EnvanterTarihi FROM FifoSorunluStoklar ORDER BY EnvanterTarihi DESC"
        )).ToList();

        if (EnvanterTarihi == null && MevcutTarihler.Count > 0)
            EnvanterTarihi = MevcutTarihler[0];

        var param = new { EnvanterTarihi, SorunTipi };

        OzetListesi = (await conn.QueryAsync<SorunOzet>("""
            SELECT SorunTipi, COUNT(DISTINCT StkId) AS UrunSayisi,
                   SUM(StokMiktar) AS ToplamMiktar
            FROM FifoSorunluStoklar
            WHERE (@EnvanterTarihi IS NULL OR EnvanterTarihi = @EnvanterTarihi)
            GROUP BY SorunTipi
            ORDER BY UrunSayisi DESC
            """, param)).ToList();

        var rows = (await conn.QueryAsync<SorunluStokSatir>(
            BaseSql + "\nOFFSET 0 ROWS FETCH NEXT @Limit ROWS ONLY",
            new { EnvanterTarihi, SorunTipi, Limit = PageSize + 1 })).ToList();

        HasMore = rows.Count > PageSize;
        Satirlar = rows.Take(PageSize).ToList();

        await _db.GetUrunlerAsync(Satirlar.Select(s => s.StkId).Distinct());
    }

    public async Task<IActionResult> OnGetMoreAsync(int offset)
    {
        await using var conn = await _db.OpenAsync();

        if (EnvanterTarihi == null)
        {
            var tarihler = (await conn.QueryAsync<DateTime>(
                "SELECT DISTINCT EnvanterTarihi FROM FifoSorunluStoklar ORDER BY EnvanterTarihi DESC"
            )).ToList();
            if (tarihler.Count > 0) EnvanterTarihi = tarihler[0];
        }

        var rows = (await conn.QueryAsync<SorunluStokSatir>(
            BaseSql + "\nOFFSET @Offset ROWS FETCH NEXT @Limit ROWS ONLY",
            new { EnvanterTarihi, SorunTipi, Offset = offset, Limit = PageSize + 1 })).ToList();

        var hasMore = rows.Count > PageSize;
        var data = rows.Take(PageSize).ToList();

        await _db.GetUrunlerAsync(data.Select(s => s.StkId).Distinct());

        return new JsonResult(new
        {
            rows = data.Select(s => new
            {
                envanterTarihi = s.EnvanterTarihi.ToString("yyyy-MM-dd"),
                s.MekanId,
                mekanAdi = Db.MekanAdi(s.MekanId),
                s.StkId,
                urunAdi = Db.UrunAdi(s.StkId),
                s.SorunTipi,
                stokMiktar = s.StokMiktar.ToString("N2"),
                aciklama = s.Aciklama ?? "-",
                kayitTarihi = s.KayitTarihi.ToString("yyyy-MM-dd HH:mm")
            }),
            hasMore
        });
    }

    public async Task<IActionResult> OnGetExportAsync()
    {
        await using var conn = await _db.OpenAsync();

        var mevcutTarihler = (await conn.QueryAsync<DateTime>(
            "SELECT DISTINCT EnvanterTarihi FROM FifoSorunluStoklar ORDER BY EnvanterTarihi DESC"
        )).ToList();

        if (EnvanterTarihi == null && mevcutTarihler.Count > 0)
            EnvanterTarihi = mevcutTarihler[0];

        var param = new { EnvanterTarihi, SorunTipi };

        var satirlar = (await conn.QueryAsync<SorunluStokSatir>(
            BaseSql, param)).ToList();

        var csv = CsvExporter.ToCsv(satirlar);
        return File(csv, "text/csv", "sorunlu_stoklar.csv");
    }
}

public class SorunOzet
{
    public string SorunTipi { get; set; } = "";
    public int UrunSayisi { get; set; }
    public decimal ToplamMiktar { get; set; }
}

public class SorunluStokSatir
{
    public DateTime EnvanterTarihi { get; set; }
    public int MekanId { get; set; }
    public int StkId { get; set; }
    public string SorunTipi { get; set; } = "";
    public decimal StokMiktar { get; set; }
    public string? Aciklama { get; set; }
    public DateTime KayitTarihi { get; set; }
}
