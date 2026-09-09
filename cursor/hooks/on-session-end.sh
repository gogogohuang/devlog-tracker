#!/usr/bin/env bash
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
PLUGIN_SCRIPTS="$(cd "$SCRIPT_DIR/../../hooks/scripts" && pwd)"
INPUT="$(cat 2>/dev/null || true)"
ROOT="$(printf '%s' "$INPUT" | bash "$SCRIPT_DIR/project-dir.sh")"
export CLAUDE_PROJECT_DIR="$ROOT"
if command -v jq >/dev/null 2>&1; then
  REASON="$(printf '%s' "$INPUT" | jq -r '.reason // "other"' 2>/dev/null || echo other)"
  PAYLOAD="$(jq -n --arg r "$REASON" '{reason:$r}')"
else
  PAYLOAD='{"reason":"other"}'
fi
printf '%s' "$PAYLOAD" | bash "$PLUGIN_SCRIPTS/on-session-end.sh" >/dev/null 2>&1 || true
printf '{}\n'
#!/usr/bin/env bash
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
PLUGIN_SCRIPTS="$(cd "$SCRIPT_DIR/../../hooks/scripts" && pwd)"
INPUT="$(cat 2>/dev/null || true)"
ROOT="$(printf '%s' "$INPUT" | bash "$SCRIPT_DIR/project-dir.sh")"
export CLAUDE_PROJECT_DIR="$ROOT"
printf '%s' "$INPUT" | bash "$PLUGIN_SCRIPTS/on-session-end.sh" >/dev/null 2>&1 || true
echo '{}'
