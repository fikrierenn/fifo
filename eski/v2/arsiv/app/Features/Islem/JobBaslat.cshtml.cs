using System.Data;
using Dapper;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.Data.SqlClient;
using App.Lib;

namespace App.Features.Islem;

[IgnoreAntiforgeryToken]
public class JobBaslatModel : PageModel
{
    private readonly Db _db;
    private readonly MaliyetLogger _logger;
    private readonly IServiceScopeFactory _scopeFactory;

    public JobBaslatModel(Db db, MaliyetLogger logger, IServiceScopeFactory scopeFactory)
    {
        _db = db;
        _logger = logger;
        _scopeFactory = scopeFactory;
    }

    [BindProperty] public int Yil { get; set; }
    [BindProperty] public int Ay { get; set; }
    [BindProperty] public bool OrtalamaHesapla { get; set; } = true;
    [BindProperty] public bool Cascade { get; set; }
    [BindProperty] public bool Onayli { get; set; }

    private const int BatchBoyutu = 500;

    public List<SonIslemDto> SonIslemler { get; set; } = new();

    public async Task OnGetAsync()
    {
        var oncekiAy = DateTime.Today.AddMonths(-1);
        Yil = oncekiAy.Year;
        Ay = oncekiAy.Month;

        await using var conn = await _db.OpenAsync();
        SonIslemler = (await conn.QueryAsync<SonIslemDto>("""
            SELECT TOP 10 i.IslemId, i.IslemAdi, i.Baslangic, i.Bitis, i.Durum, i.Aciklama,
                   DATEDIFF(SECOND, i.Baslangic, ISNULL(i.Bitis, GETUTCDATE())) AS SureSn
            FROM MaliyetIslem i
            ORDER BY i.Baslangic DESC
            """, commandTimeout: 10)).AsList();
    }

