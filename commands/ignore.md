---
description: 管理專案根目錄的 .devlogignore——列出、新增、移除 ignore pattern，或檢查某個路徑是否被 ignore。
---

取得子指令：`list`（預設）、`add <pattern>`、`remove <pattern>`、`check <path>`；`add`／`remove`／`check` 沒帶參數就先問，不要猜。
跑：

```bash
PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
DEVLOG_PROJECT_DIR="<專案根目錄絕對路徑，不要用 $(pwd) 重新推>" bash "${PLUGIN_ROOT}/core/scripts/ignore-patterns.sh" <list|add|remove|check> [<pattern-or-path>]
```

`.devlogignore` 放在專案根目錄，語法是 gitignore 子集（`*.lock`、`dist/`、`!keep.lock`；不支援 `[...]` 與 `\`）。不需要先 `/devlog-tracker:start`。手動編輯該檔同樣有效。

- `list`：原樣顯示輸出（含行號）；沒有檔案就告知尚無 `.devlogignore`。
- `add`／`remove`：原樣顯示結果（`added`／`already present`／`removed`／`not found`）。`remove` 只刪完全相同的行。
- `check`：顯示該路徑是否被 ignore；輸出為 `matching unavailable` 時告知目前版本沒有 matcher。
- exit 1：原樣顯示 stderr（用法），請使用者修正後再試。

不要自己手改 `.devlogignore` 的內容來代替這個指令；這一輪不開新的 Round。
