#!/usr/bin/env bash
# User-invoked: /devlog-tracker:lessons-drift filesystem side.
# Sets the workspace-drift nudge's threshold (docs/design/lessons-mode.md
# 「機制性訊號：工作區漂移重複發生」): how many cumulative 工作區-mismatch
# occurrences (round-start.sh) before printing one advisory suggestion to
# write a Lessons Mode entry. Nested under Lessons Mode, which is itself
# nested under the main switch. $1 is required: a positive integer.
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

if [ -f "$DEVLOG_DIR/.lessons-drift-state" ]; then
  json_int_set "$DEVLOG_DIR/.lessons-drift-state" threshold "$COUNT_ARG"
else
  printf '%s\n' "{\"mismatch_count\": 0, \"threshold\": ${COUNT_ARG}}" \
    > "$DEVLOG_DIR/.lessons-drift-state" || exit 1
fi

echo "LESSONS_DRIFT_THRESHOLD=$(json_int_get "$DEVLOG_DIR/.lessons-drift-state" threshold)"
exit 0
