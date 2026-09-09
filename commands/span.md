---
description: 開啟或關閉 Span Mode，讓自動續接的長任務定期記錄進度。
---

先判斷使用者要開啟或關閉：

- 使用者明確要求關閉，或 `.devlog/.span-open` 已存在且沒有明確要求重新開啟：
  先跑 `CLAUDE_PROJECT_DIR="$(pwd)" bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/span-close.sh"`，
  再依 SKILL 的 span 收尾規則寫一個**新的 Round**，總結整段 span。
- 使用者要求開啟：先把目前 Round 正常寫完，`Status` 設為 `IN_PROGRESS`，再跑
  `CLAUDE_PROJECT_DIR="$(pwd)" bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/span-open.sh"`。

不要手寫 `.span-open` JSON。腳本 exit 1 時顯示 stderr，停止操作。
