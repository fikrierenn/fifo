using Dapper;
using Microsoft.Data.SqlClient;

namespace App.Lib;

public sealed class MaliyetLogger
{
    private readonly Db _db;

    public MaliyetLogger(Db db) => _db = db;

    public async Task<Guid> BaslatAsync(string islemAdi, string? aciklama = null,
        DateOnly? envanterTarihi = null, int? mekanId = null, int? stkId = null)
    {
        var islemId = Guid.NewGuid();
        await using var conn = await _db.OpenAsync();
        await conn.ExecuteAsync("""
            INSERT INTO MaliyetIslem (IslemId, IslemAdi, Baslangic, Durum, Aciklama, EnvanterTarihi, MekanId, StkId)
            VALUES (@IslemId, @IslemAdi, SYSDATETIME(), 'CALISIYOR', @Aciklama, @EnvanterTarihi, @MekanId, @StkId)
            """, new { IslemId = islemId, IslemAdi = islemAdi, Aciklama = aciklama,
                       EnvanterTarihi = envanterTarihi?.ToDateTime(TimeOnly.MinValue),
                       MekanId = mekanId, StkId = stkId });
        return islemId;
    }

    public async Task AdimYazAsync(Guid islemId, string adimKodu, string adimAdi,
        int siraNo, string durum, string? mesaj = null)
    {
        await using var conn = await _db.OpenAsync();
        await conn.ExecuteAsync(
            "EXEC sp_MaliyetAdimYaz @IslemId, @AdimKodu, @AdimAdi, @SiraNo, @Durum, @Mesaj",
            new { IslemId = islemId, AdimKodu = adimKodu, AdimAdi = adimAdi,
                  SiraNo = siraNo, Durum = durum, Mesaj = mesaj });
    }

    public async Task BitirAsync(Guid islemId, string durum, string? aciklama = null)
    {
        await using var conn = await _db.OpenAsync();
        await conn.ExecuteAsync("""
            UPDATE MaliyetIslem
            SET Durum = @Durum, Bitis = SYSDATETIME(), Aciklama = @Aciklama
            WHERE IslemId = @IslemId
            """, new { IslemId = islemId, Durum = durum, Aciklama = aciklama });
    }

    /// <summary>Islemi IPTAL olarak isaretle. Background task her adimda kontrol eder.</summary>
    public async Task IptalEtAsync(Guid islemId)
    {
        await using var conn = await _db.OpenAsync();
        await conn.ExecuteAsync("""
            UPDATE MaliyetIslem
            SET Durum = 'IPTAL', Bitis = SYSDATETIME(), Aciklama = 'Kullanici tarafindan iptal edildi.'
            WHERE IslemId = @IslemId AND Durum = 'CALISIYOR'
            """, new { IslemId = islemId });
    }

    /// <summary>Islem iptal edilmis mi kontrol et. Her adim oncesi cagrilmali.</summary>
    public async Task<bool> IptalMiAsync(Guid islemId)
    {
        await using var conn = await _db.OpenAsync();
        var durum = await conn.ExecuteScalarAsync<string>(
            "SELECT Durum FROM MaliyetIslem WHERE IslemId = @IslemId",
            new { IslemId = islemId });
        return durum == "IPTAL";
    }

    public async Task<IslemDurum?> DurumOkuAsync(Guid islemId)
    {
        await using var conn = await _db.OpenAsync();

        // READ UNCOMMITTED: SP transaction icinde adim yazarken bile polling gorebilsin
        await conn.ExecuteAsync("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED");

        var islem = await conn.QuerySingleOrDefaultAsync<IslemDurum>("""
            SELECT IslemId, IslemAdi, Baslangic, Bitis, Durum, Aciklama
            FROM MaliyetIslem WHERE IslemId = @IslemId
            """, new { IslemId = islemId });
        if (islem == null) return null;

        islem.Adimlar = (await conn.QueryAsync<IslemAdim>("""
            SELECT AdimKodu, AdimAdi, SiraNo, Durum, Mesaj, Baslangic, Bitis
            FROM MaliyetIslemAdim WHERE IslemId = @IslemId
            ORDER BY SiraNo
            """, new { IslemId = islemId })).ToList();

        // V2 SP'ler bkm.fifo_CalistirmaAdim tablosuna yazar — oradan da oku
        if (islem.Adimlar.Count == 0)
        {
            islem.Adimlar = (await conn.QueryAsync<IslemAdim>("""
                SELECT adimKodu AS AdimKodu, adimAdi AS AdimAdi, adimSirasi AS SiraNo,
                       durum AS Durum, mesaj AS Mesaj,
                       baslamaTarihi AS Baslangic, bitisTarihi AS Bitis
                FROM bkm.fifo_CalistirmaAdim
                WHERE calistirmaId = @IslemId
                ORDER BY adimSirasi
                """, new { IslemId = islemId })).ToList();
        }

        return islem;
    }
}

public class IslemDurum
{
    public Guid IslemId { get; set; }
    public string IslemAdi { get; set; } = "";
    public DateTime Baslangic { get; set; }
    public DateTime? Bitis { get; set; }
    public string Durum { get; set; } = "";
    public string? Aciklama { get; set; }
    public List<IslemAdim> Adimlar { get; set; } = new();
}

public class IslemAdim
{
    public string AdimKodu { get; set; } = "";
    public string AdimAdi { get; set; } = "";
    public int SiraNo { get; set; }
    public string Durum { get; set; } = "";
    public string? Mesaj { get; set; }
    public DateTime? Baslangic { get; set; }
    public DateTime? Bitis { get; set; }
}
