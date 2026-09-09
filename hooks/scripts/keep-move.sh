#!/usr/bin/env bash
set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
. "$SCRIPT_DIR/devlog-md.sh"
. "$SCRIPT_DIR/json-field.sh"
. "$SCRIPT_DIR/devlog-lock.sh"

FROM=""
TO=""
NAME=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --from) FROM="${2:-}"; shift 2 ;;
    --to) TO="${2:-}"; shift 2 ;;
    --name) NAME="${2:-}"; shift 2 ;;
    *) echo "未知參數：$1" >&2; exit 1 ;;
  esac
done
case "$FROM:$TO" in *[!0-9:]*|:*) echo "範圍無效" >&2; exit 1 ;; esac
[ "$FROM" -le "$TO" ] || { echo "範圍起點不可大於終點" >&2; exit 1; }

case "$NAME" in *'/'*|*'\'*|*'..'*) echo "檔名無效" >&2; exit 1 ;; esac
case "$NAME" in devlog.*) NAME="${NAME#devlog.}" ;; esac
case "$NAME" in *.md) NAME="${NAME%.md}" ;; esac
NAME="$(printf '%s' "$NAME" | tr ' ' '-' | sed -E 's/-+/-/g; s/^-//; s/-$//')"
[ -n "$NAME" ] && [ "$NAME" != "archive" ] && [ "$NAME" != "devlog.md" ] \
  || { echo "檔名無效" >&2; exit 1; }
[ "${#NAME}" -le 64 ] || { echo "檔名超過 64 字元" >&2; exit 1; }

DEVLOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.devlog"
devlog_lock_acquire
trap 'devlog_lock_release' EXIT
MAIN="$DEVLOG_DIR/devlog.md"
TARGET="$DEVLOG_DIR/devlog.$NAME.md"
[ -f "$MAIN" ] || { echo "devlog.md 不存在" >&2; exit 1; }
[ ! -e "$TARGET" ] || { echo "目標檔案已存在：$TARGET" >&2; exit 1; }

OPEN=""
[ ! -f "$DEVLOG_DIR/.round-open" ] || OPEN="$(json_int_get "$DEVLOG_DIR/.round-open" round)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/devlog-keep.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"; devlog_lock_release' EXIT
STARTS="$TMP/starts"
MOVE_ROUNDS="$TMP/move-rounds"
MOVE_BLOCKS="$TMP/move-blocks"
H2="$TMP/h2"
NEW_MAIN="$TMP/main"
devlog_list_round_starts "$MAIN" > "$STARTS"
: > "$MOVE_ROUNDS"
: > "$MOVE_BLOCKS"

HISTORICAL=0
FIRST_ROUND=""
LAST_MOVED_END=""
while read -r start round; do
  [ -n "${start:-}" ] || continue
  [ -n "$FIRST_ROUND" ] || FIRST_ROUND="$start"
  [ "$round" = "$OPEN" ] && continue
  HISTORICAL=$((HISTORICAL + 1))
  if [ "$round" -ge "$FROM" ] && [ "$round" -le "$TO" ]; then
    printf '%s %s\n' "$start" "$round" >> "$MOVE_ROUNDS"
    printf '%s\n' "$start" >> "$MOVE_BLOCKS"
    LAST_MOVED_END="$(devlog_block_end "$MAIN" "$start")"
  fi
done < "$STARTS"

EXPECTED=$((TO - FROM + 1))
MOVED="$(wc -l < "$MOVE_ROUNDS" | tr -d ' ')"
[ "$MOVED" -eq "$EXPECTED" ] || { echo "範圍內有不存在或非歷史的 Round" >&2; exit 1; }
[ "$HISTORICAL" -gt 0 ] || { echo "目前沒有東西可 keep" >&2; exit 1; }
FULL=0
[ "$MOVED" -eq "$HISTORICAL" ] && FULL=1
FIRST_MOVED="$(awk 'NR == 1 { print $1 }' "$MOVE_ROUNDS")"

awk '
  /^```/ { fence = !fence }
  !fence && /^## / { print NR "\t" $0 }
' "$MAIN" > "$H2"
while IFS="$(printf '\t')" read -r start heading; do
  case "$heading" in
    "## Checkpoint"*)
      span="$(printf '%s' "$heading" | sed -nE 's/.*Round ([0-9]+)-([0-9]+).*/\1 \2/p')"
      if [ -n "$span" ]; then
        x="${span%% *}"; y="${span##* }"
        if [ "$x" -ge "$FROM" ] && [ "$y" -le "$TO" ]; then
          printf '%s\n' "$start" >> "$MOVE_BLOCKS"
        fi
      elif [ "$start" -gt "$FIRST_MOVED" ] && [ "$start" -le "$LAST_MOVED_END" ]; then
        printf '%s\n' "$start" >> "$MOVE_BLOCKS"
      fi
      ;;
  esac
done < "$H2"

KEPT_AT="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"
{
  printf '# Kept log\n\n- source: `.devlog/devlog.md`\n- rounds: %s-%s\n- kept_at: %s\n\n' \
    "$FROM" "$TO" "$KEPT_AT"
  awk -v selected="$MOVE_BLOCKS" -v full="$FULL" -v first_round="$FIRST_ROUND" '
    BEGIN { while ((getline n < selected) > 0) move[n] = 1 }
    /^```/ { fence = !fence }
    !fence && /^## / { moving = (NR in move) }
    full && NR < first_round { print; next }
    moving { print }
  ' "$MAIN"
} > "$TARGET" || exit 1

while read -r start round; do
  heading="$(awk -v n="$start" 'NR == n { print; exit }' "$MAIN")"
  grep -Fqx "$heading" "$TARGET" || { echo "具名檔驗證失敗" >&2; exit 1; }
done < "$MOVE_ROUNDS"

awk -v selected="$MOVE_BLOCKS" -v full="$FULL" -v first_round="$FIRST_ROUND" -v open="$OPEN" '
  BEGIN { while ((getline n < selected) > 0) move[n] = 1 }
  /^```/ { fence = !fence }
  !fence && /^## / { moving = (NR in move) }
  full && NR < first_round { next }
  moving { next }
  full && open != "" && $0 ~ ("^## Round " open "([^0-9]|$)") {
    sub("^## Round " open, "## Round 1")
  }
  { print }
' "$MAIN" > "$NEW_MAIN" || exit 1
mv "$NEW_MAIN" "$MAIN" || exit 1

if [ "$FULL" -eq 1 ]; then
  rm -f "$DEVLOG_DIR/.span-open"
  [ ! -f "$DEVLOG_DIR/.round-open" ] || json_int_set "$DEVLOG_DIR/.round-open" round 1
  [ ! -f "$DEVLOG_DIR/.checkpoint-state" ] || json_int_set "$DEVLOG_DIR/.checkpoint-state" rounds_since_checkpoint 0
elif [ -f "$DEVLOG_DIR/.span-open" ]; then
  SPAN_ROUND="$(json_int_get "$DEVLOG_DIR/.span-open" round)"
  if [ -n "$SPAN_ROUND" ] && [ "$SPAN_ROUND" -ge "$FROM" ] && [ "$SPAN_ROUND" -le "$TO" ]; then
    rm -f "$DEVLOG_DIR/.span-open"
  fi
fi

REMAINING="$(devlog_list_round_starts "$MAIN" | wc -l | tr -d ' ')"
printf 'KEPT=%s ROUNDS=%s-%s REMAINING=%s\n' "$TARGET" "$FROM" "$TO" "$REMAINING"
