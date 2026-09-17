# Round-Current Split（`.devlog/.round-current.md`）

Devlog SSOT 的效能修正：把「目前開著的這一輪」從 `devlog.md` 切出來，變成
一個獨立、有界的暫存檔。已實作、已合入（`round-current-split` 分支），這份
文件記錄的是實際落地的行為，不是尚未動工的規劃。

## 問題

一輪對話進行中，Claude 跟 hook 對 `devlog.md` 的讀取／雜湊次數遠不只一次：

- `round-start.sh` 開新一輪要寫 skeleton；
- Round Segments 的 Segment Watch 每次同一輪沉默超過門檻，都要求 Claude
  先 Read 整份檔案再追加一段；
- workspace-mismatch 偵測到上一輪「工作區」跟 git 不符時，也要求 Claude
  先 Read 整份檔案才能追加段落說明宣稱 vs 實際。

`devlog.md` 是整個專案的歷史累積檔，只會愈長不會變短（compact／keep 之前
不會自動搬移）。上面這些操作理論上只需要「這一輪」的內容，但因為 Claude
與 hook 都是對整份 `devlog.md` 下手（Stop hook 逐輪還要對它算一次
`cksum`），成本會隨**專案歷史的總大小**成長，不是隨**這一輪的內容量**成
長——專案跑得愈久、輪數愈多，就算這一輪本身只有幾行，光是重複讀寫這份
不斷變大的檔案就愈貴。

## 決定

切成兩個檔案：

- **`.devlog/.round-current.md`（熱、有界）**：只裝「目前開著的這一輪」
  （skeleton、段落、收尾時的 Summary／Handoff／Status），大小跟這一輪的
  內容成正比，跟專案歷史無關。這一輪進行中，Claude 該 Read／Edit 的是這
  個檔；PreToolUse（Segment Watch、workspace-mismatch 保底）與 Stop 的雜
  湊比對，也都是對這個檔算，不是對 `devlog.md`。
- **`.devlog/devlog.md`（冷、只增不減，歷史 SSOT）**：維持原本角色——逐
  輪對話紀錄的歷史真相來源。這一輪還開著的時候，`devlog.md` 完全看不到
  它；只有在這一輪收尾（正常結束或被判定中斷）之後，才會把
  `.round-current.md` 的內容併進 `devlog.md` 尾端，然後清空
  `.round-current.md`。

任何時刻，一輪的內容只會存在於兩個檔案之一，不會同時存在——即使是下面
「Reopen」段落描述的情況，也是把 `devlog.md` 裡那段整段剪下寫進
`.round-current.md`（`devlog.md` 那邊同步移除），不是複製一份。

## 併回 `devlog.md` 的時機

兩個地方會做「併回」，都是呼叫 `hooks/scripts/devlog-md.sh` 新增的
`devlog_merge_round_current(devlog, current)`（把 `current` 的內容接到
`devlog` 尾端、一行空白分隔，然後刪掉 `current`；`current` 不存在或是空
檔就整個 no-op）：

1. **`enforce-devlog.sh` 的 Stop 成功收尾。** 雜湊比對證明這一輪真的寫過
   東西之後，`enforce-devlog.sh` 對 `.round-current.md` 做完整套格式／機
   器核對（`### Summary`／`### Handoff` 存在且非空、Handoff 小節順序、
   `#### 工作區`／`#### 檔案` 機器核對……）全部通過，才呼叫
   `devlog_merge_round_current`，把 `.round-current.md` 併進 `devlog.md`
   並清空。這一步刻意放在 Checkpoint 計數檢查**之前**：如果這一輪內容裡
   本來就帶了 Claude 寫的 `## Checkpoint`，併完馬上就會被算進當次的
   checkpoint 計數，不用等下一輪才被看到。

