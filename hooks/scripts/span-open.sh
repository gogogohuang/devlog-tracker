#!/usr/bin/env bash
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
. "$SCRIPT_DIR/json-field.sh"
. "$SCRIPT_DIR/devlog-md.sh"

DEVLOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.devlog"
[ -f "$DEVLOG_DIR/.enabled" ] || { echo "NOT_ENABLED" >&2; exit 1; }
[ ! -e "$DEVLOG_DIR/.span-open" ] || { echo "ALREADY_OPEN" >&2; exit 1; }
ROUND=""
[ ! -f "$DEVLOG_DIR/.round-open" ] || ROUND="$(json_int_get "$DEVLOG_DIR/.round-open" round)"
if [ -z "$ROUND" ] && [ -f "$DEVLOG_DIR/devlog.md" ]; then
  ROUND="$(devlog_list_round_starts "$DEVLOG_DIR/devlog.md" | awk 'END { print $2 }')"
fi
[ -n "$ROUND" ] || { echo "NO_ROUND" >&2; exit 1; }
OPENED_AT="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"
printf '{"round": %s, "opened_at": "%s", "ticks_since_checkin": 0, "max_silent_ticks": 5}\n' \
  "$ROUND" "$OPENED_AT" > "$DEVLOG_DIR/.span-open" || exit 1
printf 'OPENED=%s\n' "$ROUND"
