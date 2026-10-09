# PLAN — Kapı Sertleştirme: yıkıcı DDL deseni + antipattern kancası

**Tarih:** 2026-09-11 · **Tier:** 3 · **Durum:** Tamamlandı

> **Onay notu:** Kullanıcı 2026-09-10/11 oturumunda "bel ve pusula depolarındaki
> skill/hook/agent/kural ne varsa al, uyarla, atlama" talimatını verdi ve
> ardından "danış, kodla kontrol et, izle, tier 3 disiplinleri" dedi. Bu plan o
> talimatın kapsamındadır. İki danışman bağımsız denetledi ve reçeteyi verdi.
> **Kullanıcının plan üzerinde ayrıca söz hakkı saklıdır** — itiraz gelirse
> değişiklikler geri alınır.

## 1. Problem

Üretim master'ının yıkıcı DDL kapısı **dar desenle** yazılmıştı:

```bash
grep -cE '^[[:space:]]*DROP TABLE dbo\.' "$OUT"
```

Üç biçimi birden kaçırıyor (ÖLÇÜLDÜ, `fifo-kapi-danismani` + `fifo-deploy-danismani`):

| Kaçırılan biçim | Neden |
|---|---|
| `IF OBJECT_ID('dbo.X','U') IS NOT NULL DROP TABLE dbo.X;` | satır başına çapalı |
| `DROP TABLE FifoKatman` | `dbo.` öneki varsayılıyor |
| `DROP TABLE [dbo].[FifoKatman]` | köşeli parantez |

Aynı aileden bir desen **2026-09-10'da gerçekten kaçırdı**: `12_V2`deki
`DROP TABLE dbo.OrtalamaAylikMaliyet` görülmedi ve "yıkıcı DROP temizlendi"
sanıldı. Bağımsız bir danışman buldu.

