---
name: devlog-keep-all
description: "整理所有 devlog：跨主檔、所有分支檔、archive 與既有 keep 檔，依主題重新分成 devlog.<name>.md"
---

Codex plugin 安裝：目前這份 `SKILL.md` 的絕對路徑位於
`<plugin 根目錄>/codex/skills/<skill 名稱>/SKILL.md`。每次用 shell 執行下方步驟時，
先從這份檔案的所在目錄往上三層取得 plugin 根目錄，並在同一次 shell 呼叫中
`export DEVLOG_TRACKER_ROOT="<該根目錄的絕對路徑>"`。
一般 shell 呼叫不一定有 hook 專用的 `PLUGIN_ROOT`／`CLAUDE_PLUGIN_ROOT` 環境變數。
若是 npx 安裝，沿用專案內既有的 `DEVLOG_TRACKER_ROOT`。

請執行 devlog keep-all（整理全部 devlog）。這是使用者主動執行 `/devlog-tracker:keep-all` 時才做的事，不要自動觸發。

跟 `/devlog-tracker:keep` 的差別：keep 只整理目前分支的主檔；keep-all 一次看 `.devlog/` 裡**所有** devlog 檔——目前分支的主檔、其他分支的 `devlog.<branch>.md`、`devlog.archive.md`，以及先前 keep／keep-all 產生的具名檔——跨檔依主題重新分段。既有的具名檔會被拆開重組，所以一個主題散在 main、feature 分支與 archive 的片段可以合回同一個檔。設計見 `docs/design/keep-all.md`。

確認之前不要寫任何檔。

先決定 plugin 根目錄（有 `DEVLOG_TRACKER_ROOT` 用它；否則用 `CLAUDE_PLUGIN_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄），並記下目前已確認的專案根目錄絕對路徑（後面兩次呼叫都用同一個值，不要用 `$(pwd)` 重新推）。

## 1. 掃描

```bash
PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
DEVLOG_PLATFORM="<你所在的平台：claude／codex／cursor>" DEVLOG_PROJECT_DIR="<專案根目錄絕對路徑>" bash "${PLUGIN_ROOT}/core/scripts/keep-all.sh" --scan
```

- `NO_NODE`：告知 keep-all 需要 Node.js（可改用 `/devlog-tracker:keep` 整理目前分支），結束。
- `NOTHING`：告知目前沒有可整理的 Round，不要建立任何檔，結束。
- 否則輸出是：
  - `FINGERPRINT=<fp> COUNT=<n>`：記下這兩個值，步驟 4 原樣帶回。
  - `SOURCE file=… kind=…`：每個來源檔。`kind` 由腳本判定，不要自己依檔名猜：
    - `current`：目前分支的主檔
    - `branch`：其他分支的主檔；`origin` 是分支名，`state` 是 `active`（還在開發）／`merged`（已合併進 main）／`gone`（本地分支已刪）／`unknown`／`n/a`
    - `archive`：`devlog.archive.md`
    - `kept`：既有的具名檔（第一行是 `# Kept log`）
  - `ROUND id=… file=… round=… line=… ts=… status=… movable=0|1`：每個 Round 一行，`id` 是依時間排序的全域編號（不同檔的 Round 編號會重複，一律用 `id` 指稱）。`movable=0` 的是目前開著的 Round，或其他分支最後一個 `DONE` 之後還沒完成的尾巴——這些不能搬，也不要列進任何段落。

## 2. 讀檔、分主題

讀完每個 `SOURCE` 檔（至少讀 `movable=1` 的 Round 所在範圍）。依 `### User Input` 與 `### Summary` 的主題，把 `movable=1` 的 Round 分成主題段落：

