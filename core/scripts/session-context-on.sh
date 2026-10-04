#!/usr/bin/env bash
# User-invoked: /devlog-tracker:session-context-on filesystem side.
set -uo pipefail

PROJECT_DIR="${DEVLOG_PROJECT_DIR:-}"
if [[ "$PROJECT_DIR" != /* ]] || [ ! -d "$PROJECT_DIR" ]; then
  echo "DEVLOG_PROJECT_DIR must be an existing absolute directory" >&2
  exit 1
fi

SWITCH="$PROJECT_DIR/.devlog-session-context"
if [ ! -e "$SWITCH" ] && [ ! -L "$SWITCH" ]; then
  echo "SESSION_CONTEXT_ALREADY_ENABLED"
  exit 0
fi

if ! rm -f -- "$SWITCH" || [ -e "$SWITCH" ] || [ -L "$SWITCH" ]; then
  echo "failed to remove $SWITCH" >&2
  exit 1
fi
echo "SESSION_CONTEXT_ENABLED"
