# Agent Kullanım Disiplini (FIFO)

> Operax `agent-usage.md`'den fifo'ya adapte. Ana ajanın işleri alt-ajanlara nasıl dağıtacağı + model katmanı seçimi. `paths:` yok — compact sonrası da geçerli.

## 1. Temel İlke
**`general-purpose`'u varsayılan yapma.** Her iş için en dar kapsamlı özelleşmiş ajanı seç. Özel ajan yoksa `general-purpose` kullan ama `model` parametresini işe göre elle ata — varsayılana bırakma.

## 2. Model Katmanı (ZORUNLU farklılaştırma)
| Model | Ne zaman | Örnek iş |
|---|---|---|
| **haiku** | Mekanik, deterministik, düşük-muhakeme; hızlı tarama | dosya/sembol arama, build/test çalıştır, şema diff, GO sayımı, satır sayımı |
| **sonnet** | Dengeli analiz + üretim; orta muhakeme | yeni Razor sayfa, view yazımı, kod review (kural uyumu), orta keşif |
| **opus** | Derin muhakeme, çok-adımlı, yüksek-risk | FIFO SP iş-doğruluğu, silent-failure avı, güvenlik review, mimari karar |

**Kural:** Her Agent/Task çağrısında model'i bilinçli seç. Eşit harcama (her şeye opus / her şeye general-purpose) yasak.

## 3. İş → Ajan Matrisi (fifo)
| İş türü | Ajan | Model |
|---|---|---|
| "X nerede / Y referansı / keşif" (app/ + v2-production/) | `code-explorer` | haiku |
| FIFO SP/View iş-doğruluğu (transaction/THROW/katman-tüketim/mekan-kapsam/invariant) | `sql-sp-reviewer` | opus |
| Silent failure / error handling (C#/Razor + SP) | `silent-failure-hunter` | opus |
| Build derle + hata/uyarı say (fifo.sln) | `build-validator` | haiku |
| v2-production şema ↔ canlı/lokal DB farkı (sqlcli) | `db-schema-checker` | haiku |
| FIFO↔ERP mutabakat (STOK_YETERSIZ/sıfır maliyet/IADE/C8 fark) | `maliyet-stok-uzman` | opus |
| Sorunlu ürün tek tek inceleme + sınıflandırma (FIYAT_YOK/cost anomali/non-inventory) | `sorunlu-urun-dedektif` | opus |
| Hiçbiri uymuyor (genel çok-adımlı) | `general-purpose` | işe göre elle ata |

> Operax'ta olup fifo'da OLMAYAN (kasıtlı): `pgsql-porter` (PostgreSQL yok), `commit-splitter`, `code-architect`, `code-reviewer`, `reference-researcher`, `security-reviewer`, `test-runner`. Gerekirse eklenir; körlemesine port edilmedi.

## 4. Paralellik
- Bağımsız işleri tek mesajda paralel başlat.
- N dosya/N SP → her birine ayrı dar-kapsam ajan; ana ajan sentezler.
- Onlarca-ajan orkestrasyon sadece kullanıcı "workflow" derse / ultracode açıksa.

## 5. Salt-Okuma Disiplini
- Denetim/keşif ajanları YAZMA tool'u almaz (Edit/Write yok): code-explorer, sql-sp-reviewer, silent-failure-hunter, build-validator, db-schema-checker = read-only (+ gereken Bash).

## 6. Çıktı Beklentisi
- Her denetim ajanı **kanıt** + **confidence** raporlar; tahmin yasak. Emin değilse "DOĞRULANMADI" der.
- Ajan final mesajı ana ajana döner → ana ajan özetler.

## 7. Yeni Ajan Eklerken
1. `.claude/agents/<name>.md` — YAML frontmatter ZORUNLU: `name`, `description`, `tools`, `model`.
2. Frontmatter yoksa = ölü ajan (registry'ye girmez).
3. `description` "ne zaman çağrılır" + proaktif tetikleyici içersin.
4. Bu matrise (§3) satır ekle.

## İlişkili
- `.claude/rules/memory-protocol.md` — oturum/hafıza disiplini
- `memory/fifo_logic_findings.md` — FIFO invariant bağlamı (sql-sp-reviewer kullanır)
