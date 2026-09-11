---
description: 開啟 Lessons Mode（開發歷程教訓，預設關閉）。隸屬主開關：沒下過 /devlog-tracker:start 就開不了。
---

請執行：

1. 先決定 plugin 根目錄（有 `CLAUDE_PLUGIN_ROOT` 用它；否則用 `DEVLOG_TRACKER_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄）：
   ```bash
   PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${DEVLOG_TRACKER_ROOT:-}}"
   CLAUDE_PROJECT_DIR="$(pwd)" bash "${PLUGIN_ROOT}/hooks/scripts/lessons-on.sh"
   ```
   不要自己用手建 `.lessons-enabled`。
2. stdout 是 `NOT_ENABLED`：告知這個專案還沒下過 `/devlog-tracker:start`，Lessons Mode 隸屬主開關，沒有 Round/Status 紀錄可判斷「BLOCKED→解開」，請先 `/devlog-tracker:start` 再開這個。
3. stdout 是 `LESSONS_ENABLED=...`：告知 Lessons Mode 已開啟。簡短說明：
   - 這是給「開發歷程中的困難/決策」用的，不是架構知識庫（那個留在 `docs/design/*.md`）
   - 只有兩種訊號會讓你考慮記一筆：這輪的 Status 從 `BLOCKED` 解開，或你自己判斷這輪明顯繞了一圈才對
   - 完全不強制——寫不寫都不影響這一輪能不能收尾，跟 `#### 決策` 同一種「沒有就整節省略」的精神
   - 用 `/devlog-tracker:lessons` 查現有教訓，或 `/devlog-tracker:lessons-off` 關掉

不要因為 `.lessons-enabled` 已經存在就跳過步驟 3——重新確認一次現在的狀態即可。
