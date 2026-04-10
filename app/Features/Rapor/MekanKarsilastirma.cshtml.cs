using Microsoft.AspNetCore.Mvc.RazorPages;
using Dapper;
using App.Lib;

namespace App.Features.Rapor;

public class MekanKarsilastirmaModel : PageModel
{
    private readonly Db _db;
    public MekanKarsilastirmaModel(Db db) => _db = db;

    public List<MekanStokDto> MekanStoklar { get; set; } = new();
    public List<MekanSmmDto> MekanSmmler { get; set; } = new();

    public async Task OnGetAsync()
    {
        await using var conn = await _db.OpenAsync();

        MekanStoklar = (await conn.QueryAsync<MekanStokDto>("""
            SELECT
                k.StkId,
                SUM(CASE WHEN e.MekanId = 1 THEN e.StokMiktar ELSE 0 END) AS MerkezMiktar,
                SUM(CASE WHEN e.MekanId = 12 THEN e.StokMiktar ELSE 0 END) AS Sube2Miktar,
                SUM(CASE WHEN e.MekanId = 4477 THEN e.StokMiktar ELSE 0 END) AS Sube3Miktar,
                SUM(CASE WHEN e.MekanId = 4478 THEN e.StokMiktar ELSE 0 END) AS Sube4Miktar
            FROM FifoAcilisEnvanter e
            JOIN (SELECT DISTINCT StkId FROM FifoKatman WHERE KalanMiktar > 0) k ON k.StkId = e.StkId
            WHERE e.EnvanterTarihi = (SELECT MAX(EnvanterTarihi) FROM FifoAcilisEnvanter)
            GROUP BY k.StkId
            ORDER BY k.StkId
            """)).ToList();

        MekanSmmler = (await conn.QueryAsync<MekanSmmDto>("""
            SELECT MekanId,
                   COUNT(DISTINCT StkId) AS UrunSayisi,
                   SUM(CikisTutar) AS ToplamSmm,
                   SUM(Miktar) AS ToplamMiktar
            FROM FifoCikisDetay
            WHERE HareketTipi = 'SATIS'
            GROUP BY MekanId
            """)).ToList();

        await _db.GetUrunlerAsync(MekanStoklar.Select(s => s.StkId).Distinct());
    }
}

public class MekanStokDto
{
    public int StkId { get; set; }
    public decimal MerkezMiktar { get; set; }
    public decimal Sube2Miktar { get; set; }
    public decimal Sube3Miktar { get; set; }
    public decimal Sube4Miktar { get; set; }
}

public class MekanSmmDto
{
    public int MekanId { get; set; }
    public int UrunSayisi { get; set; }
    public decimal ToplamSmm { get; set; }
    public decimal ToplamMiktar { get; set; }
}
