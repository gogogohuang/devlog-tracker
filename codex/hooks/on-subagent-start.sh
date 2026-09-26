#!/usr/bin/env bash
# Codex SubagentStart: give the child the shared Lessons Mode guidance.
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
PLUGIN_SCRIPTS="$(cd "$SCRIPT_DIR/../../core/scripts" 2>/dev/null && pwd)"
[ -d "$PLUGIN_SCRIPTS" ] || exit 0
INPUT="$(cat 2>/dev/null || true)"
ROOT="$(printf '%s' "$INPUT" | bash "$SCRIPT_DIR/project-dir.sh")"
# A subagent may run in a separate worktree. Installed hook scripts live under
# <project>/.devlog-tracker/codex/hooks, so their path identifies the parent.
case "$SCRIPT_DIR" in
  */.devlog-tracker/codex/hooks)
    ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
    ;;
esac
export DEVLOG_PROJECT_DIR="$ROOT"
printf '%s' "$INPUT" | bash "$PLUGIN_SCRIPTS/lessons-subagent-start.sh" || true
exit 0
