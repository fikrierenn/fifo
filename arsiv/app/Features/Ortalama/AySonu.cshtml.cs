using Dapper;
using App.Lib;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace App.Features.Ortalama;

[IgnoreAntiforgeryToken]
public class AySonuModel : PageModel
{
    private readonly Db _db;
    private readonly MaliyetLogger _logger;
    private readonly IServiceScopeFactory _scopeFactory;

    public AySonuModel(Db db, MaliyetLogger logger, IServiceScopeFactory scopeFactory)
    {
        _db = db;
        _logger = logger;
        _scopeFactory = scopeFactory;
    }

    [BindProperty]
    public int Yil { get; set; } = DateTime.Today.Year;

    [BindProperty]
    public int Ay { get; set; } = DateTime.Today.Month == 1 ? 12 : DateTime.Today.Month - 1;

    [BindProperty]
    public DateTime? AcilisTarihi { get; set; }

    [BindProperty]
    public int? StkId { get; set; }

    public void OnGet() { }

    public async Task<IActionResult> OnPostStartAsync()
    {
        if (Yil < 2020 || Yil > 2099 || Ay < 1 || Ay > 12)
        {
            return new JsonResult(new { ok = false, error = "Gecersiz yil veya ay." })
            {
                StatusCode = StatusCodes.Status400BadRequest
            };
        }

        var islemId = await _logger.BaslatAsync(
            "Ortalama Aylik Maliyet",
            aciklama: $"YilAy: {Yil}-{Ay:D2}, AcilisTarihi: {AcilisTarihi?.ToString("yyyy-MM-dd") ?? "Devir"}, StkId: {StkId?.ToString() ?? "Tumu"}",
            stkId: StkId);

        var yil = Yil;
        var ay = Ay;
        var acilisTarihi = AcilisTarihi;
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
                    EXEC sp_Ortalama_AylikHesapla
                        @Yil           = @Yil,
                        @Ay            = @Ay,
                        @AcilisTarihi  = @AcilisTarihi,
                        @StkId         = @StkId,
                        @IslemId       = @IslemId
                    """,
                    new
                    {
                        Yil = yil,
                        Ay = ay,
                        AcilisTarihi = acilisTarihi,
                        StkId = stkId,
                        IslemId = islemId
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

    public async Task<IActionResult> OnGetSonucAsync(int yil, int ay)
    {
        await using var conn = await _db.OpenAsync();
        var count = await conn.ExecuteScalarAsync<int>(
            """
            SELECT COUNT(*)
            FROM OrtalamaAylikMaliyet
            WHERE YilAy = @YilAy
            """,
            new { YilAy = yil * 100 + ay });

        return new JsonResult(new { ok = true, urunSayisi = count });
    }
}
