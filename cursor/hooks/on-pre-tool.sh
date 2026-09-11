#!/usr/bin/env bash
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
PLUGIN_SCRIPTS="$(cd "$SCRIPT_DIR/../../hooks/scripts" && pwd)"
INPUT="$(cat 2>/dev/null || true)"
ROOT="$(printf '%s' "$INPUT" | bash "$SCRIPT_DIR/project-dir.sh")"
export CLAUDE_PROJECT_DIR="$ROOT"
ERR_FILE="$(mktemp "${TMPDIR:-/tmp}/cursor-pre-tool.XXXXXX")" || { echo '{}'; exit 0; }
printf '%s' "$INPUT" | bash "$PLUGIN_SCRIPTS/segment-watch.sh" >/dev/null 2>"$ERR_FILE"
RESULT=$?
MESSAGE="$(cat "$ERR_FILE" 2>/dev/null || true)"
rm -f "$ERR_FILE"
if [ "$RESULT" -eq 2 ]; then
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg m "$MESSAGE" '{permission:"deny",user_message:$m}'
  else
    esc="$(printf '%s' "$MESSAGE" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | awk '{printf "%s\\n", $0}' | sed '$ s/\\n$//')"
    printf '{"permission":"deny","user_message":"%s"}\n' "$esc"
  fi
else
  echo '{}'
fi
exit 0
