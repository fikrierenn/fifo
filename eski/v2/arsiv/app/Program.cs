using Dapper;
using App.Lib;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddRazorPages(options =>
{
    options.RootDirectory = "/Features";
    options.Conventions.AddPageRoute("/Rapor/Index", "");
});

builder.Services.AddScoped<Db>();
builder.Services.AddScoped<MaliyetLogger>();

var app = builder.Build();

// Cache'leri DB'den yukle (bir kez)
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<Db>();
    await db.EnsureMekanCacheAsync();
    await db.EnsureDevreDisiCacheAsync();
}

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
    app.UseHsts();
    app.UseHttpsRedirection();
}
app.UseRouting();
app.UseStaticFiles();
app.MapRazorPages();

// Sidebar autocomplete icin urun arama endpoint'i
app.MapGet("/api/urun-ara", async (string? q, Db db) =>
{
    if (string.IsNullOrWhiteSpace(q) || q.Length < 3) return Results.Json(Array.Empty<object>());
    var list = await db.SearchUrunAsync(q);
    return Results.Json(list.Select(u => new { u.StkId, u.Kod, u.Ad, u.MarkaAd, u.Kategori }));
});

// Devre disi urun API endpoint'leri
app.MapPost("/api/devredisi/ekle", async (int stkId, string? sebep, Db db) =>
{
    var ok = await db.DevreDisiEkleAsync(stkId, sebep);
    return ok ? Results.Ok(new { ok = true }) : Results.Problem("Hata");
});
app.MapPost("/api/devredisi/kaldir", async (int stkId, Db db) =>
{
    var ok = await db.DevreDisiKaldirAsync(stkId);
    return ok ? Results.Ok(new { ok = true }) : Results.Problem("Hata");
});
app.MapGet("/api/devredisi/liste", async (Db db) =>
{
    await db.EnsureDevreDisiCacheAsync();
    return Results.Ok(new { sayisi = Db.DevreDisiSayisi });
});
app.MapGet("/api/devredisi/durum", (int stkId) =>
{
    return Results.Ok(new { stkId, devreDisi = Db.DevreDisiMi(stkId) });
});
app.MapGet("/api/kategoriler", async (Db db) =>
{
    await using var conn = await db.OpenAsync();
    var rows = await conn.QueryAsync<dynamic>("""
        SELECT u.KatAna AS kategori, u.Kategori3 AS kategori3,
               COUNT(*) AS urunSayisi,
               SUM(CASE WHEN dd.StkId IS NOT NULL THEN 1 ELSE 0 END) AS devreDisiSayisi
        FROM DerinSISBkm.bkm.UrunBilgi u
        LEFT JOIN dbo.FifoDevreDisiUrunler dd ON dd.StkId = u.stkID
        WHERE u.KatAna IS NOT NULL AND u.KatAna <> ''
        GROUP BY u.KatAna, u.Kategori3
        ORDER BY u.KatAna, u.Kategori3
        """, commandTimeout: 30);
    return Results.Ok(rows);
});

app.MapGet("/api/kategori-urunler", async (string tip, string deger, Db db) =>
{
    await using var conn = await db.OpenAsync();
    var where = tip == "KatAna" ? "u.KatAna = @Deger" : "u.Kategori3 = @Deger";
    var rows = await conn.QueryAsync<dynamic>($"""
        SELECT TOP 200 u.stkID AS stkId, u.stkKod AS kod, u.stkAd AS ad,
               CASE WHEN dd.StkId IS NOT NULL THEN 1 ELSE 0 END AS devreDisi
        FROM DerinSISBkm.bkm.UrunBilgi u
        LEFT JOIN dbo.FifoDevreDisiUrunler dd ON dd.StkId = u.stkID
        WHERE {where}
        ORDER BY u.stkKod
        """, new { Deger = deger }, commandTimeout: 30);
    return Results.Ok(rows);
});

app.MapPost("/api/devredisi/toplu", async (HttpContext ctx, Db db) =>
{
    var body = await ctx.Request.ReadFromJsonAsync<TopluIslemDto>();
    if (body?.StkIds == null || body.StkIds.Length == 0)
        return Results.BadRequest("StkIds bos.");

    await using var conn = await db.OpenAsync();
    int etkilenen = 0;
    if (body.Islem == "ekle")
    {
        foreach (var batch in body.StkIds.Chunk(500))
        {
            etkilenen += await conn.ExecuteAsync("""
                INSERT INTO dbo.FifoDevreDisiUrunler (StkId, Sebep)
                SELECT v.StkId, @Sebep
                FROM (SELECT @StkId AS StkId) v
                WHERE NOT EXISTS (SELECT 1 FROM dbo.FifoDevreDisiUrunler dd WHERE dd.StkId = v.StkId)
                """, batch.Select(id => new { StkId = id, Sebep = body.Sebep ?? "Toplu islem" }),
                commandTimeout: 30);
        }
    }
    else
    {
        foreach (var batch in body.StkIds.Chunk(500))
        {
            etkilenen += await conn.ExecuteAsync(
                "DELETE FROM dbo.FifoDevreDisiUrunler WHERE StkId = @StkId",
                batch.Select(id => new { StkId = id }), commandTimeout: 30);
        }
    }
    Db.ResetDevreDisiCache();
    return Results.Ok(new { ok = true, etkilenen });
});

app.Run();

record TopluIslemDto(int[] StkIds, string Islem, string? Sebep);

namespace App { public partial class Program { } }
