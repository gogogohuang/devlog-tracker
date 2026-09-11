---
description: 查看 Lessons 索引，或讀某個主題的完整教訓紀錄（純讀取，不核對工作區、不等確認）。
---

取得使用者是否有給 `<topic>`（可能沒有，代表只看索引）。記下你目前已經確認的專案根目錄絕對路徑（後面步驟都要用這個值，不要用 `$(pwd)` 重新推——理由同 `commands/continue.md` 步驟 1）。先決定 plugin 根目錄（有 `CLAUDE_PLUGIN_ROOT` 用它；否則用 `DEVLOG_TRACKER_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄），再跑：

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${DEVLOG_TRACKER_ROOT:-}}"
CLAUDE_PROJECT_DIR="<剛才記下的專案根目錄絕對路徑>" bash "${PLUGIN_ROOT}/hooks/scripts/lessons-read.sh" "<topic，沒有就留空>"
```

沒有 `<topic>`：
- `NO_INDEX`：告知目前沒有任何 lessons 紀錄，結束。
- 其他輸出：就是目前的 `## Lessons 索引` 內容（每個主題檔一行：則數、最新一則標題、更新時間），原樣顯示給使用者，不用額外解讀或摘要。

有 `<topic>`：
- 回傳 `MISSING`：列出 `CANDIDATES`（若有）讓使用者選別的主題名稱，不要自己猜一個相近的名字硬讀。
- 其他輸出：第一行 `PATH=...` 之後是該主題檔的完整內容（所有歷史條目，由舊到新），原樣顯示給使用者。

這是純讀取，不做 `commands/continue.md`／`commands/resume.md` 那套「核對工作區、等確認才動手」流程——lessons 是參考資料，不是暫停中的工作主題。讀完之後不要自動據此修改任何檔案，除非使用者接著明確要求。
