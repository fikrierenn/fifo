using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Dapper;
using App.Lib;

namespace App.Features.Rapor;

public class IndexModel : PageModel
{
    private readonly Db _db;
    public IndexModel(Db db) => _db = db;

    public List<KatmanOzet> Katmanlar { get; set; } = new();
    public List<SonIslem> Islemler { get; set; } = new();
    public int SorunluStokSayisi { get; set; }
    public int ToplamKatman { get; set; }
    public decimal ToplamStokDegeri { get; set; }
    public List<BatchOzet> BatchRunlar { get; set; } = new();

    public async Task OnGetAsync()
    {
        await using var conn = await _db.OpenAsync();

        // 1. Katman durumu (TOP 100)
        Katmanlar = (await conn.QueryAsync<KatmanOzet>("""
            SELECT TOP 100 StkId, KaynakTip,
                   KatmanSayisi, ToplamMiktar, KalanMiktar, TuketilenMiktar,
                   OrtalamaBirimMaliyet, MinBirimMaliyet, MaxBirimMaliyet
            FROM vw_Fifo_KatmanDurumu
            ORDER BY KalanMiktar DESC
            """)).ToList();

        // 2. Toplam stok degeri
        var stokOzet = await conn.QuerySingleOrDefaultAsync<StokOzet>("""
            SELECT COUNT(KatmanId) AS Sayi,
                   ISNULL(SUM(KalanMiktar * BirimMaliyet), 0) AS Deger
            FROM FifoKatman WHERE KalanMiktar > 0
            """) ?? new StokOzet();
        ToplamKatman = stokOzet.Sayi;
        ToplamStokDegeri = stokOzet.Deger;

        // 3. Sorunlu stoklar
        SorunluStokSayisi = await conn.ExecuteScalarAsync<int>(
            "SELECT COUNT(DISTINCT StkId) FROM FifoSorunluStoklar");

        // 4. Son islemler (TOP 50)
        Islemler = (await conn.QueryAsync<SonIslem>("""
            SELECT TOP 50 IslemId, IslemAdi, Baslangic, Bitis, Durum, Aciklama, StkId
            FROM MaliyetIslem ORDER BY Baslangic DESC
            """)).ToList();

        // 5. Batch run ozeti (TOP 20)
        BatchRunlar = (await conn.QueryAsync<BatchOzet>("""
            SELECT TOP 20 RunId, DonemYil, DonemAy, Durum, ToplamUrun,
                   TamamlananBatch, ToplamBatch, SureSaniye, ToplamHataUrun
            FROM vw_FifoBatchRunOzet ORDER BY RunBaslangic DESC
            """)).ToList();

        // Urun isimlerini cache'e yukle
        var stkIds = Katmanlar.Select(k => k.StkId)
            .Concat(Islemler.Where(i => i.StkId.HasValue).Select(i => i.StkId!.Value))
            .Distinct();
        await _db.GetUrunlerAsync(stkIds);
    }

    public async Task<IActionResult> OnGetExportAsync()
    {
        await using var conn = await _db.OpenAsync();

        var katmanlar = (await conn.QueryAsync<KatmanOzet>("""
            SELECT TOP 100 StkId, KaynakTip,
                   KatmanSayisi, ToplamMiktar, KalanMiktar, TuketilenMiktar,
                   OrtalamaBirimMaliyet, MinBirimMaliyet, MaxBirimMaliyet
            FROM vw_Fifo_KatmanDurumu
            ORDER BY KalanMiktar DESC
            """)).ToList();

        var csv = CsvExporter.ToCsv(katmanlar);
        return File(csv, "text/csv", "dashboard_katmanlar.csv");
    }
}

public class KatmanOzet
{
    public int StkId { get; set; }
    public string KaynakTip { get; set; } = "";
    public long KatmanSayisi { get; set; }
    public decimal ToplamMiktar { get; set; }
    public decimal KalanMiktar { get; set; }
    public decimal TuketilenMiktar { get; set; }
    public decimal OrtalamaBirimMaliyet { get; set; }
    public decimal MinBirimMaliyet { get; set; }
    public decimal MaxBirimMaliyet { get; set; }
}

public class SonIslem
{
    public Guid IslemId { get; set; }
    public string IslemAdi { get; set; } = "";
    public DateTime Baslangic { get; set; }
    public DateTime? Bitis { get; set; }
    public string Durum { get; set; } = "";
    public string? Aciklama { get; set; }
    public int? StkId { get; set; }
}

public class StokOzet
{
    public int Sayi { get; set; }
    public decimal Deger { get; set; }
}

public class BatchOzet
{
    public Guid RunId { get; set; }
    public int DonemYil { get; set; }
    public int DonemAy { get; set; }
    public string Durum { get; set; } = "";
    public int ToplamUrun { get; set; }
    public int TamamlananBatch { get; set; }
    public int ToplamBatch { get; set; }
    public int? SureSaniye { get; set; }
    public int ToplamHataUrun { get; set; }
}
