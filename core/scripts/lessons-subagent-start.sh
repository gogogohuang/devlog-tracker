#!/usr/bin/env bash
# SubagentStart hook（Claude Code）：Lessons Mode 開著時，把「可以自己呼叫
# lessons-append.sh」的說明注入 sub agent／Workflow agent 的 context
# （docs/design/lessons-mode.md「sub agent／workflow 情境」）。
# sub agent 的 Bash 裡沒有 CLAUDE_PROJECT_DIR，isolation: "worktree" 時 cwd
# 還是 worktree（沒有 .devlog/），所以專案目錄跟腳本路徑都在這裡寫死成
# 主專案的絕對路徑。fail-open：任何問題都 exit 0、不輸出。

set -uo pipefail

_src="${BASH_SOURCE[0]}"
HOOKS_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$HOOKS_DIR/json-field.sh"
PROJECT_DIR="${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
[ -f "$PROJECT_DIR/.devlog/.enabled" ] || exit 0
[ -f "$PROJECT_DIR/.devlog/.lessons-enabled" ] || exit 0
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || exit 0
cat >/dev/null 2>&1 || true

MSG="[devlog-tracker Lessons Mode] 這個專案開著 Lessons Mode：記錄開發**過程**踩過的坑（不是架構知識）。如果這次任務中你繞了一大圈才找到對的做法、先前的 fix／claim 被驗證推翻、或卡在某個值得後人避開的坑，可以直接記一筆（非強制，沒有就不用記）：

DEVLOG_PROJECT_DIR='${PROJECT_DIR}' bash '${HOOKS_DIR}/lessons-append.sh' --topic '<kebab-case 主題，2–4 段>' --text '<一段自由散文：卡在哪、怎麼解開、下次怎麼避免>'

路徑都是絕對路徑，在 worktree 裡也照原樣用，不要改成相對路徑。有記的話，在最終回報裡用一句話說明記了哪個主題；腳本回報 NEW_TOPIC 時可改用它列出的既有主題重跑。"

printf '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"%s"}}\n' "$(json_escape "$MSG")"
exit 0
