# SQL Alpha Script Set

Bu klasor, `00_MASTER_DEPLOY_v2.sql` icinden alpha asamasi icin ayrilan cekirdek scriptleri icerir.

## Amac

- Tek parca master script bagimliligini azaltmak
- Baseline kurulum ile improvement scriptlerini ayirmak
- Alpha test/prova akisini daha okunur hale getirmek

## Icerik

- `00_Alpha_Install_All.sql`
  - SQLCMD Mode ile tum alpha SQL scriptlerini tek seferde include eder
- `01_Baseline_Tables.sql`
  - `bkm` schema
  - cekirdek tablolar ve indexler
- `02_Baseline_CoreProcedures.sql`
  - `sp_fifo_StokMaliyetAcilis`
  - `sp_fifo_StokMaliyetAlisKatman` (master scriptteki ilk versiyon)
  - `sp_fifo_StokMaliyetFIFOCikis`
  - `sp_fifo_CalistirmaAdim`
  - `sp_fifo_StokMaliyetCalistir` (legacy/uyumluluk wrapper)
  - `sp_fifo_AcilisCalistir` (onerilen acilis wrapper)
  - `sp_fifo_AylikCalistir` (onerilen aylik wrapper)
  - `sp_fifo_AylikRutin`
- `03_Baseline_BasicViews.sql`
  - temel raporlama view'lari (`fifo_vw_*`)
- `04_Alpha_SentetikFallback.sql`
  - `sp_fifo_SentetikAlisKatmanOlustur`
  - `STOK_YETERSIZ` sorunlarindan sart/sabit fiyatla `SENTETIK_ALIS` katmani uretir
  - FIFO cikisini otomatik tekrar hesaplamaz
- `05_Alpha_AylikRutinAlpha.sql`
  - aylik alis + fifo cikis + sentetik fallback + fifo rerun akisini tek wrapper'da toplar
- `06_Alpha_E2E_Smoke_Template.sql`
  - acilis + aylik alpha wrapper icin smoke test template

## Alpha Calistirma Sirasi (Onerilen)

1. `sql-alpha/00_Alpha_Install_All.sql` (SQLCMD Mode) veya `01..05` tek tek
2. `SQL-Improvements/01_SPRINT1_KRITIK_DUZELTMELER.sql`
3. `SQL-Improvements/02_SPRINT2_VIEWS_AUDIT.sql`
4. `SQL-Improvements/03_TEST_DATA_SETUP.sql` (test/prova) veya `sql-alpha/06_Alpha_E2E_Smoke_Template.sql`

## Onerilen Kullanim (Guncel)

1. Tek seferlik acilis icin:
   - `bkm.sp_fifo_AcilisCalistir`
2. Aylik normal akis icin:
   - `bkm.sp_fifo_AylikCalistir`
3. Aylik + sentetik fallback akisi icin:
   - `bkm.sp_fifo_AylikRutinAlpha`

Not:
- `bkm.sp_fifo_StokMaliyetCalistir` hala mevcuttur ancak yeni akista daha cok geri uyumluluk/yardimci wrapper olarak dusunulmelidir.

## Notlar

- Bu klasor "alpha cleanup" icin ara adimdir.
- Sonraki adimda `sp_fifo_StokMaliyetAlisKatman` duplicate tanimi tamamen temizlenmelidir.
- Sentetik katman (`SENTETIK_ALIS`) ve sabit fiyat fallback mantigi alpha ek scriptleriyle uygulanmistir (`04`, `05`).
- `sp_fifo_StokMaliyetAcilis` icin `@sabitFallbackBirimMaliyet` alpha patch'i uygulanmistir.
- Aylik sentetik katman helper'i ve alpha wrapper mevcuttur.
- `sp_fifo_StokMaliyetFIFOCikis` icin ayni donem rerun-safe iyilestirmesi alpha seviyesinde eklenmistir; gecmise donuk (uzak donem) rerun senaryolari ayrica ele alinmalidir.

