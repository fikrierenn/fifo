using Dapper;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using App.Lib;

namespace App.Features.Islem;

[IgnoreAntiforgeryToken]
public class HataliRetryModel : PageModel
{
    private readonly Db _db;
    private readonly MaliyetLogger _logger;
    private readonly IServiceScopeFactory _scopeFactory;

    public HataliRetryModel(Db db, MaliyetLogger logger, IServiceScopeFactory scopeFactory)
    {
        _db = db;
        _logger = logger;
        _scopeFactory = scopeFactory;
    }

    public List<HataliUrunDto> Hatalar { get; set; } = new();

    [BindProperty]
    public List<int> SecilenStkIds { get; set; } = new();

    public async Task OnGetAsync()
    {
        await using var conn = await _db.OpenAsync();
        Hatalar = (await conn.QueryAsync<HataliUrunDto>("""
            SELECT h.HataId, h.RunId, h.BatchNo, h.StkId, h.HataMesaji, h.HataZamani,
                   r.DonemYil, r.DonemAy
            FROM FifoBatchHata h
            JOIN FifoBatchRun r ON h.RunId = r.RunId
            ORDER BY h.HataZamani DESC
            """)).ToList();
    }

    public async Task<IActionResult> OnPostRetryAsync()
    {
        if (SecilenStkIds.Count == 0)
            return new JsonResult(new { ok = false, error = "En az bir urun seciniz." })
                { StatusCode = StatusCodes.Status400BadRequest };

        // Donem bilgisini son run'dan al
        await using var conn = await _db.OpenAsync();
        var donem = await conn.QuerySingleOrDefaultAsync<DonemDto>("""
            SELECT TOP 1 r.DonemYil, r.DonemAy
            FROM FifoBatchHata h
            JOIN FifoBatchRun r ON h.RunId = r.RunId
            WHERE h.StkId IN @StkIds
            ORDER BY h.HataZamani DESC
            """, new { StkIds = SecilenStkIds });

        if (donem is null)
            return new JsonResult(new { ok = false, error = "Donem bilgisi bulunamadi." })
                { StatusCode = StatusCodes.Status400BadRequest };

        var islemId = await _logger.BaslatAsync(
            "Hatali Urun Retry",
            aciklama: $"{SecilenStkIds.Count} urun, Donem: {donem.DonemYil}-{donem.DonemAy:D2}");

        var stkIds = SecilenStkIds.ToList();
        var yil = donem.DonemYil;
        var ay = donem.DonemAy;

        _ = Task.Run(async () =>
        {
            await using var scope = _scopeFactory.CreateAsyncScope();
            var db = scope.ServiceProvider.GetRequiredService<Db>();
            var logger = scope.ServiceProvider.GetRequiredService<MaliyetLogger>();

            try
            {
                await using var retryConn = await db.OpenAsync();

                int basarili = 0, hatali = 0;

                await logger.AdimYazAsync(islemId, "retry_baslat", "Retry Baslat", 1, "CALISIYOR",
                    $"{stkIds.Count} urun isleniyor.");

                foreach (var stkId in stkIds)
                {
                    try
                    {
                        await retryConn.ExecuteAsync(
                            "EXEC sp_Fifo_AylikCalistir @Yil, @Ay, @StkId",
                            new { Yil = yil, Ay = ay, StkId = stkId },
                            commandTimeout: 600);
                        basarili++;
                    }
                    catch
                    {
                        hatali++;
                    }
                }

                var durum = hatali > 0 ? "KISMEN_HATA" : "TAMAMLANDI";
                await logger.AdimYazAsync(islemId, "retry_baslat", "Retry Baslat", 1, "TAMAMLANDI",
                    $"{basarili} basarili, {hatali} hatali.");
                await logger.BitirAsync(islemId, durum,
                    $"{basarili} basarili, {hatali} hatali ({stkIds.Count} toplam).");
            }
            catch (Exception ex)
            {
                var mesaj = ex.Message.Length > 500 ? ex.Message[..500] : ex.Message;
                await logger.BitirAsync(islemId, "HATA", mesaj);
            }
        });

        return new JsonResult(new { ok = true, islemId, toplam = stkIds.Count });
    }

    public async Task<IActionResult> OnGetDurumAsync(Guid islemId)
    {
        var durum = await _logger.DurumOkuAsync(islemId);
        if (durum is null)
            return new JsonResult(new { ok = false, error = "Islem bulunamadi." })
                { StatusCode = StatusCodes.Status404NotFound };

        return new JsonResult(new
        {
            ok = true,
            durum = durum.Durum,
            baslangic = durum.Baslangic,
            bitis = durum.Bitis,
            aciklama = durum.Aciklama,
            adimlar = durum.Adimlar.Select(a => new
            {
                adimKodu = a.AdimKodu,
                adimAdi = a.AdimAdi,
                durum = a.Durum,
                mesaj = a.Mesaj
            })
        });
    }
}

public class HataliUrunDto
{
    public long HataId { get; set; }
    public Guid RunId { get; set; }
    public int BatchNo { get; set; }
    public int StkId { get; set; }
    public string HataMesaji { get; set; } = "";
    public DateTime HataZamani { get; set; }
    public int DonemYil { get; set; }
    public int DonemAy { get; set; }
}

public class DonemDto
{
    public int DonemYil { get; set; }
    public int DonemAy { get; set; }
}
