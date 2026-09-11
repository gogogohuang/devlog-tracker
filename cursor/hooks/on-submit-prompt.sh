#!/usr/bin/env bash
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
PLUGIN_SCRIPTS="$(cd "$SCRIPT_DIR/../../hooks/scripts" && pwd)"
INPUT="$(cat 2>/dev/null || true)"
ROOT="$(printf '%s' "$INPUT" | bash "$SCRIPT_DIR/project-dir.sh")"
export CLAUDE_PROJECT_DIR="$ROOT"
PROMPT=""
SESSION_ID=""
if command -v jq >/dev/null 2>&1; then
  PROMPT="$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)"
  SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
  PAYLOAD="$(jq -n --arg prompt "$PROMPT" --arg session_id "$SESSION_ID" '{prompt:$prompt,session_id:$session_id}')"
else
  PROMPT="$(printf '%s' "$INPUT" | grep -o '"prompt"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
  SESSION_ID="$(printf '%s' "$INPUT" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
  # Escape only what we embed; prompts with quotes remain a known no-jq limitation.
  PAYLOAD="$(printf '{"prompt":"%s","session_id":"%s"}' "$PROMPT" "$SESSION_ID")"
fi
NOTE="$(printf '%s' "$PAYLOAD" | bash "$PLUGIN_SCRIPTS/round-start.sh" 2>/dev/null || true)"
if command -v jq >/dev/null 2>&1; then
  jq -cn --arg n "$NOTE" '{continue:true, additional_context:$n}'
else
  esc="$(printf '%s' "$NOTE" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | awk '{printf "%s\\n", $0}' | sed '$ s/\\n$//')"
  printf '{"continue":true,"additional_context":"%s"}\n' "$esc"
fi
exit 0
