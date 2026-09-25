---
description: 把 devlog 產生成一份離線可開的 HTML 時間軸（.devlog/timeline.html），可依 Status／branch／關鍵字篩選。
---

先決定 plugin 根目錄（有 `DEVLOG_TRACKER_ROOT` 用它；否則用 `CLAUDE_PLUGIN_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄），再跑：

```bash
PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
DEVLOG_PROJECT_DIR="<專案根目錄絕對路徑，不要用 $(pwd) 重新推>" bash "${PLUGIN_ROOT}/core/scripts/timeline-devlog.sh"
```

使用者要看所有 branch 時加 `--all-branches`；要寫到別的位置時加 `--out <路徑>`。

- `NO_NODE`：告知這個功能需要 Node.js（≥18），裝好後再跑；結束。
- `NOT_STARTED`：告知還沒 `/devlog-tracker:start`，結束。
- `OUT=<路徑>`：告知檔案位置，並提示可以直接用瀏覽器開（macOS：`open <路徑>`）。不要自己打開瀏覽器，也不要把 HTML 內容貼進對話。

時間軸不含 User Input 原文。`.devlog/timeline.html` 在 `.devlog/` 底下，每次重跑會覆寫；`.devlog/` 通常已被 gitignore，沒有的話別把它 commit。
