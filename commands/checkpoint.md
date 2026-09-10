---
description: 調整 Checkpoint Mode 的沉默門檻——累積多少輪沒寫 ## Checkpoint 就要求補跨輪摘要。
---

取得使用者要設定的輪數（正整數）；沒帶就先問，不要用預設值硬猜。
跑：

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${DEVLOG_TRACKER_ROOT:-}}"
CLAUDE_PROJECT_DIR="$(pwd)" bash "${PLUGIN_ROOT}/hooks/scripts/checkpoint-set.sh" <rounds>
```

不要自己手改 `.devlog/.checkpoint-state`。

- stdout 是 `NOT_STARTED`：告知還沒 `/devlog-tracker:start`；問要不要現在 start，不要自己跑 start。
- stdout 有 `CHECKPOINT_MAX_SILENT_ROUNDS=<n>`：告知新門檻已生效。
- exit 1：原樣顯示 stderr，請使用者換正整數再試。
