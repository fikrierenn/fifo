using Dapper;
using Microsoft.Data.SqlClient;

namespace App.Lib;

public sealed class Db
{
    private readonly string _connectionString;

    /// <summary>Default command timeout (saniye). SP'ler ve cross-DB view'lar icin.</summary>
    public const int DefaultTimeout = 120;

    /// <summary>Uzun batch islemleri icin timeout (saniye).</summary>
    public const int BatchTimeout = 1800;

    /// <summary>Mekan ID → Bilgi cache (App baslatildiginda DB'den yuklenir)</summary>
    private static Dictionary<int, MekanBilgi> _mekanCache = new();
    private static bool _mekanLoaded;

    /// <summary>StkId → Urun bilgi cache (lazy, talep edildikce yuklenir)</summary>
    private static readonly Dictionary<int, UrunBilgi> _urunCache = new();
    // _tumUrunlerYuklendi reserved for future bulk preload

    /// <summary>Devre disi urun listesi cache</summary>
    private static HashSet<int> _devreDisiCache = new();
    private static bool _devreDisiLoaded;

    public Db(IConfiguration config)
    {
        _connectionString = config.GetConnectionString("BKMMaliyet")
            ?? throw new InvalidOperationException("BKMMaliyet connection string bulunamadi.");
    }

    public async Task<SqlConnection> OpenAsync()
    {
        var conn = new SqlConnection(_connectionString);
        await conn.OpenAsync();
        return conn;
    }

    /// <summary>Mekan listesini DerinSISBkm.dbo.mekan_vw'den yukle (bir kez)</summary>
    public async Task EnsureMekanCacheAsync()
    {
        if (_mekanLoaded) return;
        try
        {
            await using var conn = await OpenAsync();
            var rows = await conn.QueryAsync<MekanBilgi>(
                "SELECT mekanID AS Id, mekanAd AS Ad, mekanTip AS Tip FROM DerinSISBkm.dbo.mekan_vw WHERE mekanID IN (1, 12, 4477, 4478)",
                commandTimeout: 10);
            _mekanCache = rows.ToDictionary(r => r.Id, r => { r.Ad = r.Ad.Trim(); return r; });
            _mekanLoaded = true;
        }
        catch
        {
            // Fallback: DB erisimi yoksa hardcoded kullan
            _mekanCache = new Dictionary<int, MekanBilgi>
            {
                { 1, new MekanBilgi { Id = 1, Ad = "FSM Mgz", Tip = 2 } },
                { 12, new MekanBilgi { Id = 12, Ad = "Merkez Depo", Tip = 3 } },
                { 4477, new MekanBilgi { Id = 4477, Ad = "OZLUCE Mgz", Tip = 2 } },
                { 4478, new MekanBilgi { Id = 4478, Ad = "IST YOLU Mgz", Tip = 2 } }
            };
            _mekanLoaded = true;
        }
    }

    public static Dictionary<int, MekanBilgi> Mekanlar => _mekanCache;
    public static Dictionary<int, string> MekanAdlari => _mekanCache.ToDictionary(kv => kv.Key, kv => kv.Value.Ad);
    public static string MekanAdi(int mekanId) => _mekanCache.TryGetValue(mekanId, out var m) ? m.Ad : $"Mekan {mekanId}";
    public static string MekanTipi(int mekanId) => _mekanCache.TryGetValue(mekanId, out var m) ? m.TipAdi : "Bilinmiyor";

    /// <summary>Tek urun bilgisi getir (cache'li)</summary>
    public async Task<UrunBilgi?> GetUrunAsync(int stkId)
    {
        if (_urunCache.TryGetValue(stkId, out var cached)) return cached;
        try
        {
            await using var conn = await OpenAsync();
            var urun = await conn.QuerySingleOrDefaultAsync<UrunBilgi>(
                """
                SELECT stkID AS StkId, stkKod AS Kod, stkAd AS Ad, mrkAd AS MarkaAd,
                       KatAna AS Kategori, Kategori3, SatisFiyat, SonAlis AS SonAlisFiyat
                FROM DerinSISBkm.bkm.UrunBilgi
                WHERE stkID = @StkId
                """, new { StkId = stkId }, commandTimeout: 10);
            if (urun != null)
            {
                urun.Ad = urun.Ad?.Trim() ?? "";
                urun.MarkaAd = urun.MarkaAd?.Trim() ?? "";
                _urunCache[stkId] = urun;
            }
            return urun;
        }
        catch { return null; }
    }

