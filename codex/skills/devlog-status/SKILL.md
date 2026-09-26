---
name: devlog-status
description: "查看這個專案 devlog 強制記錄是否開著、span / checkpoint / 最後一輪 Status。"
---

Codex plugin 安裝：目前這份 `SKILL.md` 的絕對路徑位於
`<plugin 根目錄>/codex/skills/<skill 名稱>/SKILL.md`。每次用 shell 執行下方步驟時，
先從這份檔案的所在目錄往上三層取得 plugin 根目錄，並在同一次 shell 呼叫中
`export DEVLOG_TRACKER_ROOT="<該根目錄的絕對路徑>"`。
一般 shell 呼叫不一定有 hook 專用的 `PLUGIN_ROOT`／`CLAUDE_PLUGIN_ROOT` 環境變數。
若是 npx 安裝，沿用專案內既有的 `DEVLOG_TRACKER_ROOT`。

跑：
```bash
先決定 plugin 根目錄（有 `DEVLOG_TRACKER_ROOT` 用它；否則用 `CLAUDE_PLUGIN_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄）：

```bash
PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
DEVLOG_PROJECT_DIR="<專案根目錄絕對路徑，不要用 $(pwd) 重新推>" bash "${PLUGIN_ROOT}/core/scripts/status-devlog.sh"
```
```
把 stdout 翻譯成給人看的幾行（含 `LESSONS=yes/no`：Lessons Mode 開關狀態；`LESSONS_ADVISORY=<count>/<threshold>`：Lessons Mode 開著時，機制性訊號（工作區漂移不符、或
BLOCKED 輪次累積）的共用累積次數／門檻）。不要改任何檔。`NOT_STARTED` 就說還沒 `/devlog-tracker:start`。

使用者提供的額外參數：請看觸發這個 skill 的使用者訊息。
