---
name: fifo-sql-developer
description: >
  FIFO maliyet sistemi için T-SQL yazma/revize etme disiplini. Stored procedure, view,
  TVF, tablo DDL veya deploy scripti yazarken, değiştirirken ya da review ederken
  tetiklenir. "SP yaz", "şu SP'yi düzelt", "deploy scripti", "constraint ekle",
  "bu SQL doğru mu", "performans", "hata yönetimi", "idempotent script", "master
  deploy" ifadelerinde devreye gir. Yazım standardı + zorunlu şablonlar + reddedilen
  kalıplar + FIFO'ya özgü değişmezler. Kod ÜRETİR (fifo-danisman karar verir,
  sql-sp-reviewer denetler, bu skill yazar).
---

# FIFO SQL Developer

Bu projede T-SQL yazan kişinin kural kitabı. Muhasebe defteri yazıyorsun, rapor sorgusu değil.
Sessiz yanlış sonuç, gürültülü hatadan **çok daha pahalı**. Şüphede kal, patlat, yut**ma**.

---

## 0. Yazmadan Önce
1. İlgili SP'yi OKU. Memory ve doküman kanıt değil, **kaynak kod otoritedir**.
2. Değişmezi (invariant) belirle: bu kodun bozamayacağı şey ne.
3. O değişmez **veritabanında zorlanabiliyor mu** diye sor. Zorlanabiliyorsa CHECK/FK/UNIQUE ile
   zorla. Checklist'e veya doğrulama sorgusuna bırakmak son çare.
4. Değiştirdiğin şeyin geçmiş dönemi yeniden hesaplatıp hesaplatmadığını söyle.

---

## 1. Zorunlu SP İskeleti

```sql
CREATE OR ALTER PROCEDURE dbo.sp_Fifo_Ornek
    @EnvanterTarihi DATE,
    @StkId          INT = NULL,
    @IslemId        UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Parametre dogrulamasi: sessiz yanlis sonuc yerine erken patla
    IF @EnvanterTarihi IS NULL
        THROW 50001, 'sp_Fifo_Ornek: @EnvanterTarihi zorunlu.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- is...

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        -- Hata bilgisi SADECE CATCH icinde okunur. Bloktan cikinca NULL doner.
        DECLARE @ErrMsg  NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrLine INT            = ERROR_LINE();

        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId=@IslemId, @AdimKodu='hata',
                 @AdimAdi='Hata', @SiraNo=999, @Durum='HATA', @Mesaj=@ErrMsg;

        THROW;   -- orijinal hata numarasi/severity/state korunur
    END CATCH
END
GO
```

### Hata yönetimi kuralları
- **`THROW;` kullan, `RAISERROR` kullanma.** `RAISERROR` orijinal hata numarasını 50000'e çevirir.
- **`GOTO` ile CATCH bloğundan çıkma.** `ERROR_MESSAGE()`, `ERROR_LINE()`, `ERROR_SEVERITY()`,
  `ERROR_STATE()` CATCH dışında **NULL** döner. Ortak hata bloğu istiyorsan değerleri CATCH
  içinde değişkene al, sonra atla.
- `'metin ' + @ErrMsg` yazma. `@ErrMsg` NULL ise **tüm metin NULL** olur ve log boş kaydedilir.
  `CONCAT()` veya `ISNULL(@ErrMsg, '<hata metni alinamadi>')` kullan.
- Boş CATCH veya sadece log yazıp devam eden CATCH = sessiz hata. Yasak.

### Transaction kuralları
- Bir SP tek mantıksal iş yapıyorsa **tek transaction**. Fazlara bölüyorsan yarım kalma
  senaryosunu ve temizleme yolunu **yorumda yaz**, yoksa bölme.
- `SET XACT_ABORT ON` her zaman. `@@TRANCOUNT` kontrolü olmadan `ROLLBACK` çağırma.

---

## 2. Deploy Scripti Kuralları (en kritik başlık)

**Üretimde çalışacak bir script asla veri kaybettirmez.** Bu tek cümle en pahalı hatayı önler.

| Amaç | Doğru kalıp |
|---|---|
| Tablo | `IF OBJECT_ID('dbo.X','U') IS NULL CREATE TABLE ...` |
| Index | `IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE ...) CREATE INDEX ...` |
| Kolon | `IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE ...) ALTER TABLE ... ADD ...` |
| Constraint | `IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE ...) ALTER TABLE ... ADD CONSTRAINT ...` |
| SP / View / TVF | `CREATE OR ALTER` |
| Seed | `INSERT ... WHERE NOT EXISTS (...)` |

- **`DROP TABLE` üretim scriptine girmez.** Yıkıcı sıfırlama ayrı, adında `RESET` geçen,
  master'a dahil edilmeyen dosyada durur ve açık onay değişkeni ister.
- **`MERGE` yasak.** `DELETE` + `INSERT` kullan.
- Constraint sıkılaştırırken önce ihlal var mı bak. Varsa script'i patlatma, uyar ve
  constraint'i `NOCHECK` bırakma. İhlali raporla, veri düzeltilsin.
- İkinci kez çalıştırınca fark üretmiyorsa idempotenttir. "CREATE OR ALTER var" demek yetmez,
  DDL'in tamamına bak.

