---
name: devlog-checkpoint
description: "調整 Checkpoint Mode 的沉默門檻——累積多少輪沒寫 ## Checkpoint 就要求補跨輪摘要。"
---

Codex plugin 安裝：目前這份 `SKILL.md` 的絕對路徑位於
`<plugin 根目錄>/codex/skills/<skill 名稱>/SKILL.md`。每次用 shell 執行下方步驟時，
先從這份檔案的所在目錄往上三層取得 plugin 根目錄，並在同一次 shell 呼叫中
`export DEVLOG_TRACKER_ROOT="<該根目錄的絕對路徑>"`。
一般 shell 呼叫不一定有 hook 專用的 `PLUGIN_ROOT`／`CLAUDE_PLUGIN_ROOT` 環境變數。
若是 npx 安裝，沿用專案內既有的 `DEVLOG_TRACKER_ROOT`。

取得使用者要設定的輪數（正整數）；沒帶就先問，不要用預設值硬猜。
跑：

```bash
PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
DEVLOG_PROJECT_DIR="<專案根目錄絕對路徑，不要用 $(pwd) 重新推>" bash "${PLUGIN_ROOT}/core/scripts/checkpoint-set.sh" <rounds>
```

不要自己手改 `.devlog/.checkpoint-state`。

- stdout 是 `NOT_STARTED`：告知還沒 `/devlog-tracker:start`；問要不要現在 start，不要自己跑 start。
- stdout 有 `CHECKPOINT_MAX_SILENT_ROUNDS=<n>`：告知新門檻已生效。
- exit 1：原樣顯示 stderr，請使用者換正整數再試。

使用者提供的額外參數：請看觸發這個 skill 的使用者訊息。
