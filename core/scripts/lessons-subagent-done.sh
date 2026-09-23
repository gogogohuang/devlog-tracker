#!/usr/bin/env bash
# PostToolUse hook（Claude Code，matcher Agent|Task）：前景 sub agent 跑完、
# 結果回到主 session 時，Lessons Mode 開著就用 additionalContext 提示主
# session 檢查 sub agent 訊號（docs/design/lessons-mode.md「sub agent／
# workflow 情境」）。背景 agent 在這裡只是剛啟動（tool_response.status 為
# async_launched），完成時改由 round-start.sh 的 task-notification 分支提示，
# 這裡略過；sub agent 自己再派 agent（payload 帶 agent_id）也略過。
# fail-open：任何問題都 exit 0、不輸出。

set -uo pipefail

_src="${BASH_SOURCE[0]}"
HOOKS_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$HOOKS_DIR/json-field.sh"
PROJECT_DIR="${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
[ -f "$PROJECT_DIR/.devlog/.enabled" ] || exit 0
[ -f "$PROJECT_DIR/.devlog/.lessons-enabled" ] || exit 0

INPUT="$(cat 2>/dev/null || true)"
[ -n "$(json_str_field "$INPUT" agent_id)" ] && exit 0

ASYNC=0
if command -v jq >/dev/null 2>&1; then
  if printf '%s' "$INPUT" | jq -e '(.tool_response.status? == "async_launched") or (.tool_response.isAsync? == true)' >/dev/null 2>&1; then
    ASYNC=1
  fi
else
  case "$INPUT" in
    *'"status":"async_launched"'*|*'"isAsync":true'*) ASYNC=1 ;;
  esac
fi
[ "$ASYNC" -eq 1 ] && exit 0

printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[Lessons Mode 提示] sub agent 完成。讀完回報後檢查：verify 推翻先前的 fix／claim、sub agent 自陳繞路、多個 agent 卡在類似問題、成果被打回票——有的話可考慮用 lessons-append.sh 記一筆（sub agent 若已自己記過就不用重複），非強制。"}}'
exit 0
