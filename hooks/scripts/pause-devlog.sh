#!/usr/bin/env bash
set -uo pipefail
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
if [ ! -f "$DEVLOG_DIR/.enabled" ]; then
  echo "NOT_ENABLED"
  exit 0
fi
rm -f "$DEVLOG_DIR/.enabled" "$DEVLOG_DIR/.span-open" \
  "$DEVLOG_DIR/.round-open" "$DEVLOG_DIR/.interrupted"
echo "PAUSED"
exit 0
