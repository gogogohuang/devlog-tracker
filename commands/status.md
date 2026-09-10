---
description: 查看這個專案 devlog 強制記錄是否開著、span / checkpoint / 最後一輪 Status。
---

跑：
```bash
先決定 plugin 根目錄（有 `CLAUDE_PLUGIN_ROOT` 用它；否則用 `DEVLOG_TRACKER_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄）：

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${DEVLOG_TRACKER_ROOT:-}}"
CLAUDE_PROJECT_DIR="$(pwd)" bash "${PLUGIN_ROOT}/hooks/scripts/status-devlog.sh"
```
```
把 stdout 翻譯成給人看的幾行。不要改任何檔。`NOT_STARTED` 就說還沒 `/devlog-tracker:start`。
