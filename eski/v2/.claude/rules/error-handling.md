# Hata Yönetimi — Beklenen Sonuç vs Gerçek Hata

_pusula `error-handling.md`den uyarlandı; **T-SQL tarafı bu deponun ölçülmüş
kusurlarıyla yeniden yazıldı**._

## Temel ayrım

**Beklenen iş sonucu** ≠ **gerçek sistem hatası**.

| Durum | Tip | Mekanizma |
|---|---|---|
| "Bu ürünün fiyatı bu kademede yok" · "stok yetersiz" · "devre dışı ürün" | Beklenen | **Sonraki kademeye geç** + `FifoSorunluStoklar`'a kayıt |
| Deadlock, timeout, bağlantı kopması, disk dolu | Gerçek hata | `TRY/CATCH` + log + `THROW` |
| Değişmez ihlali (kalan > giriş, maliyet ≤ 0, orphan çıkış) | **Kod hatası** | `THROW` / constraint — asla yutma |

**Anti-pattern:** beklenen bir iş sonucu için hata fırlatmak. Fiyatı olmayan
ürün bir istisna değil, bir **kademe atlaması**dır.

**Karşı anti-pattern (bu depoda daha pahalı):** bir değişmez ihlalini
"beklenen" sayıp sessizce 0 yazmak. Ölçülmüş vaka: açılış, fiyatı bulunamayan
ürüne `ISNULL(...,0)` ile 0 maliyet yazıyordu. Bu bir kademe atlaması değil,
**%100 marj**dır.

## T-SQL kuralları — hepsi ölçülmüş bir kusurdan

### 1. `THROW` kullan, `RAISERROR` kullanma
`RAISERROR` orijinal hata numarasını 50000 yapar ve zinciri koparır.

### 2. `GOTO` ile CATCH bloğundan çıkma
`ERROR_MESSAGE()`, `ERROR_NUMBER()`, `ERROR_LINE()`, `ERROR_SEVERITY()`,
`ERROR_STATE()` **CATCH dışında NULL döner**.

_Ölçüldü 2026-09-10: `14_V2`de üç CATCH bloğu da `GOTO HataYonetimi` yapıyor,
etiketten sonra `ERROR_MESSAGE()` çağrılıyordu. Sonuç: hata metni NULL, log
boş, `RAISERROR(NULL, NULL, NULL)` kendi hatasını üretiyor ve **orijinal hata
tamamen kayboluyordu**._

Ortak hata bloğu isteniyorsa değerler **CATCH içinde değişkene alınır**,
etikette yalnız kullanılır.

### 3. `'metin ' + @ErrMsg` yazma
Değişken NULL ise **tüm ifade NULL** olur ve log boş kaydedilir.
`CONCAT()` ya da `ISNULL(@x, N'?')` kullan.

### 4. Log yazmak asıl hatayı EZMEMELİ
_Ölçüldü: `FifoSorunluStoklar`'ın PK'sı `(EnvanterTarihi, MekanId, StkId,
SorunTipi)`. Hata bloğu hep aynı anahtarı yazıyordu; aynı tarihte **ikinci**
bir hata olduğunda düz INSERT 2627 (PK ihlali) veriyor, `XACT_ABORT ON` ile
batch orada ölüyor ve `THROW` hiç çalışmıyordu. Çağırana gerçek hata yerine
"Violation of PRIMARY KEY" dönüyordu._

Doğrusu: önce sil, sonra yaz, ve **tüm log bloğunu kendi TRY/CATCH'ine al**.
Log yazılamazsa `PRINT` ile bildir, asıl `THROW`u engelleme.

### 5. `THROW` öncesi noktalı virgül
`END CATCH;` — yoksa `Incorrect syntax near 'THROW'`.

### 6. Boş CATCH yasak
Sadece log yazıp devam eden CATCH de sessiz hatadır. Ya `THROW` ya da neden
devam edildiği **yorumda** yazılı olmalı.

### 7. Fallback sessiz olmasın
Bir kademe atlandıysa `FifoSorunluStoklar`'a **hangi kademede** çözüldüğü
yazılır (`TAMAMLAMA` · `MERKEZ_TAMAMLAMA` · `SART_TAMAMLAMA` ·
`AYLIK_DEVIR` · `KATEGORI_IMPUT` …). Sessiz fallback, tahmini gerçek gibi
gösterir ve denetlenemez.

### 8. Parametre doğrulaması
SP başında, `THROW` ile. Sessiz yanlış sonuç yerine erken patla.

## PowerShell / betik tarafı

- **`set -e` altında `grep -q ... && fail`** yazma: grep bulamayınca (çoğu
  zaman istenen durum) betik **sessizce 1 ile düşer**. `if grep -q ...; then`
  kullan. Sayım için `$(grep -c ... || true)`.
- **Kapının kendi hatası görünür olmalı.** `2>/dev/null` ile yutulan bir hook
  hatası, kapının aylarca ölü kalmasına yol açar (bel'de 11 gün ölçüldü).
  Görünür yap, ama çalışmayı durdurma.
- **`PRINT` otomasyonda kaybolur.** Kalıcı iz gerekiyorsa tabloya yaz.

## Reddet mi, Say mı

Bir doğrulayıcının koşuyu durdurup durdurmayacağı sezgiyle değil,
`dogrulama-siniri.md` ölçütüyle belirlenir: **çelişki → reddet, eksiklik → say.**

## İlişkili
- `dogrulama-siniri.md` · `fifo-domain.md` §6
- `.claude/skills/fifo-sql-developer/SKILL.md` §1 — SP iskeleti
- `silent-failure-hunter` ajanı
