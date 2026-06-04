using Dapper;
using App.Lib;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace App.Features.Rapor;

public class HareketliUrunlerModel : PageModel
{
    private readonly Db _db;

    public HareketliUrunlerModel(Db db) => _db = db;

    [BindProperty(SupportsGet = true)]
    public int Yil { get; set; }

    [BindProperty(SupportsGet = true)]
    public int Ay { get; set; }

    public int PageSize { get; set; } = 50;
    public bool HasMore { get; set; }
    public List<HareketliUrunSatir> Urunler { get; set; } = new();
    public bool Sorgulandimi { get; set; }
    public int ToplamUrunSayisi { get; set; }

    /// <summary>SP sonucu cache (ayni ay icin tekrar SP cagirmamak icin)</summary>
    private static List<int>? _cachedStkIds;
    private static int _cachedYil, _cachedAy;
    private static readonly SemaphoreSlim _spLock = new(1, 1);

    private async Task<List<int>> GetHareketliUrunlerAsync(System.Data.Common.DbConnection conn, int yil, int ay)
    {
        await _spLock.WaitAsync();
        try
        {
            if (_cachedStkIds != null && _cachedYil == yil && _cachedAy == ay)
                return _cachedStkIds;

            var ids = (await conn.QueryAsync<int>(
                "EXEC sp_Fifo_HareketliUrunListesi @Yil = @Yil, @Ay = @Ay",
                new { Yil = yil, Ay = ay }, commandTimeout: 120)).ToList();

            _cachedStkIds = ids;
            _cachedYil = yil;
            _cachedAy = ay;
            return ids;
        }
        finally { _spLock.Release(); }
    }

    public async Task OnGetAsync()
    {
        if (Yil == 0 || Ay == 0)
        {
            var oncekiAy = DateTime.Today.AddMonths(-1);
            Yil = oncekiAy.Year;
            Ay = oncekiAy.Month;
            return;
        }

        Sorgulandimi = true;
        await using var conn = await _db.OpenAsync();

        var stkIds = await GetHareketliUrunlerAsync(conn, Yil, Ay);
        ToplamUrunSayisi = stkIds.Count;
        if (stkIds.Count == 0) return;

        // Sadece ilk sayfa icin katman ozeti — 50 urun
        var pageStkIds = stkIds.Take(PageSize + 1).ToList();

        var katmanOzet = (await conn.QueryAsync<HareketliUrunSatir>("""
            SELECT StkId, COUNT(KatmanId) AS KatmanSayisi, SUM(KalanMiktar) AS KalanMiktar
            FROM FifoKatman
            WHERE KalanMiktar > 0 AND StkId IN @Ids
            GROUP BY StkId
            """, new { Ids = pageStkIds })).ToDictionary(k => k.StkId);

        var pageUrunler = pageStkIds.Select(id =>
        {
            katmanOzet.TryGetValue(id, out var ozet);
            return new HareketliUrunSatir
            {
                StkId = id,
                KatmanSayisi = ozet?.KatmanSayisi ?? 0,
                KalanMiktar = ozet?.KalanMiktar ?? 0
            };
        }).ToList();

        HasMore = pageUrunler.Count > PageSize;
        Urunler = pageUrunler.Take(PageSize).ToList();

        await _db.GetUrunlerAsync(Urunler.Select(s => s.StkId));
    }

    public async Task<IActionResult> OnGetMoreAsync(int offset)
    {
        if (Yil == 0 || Ay == 0)
            return new JsonResult(new { rows = Array.Empty<object>(), hasMore = false });

        await using var conn = await _db.OpenAsync();

        var stkIds = await GetHareketliUrunlerAsync(conn, Yil, Ay);
        if (stkIds.Count == 0)
            return new JsonResult(new { rows = Array.Empty<object>(), hasMore = false });

        // Sadece bu sayfa icin StkId'ler
        var pageStkIds = stkIds.Skip(offset).Take(PageSize + 1).ToList();

        var katmanOzet = (await conn.QueryAsync<HareketliUrunSatir>("""
            SELECT StkId, COUNT(KatmanId) AS KatmanSayisi, SUM(KalanMiktar) AS KalanMiktar
            FROM FifoKatman
            WHERE KalanMiktar > 0 AND StkId IN @Ids
            GROUP BY StkId
            """, new { Ids = pageStkIds })).ToDictionary(k => k.StkId);

        var allUrunler = pageStkIds.Select(id =>
        {
            katmanOzet.TryGetValue(id, out var ozet);
            return new HareketliUrunSatir
            {
                StkId = id,
                KatmanSayisi = ozet?.KatmanSayisi ?? 0,
                KalanMiktar = ozet?.KalanMiktar ?? 0
            };
        }).ToList();

        var page = allUrunler.Skip(offset).Take(PageSize + 1).ToList();
        var hasMore = page.Count > PageSize;
        var data = page.Take(PageSize).ToList();

        await _db.GetUrunlerAsync(data.Select(s => s.StkId));

        return new JsonResult(new
        {
            rows = data.Select(s => new
            {
                s.StkId,
                urunAdi = Db.UrunAdi(s.StkId),
                s.KatmanSayisi,
                kalanMiktar = s.KalanMiktar.ToString("N4"),
                devreDisi = Db.DevreDisiMi(s.StkId)
            }),
            hasMore
        });
    }

    public async Task<IActionResult> OnGetCsvAsync()
    {
        if (Yil == 0 || Ay == 0)
            return BadRequest("Yil ve Ay zorunlu.");

        await using var conn = await _db.OpenAsync();
        var stkIds = await GetHareketliUrunlerAsync(conn, Yil, Ay);

        var katmanOzet = new Dictionary<int, HareketliUrunSatir>();
        if (stkIds.Count > 0)
        {
            // CSV icin tum urunlerin katman ozetini batch'lerle al
            foreach (var batch in stkIds.Chunk(1000))
            {
                var batchResult = await conn.QueryAsync<HareketliUrunSatir>("""
                    SELECT StkId, COUNT(KatmanId) AS KatmanSayisi, SUM(KalanMiktar) AS KalanMiktar
                    FROM FifoKatman
                    WHERE KalanMiktar > 0 AND StkId IN @Ids
                    GROUP BY StkId
                    """, new { Ids = batch });
                foreach (var r in batchResult) katmanOzet[r.StkId] = r;
            }
        }

        var sb = new System.Text.StringBuilder();
        sb.AppendLine("StkId;KatmanSayisi;KalanMiktar");
        foreach (var id in stkIds)
        {
            katmanOzet.TryGetValue(id, out var ozet);
            sb.AppendLine($"{id};{ozet?.KatmanSayisi ?? 0};{ozet?.KalanMiktar ?? 0:F4}");
        }

        return File(System.Text.Encoding.UTF8.GetBytes(sb.ToString()),
            "text/csv", $"HareketliUrunler_{Yil}_{Ay:D2}.csv");
    }
}

public class HareketliUrunSatir
{
    public int StkId { get; set; }
    public int KatmanSayisi { get; set; }
    public decimal KalanMiktar { get; set; }
}
