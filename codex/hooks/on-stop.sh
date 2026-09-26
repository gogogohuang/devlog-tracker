#!/usr/bin/env bash
# Codex Stop wrapper. Same exit-code contract as PreToolUse; enforce-devlog.sh
# reads "stop_hook_active", which is Claude Code's own standard field name
# and not one of the documented Codex naming gaps, so it is forwarded as-is.
# Fail-open like the Cursor adapter: only an exit code of exactly 2 blocks;
# anything else (including a missing core/scripts dir or a crash) allows.
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
PLUGIN_SCRIPTS="$(cd "$SCRIPT_DIR/../../core/scripts" 2>/dev/null && pwd)"
[ -d "$PLUGIN_SCRIPTS" ] || { printf '{}\n'; exit 0; }
INPUT="$(cat 2>/dev/null || true)"
ROOT="$(printf '%s' "$INPUT" | bash "$SCRIPT_DIR/project-dir.sh")"
export DEVLOG_PROJECT_DIR="$ROOT"
printf '%s' "$INPUT" | bash "$PLUGIN_SCRIPTS/enforce-devlog.sh" >/dev/null
RC=$?
[ "$RC" -eq 2 ] && exit 2
printf '{}\n'
exit 0
