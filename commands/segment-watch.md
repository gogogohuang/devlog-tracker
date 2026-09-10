---
description: 調整 Segment Watch 的沉默門檻——同一輪連續多久沒改 devlog.md 就要求先補一段 ### 段落。
---

取得使用者要設定的時間長度（例如「10 分鐘」「5min」「300 秒」）；沒帶就先問，不要用預設值硬猜。
換算成整數秒數 `<seconds>`，跑：

```bash
CLAUDE_PROJECT_DIR="$(pwd)" bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/segment-watch-set.sh" <seconds>
```

不要自己手改 `.devlog/.segment-state`。

- stdout 是 `NOT_STARTED`：告知這個專案還沒 `/devlog-tracker:start`，門檻設定只在啟動後才有意義；問要不要現在 `/devlog-tracker:start`，不要自己跑 start。
- stdout 有 `SEGMENT_MAX_SILENT_SECONDS=<n>`：告知使用者新門檻已生效（換算回分鐘講會更好懂）。
- exit 1（例如帶了非正整數）：原樣顯示 stderr，請使用者換一個時間長度再試，不要自己編秒數硬跑。
