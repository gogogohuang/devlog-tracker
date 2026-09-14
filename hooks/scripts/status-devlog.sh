#!/usr/bin/env bash
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
. "$SCRIPT_DIR/json-field.sh"
. "$SCRIPT_DIR/devlog-md.sh"
. "$SCRIPT_DIR/devlog-path.sh"

devlog_resolve_paths "${CLAUDE_PROJECT_DIR:-.}"
[ -d "$DEVLOG_DIR" ] || { echo "NOT_STARTED"; exit 0; }

[ -f "$DEVLOG_DIR/.enabled" ] && echo "ENABLED=yes" || echo "ENABLED=no"
[ -f "$DEVLOG_DIR/.lessons-enabled" ] && echo "LESSONS=yes" || echo "LESSONS=no"
if [ -f "$DEVLOG_DIR/.span-open" ]; then
  r="$(json_int_get "$DEVLOG_DIR/.span-open" round)"
  opened="$(json_str_get "$DEVLOG_DIR/.span-open" opened_at)"
  ticks="$(json_int_get "$DEVLOG_DIR/.span-open" ticks_since_checkin)"
  max="$(json_int_get "$DEVLOG_DIR/.span-open" max_silent_ticks)"
  printf 'SPAN=%s,%s,%s,%s\n' "${r:-?}" "${opened:-?}" "${ticks:-?}" "${max:-5}"
else
  echo "SPAN=closed"
fi
rounds="$(json_int_get "$DEVLOG_DIR/.checkpoint-state" rounds_since_checkpoint)"
checkpoint_max="$(json_int_get "$DEVLOG_DIR/.checkpoint-state" max_silent_rounds)"
printf 'CHECKPOINT=%s/%s\n' "${rounds:-0}" "${checkpoint_max:-20}"
seconds="$(json_int_get "$DEVLOG_DIR/.segment-state" max_silent_seconds)"
printf 'SEGMENT=max_silent_seconds=%s\n' "${seconds:-600}"

status="none"
if [ -f "$DEVLOG_FILE" ]; then
  last="$(devlog_list_round_starts "$DEVLOG_FILE" | awk 'END { print $1 }')"
  if [ -n "$last" ]; then
    end="$(devlog_block_end "$DEVLOG_FILE" "$last")"
    found="$(devlog_round_status "$DEVLOG_FILE" "$last" "$end")"
    [ -z "$found" ] || status="$found"
  fi
fi
printf 'LAST_STATUS=%s\n' "$status"
