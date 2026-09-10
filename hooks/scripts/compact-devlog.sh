#!/usr/bin/env bash
set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
. "$SCRIPT_DIR/devlog-md.sh"
. "$SCRIPT_DIR/devlog-lock.sh"

DEVLOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.devlog"
devlog_lock_acquire
trap 'devlog_lock_release' EXIT
MAIN="$DEVLOG_DIR/devlog.md"
ARCHIVE="$DEVLOG_DIR/devlog.archive.md"
[ -f "$MAIN" ] || { echo "devlog.md 不存在" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/devlog-compact.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"; devlog_lock_release' EXIT
STARTS="$TMP/starts"
MOVE="$TMP/move"
CANDIDATES="$TMP/candidates"
MOVED_BLOCKS="$TMP/moved"
NEW_MAIN="$TMP/main"
devlog_list_round_starts "$MAIN" > "$STARTS"
: > "$MOVE"
: > "$CANDIDATES"

TOTAL="$(wc -l < "$STARTS" | tr -d ' ')"
while read -r start _; do
  [ -n "${start:-}" ] || continue
  end="$(devlog_block_end "$MAIN" "$start")"
  status="$(devlog_round_status "$MAIN" "$start" "$end")"
  case "$status" in
    IN_PROGRESS|BLOCKED|INTERRUPTED) ;;
    *) printf '%s\n' "$start" >> "$CANDIDATES" ;;
  esac
done < "$STARTS"

COMPLETED="$(wc -l < "$CANDIDATES" | tr -d ' ')"
TO_MOVE=$((COMPLETED > 5 ? COMPLETED - 5 : 0))
awk -v count="$TO_MOVE" 'NR <= count { print }' "$CANDIDATES" > "$MOVE"
MOVED="$(wc -l < "$MOVE" | tr -d ' ')"
if [ "$MOVED" -eq 0 ]; then
  ARCHIVE_COUNT=0
  [ ! -f "$ARCHIVE" ] || ARCHIVE_COUNT="$(devlog_list_round_starts "$ARCHIVE" | wc -l | tr -d ' ')"
  printf 'MOVED=0 REMAINING=%s ARCHIVE=%s\n' "$TOTAL" "$ARCHIVE_COUNT"
  exit 0
fi

awk -v move_file="$MOVE" -v moved_file="$MOVED_BLOCKS" '
  BEGIN {
    while ((getline line < move_file) > 0) move[line] = 1
  }
  /^[ \t]*```/ { fence = !fence }
  !fence && /^## / {
    moving = (NR in move)
  }
  moving { print >> moved_file; next }
  { print }
' "$MAIN" > "$NEW_MAIN" || exit 1

while read -r start; do
  heading="$(awk -v n="$start" 'NR == n { print; exit }' "$MAIN")"
  grep -Fqx "$heading" "$MOVED_BLOCKS" || { echo "archive 驗證失敗" >&2; exit 1; }
done < "$MOVE"

cat "$MOVED_BLOCKS" >> "$ARCHIVE" || exit 1
mv "$NEW_MAIN" "$MAIN" || exit 1

REMAINING="$(devlog_list_round_starts "$MAIN" | wc -l | tr -d ' ')"
ARCHIVE_COUNT="$(devlog_list_round_starts "$ARCHIVE" | wc -l | tr -d ' ')"
printf 'MOVED=%s REMAINING=%s ARCHIVE=%s\n' "$MOVED" "$REMAINING" "$ARCHIVE_COUNT"
