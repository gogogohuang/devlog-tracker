---
description: 把已 keep 的具名檔（devlog.<name>.md）整合成一份跨主題總覽，並列出看起來該進 CLAUDE.md 的規範候選。純讀取，不核對工作區、不等確認。
---

請執行 devlog overview（已 keep 舊檔總覽）。這是使用者主動執行 `/devlog-tracker:overview` 時才做的事。

這是純讀取，不做 `commands/continue.md`／`commands/resume.md` 那套「核對工作區、等確認才動手」流程——已 keep 的檔案是參考資料，不是暫停中的工作主題。讀完之後不要自動據此修改任何檔案（包含 `CLAUDE.md`），除非使用者接著明確要求。

## 1. 取得已 keep 的檔案清單

記下你目前已經確認的專案根目錄絕對路徑（後面步驟都要用這個值，不要用 `$(pwd)` 重新推——理由同 `commands/continue.md` 步驟 1）。先決定 plugin 根目錄（有 `DEVLOG_TRACKER_ROOT` 用它；否則用 `CLAUDE_PLUGIN_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄），再跑：

```bash
PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
DEVLOG_PROJECT_DIR="<剛才記下的專案根目錄絕對路徑>" bash "${PLUGIN_ROOT}/core/scripts/kept-list.sh"
```

- `NO_INDEX`：告知「目前沒有已 keep 的舊檔」，結束。
- 其他輸出：每行一個 `FILE=<絕對路徑> EXISTS=1` 或 `EXISTS=0`。`EXISTS=0` 是索引裡還留著、但檔案已被手動刪掉的 ghost row，不要嘗試讀它，記下檔名等步驟 3 一併提一句；`EXISTS=1` 才要讀。

若 `EXISTS=1` 的檔案一個都沒有（清單全是 ghost row），告知「已 keep 的舊檔都不存在了」，列出這些 ghost 檔名，結束。

## 2. 讀取內容，整合總覽

用 Read 讀取每個 `EXISTS=1` 的檔案全文。讀完後在對話裡輸出兩塊，不寫入任何檔案：

1. **跨主題總覽**：依主題（不是依檔案機械條列）概述做了什麼、關鍵決定、還沒收尾或之後可能要接續的事。同一主題如果分散在多個檔案，合併描述，不用一檔一段硬切。
2. **可能該進 CLAUDE.md 的規範**：從內容裡挑出讀起來像「規則、決定、之後應該一直遵守」的部分（不是單次任務細節、不是已經過時或被後續內容取代的決定）。格式盡量貼近 CLAUDE.md 條列寫法（一行一條規則，必要時附一句原因），方便使用者直接複製貼上。找不到夠格的候選就不要輸出這一節、也不要硬湊。

## 3. 收尾

若步驟 1 有 ghost row，在總覽最後補一句列出哪些 `devlog.<name>.md` 已經在索引裡但磁碟上找不到（不用建議刪索引行或做任何修復，這是已知限制，見 `docs/design/keep.md` Kept index）。
