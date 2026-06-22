#!/usr/bin/env bash
# PreCompact hook — FIFO projesi. /compact öncesi ne üzerinde çalışıldığının snapshot'ı.
# Mevcut memory/session_log.md'ye append eder (yeni/mükerrer log sistemi kurmaz).
# memory/ repo dışında: $HOME/.claude/projects/d--Dev-fifo/memory. Erişilemezse repo docs/journal'a düşer.
# Operax pre-compact.sh'tan fifo'ya adapte (PLAN/TODO yerine project_status referansı).

REPO="${CLAUDE_PROJECT_DIR:-D:/Dev/fifo}"
cd "$REPO" 2>/dev/null || exit 0

MEM="${HOME}/.claude/projects/d--Dev-fifo/memory"
ts=$(date '+%Y-%m-%d %H:%M' 2>/dev/null)

if [ -d "$MEM" ]; then
  target="$MEM/session_log.md"
else
  mkdir -p docs/journal 2>/dev/null
  target="docs/journal/$(date +%Y-%m-%d 2>/dev/null).md"
fi
[ -f "$target" ] || { echo "# Oturum Logu" > "$target"; echo "" >> "$target"; }

{
  echo ""
  echo "## Compact Snapshot — $ts"
  echo ""
  echo "### Son 5 commit"
  git log --oneline -5 2>/dev/null | sed 's/^/- /' || echo "- (git log başarısız)"
  echo ""
  uc=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  echo "### Uncommitted: ${uc:-?} dosya"
  git status --porcelain 2>/dev/null | head -15 | sed 's/^/- /'
  echo ""
  echo "> Sıradaki görevler: memory/project_status.md · SON DURUM: .claude/CLAUDE.md"
  echo ""
} >> "$target" 2>/dev/null

exit 0
