# Performance Strategy v1: Tum Urunlerde Uzun Sureyi Azaltma (Batch + Hybrid)

## Problem Ozeti

Tum urunlerde acilis/aylik FIFO calistirildiginda sure ciddi uzuyor.
Ozellikle asagidaki bolumler pahali:

- `sp_fifo_StokMaliyetAcilis` icindeki fallback/sorun adimi
- `#aylikAlloc` + `fn_SonGecerliFiyat_Adv(...)` kullanan aylik devir fallback
- `sp_fifo_StokMaliyetFIFOCikis` tum urunlerde buyuk temp + window hesaplari

## Hedef

- SQL mantigini tamamen bozmeden performansi iyilestirmek
- Timeout riskini azaltmak
- Hata izolasyonu ve tekrar denemeyi kolaylastirmak
- Hangfire ile paralel/seri orkestrasyona uygun hale getirmek

## Ana Strateji (Onerilen)

1. **Chunked Set-Based Calisma (Temel Cozum)**
- Tum urunler yerine `stkID` batch'leri ile calistir
- Ornek batch boyutu: `250`, `500`, `1000` (ortama gore)
- Her batch ayri `runId` / job olabilir

2. **Hybrid Yaklasim (Sadece Tail/Exception icin)**
- Ana akis set-based kalsin
- Yalnizca en pahali ve kucuk kalan fallback grubu icin (gerekiyorsa) `FAST_FORWARD` cursor

3. **Precompute / Materialize**
- Pahali fonksiyon sonucunu (`fn_SonGecerliFiyat_Adv`) satir bazli tekrar cagirmak yerine
- once aday urun listesi icin materialize et (staging/temp)
- sonra join ile kullan

4. **Incremental Urun Listesi**
- Tum urunler yerine:
  - ilgili ay hareket goren urunler
  - sorunlu kaydi olan urunler
  - sentetik/fallback etkilenen urunler

## Neden Cursor Degil?

- Cursor tum veride kullanildiginda toplam sureyi daha da uzatabilir
- Transaction ve lock davranisini kotulestirebilir
- Yeniden deneme / idempotency zorlasir

**Ne zaman olabilir?**
- Sadece "zor kalan kucuk kuyruk" (tail) icin
- Ornek: `#eksikKalan` < 5000 ve fonksiyon/case bazli hesap pahali ise

---

## Batch Calistirma Tasarimi (SQL Seviyesi)

### Yontem A (En basit): Uygulama tarafi urun listesi dagitirir
- .NET tarafi `stkID` listesini batch'lere boler
- Her batch icin mevcut SP'ler `@stkID` tekli/tekrarlı cagrilir
- Dezavantaj: tekli calistirma cok artarsa overhead olur

### Yontem B (Onerilen): Batch tablosu + range cagrisi
- `bkm_work.FifoBatchUrun` gibi bir staging tablo
- `runId`, `batchNo`, `stkID`
- SP'ler `@runId`, `@batchNo` ile calisir ve urun filtresini tablodan alir

Bu repo icin Faz 1'de minimal degisiklikle:
- Uygulama tarafinda batch listesi olustur
- Her `stkID` icin degil, **batch bazli temp/staging** kullan

---

## Ornek SQL: Batch Urun Listesi Uretimi (Aylik)

Asagidaki mantik aylik calisacak urunleri daraltmak icin kullanilabilir:

```sql
DECLARE @yil INT = 2026;
DECLARE @ay INT = 1;
DECLARE @ayBas DATE = DATEFROMPARTS(@yil, @ay, 1);
DECLARE @ayBit DATE = EOMONTH(@ayBas);

;WITH Hareketli AS (
    SELECT DISTINCT a.ehStkID AS stkID
    FROM DerinSISBkm.dbo.fatAyr a WITH(NOLOCK)
    JOIN DerinSISBkm.dbo.fat f WITH(NOLOCK) ON f.eID = a.ehID
    WHERE f.eTarihS >= @ayBas AND f.eTarihS < DATEADD(DAY, 1, @ayBit)
      AND f.eTip IN (0,2)
    UNION
    SELECT DISTINCT dt.ehStkID AS stkID
    FROM DerinSISBkm.dbo.irs bs WITH(NOLOCK)
    JOIN DerinSISBkm.dbo.irsAyr dt WITH(NOLOCK) ON dt.ehID = bs.eID
    WHERE bs.eTarihS >= @ayBas AND bs.eTarihS < DATEADD(DAY, 1, @ayBit)
      AND bs.eTip IN (1,4,5,100,101)
      AND bs.eMekan IN (1,12,4477,4478)
    UNION
    SELECT DISTINCT s.stkID
    FROM bkm.fifo_StokMaliyetSorunlu s
    WHERE s.envanterTarihi = @ayBit
)
SELECT
    h.stkID,
    ROW_NUMBER() OVER (ORDER BY h.stkID) AS rn,
    ((ROW_NUMBER() OVER (ORDER BY h.stkID) - 1) / 500) + 1 AS batchNo
FROM Hareketli h
ORDER BY h.stkID;
```

