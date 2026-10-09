---
paths:
  - "**/*.sql"
---

# SQL dosyası kuralları (özet — tam katalog: kurallar-sql, biçim: yazim-sql)

- Runtime kuralları ezilemez: yerel tarih literal'i DMY `CONVERT(date, 'gg.aa.yyyy', 104)`; ODAKJOKER'de `'YYYYMMDD'`; compat 110 hedefte `STRING_AGG`/`TRIM`/`IIF`/`TRY_CONVERT` yok; para `DECIMAL(18,4)`; `src.*` salt okunur; okumada `IsValid = 1`; hard `DELETE` yok.
- SP: `CREATE OR ALTER PROCEDURE dbo.usp_FiilNesne`, header bloğu (Amaç, Versiyon, Değişiklik, Bağımlılıklar, Çağıranlar, Hata kodları), `SET NOCOUNT ON`, yazmada `XACT_ABORT` + TRY/CATCH + TRAN + `@@TRANCOUNT` ROLLBACK + `THROW`, hata numarası 50000–59999 ve `db/hata-kodlari.yaml`'da.
- `SELECT *` yok, INSERT kolon listeli, alias `AS` ile, her ifade `;` ile biter, `TOP` + `ORDER BY`.
- Köprü, kod değeri, sentinel ve metrik tahmin edilmez: önce `ork sema ogren "<tablo.kolon>"` (BKM'de pusula sema'sı, salt okunur); yeni ölçülmüş gerçek → `ork sema-aday` (kurallar-sql § Semantik katman).
- Dosya başına hedef veritabanı: `-- ork:hedef-db <ad>`. Bastırma yalnız gerekçeyle: `-- ork:izin KURAL-ID <gerekçe>`.
- Kaydettiğin anda `sql_denetle.py` hook'u koşar; E seviyeli bulgu kalmadan bitmiş sayma. Elle: `python .claude/hooks/sql_denetle.py <dosya>`.
