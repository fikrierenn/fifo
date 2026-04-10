using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Dapper;
using App.Lib;

namespace App.Features.Rapor;

public class EvrakDetayModel : PageModel
{
    private readonly Db _db;
    public EvrakDetayModel(Db db) => _db = db;

    [BindProperty(SupportsGet = true)] public long HrkId { get; set; }

    // Üst bilgi (tıklanan hareket satırı)
    public EvrakBaslikDto? Baslik { get; set; }

    // Aynı evraktaki tüm kalemler
    public List<EvrakKalemDto> Kalemler { get; set; } = new();

    public async Task<IActionResult> OnGetAsync()
    {
        if (HrkId <= 0) return RedirectToPage("/Rapor/Index");

        await using var conn = await _db.OpenAsync();

        // 1) Tıklanan hareketin bilgisi
        Baslik = await conn.QuerySingleOrDefaultAsync<EvrakBaslikDto>("""
            SELECT h.hrkID AS HrkId, h.ehID AS EvrakId, h.ehstkID AS StkId,
                   h.ehMekan AS MekanId, h.ehTrhS AS Tarih, h.ehAdetN AS Miktar,
                   h.ehTutarN AS Tutar, h.ehMlyt AS ErpMaliyet, h.ehTip AS IrsTip,
                   u.stkKod AS UrunKod, u.stkAd AS UrunAd, u.mrkAd AS MarkaAd
            FROM DerinSISBkm.dbo.irsHrk h
            LEFT JOIN DerinSISBkm.bkm.UrunBilgi u ON u.stkID = h.ehstkID
            WHERE h.hrkID = @HrkId
            """, new { HrkId }, commandTimeout: 15);

        if (Baslik == null) return RedirectToPage("/Rapor/Index");

        Baslik.UrunAd = Baslik.UrunAd?.Trim() ?? "";
        Baslik.MarkaAd = Baslik.MarkaAd?.Trim() ?? "";
        Baslik.UrunKod = Baslik.UrunKod?.Trim() ?? "";

        // 2) Aynı evraktaki tüm kalemler (ehID bazlı)
        Kalemler = (await conn.QueryAsync<EvrakKalemDto>("""
            SELECT h2.hrkID AS HrkId, h2.ehstkID AS StkId, h2.ehMekan AS MekanId,
                   u.stkKod AS UrunKod, u.stkAd AS UrunAd, u.mrkAd AS MarkaAd,
                   h2.ehAdetN AS Miktar, h2.ehTutarN AS Tutar, h2.ehMlyt AS ErpMaliyet
            FROM DerinSISBkm.dbo.irsHrk h2
            LEFT JOIN DerinSISBkm.bkm.UrunBilgi u ON u.stkID = h2.ehstkID
            WHERE h2.ehID = @EvrakId
            ORDER BY h2.hrkID
            """, new { Baslik.EvrakId }, commandTimeout: 30)).ToList();

        // 3) FIFO maliyet eşleştirmesi (kalem bazlı lookup)
        if (Kalemler.Count > 0)
        {
            var stkIds = Kalemler.Select(k => k.StkId).Distinct().ToList();
            var fifoRows = await conn.QueryAsync<(int StkId, int MekanId, decimal FifoMaliyet, decimal FifoSatisTutar)>("""
                SELECT cd.StkId, cd.MekanId,
                       SUM(cd.CikisTutar) AS FifoMaliyet,
                       SUM(cd.SatisTutar) AS FifoSatisTutar
                FROM dbo.FifoCikisDetay cd
                WHERE cd.StkId IN @StkIds
                  AND cd.HareketTarihi = @Tarih
                GROUP BY cd.StkId, cd.MekanId
                """, new { StkIds = stkIds, Tarih = Baslik.Tarih }, commandTimeout: 15);
            var fifoMap = fifoRows.ToDictionary(x => (x.StkId, x.MekanId));

            foreach (var k in Kalemler)
            {
                if (fifoMap.TryGetValue((k.StkId, k.MekanId), out var f))
                {
                    k.FifoMaliyet = f.FifoMaliyet;
                    k.FifoSatisTutar = f.FifoSatisTutar;
                }
            }
        }

        foreach (var k in Kalemler)
        {
            k.UrunAd = k.UrunAd?.Trim() ?? "";
            k.MarkaAd = k.MarkaAd?.Trim() ?? "";
            k.UrunKod = k.UrunKod?.Trim() ?? "";
        }

        return Page();
    }

    public string HareketTipiAdi => Baslik?.IrsTip switch
    {
        0 or 2 => "ALIŞ",
        1 or 4 or 5 or 100 or 101 => "SATIŞ",
        3 or 10 or 11 => "TRANSFER",
        6 => "SAYIM",
        88 => "ENVANTER",
        96 => "İADE",
        _ => $"TİP_{Baslik?.IrsTip}"
    };

    public string MekanAdi => Baslik?.MekanId switch
    {
        1 => "Depo",
        12 => "İstanbul Mağaza",
        4477 => "Ankara Mağaza",
        4478 => "İzmir Mağaza",
        _ => $"Mekan {Baslik?.MekanId}"
    };
}

public class EvrakBaslikDto
{
    public long HrkId { get; set; }
    public long EvrakId { get; set; }
    public int StkId { get; set; }
    public int MekanId { get; set; }
    public DateTime Tarih { get; set; }
    public decimal Miktar { get; set; }
    public decimal Tutar { get; set; }
    public decimal ErpMaliyet { get; set; }
    public int IrsTip { get; set; }
    public string UrunKod { get; set; } = "";
    public string UrunAd { get; set; } = "";
    public string MarkaAd { get; set; } = "";
}

public class EvrakKalemDto
{
    public long HrkId { get; set; }
    public int StkId { get; set; }
    public int MekanId { get; set; }
    public string UrunKod { get; set; } = "";
    public string UrunAd { get; set; } = "";
    public string MarkaAd { get; set; } = "";
    public decimal Miktar { get; set; }
    public decimal Tutar { get; set; }
    public decimal ErpMaliyet { get; set; }
    /// <summary>FIFO çıkış maliyeti (FifoCikisDetay toplam)</summary>
    public decimal? FifoMaliyet { get; set; }
    /// <summary>FIFO satış tutarı</summary>
    public decimal? FifoSatisTutar { get; set; }

    public decimal BirimFiyat => Miktar != 0 ? Tutar / Math.Abs(Miktar) : 0;
    public decimal? FifoBirimMaliyet => (FifoMaliyet.HasValue && Miktar != 0)
        ? FifoMaliyet.Value / Math.Abs(Miktar) : null;
    public decimal? BrutKar => FifoMaliyet.HasValue ? Tutar - FifoMaliyet.Value : null;
    public decimal? BrutKarMarji => (BrutKar.HasValue && Tutar != 0)
        ? (BrutKar.Value / Math.Abs(Tutar)) * 100 : null;
}
