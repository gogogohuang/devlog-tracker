#!/usr/bin/env bash
# Codex Stop wrapper. Same exit-code contract as PreToolUse; enforce-devlog.sh
# reads "stop_hook_active", which is Claude Code's own standard field name
# and not one of the documented Codex naming gaps, so it is forwarded as-is.
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
PLUGIN_SCRIPTS="$(cd "$SCRIPT_DIR/../../hooks/scripts" && pwd)"
INPUT="$(cat 2>/dev/null || true)"
ROOT="$(printf '%s' "$INPUT" | bash "$SCRIPT_DIR/project-dir.sh")"
export CLAUDE_PROJECT_DIR="$ROOT"
printf '%s' "$INPUT" | bash "$PLUGIN_SCRIPTS/enforce-devlog.sh"
exit $?
