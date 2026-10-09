# Danışman Brifingi — bir ajanı koşturmadan önce

_Belinza `danisman-brifingi.md`den uyarlandı. **Tuzak listesi FIFO'ya ait**
ve bu deponun ölçülmüş kayıplarından geliyor._

## Ölçüm (FIFO, 2026-09-10)

İki ajan koşturuldu, ikisi de brifingin beş maddesini taşıyordu ve ikisi de
isabetli çıktı:

| Ajan | Token | Sonuç |
|---|---|---|
| `fifo-danisman` (karar) | 89k | 5 karar + 2 açık kapı; **`12_V2`deki ikinci yıkıcı DROP'u buldu** |
| `sql-sp-reviewer` (kod) | 121k | 3 kritik + 4 önemli; **02'deki eksik sıfır-fiyat korumasını buldu** |

Brifinglerde şu vardı ve bu yüzden ucuz oldular: **zaten yapılan doğrulamanın
sonucu** ("tekrar etme, bilgi olarak kullan"). Olmasaydı ikisi de aynı deploy
testini baştan koşacaktı.

## Kural

> Bir ajan koşturmadan önce brifing ŞU BEŞİNİ içerir. Eksik olan her madde,
> ajanın onu **keşfetmek için** harcayacağı token demektir — ve keşfedemezse
> **uydurduğu** şey demektir.

### 1. Kapsam — hangi dosyalar, hangi tablolar, ne kadar büyük

"Kodu denetle" değil: dosya yolları + neyin değiştiği + satır sayıları +
tablo büyüklükleri. Ajan bunları bulmak için 20 tool çağrısı harcar.

### 2. Erişim — bağlantı, komut biçimi, ARACIN TUZAKLARI

Bu depoda ölçülen tuzaklar (brifinge **kopyalanır**):

- **`sqlcli --format json` çıktısı stderr'e, banner stdout'a gider.**
  `2>/dev/null > f` SADECE banner'ı kaydeder ve boş JSON sanılır.
  Doğrusu: `... --format json > f 2>&1`.
- **Banner'daki ANSI escape (`\x1b[38;5;8m`) içinde `[` var.** Python
  `raw.find('[')` onu yakalar. Önce ANSI strip
  (`re.sub(r'\x1b\[[0-9;]*m','',raw)`), sonra `raw[raw.index('['):raw.rindex(']')+1]`.
- **`sqlcli --max-rows` varsayılanı 1000 ve SESSİZ keser.** Satır sayısı
  belirsiz her çekimde açıkça ver; dönen satır tam 1000 ise kesilme şüphesi.
- **`sqlcmd.exe` bu makinede ODBC hatası veriyor — kullanma.**
  Tek sorgu: `sqlcli`. Dosya koşturma: `Invoke-Sqlcmd -InputFile`.
- **Kanonik sqlcli `D:\Dev\sqlcli`.** `D:\Dev\fifo\sqlcli` eski bir fork,
  drift etmiş olabilir.
- **`SELECT a/b` bölmelerinde `NULLIF(b,0)`** — sıfıra bölme sorguyu komple
  düşürür ve sessiz boş dosya bırakır.
- **`Invoke-Sqlcmd`'de `-TrustServerCertificate` parametresi YOK** (bu
  sürümde). Lokal `BT-FIKRI` için gerekmiyor.
- **`PRINT` çıktısı verbose akışına gider**; yakalamak için `-Verbose 4>&1`.
- **Lokal instance `BT-FIKRI`** (named instance YOK), ERP kaynağı
  `DerinSIS_Local`, canlı `192.168.40.201` **erişilemez**.

### 3. Ölçüt — bu deponun kuralları, adıyla

`fifo-domain.md` (§1 mekan havuzu, §2 devre-dışı kriteri, §6 fiyat>0),
`dogrulama-siniri.md` (çelişki→reddet, eksik→say),
`yama-hedefi-dogrulama.md` (olumsuz iddia tek başına kanıt değil),
`olctum-mu-cikardim-mi.md` (ölçüldü / çıkarım / doğrulanmadı).

**Neyin bulgu SAYILMADIĞINI da yaz.** Örnek: *"mevcut SP'lerdeki `NOLOCK`
kullanımları bilinçli korunuyor, bulgu değil"* — yoksa ajan 22 satırı
bulgu diye listeler ve gerçek bulgular arasında kaybolur.

### 4. Çıktı biçimi — alanları say

Denetçi: `NEREDE (dosya:satır) · KANIT (sayıyla) · ETKİ · ÖNERİ · CONFIDENCE`,
ağırdan hafife.
Danışman: `KARAR · GEREKÇE · KANIT · ETKİ · ŞART · RİSK`.

Biçim verilmezse ajan anlatı yazar; anlatıdan bulgu çıkarmak ikinci bir okuma.

### 5. Sınır — ne YAPMAYACAĞI

- Salt-okuma mu, yazabilir mi (denetçi/danışman **yazmaz**).
- Zaten yapılmış doğrulamayı tekrar etmesin — sonucu brifinge yaz.
- Pipeline koşturmasın, veritabanı değiştirmesin.

## Denetçi ≠ danışman — ayrım araçtan gelir

| | denetçi | danışman |
|---|---|---|
| Bash / sqlcli | **var** | **yok ya da salt-okuma** |
| üretir | ölçüm, dosya:satır kanıtı | yorum, karar |
| en büyük riski | kapsam hatası (süzgeç ≠ iddia) | **uydurma** |

> **Ölçüm aracı olmayan ajandan ölçüm isteme.** Ona **dosya yolu** ve
> **hazır ölçüm çıktısı** verilir.

## FIFO ajan kadrosu

**Danışman (karar):** `fifo-danisman` · `fifo-deploy-danismani` ·
`fifo-kapi-danismani`
**Denetçi (ölçüm):** `sql-sp-reviewer` · `silent-failure-hunter` ·
`maliyet-stok-uzman` · `sorunlu-urun-dedektif` · `db-schema-checker` ·
`build-validator` · `code-explorer`

Model katmanı: `agent-usage.md` §2.

## Sınır testi

> *"Bu ajanın brifingde bulamadığı her şeyi nereden bulacağını biliyor mu —
> yoksa uyduracak mı?"*

## İlişkili
- `agent-usage.md` — iş→ajan matrisi ve model katmanı
- `calisma-protokolu.md` — Danış / Kontrol Ettir adımları
