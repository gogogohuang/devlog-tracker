#!/usr/bin/env bash
# User-invoked: /devlog-tracker:session-context-off filesystem side.
set -euo pipefail

if [ -z "${DEVLOG_PROJECT_DIR:-}" ]; then
  echo "DEVLOG_PROJECT_DIR must be set to an absolute project directory" >&2
  exit 1
fi

case "$DEVLOG_PROJECT_DIR" in
  /*) ;;
  *)
    echo "DEVLOG_PROJECT_DIR must be an absolute project directory" >&2
    exit 1
    ;;
esac

if [ ! -d "$DEVLOG_PROJECT_DIR" ]; then
  echo "DEVLOG_PROJECT_DIR must be an existing directory" >&2
  exit 1
fi

printf 'off' > "$DEVLOG_PROJECT_DIR/.devlog-session-context"
echo "SESSION_CONTEXT_DISABLED"
