#!/usr/bin/env bash
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"
# shellcheck source=devlog-md.sh
. "$SCRIPT_DIR/devlog-md.sh"
# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"

devlog_resolve_paths "${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
[ -f "$DEVLOG_DIR/.enabled" ] || { echo "NOT_ENABLED"; exit 1; }
[ ! -e "$AWAITING_FILE" ] || { echo "ALREADY_OPEN"; exit 1; }
ROUND=""
[ ! -f "$ROUND_OPEN" ] || ROUND="$(json_int_get "$ROUND_OPEN" round)"
if [ -z "$ROUND" ] && [ -f "$DEVLOG_FILE" ]; then
  ROUND="$(devlog_list_round_starts_of "$DEVLOG_FILE" "$DEVLOG_PLATFORM" | awk 'END { print $2 }')"
fi
[ -n "$ROUND" ] || { echo "NO_ROUND"; exit 1; }
OPENED_AT="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"
printf '{"round": %s, "opened_at": "%s"}\n' "$ROUND" "$OPENED_AT" > "$AWAITING_FILE" || exit 1
printf 'OPENED=%s\n' "$ROUND"
