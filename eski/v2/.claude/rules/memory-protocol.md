# Oturum & Hafıza Protokolü (FIFO)

> Operax `session-memory.md` + `session-protocol.md`'den fifo'ya adapte.
> ÖNEMLİ: Fifo'nun ZATEN bir hafıza sistemi var (`memory/` + MAIN_INDEX). Bu dosya o sistemin oturum disiplinidir — yeni/mükerrer sistem KURMAZ. `paths:` yok (compact sonrası geçerli).

## 1. Bilgi Katmanları — her bilgi TEK yerde
| Katman | Nerede | Ne yazılır |
|---|---|---|
| **Kimlik** | `CLAUDE.md` (kök) + `.claude/CLAUDE.md` | Proje tanımı, tech stack, kurallar indeksi, SON DURUM |
| **Kurallar** | `.claude/rules/*.md` | Davranış/agent/hafıza disiplini |
| **Kalıcı bilgi** | `memory/*.md` (repo dışı: `~/.claude/projects/d--Dev-fifo/memory/`) | semantic_layer, schema, db_live_state, findings, feedback |
| **Süreç** | `memory/project_status.md` + `memory/session_log.md` | Sıradaki görevler, oturum logları |

**Kural:** Aynı bilgi iki dosyada yaşamaz. Kural değişirse konuşmada bırakılmaz → ilgili dosya güncellenir. Yeni kalıcı bilgi → `memory/` + MEMORY.md index satırı.

## 2. Compact / Clear Disiplini
- **Compact ne zaman:** bağlam %60'ı aşınca; uzun okuma/arama dizisi bitince.
- **Clear ne zaman:** ana görev tamamen değişince; "poisoned" döngüsel hata durumunda.
- **Compact sonrası hayatta kalan:** `CLAUDE.md` (kök+.claude) ✅ otomatik re-inject · `.claude/rules/*.md` ✅ · konuşma geçmişi ❌ (özet kalır) · `memory/*.md` ⚠️ sadece okunduysa.
- **Kritik:** Kalıcı kararlar konuşmada bırakılmaz; `memory/` veya `.claude/rules/`'a yazılır (pre-compact hook snapshot alır ama tek güvence değil).

## 3. Oturum Başı (ilk yanıttan önce)
SessionStart hook git özeti + son session_log girdilerini inject eder. Ana ajan:
1. `.claude/CLAUDE.md` SON DURUM'u oku → nerede kaldık.
2. Göreve göre `memory/` routing (MAIN_INDEX tablosu): SQL→schema, mantık→semantic_layer, deploy→db_live_state.
3. `git status` — uncommitted çok ise önce commit planı.

## 4. Oturum Ortası
- **En fazla 3 paralel görev** — biri bitmeden yeni başlığa geçme.
- **Kararı anında yaz:** yeni kural → `.claude/rules/`; yeni kalıcı bilgi → `memory/`. Konuşmada bırakma.
- **3+ dosya etkileyen iş:** önce kapsam (Spec) → `memory/project_status.md` Sırada (Plan) → kod (Execute).
- **Kod körlemesine kullanma** (kullanıcı kuralı): dış kaynaktan (Operax vb.) gelen kodu sorgula, doğrula, fifo'ya adapte et — kopyalama.

## 5. Oturum Sonu (Handoff)
Kullanıcı "kapatabiliriz / iyi geceler / devam edeceğiz / handoff" derse:
1. `memory/session_log.md` güncelle: Ana konu · Tamamlananlar (dosya:satır) · Build durumu · Git/commit · Yarım kalan · Yarına 1-3 somut adım.
2. `.claude/CLAUDE.md` SON DURUM'u güncelle (deploy varsa `memory/db_live_state.md` + `project_status.md`).
3. **CLAUDE.md'ye tarihli günlük YAZMA** — statik kimlik+indeks; günlük `session_log.md`'ye.

## İlişkili
- `memory/MAIN_INDEX.md` — routing + güncelleme protokolü (asıl referans)
- `.claude/rules/agent-usage.md` — delegasyon disiplini
- `.claude/hooks/session-start.sh`, `pre-compact.sh` — bu protokolü otomatikleştirir