    /// <summary>Birden fazla urun bilgisi getir (batch, cache'li)</summary>
    public async Task<Dictionary<int, UrunBilgi>> GetUrunlerAsync(IEnumerable<int> stkIds)
    {
        var needed = stkIds.Where(id => !_urunCache.ContainsKey(id)).Distinct().ToList();
        if (needed.Count > 0)
        {
            try
            {
                await using var conn = await OpenAsync();
                // SQL Server max 2100 parametre — 1000'lik batch'lere böl
                foreach (var batch in needed.Chunk(1000))
                {
                    var rows = await conn.QueryAsync<UrunBilgi>(
                        """
                        SELECT stkID AS StkId, stkKod AS Kod, stkAd AS Ad, mrkAd AS MarkaAd,
                               KatAna AS Kategori, Kategori3, SatisFiyat, SonAlis AS SonAlisFiyat
                        FROM DerinSISBkm.bkm.UrunBilgi
                        WHERE stkID IN @Ids
                        """, new { Ids = batch }, commandTimeout: 30);
                    foreach (var u in rows)
                    {
                        u.Ad = u.Ad?.Trim() ?? "";
                        u.MarkaAd = u.MarkaAd?.Trim() ?? "";
                        _urunCache[u.StkId] = u;
                    }
                }
            }
            catch { /* DB erisimi yoksa cache'siz devam */ }
        }
        return stkIds.Distinct()
            .Where(id => _urunCache.ContainsKey(id))
            .ToDictionary(id => id, id => _urunCache[id]);
    }

    /// <summary>Urun adi getir (cache'li, sync helper)</summary>
    public static string UrunAdi(int stkId) =>
        _urunCache.TryGetValue(stkId, out var u) ? $"{u.Kod} - {u.Ad}" : $"#{stkId}";

    /// <summary>Akilli urun arama: kod, ad, marka, barkod.
    /// Coklu kelime destegi: her kelime ad+marka alaninda aranir.
    /// Siralama: cok satan urunler uste (FifoCikisDetay toplam miktar).</summary>
    public async Task<List<UrunBilgi>> SearchUrunAsync(string q)
    {
        if (string.IsNullOrWhiteSpace(q) || q.Length < 3) return new();
        try
        {
            var trimmed = q.Trim();
            var words = trimmed.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            await using var conn = await OpenAsync();

            // WHERE kosullarini olustur
            var conditions = new List<string>();
            var p = new DynamicParameters();

            if (words.Length == 1)
            {
                p.Add("Q", trimmed);
                conditions.Add("""
                    (u.stkKod LIKE @Q + '%'
                     OR u.stkAd LIKE '%' + @Q + '%'
                     OR u.mrkAd LIKE '%' + @Q + '%'
                     OR EXISTS (SELECT 1 FROM DerinSISBkm.dbo.urnBrkd b
                                WHERE b.urnBrkdStkID = u.stkID AND b.urnBarkod LIKE '%' + @Q + '%'))
                    """);
            }
            else
            {
                // Coklu kelime: her kelime ad veya marka'da olmali
                for (int i = 0; i < Math.Min(words.Length, 5); i++)
                {
                    var pn = $"W{i}";
                    conditions.Add($"(u.stkAd LIKE '%' + @{pn} + '%' OR u.mrkAd LIKE '%' + @{pn} + '%')");
                    p.Add(pn, words[i]);
                }
            }

            var sql = $"""
                SELECT TOP 20 u.stkID AS StkId, u.stkKod AS Kod, u.stkAd AS Ad, u.mrkAd AS MarkaAd,
                       u.KatAna AS Kategori, u.Kategori3, u.SatisFiyat, u.SonAlis AS SonAlisFiyat
                FROM DerinSISBkm.bkm.UrunBilgi u
                LEFT JOIN (
                    SELECT StkId, SUM(Miktar) AS TopCikis
                    FROM dbo.FifoCikisDetay
                    GROUP BY StkId
                ) c ON c.StkId = u.stkID
                WHERE {string.Join(" AND ", conditions)}
                ORDER BY ISNULL(c.TopCikis, 0) DESC, u.stkAd
                """;

            var rows = await conn.QueryAsync<UrunBilgi>(sql, p, commandTimeout: 10);
            var result = rows.ToList();
            foreach (var u in result)
            {
                u.Ad = u.Ad?.Trim() ?? "";
                u.MarkaAd = u.MarkaAd?.Trim() ?? "";
                _urunCache.TryAdd(u.StkId, u);
            }
            return result;
        }
        catch { return new(); }
    }

