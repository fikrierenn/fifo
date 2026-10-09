using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Dapper;
using App.Lib;

namespace App.Features.Ayar;

[IgnoreAntiforgeryToken]
public class FallbackFiyatModel : PageModel
{
    private readonly Db _db;
    public FallbackFiyatModel(Db db) => _db = db;

    public List<FallbackFiyatDto> Fiyatlar { get; set; } = new();
    public string? Mesaj { get; set; }
    public bool MesajHata { get; set; }

    [BindProperty] public int EkleStkId { get; set; }
    [BindProperty] public string EkleSatinalmaSarti { get; set; } = "";
    [BindProperty] public int EkleMekanId { get; set; }
    [BindProperty] public decimal EkleBirimMaliyet { get; set; }
    [BindProperty] public decimal EkleMiktar { get; set; }
    [BindProperty] public string? EkleAciklama { get; set; }

    public async Task OnGetAsync()
    {
        await LoadListAsync();
    }

    public async Task<IActionResult> OnPostEkleAsync()
    {
        await using var conn = await _db.OpenAsync();

        var toplamTutar = EkleBirimMaliyet * EkleMiktar;

        await conn.ExecuteAsync("""
            INSERT INTO FifoFallbackFiyatlari (StkId, SatinalmaSarti, MekanId, BirimMaliyet, Miktar, ToplamTutar, Aciklama)
            VALUES (@StkId, @SatinalmaSarti, @MekanId, @BirimMaliyet, @Miktar, @ToplamTutar, @Aciklama)
            """, new
        {
            StkId = EkleStkId,
            SatinalmaSarti = EkleSatinalmaSarti,
            MekanId = EkleMekanId,
            BirimMaliyet = EkleBirimMaliyet,
            Miktar = EkleMiktar,
            ToplamTutar = toplamTutar,
            Aciklama = EkleAciklama
        });

        Mesaj = "Fallback fiyat eklendi.";
        MesajHata = false;
        await LoadListAsync();
        return Page();
    }

    public async Task<IActionResult> OnPostSilAsync(int stkId, string satinalmaSarti, int mekanId)
    {
        await using var conn = await _db.OpenAsync();

        await conn.ExecuteAsync("""
            DELETE FROM FifoFallbackFiyatlari
            WHERE StkId = @StkId AND SatinalmaSarti = @SatinalmaSarti AND MekanId = @MekanId
            """, new { StkId = stkId, SatinalmaSarti = satinalmaSarti, MekanId = mekanId });

        Mesaj = "Fallback fiyat silindi.";
        MesajHata = false;
        await LoadListAsync();
        return Page();
    }

    private async Task LoadListAsync()
    {
        await using var conn = await _db.OpenAsync();

        Fiyatlar = (await conn.QueryAsync<FallbackFiyatDto>("""
            SELECT StkId, SatinalmaSarti, MekanId, BirimMaliyet, Miktar, ToplamTutar, Aciklama, KayitTarihi
            FROM FifoFallbackFiyatlari ORDER BY StkId, MekanId
            """)).ToList();
    }
}

public class FallbackFiyatDto
{
    public int StkId { get; set; }
    public string SatinalmaSarti { get; set; } = "";
    public int MekanId { get; set; }
    public decimal BirimMaliyet { get; set; }
    public decimal Miktar { get; set; }
    public decimal ToplamTutar { get; set; }
    public string? Aciklama { get; set; }
    public DateTime KayitTarihi { get; set; }
}
