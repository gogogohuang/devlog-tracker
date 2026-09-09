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
INCOMING=""
if command -v jq >/dev/null 2>&1; then
  INCOMING="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
  [ "$INCOMING" = "null" ] && INCOMING=""
else
  INCOMING="$(printf '%s' "$INPUT" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
fi
if [ -n "$STORED" ] && [ -n "$INCOMING" ] && [ "$STORED" != "$INCOMING" ]; then
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
  local epoch="$1" sum="$2"
  json_int_set "$SEGMENT_FILE" last_change_epoch "$epoch"
  json_str_set "$SEGMENT_FILE" last_seen_cksum "$sum"
}

NOW="$(date +%s 2>/dev/null || echo '')"
case "$NOW" in ''|*[!0-9]*) exit 0 ;; esac

if [ -f "$DEVLOG_FILE" ]; then
  CURRENT="$(cksum < "$DEVLOG_FILE" 2>/dev/null | tr -d '\n' || echo '')"
else
  CURRENT="MISSING"
fi
[ -n "$CURRENT" ] || exit 0

if [ "$CURRENT" != "$SEG_SUM" ]; then
  persist_seen "$NOW" "$CURRENT"
  exit 0
fi

TOOL_NAME=""
FILE_PATH=""
if command -v jq >/dev/null 2>&1; then
  TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo '')"
  FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo '')"
else
  TOOL_NAME="$(printf '%s' "$INPUT" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo '')"
  FILE_PATH="$(printf '%s' "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo '')"
fi
[ -n "$TOOL_NAME" ] || exit 0

if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ]; then
  case "$FILE_PATH" in
    .devlog/devlog.md|*/.devlog/devlog.md) exit 0 ;;
  esac
fi

ELAPSED=$((NOW - SEG_EPOCH))
if [ "$ELAPSED" -ge "$SEG_MAX" ]; then
  echo "這一輪已經 ${ELAPSED} 秒沒有更新 .devlog/devlog.md（門檻 ${SEG_MAX} 秒）。請先追加一段「### 段落」（一行也可以），寫完再繼續呼叫工具。" >&2
  exit 2
fi

exit 0
