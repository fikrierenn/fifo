#!/usr/bin/env bash
# SessionStart hook — FIFO projesi. Her oturum başında git + hafıza özetini stdout'a yazar.
# Çıktı additionalContext olarak Claude'a görünür. Caveman SessionStart hook'u (user-level) ile yan yana çalışır — ezmez.
# Operax session-start.sh'tan fifo'ya adapte: docs/journal yerine memory/session_log, Operax'a özel kod-sağlığı kontrolleri çıkarıldı.

REPO="${CLAUDE_PROJECT_DIR:-D:/Dev/fifo}"
cd "$REPO" 2>/dev/null || exit 0

MEM="${HOME}/.claude/projects/d--Dev-fifo/memory"

echo "## FIFO — Oturum Başı Özet"
echo ""

echo "### Son 3 gün commit'ler"
git log --since='3 days ago' --oneline 2>/dev/null | head -10 || echo "(git log yok)"
echo ""

echo "### Uncommitted dosya"
count=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
echo "$count dosya"
if [ "${count:-0}" -gt 15 ]; then
  echo "UYARI: 15 dosya eşiği aşıldı — yeni işe başlamadan commit planla."
fi
echo ""

# .claude/CLAUDE.md SON DURUM bloğu (statik kimlik/durum — compact sonrası re-inject edilir ama burada öne çıkar)
if [ -f ".claude/CLAUDE.md" ]; then
  echo "### SON DURUM (.claude/CLAUDE.md)"
  awk '/^## SON DURUM/{f=1} f&&/^## CONTEXT INDEX/{exit} f' .claude/CLAUDE.md 2>/dev/null | head -15
  echo ""
fi

# En son oturum logu (memory/ repo dışı)
if [ -f "$MEM/session_log.md" ]; then
  echo "### En son oturum logu (memory/session_log.md — son 25 satır)"
  tail -25 "$MEM/session_log.md" 2>/dev/null
  echo ""
fi

# ── DANISMAN ISARETLERINI TEMIZLE ──
# Kapi "bu OTURUMDA ilk dokunus" iddia ediyor; isaret kalici olursa iddia
# YALAN olur. Bel'de olculdu: bes isaret 11 gun boyunca silinmedi ve kapi
# hicbir seyi bloklamadi. Burada her oturum basinda sifirlaniyor.
ISARET_DIZIN="$REPO/.claude/.advisor-marks"
if [ -d "$ISARET_DIZIN" ]; then
  silinen=$(find "$ISARET_DIZIN" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
  find "$ISARET_DIZIN" -maxdepth 1 -type f -delete 2>/dev/null
  [ "${silinen:-0}" -gt 0 ] && echo "### Danışman işaretleri sıfırlandı ($silinen alan)" && echo ""
fi

# ── ACIK PLAN (Tier 3 kapisi bunu arar) ──
echo "### Açık plan (Tier 3)"
acik=""
for f in "$REPO"/plans/[0-9]*.md; do
  [ -e "$f" ] || continue
  if grep -qiE '^\*\*Durum:\*\*.*(Onaylandı|Onaylandi|Uygulamada)' "$f" 2>/dev/null; then
    acik="$acik $(basename "$f")"
  fi
done
if [ -n "$acik" ]; then echo "AÇIK:$acik"; else echo "(yok — Tier 3 işte önce plan yaz)"; fi
echo ""

echo "### Kritik kurallar"
echo "- Tier sistemi + plan zorunluluğu: .claude/rules/plan-first.md"
echo "- Danış → Yap → Kontrol Ettir → Smoke: .claude/rules/calisma-protokolu.md"
echo "- Ölçtüm mü çıkardım mı: .claude/rules/olctum-mu-cikardim-mi.md"
echo "- Hafıza/oturum protokolü: .claude/rules/memory-protocol.md"
echo "- Agent delegasyon + model katmanı: .claude/rules/agent-usage.md"
echo "- Ajan brifingi (5 madde): .claude/rules/danisman-brifingi.md"
echo "- Çalışmalar LOKAL DB üstünde (canlı 192.168.40.201 sıkıntılı): memory/feedback_local_db.md"
echo "- FIFO invariant doğrulama: /fifo-dogrula · FIFO mantık bulguları: memory/fifo_logic_findings.md"
echo "- Görev tipine göre memory/ routing: memory/MAIN_INDEX.md"

exit 0
