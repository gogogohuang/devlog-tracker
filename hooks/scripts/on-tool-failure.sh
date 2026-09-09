#!/usr/bin/env bash
# PostToolUseFailure: remember user Esc so Stop can stamp without blocking.
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
ENABLED_FLAG="$DEVLOG_DIR/.enabled"
[ -f "$ENABLED_FLAG" ] || exit 0

INPUT="$(cat 2>/dev/null || true)"
IS_INT="false"
if command -v jq >/dev/null 2>&1; then
  IS_INT="$(printf '%s' "$INPUT" | jq -r '.is_interrupt // false' 2>/dev/null || echo false)"
else
  case "$INPUT" in
    *'"is_interrupt":true'*|*'"is_interrupt": true'*) IS_INT=true ;;
    *) IS_INT=false ;;
  esac
fi

if [ "$IS_INT" = "true" ]; then
  mkdir -p "$DEVLOG_DIR" 2>/dev/null || true
  : > "$DEVLOG_DIR/.interrupted" 2>/dev/null || true
fi
exit 0