2. **`close-open-round.sh` 判定這一輪已經結束——不管是哪一種結束方式，
   都會合併。** 這支 hook 走到底時只有兩種可能結果，**兩種都會合併**：
   - **蓋章 `INTERRUPTED`：** 這一輪真的沒收尾（`.round-open` 還在、內容
     缺 `### Summary` 或 `### Handoff`），awk 改寫 `.round-current.md`：
     補上 Summary／Handoff 的存根、把 `### Status` 蓋成 `INTERRUPTED` 並
     附一行 `[reason: ...]`（awk 回傳 0）。
   - **recovered（其實已經寫完，只是中斷訊號晚到）：** awk 偵測到
     `.round-current.md` 已經有 Summary 跟 Handoff，且內容雜湊跟
     `.turn-start` 記的不一樣（代表 Claude 在中斷訊號送達前，其實已經正
     常寫完收尾）——這時完全不改內容，直接回傳 3。
   - 呼叫端看到 `AWK_RC` 是 0 或 3 都會執行
     `devlog_merge_round_current`。不管是被蓋章成 `INTERRUPTED`，還是內
     容其實早就正常收尾、只是偵測晚了一步，都代表「這一輪已經確定結
     束」，都必須併回歷史檔——不能留下第三種「已經結束但沒併」的狀態卡
     在 `.round-current.md` 裡。

`enforce-devlog.sh` 的 Stop 一開始碰到 `.devlog/.interrupted` 時，也是先
呼叫 `close-open-round.sh`（走上面第 2 點），併完之後才判斷
`.round-current.md` 還有沒有剩下內容要驗證（只有 `close-open-round.sh`
判定是 no-op、也就是 `.round-open` 本來就不存在或已經是舊資料時，才會有
剩）——不是自己重複一套合併邏輯。

## Stop 驗證時為什麼不能整份 `cat .round-current.md`

`enforce-devlog.sh` 通過雜湊比對（證明這一輪確實寫過東西）之後，要驗證
的是「最後一個 Round」的 Summary／Handoff／Status。理論上
`.round-current.md` 本來就應該只裝這一輪、也只有這一輪，但不能直接把整
個檔案內容當成驗證範圍：

1. **Checkpoint 可能已經接在同一個檔案尾端。** Claude 收尾這一輪時，可
   能已經在 `.round-current.md` 尾端多寫了一段 `## Checkpoint`
   （Checkpoint Mode 要求的橫跨多輪摘要）——這段內容如果沒被排除，
   Summary／Handoff 的擷取範圍會被它汙染或誤判邊界。
2. **內容可能根本沒有 `## Round ` 這一行。** 例如只是一段雜訊，代表根本
   沒有 Round 可驗。

`enforce-devlog.sh` 延用了切分之前就有的、對這份內容做邊界擷取的規則，
只是把來源換成 `.round-current.md`：用 fence-aware 的 awk 找第一個不在
fence 裡的 `## Round ` 行當起點，往後找到下一個不在 fence 裡的 `## ` 行
（或檔尾）當終點，只擷取這段範圍——`## Checkpoint` 這類接在後面的區段自
然被排除在外。**完全找不到 `## Round ` 這一行時 fail-open**（擷取結果留
空，不擋這一輪，`LAST_ROUND` 判斷為空就整段跳過驗證）——這是切分之前就
存在、刻意保留的設計性質（對應舊版 `last_round_block()` 的
`if (start == 0) exit 0`），切分成 `.round-current.md` 之後這條規則原封
不動地保留，只是換了讀取的檔案，沒有被简化成一個會窄化這條規則的
plain `cat`。

## Reopen：Reply Fold 讓問答重新打開這一輪

Reply Fold（`skills/devlog-tracker/references/reply-fold.md`）讓「Claude
提問、下一則訊息才收到答案」折進同一個 Round，而不是被拆成兩個不相干的
Round。切分之後，這個機制多了一個步驟：

- **偵測邏輯不變，仍然對 `devlog.md` 比對。** `round-start.sh` 看
  `.devlog/.awaiting-reply` 記的輪次，是不是跟 `devlog.md`（用
  `devlog_list_round_starts` 取得的最後一個 `## Round`）目前最後一輪吻
  合——因為這一輪照理說已經完整收尾、已經併回 `devlog.md` 了（提問前
  Claude 已經完整寫過一次 Summary／Handoff／Status 才結束 turn），這時
  它只會存在於 `devlog.md`，不會在 `.round-current.md` 裡，所以偵測仍然
  對著 `devlog.md` 做，沒有理由換掉。
