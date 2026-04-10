# CHAT_LOG

## Oturum Ozeti (FIFO Stok Maliyet)

### Kapsam
- FIFO stok maliyetleme icin iki katman netlesti: (1) acilis/devir (envanter tarihine gore ters fatura yaslandirma) + (2) ay icindeki alislar ve FIFO cikis maliyetleme (2026 icin).
- Stok envanteri mekan bazli; maliyet hesaplama mekanlardan bagimsiz olacak sekilde tasarlaniyor.

### Yapilanlar
- SQL objeleri tek dosyada toplandi: `00_MASTER_DEPLOY.sql` icine tum tablolar, indeksler, SP ve view'lar alindi.
- Obje isimleri `bkm` semasi ve `fifo_` on eki ile standardize edildi.
- Havuz tablosuna `belgeTarihi` ve `firmaID` alanlari eklendi.
- Zaman cizgisi/akim takibi icin `bkm.fifo_Run` ve `bkm.fifo_RunStep` tablolari + `bkm.sp_fifo_RunStep` SP eklendi; acilis/alis/cikis SP'lerine `@runId` baglandi.
- `TEST_urun_senaryo_tespit.sql` icinde senaryo tespiti, stok snapshot ve merkez depo dahil etme opsiyonlari eklendi; aggregate + subquery hatasi JOIN ile duzeltildi.
- Kodlama/encoding kaynakli Turkce karakter sorunlari giderildi.

### Acilis Katmani Akisi (SP)
- Envanter: `stokSonAltDepo_vw` uzerinden mekan (1,4477,4478) stoklari cekiliyor ve `bkm.fifo_StokEnvanter` yaziliyor.
- Alislar: `irs/irsAyr/fat/fatAyr` ile tarih araligindan alislar cekiliyor, birim maliyet hesaplanip `bkm.fifo_StokMaliyetHavuzu` icin ACILIS katmanlari uretiliyor.
- Eksik miktar: Son alis fiyatiyla `ACILIS_TAMAMLA` yaziliyor, sorunlara log dusuluyor.

### Merkez Depo Tamamlama
- Alisi olmayan urunler icin merkez depo (mekan 12) son alis fiyatina bakilip tamamlama eklendi.
- Sonuc loglari: `ALIS_YOK_MERKEZ_TAMAMLANDI`, `ALIS_YOK`, `ALIS_EKSIK_TAMAMLANDI` sayilari raporlandi.

### UI / Uygulama
- Tailwind tabanli admin panel gorunumu ve menu ayrimlari istendi.
- "Calistir" aksiyonu icin timeline/panel gorunum fikri eklendi.
- Dapper sorgusu zaman asimina dustu (Issues sayfasi).

### Acik Konular / Sonraki Adimlar
- Alisi olmayanlar icin ikinci fallback: `bkm.fn_SonGecerliFiyat(tarih, 1)` kullanimi; `fTur=1` alis, `fTur=0` satis; `sonrakiNet` alaninin maliyet icin yeterli oldugu not edildi.
- Satin alma sarti / fiyat turu (fTur) parametresi netlestirildi; gerekli tablo/parametre baglantisi eklenecek.
- Sabit maliyet tablosu ile kalanlarin tamamlama kuralini tasarlama.
- Performans iyilestirme: buyuk calistirmalarda timeout ve indeks stratejileri.

---

Not: Bundan sonraki degisiklik ve kararlar bu dosyanin sonuna "Yeni Kayit" olarak eklenecek.

## Yeni Kayit
- Kullanicinin talebi: Chat yazismalari Turkce (ASCII) olarak bu dosyada loglansin ve her oturumda sona ekleme yapilsin.
- Satin alma sarti / fiyat turu netlesmesi: `fTur=1` alis fiyatlarini, `fTur=0` satis fiyatlarini getirir.
- Acilis/ek tamamlama icin `bkm.fn_SonGecerliFiyat(tarih, 1)` sonucu yeterli; `sonrakiNet` alaninin maliyet icin yeterli oldugu belirtildi.
- Onay: Kullanici "1" diyerek son yaklasimi onayladi.
- Yeni oturum: Master deploy canonical kabul edildi, prosedur/view tanimlari CREATE OR ALTER yapildi, transactional SP'lere SET XACT_ABORT ON eklendi, CATCH bloklarinda THROW kullanildi.
- Aylik devir ve fiyatlama bloklari ile tarih sinirlarinda DATEADD(DAY,1, ...) kullanildi; sabit fiyat fallback icin bkm.fifo_SabitFiyat tablosu eklendi; FIFO cikis filtrelerinden yazilmayan kaynakTip degerleri cikartildi.
- 00_MASTER_DEPLOY.sql ile 01/02/03/04/05/06 dosyalari ve bkm_fifo_stok_maliyet_sistemi.sql senkronlandi; ornek tarih formatlari dd.MM.yyyy yapildi, 06_manual_run.sql guncellendi.
- Yeni oturum: CREATE OR ALTER batch hatasi icin master deploy'a PRINT bloklarindan sonra GO eklendi ve bkm_fifo_stok_maliyet_sistemi.sql yeniden senkronlandi.
- Yeni oturum: DOGRULAMA_tek_urun.sql tarih araligi DATEFROMPARTS ile alindi, tarih filtreleri inclusive/exclusive yapildi, alis tipleri/mekan filtreleri ve ozet katman listesi guncellendi.
