#!/usr/bin/env bash
set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
. "$SCRIPT_DIR/devlog-md.sh"
. "$SCRIPT_DIR/json-field.sh"
. "$SCRIPT_DIR/devlog-lock.sh"

# Destructive and irreversible: only run when the caller has explicitly
# confirmed with the user first. This is a mechanical guard, not a
# replacement for that confirmation.
[ "${1:-}" = "--confirmed" ] || { echo "需要 --confirmed（使用者尚未確認，不要呼叫這支腳本）" >&2; exit 1; }

DEVLOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.devlog"
devlog_lock_acquire
trap 'devlog_lock_release' EXIT
MAIN="$DEVLOG_DIR/devlog.md"
[ -f "$MAIN" ] || { echo "devlog.md 不存在" >&2; exit 1; }

ROUND_OPEN="$DEVLOG_DIR/.round-open"
FOUND_START=""
OPEN=""
if [ -f "$ROUND_OPEN" ]; then
  OPEN="$(json_int_get "$ROUND_OPEN" round)"
  [ -n "$OPEN" ] || { echo ".round-open 內容無法解析，未清空" >&2; exit 1; }
  FOUND_START="$(devlog_list_round_starts "$MAIN" | awk -v r="$OPEN" '$2 == r { print $1 }' | tail -1)"
  [ -n "$FOUND_START" ] || { echo "找不到開著的 Round $OPEN，狀態可能不一致，未清空" >&2; exit 1; }
fi

if [ -n "$FOUND_START" ]; then
  END="$(devlog_block_end "$MAIN" "$FOUND_START")"
  TMP_DIR="$(mktemp -d "$DEVLOG_DIR/.clean.XXXXXX")" || exit 1
  trap 'rm -rf "$TMP_DIR"; devlog_lock_release' EXIT
  NEW_MAIN="$TMP_DIR/devlog.md"
  awk -v start="$FOUND_START" -v end="$END" -v open="$OPEN" '
    NR < start || NR > end { next }
    NR == start && $0 ~ ("^## Round " open "([^0-9]|$)") {
      sub("^## Round " open, "## Round 1")
    }
    { print }
  ' "$MAIN" > "$NEW_MAIN" || exit 1
  [ -s "$NEW_MAIN" ] && grep -q '^## Round 1' "$NEW_MAIN" || { echo "重寫結果異常，未寫入" >&2; exit 1; }
  mv "$NEW_MAIN" "$MAIN" || exit 1
  rm -rf "$TMP_DIR"
  json_int_set "$ROUND_OPEN" round 1
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