- 一段是一組 `id`，**可以跨檔、可以不連續**——同一主題在 main、分支與 archive 的片段應該放進同一段。
- `kind=kept` 來源的 Round **全部都必須**分進某一段（它們先前已被判定值得留），可以跟其他主題合併或拆開重組。
- 其他來源的瑣碎 Round（只有確認、閒聊、重複）可以不收，留在原檔。判斷標準同 `/devlog-tracker:keep` 步驟 2。
- 讀的時候同時標出**糾正 AI 的內容**：使用者在 `### User Input` 裡指出 AI 做錯、不要這樣做、改用別的方式（例如「不要」「應該」「改成」「又漏了」「我說過」、要求重做或改變回覆語言／格式），或使用者中斷／否決 AI 的做法，而 `### Summary`／`<decisions>` 顯示 AI 因此改了做法。純粹的需求變更、新功能要求、確認或追問不算。每筆記下：發生在哪個 `id`、AI 原本怎麼做、使用者要求怎樣、後來怎麼改。這些在步驟 4.5 單獨成節。
- 每段產生建議 `<name>`（小寫 ASCII kebab-case，2–4 段，只反映主題，不加日期），以及一句這段在做什麼的描述（純文字、不換行、不含 tab 與反引號；步驟 4 原樣寫進索引）。同一批兩段撞名時，較晚的加 `-2`／`-3`。既有 kept 檔的名稱若仍貼切可以沿用——它會被這次整理取代。

## 3. 一次列出，然後停下來等

```
掃到 N 段主題：
  1. <一句描述>　→ devlog.<name>.md
     <來源檔> Round <編號…>（#<id…>）、<來源檔> Round <編號…>（#<id…>，分支 <origin> <state>）
  2. ...
會被重整並刪除的既有 keep 檔：<檔名，逗號分隔，或「無」>
會被搬空並刪除的分支檔：<檔名，逗號分隔，或「無」>
糾正 AI 的紀錄：共 K 筆（#<id…>），會寫進分析檔「糾正 AI」節；沒有就寫「無」
可搬但偏瑣碎、留在原檔：<來源檔與 Round，或「無」>
不能搬、保持原樣：<各分支未完成尾巴與開著的 Round，或「無」>

回覆：
  採用 → 全部照上面寫入
  改第 N 段檔名 <name> / 移除第 N 段 / 第 N 段併入第 M 段
  摘要第 N 段 → 搬完後把該段敘事改寫得更精簡
  取消
```

同一則回覆可以合併多條修改；`N` 一律對應原始編號。使用者用文字要求把某些 Round 換段，照做後重新列一次再等。然後停止，使用者回覆前不要寫任何檔。

「會被搬空並刪除的分支檔」＝所有 Round 都分進某段、`state` 不是 `active`、且不是 `devlog.md` 的 `kind=branch` 來源（腳本會照這個規則刪）。

- 取消 → 不改檔，結束。
- `移除第 N 段`：該段若含 `kind=kept` 的 Round，拒絕並說明只能 `併入`；其餘 Round 留在原檔。
- `第 N 段併入第 M 段`：合併 id，沿用第 M 段的檔名與描述。
- 檔名規則同 `/devlog-tracker:keep` 步驟 4（`devlog.` 前綴與 `.md` 後綴會剝掉；不可為空、`archive`、`lessons.*`，不可含 `/`、`\`、`..`，最多 64 字元）；目標檔已存在（且不是這次會被整理掉的 kept 檔）時改建議 `-2`。

## 4. 寫計畫並執行（整批一次，全有或全無）

把確認後的段落寫到 `.devlog/.keep-all-plan.tsv`，一段一行，三欄以 tab 分隔：

```
<name>	<描述>	<id 清單，例如 3-8,20,24-25>
```

然後：

```bash
DEVLOG_PLATFORM="<你所在的平台：claude／codex／cursor>" DEVLOG_PROJECT_DIR="<專案根目錄絕對路徑>" bash "${PLUGIN_ROOT}/core/scripts/keep-all.sh" \
  --apply "<專案根目錄絕對路徑>/.devlog/.keep-all-plan.tsv" --fingerprint <fp> --count <n>
```

`<fp>`／`<n>` 用步驟 1 的值。不要自己搬檔、刪檔或改索引——腳本是唯一的實作：驗證計畫、把所有會動到的檔備份到 `.devlog/.keep-all-backup/<時間戳>/`、組好新檔、改寫來源、刪除被整理掉的 kept 檔、清空的 archive 與搬空的分支檔、重建 `## Kept 索引`（新索引行寫在目前分支的主檔）。搬空的分支檔只在該分支不是 `active` 時才刪；目前主檔與 `devlog.md` 一律不刪。

