#!/usr/bin/env bash
# User-invoked: /devlog-tracker:session-context-off filesystem side.
set -uo pipefail

PROJECT_DIR="${DEVLOG_PROJECT_DIR:-}"
if [[ "$PROJECT_DIR" != /* ]] || [ ! -d "$PROJECT_DIR" ]; then
  echo "DEVLOG_PROJECT_DIR must be an existing absolute directory" >&2
  exit 1
fi

if ! printf 'off' > "$PROJECT_DIR/.devlog-session-context"; then
  exit 1
fi
echo "SESSION_CONTEXT_DISABLED"
