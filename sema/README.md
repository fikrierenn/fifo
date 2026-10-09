# sema/ — FIFO Semantik Katman

Makine-okunur, **koşulabilir** şema gerçeği. pusula'nın `sema/` yapısından
uyarlandı; **bu depoda önce `degismezler.json` kuruldu** çünkü FIFO'nun asıl
sorunu "şema bilgisi nerede" değil, **"yazılı kural kimse tarafından
koşturulmuyor"** idi.

## Neden değişmezle başlandı

`fifo-domain.md` §6 "FİYAT 0 OLAMAZ" diyordu. Bir markdown başlığıydı.
`20_V2_Reprice_SifirMaliyetKatman.sql` ve `21_V2_AcilisEksikMaliyet.sql`
o kuralı **elle onarmak** için yazılmış scriptlerdi. Kural koşmuyordu.

> **Yazılan gerçek, komutla yeniden koşturulabiliyorsa koşturulur.**

`last_verified` + `ttl` bir **bayraktır**, bir **ölçüm** değil: süresi
dolduğunu görmek için birinin bakması gerekir ve bakılmaz.

## Dosyalar

| Dosya | İçerik | Durum |
|---|---|---|
| `degismezler.json` | **Koşan** değişmezler. `pwsh tools/fifo-degismez.ps1` | **14 kayıt, aktif** |
| `entities.yaml` | Tablo/view sözlüğü — PK, anahtar kolon, grain | açık iş |
| `bridges.yaml` | Köprüler — BKMMaliyet ↔ DerinSIS join tanımları | açık iş |
| `codes.yaml` | KaynakTip · Durum · SorunTipi · HareketTipi · ERP tip kodları | açık iş |
| `metrics.yaml` | Brüt kâr · marj · SMM · ortalama maliyet formülleri | açık iş |

Açık iş olanlar kasten boş: `footprint-ladder.md` — ihtiyaç doğmadan yüzey
açılmaz. İlk gerçek öğrenildiğinde `sema-ogren` skill'i dosyayı kurar.

## Değişmezleri koşturmak

```bash
pwsh tools/fifo-degismez.ps1                          # BKMMaliyet
pwsh tools/fifo-degismez.ps1 -Veritabani BKMMaliyet_Run
pwsh tools/fifo-degismez.ps1 -Sadece katman-maliyet-pozitif -Ayrintili
```

### Çıkış kodu sözleşmesi — 0 / 1 / 2

| Kod | Anlam |
|---|---|
| **0** | hepsi geçti |
| **1** | **KIRIK** — ölçüm koştu, değer beklenenden farklı |
| **2** | **KOŞAMADI** — bağlantı yok, SQL patladı, sonuç YOK/NULL, kayıt kusurlu |

**Koşamamak yeşil değildir.** Bir ölçümün boş dönmesi ile hiç koşmaması
ekranda aynı görünür; ikisini ayırmayan bir çıkış kodu "ölçmedik"i
"ölçtük, tuttu" gibi gösterir.

⚠ NULL / satır yok **0 sayılmaz**. `karsilastirma: esit, beklenen: 0` olan
kayıtlarda bu **hiç ölçmeden yeşil** verirdi.

## Yeni değişmez eklerken — pazarlıksız

1. `soru` · `neden` · `sql` · `karsilastirma` · `beklenen` doldur.
   **Gerekçesi yazılmayan değişmez, kırıldığında ne yapılacağını söylemez.**
   Koşucu bunu yapısal olarak denetler; eksikse KOŞAMADI verir.
2. **Beklenen değeri bilerek boz, KIRMIZI olduğunu GÖR, sonra geri al.**
   `-Sadece <id>` ile. Kırılabildiği kanıtlanmamış bir test, test değildir.
3. `dogrulandi` alanına **tarih + ölçülen değer** yaz.

### Kırılabilirlik kanıtı (2026-09-10)

Koşucu iki veritabanına çevrildi:

| Hedef | Sonuç |
|---|---|
| `BKMMaliyet_Run` (yeni pipeline, sıkı constraint'li) | **14/14 GEÇTİ**, çıkış 0 |
| `BKMMaliyet` (2026-06-02 koşusu, constraint yok) | **12 geçti, 2 KIRIK**, çıkış 1 |

Kırılan ikisi tam olarak beklenen ikisiydi:
`katman-constraint-siki-ve-guvenilir` ve `cikis-constraint-siki-ve-guvenilir`.
Mekanizma totolojik değil.

## DEĞİŞMEZ ≠ ÖLÇÜM

Ayrım testi: *"bu iddia yarınki veriyle de doğru mu?"*

| Yazılır (değişmez) | Yazılmaz (ölçüm) |
|---|---|
| `BirimMaliyet` 0 olamaz | "Ocak SMM 46,65M" |
| `KaynakTip` kümesi kapalı (6 değer) | "563.549 katman var" |
| Mekan 12 açılışta bulunur | "mekan 12'de 26.432 satır" |
| Çıkış maliyeti katmandan kopyalanır | "brüt marj %35,5" |

Ölçümler `dogrulandi` alanına **tarih damgasıyla** yazılır; değişmezler
koşulmak üzere `sql` alanına.

## ŞEMA GERÇEĞİ ≠ SATIR VERİSİ

**Sema'ya KURAL yazılır, LİSTE yazılmaz.** Ürün listesi, devre-dışı ürün
listesi, mekan adları — hepsi değişkendir ve yazıldığı an bayatlamaya başlar.

| ❌ Yazma | ✅ Yaz |
|---|---|
| "77 devre-dışı ürün: 226066, 67903 …" | "Devre-dışı kriteri ürünün NİTELİĞİ; liste tablodan canlı okunur, kalıcı+additive" |
| "Kategori3: Hazırlık, Kırtasiye, Kitap…" | "Kategori `bkm.UrunBilgi.KatAna`dan gelir" |

**Ayrım testi:** *"Bu bilgi 6 ay sonra hâlâ doğru mu?"* Hayırsa satır
verisidir, sema'ya girmez.

**İstisnalar:** kod/enum lookup (gerçekten sabit sözleşme) · büyüklük
mertebesi (**tarih damgalı**) · bir tuzağın tek örnek kanıtı.

## Confidence ölçeği (YAML dosyaları için)

`1.0` kalıcı (PK/FK) · `0.9-0.99` canlı doğrulandı · `0.5-0.8` gözlem, tam
teyit yok · `0.3-0.5` hipotez.
`1.0` **muaftır**, yaşlanmaz. Altındakiler `last_verified` + `ttl_days` taşır.

## İlişkili
- `.claude/rules/semantic-layer.md` — disiplin
- `.claude/skills/sema-ogren/SKILL.md` — öğrenilen gerçeği yazma akışı
- `.claude/rules/fifo-domain.md` — bağlayıcı domain kuralları
- `.claude/commands/fifo-dogrula.md` — C1–C8 (değişmezlerin insan-okunur hâli)
