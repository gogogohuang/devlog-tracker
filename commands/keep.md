---
description: 若這段 devlog 值得單獨留名，把它從 devlog.md 搬走成 devlog.<name>.md；可抽出一段或全部歷史
---

請執行 devlog keep（具名搬走）。這是使用者主動執行 `/devlog-tracker:keep` 時才做的事，不要自動觸發。

確認之前不要寫任何檔。這一輪本身是開著的 Round，永遠不要把它搬走；這一輪結束前仍要補 `### Summary` / `### Handoff` / `### Status`。

## 1. 讀檔、找出開著的 Round

1. 讀取 `.devlog/devlog.md` 全文。若檔案不存在，告知「目前沒有東西可 keep」，不要建立 `.devlog/` 或任何新檔，結束。
2. 開著的 Round：若 `.devlog/.round-open` 存在且有 `"round"` 數字，用那個編號。若 `.round-open` 不存在（從未 start 或已 pause），表示沒有開著的 Round，檔案裡所有 `## Round` 都是歷史，不要把最後一個 Round 當成開著的 Round 來排除。
3. 歷史 Round = 檔案裡除了開著的 Round 以外的所有 `## Round`（判斷 `## ` 標題時，略過圍欄程式碼區塊 ``` 內的行，與 hook 腳本解析方式一致）。若沒有任何歷史 Round，告知「目前沒有東西可 keep」，不要建立新檔，結束。

## 2. 建議範圍與價值

1. 範圍必須是連續、含端點的 `from`–`to`，且不得包含開著的 Round。歷史裡未收尾的 `IN_PROGRESS` / `BLOCKED` / `INTERRUPTED` 可以納入，不要因此拒絕。
2. 依各輪 `### User Input` 與 `### Summary` 的主題變化，建議「現在這題」的最新一段。只有整份歷史都在講同一件事時，才建議全部歷史（仍不含開著的 Round）。
3. 用 skills/devlog-tracker 判斷瑣碎程度的同一套訊號，評估**建議搬走的那段**：有檔案異動、有影響後續的決策、有未完成工作、刪掉會接續不上 → 值得留名；只有確認、閒聊、重複 → 偏低。
4. 用即將搬走的那段（不是留下的 Round）產出建議 `<name>`：小寫 ASCII kebab-case，2–4 段，只反映主題。不要加日期、不要加 `round-12-18`。例如 `span-mode`、`summary-handoff`。

## 3. 一次問清，然後停下來等

用這一則訊息問（偏低時第一句改成「建議先不要 keep」加一句理由，後面欄位仍要給）：

```
價值：值得留名 / 偏低（<一句理由>）
建議範圍：Round <from>–<to>（<一句這段在做什麼>）。也可改成全部歷史。
建議檔名：`.devlog/devlog.<name>.md`
請回覆：採用 / 改範圍 <from>-<to> / 改檔名 <name> / 全部歷史 / 取消
偏低且仍要存時，回覆「仍要存」即可。
```

然後停止。使用者還沒回覆前不要寫檔。

- 取消，或價值偏低且沒有明確「仍要存」／採用 → 不改檔，結束。
- 採用 / 改範圍 / 改檔名 / 全部歷史 / 仍要存 → 進入步驟 4。

## 4. 驗證範圍與檔名（不通過就再問一次，仍不寫檔）

**範圍**

- 「全部歷史」= 每一個歷史 Round，仍不含開著的 Round。
- `from` > `to`、輪次不存在於檔案、範圍含開著的 Round、或要求不連續的輪次 → 說明原因，請使用者改，不要寫檔。

**`<name>` 正規化**

使用者給的字串依序處理：若以 `devlog.` 開頭先剝掉；若以 `.md` 結尾再剝掉。因此 `foo`、`devlog.foo`、`devlog.foo.md` 都是 `foo`。空白改成 `-`；連續 `-` 收成一個；去掉頭尾的 `-`。

拒絕（再問、不寫檔）：

- 結果是空的，或路徑會變成 `.devlog/devlog.md`
- 結果是 `archive`（那是 compact 的 `devlog.archive.md`）
- 含 `/`、`\` 或 `..`
- 長度超過 64 個字元

使用者自訂可以用非 ASCII，只要通過上面的檢查。Claude 的第一個建議仍必須是 ASCII kebab-case。

**撞名**

目標 `.devlog/devlog.<name>.md` 已存在 → 不要覆寫。改建議 `devlog.<name>-2.md`（已存在就 `-3`，依此加），等使用者確認或另取名。

## 5. 跑搬移腳本

使用者確認範圍與檔名後，跑（不要自己搬檔）：

```bash
CLAUDE_PROJECT_DIR="$(pwd)" bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/keep-move.sh" \
  --from <from> --to <to> --name "<name>"
```

`<from>`、`<to>`、`<name>` 必須使用步驟 4 確認後的值。腳本是搬移、
Checkpoint 歸屬、full keep 重編與 checkpoint counter reset 的唯一實作來源。

## 6. 處理腳本結果

成功時依 stdout 回報具名檔與輪次統計。腳本 exit 1 時，原樣顯示 stderr，
不要自行重試刪除，也不要手動補做搬移。

## 7. 回報並收尾這一輪

回報：具名檔路徑、搬走幾輪（哪些編號）、主檔目前剩幾輪。不要讀寫 `devlog.archive.md`。

若 `.round-open` 存在：在開著的那一輪補上 `### Summary` / `### Handoff` / `### Status` 再結束（Stop hook 仍會檢查）。若沒有開著的 Round：不要改寫歷史 Round 的收尾。
