using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Dapper;
using App.Lib;

namespace App.Features.Islem;

public class RunHistoryModel : PageModel
{
    private readonly Db _db;
    public RunHistoryModel(Db db) => _db = db;

    [BindProperty(SupportsGet = true)]
    public Guid? RunId { get; set; }

    public List<RunSatir> Runlar { get; set; } = new();
    public RunSatir? SeciliRun { get; set; }
    public List<BatchSatir> Batchler { get; set; } = new();
    public List<HataSatir> Hatalar { get; set; } = new();

    public async Task OnGetAsync()
    {
        await using var conn = await _db.OpenAsync();

        if (RunId.HasValue)
        {
            SeciliRun = await conn.QuerySingleOrDefaultAsync<RunSatir>("""
                SELECT RunId, DonemYil, DonemAy, RunBaslangic, RunBitis,
                       ToplamUrun, ToplamBatch, TamamlananBatch, BatchBoyutu,
                       Durum, HataMesaji,
                       DATEDIFF(SECOND, RunBaslangic, ISNULL(RunBitis, GETUTCDATE())) AS SureSn
                FROM FifoBatchRun
                WHERE RunId = @RunId
                """, new { RunId });

            if (SeciliRun != null)
            {
                Batchler = (await conn.QueryAsync<BatchSatir>("""
                    SELECT DetayId, BatchNo, UrunSayisi, BaslangicZamani, BitisZamani,
                           Durum, BasariliUrun, HataliUrun,
                           DATEDIFF(SECOND, BaslangicZamani, ISNULL(BitisZamani, GETUTCDATE())) AS SureSn
                    FROM FifoBatchDetay
                    WHERE RunId = @RunId
                    ORDER BY BatchNo
                    """, new { RunId })).AsList();

                Hatalar = (await conn.QueryAsync<HataSatir>("""
                    SELECT HataId, BatchNo, StkId, HataMesaji, HataZamani
                    FROM FifoBatchHata
                    WHERE RunId = @RunId
                    ORDER BY HataZamani DESC
                    """, new { RunId })).AsList();

                if (Hatalar.Count > 0)
                    await _db.GetUrunlerAsync(Hatalar.Select(h => h.StkId).Distinct());
            }
        }
        else
        {
            Runlar = (await conn.QueryAsync<RunSatir>("""
                SELECT RunId, DonemYil, DonemAy, RunBaslangic, RunBitis,
                       ToplamUrun, ToplamBatch, TamamlananBatch, BatchBoyutu,
                       Durum, HataMesaji,
                       DATEDIFF(SECOND, RunBaslangic, ISNULL(RunBitis, GETUTCDATE())) AS SureSn
                FROM FifoBatchRun
                ORDER BY RunBaslangic DESC
                """)).AsList();
        }
    }

    public async Task<IActionResult> OnGetExportAsync()
    {
        await using var conn = await _db.OpenAsync();
        var rows = await conn.QueryAsync<RunSatir>("""
            SELECT RunId, DonemYil, DonemAy, RunBaslangic, RunBitis,
                   ToplamUrun, ToplamBatch, TamamlananBatch, Durum,
                   DATEDIFF(SECOND, RunBaslangic, ISNULL(RunBitis, GETUTCDATE())) AS SureSn
            FROM FifoBatchRun
            ORDER BY RunBaslangic DESC
            """);
        var csv = CsvExporter.ToCsv(rows);
        return File(csv, "text/csv", $"RunHistory_{DateTime.Now:yyyyMMdd}.csv");
    }
}

public class RunSatir
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
    public int SureSn { get; set; }

    public string SureStr => SureSn < 60 ? $"{SureSn}sn"
        : SureSn < 3600 ? $"{SureSn / 60}dk {SureSn % 60}sn"
        : $"{SureSn / 3600}sa {(SureSn % 3600) / 60}dk";

    public string DonemStr => $"{DonemYil}-{DonemAy:D2}";
}

public class BatchSatir
{
    public int DetayId { get; set; }
    public int BatchNo { get; set; }
    public int UrunSayisi { get; set; }
    public DateTime BaslangicZamani { get; set; }
    public DateTime? BitisZamani { get; set; }
    public string Durum { get; set; } = "";
    public int? BasariliUrun { get; set; }
    public int? HataliUrun { get; set; }
    public int SureSn { get; set; }

    public string SureStr => SureSn < 60 ? $"{SureSn}sn"
        : $"{SureSn / 60}dk {SureSn % 60}sn";
}

public class HataSatir
{
    public int HataId { get; set; }
    public int BatchNo { get; set; }
    public int StkId { get; set; }
    public string HataMesaji { get; set; } = "";
    public DateTime HataZamani { get; set; }
}
