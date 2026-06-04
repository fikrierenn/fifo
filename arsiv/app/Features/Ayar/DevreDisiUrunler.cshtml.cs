using Dapper;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using App.Lib;

namespace App.Features.Ayar;

[IgnoreAntiforgeryToken]
public class DevreDisiUrunlerModel : PageModel
{
    private readonly Db _db;
    public DevreDisiUrunlerModel(Db db) => _db = db;

    public List<DevreDisiSatir> Urunler { get; set; } = new();
    public string? Mesaj { get; set; }
    public bool MesajHata { get; set; }

    public async Task OnGetAsync()
    {
        await LoadListAsync();
    }

    public async Task<IActionResult> OnPostEkleAsync(int ekleStkId, string? ekleSebep)
    {
        if (ekleStkId <= 0)
        {
            Mesaj = "Gecerli bir StkId girin.";
            MesajHata = true;
            await LoadListAsync();
            return Page();
        }

        var ok = await _db.DevreDisiEkleAsync(ekleStkId, ekleSebep);
        Mesaj = ok ? "Urun devre disi olarak isaretlendi." : "Islem basarisiz.";
        MesajHata = !ok;
        await LoadListAsync();
        return Page();
    }

    public async Task<IActionResult> OnPostKaldirAsync(int stkId)
    {
        var ok = await _db.DevreDisiKaldirAsync(stkId);
        Mesaj = ok ? "Urun yeniden aktif edildi." : "Islem basarisiz.";
        MesajHata = !ok;
        await LoadListAsync();
        return Page();
    }

    public async Task<IActionResult> OnPostKategoriEkleAsync(string kategori, string? sebep)
    {
        if (string.IsNullOrWhiteSpace(kategori))
        {
            Mesaj = "Kategori secin.";
            MesajHata = true;
            await LoadListAsync();
            return Page();
        }

        await using var conn = await _db.OpenAsync();
        var eklenen = await conn.ExecuteAsync("""
            INSERT INTO dbo.FifoDevreDisiUrunler (StkId, Sebep)
            SELECT u.stkID, @Sebep
            FROM DerinSISBkm.bkm.UrunBilgi u
            WHERE u.KatAna = @Kategori
              AND NOT EXISTS (SELECT 1 FROM dbo.FifoDevreDisiUrunler dd WHERE dd.StkId = u.stkID)
            """, new { Kategori = kategori, Sebep = sebep ?? $"Kategori: {kategori}" },
            commandTimeout: 120);

        Db.ResetDevreDisiCache();

        Mesaj = $"'{kategori}' kategorisinden {eklenen} urun devre disi olarak eklendi.";
        MesajHata = false;
        await LoadListAsync();
        return Page();
    }

    public async Task<IActionResult> OnPostKategoriKaldirAsync(string kategori)
    {
        if (string.IsNullOrWhiteSpace(kategori))
        {
            Mesaj = "Kategori secin.";
            MesajHata = true;
            await LoadListAsync();
            return Page();
        }

        await using var conn = await _db.OpenAsync();
        var silinen = await conn.ExecuteAsync("""
            DELETE dd FROM dbo.FifoDevreDisiUrunler dd
            INNER JOIN DerinSISBkm.bkm.UrunBilgi u ON u.stkID = dd.StkId
            WHERE u.KatAna = @Kategori
            """, new { Kategori = kategori }, commandTimeout: 120);

        Db.ResetDevreDisiCache();

        Mesaj = $"'{kategori}' kategorisinden {silinen} urun aktif edildi.";
        MesajHata = false;
        await LoadListAsync();
        return Page();
    }

    public async Task<IActionResult> OnPostKategori3EkleAsync(string kategori3, string? sebep)
    {
        if (string.IsNullOrWhiteSpace(kategori3))
        {
            Mesaj = "Kategori3 secin.";
            MesajHata = true;
            await LoadListAsync();
            return Page();
        }

        await using var conn = await _db.OpenAsync();
        var eklenen = await conn.ExecuteAsync("""
            INSERT INTO dbo.FifoDevreDisiUrunler (StkId, Sebep)
            SELECT u.stkID, @Sebep
            FROM DerinSISBkm.bkm.UrunBilgi u
            WHERE u.Kategori3 = @Kategori3
              AND NOT EXISTS (SELECT 1 FROM dbo.FifoDevreDisiUrunler dd WHERE dd.StkId = u.stkID)
            """, new { Kategori3 = kategori3, Sebep = sebep ?? $"Kategori3: {kategori3}" },
            commandTimeout: 120);

        Db.ResetDevreDisiCache();
        Mesaj = $"'{kategori3}' alt kategorisinden {eklenen} urun devre disi olarak eklendi.";
        MesajHata = false;
        await LoadListAsync();
        return Page();
    }

    public async Task<IActionResult> OnPostKategori3KaldirAsync(string kategori3)
    {
        if (string.IsNullOrWhiteSpace(kategori3))
        {
            Mesaj = "Kategori3 secin.";
            MesajHata = true;
            await LoadListAsync();
            return Page();
        }

        await using var conn = await _db.OpenAsync();
        var silinen = await conn.ExecuteAsync("""
            DELETE dd FROM dbo.FifoDevreDisiUrunler dd
            INNER JOIN DerinSISBkm.bkm.UrunBilgi u ON u.stkID = dd.StkId
            WHERE u.Kategori3 = @Kategori3
            """, new { Kategori3 = kategori3 }, commandTimeout: 120);

        Db.ResetDevreDisiCache();
        Mesaj = $"'{kategori3}' alt kategorisinden {silinen} urun aktif edildi.";
        MesajHata = false;
        await LoadListAsync();
        return Page();
    }

    private async Task LoadListAsync()
    {
        var liste = await _db.GetDevreDisiListeAsync();
        var stkIds = liste.Select(d => d.StkId).ToList();
        await _db.GetUrunlerAsync(stkIds);
        Urunler = liste.Select(d => new DevreDisiSatir
        {
            StkId = d.StkId,
            UrunAdi = Db.UrunAdi(d.StkId),
            Sebep = d.Sebep,
            EkleyenKullanici = d.EkleyenKullanici,
            EklenmeTarihi = d.EklenmeTarihi
        }).ToList();
    }
}

public class DevreDisiSatir
{
    public int StkId { get; set; }
    public string UrunAdi { get; set; } = "";
    public string? Sebep { get; set; }
    public string? EkleyenKullanici { get; set; }
    public DateTime EklenmeTarihi { get; set; }
}
