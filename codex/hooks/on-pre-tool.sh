#!/usr/bin/env bash
# Codex PreToolUse wrapper. Codex's "command" hooks use the same exit-code
# contract as Claude Code (0 = allow, 2 = block), so this only needs the
# cwd->CLAUDE_PROJECT_DIR translation; segment-watch.sh's own exit code and
# stderr message propagate unchanged.
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
PLUGIN_SCRIPTS="$(cd "$SCRIPT_DIR/../../hooks/scripts" && pwd)"
INPUT="$(cat 2>/dev/null || true)"
ROOT="$(printf '%s' "$INPUT" | bash "$SCRIPT_DIR/project-dir.sh")"
export CLAUDE_PROJECT_DIR="$ROOT"
printf '%s' "$INPUT" | bash "$PLUGIN_SCRIPTS/segment-watch.sh"
exit $?
