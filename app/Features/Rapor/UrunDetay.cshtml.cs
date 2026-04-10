using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Dapper;
using App.Lib;

namespace App.Features.Rapor;

public class UrunDetayModel : PageModel
{
    private readonly Db _db;
    public UrunDetayModel(Db db) => _db = db;

    [BindProperty(SupportsGet = true)] public int StkId { get; set; }
    [BindProperty(SupportsGet = true)] public DateTime? HrkBaslangic { get; set; }
    [BindProperty(SupportsGet = true)] public DateTime? HrkBitis { get; set; }
    [BindProperty(SupportsGet = true)] public int? HrkMekanId { get; set; }
    [BindProperty(SupportsGet = true)] public string? Tab { get; set; }

    public List<HareketDto> Hareketler { get; set; } = new();
    public List<KatmanDto> Katmanlar { get; set; } = new();
    public List<CikisDto> Cikislar { get; set; } = new();
    public List<SorunDto> Sorunlar { get; set; } = new();
    public List<AcilisEnvanterDto> AcilisEnvanter { get; set; } = new();
    public List<OrtalamaDto> OrtalamaMaliyetler { get; set; } = new();
    public List<ManuelMaliyetDetayDto> ManuelMaliyetler { get; set; } = new();

    public decimal ToplamKalanMiktar { get; set; }
    public decimal AgirlikliOrtBirimMaliyet { get; set; }
    public decimal ToplamStokDegeri { get; set; }
    public decimal ToplamSmm { get; set; }

    public decimal DevirBasi { get; set; }
    public decimal ToplamGiris { get; set; }
    public decimal ToplamCikis { get; set; }
    public decimal DevirSonu { get; set; }

    public UrunBilgi? Urun { get; set; }

