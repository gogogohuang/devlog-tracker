#!/usr/bin/env bash
# User-invoked: /devlog-tracker:start filesystem side.
set -uo pipefail
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
mkdir -p "$DEVLOG_DIR" || exit 1
if [ ! -f "$DEVLOG_DIR/.enabled" ]; then
  date -Iseconds > "$DEVLOG_DIR/.enabled" 2>/dev/null || echo enabled > "$DEVLOG_DIR/.enabled"
fi
if [ ! -f "$DEVLOG_DIR/.checkpoint-state" ]; then
  printf '%s\n' '{"rounds_since_checkpoint": 0, "max_silent_rounds": 20, "checkpoint_marker_count": 0}' \
    > "$DEVLOG_DIR/.checkpoint-state" || exit 1
fi
if [ ! -f "$DEVLOG_DIR/.segment-state" ]; then
  printf '%s\n' '{"last_change_epoch": 0, "last_seen_cksum": "", "max_silent_seconds": 900}' \
    > "$DEVLOG_DIR/.segment-state" || exit 1
fi
GITIGNORE_DEVLOG=no
if [ -f "$PROJECT_DIR/.gitignore" ] && grep -E -q '(^|/)\.devlog(/|$)' "$PROJECT_DIR/.gitignore"; then
  GITIGNORE_DEVLOG=yes
fi
echo "ENABLED=$DEVLOG_DIR/.enabled"
echo "GITIGNORE_DEVLOG=$GITIGNORE_DEVLOG"
exit 0
