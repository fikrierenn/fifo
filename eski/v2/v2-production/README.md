# V2 Production (Ayrı Calisma Alani)

Bu klasor, mevcut onceki SQL-SP odakli yapidan ayri olarak **V2 production-grade** calisma alanidir.

## Hedef
- Dogru FIFO sonucu
- Tekrar calistirilabilir (rerun-safe)
- Batch/chunk performansi
- Uygulama tarafindan orkestre edilen pipeline (Hangfire)
- Gozlemlenebilirlik (run/step/log)

## Kural
- Root'a daginik yeni dosya ekleme YOK
- V2 ile ilgili tum yeni isler bu klasor altinda ilerler
- Mevcut onceki yapi korunur (referans/gercek veri testi icin)

## V2 Kapsam (Net)
1. SQL decomposition (dev SP'leri step'lere bolme)
2. Batch/chunk stratejisi (`stkID` batch)
3. Hangfire orchestration
4. Retry + timeout + idempotency standardi
5. Lokasyon bazli raporlama (`MekanId`) korunarak

## Production Kriterleri (Done Definition)
- Tum adimlar idempotent / rerun-safe
- Batch bazli calisma timeout almadan tamamlanabilir
- "Tum urunler" kosusu batch orchestrator ile yonetilir
- Hata durumunda hangi batch/adim patladi net gorulur
- SQL scriptler idempotent (index/view/constraint create hatasi vermez)
- Smoke + batch integration test checklist gecer (`11_V2_SmokeTest.sql`)

## V2 Backlog (Tek Liste)

| ID | Baslik | Oncelik | Durum | Not |
|---|---|---|---|---|
| V2-01 | V2 klasor yapisini standardize et | Yuksek | DONE | hangfire/Fifo.Hangfire.csproj + FifoJobServiceExtensions.cs (DI, Hangfire server, WorkerCount=2) |
| V2-02 | FIFO cikis "ilk fatura" sira dogrulama testini netlestir | Yuksek | DONE | 08_V2_IlkFaturaDogrulama.sql - 4 kontrol sorgusu |
| V2-03 | Aylik calisma icin hareketli urun listesi SQL | Yuksek | DONE | 07_V2_HareketliUrunListesi.sql - sp_Fifo_HareketliUrunListesi |
| V2-04 | `stkID` batchleme standardi (500/1000) | Yuksek | DONE | 09_V2_BatchOrchestration.sql - StkIdListType TVP + sp_Fifo_AylikCalistirBatch |
| V2-05 | Batch runner SQL/.NET sozlesmesi | Yuksek | DONE | FifoBatchRun/Detay/Hata tablolari + hangfire/FifoAylikJob.cs sozlesmesi |
| V2-06 | Acilis fallback agir adimini ayri pipeline'a al | Yuksek | DONE | hangfire/FifoAcilisJob.cs - 2-phase: fast pass + ALIS_YOK kuyruk |
| V2-07 | `fn_SonGecerliFiyat_Adv` materialize optimizasyonu | Yuksek | DONE | 02_V2_CoreProcedures.sql - OUTER APPLY kaldirildi, #fiyatMaterialize + cursor |
| V2-08 | Hangfire orchestrator iskeleti (.NET) | Yuksek | DONE | hangfire/FifoAylikJob.cs + StkIdTvp.cs + FifoJobOptions.cs |
| V2-09 | Polly retry matrix | Orta | DONE | hangfire/FifoRetryPolicy.cs - deadlock/timeout/transient pipeline |
| V2-10 | Run/Step observability standardi | Orta | DONE | hangfire/Program.cs - Serilog bootstrap + Hangfire dashboard (/hangfire) + appsettings.json |
| V2-11 | Sprint1/Sprint2 scriptlerini idempotent hale getirme | Yuksek | DONE | SQL-Improvements CREATE INDEX IF NOT EXISTS kontrolleri eklendi |
| V2-12 | Tum urun batch benchmark ve tuning | Yuksek | DONE | 10_V2_BenchmarkScript.sql - 5 bolum: timing/IO/CPU, tek urun, batch karsilastirma (50/250/500), tablo boyutu, run ozeti |

## Deploy Sirasi
1. `00_V2_Master_Deploy.sql` — tum V2 nesnelerini kur
2. `11_V2_SmokeTest.sql` — nesne varlik + idempotency + roundtrip dogrulama
3. `10_V2_BenchmarkScript.sql` — sure/IO/CPU olcumu (gercek veri)
4. Hangfire host'u ayaga kaldir: `dotnet run --project hangfire/Fifo.Hangfire.csproj`
5. Dashboard: `http://localhost:5000/hangfire`

## Sonraki Adim
**V2 Backlog + Build + Smoke Test tamamen tamamlandi.** Proje production deploy'a hazir.