- exit 1：原樣顯示 stderr，不要自行重試或手動補做。驗證錯誤時不會寫任何檔；fingerprint 不符代表掃描後檔案被改過，回到步驟 1 重新掃描。同一工作樹有兩個以上平台的輪次開著時，腳本會以 `其他平台還有進行中的輪次（…），等它們收尾再執行。若該平台已不再使用，可先 pause 再 start 清掉它的標記。` 拒絕，請使用者等其他平台收尾再跑。
- 成功後刪除 `.devlog/.keep-all-plan.tsv`，接著寫分析檔（步驟 4.5）。

## 4.5 寫分析檔

apply 成功後，把本次確認的**所有主題**分析集中寫進單一檔 `.devlog/keep-all.analysis.md`（每次覆寫）。先用 Write 寫暫存檔 `<專案根目錄>/.devlog/.keep-all-analysis.tmp`，格式：

```
# Keep-all analysis

## 糾正 AI
- #<id> <來源檔> Round <編號>（主題：<topic>）
  - AI 做錯／不當：<AI 原本怎麼做>
  - 使用者糾正：<使用者要求怎樣，用自己的話濃縮，不貼原文>
  - 應遵守的規則：<一行、可直接放進 CLAUDE.md／AGENTS.md 的指示句；已被後續推翻就寫「已被推翻」>

## <topic>
<一句描述>

規範候選：
- <跨任務都成立、值得進 CLAUDE.md／AGENTS.md 的規則；沒有就寫「無」>

來源檔：<來源檔> Round <編號…>
```

`## 糾正 AI` 永遠放在最前面；沒有任何糾正時仍寫這一節，內容只寫「無」。同一種錯被糾正多次，合併成一筆並列出所有 `id`（重複被糾正代表這條規則最該進 prompt）。
`## 糾正 AI` 之後每個主題一節 `## <topic>`，每節含描述、規範候選、來源檔與 Round。規範候選不要貼 `### User Input` 原文。然後：

```bash
DEVLOG_PROJECT_DIR="<專案根目錄絕對路徑>" bash "${PLUGIN_ROOT}/core/scripts/keep-all.sh" --write-analysis "<專案根目錄絕對路徑>/.devlog/.keep-all-analysis.tmp" \
  && rm -f "<專案根目錄絕對路徑>/.devlog/.keep-all-analysis.tmp"
```

成功印 `ANALYSIS=<路徑>`。exit 1（來源檔不存在或空白、lock 被占用、寫入或搬移失敗）時原樣顯示 stderr，不要自行重試；此時 apply 已完成，不要回滾。

## 5. 選配：摘要

只對使用者標記「摘要第 N 段」的段落做，規則同 `/devlog-tracker:keep` 步驟 5.5（只改寫 `### Summary`、`### Reply`、`<decisions>`／舊格式 `#### 決策`、`<state>`／舊格式 `#### 現況` 的敘事；標題、`### User Input`、`<workspace>`／舊格式 `#### 工作區`、`<files>`／舊格式 `#### 檔案`、`<done-when>`／舊格式 `#### 完成條件`、`<next>`／舊格式 `#### 下一步`、`### Status` 一律不動；改寫 XML 欄位內容時，標籤行本身不動；用 Edit 不用 Write）。

## 6. 回報

依 stdout 回報：每個 `KEPT=<路徑> ROUNDS=<n>`、每個 `DELETED=<路徑>`、`BACKUP=<目錄>`（出錯時可從這裡還原），以及 `ANALYSIS=<路徑>`、哪幾段套用了摘要。

若你所在平台的 `.round-open` 檔（Claude Code 是 `.devlog/.round-open`，Codex／Cursor 是 `.devlog/.round-open@codex`／`.devlog/.round-open@cursor`）存在：在開著的那一輪補上 `### Summary` / `### Handoff` / `### Status` 再結束（Stop hook 仍會檢查）。

使用者提供的額外參數：請看觸發這個 skill 的使用者訊息。
