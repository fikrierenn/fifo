# SQL Server / DerinSIS Konvansiyonları — FIFO

_pusula `sql-server-conventions.md`den **yalnız FIFO'yu ilgilendiren** kısımlar
alındı ve bu deponun ölçümleriyle doğrulandı. EncoreMerkez/POS, e-ticaret
(JOKER), DerinCrm ve Blazor bölümleri **kasten alınmadı** — bu depoda
karşılıkları yok (`footprint-ladder.md`: taşımadığın yüzey bakım yükü
getirmez)._

## Ortam

| | |
|---|---|
| Lokal instance | **`BT-FIKRI`** (named instance YOK), SQL Server 2022 Developer |
| DB dosyaları | `D:\SQLData` |
| Maliyet DB | `BKMMaliyet` · doğrulama kopyası `BKMMaliyet_Test` |
| ERP kaynağı (lokal) | **`DerinSIS_Local`** (`DerinSISBkm` DEĞİL — karışmasın) |
| Canlı | `192.168.40.201` — **erişilemez** (VPN/kapalı) |
| Kapsam | yıl **2026**, devir **2025-12-31** |

Deploy: `Invoke-Sqlcmd -ServerInstance 'BT-FIKRI' -InputFile ... -Variable "MaliyetDb=X","ErpDb=Y"`
Tek sorgu: `sqlcli` (kanonik kopya **`D:\Dev\sqlcli`**).
**`sqlcmd.exe` bu makinede ODBC hatası veriyor — kullanma.**

## DerinSIS tip kodları — İKİ AYRI SÖZLÜK (kritik)

`dbo.irsTip_vw` (34 kod) ve `dbo.fatTip_vw` (13 kod) **AYRI** sözlüklerdir.
Biri diğerine kopyalanamaz.

| | irsHrk (`ehTip`) | fat (`eTip`) |
|---|---|---|
| **10** | Yerel Alım (**alış**) | İade Fark Faturası (**alış DEĞİL**) |

- **FIFO alış kaynağı = fatura tarafı:** `fat` + `fatAyr`, `f.eTip IN (0, 2)`.
  Yön: `eGC = 0 → +`, `eGC = 1 → −`.
- **FIFO satış kaynağı = `irsHrk`:** `ehTip IN (1, 4, 5, 100, 101)`.
  `ehAdetN` çıkışta **negatif**; `ehTutarN` mutlak (pozitif).
- **İade:** satış iadesi `3, 5, 101` · alış iadesi `2`.
- `ehMaliyet` alış faturasında 0 olabilir — ayrı job günceller. Anlık 0,
  "maliyet yok" demek değil, "job koşmamış" demektir. **FIFO bunu kullanmaz.**

## Mekan havuzu — pazarlıksız

```sql
AND h.ehMekan IN (1, 12, 4477, 4478)
AND h.ehAltDepo = 0
```

**Mekan 12 = ANA DEPO**, şube değil, en büyük stok. Açılışta, çıkışta ve
ortalamada **aynı** set kullanılır; birini değiştiren üçünü değiştirir
(`fifo-domain.md` §1).

## Tarih

- Yerel sorgular DMY (`CONVERT(varchar, tarih, 104)`) ya da parametre.
- **`yyyy-MM-dd` string literal'ından kaçın**; `DATEFROMPARTS` veya
  parametre kullan.
- **SARGable yaz.** İndeksli kolona fonksiyon uygulama:

```sql
-- YANLIŞ (indeks kullanılmaz)
WHERE CAST(h.ehTrhS AS DATE) = @d
-- DOĞRU
WHERE h.ehTrhS >= @d AND h.ehTrhS < DATEADD(DAY, 1, @d)
```

## Para ve miktar tipleri

| Alan | Tip |
|---|---|
| Birim maliyet / fiyat | `DECIMAL(18,6)` |
| Miktar | `DECIMAL(18,4)` |
| Tutar | `DECIMAL(18,4)` |
| Hesaplanan tutar | `AS (Miktar * BirimMaliyet) PERSISTED` |

**`FLOAT` ve `MONEY` yasak.** Yuvarlama hatası maliyet defterinde birikir.

## TVF'i korelasyonlu alt sorguda satır-başı çağırma (19.06 dersi)

