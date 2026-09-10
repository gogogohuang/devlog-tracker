---
description: 掃描整份 devlog.md，把值得留名的主題段落一次分別搬成 devlog.<name>.md；也可只抽出一段或合併成全部歷史一個檔
---

請執行 devlog keep（具名搬走）。這是使用者主動執行 `/devlog-tracker:keep` 時才做的事，不要自動觸發。

確認之前不要寫任何檔。若這一輪本身是開著的 Round，永遠不要把它搬走，這一輪結束前仍要補 `### Summary` / `### Handoff` / `### Status`（若沒有開著的 Round，見步驟 1 第 2 點）。

## 1. 讀檔、找出開著的 Round

1. 讀取 `.devlog/devlog.md` 全文。若檔案不存在，告知「目前沒有東西可 keep」，不要建立 `.devlog/` 或任何新檔，結束。
2. 開著的 Round：若 `.devlog/.round-open` 存在且有 `"round"` 數字，用那個編號。若 `.round-open` 不存在（從未 start 或已 pause），表示沒有開著的 Round，檔案裡所有 `## Round` 都是歷史，不要把最後一個 Round 當成開著的 Round 來排除。
3. 歷史 Round = 檔案裡除了開著的 Round 以外的所有 `## Round`（判斷 `## ` 標題時，略過圍欄程式碼區塊 ``` 內的行，與 hook 腳本解析方式一致）。若沒有任何歷史 Round，告知「目前沒有東西可 keep」，不要建立新檔，結束。

## 2. 切出主題段落，過濾瑣碎段落

1. 依各輪 `### User Input` 與 `### Summary` 的主題變化，把**全部**歷史 Round（不含開著的 Round）切成連續、不重疊、涵蓋所有歷史 Round 的候選段落，由舊到新排列，不要留空隙。如果同一個主題橫跨了 Round 編號的缺口（例如先前 keep 或 compact 已經搬走中間的 Round，留下不連續的編號），在缺口處切成兩段：每一段的 `from`–`to` 之間必須都是實際存在的歷史 Round，不能有缺號（腳本會嚴格比對數量，缺號的段落會直接失敗）。
2. 用 skills/devlog-tracker 判斷瑣碎程度的同一套訊號，評估每一個候選段落：有檔案異動、有影響後續的決策、有未完成工作、刪掉會接續不上 → 值得留名，列為候選；只有確認、閒聊、重複 → 偏低，直接丟掉，不列入建議清單，繼續留在 `devlog.md`，不用再嘗試併進相鄰段落。段落裡有未收尾的 `IN_PROGRESS` / `BLOCKED` / `INTERRUPTED` Round 可以正常納入候選段落，不要僅因為未收尾就拒絕或把它排除到段落外。
3. 若一個候選段落都沒有，告知「目前沒有值得分主題留名的段落」，不要建立新檔，結束。
4. 對每個候選段落，用**那一段的內容**（不是留下的 Round）產生建議 `<name>`：小寫 ASCII kebab-case，2–4 段，只反映主題。不要加日期、不要加 `round-12-18`。例如 `span-mode`、`keep-plan`。這一批裡若兩段的建議 `<name>` 相同，比照步驟 4 的撞名規則先加上 `-2`/`-3` 分開，再一起列出：Round 編號較小（較早）的段落保留原建議名稱，較晚的段落加 `-2`/`-3`。

## 3. 一次列出全部候選段落，然後停下來等

用這一則訊息列出所有候選段落（不要分開一段一段問）：

```
掃到 N 段值得留名：
  1. Round <from>–<to>　<一句這段在做什麼>　→ devlog.<name>.md
  2. Round <from>–<to>　<一句這段在做什麼>　→ devlog.<name>.md
  ...
其餘 Round（<留下的範圍，可能不只一段、逗號分隔，或「無」>）偏瑣碎，留在 devlog.md。

回覆：
  採用 → 全部照上面寫入
  改第 N 段範圍 <from>-<to> / 改第 N 段檔名 <name> / 移除第 N 段
  全部歷史合併成一個檔 <name> → 放棄分段，整份歷史存成一檔
  取消
```

同一則回覆可以合併多條修改，例如「改第 2 段檔名 foo，移除第 3 段」。`N` 一律對應上面列出的原始編號，修改不會讓其他段落重新編號。

然後停止。使用者還沒回覆前不要寫任何檔。

- 取消，或套用修改後一段都不剩 → 不改檔，結束。
- 「全部歷史合併成一個檔 `<name>`」→ 放棄前面列出的分段，改成單一段：`from` = 最早的歷史 Round、`to` = 最晚的歷史 Round（仍不含開著的 Round），`<name>` 用使用者這裡給的名稱。之後只處理這一段，跳過步驟 4 的「重疊」與「批次撞名」檢查（只有一段）。
- 其他回覆（採用 / 各種修改組合）→ 帶著套用修改後的段落清單，進入步驟 4。

