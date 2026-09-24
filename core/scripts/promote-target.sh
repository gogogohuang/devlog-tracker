#!/usr/bin/env bash
# Picks the file /devlog-tracker:promote writes rules into
# (docs/design/read-side-and-promote.md D). Plain read only.
#   1. Codex-only project (no CLAUDE.md, Codex hooks or devlog skills present) -> AGENTS.md
#   2. CLAUDE.md that is nothing but "@AGENTS.md"                              -> AGENTS.md
#   3. otherwise                                                               -> CLAUDE.md
set -uo pipefail

PROJECT_DIR="$(cd "${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}" 2>/dev/null && pwd)" || exit 1
CLAUDE_MD="$PROJECT_DIR/CLAUDE.md"
AGENTS_MD="$PROJECT_DIR/AGENTS.md"
BEGIN_MARK='<!-- devlog-tracker:rules:begin -->'
END_MARK='<!-- devlog-tracker:rules:end -->'

HAS_CODEX=0
[ -f "$PROJECT_DIR/.codex/hooks.json" ] && HAS_CODEX=1
for d in "$PROJECT_DIR"/.agents/skills/devlog-*; do
  [ -d "$d" ] && HAS_CODEX=1
done

TARGET="$CLAUDE_MD"
if [ ! -f "$CLAUDE_MD" ] && [ "$HAS_CODEX" -eq 1 ]; then
  TARGET="$AGENTS_MD"
elif [ -f "$CLAUDE_MD" ] && [ "$(tr -d '[:space:]' < "$CLAUDE_MD")" = "@AGENTS.md" ]; then
  TARGET="$AGENTS_MD"
fi
echo "TARGET=$TARGET"

if [ -f "$TARGET" ] && grep -qxF "$BEGIN_MARK" "$TARGET"; then
  n="$(awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    $0 == b { g = 1; next }
    $0 == e { g = 0 }
    g && /^- / { c++ }
    END { print c + 0 }
  ' "$TARGET")"
  echo "EXISTING=$n"
fi