- **執行折疊之前，先把這一輪從 `devlog.md` 挖出來。** 確認輪次吻合後，
  `round-start.sh` 呼叫新增的 `devlog_reopen_last_round(devlog, current)`：
  把 `devlog.md` 最後一個 `## Round` 區塊整段剪下（從 `devlog.md` 移
  除、寫進 `.round-current.md`），然後才在 `.round-current.md` 裡插入這
  則回覆的 `### 段落`。
- **這一輪重新變成「開著的」**，後續驗證、Segment Watch、下一次收尾都跟
  一般開著的輪次完全一樣——這則回覆所在的這個 turn 結束時，
  `enforce-devlog.sh` 一樣要求 Summary／Handoff 有效才放行，通過後一樣
  把它併回 `devlog.md`。

也就是說，只有**執行折疊**（把內容搬進 `.round-current.md`、插入段落）
這個動作換了目標檔案；**判斷要不要折疊**這件事的比對對象完全沒變。這樣
設計是為了不讓「使用者隔了很久才回覆」造成資料在兩個檔案間長期不一致：
在使用者還沒回覆的這段期間（問題已經問出去、答案還沒進來），這一輪確實
已經收尾、確實完整躺在 `devlog.md` 的歷史裡，不會懸在 `.round-current.md`
裡假裝還開著；只有下一則訊息真的進來、被判定是在回答時，才會被短暫重新
打開，用完立刻又併回去。

## 沒被這個切分影響的東西

以下路徑保證只會看到已經完全併回 `devlog.md` 的內容，因為任何可能在它
們之前發生的路徑（Stop 成功、`close-open-round.sh` 的蓋章或 recovered 判
定）都已經先收尾並合併：

- `/devlog-tracker:continue`、`/devlog-tracker:resume`、
  `/devlog-tracker:compact`、`/devlog-tracker:keep`、
  `/devlog-tracker:status`
- SessionStart 的接手摘錄注入（`hooks/scripts/session-start-devlog.sh`）
- `/devlog-tracker:clean`——除了一個例外：呼叫時如果剛好有一輪開著，
  `clean-devlog.sh` 要從 `.round-current.md` 讀出這一輪的內容，重編成新
  的 `## Round 1` 寫回 `devlog.md`（其餘歷史整份清空、不留），而不是去讀
  已經被清空的 `devlog.md` 本體取得要保留的那一輪。

## 新增的 helper

`hooks/scripts/devlog-md.sh` 新增兩個函式：

- `devlog_merge_round_current(devlog, current)`：把 `current` 接到
  `devlog` 尾端（一行空白分隔）並刪除 `current`；`current` 不存在或是空
  檔就是 no-op。
- `devlog_reopen_last_round(devlog, current)`：把 `devlog` 最後一個
  `## Round` 區塊剪下寫進 `current`（建立該檔），並從 `devlog` 移除同一
  段；`devlog` 裡完全沒有 Round 可剪時回傳 1，兩個檔案都不動。

## Files

| File | 角色 |
|---|---|
| `hooks/scripts/devlog-md.sh` | 新增 `devlog_merge_round_current` / `devlog_reopen_last_round` |
| `hooks/scripts/round-start.sh` | 開新輪、Reply Fold 折疊執行都寫進 `.round-current.md`；round 編號、Reply Fold 偵測仍讀 `devlog.md` |
| `hooks/scripts/enforce-devlog.sh` | 對 `.round-current.md` 雜湊比對、fence-aware 邊界擷取驗證；成功時呼叫 `devlog_merge_round_current` |
| `hooks/scripts/close-open-round.sh` | 蓋章 `INTERRUPTED` 或判定 recovered，兩種結果都呼叫 `devlog_merge_round_current` |
| `hooks/scripts/segment-watch.sh` | 沉默偵測、PreToolUse 允許清單的目標都換成 `.round-current.md` |
| `hooks/scripts/clean-devlog.sh` | 有開著的輪次時，改讀 `.round-current.md` 取得要保留的內容 |
| `skills/devlog-tracker/SKILL.md` | 「檔案位置」新增 `.round-current.md`；強制記錄步驟、寫進 devlog 相關段落改為指向 `.round-current.md` |
| `skills/devlog-tracker/references/round-segments.md` | Segment Watch 保底段落改為 Read `.round-current.md` |
| `skills/devlog-tracker/references/reply-fold.md` | 說明折疊實際發生在 `.round-current.md`，以及 reopen 機制 |
