#!/usr/bin/env bash
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
PLUGIN_SCRIPTS="$(cd "$SCRIPT_DIR/../../hooks/scripts" && pwd)"
INPUT="$(cat 2>/dev/null || true)"
ROOT="$(printf '%s' "$INPUT" | bash "$SCRIPT_DIR/project-dir.sh")"
export CLAUDE_PROJECT_DIR="$ROOT"
if command -v jq >/dev/null 2>&1; then
  IS_INTERRUPT="$(printf '%s' "$INPUT" | jq -r '.is_interrupt // .tool_result.is_interrupt // false' 2>/dev/null || echo false)"
else
  case "$INPUT" in *'"is_interrupt":true'*|*'"is_interrupt": true'*) IS_INTERRUPT=true ;; *) IS_INTERRUPT=false ;; esac
fi
printf '{"is_interrupt":%s}' "$IS_INTERRUPT" | bash "$PLUGIN_SCRIPTS/on-tool-failure.sh" >/dev/null 2>&1 || true
printf '{}\n'
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
