#!/usr/bin/env bash
# Codex SessionStart wrapper. Claude Code's own hooks.json calls
# session-start-devlog.sh directly and its plain stdout becomes the injected
# context — no JSON envelope. Codex hooks are documented to share the same
# JSON-in shape as Claude Code, so we assume the same is true for stdout-out
# here and skip any envelope too.
#
# Codex's documented SessionStart field is `source`. Accept older `how`
# payloads too, and default to "startup" on purpose: session-start-devlog.sh
# SKIPS the dangling-round heal when source is missing/unrecognized (same as
# `compact`); the wrapper forces SRC="startup" so healing runs.
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
PLUGIN_SCRIPTS="$(cd "$SCRIPT_DIR/../../core/scripts" && pwd)"
INPUT="$(cat 2>/dev/null || true)"
ROOT="$(printf '%s' "$INPUT" | bash "$SCRIPT_DIR/project-dir.sh")"
export DEVLOG_PROJECT_DIR="$ROOT"

SRC=""
if command -v jq >/dev/null 2>&1; then
  SRC="$(printf '%s' "$INPUT" | jq -r '.source // .how // empty' 2>/dev/null || true)"
else
  SRC="$(printf '%s' "$INPUT" | grep -o '"source"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
  [ -n "$SRC" ] || SRC="$(printf '%s' "$INPUT" | grep -o '"how"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"how"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
fi
[ -n "$SRC" ] || SRC="startup"

if command -v jq >/dev/null 2>&1; then
  PAYLOAD="$(jq -n --arg s "$SRC" '{source:$s}')"
else
  esc="$(printf '%s' "$SRC" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  PAYLOAD="$(printf '{"source":"%s"}' "$esc")"
fi
printf '%s' "$PAYLOAD" | bash "$PLUGIN_SCRIPTS/session-start-devlog.sh"
exit 0
