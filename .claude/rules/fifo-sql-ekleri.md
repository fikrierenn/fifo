# FIFO SQL ekleri (Orkestra `sql.md`'ye ek)

> `sql.md` (Orkestra) esastır; burada yalnız orada olmayan, v2'de ödenmiş dersler var.

## Hata yönetimi
- CATCH bloğunda `GOTO` yok; `GOTO` sonrası `ERROR_*()` fonksiyonları NULL döner.
- `'metin' + @Err` NULL ise bütün mesaj NULL olur → `CONCAT` ya da `ISNULL`.
- `THROW` öncesi önceki ifade `;` ile biter.
- Bölmede payda `NULLIF(x, 0)` ile korunur.

## Deploy
- Nesne kurulumu idempotent: `IF OBJECT_ID(...) IS NULL CREATE` / `CREATE OR ALTER`; seed additive.
- Kalıcı (veri taşıyan) tablo deploy betiğinde **DROP edilmez**. Şema değişikliği expand–contract ile.
- SP adı `usp_` önekli (`dbo.usp_FiilNesne`); `sp_Fifo_*` kullanılmaz.

## Orkestra kurallarıyla bilinçli çatışmalar
- **RUN-005** para için `DECIMAL(18,4)` ister; birim maliyet daha fazla hassasiyet gerektirebilir.
- **RUN-008** iş tablosunda hard `DELETE`/`TRUNCATE` yasaklar; yeniden koşum geri alma deseni silme gerektirebilir.
- İkisi de gerekirse `-- ork:izin KURAL-ID <gerekçe>` ile satırda bastırılır ve kararı bir ADR'ye yazılır.
  ADR olmadan bastırma yapılmaz.

## Test
- SP sonuç kümesi ↔ C# DTO kontratı testle sabitlenir (kolon sırası/adı/tipi).
- Smoke = dolu DB + canary + constraint'i çiğneyen satırı INSERT etmeyi dene (hata 547 beklenir).
