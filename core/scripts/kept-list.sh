#!/usr/bin/env bash
# Filesystem side of /devlog-tracker:overview (docs/design/keep.md "Kept
# index"). Plain read only -- parses the `## Kept 索引` block for the list
# of devlog.<name>.md files kept so far, checking each against disk so a
# manually-deleted file is reported as a ghost row instead of silently
# dropped (same tolerance as the index itself).
set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=devlog-md.sh
. "$SCRIPT_DIR/devlog-md.sh"
# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"

PROJECT_DIR="${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
devlog_resolve_paths "$PROJECT_DIR"
MAIN="$DEVLOG_FILE"

if [ ! -f "$MAIN" ]; then
  echo "NO_INDEX"
  exit 0
fi

LINES="$(devlog_kept_index_lines "$MAIN")"
if [ -z "$LINES" ]; then
  echo "NO_INDEX"
  exit 0
fi

printf '%s\n' "$LINES" | while IFS= read -r line; do
  name="$(printf '%s' "$line" | sed -nE 's/.*`devlog\.([^`]+)\.md`.*/\1/p')"
  [ -n "$name" ] || continue
  file="$DEVLOG_DIR/devlog.$name.md"
  if [ -f "$file" ]; then
    printf 'FILE=%s EXISTS=1\n' "$file"
  else
    printf 'FILE=%s EXISTS=0\n' "$file"
  fi
done