    public async Task<IActionResult> OnPostStartAsync()
    {
        if (Yil < 2020 || Yil > 2099)
            return new JsonResult(new { ok = false, error = "Yil 2020-2099 araliginda olmali." })
                { StatusCode = StatusCodes.Status400BadRequest };

        if (Ay < 1 || Ay > 12)
            return new JsonResult(new { ok = false, error = "Ay 1-12 araliginda olmali." })
                { StatusCode = StatusCodes.Status400BadRequest };

        // Donem kontrol: sonraki aylar var mi?
        if (!Onayli)
        {
            await using var kontConn = await _db.OpenAsync();
            var sonrakiDonemler = (await kontConn.QueryAsync<SonrakiDonemDto>(
                "EXEC sp_Fifo_DonemKontrol @Yil, @Ay",
                new { Yil, Ay }, commandTimeout: 10)).AsList();

            if (sonrakiDonemler.Count > 0)
            {
                return new JsonResult(new
                {
                    ok = false,
                    uyari = true,
                    sonrakiDonemler = sonrakiDonemler.Select(d => new
                    {
                        yilAy = d.YilAy,
                        donemYil = d.DonemYil,
                        donemAy = d.DonemAy,
                        toplamKayit = d.ToplamKayit,
                        detay = d.Detay
                    }),
                    mesaj = $"Sonraki {sonrakiDonemler.Count} donemde veri var. Tekrar calistirirseniz tutarsizlik olusur."
                });
            }
        }

        // Cascade: sonraki donemleri de toplayalim
        var cascadeDonemler = new List<(int Yil, int Ay)> { (Yil, Ay) };
        if (Cascade)
        {
            await using var cascConn = await _db.OpenAsync();
            var sonraki = await cascConn.QueryAsync<SonrakiDonemDto>(
                "EXEC sp_Fifo_DonemKontrol @Yil, @Ay",
                new { Yil, Ay }, commandTimeout: 10);
            foreach (var d in sonraki.OrderBy(d => d.YilAy))
                cascadeDonemler.Add((d.DonemYil, d.DonemAy));
        }

        var islemId = await _logger.BaslatAsync(
            Cascade ? "Cascade FIFO Batch" : "Aylik FIFO Batch",
            aciklama: Cascade
                ? $"Cascade: {string.Join(" → ", cascadeDonemler.Select(d => $"{d.Yil}-{d.Ay:D2}"))}"
                : $"Yil: {Yil}, Ay: {Ay}, Ortalama: {(OrtalamaHesapla ? "Evet" : "Hayir")}");

        var yil = Yil;
        var ay = Ay;
        var ortalamaHesapla = OrtalamaHesapla;
        var donemListesi = cascadeDonemler.ToList();

        _ = Task.Run(async () =>
        {
            await using var scope = _scopeFactory.CreateAsyncScope();
            var db = scope.ServiceProvider.GetRequiredService<Db>();
            var logger = scope.ServiceProvider.GetRequiredService<MaliyetLogger>();
            int adimNo = 0;

            try
            {
                int donemIdx = 0;
                foreach (var (dYil, dAy) in donemListesi)
                {
                    donemIdx++;
                    var donemLabel = $"{dYil}-{dAy:D2}";
                    Guid runId = Guid.NewGuid();

                    await using var conn = await db.OpenAsync();

                    // Snapshot al (re-run oncesi mevcut durumu kaydet)
                    adimNo++;
                    await logger.AdimYazAsync(islemId, $"snapshot_{donemLabel}", $"Snapshot {donemLabel}", adimNo, "CALISIYOR");
                    try
                    {
                        await conn.ExecuteAsync(
                            "EXEC sp_Fifo_DonemSnapshotAl @Yil, @Ay, @RunId",
                            new { Yil = dYil, Ay = dAy, RunId = runId }, commandTimeout: 120);
                        await logger.AdimYazAsync(islemId, $"snapshot_{donemLabel}", $"Snapshot {donemLabel}", adimNo, "TAMAMLANDI");
                    }
                    catch
                    {
                        await logger.AdimYazAsync(islemId, $"snapshot_{donemLabel}", $"Snapshot {donemLabel}", adimNo, "TAMAMLANDI", "Snapshot alinamadi, devam ediliyor.");
                    }

                    // 1) Hareketli urun listesi
                    adimNo++;
                    await logger.AdimYazAsync(islemId, $"urun_{donemLabel}", $"Urun Listesi {donemLabel}", adimNo, "CALISIYOR");
                    var stkIds = (await conn.QueryAsync<int>(
                        "EXEC sp_Fifo_HareketliUrunListesi @Yil, @Ay",
                        new { Yil = dYil, Ay = dAy }, commandTimeout: 300)).AsList();

                    await db.EnsureDevreDisiCacheAsync();
                    stkIds.RemoveAll(id => Db.DevreDisiMi(id));

                    if (stkIds.Count == 0)
                    {
                        await logger.AdimYazAsync(islemId, $"urun_{donemLabel}", $"Urun Listesi {donemLabel}", adimNo, "TAMAMLANDI",
                            "Hareketli urun bulunamadi, donem atlandi.");
                        continue;
                    }
                    await logger.AdimYazAsync(islemId, $"urun_{donemLabel}", $"Urun Listesi {donemLabel}", adimNo, "TAMAMLANDI",
                        $"{stkIds.Count} urun bulundu.");

                    // 2) Batch'lere bol + run baslat
                    var batches = stkIds.Chunk(BatchBoyutu).ToList();
                    await conn.ExecuteAsync(
                        "EXEC sp_Fifo_BatchRunBaslat @RunId, @DonemYil, @DonemAy, @ToplamUrun, @ToplamBatch, @BatchBoyutu",
                        new { RunId = runId, DonemYil = dYil, DonemAy = dAy,
                              ToplamUrun = stkIds.Count, ToplamBatch = batches.Count, BatchBoyutu = BatchBoyutu });

                    // 3) Her batch icin SP cagir
                    adimNo++;
                    await logger.AdimYazAsync(islemId, $"batch_{donemLabel}", $"Batch {donemLabel}", adimNo, "CALISIYOR",
                        $"{batches.Count} batch baslatiliyor.");

                    int batchNo = 1;
                    foreach (var batch in batches)
                    {
                        await using var cmd = conn.CreateCommand();
                        cmd.CommandText = "EXEC sp_Fifo_AylikCalistirBatch @Yil=@Yil, @Ay=@Ay, @StkIdList=@StkIdList, @RunId=@RunId, @BatchNo=@BatchNo";
                        cmd.Parameters.AddWithValue("@Yil", dYil);
                        cmd.Parameters.AddWithValue("@Ay", dAy);
                        cmd.Parameters.Add(CreateStkIdTvp(batch));
                        cmd.Parameters.AddWithValue("@RunId", runId);
                        cmd.Parameters.AddWithValue("@BatchNo", batchNo);
                        cmd.CommandTimeout = 1800;
                        await cmd.ExecuteNonQueryAsync();
                        batchNo++;
                    }

                    await logger.AdimYazAsync(islemId, $"batch_{donemLabel}", $"Batch {donemLabel}", adimNo, "TAMAMLANDI",
                        $"{batches.Count} batch tamamlandi.");

                    // 4) Run bitir
                    await conn.ExecuteAsync(
                        "EXEC sp_Fifo_BatchRunBitir @RunId, @Durum, @HataMesaji",
                        new { RunId = runId, Durum = "TAMAMLANDI", HataMesaji = (string?)null });

                    // 5) Opsiyonel ortalama hesapla
                    if (ortalamaHesapla)
                    {
                        adimNo++;
                        await logger.AdimYazAsync(islemId, $"ort_{donemLabel}", $"Ortalama {donemLabel}", adimNo, "CALISIYOR");
                        await conn.ExecuteAsync(
                            "EXEC sp_Ortalama_AylikHesapla @Yil, @Ay",
                            new { Yil = dYil, Ay = dAy }, commandTimeout: 600);
                        await logger.AdimYazAsync(islemId, $"ort_{donemLabel}", $"Ortalama {donemLabel}", adimNo, "TAMAMLANDI");
                    }
                }

                var ozet = donemListesi.Count == 1
                    ? $"{donemListesi[0].Yil}-{donemListesi[0].Ay:D2} tamamlandi."
                    : $"{donemListesi.Count} donem cascade tamamlandi.";
                await logger.BitirAsync(islemId, "TAMAMLANDI", ozet);
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
            return new JsonResult(new { ok = false, error = "Islem bulunamadi." })
                { StatusCode = StatusCodes.Status404NotFound };

        // Batch progress
        await using var conn = await _db.OpenAsync();
        var batchProgress = await conn.QuerySingleOrDefaultAsync<BatchProgressDto>("""
            SELECT TOP 1 TamamlananBatch, ToplamBatch, ToplamUrun, Durum AS RunDurum
            FROM FifoBatchRun
            WHERE DonemYil = @Yil AND DonemAy = @Ay
            ORDER BY RunBaslangic DESC
            """, new { Yil = durum.Baslangic.Year, Ay = durum.Baslangic.Month });

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
            }),
            batch = batchProgress is not null
                ? new { tamamlanan = batchProgress.TamamlananBatch, toplam = batchProgress.ToplamBatch, urun = batchProgress.ToplamUrun, runDurum = batchProgress.RunDurum }
                : null
        });
    }

    private static SqlParameter CreateStkIdTvp(IEnumerable<int> stkIds)
    {
        var dt = new DataTable();
        dt.Columns.Add("StkId", typeof(int));
        foreach (var id in stkIds) dt.Rows.Add(id);
        return new SqlParameter("@StkIdList", SqlDbType.Structured)
        {
            TypeName = "StkIdListType",
            Value = dt
        };
    }
}

public class SonrakiDonemDto
{
    public int YilAy { get; set; }
    public int DonemYil { get; set; }
    public int DonemAy { get; set; }
    public int ToplamKayit { get; set; }
    public string Detay { get; set; } = "";
}

public class BatchProgressDto
{
    public int TamamlananBatch { get; set; }
    public int ToplamBatch { get; set; }
    public int ToplamUrun { get; set; }
    public string RunDurum { get; set; } = "";
}

public class SonIslemDto
{
    public Guid IslemId { get; set; }
    public string IslemAdi { get; set; } = "";
    public DateTime Baslangic { get; set; }
    public DateTime? Bitis { get; set; }
    public string Durum { get; set; } = "";
    public string? Aciklama { get; set; }
    public int SureSn { get; set; }

    public string SureStr => SureSn < 60 ? $"{SureSn}sn"
        : SureSn < 3600 ? $"{SureSn / 60}dk {SureSn % 60}sn"
        : $"{SureSn / 3600}sa {(SureSn % 3600) / 60}dk";
}