```sql
-- YANLIŞ: TVF N kez, her seferinde 6,5M satırı window'lar → timeout
WHERE EXISTS (SELECT 1 FROM fn_SonGecerliFiyat(@d,1) f WHERE f.fStkID = u.StkId)
```

**Doğrusu:** TVF'in iç mantığını çıkar, hedef ID filtresini scan'e **göm**,
`ROW_NUMBER` yalnız hedef satırlarda koşsun:

```sql
... WHERE f.fStkID IN (SELECT StkId FROM #hedef)
```

Aynı "filtreyi aşağı it" ilkesi. `fn_SonGecerliFiyat` 619 üründe böyle
timeout verdi, restrict-then-rownumber ile saniyelere indi.

Aynı sebeple `02_V2`de aylar üzerinde TVF çağıran bir cursor var
(`LOCAL FAST_FORWARD`); `CROSS APPLY` ile set-based yazılabilir, açık iş.

## Aggregate içinde alt sorgu

```sql
-- YANLIŞ: "Cannot perform an aggregate function on an expression
-- containing an aggregate or a subquery"
SUM(CASE WHEN x NOT IN (SELECT ...) THEN 1 ELSE 0 END)
```

Filtreyi `WHERE`'e taşı ya da JOIN'e çevir. `WHERE` içinde
`NOT IN (subquery)` serbesttir.

## Bölme

Her bölmede `NULLIF(payda, 0)`. Sıfıra bölme sorguyu **komple düşürür** ve
sessiz boş çıktı bırakır (ölçüldü 19.06, sqlcli dosyası boş sanıldı).

## Yasaklar (proje kuralı)

| Yasak | Yerine |
|---|---|
| `SELECT *` (`SELECT * INTO #temp` dahil) | açık kolon listesi |
| `MERGE` | `DELETE` + `INSERT` |
| `NOLOCK` **yeni kodda** | kaynak tarafta snapshot izolasyonu |
| `RAISERROR` | `THROW` |
| `DROP TABLE` üretim deploy scriptinde | `IF OBJECT_ID(...) IS NULL CREATE TABLE` |
| `FLOAT` / `MONEY` para için | `DECIMAL` |

⚠ Mevcut SP'lerdeki 22 `NOLOCK` **bilinçli korunuyor** (canlı ERP tablolarını
uzun maliyet koşusu boyunca kilitlememek için). Bulgu değil. Yeni okuma
eklerken ekleme.

## `THROW` öncesi noktalı virgül

T-SQL, `THROW`dan önceki ifadenin `;` ile bitmesini ister.
`END CATCH` sonrası unutulursa: **`Incorrect syntax near 'THROW'`**
(ölçüldü 2026-09-10, deploy testinde yakalandı).

```sql
END CATCH;   -- noktalı virgül ZORUNLU
THROW 50000, @ErrMetin, 1;
```

## `sqlcli` tuzakları

- **`--format json` sonucu stderr'e, banner stdout'a gider.**
  `2>/dev/null > f` sadece banner'ı kaydeder. Doğrusu: `--format json > f 2>&1`.
- Banner'daki ANSI escape içinde `[` var → önce
  `re.sub(r'\x1b\[[0-9;]*m','',raw)`, sonra `raw[raw.index('['):raw.rindex(']')+1]`.
- **`--max-rows` varsayılanı 1000 ve SESSİZ keser.** Satır sayısı belirsiz
  çekimde açıkça ver; dönen satır tam 1000 ise kesilme şüphesi.
- Kanonik kopya `D:\Dev\sqlcli`. `D:\Dev\fifo\sqlcli` eski fork.

## `Invoke-Sqlcmd` tuzakları

- Bu sürümde **`-TrustServerCertificate` parametresi YOK**.
- `PRINT` çıktısı verbose akışına gider: yakalamak için `-Verbose 4>&1`.
- Uzun pipeline için `-QueryTimeout` ver (varsayılan 30 sn yetmez).
- Pipeline koşarken sayım sorguları **kilide takılır**; bu engel değil,
  koşan iş olduğunun **işaretidir** (`kosan-is-bayatlar.md`).

## İlişkili
- `fifo-domain.md` — bağlayıcı domain kuralları
- `.claude/skills/fifo-sql-developer/SKILL.md` — yazım şablonları
- `alan-var-mi-sor.md` — kolon/kod var mı doğrulaması
