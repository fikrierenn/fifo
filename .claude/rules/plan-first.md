# Plan-First Disiplini (Tier Sistemi) — FIFO

_Eşikler ve akış `D:\Dev\bel\.claude\rules\plan-first.md` ve `D:\Dev\pusula`
üzerinden geldi. **SİNYALLER KOPYALANMADI, yeniden kuruldu.** Belinza'da geri
alınamayan şey "uygulanmış şema ve saatlerce koşmuş çekim"; burada geri
alınamayan şey **silinmiş maliyet defteri, yayınlanmış bir SMM rakamı ve
mali tabloya girmiş bir marj**._

_`alan-var-mi-sor.md` dersi: kopyalanan desende tehlike kodda değil
**gerekçededir**; gerekçe her hedefte yeniden kurulur._

## Temel kural

> **Tier 3 işte plan ZORUNLU. Plan onaylanmadan uygulanmaz.**

## Eşikler

| Tier | Tanım | Plan? | FIFO örneği |
|---|---|---|---|
| **1 — Önemsiz** | <30 satır, 1-2 dosya, yeni desen yok, geri alması kolay | **YOK** | yorum, PRINT metni, README |
| **2 — Standart** | <5 dosya, mevcut desen, **geri alınamaz yüzeye dokunmuyor** | **session_log satırı yeterli** | mevcut view'a kolon, yeni rapor sorgusu, Razor metni |
| **3 — Ağır** | aşağıdaki sinyallerden **BİRİ** | **TAM PLAN** (`plans/NN-<slug>.md`) | master, katman yazan SP, constraint, cutover |

## Tier 3 sinyalleri — FIFO'ya özgü

Şunlardan **biri** varsa Tier 3:

1. **Deploy scripti / master değişiyor.** `00_V2_MASTER_FULL.sql`,
   `01_V2_Tables.sql`, `tools/build-master.sh`.
   _Ödenmiş vaka (2026-09-10): master 7 çekirdek tabloyu koşulsuz DROP
   ediyordu; `FifoKatman` (maliyet defteri) ve `FifoCikisDetay` (SMM detayı)
   dahil. "Idempotent, re-deploy güvenli" sanılıyordu. İkinci deploy tüm
   defteri silerdi. **Aynı kusurdan ikincisi `12_V2`de duruyordu ve ilk
   düzeltme turunda gözden kaçtı** — çünkü o tablo lokalde boştu._

2. **`FifoKatman` veya `FifoCikisDetay`'a yazan/silen kod değişiyor.**
   Maliyet defteri budur. Bir satır fazla ya da eksik = yanlış SMM.
   _Ödenmiş vaka: açılış aylık devir katmanını `ISNULL(...,0)` ile
   FİLTRESİZ yazıyordu; kardeş SP'de aynı yerde `WHERE BirimMaliyet > 0`
   VARDI. İki SP aynı işi farklı yapıyordu ve kimse fark etmemişti._

3. **Constraint / değişmez sıkılaşıyor ya da gevşiyor.**
   Bir CHECK eklemek "sadece DDL" değildir: o güne kadar sessizce yazılan
   satır artık **çalışmayı durdurur**.
   _Ödenmiş vaka: `BirimMaliyet > 0` constraint'i, açılışın kendi 0-yazan
   kod yolunu 547 ile öldürecekti. Boş veritabanı testi bunu göremez._

4. **Fallback kademesi, tier sırası veya devre-dışı politikası değişiyor.**
   Bu deponun **en pahalı** sınıfı: sonuç yanlış değil, **bir ürünün maliyeti
   sessizce başka yerden geliyor**.
   _Ödenmiş vakalar: 1-TL sabit fallback Ocak'ı +1,37M şişirdi (272 kalem) ·
   salt kategori-imputation gerçek ürünleri yanlış devre-dışı yaptı._

5. **Uzun pipeline koşuyor** (açılış, `AylikRutinFull`, ortalama).
   Başladıktan sonra kod değişirse iş **bayatlar** → `kosan-is-bayatlar.md`.

6. **Bir sayı mali tabloya / CFO raporuna gidiyor.**
   Gelir, SMM, brüt kâr, marj. Yayınlanmış rakam geri alınamaz; düzeltme
   **restatement** olur ve açıklanması gerekir.

7. **Prod cutover** (192.168.40.201). Ayrı ve açık onay ister.

## Akış

```
Ölç → Tier → [Tier 3] Plan → ONAY → DANIŞ → YAP → KONTROL ETTİR → SMOKE → session_log
```

Detay: `calisma-protokolu.md`.

## Plan dosyası

`plans/NN-<slug>.md`, şablon `plans/plan-sablonu.md`.
Zorunlu bölümler: Problem · Kapsam (dahil/hariç/etkilenen) · Adımlar ·
Riskler+mitigasyon · **Done kriterleri (ölçülebilir)** · Rollback.

`**Durum:**` satırı `Taslak` → `Onaylandı` → `Uygulamada` → `Tamamlandı`.
Kapı (`tier3-plan-gate.sh`) `Onaylandı`/`Uygulamada` arar.

⚠ **Plan bitince Durum'u güncelle.** 2026-09-10'da ölçüldü:
`docs/PLAN-uretim-master-deploy.md` yedi adımın yedisi de işaretsiz
duruyordu, oysa hepsi bitmiş ve commit edilmişti. Bayat plan, planın
yokluğundan kötüdür — okuyan yanlış yerde sanır.

## Sınır testi

> *"Bu değişiklik yanlışsa, yanlışlığı NEREDE görürüm — derlemede mi,
> deploy'da mı, yoksa ancak bir CFO raporundaki marj tuhaf gelince mi?"*

Cevap üçüncüyse Tier 3'tür.

## İlişkili
- `calisma-protokolu.md` — dört adım
- `.claude/hooks/tier3-plan-gate.sh` — bu kuralın kapısı
- `fifo-domain.md` — bağlayıcı domain kuralları
