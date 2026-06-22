# FIFO Maliyet Projesi — AGENTS.md

> **Hafıza Mimarisi**: Hiyerarşik context (3 katman).
> Bu dosya (Katman 1) her session okunur. Detaylar `.Codex/AGENTS.md` index'i üzerinden sub-file'larda.
> Sub-file'lar: `C:\Users\fikri.eren\.Codex\projects\d--Dev-fifo\memory\MAIN_INDEX.md`

## Proje Nedir?
BKMMaliyet: FIFO + Ortalama maliyet hesaplama sistemi.
Kaynak: DerinSIS ERP (linked server: `DerinSISBkm`) → `BKMMaliyet` DB → .NET Razor Pages UI.

## Teknoloji Kararları (ZORUNLU)
- **.NET 10** + ASP.NET Core Razor Pages (server-side rendering)
- **MVC yok, Controller yok** — feature-based transaction script pattern
- **Dapper** ile SQL Server erişimi, ORM yok
- **UI**: Vanilla JS + TailwindCSS, minimalist
- **Hangfire** ile batch orchestration (ayrı proje: `hangfire/`)

## SQL Kuralları (ZORUNLU)
- `SET XACT_ABORT ON` + `TRY/CATCH` her SP'de
- `SELECT *` yasak — kolon isimlerini yaz
- `NOLOCK` yasak (SP'ler zaten kullanıyor ama yeni kodda kullanma)
- SARGable sorgular (fonksiyon WHERE'de indeks kolonuna uygulanmaz)
- `MERGE` yerine `DELETE + INSERT` tercih et
- Idempotent scriptler (CREATE OR ALTER, IF NOT EXISTS)

## Cevap Formatı
1 cümle gerekçe + çıktı (kod/şema/plan). Uzun açıklama yapma.

## API Politikası
Razor Pages → direkt DB (Dapper). API endpoint sadece mobil/harici/webhook zorunlu olursa.

## Dizin Yapısı
```
D:/Dev/fifo/
├── AGENTS.md              ← BU DOSYA
├── hangfire/              ← Hangfire orchestrator (.NET 10, DONE)
│   ├── Fifo.Hangfire.csproj
│   ├── Program.cs, appsettings.json
│   ├── FifoMonthlyJob.cs, FifoOpeningJob.cs
│   ├── FifoRetryPolicy.cs, FifoJobOptions.cs
│   └── StkIdTvp.cs, FifoJobServiceExtensions.cs
├── app/                   ← .NET 10 Razor Pages UI (TAMAMLANDI, 21 sayfa)
├── v2-production/         ← SQL scriptler (TÜMÜ DEPLOYED)
│   ├── 00–11: Tables, SPs, Views, Tests
│   ├── 12_V2_OrtalamaAylikMaliyet.sql
│   └── 13_V2_EksikViewlar.sql
├── SQL-Improvements/      ← Sprint1+2 (DONE)
├── docs/                  ← SCHEMA.md, strateji dokümanları
├── sql-alpha/             ← Alpha referans
└── yedek/src/App/         ← Eski Razor Pages (referans kodu)
```

## Veritabanı
- **DB**: `BKMMaliyet` (SQL Server 2019, Host: 192.168.40.201 — VPN gerekli)
- **Cross-DB**: `DerinSISBkm` (aynı sunucu, linked server değil)
- **sqlcli**: `cd D:/Dev/fifo && dotnet run --project D:/Dev/sqlcli -- <komut>`
- **sqlcli.json**: bağlantı bilgisi burada

### Tablolar (dbo)
| Tablo | PK | Açıklama |
|-------|-----|---------|
| FifoKatman | KatmanId (IDENTITY) | FIFO maliyet katmanları |
| FifoAcilisEnvanter | (EnvanterTarihi, MekanId, StkId) | Açılış stok snapshot |
| FifoCikisDetay | CikisId (IDENTITY) | FIFO çıkış detayları |
| FifoFallbackFiyatlari | (StkId, SatinalmaSarti, MekanId) | Fallback fiyatlar |
| FifoSorunluStoklar | (EnvanterTarihi, MekanId, StkId, SorunTipi) | Sorunlu stoklar |
| MaliyetIslem | IslemId (GUID) | İşlem log başlık |
| MaliyetIslemAdim | (IslemId, AdimKodu) | İşlem log adım |
| OrtalamaAylikMaliyet | (YilAy, StkId) | Aylık ortalama maliyet |
| FifoBatchRun | RunId (GUID) | Batch çalıştırma üst kayıt |
| FifoBatchDetay | DetayId (IDENTITY) | Batch detay takibi |
| FifoBatchHata | HataId (IDENTITY) | Ürün bazlı hata logu |

### SP'ler
- `sp_Fifo_AcilisMaliyetlendir` — açılış maliyetlendirme
- `sp_Fifo_AlisKatmanEkle` — alış katman ekleme
- `sp_Fifo_CikisMaliyetle` — FIFO çıkış
- `sp_Fifo_Calistir`, `sp_Fifo_AcilisCalistir`, `sp_Fifo_AylikCalistir`
- `sp_Fifo_AylikCalistirBatch` (TVP: StkIdListType)
- `sp_Fifo_BatchRunBaslat`, `sp_Fifo_BatchRunBitir`
- `sp_Fifo_HareketliUrunListesi`, `sp_Fifo_SentetikKatmanOlustur`
- `sp_Fifo_AylikRutin`, `sp_Fifo_AylikRutinFull`
- `sp_MaliyetAdimYaz` — loglama
- `sp_Ortalama_AylikHesapla` — ortalama maliyet hesaplama

### DerinSIS Tabloları (linked server)
- `DerinSISBkm.dbo.irsHrk` — stok hareketleri (ehMekan, ehstkID, ehAdetN, ehTrhS)
- `DerinSISBkm.dbo.fat` — faturalar (eTarihS, eTip, eGC, eFirma, eMekan)
- `DerinSISBkm.dbo.fatAyr` — fatura satırları (ehStkId, ehAdetN, ehTutarN, ehID)
- Alış filtresi: `f.eTip IN (0, 2)`, `eGC=0 → +, eGC=1 → -`

## .NET App Yapısı (TAMAMLANDI)
```
app/
├── Program.cs, appsettings.json, App.csproj
├── Features/
│   ├── Rapor/       Index, Karsilastirma, UrunDetay, KatmanDetay,
│   │                CikisRaporu, SorunluStoklar, IslemLog, BatchDetay,
│   │                MekanKarsilastirma, Trend, BrutKar, HareketliUrunler (12 sayfa)
│   ├── Fifo/        Acilis, Hesapla, Wizard (3 sayfa)
│   ├── Islem/       JobBaslat, HataliRetry (2 sayfa)
│   ├── Ortalama/    AySonu (1 sayfa)
│   ├── Snapshot/    Create (1 sayfa)
│   ├── Ayar/        FallbackFiyat, DevreDisiUrunler, ManuelMaliyet (3 sayfa)
│   ├── Yardim/      Index, SqlReferans (2 sayfa)
│   └── Shared/      _Layout, _ViewImports, _ViewStart
└── Lib/
    ├── Db.cs            ← Dapper SqlConnection wrapper (DI: IServiceProvider)
    ├── MaliyetLogger.cs ← sp_MaliyetAdimYaz wrapper (DI: Db)
    └── CsvExporter.cs   ← Generic CSV export helper
```

### UI Özellikleri
- **Chart.js** grafikleri (7+ sayfada)
- **CSV Export** (8 raporda)
- **Tıklanabilir satırlar** → drill-down detay sayfaları
- **Dark Mode** toggle + localStorage persist
- **Polling** ile async işlem takibi (Job, Retry, Hesaplama)
- **TVP desteği** (StkIdListType → SqlCommand ile batch SP çağrısı)

## Görev Durumu
- [x] SQL tabloları ve SP'ler (v2-production 01-13) — TÜMÜ DEPLOYED
- [x] Hangfire orchestrator
- [x] Batch strategy + benchmark + deploy (07, 09)
- [x] Ortalama maliyet (12) — tablo + SP deployed
- [x] Rapor view'ları (13) — 8 view deployed
- [x] .NET App: Lib (Db.cs, MaliyetLogger.cs, CsvExporter.cs)
- [x] .NET App: 25 sayfa (Rapor 12, Fifo 3, Islem 3, Ortalama 1, Snapshot 1, Ayar 3, Yardim 2)
- [x] Dark Mode + CSV Export + Chart.js grafikleri
- [x] Açılış optimizasyonu (14) — sp_Fifo_AcilisCalistir_V2 yazıldı
- [x] Devre dışı ürün yönetimi (15, 16) — tablo + view + SP filtre
- [x] Manuel maliyet girişi (17) — tablo + view + sayfa
- [x] 14-17 SQL deploy — DEPLOYED (2026-03-24)
- [x] Test altyapısı — fifo.sln + tests/Fifo.Tests/ (27 test, 27 geçti)
- [x] RunHistory sayfası + JobBaslat log tablosu
- [x] Connection string ortam ayrımı (Dev/Prod)
- [x] Semantik katman güncelleme
- [ ] Production deploy (ertelendi — sunucu belirsiz)
