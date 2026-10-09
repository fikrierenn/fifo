using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Dapper;
using App.Lib;

namespace App.Features.Rapor;

public class KatmanDetayModel : PageModel
{
    private readonly Db _db;
    public KatmanDetayModel(Db db) => _db = db;

    [BindProperty(SupportsGet = true)] public long KatmanId { get; set; }

    public KatmanBilgiDto? Katman { get; set; }
    public List<KatmanCikisDto> Cikislar { get; set; } = new();
    public decimal ToplamTuketilen { get; set; }
    public decimal TuketimYuzdesi { get; set; }

    public async Task OnGetAsync()
    {
        if (KatmanId <= 0) return;

        await using var conn = await _db.OpenAsync();

        // a) Katman bilgisi
        Katman = await conn.QuerySingleOrDefaultAsync<KatmanBilgiDto>("""
            SELECT KatmanId, StkId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi,
                   FirmaId, GirisMiktar, KalanMiktar, BirimMaliyet, Durum, KayitTarihi
            FROM FifoKatman WHERE KatmanId = @KatmanId
            """, new { KatmanId });

        if (Katman is null) return;

        await _db.GetUrunlerAsync(new[] { Katman.StkId });

        // b) Cikislar
        Cikislar = (await conn.QueryAsync<KatmanCikisDto>("""
            SELECT CikisId, StkId, HareketTarihi, HareketTipi, MekanId, BelgeNo,
                   Miktar, BirimMaliyet, CikisTutar, KayitTarihi
            FROM FifoCikisDetay WHERE KatmanId = @KatmanId
            ORDER BY HareketTarihi, CikisId
            """, new { KatmanId })).ToList();

        // Ozet
        ToplamTuketilen = Cikislar.Sum(c => c.Miktar);
        TuketimYuzdesi = Katman.GirisMiktar > 0
            ? (Katman.GirisMiktar - Katman.KalanMiktar) / Katman.GirisMiktar * 100
            : 0;
    }
}

public class KatmanBilgiDto
{
    public long KatmanId { get; set; }
    public int StkId { get; set; }
    public DateTime GirisTarihi { get; set; }
    public string KaynakTip { get; set; } = "";
    public string? BelgeNo { get; set; }
    public DateTime? BelgeTarihi { get; set; }
    public int? FirmaId { get; set; }
    public decimal GirisMiktar { get; set; }
    public decimal KalanMiktar { get; set; }
    public decimal BirimMaliyet { get; set; }
    public string Durum { get; set; } = "";
    public DateTime KayitTarihi { get; set; }
}

public class KatmanCikisDto
{
    public long CikisId { get; set; }
    public int StkId { get; set; }
    public DateTime HareketTarihi { get; set; }
    public string HareketTipi { get; set; } = "";
    public int MekanId { get; set; }
    public string? BelgeNo { get; set; }
    public decimal Miktar { get; set; }
    public decimal BirimMaliyet { get; set; }
    public decimal CikisTutar { get; set; }
    public DateTime KayitTarihi { get; set; }
}
