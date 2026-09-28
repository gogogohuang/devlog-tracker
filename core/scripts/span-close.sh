#!/usr/bin/env bash
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"
devlog_resolve_paths "${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
if [ ! -e "$SPAN_FILE" ]; then
  echo "NOT_OPEN"
  exit 0
fi
rm -f "$SPAN_FILE" || exit 1
echo "CLOSED"
