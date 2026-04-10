using Dapper;
using App.Lib;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace App.Features.Fifo;

[IgnoreAntiforgeryToken]
public class AcilisModel : PageModel
{
    private readonly Db _db;
    private readonly MaliyetLogger _logger;
    private readonly IServiceScopeFactory _scopeFactory;

    public AcilisModel(Db db, MaliyetLogger logger, IServiceScopeFactory scopeFactory)
    {
        _db = db;
        _logger = logger;
        _scopeFactory = scopeFactory;
    }

    [BindProperty]
    public DateTime EnvanterTarihi { get; set; } = new(2025, 12, 31);

    [BindProperty]
    public int? StkId { get; set; }

    public string? Mesaj { get; set; }
    public Guid? AktifIslemId { get; set; }

    public void OnGet() { }

    public async Task<IActionResult> OnPostStartAsync()
    {
        if (EnvanterTarihi == default)
        {
            return new JsonResult(new { ok = false, error = "Envanter tarihi zorunludur." })
            {
                StatusCode = StatusCodes.Status400BadRequest
            };
        }

        var islemId = await _logger.BaslatAsync(
            "Acilis Maliyetlendirme",
            aciklama: $"Envanter: {EnvanterTarihi:yyyy-MM-dd}, StkId: {StkId?.ToString() ?? "Tumu"}",
            envanterTarihi: DateOnly.FromDateTime(EnvanterTarihi),
            stkId: StkId);

        var envTarihi = EnvanterTarihi;
        var stkId = StkId;
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
                    EXEC bkm.sp_fifo_StokMaliyetAcilis_V2
                        @envanterTarihi  = @EnvanterTarihi,
                        @stkID           = @StkId,
                        @calistirmaId    = @CalistirmaId
                    """,
                    new
                    {
                        EnvanterTarihi = envTarihi,
                        StkId = stkId,
                        CalistirmaId = islemId
                    },
                    commandTimeout: 600);

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
