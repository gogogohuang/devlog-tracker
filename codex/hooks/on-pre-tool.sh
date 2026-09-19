#!/usr/bin/env bash
# Codex PreToolUse wrapper. Codex's "command" hooks use the same exit-code
# contract as Claude Code (0 = allow, 2 = block), so this only needs the
# cwd->CLAUDE_PROJECT_DIR translation; segment-watch.sh's stderr message
# propagates unchanged. Fail-open like the Cursor adapter: only an exit code of
# exactly 2 blocks; anything else (including a missing hooks/scripts dir or a
# crash) allows.
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
PLUGIN_SCRIPTS="$(cd "$SCRIPT_DIR/../../core/scripts" 2>/dev/null && pwd)"
[ -d "$PLUGIN_SCRIPTS" ] || exit 0
INPUT="$(cat 2>/dev/null || true)"
ROOT="$(printf '%s' "$INPUT" | bash "$SCRIPT_DIR/project-dir.sh")"
export CLAUDE_PROJECT_DIR="$ROOT"
printf '%s' "$INPUT" | bash "$PLUGIN_SCRIPTS/segment-watch.sh"
RC=$?
[ "$RC" -eq 2 ] && exit 2
exit 0
