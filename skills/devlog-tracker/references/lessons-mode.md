# Lessons Mode：開發歷程教訓（預設關閉，非架構知識庫）

`docs/design/lessons-mode.md` 的完整設計。這裡只講操作規則。

跟 Checkpoint／Span 不同，Lessons Mode 管的是「開發**過程**踩過的坑」，不是進度或架構——
架構/設計決策的 SSOT 永遠是 `docs/design/*.md`，這個模式不取代它。**預設關閉**，隸屬主開關：
`/devlog-tracker:lessons-on` 若沒下過 `/devlog-tracker:start`（`.enabled` 不存在）會直接拒絕，
因為沒有 Round/Status 歷史可判斷「BLOCKED→解開」這個訊號。`/devlog-tracker:lessons-off` 只刪
`.lessons-enabled`，不動任何已寫的 `devlog.lessons.*.md` 或索引。

**開著的時候，只有兩種訊號會讓你考慮記一筆**：這一輪的 `### Status` 從 `BLOCKED` 變成別的值
（機器可判斷，但不因此強制），或你自行判斷這輪明顯繞了一圈才找到對的做法。**完全不 hook
強制**——寫不寫都不影響這一輪能不能收尾，跟「`#### 決策` 沒有就整節省略」同一種精神，不要
自己加壓力覺得每輪都要交一份。

**寫法**：跑（`PLUGIN_ROOT` 同其他指令）：

```bash
CLAUDE_PROJECT_DIR="$(pwd)" bash "${PLUGIN_ROOT}/hooks/scripts/lessons-append.sh" \
  --topic "<主題 kebab-case slug，跟 keep 的 <name> 同一套正規化規則>" \
  --text "<自由散文，一段就好：卡在哪、怎麼解開、下次怎麼避免>"
```

同一個主題重複呼叫會累加進同一個 `devlog.lessons.<topic>.md`；不同主題各自成檔。內容不用固定
子欄位，跟 `#### 決策` 一樣是敘事性的，不要硬套模板。腳本會自動重建 `devlog.md` 尾端的
`## Lessons 索引`（每個主題檔一行：則數、最新一則的標題、更新時間），SessionStart 只注入這個
索引，不會注入任何 `devlog.lessons.*.md` 的全文。要看全文用 `/devlog-tracker:lessons [<topic>]`
（沒給 topic 就只印索引）——這是純讀取，不像 `resume` 會核對工作區或等使用者確認才動手。
