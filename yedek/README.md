# BKM FIFO Stok Maliyet Sistemi

Bu repo, perakende ortamlari icin FIFO (First-In-First-Out) stok maliyet
hesaplama sistemidir. SQL Server uzerinde calisir.

## Akis (2 katman)
1) Acilis (devir) katmani
   - Envanter tarihindeki stok miktarlari alinır.
   - ERP gecis tarihinden envanter tarihine kadar olan alislar ters
     fatura yaslandirmasi ile esitlenir.
   - Sonuc havuza ACILIS ve gerekirse ACILIS_TAMAMLA olarak yazilir.
2) Donem FIFO
   - Ay icindeki alislar ALIS olarak katmanlanir.
   - Satislar FIFO mantigi ile katmanlardan dusulur.

## Dosyalar
- `00_MASTER_DEPLOY.sql`        : Tum objeleri kurar (SQLCMD ile).
- `01_tables_and_indexes.sql`   : Tablolar ve indeksler.
- `02_sp_fifo_StokMaliyetAcilis.sql` : Acilis (devir) katmani.
- `03_sp_fifo_StokMaliyetAlisKatman.sql` : Alis katmanlari.
- `04_sp_fifo_StokMaliyetFIFOCikis.sql`  : FIFO cikis.
- `05_reporting_views.sql`      : Rapor view'lari.
- `06_sp_fifo_StokMaliyetCalistir.sql`   : Tek SP ile toplu calistirma.
- `06_manual_run.sql`           : Manuel calistirma ornegi.
- `bkm_fifo_stok_maliyet_sistemi.sql` : Tek parca deploy.
- `TEST_*.sql`                  : Test ve analiz scriptleri.

## Veri kaynaklari ve filtreler
- Envanter: `dbo.stokSonAltDepo_vw`
  - `ehAltDepo = 0`, `stok > 0`
  - Mekan filtreleri: `1, 4477, 4478` (gerekirse guncelleyin)
- Alislar: `dbo.irs`, `dbo.irsAyr`, `dbo.fatAyr`, `dbo.fat`
  - eTip: `(2,0,10,3,6,102,103)`
- Satislar: `dbo.irs`, `dbo.irsAyr`
  - eTip: `(1,4,5,100,101)`
  - eMekan: `1, 4477, 4478`

## Kurulum
### SQLCMD ile
```sql
sqlcmd -S ServerName -d DatabaseName -i 00_MASTER_DEPLOY.sql
```

### SSMS ile
SQLCMD mode acin ve:
```sql
:r 01_tables_and_indexes.sql
:r 02_sp_fifo_StokMaliyetAcilis.sql
:r 03_sp_fifo_StokMaliyetAlisKatman.sql
:r 04_sp_fifo_StokMaliyetFIFOCikis.sql
:r 06_sp_fifo_StokMaliyetCalistir.sql
:r 05_reporting_views.sql
```

## Web UI (Razor Pages)
Web arayuz `src/App` altindadir. Connection stringi guncelleyip calistirin.

```bash
cd src/App
dotnet run
```

`appsettings.json` icindeki `ConnectionStrings:FifoDb` alanini kendi ortaminiza
gore guncelleyin.

## Calistirma
### 1) Acilis (yil/ay kapanisi)
```sql
EXEC bkm.sp_fifo_StokMaliyetAcilis
    @envanterTarihi = '2025-12-31';
```

### 2) Donem alis + FIFO
```sql
EXEC bkm.sp_fifo_StokMaliyetAlisKatman
    @baslangicTarihi = '2026-01-01',
    @bitisTarihi = '2026-01-31';

EXEC bkm.sp_fifo_StokMaliyetFIFOCikis
    @satisBaslangic = '2026-01-01',
    @satisBitis = '2026-01-31';
```

### 3) Tek SP ile (job + manuel ortak)
```sql
EXEC bkm.sp_fifo_StokMaliyetCalistir
    @envanterTarihi = '2025-12-31',
    @alisBaslangic = '2026-01-01',
    @alisBitis = '2026-01-31',
    @satisBaslangic = '2026-01-01',
    @satisBitis = '2026-01-31',
    @calistirAcilis = 0; -- gece job icin
```

## Tek urun guncelleme
Alis ve FIFO cikis adimlari tek urun icin calistirilabilir.
```sql
EXEC bkm.sp_fifo_StokMaliyetCalistir
    @envanterTarihi = '2025-12-31',
    @alisBaslangic = '2026-01-01',
    @alisBitis = '2026-01-31',
    @satisBaslangic = '2026-01-01',
    @satisBitis = '2026-01-31',
    @stkID = 392,
    @calistirAcilis = 0;
```
Not: Acilis icin de `@stkID` parametresi desteklenir.

## Raporlama
- `bkm.fifo_vw_GunlukSMM`
- `bkm.fifo_vw_UrunBazliSMM`
- `bkm.fifo_vw_KatmanDurumu`
- `bkm.fifo_vw_SorunluStoklar`

## Testler
Onerilen scriptler:
- `TEST_urun_senaryo_tespit.sql` (senaryo bazli urun listeleri)
- `TEST_392_BASIT.sql` / `RAPOR_392.sql`
- `TEST_FINAL_2025.sql`

## Sorun giderme
- `bkm.fifo_StokMaliyetSorunlu` tablosunu kontrol edin.
  - `ALIS_YOK`: ilgili urun icin alis bulunamadi.
  - `ALIS_EKSIK_TAMAMLANDI`: eksik miktar son alis fiyatindan tamamlandi.
  - `STOK_YETERSIZ`: satis miktari, katman miktarini asti.
- Katman kontrolu:
```sql
SELECT * FROM bkm.fifo_StokMaliyetHavuzu WHERE stkID = 392;
```

## Notlar ve varsayimlar
- `sp_fifo_StokMaliyetAcilis` icindeki `@baslangicTarihi` ERP gecis tarihidir.
  Gerekirse bu tarihi kod icinden guncelleyin.
- Alis/FIFO prosedurleri idempotent calisir; ayni tarih araligi tekrar
  calistirilabilir.
- `miktarKalan` FIFO cikisla guncellenir.
