<!-- merkez-bildirimi -->
# MERKEZ BİLDİRİMİ — kurallar artık tek yerde (23.09.2026)

> **Kuralı kopyalama, işaret et.** Kopyalanan kural bayatlar ve iki gerçek doğar.
> Kanonik merkez: `../claude-context-template/`
> Tam rehber: `../claude-context-template/docs/TUKETICI-REHBERI.md`
> Gerekçe ve ölçüm: `../claude-context-template/docs/ASAMA-1-TEK-MERKEZ-2026-09-23.md`

## 0. BU DEPONUN ÖLÇÜMÜ (`bin/durum.sh`, 23.09.2026)

| aynı | sapma | yerel | toplam | model |
|--:|--:|--:|--:|---|
| 0 | **5** | 11 | 16 | KOPYA |

Bu depoda şablon kurallarının **kopyası var**. O kopyalar artık kanonik **değil** — 3. bölümdeki göç geçerlidir.

### Merkezin ilerlediği dosyalar — bu depoda AYRIŞMIŞ (23.09.2026)

Merkez şu dosyalarda 23.09.2026'da ilerledi **ve** buradaki kopya farklı:

- `error-handling.md`
- `footprint-ladder.md`

⚠ **"Ayrışmış" bayat demek DEĞİLDİR — yön ölçülmedi.** `durum.sh` skaler
ölçer: iki dosyanın farklı olduğunu söyler, hangisinin ileride olduğunu
söylemez. İki tüketici bunu bağımsız olarak ölçtü ve **her dosyada her iki
yönde de fark** buldu. Kopyayı "bayat" sanıp silmek, burada olgunlaşmış
bir kuralı ekosistemden sessizce yok eder.

Her farkı **üç kovadan birine** koy (`--diff` ile, tercihle değil ölçümle):

| Kova | Ne yapılır |
|---|---|
| **MERKEZ İLERİDE** | al |
| **KARŞILIKLI** | buradaki kısım merkeze terfi (`harvest.sh --promote`), merkezdeki alınır |
| **YERELLEŞTİRİLMİŞ** | yapı aynı, yalnız örnek/alan farkı — **dokunma** |

## 1. Oturum başı

```bash
ls ../claude-context-template/templates/.claude/rules/_universal/*.md   # 18 kanonik kural
```

Ekosistem ölçümü: 39 depo · **169 sapmış kural** · sapması sıfır olan tek depo
`bkm-magaza` — çünkü kopyalamıyor. Hedef, o satırı 39 kere yazdırmak.

## 2. Türkçe tanımlayıcı kapısı — çağır, kopyalama

Kod İngilizce, **yorum ve arayüz metni Türkçe**. Kapı yorumlara ve dizelere dokunmaz.

```bash
python ../claude-context-template/tools/turkce_tanimlayici_denetimi.py <dosya...>
```

Kancadan çağırırken üç şart:
1. **Yalnız yeni/dokunulan dosyaları ver.** Var olan Türkçe adları taramak her commit'i
   bloklar → kapı ilk gün kapatılır.
2. **Araç yoksa ya da koşamazsa SARI uyar**, sessizce geçme. Sessiz geçen kapı, hiç
   olmayan kapıdan beterdir: çalışıyor *görünür*.
3. Süpürme kipi istiyorsan `.claude/turkce-kapi.json` yaz; yoksa kapı KOŞAMADI der.

İsteğe bağlı tüketici dosyaları:
`.claude/turkce-kapi.json` (kapsam, alan adları) ·
`.claude/kod-sozcukleri.ek.txt` (bu deponun ALAN sözcükleri) ·
`.claude/turkce-taban.json` (devralınmış borcu dondurmak)

⚠ **Ak liste ayrımı:** dilin kendi sözcüğü (`Deleted`, `Timer`) → merkezdeki çekirdek
liste. Bu deponun alan adı → kendi ek dosyası. Yanlış yere konursa ya merkez bir
tüketiciye bağımlı olur ya da başka depolarda hatalı bulgu üretir.

## 3. Göç — kopyadan referansa

⚠ **TOPLU SİLME YOK.** Her sapmanın *bayat mı bilerek mi* olduğu insan kararıdır.

```bash
bash ../claude-context-template/bin/harvest.sh --diff <dosya> fifo
```

| Fark neyse | Karar |
|---|---|
| Yalnız merkez ilerlemiş | **bayat** → kopyayı sil, merkeze işaret et |
| Bu depoya özgü bir gerçek | **bilerek** → kural yerel kalır, **gerekçesi dosyanın ilk satırlarına yazılır** |
| Burada olgunlaşmış, evrensel | **terfi** → `harvest.sh --promote`, silme |

Gerekçeli yerel kural deseni (`bkm-magaza/.claude/rules/capacitor-kabuk.md`):
*"Bu kural yerel, çünkü komşu depo .NET/SQL odaklı; mobil paketleme orada yok."*
**Gerekçesiz yerel kural kabul edilmiyor.**

## 4. Üç uyarı

1. **Depo adı değişecek:** `claude-context-template` → **`Norma`** (Aşama 2'de,
   `bootstrap --reference` ile birlikte). Yolu bu depoda **tek bir yere** yaz; her
   kancaya gömersen ad değiştiğinde hepsini tek tek düzeltmek zorunda kalırsın.
2. **Aynı depoda başka oturum çalışıyor olabilir.** Kırıcı dokunuştan **önce** tek
   satır haber.
3. **Önce ve sonra ölç:** `bash ../claude-context-template/bin/durum.sh`. Bu deponun
   satırında `sapma` düşmeli, `model` sütunu **REFERANS** olmalı. Ölçmediysen göç
   olmamıştır.

---
*Bu dosya merkez tarafından bırakıldı (Aşama 1 · 23.09.2026). Aşama 2 ve 3 YAPILMADI:
`bootstrap --reference` kipi yok, 37 deponun göçü her deponun kendi oturumundadır.*
