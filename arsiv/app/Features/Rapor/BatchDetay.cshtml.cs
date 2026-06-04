using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Dapper;
using App.Lib;

namespace App.Features.Rapor;

public class BatchDetayModel : PageModel
{
    private readonly Db _db;
    public BatchDetayModel(Db db) => _db = db;

    [BindProperty(SupportsGet = true)] public Guid? RunId { get; set; }

    public List<BatchRunDto> Runs { get; set; } = new();
    public BatchRunDto? Run { get; set; }
    public List<BatchDetayDto> Detaylar { get; set; } = new();
    public List<BatchHataDto> Hatalar { get; set; } = new();

    public async Task OnGetAsync()
    {
        await using var conn = await _db.OpenAsync();

        if (RunId is null)
        {
            Runs = (await conn.QueryAsync<BatchRunDto>("""
                SELECT TOP 50 RunId, DonemYil, DonemAy, RunBaslangic, RunBitis,
                       ToplamUrun, ToplamBatch, TamamlananBatch, BatchBoyutu, Durum, HataMesaji
                FROM FifoBatchRun ORDER BY RunBaslangic DESC
                """)).ToList();
            return;
        }

        Run = await conn.QuerySingleOrDefaultAsync<BatchRunDto>("""
            SELECT RunId, DonemYil, DonemAy, RunBaslangic, RunBitis,
                   ToplamUrun, ToplamBatch, TamamlananBatch, BatchBoyutu, Durum, HataMesaji
            FROM FifoBatchRun WHERE RunId = @RunId
            """, new { RunId });

        if (Run is null) return;

        Detaylar = (await conn.QueryAsync<BatchDetayDto>("""
            SELECT DetayId, BatchNo, UrunSayisi, BaslangicZamani, BitisZamani,
                   Durum, BasariliUrun, HataliUrun
            FROM FifoBatchDetay WHERE RunId = @RunId ORDER BY BatchNo
            """, new { RunId })).ToList();

        Hatalar = (await conn.QueryAsync<BatchHataDto>("""
            SELECT HataId, BatchNo, StkId, HataMesaji, HataZamani
            FROM FifoBatchHata WHERE RunId = @RunId ORDER BY HataZamani DESC
            """, new { RunId })).ToList();

        await _db.GetUrunlerAsync(Hatalar.Select(h => h.StkId).Distinct());
    }
}

public class BatchRunDto
{
    public Guid RunId { get; set; }
    public int DonemYil { get; set; }
    public int DonemAy { get; set; }
    public DateTime RunBaslangic { get; set; }
    public DateTime? RunBitis { get; set; }
    public int ToplamUrun { get; set; }
    public int ToplamBatch { get; set; }
    public int TamamlananBatch { get; set; }
    public int BatchBoyutu { get; set; }
    public string Durum { get; set; } = "";
    public string? HataMesaji { get; set; }
}

public class BatchDetayDto
{
    public long DetayId { get; set; }
    public int BatchNo { get; set; }
    public int UrunSayisi { get; set; }
    public DateTime BaslangicZamani { get; set; }
    public DateTime? BitisZamani { get; set; }
    public string Durum { get; set; } = "";
    public int BasariliUrun { get; set; }
    public int HataliUrun { get; set; }
}

public class BatchHataDto
{
    public long HataId { get; set; }
    public int BatchNo { get; set; }
    public int StkId { get; set; }
    public string HataMesaji { get; set; } = "";
    public DateTime HataZamani { get; set; }
}
