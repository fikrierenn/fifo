using Dapper;
using App.Lib;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace App.Features.Fifo;

[IgnoreAntiforgeryToken]
public class WizardModel : PageModel
{
    private readonly Db _db;
    private readonly MaliyetLogger _logger;
    private readonly IServiceScopeFactory _scopeFactory;

    public WizardModel(Db db, MaliyetLogger logger, IServiceScopeFactory scopeFactory)
    {
        _db = db;
        _logger = logger;
        _scopeFactory = scopeFactory;
    }

    [BindProperty]
    public DateTime EnvanterTarihi { get; set; } = new(2025, 12, 31);

    [BindProperty]
    public int Yil { get; set; }

    [BindProperty]
    public int Ay { get; set; }

    public void OnGet()
    {
        var oncekiAy = DateTime.Today.AddMonths(-1);
        Yil = oncekiAy.Year;
        Ay = oncekiAy.Month;
    }

    // ── Adim 1: Snapshot ──────────────────────────────────────────────

    public async Task<IActionResult> OnPostSnapshotAsync()
    {
        if (EnvanterTarihi == default)
            return new JsonResult(new { ok = false, error = "Envanter tarihi zorunludur." })
                { StatusCode = StatusCodes.Status400BadRequest };

        var islemId = await _logger.BaslatAsync(
            "Wizard — Snapshot",
            aciklama: $"Tarih: {EnvanterTarihi:yyyy-MM-dd}",
            envanterTarihi: DateOnly.FromDateTime(EnvanterTarihi));

        var envTarihi = EnvanterTarihi;
        _ = Task.Run(async () =>
        {
            await using var scope = _scopeFactory.CreateAsyncScope();
            var db = scope.ServiceProvider.GetRequiredService<Db>();
            var logger = scope.ServiceProvider.GetRequiredService<MaliyetLogger>();
            try
            {
                await using var conn = await db.OpenAsync();

                // Snapshot zaten varsa skip et
                var mevcutSayisi = await conn.ExecuteScalarAsync<int>("""
                    SELECT COUNT(*) FROM FifoAcilisEnvanter
                    WHERE EnvanterTarihi = @EnvanterTarihi
                    """, new { EnvanterTarihi = envTarihi });

                if (mevcutSayisi > 0)
                {
                    await logger.AdimYazAsync(islemId, "snapshot_temizle", "Snapshot zaten mevcut", 1, "ATLANDI",
                        $"{mevcutSayisi} kayit mevcut, tekrar cekilmedi.");
                    await logger.AdimYazAsync(islemId, "snapshot_cek", "Snapshot zaten mevcut", 2, "ATLANDI");
                    await logger.BitirAsync(islemId, "TAMAMLANDI", $"Snapshot zaten mevcut ({mevcutSayisi} kayit).");
                    return;
                }

                await logger.AdimYazAsync(islemId, "snapshot_temizle", "Eski snapshot temizle", 1, "CALISIYOR");

                await conn.ExecuteAsync("""
                    DELETE FROM FifoAcilisEnvanter
                    WHERE EnvanterTarihi = @EnvanterTarihi
                    """, new { EnvanterTarihi = envTarihi },
                    commandTimeout: 120);

                await logger.AdimYazAsync(islemId, "snapshot_temizle", "Eski snapshot temizle", 1, "TAMAMLANDI");

                // Mekan bazli parca parca snapshot — sistemi kilitlememek icin
                int[] mekanlar = [1, 12, 4477, 4478];
                string[] mekanAdlari = ["FSM Mgz", "Merkez Depo", "OZLUCE Mgz", "IST YOLU Mgz"];
                var toplamSatir = 0;

                for (var i = 0; i < mekanlar.Length; i++)
                {
                    // Iptal kontrolu — her mekan oncesi
                    if (await logger.IptalMiAsync(islemId))
                    {
                        await logger.BitirAsync(islemId, "IPTAL", $"Kullanici tarafindan iptal edildi. {toplamSatir} kayit yazilmisti.");
                        return;
                    }

                    var mekanId = mekanlar[i];
                    var adimKodu = $"snapshot_mekan_{mekanId}";
                    var adimAdi = $"Mekan {mekanAdlari[i]} ({mekanId})";

                    await logger.AdimYazAsync(islemId, adimKodu, adimAdi, i + 2, "CALISIYOR");

                    var satirSayisi = await conn.ExecuteAsync("""
                        INSERT INTO FifoAcilisEnvanter (EnvanterTarihi, MekanId, StkId, StokMiktar)
                        SELECT
                            @EnvanterTarihi AS EnvanterTarihi,
                            h.ehMekan AS MekanId,
                            h.ehstkID AS StkId,
                            SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) AS StokMiktar
                        FROM DerinSISBkm.dbo.irsHrk h
                        WHERE h.ehMekan = @MekanId
                          AND h.ehTrhS <= CONVERT(smalldatetime, @EnvanterTarihi)
                        GROUP BY h.ehMekan, h.ehstkID
                        HAVING SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) > 0
                        """,
                        new { EnvanterTarihi = envTarihi, MekanId = mekanId },
                        commandTimeout: 300);

                    toplamSatir += satirSayisi;
                    await logger.AdimYazAsync(islemId, adimKodu, adimAdi, i + 2, "TAMAMLANDI",
                        $"{satirSayisi} urun yazildi.");
                }

                await logger.BitirAsync(islemId, "TAMAMLANDI", $"{toplamSatir} kayit, {mekanlar.Length} mekan.");
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

    public async Task<IActionResult> OnGetSnapshotDurumAsync(Guid islemId)
    {
        return await DurumJsonAsync(islemId);
    }

    // ── Adim 2: Acilis Maliyetlendirme ────────────────────────────────

    public async Task<IActionResult> OnPostAcilisAsync()
    {
        if (EnvanterTarihi == default)
            return new JsonResult(new { ok = false, error = "Envanter tarihi zorunludur." })
                { StatusCode = StatusCodes.Status400BadRequest };

        var islemId = await _logger.BaslatAsync(
            "Wizard — Acilis",
            aciklama: $"Envanter: {EnvanterTarihi:yyyy-MM-dd}",
            envanterTarihi: DateOnly.FromDateTime(EnvanterTarihi));

        var envTarihi = EnvanterTarihi;
        _ = Task.Run(async () =>
        {
            await using var scope = _scopeFactory.CreateAsyncScope();
            var db = scope.ServiceProvider.GetRequiredService<Db>();
            var logger = scope.ServiceProvider.GetRequiredService<MaliyetLogger>();
            try
            {
                await using var conn = await db.OpenAsync();

                // V2 SP tek seferde tum urunleri isler (~2.5 dk)
                // SP kendi adimlarini yazar: envanter_v2, alis_v2, katman_v2, tamamla_v2, aylik_devir_v2, sorun_v2
                await conn.ExecuteAsync(
                    """
                    EXEC dbo.sp_Fifo_AcilisCalistir_V2
                        @EnvanterTarihi  = @EnvanterTarihi,
                        @StkId           = NULL,
                        @IslemId         = @CalistirmaId
                    """,
                    new
                    {
                        EnvanterTarihi = envTarihi,
                        CalistirmaId = islemId
                    },
                    commandTimeout: 600);

                // Devre disi urunlerin acilis katmanlarini temizle
                var devreDisiSilinen = await conn.ExecuteAsync("""
                    DELETE k FROM dbo.FifoKatman k
                    INNER JOIN dbo.FifoDevreDisiUrunler dd ON dd.StkId = k.StkId
                    WHERE k.KaynakTip IN ('ACILIS', 'ACILIS_TAMAMLA', 'SENTETIK')
                    """, commandTimeout: 30);
                var ddMesaj = devreDisiSilinen > 0
                    ? $" ({devreDisiSilinen} devre disi urun katmani temizlendi)"
                    : "";

                await logger.BitirAsync(islemId, "TAMAMLANDI", $"Acilis maliyetlendirme tamamlandi (V2).{ddMesaj}");
            }
            catch (Exception ex)
            {
                var mesaj = ex.Message.Length > 500 ? ex.Message[..500] : ex.Message;
                await logger.BitirAsync(islemId, "HATA", mesaj);
            }
        });

        return new JsonResult(new { ok = true, islemId });
    }

    public async Task<IActionResult> OnGetAcilisDurumAsync(Guid islemId)
    {
        return await DurumJsonAsync(islemId);
    }

    // ── Adim 3: Ilk Hesaplama ─────────────────────────────────────────

    public async Task<IActionResult> OnPostHesaplaAsync()
    {
        if (Yil < 2020 || Yil > 2099)
            return new JsonResult(new { ok = false, error = "Yil 2020-2099 araliginda olmali." })
                { StatusCode = StatusCodes.Status400BadRequest };

        if (Ay < 1 || Ay > 12)
            return new JsonResult(new { ok = false, error = "Ay 1-12 araliginda olmali." })
                { StatusCode = StatusCodes.Status400BadRequest };

        var islemId = await _logger.BaslatAsync(
            "Wizard — Hesaplama",
            aciklama: $"Yil: {Yil}, Ay: {Ay}");

        var yil = Yil;
        var ay = Ay;
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
                        @StkId                     = NULL,
                        @IslemId                   = @IslemId,
                        @SentetikSatinalmaSarti    = @SentetikSatinalmaSarti,
                        @SabitFallbackBirimMaliyet = @SabitFallbackBirimMaliyet,
                        @SentetikAktif             = @SentetikAktif
                    """,
                    new
                    {
                        Yil = yil,
                        Ay = ay,
                        IslemId = islemId,
                        SentetikSatinalmaSarti = "SatinAlma",
                        SabitFallbackBirimMaliyet = (decimal?)null,
                        SentetikAktif = true
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

    public async Task<IActionResult> OnGetHesaplaDurumAsync(Guid islemId)
    {
        return await DurumJsonAsync(islemId);
    }

    // ── Iptal ────────────────────────────────────────────────────────

    public async Task<IActionResult> OnPostIptalAsync(Guid islemId)
    {
        await _logger.IptalEtAsync(islemId);
        return new JsonResult(new { ok = true });
    }

    // ── Ortak Durum ───────────────────────────────────────────────────

    private async Task<IActionResult> DurumJsonAsync(Guid islemId)
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
                mesaj = a.Mesaj,
                baslangic = a.Baslangic,
                bitis = a.Bitis
            })
        });
    }
}
