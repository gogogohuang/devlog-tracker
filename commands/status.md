---
description: 查看這個專案 devlog 強制記錄是否開著、span / checkpoint / 最後一輪 Status。
---

跑：
```bash
CLAUDE_PROJECT_DIR="$(pwd)" bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/status-devlog.sh"
```
把 stdout 翻譯成給人看的幾行。不要改任何檔。`NOT_STARTED` 就說還沒 `/devlog-tracker:start`。
