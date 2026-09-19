#!/usr/bin/env bash
# Codex UserPromptSubmit wrapper. round-start.sh is fail-open and side-effect
# only (writes .devlog files); the one case where it prints anything to
# stdout (workspace-mismatch notice) relies on the same plain-stdout-as-
# context contract as SessionStart, so this is a straight pass-through of
# the original payload after the cwd->CLAUDE_PROJECT_DIR translation.
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
PLUGIN_SCRIPTS="$(cd "$SCRIPT_DIR/../../core/scripts" && pwd)"
INPUT="$(cat 2>/dev/null || true)"
ROOT="$(printf '%s' "$INPUT" | bash "$SCRIPT_DIR/project-dir.sh")"
export DEVLOG_PROJECT_DIR="$ROOT"
printf '%s' "$INPUT" | bash "$PLUGIN_SCRIPTS/round-start.sh"
exit 0
