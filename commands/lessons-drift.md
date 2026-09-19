---
description: 調整 Lessons Mode「工作區漂移重複發生」機制性提醒的門檻——累積幾次工作區不符才印一次建議。
---

取得使用者要設定的次數（正整數）；沒帶就先問，不要用預設值硬猜。跑：

```bash
PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
DEVLOG_PROJECT_DIR="$(pwd)" bash "${PLUGIN_ROOT}/core/scripts/lessons-drift-set.sh" <次數>
```

不要自己手改 `.devlog/.lessons-drift-state`。

- stdout 是 `NOT_STARTED`：告知這個專案還沒 `/devlog-tracker:start`，問要不要現在
  `/devlog-tracker:start`，不要自己跑 start。
- stdout 是 `LESSONS_NOT_ENABLED`：告知這個門檻隸屬 Lessons Mode，請先
  `/devlog-tracker:lessons-on`，不要自己跑 lessons-on。
- stdout 有 `LESSONS_DRIFT_THRESHOLD=<n>`：告知新門檻已生效。
- exit 1：原樣顯示 stderr，請使用者換正整數再試，不要自己編數字硬跑。
