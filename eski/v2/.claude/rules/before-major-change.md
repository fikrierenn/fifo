# Büyük Değişiklik Öncesi Zorunlu Çek-Liste

_pusula `before-major-change.md`den uyarlandı. **Vakalar FIFO'dan.**_

_Kapsam: silme, rename, refactor, kolon/tablo drop, SP kaldırma, constraint
değişimi, master yeniden üretme._
_Tetik: 30+ satır etkileniyor VEYA geri alınamaz bir yüzeye dokunuluyor._

## Sırayla, atlanmadan

### 1. Kaynak kodu oku — dokümanı değil
Silmek/değiştirmek üzere olduğun şey gerçekten anlattığı gibi mi?

_Ölçülmüş vaka: kök `CLAUDE.md` `app/` dizinini 25 sayfalık tamamlanmış bir
uygulama diye anlatıyordu; o dizin `arsiv/` altına taşınmıştı ve `fifo.sln`
yalnız `hangfire` içeriyordu. Her oturum bu yanlış haritayla başlıyordu._

### 2. Referans tara — desen ÖNEK VARSAYMASIN
```bash
grep -rn "<isim>" v2-production/ tools/ hangfire/ .claude/
```

_Ölçülmüş vaka: `grep 'DROP TABLE dbo.Fifo\|dbo.Maliyet'` deseni
`OrtalamaAylikMaliyet`'i kaçırdı ve "temizlendi" sanıldı. Doğrusu
`grep -E '^[[:space:]]*DROP TABLE dbo\.'` idi._

Sonuç **sıfır** olsa bile şüphelen — desen dar olabilir
(`yama-hedefi-dogrulama.md`).

### 3. Kardeş kod yolu var mı
Bu depoda açılış **iki kez** yazılmıştır (`02_V2` ve `14_V2`). Birine
eklenen koruma diğerinde eksik kalabilir — 2026-09-10'da tam bu oldu.

Sor: *"aynı işi yapan başka bir SP var mı, orada da aynı mı?"*

### 4. Cascade kontrol
- Bu SP/view silinince kim kırılır? (`sys.sql_expression_dependencies`)
- `build-master.sh` SECTIONS listesinde mi?
- Hangfire job çağırıyor mu?
- Razor sayfa okuyor mu?

### 5. Kullanıcıya net soru sor — TEHLİKELİ SİLME ÖNCESİ ZORUNLU

Şu durumlarda **onay olmadan yapma:**
- Tablo drop / kolon drop
- `FifoKatman` / `FifoCikisDetay` üzerinde toplu `DELETE`
- Constraint gevşetme
- Master'ı dolu bir veritabanına deploy
- Prod'a herhangi bir şey

Soru kalıbı: **"X'i siliyorum, Y satır gider ve geri gelmez — onaylıyor
musun?"** Sayıyı **ölç**, tahmin etme.

### 6. Yedek al ve restore'u DENE
Yedek almak yetmez; geri dönebildiğini görmeden yıkıcı işe başlama.
`BACKUP ... COPY_ONLY` ucuzdur (3,3 GB veritabanı → 62 MB, saniyeler).

### 7. Tier 3 ise plan
`plan-first.md`. Plansız refactor yasak.

### 8. Sonrası
- Build + **dolu veritabanında** smoke
- `/fifo-dogrula` C1–C7
- Referans mutabakatı
- `session_log.md` + `.claude/CLAUDE.md` SON DURUM güncelle

## İlk dokunuş kuralı

**Bir dosyayı bu oturumda İLK KEZ değiştirmeden önce OKU** (değiştireceğin
bölge + çevre 50 satır). Benzer koddaki kalıbı taklit et, kendi stilini
dayatma.

SQL içeriyorsa `sql-server-conventions.md` ile doğrula: mekan havuzu, tip
kodu sözlüğü, SARGable, `DECIMAL`, `NULLIF`.

**Gerekçe:** okumadan yapılan ilk dokunuş sessiz yanlış rakam üretir.
"Dosya tanıdık, direkt düzenlerim" istisna değildir.

## Anti-pattern

1. **"Sanırım bu kullanılmıyor" → silme.** Sanmak yetmez, ölç.
2. **Bir yerde düzelttim, sınıf kapandı.** Deseni tüm depoda ara.
3. **Boş DB'de test ettim, güvenli.** Boş DB, dolu DB'nin kod yollarını
   çalıştırmaz.
4. **Plan yazmadan Tier 3 refactor.**

## Hata yapıldığında
1. Kabul et. 2. Geri al. 3. Bu dosyaya vaka olarak ekle.
4. Kalıcıysa `.claude/rules/` ya da `memory/`ye yaz.

## İlişkili
- `plan-first.md` · `yama-hedefi-dogrulama.md` · `kosan-is-bayatlar.md`
- `calisma-protokolu.md` — Danış adımı