    // ────── Devre Disi Urun Yonetimi ──────

    /// <summary>Devre disi urun listesini DB'den yukle (bir kez)</summary>
    public async Task EnsureDevreDisiCacheAsync()
    {
        if (_devreDisiLoaded) return;
        try
        {
            await using var conn = await OpenAsync();
            var ids = await conn.QueryAsync<int>(
                "SELECT StkId FROM FifoDevreDisiUrunler", commandTimeout: 10);
            _devreDisiCache = new HashSet<int>(ids);
            _devreDisiLoaded = true;
        }
        catch { _devreDisiLoaded = true; }
    }

    public static bool DevreDisiMi(int stkId) => _devreDisiCache.Contains(stkId);
    public static int DevreDisiSayisi => _devreDisiCache.Count;
    public static void ResetDevreDisiCache() { _devreDisiLoaded = false; _devreDisiCache.Clear(); }

    public async Task<bool> DevreDisiEkleAsync(int stkId, string? sebep)
    {
        try
        {
            await using var conn = await OpenAsync();
            await conn.ExecuteAsync("""
                IF NOT EXISTS (SELECT 1 FROM FifoDevreDisiUrunler WHERE StkId = @StkId)
                    INSERT INTO FifoDevreDisiUrunler (StkId, Sebep) VALUES (@StkId, @Sebep)
                """, new { StkId = stkId, Sebep = sebep }, commandTimeout: 10);
            _devreDisiCache.Add(stkId);
            return true;
        }
        catch { return false; }
    }

    public async Task<bool> DevreDisiKaldirAsync(int stkId)
    {
        try
        {
            await using var conn = await OpenAsync();
            await conn.ExecuteAsync(
                "DELETE FROM FifoDevreDisiUrunler WHERE StkId = @StkId",
                new { StkId = stkId }, commandTimeout: 10);
            _devreDisiCache.Remove(stkId);
            return true;
        }
        catch { return false; }
    }

    /// <summary>Tum devre disi urunleri getir (yonetim sayfasi icin)</summary>
    public async Task<List<DevreDisiUrunDto>> GetDevreDisiListeAsync()
    {
        try
        {
            await using var conn = await OpenAsync();
            return (await conn.QueryAsync<DevreDisiUrunDto>(
                "SELECT StkId, Sebep, EkleyenKullanici, EklenmeTarihi FROM FifoDevreDisiUrunler ORDER BY EklenmeTarihi DESC",
                commandTimeout: 10)).ToList();
        }
        catch { return new(); }
    }
}

public class DevreDisiUrunDto
{
    public int StkId { get; set; }
    public string? Sebep { get; set; }
    public string? EkleyenKullanici { get; set; }
    public DateTime EklenmeTarihi { get; set; }
}

public class UrunBilgi
{
    public int StkId { get; set; }
    public string Kod { get; set; } = "";
    public string Ad { get; set; } = "";
    public string MarkaAd { get; set; } = "";
    public string Kategori { get; set; } = "";
    public string Kategori3 { get; set; } = "";
    public decimal SatisFiyat { get; set; }
    public decimal SonAlisFiyat { get; set; }

    public string Etiket => $"{Kod} - {Ad}";
    public string KisaEtiket => Ad.Length > 40 ? Ad[..37] + "..." : Ad;
}

public class MekanBilgi
{
    public int Id { get; set; }
    public string Ad { get; set; } = "";
    public int Tip { get; set; }

    /// <summary>2=Magaza (Sube), 3=Depo</summary>
    public string TipAdi => Tip switch { 2 => "Magaza", 3 => "Depo", _ => $"Tip {Tip}" };
    public string Etiket => $"{Ad} ({TipAdi})";
}
