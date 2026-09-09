#!/usr/bin/env bash
set -uo pipefail
DEVLOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.devlog"
if [ ! -e "$DEVLOG_DIR/.span-open" ]; then
  echo "NOT_OPEN"
  exit 0
fi
rm -f "$DEVLOG_DIR/.span-open" || exit 1
echo "CLOSED"