Bu sonucu .NET tarafi okuyup Hangfire batch zinciri kurabilir.

---

## Hangfire Batch / Job Orchestration (Onerilen)

## Aylik Pipeline (Tum urunler yerine batch)

1. `BuildMonthlyProductBatchListJob(yil, ay)`
2. Her `batchNo` icin:
   - `RunMonthlyBatchJob(yil, ay, batchNo)`
3. Sonunda:
   - `RunMonthlyValidationJob(yil, ay)`

### `RunMonthlyBatchJob` icinde (lineer)
- `sp_fifo_StokMaliyetAlisKatman` (batch urunleri)
- `sp_fifo_StokMaliyetFIFOCikis` (batch urunleri)
- gerekirse `sp_fifo_SentetikAlisKatmanOlustur`
- rerun `sp_fifo_StokMaliyetFIFOCikis`

## Acilis Pipeline (Tum urunler)

Acilis daha zor oldugu icin 2 secenek:

### Secenek 1 (Kisa vadeli, guvenli)
- Acilis tek akista ama `@atlamaAylikDevir=1`
- Sonra fallback gereken urunler icin ayri batch pipeline

### Secenek 2 (Orta vadeli, daha iyi)
- Acilis step decomposition + batch execution
- `Envanter`, `Alis`, `Ters FIFO`, `Fallback` ayri job/step

---

## Hemen Uygulanabilecek Kisa Vadeli Iyilestirmeler

1. **Smoke / testlerde tek urun + `@atlamaAylikDevir = 1`**
2. **Tum urunler icin tek geciste degil, `stkID` batch**
3. **Aylik pipeline'da sadece hareketli urunler**
4. **Pahali fallback adimini ayri kosu yap**

---

## Teknik Tasarim Notlari

### Idempotency
- Batch bazli calismada `replace-in-range` mantigi korunabilir
- Her batch kendi `stkID` setiyle sinirli `DELETE + INSERT` yapmali

### Transaction
- Global transaction yok
- Step-level transaction var
- Batch-level timeout configurable olmali

### Concurrency
- Ayni `stkID` iki batch'te olmamali
- Batch overlap engellenmeli
- Hangfire concurrency limiti verilmeli (orn. `WorkerCount` / queue bazli)

### Gozlemlenebilirlik
- Her batch icin:
  - `runId`
  - `batchNo`
  - `urunSayisi`
  - sure
  - hata

---

## TODO Tablosu (Performans Backlog)

| ID | Baslik | Oncelik | Durum | Aciklama |
|---|---|---|---|---|
| P01 | Aylik hareketli urun listesi SQL'i | Yuksek | TODO | Aylik calisacak urunleri tum urunler yerine daralt |
| P02 | `stkID` batchleme standardi | Yuksek | TODO | Batch boyutu + batchNo uretim kurali netlestir |
| P03 | Hangfire batch job zinciri | Yuksek | TODO | `BuildBatchList -> RunBatch -> Validate` akisi |
| P04 | Acilis fallback agir adimini ayirma | Yuksek | TODO | `@atlamaAylikDevir=1` + sonradan fallback batch |
| P05 | `fn_SonGecerliFiyat_Adv` materialize denemesi | Yuksek | TODO | Satir bazli OUTER APPLY yerine precompute benchmark |
| P06 | Batch overlap/lock stratejisi | Orta | TODO | Ayni urunun iki job tarafindan islenmesini engelle |
| P07 | Batch-level timeout/retry politikasi | Orta | TODO | Polly + Hangfire retry sinirlari |
| P08 | Tail fallback icin hybrid cursor spike | Dusuk | TODO | Sadece kucuk kalan urun grubu icin feasibility |

