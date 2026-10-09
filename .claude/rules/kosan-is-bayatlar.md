# Koşan İş, Altından Kod Değişince Bayatlar

_Belinza `kosan-is-bayatlar.md`den uyarlandı. Orada ölçülen kayıp 45 dakikalık
bir ETL çekimiydi; burada karşılığı **tam pipeline koşusu**._

## FIFO'da neye karşılık geliyor

| İş | Tipik süre | Bayatlarsa |
|---|---|---|
| Açılış (`sp_Fifo_AcilisCalistir_V2`) | ~2-3 dk | katmanlar eski tier mantığıyla kurulur |
| `sp_Fifo_AylikRutinFull` (1 ay) | 30+ dk | alış+çıkış eski SP ile hesaplanır |
| `sp_Ortalama_AylikHesapla` | dakikalar | açılış/çıkış ile tutarsız ortalama |
| Tam pipeline (üçü birden) | **saatler** | tamamı çöp |

## Kural

> Uzun koşan bir pipeline, **başladığı andaki kod sürümüyle** biter.
> O sürüm değişirse iş **bayattır** ve bitirilmesinin değeri yoktur.

Üç parça birlikte gerekir:

1. **Kaydet** — koşu başlarken hangi master/SP sürümüyle başlandığı yazılır
   (`git rev-parse HEAD` ve varsa master dosyasının hash'i). Yoksa
   karşılaştıracak bir şey yok.
2. **Her adımdan önce bak** — yalnız başta bakmak, iş başladıktan *sonra*
   deploy edilen bir SP'yi hiç görmez.
3. **Dur** — devam eden iş **yarım defter** bırakır. Açılış yeni SP ile,
   aylık rutin eski SP ile koşarsa `FifoKatman` iki farklı mantığın karışımı
   olur ve bunu sonradan ayırmak imkânsızdır.

Üçüncüsü en önemlisi. `dogrulama-siniri.md`: *"Ocak işlendi"* ile *"katmanların
yarısı eski tier mantığıyla kuruldu"* aynı anda doğru olamaz → **çelişki →
devam etme, dur.**

## İnsan tarafı — asıl ders

Kusur yalnız mekanizmada değil. *"Bitsin de sonra bakarız"* bir karar değil,
kararı ertelemektir.

> **Bir pipeline başlattıktan sonra onun varsayımını değiştiriyorsan,
> pipeline'ı durdur.**

Sınama: *"şu an yazdığım şey, koşan işin çıktısını geçersiz kılıyor mu?"*
Cevap evetse iş **o anda** durdurulur.

## FIFO'ya özgü işaretler

- **`Invoke-Sqlcmd` bir sayım sorgusunda takılıyorsa** koşan bir iş var
  demektir; engel değil, **işaret**. Kilit çakışmasıdır.
- **Yeniden koşu referans veritabanında yapılmaz.** `BACKUP ... COPY_ONLY` +
  `RESTORE` ile kopya çıkar, koşuyu orada yap. Koşu bozulursa
  karşılaştıracağın referans yerinde durur. (3,3 GB veritabanı → 62 MB yedek,
  saniyeler.)
- **Rerun-safe sıra pazarlıksız** (`fifo-domain.md` §4): çıkışı geri al →
  katmanı sil → alışı yaz → satışı işle. Ters sıra
  `FK_FifoCikisDetay_FifoKatman` ihlali verir.
- **`FifoDevreDisiUrunler` kalıcı ve additive** — temizlikte silinmez.
  Silinirse koşu farklı bir ürün kümesiyle çalışır ve sonuç karşılaştırılamaz.

## Sınır testi

> *"Bu koşu bittiğinde defter, koşunun BAŞLADIĞI andaki kodun ürettiği
> defter mi olacak?"*

Hayırsa iş bayattır.

## İlişkili
- `plan-first.md` sinyal 5 — uzun pipeline Tier 3
- `fifo-domain.md` §4 — rerun-safe sıra
- `calisma-protokolu.md` — Smoke adımı, kopyada test kuralı
