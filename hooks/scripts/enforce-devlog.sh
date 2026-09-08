#!/usr/bin/env bash
# Stop hook：Claude 想結束這一輪回應時執行。
# 檢查 devlog.md 的內容雜湊有沒有在這一輪開始之後變過，沒有就擋下來（exit 2），
# 逼 Claude 先依 SKILL.md 格式補寫這一輪的 Round 區塊，才能真正結束。
# 這是保證每輪都記錄的關鍵：不依賴 Claude 自行判斷「值不值得記錄」。
#
# 用內容雜湊（cksum）取代舊版的 mtime 比對：mtime 只有整秒精度，快速連續的
# 對話很容易讓「上一輪的寫入」跟「這一輪的開始」落在同一秒，導致誤判成
# 「已經寫過」而放行。雜湊直接比對內容有沒有變，不受時間精度影響，也不需要
# 再處理 GNU/BSD stat 的跨平台差異。
#
# 兩個穩健性設計，參考 agfnow/agentflow 的 stop-hook.js：
# 1. loop guard：讀 stdin 的 stop_hook_active 欄位，這是 Claude Code 官方標準欄位，
#    代表「這輪已經被本支 hook 擋下來、Claude 正在重跑」，此時直接放行，避免無窮迴圈
#    （Claude Code 本身也有連續擋 8 次的上限保護，這裡是多一層保險，且能更快恢復）。
# 2. fail-open：不用 set -e，每一步可能失敗的地方都明確接住、失敗就直接放行（exit 0），
#    絕不讓這支腳本自己的錯誤意外卡死使用者的 session——這支腳本的職責是「檢查」，
#    不該因為自己壞掉就變成「阻擋」。

set -uo pipefail

# --- loop guard -------------------------------------------------------
# 有 jq 就用 jq 精準解析；沒有 jq 就退化成字串比對（沒有更嚴謹的 parse，但
# 足以涵蓋 Claude Code 實際送出的 stop_hook_active 欄位形狀），兩種環境都要生效。
INPUT="$(cat 2>/dev/null || true)"
if command -v jq >/dev/null 2>&1; then
  STOP_HOOK_ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
else
  case "$INPUT" in
    *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) STOP_HOOK_ACTIVE=true ;;
    *)                                                          STOP_HOOK_ACTIVE=false ;;
  esac
fi
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# --- 開關檢查 -----------------------------------------------------------
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
ENABLED_FLAG="$DEVLOG_DIR/.enabled"
TURN_MARKER="$DEVLOG_DIR/.turn-start"
DEVLOG_FILE="$DEVLOG_DIR/devlog.md"

# 沒下過 /devlog-tracker:start，代表這個專案沒啟動強制記錄，直接放行。
# 這是唯一的判斷依據——不猜這輪是否呼叫了某個 skill，也不解析 transcript。
[ -f "$ENABLED_FLAG" ] || exit 0

# 還沒有 turn marker，代表 UserPromptSubmit hook 這次沒跑到（例如剛裝上、
# 或是某種特殊情況），直接放行避免卡住——fail-open。
[ -f "$TURN_MARKER" ] || exit 0

TURN_START_HASH="$(cat "$TURN_MARKER" 2>/dev/null || echo '')"
# marker 內容讀不出來（讀取失敗、被意外改壞等）就當作沒有可靠依據，放行。
[ -n "$TURN_START_HASH" ] || exit 0

if [ -f "$DEVLOG_FILE" ]; then
  CURRENT_HASH="$(cksum < "$DEVLOG_FILE" 2>/dev/null || echo '')"
else
  CURRENT_HASH="MISSING"
fi
# 一樣的防呆：雜湊算不出來就放行，不要因為偵測異常反而卡住使用者。
[ -n "$CURRENT_HASH" ] || exit 0

if [ "$CURRENT_HASH" = "$TURN_START_HASH" ]; then
  echo "這一輪還沒有寫進 .devlog/devlog.md。請依 skills/devlog-tracker/SKILL.md 的格式，在檔案尾端補上這一輪的 \`## Round <N>\`（User Input / Response / Status），寫完再結束這一輪。" >&2
  exit 2
fi

exit 0
