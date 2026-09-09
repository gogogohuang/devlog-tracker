#!/usr/bin/env bash
# PreToolUse hook：同一輪若太久沒改 devlog.md，擋住下一個工具，逼補 ### 段落。
# fail-open：這支腳本自己出錯一律 exit 0，不該卡死使用者的 session。

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
ENABLED_FLAG="$DEVLOG_DIR/.enabled"
DEVLOG_FILE="$DEVLOG_DIR/devlog.md"
SEGMENT_FILE="$DEVLOG_DIR/.segment-state"

[ -f "$ENABLED_FLAG" ] || exit 0
[ -f "$SEGMENT_FILE" ] || exit 0

INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0

SEG_EPOCH="$(grep -o '"last_change_epoch"[[:space:]]*:[[:space:]]*[0-9]\+' "$SEGMENT_FILE" 2>/dev/null | grep -o '[0-9]\+$' || echo '')"
SEG_MAX="$(grep -o '"max_silent_seconds"[[:space:]]*:[[:space:]]*[0-9]\+' "$SEGMENT_FILE" 2>/dev/null | grep -o '[0-9]\+$' || echo '')"
SEG_SUM="$(grep -o '"last_seen_cksum"[[:space:]]*:[[:space:]]*"[^"]*"' "$SEGMENT_FILE" 2>/dev/null | sed 's/.*"last_seen_cksum"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo '')"
SEG_SUM_KEY="$(grep -o '"last_seen_cksum"[[:space:]]*:' "$SEGMENT_FILE" 2>/dev/null || echo '')"

case "$SEG_EPOCH" in ''|*[!0-9]*) exit 0 ;; esac
case "$SEG_MAX" in ''|*[!0-9]*) exit 0 ;; esac
[ -n "$SEG_SUM_KEY" ] || exit 0

persist_seen() {
  local epoch="$1" sum="$2"
  awk -v epoch="$epoch" -v sum="$sum" '{
    gsub(/"last_change_epoch"[[:space:]]*:[[:space:]]*[0-9]+/, "\"last_change_epoch\": " epoch);
    gsub(/"last_seen_cksum"[[:space:]]*:[[:space:]]*"[^"]*"/, "\"last_seen_cksum\": \"" sum "\"");
    print
  }' "$SEGMENT_FILE" > "$SEGMENT_FILE.tmp" 2>/dev/null \
    && mv "$SEGMENT_FILE.tmp" "$SEGMENT_FILE" 2>/dev/null || true
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
