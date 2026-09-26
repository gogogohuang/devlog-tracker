---
name: devlog-promote
description: "從已 keep 的檔、lessons 檔與 Checkpoint 決策挑出該長期遵守的規範，你選定後寫進 CLAUDE.md 或 AGENTS.md 的 devlog-tracker 規範區塊。"
---

Codex plugin 安裝：目前這份 `SKILL.md` 的絕對路徑位於
`<plugin 根目錄>/codex/skills/<skill 名稱>/SKILL.md`。每次用 shell 執行下方步驟時，
先從這份檔案的所在目錄往上三層取得 plugin 根目錄，並在同一次 shell 呼叫中
`export DEVLOG_TRACKER_ROOT="<該根目錄的絕對路徑>"`。
一般 shell 呼叫不一定有 hook 專用的 `PLUGIN_ROOT`／`CLAUDE_PLUGIN_ROOT` 環境變數。
若是 npx 安裝，沿用專案內既有的 `DEVLOG_TRACKER_ROOT`。

這是使用者主動執行 `/devlog-tracker:promote` 時才做的事。**沒有使用者明確選擇就不寫入任何檔案。**

## 1. 取得來源與目標

記下你目前已經確認的專案根目錄絕對路徑（後面步驟都要用這個值，不要用 `$(pwd)` 重新推——理由同 `commands/continue.md` 步驟 1）。先決定 plugin 根目錄（有 `DEVLOG_TRACKER_ROOT` 用它；否則用 `CLAUDE_PLUGIN_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄），再跑：

```bash
PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
DEVLOG_PROJECT_DIR="<專案根目錄絕對路徑>" bash "${PLUGIN_ROOT}/core/scripts/promote-sources.sh"
DEVLOG_PROJECT_DIR="<專案根目錄絕對路徑>" bash "${PLUGIN_ROOT}/core/scripts/promote-target.sh"
```

- `NO_SOURCES`：告知目前沒有可以沉澱的來源（還沒 keep 過、沒有 lessons、也沒有 Checkpoint），可以先用 `/devlog-tracker:keep` 或開 Lessons Mode；結束。
- `FILE=<路徑> KIND=kept|lessons EXISTS=1`：要讀的檔。`EXISTS=0` 是索引還在但檔案已被刪掉，跳過，最後提一句。
- `CHECKPOINT=<檔案>:<行號>`：從該行的 `## Checkpoint` 標題往下讀到下一個 `## ` 標題為止，只看其中 `### 決策` 小節。
- `TARGET=<路徑>`：規則要寫進的檔。`EXISTING=<n>` 表示這個檔已經有 n 條沉澱過的規則。

## 2. 挑候選

用 Read 讀 `EXISTS=1` 的檔案、每個 Checkpoint 的 `### 決策`，以及 `TARGET` 檔（存在的話，看它整份內容，含 `<!-- devlog-tracker:rules:begin -->` 區塊內既有規則）。

挑出讀起來像「規則、之後應該一直遵守」的內容：

- 要：跨任務都成立的約定、踩過坑後定下的做法、明確的「不要做 X」。
- 不要：單次任務細節、已經被後續內容推翻或取代的決定、`TARGET` 檔裡已經寫了（不論在不在規範區塊裡）意思相同的規則。

**不要把 `### User Input` 原文寫成規則候選**——kept 檔保留完整 Round，內容是單次任務的原文，不是沉澱過的規範。

每條候選寫成一行、可以直接放進 CLAUDE.md 的條列句，必要時附一句原因，結尾標出處：`（來源：<檔名>「<標題>」）`。找不到夠格的就說沒有，不硬湊。

在對話裡列出編號清單，並說明會寫進哪個檔（`TARGET`）。

## 3. 等使用者選

**停下來。** 請使用者回覆要寫入的編號（例如 `1,3`），也可以要求改寫某條。使用者沒有明確選擇（例如只說「看起來不錯」）時，再問一次要哪幾條；不要自己決定全寫。

## 4. 寫入

1. 用 Write 把選定（改寫過就用改寫版）的規則寫到 `<專案根目錄>/.devlog/.promote-rules.tmp`，一行一條。
2. 跑（這是新的一個 Bash call，`PLUGIN_ROOT` 要重新設一次——理由同步驟 1）：

   ```bash
   PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
   DEVLOG_PROJECT_DIR="<專案根目錄絕對路徑>" bash "${PLUGIN_ROOT}/core/scripts/promote-write.sh" "<TARGET>" "<專案根目錄>/.devlog/.promote-rules.tmp" \
     && rm -f "<專案根目錄>/.devlog/.promote-rules.tmp"
   ```

3. 依輸出 `ADDED=<n> SKIPPED_DUP=<m> TARGET=<路徑>` 回報：寫入了幾條、幾條因為一字不差已存在而跳過、寫到哪個檔。提醒使用者這個檔要不要 commit 由他決定。

規範區塊只會被追加；要修改或刪除已寫入的規則，請使用者直接編輯該檔。`npx devlog-tracker init` 不會動這個區塊。

使用者提供的額外參數：請看觸發這個 skill 的使用者訊息。
