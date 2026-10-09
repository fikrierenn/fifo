---
name: sema-ogren
description: >
  Öğrenilen şema/iş gerçeğini FIFO semantik katmanına yazar. Bir sorguyla yeni
  bir köprü, kod kümesi, tablo grain'i, formül ya da "X asla olmaz" tipi bir
  gerçek doğrulandığında tetiklenir. "sema'ya yaz", "bunu kaydet", "öğrendik",
  "değişmez ekle", "bu bir daha unutulmasın" ifadelerinde ve anlamlı her keşif
  sorgusundan sonra devreye gir. Koşulabilir gerçeği degismezler.json'a,
  yapısal gerçeği YAML'a yazar; keşif SQL'ini arşivler.
---

# sema-ogren — FIFO Semantik Katmanına Yaz

## Ne zaman
Bir sorgu çalıştırdın ve **daha önce yazılı olmayan** bir gerçek çıktı.
Tek satırlık sanity-check hariç, anlamlı her keşiften sonra.

## Karar ağacı — nereye yazılır

```
Öğrenilen gerçek
├── "X ASLA olmaz / hep şu kümededir" ve TEK SORGUYLA ölçülebiliyor
│      └── sema/degismezler.json   ← ÖNCE BURAYI DENE (koşar)
├── join / FK / cross-DB bağ            → sema/bridges.yaml
├── tablo/view + PK + grain             → sema/entities.yaml
├── enum / lookup değer kümesi          → sema/codes.yaml
├── formül / hesap modeli               → sema/metrics.yaml
└── satır verisi (liste)                → HİÇBİRİ. Kodda canlı sorgula.
```

**Ayrım testi (satır verisi mi):** *"Bu bilgi 6 ay sonra hâlâ doğru mu?"*
Hayırsa yazma.

**Ayrım testi (değişmez mi ölçüm mü):** *"Bu iddia yarınki veriyle de doğru
mu?"* Evetse değişmez; hayırsa ölçümdür ve `dogrulandi`/`evidence` alanına
tarih damgasıyla yazılır.

## Değişmez yazma akışı — beş adım, atlanmaz

### 1. Kaydı yaz
```json
{
  "id": "kisa-kebab-ad",
  "db": "BKMMaliyet",
  "soru": "Tek cümlelik soru, cevabı sayı olan",
  "neden": "KIRILDIGINDA NE YAPILACAGINI soyleyen gerekce. Hangi rapor bozulur, hangi hata sinifi geri gelir.",
  "sql": "SELECT COUNT(*) FROM ... WHERE <ihlal kosulu>",
  "karsilastirma": "esit",
  "beklenen": 0,
  "dogrulandi": "YYYY-MM-DD -> <olculen deger> (<hangi DB, hangi kosum>)"
}
```

`karsilastirma`: `esit` · `enaz` · `encok`.
**Gerekçesiz kayıt kabul edilmez** — koşucu yapısal olarak reddeder.

### 2. Yeşil olduğunu gör
```bash
pwsh tools/fifo-degismez.ps1 -Sadece <id> -Ayrintili
```

### 3. KIRILABİLDİĞİNİ KANITLA — pazarlıksız
`beklenen` değerini bilerek boz, **kırmızı gör**, geri al.
Ya da kaydın kırmızı vereceği bir veritabanına çevir.

> Kırılabildiği kanıtlanmamış bir test, test değildir.

Bu adım atlanırsa kayıt **yazılmamış sayılır**.

### 4. Tam seti koştur
```bash
pwsh tools/fifo-degismez.ps1
```
Çıkış 0 olmalı. Değilse ya yeni kayıt hatalı ya gerçekten bir şey kırık.

### 5. Keşif SQL'ini arşivle (ikiz yükümlülük)
`sorgular/YYYY-MM-DD-<konu>.sql` — çalıştırılabilir, başına 2-3 satır yorum
(ne sorusu, hangi DB, bulgu özeti).

Sema "ne öğrendik" der, arşiv "nasıl bulduk" der. Biri olmadan diğeri eksik.

## YAML tarafı (bridges / entities / codes / metrics)

Dosya henüz yoksa **kur** — `footprint-ladder.md` gereği ihtiyaç doğmadan
açılmamıştı. Kayıt biçimi:

```yaml
- id: <kebab-ad>
  <alanlar>
  confidence: 0.95        # 1.0 kalici (PK/FK) · 0.9-0.99 canli dogrulandi
                          # 0.5-0.8 gozlem · 0.3-0.5 hipotez
  evidence: "YYYY-MM-DD — nasil dogrulandi, hangi sorgu, kac satir"
  last_verified: YYYY-MM-DD   # confidence 1.0 ise GEREKMEZ (muaf)
  ttl_days: 180
```

- **Duplikasyon yok** — aynı gerçek varsa güncelle, satır açma.
- **Çelişki** — yeni gerçek eskiyi çürütürse eskiyi sil ya da
  `note: superseded` ile düşür.
- **Stale kayıt** (`last_verified + ttl_days < bugün`) körü körüne
  kullanılmaz; canlı doğrula, damgayı bugüne çek.

## "Başka ne olabilir?" kapısı

Bir bulgu yazılmadan önce **en az bir alternatif açıklama** kurulup elenir.
Elenemiyorsa kayıt **ÇIKARIM** etiketi ve düşük confidence ile yazılır.

_En tehlikeli hata yorum hatasıdır: ölçüm doğrudur, ona konan ad yanlıştır
ve ölçülmüş gibi sunulur._

## Ortam

```bash
# tek sorgu
cd D:/Dev/fifo && dotnet run --project D:/Dev/sqlcli -- query "<SQL>"
# ya da
Invoke-Sqlcmd -ServerInstance 'BT-FIKRI' -Database 'BKMMaliyet' -Query "<SQL>"
```

Tuzaklar: `sql-server-conventions.md` (sqlcli stderr/max-rows, iki tip
sözlüğü, mekan havuzu, SARGable, NULLIF).

## Yazmadan önce kontrol
- [ ] Bu gerçek `sema/`da zaten var mı? (duplikasyon)
- [ ] Satır verisi mi, kural mı?
- [ ] Değişmez mi, ölçüm mü?
- [ ] Gerekçe "kırıldığında ne yapılacağını" söylüyor mu?
- [ ] Kırılabildiği kanıtlandı mı?
- [ ] Keşif SQL'i arşivlendi mi?

## İlişkili
- `sema/README.md` · `.claude/rules/semantic-layer.md`
- `tools/fifo-degismez.ps1` — koşucu
- `.claude/rules/olctum-mu-cikardim-mi.md`
