---
name: devlog-ignore
description: "管理專案根目錄的 .devlogignore——列出、新增、移除 ignore pattern，或檢查某個路徑是否被 ignore。"
---

Codex plugin 安裝：目前這份 `SKILL.md` 的絕對路徑位於
`<plugin 根目錄>/codex/skills/<skill 名稱>/SKILL.md`。每次用 shell 執行下方步驟時，
先從這份檔案的所在目錄往上三層取得 plugin 根目錄，並在同一次 shell 呼叫中
`export DEVLOG_TRACKER_ROOT="<該根目錄的絕對路徑>"`。
一般 shell 呼叫不一定有 hook 專用的 `PLUGIN_ROOT`／`CLAUDE_PLUGIN_ROOT` 環境變數。
若是 npx 安裝，沿用專案內既有的 `DEVLOG_TRACKER_ROOT`。

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

使用者提供的額外參數：請看觸發這個 skill 的使用者訊息。
