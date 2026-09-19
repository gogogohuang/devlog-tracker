#!/usr/bin/env bash
# User-invoked: /devlog-tracker:lessons-off filesystem side.
# Removes .lessons-enabled only -- never touches devlog.lessons.*.md files
# or the "## Lessons 索引" block (docs/design/lessons-mode.md), same
# non-destructive posture as pause-devlog.sh toward devlog.md.
set -uo pipefail
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
if [ ! -f "$DEVLOG_DIR/.lessons-enabled" ]; then
  echo "NOT_ENABLED"
  exit 0
fi
rm -f "$DEVLOG_DIR/.lessons-enabled"
echo "LESSONS_DISABLED"
exit 0
