#!/usr/bin/env bash
# User-invoked: /devlog-tracker:segment-watch filesystem side.
# Sets Segment Watch's max_silent_seconds threshold. $1 is required: a
# positive integer number of seconds.
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"

if [ ! -f "$DEVLOG_DIR/.enabled" ]; then
  echo "NOT_STARTED"
  exit 0
fi

SECONDS_ARG="${1:-}"
case "$SECONDS_ARG" in
  ''|*[!0-9]*|0)
    echo "max_silent_seconds must be a positive integer number of seconds, got: $SECONDS_ARG" >&2
    exit 1
    ;;
esac

if [ -f "$DEVLOG_DIR/.segment-state" ]; then
  json_int_set "$DEVLOG_DIR/.segment-state" max_silent_seconds "$SECONDS_ARG"
  APPLIED="$(json_int_get "$DEVLOG_DIR/.segment-state" max_silent_seconds)"
  if [ "$APPLIED" != "$SECONDS_ARG" ]; then
    # Existing file didn't have a matching max_silent_seconds key to patch
    # (malformed / hand-edited) -- rebuild it fresh rather than leave the
    # requested value silently unapplied.
    LAST_EPOCH="$(json_int_get "$DEVLOG_DIR/.segment-state" last_change_epoch)"
    LAST_SUM="$(json_str_get "$DEVLOG_DIR/.segment-state" last_seen_cksum)"
    SESSION="$(json_str_get "$DEVLOG_DIR/.segment-state" session_id)"
    case "$LAST_EPOCH" in ''|*[!0-9]*) LAST_EPOCH=0 ;; esac
    printf '%s\n' "{\"last_change_epoch\": ${LAST_EPOCH}, \"last_seen_cksum\": \"${LAST_SUM}\", \"max_silent_seconds\": ${SECONDS_ARG}, \"session_id\": \"${SESSION}\"}" \
      > "$DEVLOG_DIR/.segment-state" || exit 1
  fi
else
  printf '%s\n' "{\"last_change_epoch\": 0, \"last_seen_cksum\": \"\", \"max_silent_seconds\": ${SECONDS_ARG}, \"session_id\": \"\"}" \
    > "$DEVLOG_DIR/.segment-state" || exit 1
fi

echo "SEGMENT_MAX_SILENT_SECONDS=$(json_int_get "$DEVLOG_DIR/.segment-state" max_silent_seconds)"
exit 0
