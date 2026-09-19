#!/usr/bin/env bash
# User-invoked: /devlog-tracker:checkpoint filesystem side.
# Sets Checkpoint Mode's max_silent_rounds threshold. $1 is required: a
# positive integer number of rounds.
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

ROUNDS_ARG="${1:-}"
case "$ROUNDS_ARG" in
  ''|*[!0-9]*|0)
    echo "max_silent_rounds must be a positive integer number of rounds, got: $ROUNDS_ARG" >&2
    exit 1
    ;;
esac

if [ -f "$DEVLOG_DIR/.checkpoint-state" ]; then
  json_int_set "$DEVLOG_DIR/.checkpoint-state" max_silent_rounds "$ROUNDS_ARG"
  APPLIED="$(json_int_get "$DEVLOG_DIR/.checkpoint-state" max_silent_rounds)"
  if [ "$APPLIED" != "$ROUNDS_ARG" ]; then
    ROUNDS="$(json_int_get "$DEVLOG_DIR/.checkpoint-state" rounds_since_checkpoint)"
    MARKERS="$(json_int_get "$DEVLOG_DIR/.checkpoint-state" checkpoint_marker_count)"
    case "$ROUNDS" in ''|*[!0-9]*) ROUNDS=0 ;; esac
    case "$MARKERS" in ''|*[!0-9]*) MARKERS=0 ;; esac
    printf '%s\n' "{\"rounds_since_checkpoint\": ${ROUNDS}, \"max_silent_rounds\": ${ROUNDS_ARG}, \"checkpoint_marker_count\": ${MARKERS}}" \
      > "$DEVLOG_DIR/.checkpoint-state" || exit 1
  fi
else
  printf '%s\n' "{\"rounds_since_checkpoint\": 0, \"max_silent_rounds\": ${ROUNDS_ARG}, \"checkpoint_marker_count\": 0}" \
    > "$DEVLOG_DIR/.checkpoint-state" || exit 1
fi

echo "CHECKPOINT_MAX_SILENT_ROUNDS=$(json_int_get "$DEVLOG_DIR/.checkpoint-state" max_silent_rounds)"
exit 0
