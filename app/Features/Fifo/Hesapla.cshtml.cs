using Dapper;
using App.Lib;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace App.Features.Fifo;

[IgnoreAntiforgeryToken]
public class HesaplaModel : PageModel
{
    private readonly Db _db;
    private readonly MaliyetLogger _logger;
    private readonly IServiceScopeFactory _scopeFactory;

    public HesaplaModel(Db db, MaliyetLogger logger, IServiceScopeFactory scopeFactory)
    {
        _db = db;
        _logger = logger;
        _scopeFactory = scopeFactory;
    }

    [BindProperty]
    public int Yil { get; set; }

    [BindProperty]
    public int Ay { get; set; }

    [BindProperty]
    public int? StkId { get; set; }

    [BindProperty]
    public bool SentetikAktif { get; set; }

    public void OnGet()
    {
        var oncekiAy = DateTime.Today.AddMonths(-1);
        Yil = oncekiAy.Year;
        Ay = oncekiAy.Month;
    }

    public async Task<IActionResult> OnPostStartAsync()
    {
        if (Yil < 2020 || Yil > 2099)
        {
            return new JsonResult(new { ok = false, error = "Yil 2020-2099 araliginda olmali." })
            {
                StatusCode = StatusCodes.Status400BadRequest
            };
        }

        if (Ay < 1 || Ay > 12)
        {
            return new JsonResult(new { ok = false, error = "Ay 1-12 araliginda olmali." })
            {
                StatusCode = StatusCodes.Status400BadRequest
            };
        }

        var islemId = await _logger.BaslatAsync(
            "Aylik FIFO Hesaplama",
            aciklama: $"Yil: {Yil}, Ay: {Ay}, StkId: {StkId?.ToString() ?? "Tumu"}, Sentetik: {(SentetikAktif ? "Evet" : "Hayir")}",
            stkId: StkId);

        var yil = Yil;
        var ay = Ay;
        var stkId = StkId;
        var sentetikAktif = SentetikAktif;
        _ = Task.Run(async () =>
        {
            await using var scope = _scopeFactory.CreateAsyncScope();
            var db = scope.ServiceProvider.GetRequiredService<Db>();
            var logger = scope.ServiceProvider.GetRequiredService<MaliyetLogger>();
            try
            {
                await using var conn = await db.OpenAsync();
                await conn.ExecuteAsync(
                    """
                    EXEC sp_Fifo_AylikRutinFull
                        @Yil                       = @Yil,
                        @Ay                        = @Ay,
                        @StkId                     = @StkId,
                        @IslemId                   = @IslemId,
                        @SentetikSatinalmaSarti    = @SentetikSatinalmaSarti,
                        @SabitFallbackBirimMaliyet = @SabitFallbackBirimMaliyet,
                        @SentetikAktif             = @SentetikAktif
                    """,
                    new
                    {
                        Yil = yil,
                        Ay = ay,
                        StkId = stkId,
                        IslemId = islemId,
                        SentetikSatinalmaSarti = "SatinAlma",
                        SabitFallbackBirimMaliyet = (decimal?)null,
                        SentetikAktif = sentetikAktif
                    },
                    commandTimeout: 1800);

                await logger.BitirAsync(islemId, "TAMAMLANDI");
            }
            catch (Exception ex)
            {
                var mesaj = ex.Message.Length > 500 ? ex.Message[..500] : ex.Message;
                await logger.BitirAsync(islemId, "HATA", mesaj);
            }
        });

        return new JsonResult(new { ok = true, islemId });
    }

    public async Task<IActionResult> OnGetDurumAsync(Guid islemId)
    {
        var durum = await _logger.DurumOkuAsync(islemId);
        if (durum is null)
        {
            return new JsonResult(new { ok = false, error = "Islem bulunamadi." })
            {
                StatusCode = StatusCodes.Status404NotFound
            };
        }

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
                mesaj = a.Mesaj,
                baslangic = a.Baslangic,
                bitis = a.Bitis
            })
        });
    }
}
