using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Dapper;
using App.Lib;

namespace App.Features.Rapor;

public class IslemLogModel : PageModel
{
    private readonly Db _db;
    public IslemLogModel(Db db) => _db = db;

    [BindProperty(SupportsGet = true)]
    public Guid? IslemId { get; set; }

    public List<IslemLogSatir> Islemler { get; set; } = new();
    public IslemLogSatir? SeciliIslem { get; set; }
    public List<IslemAdimSatir> Adimlar { get; set; } = new();

    public async Task OnGetAsync()
    {
        await using var conn = await _db.OpenAsync();

        if (IslemId.HasValue)
        {
            SeciliIslem = await conn.QuerySingleOrDefaultAsync<IslemLogSatir>("""
                SELECT IslemId, IslemAdi, Baslangic, Bitis, Durum, Aciklama,
                       EnvanterTarihi, MekanId, StkId
                FROM MaliyetIslem
                WHERE IslemId = @IslemId
                """, new { IslemId });

            if (SeciliIslem != null)
            {
                Adimlar = (await conn.QueryAsync<IslemAdimSatir>("""
                    SELECT AdimKodu, AdimAdi, SiraNo, Durum, Mesaj, Baslangic, Bitis, Guncelleme
                    FROM MaliyetIslemAdim
                    WHERE IslemId = @IslemId
                    ORDER BY SiraNo
                    """, new { IslemId })).ToList();

                if (SeciliIslem.StkId.HasValue)
                    await _db.GetUrunlerAsync(new[] { SeciliIslem.StkId.Value });
            }
        }
        else
        {
            Islemler = (await conn.QueryAsync<IslemLogSatir>("""
                SELECT TOP 100 IslemId, IslemAdi, Baslangic, Bitis, Durum, Aciklama,
                       EnvanterTarihi, MekanId, StkId
                FROM MaliyetIslem
                ORDER BY Baslangic DESC
                """)).ToList();

            await _db.GetUrunlerAsync(Islemler.Where(i => i.StkId.HasValue).Select(i => i.StkId!.Value).Distinct());
        }
    }
}

public class IslemLogSatir
{
    public Guid IslemId { get; set; }
    public string IslemAdi { get; set; } = "";
    public DateTime Baslangic { get; set; }
    public DateTime? Bitis { get; set; }
    public string Durum { get; set; } = "";
    public string? Aciklama { get; set; }
    public DateTime? EnvanterTarihi { get; set; }
    public int? MekanId { get; set; }
    public int? StkId { get; set; }
}

public class IslemAdimSatir
{
    public string AdimKodu { get; set; } = "";
    public string AdimAdi { get; set; } = "";
    public int SiraNo { get; set; }
    public string Durum { get; set; } = "";
    public string? Mesaj { get; set; }
    public DateTime? Baslangic { get; set; }
    public DateTime? Bitis { get; set; }
    public DateTime? Guncelleme { get; set; }
}
