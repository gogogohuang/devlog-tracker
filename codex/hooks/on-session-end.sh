#!/usr/bin/env bash
# Codex SessionEnd wrapper. on-session-end.sh (shared) reads a "reason"
# field. Codex's own field for "why the session ended" is documented
# inconsistently as either "why" or "reason" - try both, default to
# "unknown" rather than guessing further, and rebuild a synthetic payload
# so the shared script's json_str_field lookup always finds "reason".
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
PLUGIN_SCRIPTS="$(cd "$SCRIPT_DIR/../../core/scripts" && pwd)"
INPUT="$(cat 2>/dev/null || true)"
ROOT="$(printf '%s' "$INPUT" | bash "$SCRIPT_DIR/project-dir.sh")"
export DEVLOG_PROJECT_DIR="$ROOT"

REASON=""
if command -v jq >/dev/null 2>&1; then
  REASON="$(printf '%s' "$INPUT" | jq -r '.why // .reason // empty' 2>/dev/null || true)"
else
  REASON="$(printf '%s' "$INPUT" | grep -o '"why"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"why"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
  [ -n "$REASON" ] || REASON="$(printf '%s' "$INPUT" | grep -o '"reason"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"reason"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
fi
[ -n "$REASON" ] || REASON="unknown"

if command -v jq >/dev/null 2>&1; then
  PAYLOAD="$(jq -n --arg r "$REASON" '{reason:$r}')"
else
  esc="$(printf '%s' "$REASON" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  PAYLOAD="$(printf '{"reason":"%s"}' "$esc")"
fi
printf '%s' "$PAYLOAD" | bash "$PLUGIN_SCRIPTS/on-session-end.sh"
exit 0
