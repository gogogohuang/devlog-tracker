# Checkpoint Mode：定期摘要

跟 Span Mode 處理的是不同問題：Span Mode 管的是「一輪內部/自動續接期間要不要
強制寫」，Checkpoint Mode 管的是「累積夠多輪之後，要不要在 devlog.md 裡插入一段
橫跨多輪的摘要」，讓翻閱 devlog.md 的人不用逐輪爬完才知道整體進度。

設計動機見 `docs/design/checkpoint-mode.md`；這裡只講操作規則。

## 怎麼運作（不用手動開關）

`/devlog-tracker:start` 會自動建立 `.devlog/.checkpoint-state`，之後全程自動：

- 每個互動輪次，`round-start.sh` 把裡面的 `rounds_since_checkpoint` +1
  （Span Mode 的 span 開著、這個 tick 會被安靜放行時不算）
- `enforce-devlog.sh` 每輪檢查一次：如果 `devlog.md` 裡 `## Checkpoint` 開頭的
  標題數量比上次看到的多，代表這輪寫了新的 checkpoint，自動把計數器歸零；
  否則如果 `rounds_since_checkpoint` 已經到 `max_silent_rounds`（預設 20），
  就擋下這一輪，要求補寫一段摘要

## 被要求補寫的時候該怎麼寫

在 `devlog.md` 尾端追加：

```markdown
## Checkpoint（Round <X>-<Y> 摘要）
這段期間完成了...、修了...、決定採用...
```

`X`-`Y` 是這段還沒被摘要過的 Round 範圍，內容對齊各輪 Summary 抓重點就好，不用逐輪複述、
也不要變成各輪 Handoff 的合集——細節本來就還留在 Round 區塊裡，checkpoint 只是給翻閱時的路標，
不替代每輪 Summary。寫完之後這一輪就會正常結束，不用再做任何事。

## 調整門檻

`max_silent_rounds` 預設 20，覺得這個專案的節奏不合適，用
`/devlog-tracker:checkpoint <正整數輪數>` 調整（不要手改
`.devlog/.checkpoint-state`，除非指令不可用）。

## `/devlog-tracker:pause` 之後

暫停強制記錄時 `.checkpoint-state` 不會被刪除，計數保留；之後重新
`/devlog-tracker:start` 會接著原本的計數繼續，不會歸零重算。
