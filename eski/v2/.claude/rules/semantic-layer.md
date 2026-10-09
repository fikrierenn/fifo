# Semantik Katman Disiplini — FIFO

_pusula `semantic-layer.md`den uyarlandı. **Vurgu değişti:** orada asıl sorun
"şema bilgisi nerede saklanır"dı; burada asıl sorun **"yazılı kural
koşturulmuyor"**._

## Temel ilke

> **Şema gerçeği öğrenilince hafızada kalmaz — `sema/`ya yazılır.
> Ve koşturulabiliyorsa KOŞTURULUR.**

`last_verified` + `ttl_days` bir **bayraktır**, bir **ölçüm** değil: süresi
dolduğunu görmek için birinin bakması gerekir, ve bakılmaz.

Bu deponun ödediği bedel: `fifo-domain.md` §6 "FİYAT 0 OLAMAZ" bir markdown
başlığıydı. `20_V2` ve `21_V2` scriptleri o kuralı **elle onarmak** için
yazılmıştı. Kural koşmuyordu, insan koşuyordu.

## Dosya yönlendirme

| Öğrenilen | Hedef |
|---|---|
| **Koşulabilir bir gerçek** ("X asla olmaz") | `sema/degismezler.json` ← **önce buraya bak** |
| Join / FK / cross-DB bağ | `sema/bridges.yaml` |
| Tablo/view + PK + grain | `sema/entities.yaml` |
| Enum / lookup (KaynakTip, Durum, ERP tip kodu) | `sema/codes.yaml` |
| Formül / hesap modeli (brüt kâr, SMM, ortalama) | `sema/metrics.yaml` |
| Nasıl bulundu (keşif SQL'i) | `sorgular/YYYY-MM-DD-<konu>.sql` |

## Kurallar

1. **Sorgu yazmadan önce `sema/`ya bak.** Doğru join, doğru kod, doğru formül
   orada. Hardcode etme, oradan al. Canlı yeniden keşif **yasak** —
   `bridges.yaml`da tanımlı bir bağı yeniden bulmaya çalışmak iki tur kaybıdır.
2. **Yeni gerçek → anında kayıt.** "Sonra eklerim" yok.
3. **Atomic + kanıtlı.** Bir kayıt = bir gerçek. Tahmin `status: teyit bekliyor`
   + düşük confidence.
4. **Duplikasyon yok.** Aynı bağ varsa güncelle, yeni satır açma.
5. **Çelişki → düzelt.** Yeni gerçek eskiyi çürütürse eskiyi sil ya da düşür.
6. **İkiz yükümlülük.** Anlamlı bir keşif yaptıysan oturumu kapatmadan
   **ikisini birden** yap: (a) gerçeği `sema/`ya yaz, (b) çalıştırdığın SQL'i
   `sorgular/`a arşivle. Sema "ne öğrendik", arşiv "nasıl bulduk" der.

## Değişmez yazma disiplini — pazarlıksız

### Gerekçesiz değişmez kabul edilmez
`soru` · `neden` · `sql` · `karsilastirma` · `beklenen` zorunlu. Koşucu
yapısal olarak denetler ve eksikse **KOŞAMADI (çıkış 2)** verir.
Gerekçesi yazılmayan bir değişmez, kırıldığında ne yapılacağını söylemez.

### Kırılabildiği kanıtlanmadan değişmez yazılmaz
Beklenen değeri **bilerek boz**, kırmızı olduğunu **gör**, geri al.

_Yapıldı 2026-09-10: koşucu iki veritabanına çevrildi. Yeni pipeline
veritabanında 14/14 geçti (çıkış 0); constraint'siz eski referans
veritabanında iki constraint değişmezi doğru şekilde KIRIK verdi (çıkış 1).
Mekanizma totolojik değil._

### Yazarken ölçmeye zorlar — asıl değeri bu
Değişmezin değeri kırmızı vermesinden **önce**, yazarken sorulan sorudadır.
`kaynaktip-kumesi-kapali` yazılırken ölçüldü: gerçek küme altı değer
(`ACILIS · ACILIS_TAMAMLA · ALIS · AYLIK_DEVIR · SENTETIK_ALIS · IADE`) ve
eski `memory/schema.md`nin yazdığı **`FATURA` diye bir tip yok**.

### DEĞİŞMEZ ≠ ÖLÇÜM
Ayrım testi: *"bu iddia yarınki veriyle de doğru mu?"*
"BirimMaliyet 0 olamaz" değişmezdir; "Ocak SMM 46,65M" ölçümdür ve
`dogrulandi` alanına tarih damgasıyla yazılır.

## ŞEMA GERÇEĞİ ≠ SATIR VERİSİ

**Sema'ya KURAL yazılır, LİSTE yazılmaz.** Liste değişkendir; yazıldığı an
bayatlamaya başlar ve sonraki oturum onu doğruymuş gibi kullanır.

**Ayrım testi:** *"Bu bilgi 6 ay sonra hâlâ doğru mu?"* Hayırsa satır
verisidir, kodda canlı sorgulanır.

**Anti-pattern:** liste yazıp `last_verified` damgasıyla kendini güvende
sanmak. Liste TTL ile korunmaz — bir ürün devre-dışı olunca kayıt sessizce
yanlış olur ve kimse fark etmez.

## "Başka ne olabilir?" kapısı

En tehlikeli hata **yorum** hatasıdır: ölçüm doğrudur, ona konan **ad**
yanlıştır ve ölçülmüş gibi sunulur.

> Bir bulgu sema'ya ya da rapora girmeden önce **en az bir alternatif
> açıklama** yazılıp elenir. Elenemiyorsa bulgu **ÇIKARIM** etiketiyle yazılır.

_Somut vaka (2026-09-10): yeni pipeline koşusu referanstan %0,41 saptı.
İlk açıklama "benim düzeltmem maliyeti değiştirdi" idi ve makuldü. Alternatif
soruldu: "referans ne zaman kuruldu?" Cevap **2026-06-02** — açılış
düzeltmesinden 17 gün ÖNCE. Sapmanın çoğu benim değişikliğimden değil,
referansın bayat olmasından geliyordu. Tek soru tanıyı değiştirdi._

## Yaşlanma (decay)

- `confidence: 1.0` **muaf** (kalıcı PK/FK) — yaşlanmaz.
- Altındakiler `last_verified` + `ttl_days`: `0.9-0.99` → 180g ·
  `0.5-0.8` → 90g · `0.3-0.5` → 30g.
- **Stale = bayrak, otomatik aksiyon DEĞİL.** Kayıt silinmez; "yeniden
  doğrula" işaretidir. Otomatik arşivleme yasak, kullanıcı onayı şart.
- **Değişmezler yaşlanmaz** çünkü her koşuda yeniden ölçülürler. Decay
  yalnız YAML tarafı içindir.

## İlişkili
- `sema/README.md` · `tools/fifo-degismez.ps1`
- `.claude/skills/sema-ogren/SKILL.md`
- `.claude/rules/olctum-mu-cikardim-mi.md` — ölçüldü / çıkarım
- `.claude/rules/sql-server-conventions.md`
