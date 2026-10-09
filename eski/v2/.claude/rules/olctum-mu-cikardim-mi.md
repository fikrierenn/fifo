# Ölçtüm mü, Çıkardım mı — Her Cümlede Belli Olsun

_Belinza ve pusula depolarındaki aynı adlı kuraldan uyarlandı. **Vakalar
kopyalanmadı**, bu deponun kendi ölçülmüş hataları yazıldı._

## Ölçülen vakalar (FIFO)

| İddia | Nasıl "biliniyordu" | Gerçek |
|---|---|---|
| "Master idempotent, re-deploy güvenli" | plan dosyasında **yazıyordu** | 7 çekirdek tabloyu koşulsuz DROP ediyordu |
| "Yıkıcı DROP'u temizledim" | 01'i düzelttim, **diğerlerine bakmadım** | `12_V2`de aynı kusurdan ikincisi duruyordu |
| "`BirimMaliyet > 0` güvenle konur, lokalde ihlal yok" | ölçüldü ama **kapsam yanlış**: mevcut VERİ ölçüldü, üretilecek veri değil | açılış SP'si o satırı kasten yazıyor → 547 |
| "Boş DB'ye iki kez deploy geçti, master sağlam" | ölçüldü ama **nüfus yanlış**: boş DB, dolu DB'nin kod yollarını hiç çalıştırmaz | dolu DB'de üç kusur daha çıktı |
| "`FifoCikisDetay` KaynakTip `FATURA` olur" | eski `schema.md`den **kopyalandı** | öyle bir KaynakTip yok |
| "Mekan 12 açılışta hariç" (fifo-expert.md risk listesi) | eski dokümandan | düzeltilmişti, doküman bayattı |

## Ortak mekanizma

> Ölçümün yerine **makul bir çıkarım** koymak ve onu ölçümmüş gibi sunmak.

Bu sınıf sinsi çünkü çıkarım yanlış olduğunda sonuç **saçma değil, makul**
çıkar. Saçma sayı fark edilir; makul sayı kabul edilir ve karara dayanak
olur. Yukarıdaki altı vakanın altısı da ilk bakışta doğru görünüyordu.

## Kural

**1. Her olgusal cümle etiketli olmalı.**

- **ÖLÇÜLDÜ** — yanında komut/sorgu ve sayı var.
- **ÇIKARIM** — ölçülmedi, benzer bir yerden türetildi. Bu etiket olmadan
  çıkarım söylenmez.
- **DOĞRULANMADI** — bakılmadı, bilinmiyor. Söylemek serbest, **gizlemek
  yasak**.

Etiketleyemiyorsam cümleyi kurmam; önce ölçerim.

**2. Ölçümün KAPSAMI, kodun kapsamıyla aynı olmalı.**

En pahalı hata burada. Ölçüm doğru koşuldu ama nüfus yanlıştı:

- *"`BirimMaliyet <= 0` satır sayısı 0"* → doğruydu, ama **mevcut veriyi**
  ölçüyordu; asıl soru *"bu SP çalıştığında 0 yazar mı"* idi. Cevap: evet.
- *"Boş DB'ye deploy temiz"* → doğruydu, ama boş DB'de `OrtalamaAylikMaliyet`
  **zaten boştu**; onu silen DROP hiçbir şey kaybetmedi ve görünmedi.

Sınama: *"bu ölçümün süzgeci, koddaki süzgecin AYNISI mı? Ölçtüğüm nüfus,
riskin yaşadığı nüfus mu?"*

**3. Doküman ölçüm değildir.**

`CLAUDE.md`, `SON DURUM`, `memory/`, plan dosyaları — hepsi **yazıldığı
tarihte** doğruydu. Bugün doğru olduklarını kanıtlamak senin işin.

2026-09-10'da ölçüldü: kök `CLAUDE.md` hâlâ `app/` dizinini 25 sayfalık
tamamlanmış bir Razor uygulaması diye anlatıyordu; o dizin `arsiv/` altına
taşınmıştı. Her oturum bu yanlış haritayla başlıyordu.

**4. Kaynak kod otoritedir.**

İddia koddan doğrulanır, `dosya:satır` gösterilir. Memory ve eski skill
metni kanıt değildir.

## Sınır testi

> *"Bu cümleyi kurarken elimde bir komut çıktısı var mı, yoksa 'öyle
> olmalı' mı diyorum?"*

İkincisiyse ya ölç ya **ÇIKARIM** de.

## İlişkili
- `dogrulama-siniri.md` — çelişki mi eksiklik mi
- `yama-hedefi-dogrulama.md` — olumsuz iddia tek başına kanıt değil
- `danisman-brifingi.md` — ölçüm yapamayan ajandan ölçüm isteme
