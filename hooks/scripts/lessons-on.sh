#!/usr/bin/env bash
# User-invoked: /devlog-tracker:lessons-on filesystem side.
# Nested under the main switch (docs/design/lessons-mode.md「Enable /
# disable」): refuses if .enabled is absent, since there is no Round/Status
# history to detect a BLOCKED->resolved transition against.
set -uo pipefail
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
if [ ! -f "$DEVLOG_DIR/.enabled" ]; then
  echo "NOT_ENABLED"
  exit 0
fi
if [ ! -f "$DEVLOG_DIR/.lessons-enabled" ]; then
  date -Iseconds > "$DEVLOG_DIR/.lessons-enabled" 2>/dev/null || echo enabled > "$DEVLOG_DIR/.lessons-enabled"
fi
echo "LESSONS_ENABLED=$DEVLOG_DIR/.lessons-enabled"
exit 0
