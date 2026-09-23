#!/usr/bin/env bash
# Sources for /devlog-tracker:promote (docs/design/read-side-and-promote.md D):
# kept files, lessons files, and Checkpoint headings in the current branch's
# devlog. Plain read only. compact never moves Checkpoints, so the archive has
# none to list.
set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=devlog-md.sh
. "$SCRIPT_DIR/devlog-md.sh"
# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"

PROJECT_DIR="$(cd "${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}" 2>/dev/null && pwd)" || { echo "NO_SOURCES"; exit 0; }
devlog_resolve_paths "$PROJECT_DIR"
MAIN="$DEVLOG_FILE"
[ -f "$MAIN" ] || { echo "NO_SOURCES"; exit 0; }

OUT=""
add() { OUT="$OUT$1"$'\n'; }
exists_flag() { if [ -f "$1" ]; then printf '1'; else printf '0'; fi; }

while IFS= read -r name; do
  [ -n "$name" ] || continue
  f="$DEVLOG_DIR/devlog.$name.md"
  add "FILE=$f KIND=kept EXISTS=$(exists_flag "$f")"
done < <(devlog_kept_index_lines "$MAIN" | sed -nE 's/.*`devlog\.([^`]+)\.md`.*/\1/p')

while IFS= read -r topic; do
  [ -n "$topic" ] || continue
  f="$DEVLOG_DIR/devlog.lessons.$topic.md"
  add "FILE=$f KIND=lessons EXISTS=$(exists_flag "$f")"
done < <(devlog_lessons_index_lines "$MAIN" | sed -nE 's/.*`devlog\.lessons\.([^`]+)\.md`.*/\1/p')

while IFS= read -r ln; do
  [ -n "$ln" ] && add "CHECKPOINT=$MAIN:$ln"
done < <(awk '/^[ \t]*```/ { fence = !fence; next } !fence && /^## Checkpoint/ { print NR }' "$MAIN")

if [ -z "$OUT" ]; then echo "NO_SOURCES"; else printf '%s' "$OUT"; fi
