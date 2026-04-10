# AI Refactoring Prompt v2 (Repo-Ozel): SQL-Centric FIFO -> Data-Driven Pipeline (Hangfire)

## Amac
Mevcut SQL-odakli FIFO maliyet sistemini, sonucu bozmadan adim adim .NET tarafindan orkestre edilen bir pipeline mimarisine donustur.

## Proje Baglami (Bu Repo Icin Zorunlu Gercekler)

- Mevcut sonuc tablolari korunacak:
  - `bkm.fifo_StokMaliyetHavuzu`
  - `bkm.fifo_StokMaliyetCikis`
  - `bkm.fifo_StokMaliyetSorunlu`
- Mevcut is modeli:
  - Acilis havuzu: `31.12.2025`
  - Aylik akis: `ALIS` -> `FIFO CIKIS` -> gerekirse `SENTETIK_ALIS` -> rerun
- Maliyet modeli:
  - Su an `mekan bagimsiz ortak maliyet`
- Raporlama ihtiyaci:
  - `fifo_StokMaliyetCikis` icinde `hareketMekanID` (lokasyon bazli raporlama)
- Fallback oncelik sirasi:
  1. Gercek alis
  2. Son gecerli fiyat
  3. Sart/ERP devir fiyati
  4. Sentetik giris (hayali evrak)
  5. Sabit fallback fiyat

## Mevcut Problem

- Is mantigi dev sakli yordamlarda (`sp_fifo_StokMaliyetAcilis`, `sp_fifo_StokMaliyetFIFOCikis`, vb.)
- Timeout ve uzun calisma riskleri yuksek
- Adim bazli izleme DB tablosuna manuel yaziliyor, merkezi orkestrasyon yok
- Hata izolasyonu zor (tek SP icinde cok fazla sorumluluk)
- Idempotency ve rerun davranislari adim bazinda standardize degil

## Hedef Mimari (V2)

### 1) Strangler Yaklasimi (Big-Bang Rewrite YOK)
- Ilk fazda SQL sonuc tablolarini degistirme.
- Mevcut SP mantigini atomik SQL step'lere parcala.
- Orkestrasyonu .NET + Hangfire'a tası.
- Sonraki fazda istenirse hesaplama motorunun bir kismi C#'a alinabilir.

### 2) Data-Driven Pipeline
- Her adim:
  - acik bir input araligi / parametre seti alir
  - tek bir sorumluluk tasir
  - idempotent (veya acikca rerun stratejisi tanimli) olur
- Adimlar .NET tarafinda Hangfire job zinciri ile yonetilir

### 3) Observability
- Hangfire dashboard + Serilog + app metrics
- Her adim icin:
  - baslama/bitis
  - sure
  - attempt no
  - sonuc (basarili/hata/atlandi)
  - hata mesaji
- Mevcut `bkm.fifo_Calistirma` / `bkm.fifo_CalistirmaAdim` tablolari ilk fazda reuse edilebilir

## AI'dan Beklenen Cikti (Kesin Kapsam)

### Adim 1: SQL Ayrıştırma (Decomposition)
Asagidaki sakli yordamlari analiz et ve atomik adimlara bol:

- `bkm.sp_fifo_StokMaliyetAcilis`
- `bkm.sp_fifo_StokMaliyetAlisKatman`
- `bkm.sp_fifo_StokMaliyetFIFOCikis`
- `bkm.sp_fifo_SentetikAlisKatmanOlustur`

Her atomik adim icin su formatta cikti ver:
- `StepName`
- `Amac`
- `Input` (parametreler + okunan tablolar)
- `Output` (yazilan tablolar)
- `Idempotency stratejisi` (replace-in-range / upsert / append+version)
- `Transaction boundary`
- `Failure mode`

### Adim 2: Pipeline Tanimi (.NET + Hangfire)
.NET tarafinda su arayuzleri ve roller tasarla:

- `IFifoPipelineService`
- `IFifoStepExecutor`
- `ISqlStepCatalog` (step script/command registry)
- `IFifoRunRepository` (run/step status persistence)

Hangfire job zinciri tanimla:
- Acilis pipeline (`AcilisCalistir`)
- Aylik pipeline (`AylikCalistir`)
- Aylik alpha pipeline (`AylikRutinAlpha`)

Not:
- Hangfire Pro yokmus gibi alternatif sun.
- `ContinueWith` ile lineer chain, gerekirse custom state machine tasarla.

### Adim 3: Hata ve Retry Politikasi
Polly ile adim bazli retry politikasi tasarla:
- Deadlock (`1205`) retry
- Timeout retry (sinirli)
- Validation/constraint hatalarinda retry YOK

Acikca belirt:
- Hangi hatalar transient
- Hangi hatalar business/data error
- Pipeline durdurma/atlama/uyari stratejisi

### Adim 4: Transaction Standardi
Asagidaki karari netlestir ve uygula:
- Long-running global transaction YOK
- Step-level transaction VAR
- Her step rollback-safe
- Rerun-safe tasarim zorunlu