    public async Task OnGetAsync()
    {
        if (StkId <= 0) return;

        Urun = await _db.GetUrunAsync(StkId);

        await using var conn = await _db.OpenAsync();

        // a) Katmanlar
        Katmanlar = (await conn.QueryAsync<KatmanDto>("""
            SELECT KatmanId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
                   GirisMiktar, KalanMiktar, BirimMaliyet, Durum, KayitTarihi
            FROM FifoKatman WHERE StkId = @StkId
            ORDER BY GirisTarihi, KatmanId
            """, new { StkId })).ToList();

        // b) Cikislar — SatisTutar artik lokal tabloda (19_V2 ile eklendi)
        Cikislar = (await conn.QueryAsync<CikisDto>("""
            SELECT CikisId, HareketTarihi, HareketTipi, MekanId, BelgeNo,
                   KatmanId, KatmanTarihi, KatmanBelgeNo, Miktar, BirimMaliyet, CikisTutar,
                   ISNULL(SatisTutar, 0) AS SatisTutar
            FROM FifoCikisDetay WHERE StkId = @StkId
            ORDER BY HareketTarihi DESC, CikisId DESC
            """, new { StkId })).ToList();

        // c) Sorunlar
        Sorunlar = (await conn.QueryAsync<SorunDto>("""
            SELECT EnvanterTarihi, MekanId, SorunTipi, StokMiktar, Aciklama, KayitTarihi
            FROM FifoSorunluStoklar WHERE StkId = @StkId
            ORDER BY KayitTarihi DESC
            """, new { StkId })).ToList();

        // d) Acilis envanter
        AcilisEnvanter = (await conn.QueryAsync<AcilisEnvanterDto>("""
            SELECT EnvanterTarihi, MekanId, StokMiktar, KayitTarihi
            FROM FifoAcilisEnvanter WHERE StkId = @StkId
            """, new { StkId })).ToList();

        // e) Ortalama maliyet
        OrtalamaMaliyetler = (await conn.QueryAsync<OrtalamaDto>("""
            SELECT YilAy, AyBasiMiktar, AyBasiTutar, GirisMiktar, GirisTutar,
                   CikisMiktar, AySonuMiktar, AySonuBirimMaliyet, AySonuTutar
            FROM OrtalamaAylikMaliyet WHERE StkId = @StkId
            ORDER BY YilAy DESC
            """, new { StkId })).ToList();

        // f) Manuel maliyetler
        ManuelMaliyetler = (await conn.QueryAsync<ManuelMaliyetDetayDto>("""
            SELECT ManuelId, BirimMaliyet, GecerliBaslangic, GecerliBitis, Aciklama, EklenmeTarihi
            FROM vw_Fifo_ManuelMaliyet WHERE StkId = @StkId
            ORDER BY GecerliBaslangic DESC
            """, new { StkId }, commandTimeout: 10)).AsList();

        // g) ERP stok hareketleri (tarih araligi ile + mekan filtresi)
        if (!HrkBaslangic.HasValue) HrkBaslangic = DateTime.Today.AddMonths(-3);
        if (!HrkBitis.HasValue) HrkBitis = DateTime.Today;
        Hareketler = (await conn.QueryAsync<HareketDto>("""
            SELECT
                h.hrkID AS HrkId,
                h.ehID AS HareketId,
                h.ehTrhS AS Tarih,
                h.ehMekan AS MekanId,
                h.ehAdetN AS Miktar,
                h.ehTip AS IrsTip,
                CASE
                    WHEN h.ehTip IN (100, 101, 1, 4, 5) THEN 'SATIS'
                    WHEN h.ehTip IN (0, 2) THEN 'ALIS'
                    WHEN h.ehTip IN (3, 10, 11) THEN 'TRANSFER'
                    WHEN h.ehTip = 6 THEN 'SAYIM'
                    WHEN h.ehTip = 96 THEN 'IADE'
                    ELSE 'TIP_' + CAST(h.ehTip AS VARCHAR)
                END AS HareketTipi,
                CAST(h.hrkID AS VARCHAR(20)) AS BelgeNo,
                h.ehTutarN AS Tutar,
                h.ehMlyt AS ErpMaliyet
            FROM DerinSISBkm.dbo.irsHrk h WITH(NOLOCK)
            WHERE h.ehstkID = @StkId
              AND h.ehTrhS >= CONVERT(smalldatetime, @Baslangic)
              AND h.ehTrhS < DATEADD(DAY, 1, CONVERT(smalldatetime, @Bitis))
              AND h.ehMekan IN (1, 12, 4477, 4478)
              AND h.ehAltDepo = 0
              AND (@MekanId IS NULL OR h.ehMekan = @MekanId)
            ORDER BY h.ehTrhS ASC, h.ehID ASC
            """, new { StkId, Baslangic = HrkBaslangic.Value, Bitis = HrkBitis.Value, MekanId = HrkMekanId },
            commandTimeout: 30)).ToList();

        // h) Devir hesaplamasi
        var devirBasi = await conn.QuerySingleOrDefaultAsync<decimal?>("""
            SELECT SUM(CONVERT(DECIMAL(18,4), h.ehAdetN))
            FROM DerinSISBkm.dbo.irsHrk h WITH(NOLOCK)
            WHERE h.ehstkID = @StkId
              AND h.ehTrhS < CONVERT(smalldatetime, @Baslangic)
              AND h.ehMekan IN (1, 12, 4477, 4478)
              AND h.ehAltDepo = 0
              AND (@MekanId IS NULL OR h.ehMekan = @MekanId)
            """, new { StkId, Baslangic = HrkBaslangic.Value, MekanId = HrkMekanId },
            commandTimeout: 30);
        DevirBasi = devirBasi ?? 0;
        ToplamGiris = Hareketler.Where(h => h.Miktar > 0).Sum(h => h.Miktar);
        ToplamCikis = Hareketler.Where(h => h.Miktar < 0).Sum(h => Math.Abs(h.Miktar));
        DevirSonu = DevirBasi + ToplamGiris - ToplamCikis;

        // Kumulatif bakiye hesapla
        // Hareketler ASC sirada (en eski ustte). Bakiye = DevirBasi + kumulatif hareket
        var bakiye = DevirBasi;
        for (int i = 0; i < Hareketler.Count; i++)
        {
            bakiye += Hareketler[i].Miktar;
            Hareketler[i].Bakiye = bakiye;
        }

        // g) Ozet hesaplama
        var aktifKatmanlar = Katmanlar.Where(k => k.KalanMiktar > 0).ToList();
        ToplamKalanMiktar = aktifKatmanlar.Sum(k => k.KalanMiktar);
        ToplamStokDegeri = aktifKatmanlar.Sum(k => k.KalanMiktar * k.BirimMaliyet);
        AgirlikliOrtBirimMaliyet = ToplamKalanMiktar > 0
            ? ToplamStokDegeri / ToplamKalanMiktar
            : 0;
        ToplamSmm = Cikislar.Where(c => c.HareketTipi == "SATIS").Sum(c => c.CikisTutar);
    }

