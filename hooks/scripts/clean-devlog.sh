#!/usr/bin/env bash
set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
. "$SCRIPT_DIR/devlog-md.sh"
. "$SCRIPT_DIR/json-field.sh"
. "$SCRIPT_DIR/devlog-lock.sh"

DEVLOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.devlog"
devlog_lock_acquire
trap 'devlog_lock_release' EXIT
MAIN="$DEVLOG_DIR/devlog.md"
[ -f "$MAIN" ] || { echo "devlog.md 不存在" >&2; exit 1; }

OPEN=""
[ ! -f "$DEVLOG_DIR/.round-open" ] || OPEN="$(json_int_get "$DEVLOG_DIR/.round-open" round)"

FOUND_START=""
if [ -n "$OPEN" ]; then
  FOUND_START="$(devlog_list_round_starts "$MAIN" | awk -v r="$OPEN" '$2 == r { print $1 }' | tail -1)"
fi

if [ -n "$FOUND_START" ]; then
  END="$(devlog_block_end "$MAIN" "$FOUND_START")"
  TMP="$(mktemp "${TMPDIR:-/tmp}/devlog-clean.XXXXXX")" || exit 1
  awk -v start="$FOUND_START" -v end="$END" -v open="$OPEN" '
    NR < start || NR > end { next }
    NR == start && $0 ~ ("^## Round " open "([^0-9]|$)") {
      sub("^## Round " open, "## Round 1")
    }
    { print }
  ' "$MAIN" > "$TMP" || { rm -f "$TMP"; exit 1; }
  mv "$TMP" "$MAIN" || exit 1
  [ ! -f "$DEVLOG_DIR/.round-open" ] || json_int_set "$DEVLOG_DIR/.round-open" round 1
  KEPT_ROUND=1
else
  rm -f "$MAIN" || exit 1
  KEPT_ROUND=0
fi

rm -f "$DEVLOG_DIR/.span-open" "$DEVLOG_DIR/.interrupted" "$DEVLOG_DIR/.awaiting-reply"
if [ -f "$DEVLOG_DIR/.checkpoint-state" ]; then
  json_int_set "$DEVLOG_DIR/.checkpoint-state" rounds_since_checkpoint 0
  json_int_set "$DEVLOG_DIR/.checkpoint-state" checkpoint_marker_count 0
fi

printf 'CLEANED KEPT_ROUND=%s\n' "$KEPT_ROUND"
exit 0
