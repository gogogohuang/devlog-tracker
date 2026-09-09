#!/usr/bin/env bash
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"
# shellcheck source=devlog-md.sh
. "$SCRIPT_DIR/devlog-md.sh"

DEVLOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.devlog"
[ -f "$DEVLOG_DIR/.enabled" ] || { echo "NOT_ENABLED"; exit 1; }
[ ! -e "$DEVLOG_DIR/.awaiting-reply" ] || { echo "ALREADY_OPEN"; exit 1; }
ROUND=""
[ ! -f "$DEVLOG_DIR/.round-open" ] || ROUND="$(json_int_get "$DEVLOG_DIR/.round-open" round)"
if [ -z "$ROUND" ] && [ -f "$DEVLOG_DIR/devlog.md" ]; then
  ROUND="$(devlog_list_round_starts "$DEVLOG_DIR/devlog.md" | awk 'END { print $2 }')"
fi
[ -n "$ROUND" ] || { echo "NO_ROUND"; exit 1; }
OPENED_AT="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"
printf '{"round": %s, "opened_at": "%s"}\n' "$ROUND" "$OPENED_AT" > "$DEVLOG_DIR/.awaiting-reply" || exit 1
printf 'OPENED=%s\n' "$ROUND"
