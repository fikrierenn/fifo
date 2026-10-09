# Çalışma Protokolü — Danış → Yap → Kontrol Ettir → Smoke

_Belinza `calisma-protokolu.md`den uyarlandı. **Gerekçe kopyalanmadı**
(`alan-var-mi-sor.md`): orada tetikleyiciler ayna kapsamı ve Odoo anlamı;
burada **maliyet defterinin bütünlüğü, bir fiyat kademesinin anlamı ve
deploy'un veri kaybettirmemesi**._

_Doğuş sebebi ölçüldü. 2026-09-10'da master düzeltmesi `Yap` ile başladı,
`Danış` atlandı. Sonuç: aynı sınıftan ikinci bir yıkıcı DROP (`12_V2`)
gözden kaçtı, sıkılaştırılan constraint açılışın kendi kod yoluyla
çatıştı, ve reset dosyasına canlı-DB silme tuzağı kondu. **Üçünü de
`Kontrol Ettir` adımındaki iki bağımsız ajan buldu, ben bulmadım.**_

## Kural

> **Her substantive iş bu dört adımdan geçer.** Tier 1 önemsiz hariç.

`plan-first.md` akışı bunun içine oturur:

```
Ölç → Tier → [Tier 3] Plan → ONAY → DANIŞ → YAP → KONTROL ETTİR → SMOKE → session_log
```

## 1. DANIŞ (üretimden ÖNCE)

Danışman **SALT-REHBER**: ölçüm yapmaz, kod yazmaz. Ona **dosya yolu ve
ölçüm çıktısı** verilir (`danisman-brifingi.md`).

| iş türü / tetik | danışman |
|---|---|
| Maliyet yöntemi · fallback tier tasarımı · devre-dışı politikası · "bu rakam mali tabloya yazılabilir mi" · restatement | **`fifo-danisman`** |
| Deploy / master / cutover / geri dönüş · "bu script veri kaybettirir mi" | **`fifo-deploy-danismani`** |
| Constraint · değişmez · hook · `/fifo-dogrula` kontrolü · "bu kapı totolojik mi" | **`fifo-kapi-danismani`** |
| Yazılacak T-SQL'in biçimi ve kalıbı | Skill **`fifo-sql-developer`** |

**Danışılmadan yapılan constraint / deploy / tier işi EKSİK sayılır.**

Ödenmiş vakalar — hepsi *"danışsaydım"* vakası:

| ne oldu | hangi danışman yakalardı |
|---|---|
| `12_V2`de ikinci koşulsuz `DROP TABLE` gözden kaçtı (tablo lokalde boş olduğu için test görmedi) | `fifo-deploy-danismani` |
| `BirimMaliyet > 0` constraint'i açılışın 0-yazan kod yoluyla çatıştı | `fifo-kapi-danismani` |
| `01a` reset dosyasına `USE BKMMaliyet;` konuldu; kendi kullanım örneği test DB'sini gösteriyordu → canlı defter silme tuzağı | `fifo-deploy-danismani` |
| 1-TL sabit fallback non-inventory'yi %100 marj sayıp Ocak'ı +1,37M şişirdi | `fifo-danisman` |

## 2. YAP

Uygula. Disipline uy (`plan-first.md`, `fifo-domain.md`,
`fifo-sql-developer` skill, `olctum-mu-cikardim-mi.md`).

**Yargı kararı verdiğin her noktayı işaretle** — adım 3'te sınanacak.
Yargı kararı: eşik değeri, kapsam süzgeci, tier sırası, tolerans,
"bu satır elenmeli mi", "bu ürün devre-dışı mı".

## 3. KONTROL ETTİR — bağımsız ve adversarial (üretimden SONRA)

**Öz-onay YOK** (yapan ≠ onaylayan). İki katman:

**(a) Denetçi** — Bash'i **var**, ölçüm üretir:
`sql-sp-reviewer` (SP iş doğruluğu) · `silent-failure-hunter` (yutulan hata) ·
`maliyet-stok-uzman` (ERP mutabakat) · `sorunlu-urun-dedektif` (ürün bazlı
kök neden) · `db-schema-checker` · `build-validator`.

**(b) DANIŞMANA GERİ GÖTÜR** — protokolün özü:

> *"Yaptım. Verdiğim yargı kararı (eşik, kapsam, tier sırası, tolerans)
> doğru mu? Bu kapı hangi arıza kipini KAÇIRIYOR? Bir maliyetin kaynağı
> değişti mi ve onu okuyan rapor var mı?"*

**Adversarial:** "doğru" varsayma, kırmaya çalış. Emin değilse
**DOĞRULANMADI** de.

2026-09-10'da bu adım karşılığını verdi: iki ajan, altı bulgu, **üçü
kritik ve üçü de benim gözümden kaçmıştı.**

## 4. SMOKE

*"Derlendi / master 0 hata ile deploy oldu"* **YETMEZ**.

Ölçülmüş vaka: master boş bir veritabanına iki kez sorunsuz deploy oldu ve
**canary satırı hayatta kaldı**. Aynı master, dolu veritabanında
çalıştırılmamıştı; oradaki üç kusurun hiçbiri boş-DB testinde görünmezdi.

| dokunulan | kanıt |
|---|---|
| Deploy scripti / master | **Boş DB'ye iki kez** + **DOLU DB'ye bir kez**. Canary satır koy, deploy sonrası hayatta mı bak. |
| Tablo / constraint | İhlal eden satırı INSERT etmeyi dene → **reddedildiğini gör** (hata 547). |
| Katman yazan SP | Tam pipeline koş → `BirimMaliyet <= 0` sayısı **0** + `/fifo-dogrula` C1-C7. |
| Fallback / tier | Ocak referansıyla **birebir marj mutabakatı**. Sapma varsa açıkla. |
| Build scripti | Üretilen çıktıyı **doğrula** (obje sayısı, sızıntı, yasak desen) ve kırılabilirliğini sına. |
| Razor sayfa | `preview_start` → yenile → içerik + **0 konsol hatası**. |

Sonucu **çıktıyla** raporla. Kırmızıysa söyle, gizleme.

⚠ **Yıkıcı testi kopyada yap.** Referans veritabanında pipeline yeniden
koşturulmaz: koşu başarısız olursa karşılaştıracağın referans da gider.
`BACKUP ... COPY_ONLY` + `RESTORE` ucuzdur (3,3 GB veritabanı 62 MB yedek).

## Atlanırsa

1. **Kabul et** — mazeret yok.
2. Dön, eksik adımı tamamla.
3. *"Derlendi = bitti"* ve *"yaptım = doğru"* varsayımı **YASAK**.

## Sınır testi

> *"Bu işi yapmadan önce kime danıştım, yaptıktan sonra kim kontrol etti,
> ve gerçekten çalıştığını nerede GÖRDÜM?"*

Üçünden biri boşsa protokol atlanmıştır.

## İlişkili
- `plan-first.md` · `danisman-brifingi.md` · `dogrulama-siniri.md`
- `.claude/hooks/pre-edit-advisor-gate.sh` — bu kuralın 1. adımının kapısı
