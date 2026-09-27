#!/usr/bin/env bash
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
. "$SCRIPT_DIR/json-field.sh"
. "$SCRIPT_DIR/devlog-md.sh"
. "$SCRIPT_DIR/devlog-path.sh"

devlog_resolve_paths "${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
[ -f "$DEVLOG_DIR/.enabled" ] || { echo "NOT_ENABLED" >&2; exit 1; }
[ ! -e "$SPAN_FILE" ] || { echo "ALREADY_OPEN" >&2; exit 1; }
ROUND=""
[ ! -f "$ROUND_OPEN" ] || ROUND="$(json_int_get "$ROUND_OPEN" round)"
if [ -z "$ROUND" ] && [ -f "$DEVLOG_FILE" ]; then
  ROUND="$(devlog_list_round_starts "$DEVLOG_FILE" | awk 'END { print $2 }')"
fi
[ -n "$ROUND" ] || { echo "NO_ROUND" >&2; exit 1; }
OPENED_AT="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"
printf '{"round": %s, "opened_at": "%s", "ticks_since_checkin": 0, "max_silent_ticks": 5}\n' \
  "$ROUND" "$OPENED_AT" > "$SPAN_FILE" || exit 1
printf 'OPENED=%s\n' "$ROUND"