    public async Task<IActionResult> OnGetExportAsync()
    {
        if (StkId <= 0) return RedirectToPage();

        await using var conn = await _db.OpenAsync();

        var katmanlar = (await conn.QueryAsync<KatmanDto>("""
            SELECT KatmanId, GirisTarihi, KaynakTip, BelgeNo, BelgeTarihi, FirmaId,
                   GirisMiktar, KalanMiktar, BirimMaliyet, Durum, KayitTarihi
            FROM FifoKatman WHERE StkId = @StkId
            ORDER BY GirisTarihi, KatmanId
            """, new { StkId })).ToList();

        var csv = CsvExporter.ToCsv(katmanlar);
        return File(csv, "text/csv", $"urun_{StkId}_katmanlar.csv");
    }
}

public class KatmanDto
{
    public long KatmanId { get; set; }
    public DateTime GirisTarihi { get; set; }
    public string KaynakTip { get; set; } = "";
    public string? BelgeNo { get; set; }
    public DateTime? BelgeTarihi { get; set; }
    public int? FirmaId { get; set; }
    public decimal GirisMiktar { get; set; }
    public decimal KalanMiktar { get; set; }
    public decimal BirimMaliyet { get; set; }
    public string Durum { get; set; } = "";
    public DateTime KayitTarihi { get; set; }
}

public class CikisDto
{
    public long CikisId { get; set; }
    public DateTime HareketTarihi { get; set; }
    public string HareketTipi { get; set; } = "";
    public int MekanId { get; set; }
    public string? BelgeNo { get; set; }
    public long KatmanId { get; set; }
    public DateTime? KatmanTarihi { get; set; }
    public string? KatmanBelgeNo { get; set; }
    public decimal Miktar { get; set; }
    public decimal BirimMaliyet { get; set; }
    public decimal CikisTutar { get; set; }

    /// <summary>Satis fiyati * miktar (varsa)</summary>
    public decimal SatisTutar { get; set; }

    /// <summary>Brut kar = SatisTutar - CikisTutar (maliyet)</summary>
    public decimal BrutKar => SatisTutar - CikisTutar;
}

public class SorunDto
{
    public DateTime EnvanterTarihi { get; set; }
    public int MekanId { get; set; }
    public string SorunTipi { get; set; } = "";
    public decimal StokMiktar { get; set; }
    public string? Aciklama { get; set; }
    public DateTime KayitTarihi { get; set; }
}

public class AcilisEnvanterDto
{
    public DateTime EnvanterTarihi { get; set; }
    public int MekanId { get; set; }
    public decimal StokMiktar { get; set; }
    public DateTime KayitTarihi { get; set; }
}

public class HareketDto
{
    public long HrkId { get; set; }
    public long HareketId { get; set; }
    public DateTime Tarih { get; set; }
    public int MekanId { get; set; }
    public decimal Miktar { get; set; }
    public string HareketTipi { get; set; } = "";
    public string? BelgeNo { get; set; }
    public int IrsTip { get; set; }
    /// <summary>Net tutar (ehTutarN — indirimli)</summary>
    public decimal Tutar { get; set; }
    /// <summary>ERP maliyet (ehMlyt)</summary>
    public decimal ErpMaliyet { get; set; }

    /// <summary>Kumulatif stok bakiyesi (sayfa tarafinda hesaplanir)</summary>
    public decimal Bakiye { get; set; }
}

public class ManuelMaliyetDetayDto
{
    public int ManuelId { get; set; }
    public decimal BirimMaliyet { get; set; }
    public DateTime GecerliBaslangic { get; set; }
    public DateTime? GecerliBitis { get; set; }
    public string? Aciklama { get; set; }
    public DateTime EklenmeTarihi { get; set; }
}

public class OrtalamaDto
{
    public int YilAy { get; set; }
    public decimal AyBasiMiktar { get; set; }
    public decimal AyBasiTutar { get; set; }
    public decimal GirisMiktar { get; set; }
    public decimal GirisTutar { get; set; }
    public decimal CikisMiktar { get; set; }
    public decimal AySonuMiktar { get; set; }
    public decimal AySonuBirimMaliyet { get; set; }
    public decimal AySonuTutar { get; set; }
}
