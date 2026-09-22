# Lessons Mode：開發歷程教訓（預設關閉，非架構知識庫）

`docs/design/lessons-mode.md` 的完整設計。這裡只講操作規則。

跟 Checkpoint／Span 不同，Lessons Mode 管的是「開發**過程**踩過的坑」，不是進度或架構——
架構/設計決策的 SSOT 永遠是 `docs/design/*.md`，這個模式不取代它。**預設關閉**，隸屬主開關：
`/devlog-tracker:lessons-on` 若沒下過 `/devlog-tracker:start`（`.enabled` 不存在）會直接拒絕，
因為沒有 Round/Status 歷史可判斷「BLOCKED→解開」這個訊號。`/devlog-tracker:lessons-off` 只刪
`.lessons-enabled`，不動任何已寫的 `devlog.lessons.*.md` 或索引。

**兩種自我判斷訊號**（hook 判斷不到，完全仰賴你自己在 Round 收尾前想起來）：這一輪的
`### Status` 從 `BLOCKED` 變成別的值，或你自行判斷這輪明顯繞了一圈才找到對的做法。

**兩種機制性訊號**（`round-start.sh` 在下一輪開始時累積計數，`.devlog/.lessons-advisory-state`
的 `count`/`threshold`，預設門檻 3、`/devlog-tracker:lessons-drift <次數>` 可調，兩種共用同一個
計數器/門檻，達門檻印一句 `[Lessons Mode 提示]` 後歸零）：工作區漂移（宣稱跟實際不符）累積
出現，或上一輪 `### Status` 是 `BLOCKED` 累積出現。另外「上一輪從 `BLOCKED` 解開」這個轉變，
下一輪開始時 hook 會**額外**機械印一句提示——這個不經過門檻計數，偵測到就印一次（因為它本身
就是一次性事件，不是可以累積的次數）。

以上四種**完全不 hook 強制寫入本身**——寫不寫都不影響這一輪能不能收尾，跟「`#### 決策`
沒有就整節省略」同一種精神，不要自己加壓力覺得每輪都要交一份。

**寫法**：跑（`PLUGIN_ROOT` 同其他指令）：

```bash
DEVLOG_PROJECT_DIR="$(pwd)" bash "${PLUGIN_ROOT}/core/scripts/lessons-append.sh" \
  --topic "<主題 kebab-case slug，跟 keep 的 <name> 同一套正規化規則>" \
  --text "<自由散文，一段就好：卡在哪、怎麼解開、下次怎麼避免>"
```

同一個主題重複呼叫會累加進同一個 `devlog.lessons.<topic>.md`；不同主題各自成檔。內容不用固定
子欄位，跟 `#### 決策` 一樣是敘事性的，不要硬套模板。腳本會自動重建 `devlog.md` 尾端的
`## Lessons 索引`（每個主題檔一行：則數、最新一則的標題、更新時間），SessionStart 只注入這個
索引，不會注入任何 `devlog.lessons.*.md` 的全文。要看全文用 `/devlog-tracker:lessons [<topic>]`
（沒給 topic 就只印索引）——這是純讀取，不像 `resume` 會核對工作區或等使用者確認才動手。

腳本輸出除了 `PATH=...` 之外，可能多印兩種提示，都是純資訊性、不阻擋：
- 同一主題累積滿 3 則的倍數時，印一句建議升級成 `docs/design/*.md` 正式決策；
- 建立**全新**主題檔時（這個 topic 之前不存在），若已有其他主題檔，印一行既有主題清單
  （`NEW_TOPIC。既有主題：...`）——如果內容其實屬於某個既有主題，改用該名稱重跑，避免
  同一件事分裂成兩個檔案。

## sub agent／workflow 情境

上面兩種自我判斷訊號預設你在跑 Round。改由 Agent 工具的 sub agent 或 Workflow 工具執行時，
沒有 Round／Status 可比，但一樣可能踩坑，判斷方式類比如下（一樣完全自我判斷，非強制）：
verify 階段推翻了 sub agent 先前的 fix／claim、sub agent 自陳繞了一圈、同一個 workflow
裡多個 agent 各自卡在類似問題（彙整成一筆更有代表性的）、sub agent 的成果被使用者或
reviewer 打回票要求重做。

sub agent 不需要知道 Lessons Mode 存在；不新增回報格式，你覺得這次任務可能踩雷時，自己
決定要不要在 dispatch prompt 裡順口提一句「回報時順便說一下有沒有繞路」。永遠是你（主
session）讀完回報後自己判斷主題、呼叫 `lessons-append.sh`——sub agent／workflow 本身不
直接呼叫，避免 worktree isolation 下環境變數指錯專案目錄。詳見
`docs/design/lessons-mode.md`「sub agent／workflow 情境的自我判斷訊號」。