---

## 3. Sorgu Yazım Kuralları

- **`SELECT *` yasak**, `SELECT * INTO #temp` dahil. Kolon eklendiğinde `INSERT ... EXEC`
  ve arayan taraf sessizce kırılır. Bu projede bir kez oldu, `04_V2` DryRun.
- **`NOLOCK` yeni kodda yasak.** Mevcut SP'lerdeki kullanımlar bilinçli korunuyor, gerekçe:
  canlı ERP tablolarını uzun maliyet koşusu boyunca kilitlememek. Yeni okuma eklerken NOLOCK
  ekleme; kaynak tarafta snapshot izolasyonu doğru çözüm.
- **SARGable yaz.** İndeks kolonuna fonksiyon uygulama.
  Yanlış: `WHERE CAST(ehTrhS AS DATE) = @d`
  Doğru: `WHERE ehTrhS >= @d AND ehTrhS < DATEADD(DAY,1,@d)`
- **Cursor / WHILE son çare.** Set-based yaz. Parametreli TVF'yi tarih listesiyle çağırmak
  gerekiyorsa `CROSS APPLY` kullan.
- Temp tabloyu doldurduktan **hemen sonra** indeksle, join kolonlarına göre.
- Bölme varsa `NULLIF(payda, 0)`. Sıfıra bölme tüm sorguyu düşürür ve sessiz boş çıktı bırakır.
- `TRY_CONVERT` kullan, `CONVERT` ile veri tipi kumarı oynama.

### Para ve miktar tipleri
| Alan | Tip |
|---|---|
| Birim maliyet / fiyat | `DECIMAL(18,6)` |
| Miktar | `DECIMAL(18,4)` |
| Tutar | `DECIMAL(18,4)` |
| Hesaplanan tutar | `AS (Miktar * BirimMaliyet) PERSISTED` |

`FLOAT` ve `MONEY` **yasak**. Yuvarlama hatası maliyet defterinde birikir.

---

## 4. FIFO'ya Özgü Değişmezler

Bunları bozan kod yanlıştır, ne kadar hızlı olursa olsun.

1. **Ortak havuz.** Maliyet mekan-bağımsız: `PARTITION BY StkId`, mekan yok.
   Havuz seti `ehMekan IN (1,12,4477,4478)` + `ehAltDepo = 0`.
   Açılış, çıkış ve ortalama **aynı seti** kullanır. Birini değiştiren üçünü değiştirir.
   Mekan 12 ana depodur, dışlanmaz.
2. **`BirimMaliyet > 0`.** Stoğu olan katman pozitif maliyet taşır. Sıfır maliyet, yüzde yüz
   marj demektir ve mali tabloyu sessizce bozar. Fallback zincirinde sıfır fiyatlı kaynak
   "bulunamadı" sayılır, sonraki kademeye geçilir.
3. **Katman defteri mutabakatı.** `FifoKatman.GirisMiktar - SUM(FifoCikisDetay.Miktar) = KalanMiktar`.
   `KalanMiktar` doğrudan güncellenecekse aynı transaction içinde çıkış satırı da yazılır.
4. **Çıkış birim maliyeti katmanın birim maliyetidir.** Yeniden hesaplanmaz, kopyalanır.
5. **Rerun-safe.** Dönem yeniden işlenirken sıra: çıkışı geri al, katmanı sil, alışı yaz,
   satışı işle. Ters sıra `FK_FifoCikisDetay_FifoKatman` ihlali verir.
6. **Devre dışı ürün** envanterde kalır, maliyet katmanı kurulmaz. Kriter ürünün niteliğidir,
   `SonAlis = 0` değildir.

Değişiklikten sonra kapı: `/fifo-dogrula` C1 ile C8 arası.

```sql
-- her revizyondan sonra sifir donmeli
SELECT COUNT(*) FROM dbo.FifoKatman     WHERE BirimMaliyet <= 0;
SELECT COUNT(*) FROM dbo.FifoCikisDetay WHERE BirimMaliyet <= 0;
```

---

## 5. Teslim Öncesi Kontrol
- [ ] `SET NOCOUNT ON` + `SET XACT_ABORT ON` var
- [ ] `TRY/CATCH` var, `THROW;` ile bitiyor, CATCH'ten `GOTO` yok
- [ ] Parametre doğrulaması var
- [ ] `SELECT *`, `NOLOCK`, `MERGE`, cursor yok
- [ ] `DROP TABLE` yok
- [ ] Tüm DDL `IF NOT EXISTS` / `CREATE OR ALTER`
- [ ] Para `DECIMAL`, `FLOAT` yok
- [ ] Bölmelerde `NULLIF`
- [ ] Havuz seti `1,12,4477,4478` + `ehAltDepo=0`
- [ ] `BirimMaliyet > 0` korunuyor
- [ ] Kaynak dosya değiştiyse `tools/build-master.sh` ile master yeniden üretildi

---

## İlişkili
- `.claude/rules/fifo-domain.md` — bağlayıcı domain kuralları
- `.claude/agents/fifo-danisman.md` — "yapmalı mıyız" kararı
- `.claude/agents/sql-sp-reviewer.md` — yazdıktan sonra denetim
- `.claude/commands/fifo-dogrula.md` — C1–C8 kapıları
