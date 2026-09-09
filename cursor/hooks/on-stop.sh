#!/usr/bin/env bash
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
PLUGIN_SCRIPTS="$(cd "$SCRIPT_DIR/../../hooks/scripts" && pwd)"
INPUT="$(cat 2>/dev/null || true)"
ROOT="$(printf '%s' "$INPUT" | bash "$SCRIPT_DIR/project-dir.sh")"
export CLAUDE_PROJECT_DIR="$ROOT"
STATUS=""
LOOP_COUNT=0
if command -v jq >/dev/null 2>&1; then
  STATUS="$(printf '%s' "$INPUT" | jq -r '.status // empty' 2>/dev/null || true)"
  LOOP_COUNT="$(printf '%s' "$INPUT" | jq -r '.loop_count // 0' 2>/dev/null || echo 0)"
else
  STATUS="$(printf '%s' "$INPUT" | grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
  LOOP_COUNT="$(printf '%s' "$INPUT" | grep -o '"loop_count"[[:space:]]*:[[:space:]]*[0-9]\+' 2>/dev/null | grep -o '[0-9]\+$' || echo 0)"
fi
case "$STATUS" in
  aborted|error)
    bash "$PLUGIN_SCRIPTS/close-open-round.sh" "$STATUS" >/dev/null 2>&1 || true
    printf '{}\n'
    exit 0
    ;;
esac
case "$LOOP_COUNT" in ''|*[!0-9]*) LOOP_COUNT=0 ;; esac
if [ "$LOOP_COUNT" -ge 1 ]; then
  ENFORCE_INPUT='{"stop_hook_active":true}'
else
  ENFORCE_INPUT='{}'
fi
ERR="$(printf '%s' "$ENFORCE_INPUT" | bash "$PLUGIN_SCRIPTS/enforce-devlog.sh" 2>&1 >/dev/null)"
RESULT=$?
if [ "$RESULT" -eq 2 ]; then
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg m "$ERR" '{followup_message:$m}'
  else
    esc="$(printf '%s' "$ERR" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    printf '{"followup_message":"%s"}\n' "$esc"
  fi
else
  printf '{}\n'
fi
exit 0
#!/usr/bin/env bash
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
PLUGIN_SCRIPTS="$(cd "$SCRIPT_DIR/../../hooks/scripts" && pwd)"
INPUT="$(cat 2>/dev/null || true)"
ROOT="$(printf '%s' "$INPUT" | bash "$SCRIPT_DIR/project-dir.sh")"
export CLAUDE_PROJECT_DIR="$ROOT"
STATUS=""
LOOP_COUNT=0
if command -v jq >/dev/null 2>&1; then
  STATUS="$(printf '%s' "$INPUT" | jq -r '.status // empty' 2>/dev/null || true)"
  LOOP_COUNT="$(printf '%s' "$INPUT" | jq -r '.loop_count // 0' 2>/dev/null || echo 0)"
else
  STATUS="$(printf '%s' "$INPUT" | grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
  LOOP_COUNT="$(printf '%s' "$INPUT" | grep -o '"loop_count"[[:space:]]*:[[:space:]]*[0-9]\+' 2>/dev/null | grep -o '[0-9]\+$' || echo 0)"
fi
case "$STATUS" in
  aborted|error)
    bash "$PLUGIN_SCRIPTS/close-open-round.sh" "$STATUS" >/dev/null 2>&1 || true
    echo '{}'
    exit 0
    ;;
  completed) ;;
  *) echo '{}'; exit 0 ;;
esac
case "$LOOP_COUNT" in ''|*[!0-9]*) LOOP_COUNT=0 ;; esac
[ "$LOOP_COUNT" -ge 1 ] && ENFORCE_INPUT='{"stop_hook_active":true}' || ENFORCE_INPUT='{}'
ERR_FILE="$(mktemp "${TMPDIR:-/tmp}/cursor-stop.XXXXXX")" || { echo '{}'; exit 0; }
printf '%s' "$ENFORCE_INPUT" | bash "$PLUGIN_SCRIPTS/enforce-devlog.sh" >/dev/null 2>"$ERR_FILE"
RESULT=$?
MESSAGE="$(cat "$ERR_FILE" 2>/dev/null || true)"
rm -f "$ERR_FILE"
if [ "$RESULT" -eq 2 ]; then
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg m "$MESSAGE" '{followup_message:$m}'
  else
    esc="$(printf '%s' "$MESSAGE" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    printf '{"followup_message":"%s"}\n' "$esc"
  fi
else
  echo '{}'
fi