## 4. 驗證每一段的範圍與檔名（不通過就再問一次，仍不寫檔）

**範圍**

- 每一段的 `from`–`to` 必須連續、含端點、屬於歷史 Round，且不得包含開著的 Round。
- 這一批裡任兩段的範圍不可重疊。
- `from` > `to`、`from`–`to` 之間有任一整數不是實際存在的歷史 Round（例如中間被先前的 keep 或 compact 搬走過，留下缺號）、範圍含開著的 Round、或跟同批另一段重疊 → 說明原因，請使用者改，不要寫檔。範圍內有未收尾的 `IN_PROGRESS` / `BLOCKED` / `INTERRUPTED` Round 不算拒絕理由，可以正常納入。

**`<name>` 正規化**（逐段套用）

使用者給的字串依序處理：若以 `devlog.` 開頭先剝掉；若以 `.md` 結尾再剝掉。因此 `foo`、`devlog.foo`、`devlog.foo.md` 都是 `foo`。空白改成 `-`；連續 `-` 收成一個；去掉頭尾的 `-`。

拒絕（再問、不寫檔）：

- 結果是空的，或路徑會變成 `.devlog/devlog.md`
- 結果是 `archive`（那是 compact 的 `devlog.archive.md`）
- 含 `/`、`\` 或 `..`
- 長度超過 64 個字元

使用者自訂可以用非 ASCII，只要通過上面的檢查。Claude 的第一個建議仍必須是 ASCII kebab-case。

**撞名**

目標 `.devlog/devlog.<name>.md` 已存在，或跟同一批裡另一段最終確認的檔名相同 → 不要覆寫，也不要讓兩段寫進同一個檔。改建議 `devlog.<name>-2.md`（已存在就 `-3`，依此加），等使用者確認或另取名。

## 5. 依序跑搬移腳本（每段各跑一次，由舊到新）

把步驟 4 驗證通過的段落，依 `from` 由小到大排序。對每一段依序跑（一段一次，不要自己搬檔，也不要一次塞多段給腳本）：

先決定 plugin 根目錄（有 `CLAUDE_PLUGIN_ROOT` 用它；否則用 `DEVLOG_TRACKER_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄）：

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${DEVLOG_TRACKER_ROOT:-}}"
CLAUDE_PROJECT_DIR="$(pwd)" bash "${PLUGIN_ROOT}/hooks/scripts/keep-move.sh" \
  --from <from> --to <to> --name "<name>"
```

`<from>`、`<to>`、`<name>` 必須使用該段步驟 4 確認後的值。腳本是搬移、Checkpoint 歸屬、full keep 重編與 checkpoint counter reset 的唯一實作來源；它一次只認一段範圍，完全不知道這是批次的一部分，`commands/keep.md` 自己負責依序呼叫。

任一段的腳本 exit 1：立刻停止整批，原樣顯示那一段的 stderr，不要自行重試刪除，也不要手動補做搬移，也不要繼續跑後面還沒處理的段落。已經成功搬走的段落不要回滾。

如果這批段落最終涵蓋了 `devlog.md` 目前剩下的所有歷史 Round（沒有瑣碎段落留下），跑到最後一段（Round 號碼最新的那一段）時，腳本會自動判定為 full keep：專案摘要併入那一檔、開著的 Round 重編號成 1、`.span-open` 刪除、checkpoint counter 歸零。這是預期行為，不用特別處理，也不用另外判斷「這是不是 full keep」。

## 6. 處理腳本結果

每段成功時記下 stdout 給的具名檔路徑、`ROUNDS=<from>-<to>` 與 `REMAINING=<int>`，等這批全部段落都跑完（或某段失敗中止）後，一次在步驟 7 回報。

## 7. 回報並收尾這一輪

依段落回報：每個具名檔路徑、搬走幾輪（哪些編號）；再依最後一次成功執行的 `REMAINING` 回報 `devlog.md` 目前剩幾輪（這個數字含還開著的那一輪，不是只算歷史 Round）。若中途因某段腳本失敗而中止，清楚列出哪些段落已經搬走（連檔名）、哪些完全沒嘗試。不要讀寫 `devlog.archive.md`。

若 `.round-open` 存在：在開著的那一輪補上 `### Summary` / `### Handoff` / `### Status` 再結束（Stop hook 仍會檢查）。若沒有開著的 Round：不要改寫歷史 Round 的收尾。
