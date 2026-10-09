# Alpha SQL Setup Flow v1

## Hedef

Bu dokuman, mevcut SQL scriptlerini alpha asamasi icin guvenli ve anlasilir bir akisa siniflandirir.

## Temel Karar

- `00_MASTER_DEPLOY_v2.sql` tek parca "hepsi bir arada" script olarak referans kabul edilir.
- Alpha asamasinda dogrudan ana calistirma scripti olarak kullanilmaz.
- Neden:
- icinde duplicate obje tanimlari var (ornegin `sp_fifo_StokMaliyetAlisKatman`)
- baseline + sprint + audit ayni dosyada karisik
- debug/tekrar calistirma davranisini ayristirmayi zorlastiriyor

## Alpha Icin Script Gruplari

### 1) Baseline (Kurulum)

Amac:
- `bkm` tablolari
- cekirdek prosedurler
- temel rapor view'lari

Kaynak:
- `00_MASTER_DEPLOY_v2.sql` icindeki baseline bolumleri (ayristirilacak)
- veya mevcut parcali scriptler:
  - `01_sp_CreateTables.sql`
  - `02_sp_RunStep.sql`
  - cekirdek SP scriptleri (su an tek dosyada daginik)

Not:
- Alpha cleanup'ta `03_sp_CoreProcedures.sql` gibi ayri bir dosya olusturulmasi onerilir.

### 2) Core Improvements (Sprint 1)

Script:
- `SQL-Improvements/01_SPRINT1_KRITIK_DUZELTMELER.sql`

Amac:
- FIFO determinism
- ERP devir fiyat yapisi duzenleme
- check constraints + FK
- `sp_fifo_StokMaliyetAlisKatman` transaction guclendirmesi

Durum:
- Alpha icin faydali ve oncelikli
- Ancak "mekan bagimsiz maliyet" varsayimi acikca kabul edilmis olmali

### 3) Audit + Kontrol (Sprint 2)

Script:
- `SQL-Improvements/02_SPRINT2_VIEWS_AUDIT.sql`

Amac:
- audit log tablosu + triggerlar
- muhasebe kontrol view'lari
- audit sorgulama view'lari
- yardimci kontrol SP'leri

Durum:
- Alpha testlerinde siddetle onerilir
- Is kurali degil, gozlemlenebilirlik katmanidir

### 4) Test Senaryosu (Gercek Veri Uzerinden Kucuk Kapsam)

Script:
- `SQL-Improvements/03_TEST_DATA_SETUP.sql`

Amac:
- secili urunlerle acilis + aylik alis + FIFO cikis akisini prova etmek
- rapor ve kontrol view'larini dogrulamak

Durum:
- Alpha icin dogru yaklasim
- Tum urun setup'i degil, odakli dogrulama scripti

### 5) Alpha Yardimci (Sentetik Fiyat/Fallback)

Script:
- `sql-alpha/04_Alpha_SentetikFallback.sql`

Amac:
- `STOK_YETERSIZ` sorunlarindan sentetik/hayali giris katmani uretmek
- satinalma sarti fiyati veya sabit fallback fiyat kullanmak

Kisit:
- Mevcut `sp_fifo_StokMaliyetFIFOCikis` ayni donemde rerun edildiginde havuz kalanlarini tekrar tuketir.
- Bu nedenle helper SP otomatik "ikinci pass" wrapper'ina baglanmamistir (alpha backlog).

Guncel Durum:
- `sql-alpha/05_Alpha_AylikRutinAlpha.sql` ile alpha wrapper eklendi.
- `sp_fifo_StokMaliyetFIFOCikis` icin ayni donem rerun-safe iyilestirmesi baslangic seviyesinde eklendi.
- Gecmise donuk rerun zincirleri (ileri aylar islendikten sonra eski ayi yeniden kosma) hala backlog kapsamindadir.

## Alpha Calistirma Sirasi (Pratik)

1. Backup / test ortamini hazirla
2. Baseline kurulum (tablolar + cekirdek SP'ler)
3. `SQL-Improvements/01_SPRINT1_KRITIK_DUZELTMELER.sql`
4. `SQL-Improvements/02_SPRINT2_VIEWS_AUDIT.sql`
5. `sql-alpha/05_Alpha_AylikRutinAlpha.sql`
6. `sql-alpha/08_Alpha_CikisMekanDestegi_Migration.sql` (lokasyon bazli raporlama isteniyorsa)
7. `SQL-Improvements/03_TEST_DATA_SETUP.sql` veya `sql-alpha/06_Alpha_E2E_Smoke_Template.sql` (dogrulama)

## Onerilen Calisma Ayrimi (Guncel)

1. Acilis calismasi:
   - `bkm.sp_fifo_AcilisCalistir`
   - ayri `calistirmaId`
2. Aylik calisma:
   - `bkm.sp_fifo_AylikCalistir` (normal)
   - veya `bkm.sp_fifo_AylikRutinAlpha` (sentetik fallback dahil)
   - ayri `calistirmaId`

Not:
- `bkm.sp_fifo_StokMaliyetCalistir` korunur ancak yeni akista legacy/uyumluluk wrapper olarak kullanilmalidir.
7. Tum urunler icin gercek acilis calistirma planina gec

## Tum Urunler Icin Gercek Akis (Mutabik Is Kuraliyla)

1. `31.12.2025` acilis havuzu olustur (`sp_fifo_StokMaliyetAcilis`)
2. Aylik rutin:
- `sp_fifo_StokMaliyetAlisKatman`
- `sp_fifo_StokMaliyetFIFOCikis`
  veya `sp_fifo_AylikRutin`
3. Maliyetsiz kalan urunler:
- sart bazli sentetik giris katmani
- son care sabit fiyat fallback
4. `fifo_StokMaliyetSorunlu` + kontrol view'lari ile izleme

## Sonraki Teknik Isler (SQL Cleanup Backlog)

1. `00_MASTER_DEPLOY_v2.sql` icinden duplicate prosedur tanimlarini temizle
2. Baseline ile improvement scriptlerini net ayir
3. Sentetik katman icin standart `kaynakTip`/`durum` sozlugu tanimla
4. Aylik "maliyetsiz urun -> sentetik giris" adimini cekirdek prosedure ekle
5. Acilista "tek seferlik sabit fiyat" fallback adimini standartlastir (alpha patch basladi)
6. FIFO cikis prosedurunu gecmise donuk rerun zincirlerinde de guvenli hale getir (havuz kalan reset/rebuild stratejisi)

## Kabul Kriteri (Bu Dokuman Icin)

- Ekip hangi scriptin ne zaman calisacagini bilir
- Alpha test/prova akisi ile gercek tum-urun akisi birbirinden ayridir
- Baseline / improvement / audit / test script rolleri nettir

