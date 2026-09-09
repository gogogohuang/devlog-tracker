#!/usr/bin/env bash
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
PLUGIN_SCRIPTS="$(cd "$SCRIPT_DIR/../../hooks/scripts" && pwd)"
INPUT="$(cat 2>/dev/null || true)"
ROOT="$(printf '%s' "$INPUT" | bash "$SCRIPT_DIR/project-dir.sh")"
export CLAUDE_PROJECT_DIR="$ROOT"
printf '%s' "$INPUT" | bash "$PLUGIN_SCRIPTS/on-tool-failure.sh" >/dev/null 2>&1 || true
echo '{}'