Aynı kusur `.claude/hooks/post-edit-antipattern.sh` kural 1'de de vardı
(öz-testte yakalandı: 6 kusurdan 5'i ateşlendi, yıkıcı DROP ateşlenmedi).

## 2. Tier gerekçesi

`plan-first.md` sinyalleri:
- [x] **1** · deploy scripti / master / build üretici
- [x] **3** · constraint / değişmez kapısı

## 3. Danışıldı mı

| Danışman | Kararı | Engelleyici bulgusu |
|---|---|---|
| `fifo-kapi-danismani` | KOŞULLU UYGUN | **Asıl kapı `build-master.sh:97`**, hook değil. Zayıfı düzeltip güçlüyü bırakmak ikinci yalancı yeşil olur. Sıra: önce build, sonra hook. |
| `fifo-deploy-danismani` | KOŞULLU UYGUN | Önerilen çapasız desen **master satır 440'taki YORUMU** yakalar ve build'i kalıcı kilitler. Ayrıca `CKDROP <= CKADD` tek başına delik: ikisi birden silinirse `0 <= 0` geçer ve §6 CHECK'i sessizce kaybolur. |

## 4. Kapsam

### Dahil
- `tools/build-master.sh` — yıkıcı DDL kapısı (basamak 3, REDDET)
- `.claude/hooks/post-edit-antipattern.sh` — kural 1 + `:93` backtick hatası + görünürlük
- Öz-test fixture'ları (`tools/hook-selftest/`)

### Hariç
- WHERE'siz `DELETE` kuralı — master'da 16 meşru kullanım var, hepsinde WHERE
  bir sonraki satırda. Satır-bazlı grep 16 yanlış alarm üretir. Cümle-bazlı
  ayrıştırma gerekir, bu turun işi değil.
- `DROP INDEX` / `DROP COLUMN` / `sp_rename` — bugün master'da 0, maliyetsiz
  ama zorunlu değil.
- Dinamik SQL (`@sql = N'DROP ' + N'TABLE ...'`) — **bilinen kör nokta**,
  metin deseni yakalayamaz. Karşı önlem kapı değil, dolu-DB canary testi.

### Etkilenen
`tools/build-master.sh` · `.claude/hooks/post-edit-antipattern.sh` ·
üretilen `v2-production/00_V2_MASTER_FULL.sql` (salt-okuma, değişmemeli)

## 5. Adımlar

1. [x] **S1** Build kapısı: yorum-dışı tarama kopyası (`CLEAN`), kalıntı sayımı,
   TRUNCATE kapısı, CK denge + **pozitif varlık** kontrolü.
2. [x] **S2** Kırılabilirlik testleri (§8 tablosu) — 8 senaryo.
3. [x] **S3** Hook kural 1: tek pozitif desen, kapsam `v2-production/` +
   `SQL-Improvements/` (`.demo/`, `arsiv/` hariç — 6 meşru yıkıcı script var).
4. [x] **S4** Hook `:93` backtick hatası → tek tırnak.
5. [x] **S5** Hook görünürlüğü: `f` dolu ama çözülemiyorsa sessiz çıkma.
6. [x] **S6** RESET muafiyeti: yalnız `*_RESET.sql` soneki (büyük-küçük duyarsız).
7. [x] **S7** Öz-test fixture'ları + `build-master.sh`e bağla.

## 6. Riskler

| Risk | Etki | Sessiz mi gürültülü mü | Mitigasyon |
|---|---|---|---|
| Kapı dar kalır | 15 kalıcı tablo, kayıp geri gelmez | **SESSİZ** — ikinci deploy'da hata üretmeden | kalıntı sayımı + kırılabilirlik testi |
| Yorum-strip atlanır | build kalıcı kilitlenir | GÜRÜLTÜLÜ, ama insan `\|\| true` ile susturur → **sessize döner** | `CLEAN` kopyası |
| CK denge tek başına | §6 CHECK'i master'dan kaybolur, %100 marj | **SESSİZ** | pozitif varlık kontrolü |
| Hook yanlış alarm | uyarı körlüğü | GÜRÜLTÜLÜ | kapsamı deploy ağacına sınırla |

## 7. Done kriterleri

- [x] `bash tools/build-master.sh` → **GEÇER**, 4750 satır, 16 SP
- [x] `git diff --stat v2-production/00_V2_MASTER_FULL.sql` → **boş** (gate salt-okuma)
- [x] 8 kırılabilirlik senaryosunun 6'sı REDDEDİLİR, 2'si GEÇER
- [x] Hook öz-testi: `kotu.sql` → 15 kural da ateşlenir · `iyi.sql` → **0 uyarı**
- [x] `pwsh tools/fifo-degismez.ps1` → 14/14, çıkış 0

## 8. Kırılabilirlik testleri (S2)

| # | Bozma | Beklenen |
|---|---|---|
| 1 | `12_V2`ye `IF OBJECT_ID(...) IS NOT NULL DROP TABLE dbo.OrtalamaAylikMaliyet;` | REDDEDİLİR |
| 2 | satır ortasında `BEGIN DROP TABLE [dbo].[FifoKatman] END` | REDDEDİLİR |
| 3 | `DROP TABLE FifoKatman` (şemasız) | REDDEDİLİR |
| 4 | `TRUNCATE TABLE dbo.FifoDevreDisiUrunler;` | REDDEDİLİR |
| 5 | yalnız `ADD CONSTRAINT CK_FifoKatman_BirimMaliyet` sil | REDDEDİLİR (denge) |
| 6 | **hem ADD hem DROP** sil | REDDEDİLİR (**varlık** — denge tek başına GEÇİRİR) |
| 7 | `DROP TABLE IF EXISTS #tmp` ekle | GEÇER (temp) |
| 8 | temiz kaynak | GEÇER |

Test 6 kritik: ölçütün yetersizliğini gösteren tek test.

## 9. Rollback

`git checkout -- tools/build-master.sh .claude/hooks/post-edit-antipattern.sh`
Kaynak dosyalar değişmiyor; master yeniden üretilir. Veri riski yok.

## 10. İlişkili
`plan-first.md` · `yama-hedefi-dogrulama.md` · `dogrulama-siniri.md` ·
`fifo-domain.md` §2 §6 · `sema/degismezler.json`
