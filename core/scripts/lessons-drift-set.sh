#!/usr/bin/env bash
# User-invoked: /devlog-tracker:lessons-drift filesystem side.
# Sets the shared advisory-signal threshold (docs/design/lessons-mode.md
# 「機制性訊號：共用計數器」): how many cumulative occurrences — workspace-
# drift mismatches or accumulated BLOCKED rounds (both round-start.sh) —
# before printing one advisory suggestion to write a Lessons Mode entry.
# Nested under Lessons Mode, which is itself nested under the main switch.
# $1 is required: a positive integer.
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"
# shellcheck source=lessons-advisory-state.sh
. "$SCRIPT_DIR/lessons-advisory-state.sh"

PROJECT_DIR="${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"

if [ ! -f "$DEVLOG_DIR/.enabled" ]; then
  echo "NOT_STARTED"
  exit 0
fi
if [ ! -f "$DEVLOG_DIR/.lessons-enabled" ]; then
  echo "LESSONS_NOT_ENABLED"
  exit 0
fi

COUNT_ARG="${1:-}"
case "$COUNT_ARG" in
  ''|*[!0-9]*|0)
    echo "threshold must be a positive integer number of occurrences, got: $COUNT_ARG" >&2
    exit 1
    ;;
esac

lessons_advisory_migrate "$DEVLOG_DIR"
if [ -f "$DEVLOG_DIR/.lessons-advisory-state" ]; then
  json_int_set "$DEVLOG_DIR/.lessons-advisory-state" threshold "$COUNT_ARG"
else
  printf '%s\n' "{\"count\": 0, \"threshold\": ${COUNT_ARG}}" \
    > "$DEVLOG_DIR/.lessons-advisory-state" || exit 1
fi

echo "LESSONS_DRIFT_THRESHOLD=$(json_int_get "$DEVLOG_DIR/.lessons-advisory-state" threshold)"
exit 0
