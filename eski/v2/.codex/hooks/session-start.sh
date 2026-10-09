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

echo "### Kritik kurallar"
echo "- Hafıza/oturum protokolü: .claude/rules/memory-protocol.md"
echo "- Agent delegasyon + model katmanı: .claude/rules/agent-usage.md"
echo "- Çalışmalar LOKAL DB üstünde (canlı 192.168.40.201 sıkıntılı): memory/feedback_local_db.md"
echo "- FIFO invariant doğrulama: /fifo-dogrula · FIFO mantık bulguları: memory/fifo_logic_findings.md"
echo "- Görev tipine göre memory/ routing: memory/MAIN_INDEX.md"

exit 0
