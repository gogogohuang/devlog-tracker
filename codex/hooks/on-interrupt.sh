#!/usr/bin/env bash
# Codex Interrupt: close the active round as interrupted. The event is
# advisory and has a short timeout, so failures must not affect Codex.
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
PLUGIN_SCRIPTS="$(cd "$SCRIPT_DIR/../../core/scripts" 2>/dev/null && pwd)"
[ -d "$PLUGIN_SCRIPTS" ] || exit 0
INPUT="$(cat 2>/dev/null || true)"
ROOT="$(printf '%s' "$INPUT" | bash "$SCRIPT_DIR/project-dir.sh")"
export DEVLOG_PROJECT_DIR="$ROOT"
bash "$PLUGIN_SCRIPTS/close-open-round.sh" "Interrupt:cancelled" >/dev/null 2>&1 || true
exit 0
