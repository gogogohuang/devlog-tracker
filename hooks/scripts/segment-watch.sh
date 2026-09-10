#!/usr/bin/env bash
# PreToolUse hook：同一輪若太久沒改 devlog.md，擋住下一個工具，逼補 ### 段落。
# fail-open：這支腳本自己出錯一律 exit 0，不該卡死使用者的 session。

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
ENABLED_FLAG="$DEVLOG_DIR/.enabled"
DEVLOG_FILE="$DEVLOG_DIR/devlog.md"
SEGMENT_FILE="$DEVLOG_DIR/.segment-state"

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"

[ -f "$ENABLED_FLAG" ] || exit 0
[ -f "$SEGMENT_FILE" ] || exit 0

INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0

STORED="$(json_str_get "$SEGMENT_FILE" session_id 2>/dev/null || true)"
INCOMING="$(json_str_field "$INPUT" session_id)"
if [ -n "$STORED" ] && [ -n "$INCOMING" ] && [ "$STORED" != "$INCOMING" ]; then
  exit 0
fi

AGENT_ID="$(json_str_field "$INPUT" agent_id)"
[ "$AGENT_ID" = "null" ] && AGENT_ID=""
if [ -n "$AGENT_ID" ]; then
  exit 0
fi

SEG_EPOCH="$(json_int_get "$SEGMENT_FILE" last_change_epoch)"
SEG_MAX="$(json_int_get "$SEGMENT_FILE" max_silent_seconds)"
SEG_SUM="$(json_str_get "$SEGMENT_FILE" last_seen_cksum)"
SEG_SUM_KEY="$(grep -o '"last_seen_cksum"[[:space:]]*:' "$SEGMENT_FILE" 2>/dev/null || echo '')"

case "$SEG_EPOCH" in ''|*[!0-9]*) exit 0 ;; esac
case "$SEG_MAX" in ''|*[!0-9]*) exit 0 ;; esac
[ -n "$SEG_SUM_KEY" ] || exit 0

persist_seen() {
  local epoch="$1" sum="$2" mt="$3" sz="$4"
  json_int_set "$SEGMENT_FILE" last_change_epoch "$epoch"
  json_str_set "$SEGMENT_FILE" last_seen_cksum "$sum"
  [ -n "$mt" ] && json_str_set "$SEGMENT_FILE" last_seen_mtime "$mt"
  [ -n "$sz" ] && json_str_set "$SEGMENT_FILE" last_seen_size "$sz"
}

devlog_file_identity() {
  # prints: "<mtime_epoch> <size_bytes>" or empty on failure
  local f="$1" mt sz
  if mt="$(stat -f '%m' "$f" 2>/dev/null)" && sz="$(stat -f '%z' "$f" 2>/dev/null)"; then
    printf '%s %s\n' "$mt" "$sz"
    return 0
  fi
  if mt="$(stat -c '%Y' "$f" 2>/dev/null)" && sz="$(stat -c '%s' "$f" 2>/dev/null)"; then
    printf '%s %s\n' "$mt" "$sz"
    return 0
  fi
  return 1
}

NOW="$(date +%s 2>/dev/null || echo '')"
case "$NOW" in ''|*[!0-9]*) exit 0 ;; esac

ID_MT=""; ID_SZ=""
if [ -f "$DEVLOG_FILE" ]; then
  ID="$(devlog_file_identity "$DEVLOG_FILE" || true)"
  ID_MT="${ID%% *}"
  ID_SZ="${ID#* }"
  STORED_MT="$(json_str_get "$SEGMENT_FILE" last_seen_mtime 2>/dev/null || true)"
  STORED_SZ="$(json_str_get "$SEGMENT_FILE" last_seen_size 2>/dev/null || true)"
  if [ -n "$ID_MT" ] && [ -n "$ID_SZ" ] && [ "$ID_MT" = "$STORED_MT" ] && [ "$ID_SZ" = "$STORED_SZ" ] && [ -n "$SEG_SUM" ]; then
    CURRENT="$SEG_SUM"
  else
    CURRENT="$(cksum < "$DEVLOG_FILE" 2>/dev/null | tr -d '\n' || echo '')"
    ID="$(devlog_file_identity "$DEVLOG_FILE" || true)"
    ID_MT="${ID%% *}"
    ID_SZ="${ID#* }"
  fi
else
  CURRENT="MISSING"
  ID_MT=""; ID_SZ=""
fi
[ -n "$CURRENT" ] || exit 0

if [ "$CURRENT" != "$SEG_SUM" ]; then
  persist_seen "$NOW" "$CURRENT" "$ID_MT" "$ID_SZ"
  exit 0
fi

TOOL_NAME="$(json_str_field "$INPUT" tool_name)"
FILE_PATH=""
if command -v jq >/dev/null 2>&1; then
  FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || echo '')"
  [ "$FILE_PATH" = "null" ] && FILE_PATH=""
else
  FILE_PATH="$(printf '%s' "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo '')"
  if [ -z "$FILE_PATH" ]; then
    FILE_PATH="$(printf '%s' "$INPUT" | grep -o '"path"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo '')"
  fi
fi
[ -n "$TOOL_NAME" ] || exit 0

case "$TOOL_NAME" in
  Write|Edit|StrReplace|Read|Grep)
    case "$FILE_PATH" in
      .devlog/devlog.md|*/.devlog/devlog.md) exit 0 ;;
    esac
    ;;
esac

ELAPSED=$((NOW - SEG_EPOCH))
if [ "$ELAPSED" -ge "$SEG_MAX" ]; then
  echo "這一輪已經 ${ELAPSED} 秒沒有更新 .devlog/devlog.md（門檻 ${SEG_MAX} 秒）。請先 Read .devlog/devlog.md，再用 Edit 或 StrReplace **追加**一段「### 段落」（一行也可以）；禁止用 Write 覆寫整份檔。寫完再繼續呼叫其他工具。" >&2
  exit 2
fi

exit 0
