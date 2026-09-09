#!/usr/bin/env bash
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
PLUGIN_SCRIPTS="$(cd "$SCRIPT_DIR/../../hooks/scripts" && pwd)"
INPUT="$(cat 2>/dev/null || true)"
ROOT="$(printf '%s' "$INPUT" | bash "$SCRIPT_DIR/project-dir.sh")"
export CLAUDE_PROJECT_DIR="$ROOT"
EXCERPT="$(printf '%s' '{"source":"startup"}' | bash "$PLUGIN_SCRIPTS/session-start-devlog.sh" 2>/dev/null || true)"
if command -v jq >/dev/null 2>&1; then
  jq -n --arg c "$EXCERPT" '{additional_context:$c}'
else
  esc="$(printf '%s' "$EXCERPT" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | awk '{printf "%s\\n", $0}' | sed '$ s/\\n$//')"
  printf '{"additional_context":"%s"}\n' "$esc"
fi
