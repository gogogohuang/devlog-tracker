#!/usr/bin/env bash
# PostToolUseFailure: remember user Esc so Stop can stamp without blocking.
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"

PROJECT_DIR="${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
ENABLED_FLAG="$DEVLOG_DIR/.enabled"
[ -f "$ENABLED_FLAG" ] || exit 0
# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"
devlog_resolve_paths "$PROJECT_DIR"

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
  : > "$INTERRUPTED_FLAG" 2>/dev/null || true
fi
exit 0
