using Dapper;
using App.Lib;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace App.Features.Snapshot;

[IgnoreAntiforgeryToken]
public class CreateModel : PageModel
{
    private readonly Db _db;
    private readonly MaliyetLogger _logger;
    private readonly IServiceScopeFactory _scopeFactory;

    public CreateModel(Db db, MaliyetLogger logger, IServiceScopeFactory scopeFactory)
    {
        _db = db;
        _logger = logger;
        _scopeFactory = scopeFactory;
    }

    [BindProperty]
    public DateTime EnvanterTarihi { get; set; } = new(2025, 12, 31);

    [BindProperty]
    public int? StkId { get; set; }

    // Mevcut snapshot ozeti (GET icin)
    public List<SnapshotOzet> MevcutSnapshotlar { get; set; } = new();

    public async Task OnGetAsync()
    {
        await using var conn = await _db.OpenAsync();
        MevcutSnapshotlar = (await conn.QueryAsync<SnapshotOzet>("""
            SELECT EnvanterTarihi, COUNT(DISTINCT StkId) AS UrunSayisi,
                   COUNT(DISTINCT MekanId) AS MekanSayisi,
                   SUM(StokMiktar) AS ToplamMiktar,
                   MIN(KayitTarihi) AS IlkKayit
            FROM FifoAcilisEnvanter
            GROUP BY EnvanterTarihi
            ORDER BY EnvanterTarihi DESC
            """)).ToList();
    }

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
            "Envanter Snapshot",
            aciklama: $"Tarih: {EnvanterTarihi:yyyy-MM-dd}, StkId: {StkId?.ToString() ?? "Tumu"}",
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
                await logger.AdimYazAsync(islemId, "snapshot_temizle", "Eski snapshot temizle", 1, "CALISIYOR");

                await using var conn = await db.OpenAsync();

                // 1. Eski snapshot'i temizle (ayni tarih + StkId icin)
                if (stkId.HasValue)
                {
                    await conn.ExecuteAsync("""
                        DELETE FROM FifoAcilisEnvanter
                        WHERE EnvanterTarihi = @EnvanterTarihi AND StkId = @StkId
                        """, new { EnvanterTarihi = envTarihi, StkId = stkId });
                }
                else
                {
                    await conn.ExecuteAsync("""
                        DELETE FROM FifoAcilisEnvanter
                        WHERE EnvanterTarihi = @EnvanterTarihi
                        """, new { EnvanterTarihi = envTarihi });
                }

                await logger.AdimYazAsync(islemId, "snapshot_temizle", "Eski snapshot temizle", 1, "TAMAMLANDI");

                // 2. ERP'den stok miktarlarini cek ve FifoAcilisEnvanter'e yaz
                await logger.AdimYazAsync(islemId, "snapshot_cek", "ERP stok snapshot cek", 2, "CALISIYOR");

                var satirSayisi = await conn.ExecuteAsync("""
                    INSERT INTO FifoAcilisEnvanter (EnvanterTarihi, MekanId, StkId, StokMiktar)
                    SELECT
                        @EnvanterTarihi AS EnvanterTarihi,
                        h.ehMekan AS MekanId,
                        h.ehstkID AS StkId,
                        SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) AS StokMiktar
                    FROM DerinSISBkm.dbo.irsHrk h
                    WHERE h.ehMekan IN (1, 12, 4477, 4478)
                      AND h.ehTrhS <= CONVERT(smalldatetime, @EnvanterTarihi)
                      AND (@StkId IS NULL OR h.ehstkID = @StkId)
                    GROUP BY h.ehMekan, h.ehstkID
                    HAVING SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) > 0
                    """,
                    new { EnvanterTarihi = envTarihi, StkId = stkId },
                    commandTimeout: 600);

                await logger.AdimYazAsync(islemId, "snapshot_cek", "ERP stok snapshot cek", 2, "TAMAMLANDI",
                    $"{satirSayisi} mekan-urun kombinasyonu yazildi.");

                await logger.BitirAsync(islemId, "TAMAMLANDI",
                    $"{satirSayisi} kayit olusturuldu.");
            }
            catch (Exception ex)
            {
                var mesaj = ex.Message.Length > 500 ? ex.Message[..500] : ex.Message;
                await logger.AdimYazAsync(islemId, "snapshot_hata", "Hata", 99, "HATA", mesaj);
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
                mesaj = a.Mesaj
            })
        });
    }
}

public class SnapshotOzet
{
    public DateTime EnvanterTarihi { get; set; }
    public int UrunSayisi { get; set; }
    public int MekanSayisi { get; set; }
    public decimal ToplamMiktar { get; set; }
    public DateTime IlkKayit { get; set; }
}
