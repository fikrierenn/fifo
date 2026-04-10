# Yeni Razor Page Olustur

Proje pattern'ine uygun yeni bir Razor Page olusturur.

## Arguman
$ARGUMENTS — sayfa yolu ve aciklama. Ornekler:
- `Features/Fifo/Hesapla "Aylik FIFO hesaplama"`
- `Features/Rapor/Detay "Urun detay raporu"`
- `Features/Snapshot/Create "Envanter snapshot olustur"`

## Kurallar (ZORUNLU)
- App.Lib.Db ve App.Lib.MaliyetLogger kullan (DI ile)
- Dapper ile SQL, SELECT * YASAK
- Async handler'lar (OnGetAsync, OnPostAsync)
- Tailwind CSS, _Layout.cshtml'e uyumlu tasarim
- Background islem gerekliyse: Task.Run + MaliyetLogger + polling pattern (Acilis.cshtml referans)
- Read-only sayfaysa: sadece OnGetAsync + Dapper query

## Referans Pattern
- Background + polling: `app/Features/Fifo/Acilis.cshtml` ve `.cs`
- Read-only rapor: `app/Features/Rapor/Index.cshtml` ve `.cs`
- Filtreli tablo: `app/Features/Rapor/Karsilastirma.cshtml` ve `.cs`

## Baglamlar
- SP parametreleri: memory/semantic_layer.md ve memory/schema.md oku
- Mevcut sayfalar: `app/Features/` altini tara, tekrar etme
- Layout: `app/Features/Shared/_Layout.cshtml` sidebar'a yeni link ekle

## Cikti
1. `.cshtml.cs` dosyasi (PageModel, DI, Dapper sorgulari)
2. `.cshtml` dosyasi (Tailwind UI, form/tablo/timeline)
3. _Layout.cshtml'e sidebar link ekle (gerekirse)
4. `dotnet build` calistir ve 0 hata dogrula