### Adim 5: Kod Uretimi (Ilk Faz Uygulama)
Bu repo icin ornek kod uret:
- `FifoOrchestrator`
- `FifoPipelineService`
- `SqlStepExecutor` (Dapper)
- Hangfire registration
- Serilog enrichment (`runId`, `stepName`)
- Polly policy configuration

### Adim 6: Migration Plan (Strangler)
3 fazli plan ver:
- Faz 1: SQL SP decomposition + .NET orchestration
- Faz 2: Step output/staging standardization
- Faz 3: Kritik hesap adimlarinin C#'a alinmasi (opsiyonel)

## Teknik Sinirlar / Kurallar

- Sonuc semantiklerini bozma (mevcut FIFO sonuc tablolari ile uyumlu kal)
- Ilk fazda sadece orchestration + decomposition
- Her adim icin test edilebilir SQL contract tanimla
- Adimlar tekrar calistirildiginda veri bozulmasin
- Lokasyon bazli raporlama ihtiyaci korunmali (`hareketMekanID`)

## Kullanilacak Teknolojiler

- .NET 8/9
- Dapper
- Hangfire
- Serilog
- Polly

## Beklenen Teslimatlar (AI Cevabinda)

1. Mimari diyagram (metinsel)
2. Step listesi (decomposed SQL map)
3. Hangfire pipeline akisi
4. Retry/error strategy matrix
5. Ornek kod (C#)
6. SQL step ornekleri
7. Migration roadmap (fazli)

---

## TODO Tablosu (Uygulama Backlog)

| ID | Baslik | Faz | Oncelik | Durum | Cikti / Definition of Done |
|---|---|---|---|---|---|
| T01 | SP Envanter Cikartma Step'ini ayristir | Faz 1 | Yuksek | TODO | `Acilis` icindeki envanter snapshot adimi bagimsiz SQL step olarak calisir |
| T02 | SP Alis Toplama Step'ini ayristir | Faz 1 | Yuksek | TODO | Acilis ve aylik alis adimlari atomik SQL step olarak ayrilir |
| T03 | SP Ters FIFO Katman Step'ini ayristir | Faz 1 | Yuksek | TODO | Acilis katman hesaplama ayri step olur, input/output tanimi yazilir |
| T04 | SP Sorun/Fallback Step'lerini ayristir | Faz 1 | Yuksek | TODO | Merkez/son fiyat/ERP/sabit fallback adimlari ayrilir |
| T05 | FIFO Cikis step decomposition | Faz 1 | Yuksek | TODO | `FIFOCikis` icindeki satis-toplama / eslestirme / yazma / kalan guncelleme adimlari ayrisir |
| T06 | Step catalog (SQL komut kayitlari) | Faz 1 | Yuksek | TODO | .NET tarafinda `ISqlStepCatalog` ile step->sql map tanimlanir |
| T07 | `IFifoPipelineService` tasarimi | Faz 1 | Yuksek | TODO | Acilis/Aylik/AylikAlpha metot imzalari netlesir |
| T08 | Hangfire lineer pipeline iskeleti | Faz 1 | Yuksek | TODO | Acilis ve aylik zincirleri Hangfire ile calisir |
| T09 | `runId/stepId` standardi | Faz 1 | Yuksek | TODO | `fifo_Calistirma` ve `fifo_CalistirmaAdim` kullanimi standardize edilir |
| T10 | Polly retry policy matrix | Faz 1 | Yuksek | TODO | SQL timeout/deadlock vs business error ayrimi kodlanir |
| T11 | Serilog enrichment (`runId`, `stepName`) | Faz 1 | Orta | TODO | Loglarda pipeline izlenebilirligi saglanir |
| T12 | Step-level transaction standardi | Faz 1 | Yuksek | TODO | Her SQL step rollback-safe ve idempotent strateji dokumante edilir |
| T13 | `AylikRutinAlpha` .NET orchestrator | Faz 1 | Yuksek | TODO | `ALIS -> CIKIS -> SENTETIK -> RERUN` zinciri uygulama tarafinda yonetilir |
| T14 | Smoke test pipeline komutu | Faz 1 | Orta | TODO | Tek urun smoke test .NET tarafindan tetiklenebilir |
| T15 | Staging tablo standardi (`bkm_work.*`) tasarimi | Faz 2 | Orta | TODO | Temp tablo bagimliligi azaltma plani cikartilir |
| T16 | Rerun-safe strategy review (backdated rerun) | Faz 2 | Yuksek | TODO | Gecmise donuk rerun davranisi netlestirilir |
| T17 | Parallelization opportunities (mekan/depo bazli) | Faz 2 | Orta | TODO | Hangi adimlar paralellesebilir analizi tamamlanir |
| T18 | C# FIFO engine feasibility spike | Faz 3 | Dusuk | TODO | SQL'den C#'a tasinabilecek adimlar ve risk analizi raporlanir |

