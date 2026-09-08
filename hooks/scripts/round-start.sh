#!/usr/bin/env bash
# UserPromptSubmit hook：每次使用者送出新訊息時執行，
# 記下這一輪開始時 devlog.md 的內容雜湊，供 Stop hook 判斷這一輪有沒有寫過 devlog。
# 用雜湊而不是時間戳，避免同一秒內的寫入跟下一輪開始互相誤判（見 enforce-devlog.sh 註解）。
# fail-open：這支腳本本身出任何問題都不該影響使用者送出訊息，一律 exit 0。

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
ENABLED_FLAG="$DEVLOG_DIR/.enabled"
DEVLOG_FILE="$DEVLOG_DIR/devlog.md"

# 沒下過 /devlog-tracker:start（也就是沒有這個開關檔），代表這個專案沒啟動強制記錄，
# 直接放行，不留下任何 .devlog 檔案。
[ -f "$ENABLED_FLAG" ] || exit 0

if [ -f "$DEVLOG_FILE" ]; then
  cksum < "$DEVLOG_FILE" > "$DEVLOG_DIR/.turn-start" 2>/dev/null || true
else
  echo "MISSING" > "$DEVLOG_DIR/.turn-start" 2>/dev/null || true
fi

exit 0
