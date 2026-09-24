# Read-side outputs + promote（report／timeline／pr／promote）

Status: design approved 2026-09-23, not yet implemented.

devlog 目前的指令大多在「寫」與「維護」；讀取端只有 `search`、`overview`、
`lessons`，而且都停在對話裡的文字。這份設計補四個把 devlog 變成產出物、或把
沉澱內容回流到專案規範的功能：

| # | 功能 | 入口 | 寫什麼 |
|---|---|---|---|
| B | 統計 report | `report-devlog.sh`、`/devlog-tracker:report`、`npx devlog-tracker report` | 不寫檔 |
| C | HTML 時間軸 | `timeline-devlog.sh`、`/devlog-tracker:timeline`、`npx devlog-tracker timeline` | `.devlog/timeline.html` |
| A | PR 描述產生器 | `pr-context.sh`、`/devlog-tracker:pr` | `.devlog/pr-body.md`；確認後 `gh pr create/edit` |
| D | 規範回流 | `promote-*.sh`、`/devlog-tracker:promote` | CLAUDE.md 或 AGENTS.md 的 rules 受管區塊 |

一個 PR 一起出，執行順序 **B → C → A → D**（B 的 JSON 是 C 的資料來源；A、D
互相獨立）。PR 內不改版號，合併後照 `AGENTS.md` 發版流程 `pnpm version minor`。

子計畫：[`report-plan.md`](report-plan.md)、[`timeline-plan.md`](timeline-plan.md)、
[`pr-body-plan.md`](pr-body-plan.md)、[`promote-plan.md`](promote-plan.md)。

## 共通原則

- **分工照舊。** `core/scripts/*.sh` 抽資料、做檔案操作，輸出 `KEY=VALUE`
  （或 `--json`）；`commands/*.md` 指揮模型整理、跟使用者確認；`cli/` 只包一層
  呼叫。不在 Node 端重寫 Round 解析——解析只在 bash 端維護一份。
- **對外內容不帶 `User Input` 原文。** PR body、timeline、report JSON 預設都不含
  User Input；`redact-prompt.sh` 只遮常見 token，原文仍可能有敏感內容。report 需要
  時才以 `--with-input` 顯式要求。
- **寫入需要明確同意。** `pr` 送 `gh` 前、`promote` 寫 CLAUDE.md／AGENTS.md 前，都要
  停下來等使用者確認。
- **`devlog_resolve_paths` 的副作用。** 已 `start` 的專案裡，一個 branch 第一次被
  解析時它會把 `devlog.md` **改名**成 `devlog.<branch>.md`。本設計的讀取腳本照
  既有讀取指令（`kept-list.sh` 等）的做法照常呼叫它；這個改名在切 branch 後遲早會
  發生，不是新增的風險，但實作與測試要知道它存在。
- **archive 不分 branch。** 只有一份 `devlog.archive.md`。

## B：report（統計）

### `core/scripts/report-devlog.sh [--json] [--rounds] [--all-branches] [--with-input]`

- 沒有 `.devlog/`：`NOT_STARTED`（`--json` 時 `{"started":false}`），exit 0。
- 預設輸出 `KEY=VALUE`：

  | 欄位 | 內容 |
  |---|---|
  | `BRANCH` | 目前 branch（detached 時同 `devlog_resolve_paths` 的 fallback 名） |
  | `ROUNDS_TOTAL`／`ROUNDS_MAIN`／`ROUNDS_ARCHIVE` | Round 數 |
  | `STATUS_DONE`／`STATUS_IN_PROGRESS`／`STATUS_BLOCKED`／`STATUS_INTERRUPTED` | 各 Status 計數（無 Status 的不計入任何一項） |
  | `BLOCKED_RATIO` | `STATUS_BLOCKED * 100 / ROUNDS_TOTAL`，整數；0 輪時為 0 |
  | `CHECKPOINTS` | `## Checkpoint` 區塊數 |
  | `KEPT_TOPICS`／`LESSONS_TOPICS` | Kept 索引、Lessons 索引行數 |
  | `LESSONS_ADVISORY` | 同 `status-devlog.sh` 的 `count/threshold`；沒有狀態檔就省略 |
  | `FIRST_ROUND_AT`／`LAST_ROUND_AT` | 從 `## Round N — <ISO>` 標題取時間；沒有就 `none` |

- 範圍：預設是目前 branch 的 `DEVLOG_FILE` + `devlog.archive.md`。`--all-branches`
  掃 `.devlog/devlog*.md`，排除 `devlog.archive.md`、`devlog.lessons.*.md`、Kept
  索引列出的 `devlog.<name>.md`；每個檔案對應的 branch 名取自檔名（`devlog.md` 記為
  `main`）。
- `--json`：同一組欄位的 JSON 物件，數字欄位輸出成 number。
- `--json --rounds`：多一個 `rounds` 陣列，每筆
  `{branch, file, line, n, at, status, summary, reply, handoff, segments}`，各段內容是
  原始 Markdown 字串（不含 `###` 標題行本身），`segments` 是字串陣列；另加
  `checkpoint_blocks` 陣列 `{branch, file, line, heading, body}`，供 timeline 穿插
  （`checkpoints` 已是計數欄位，陣列另外命名）。`line` 是標題所在行號。
  `--with-input` 再加 `input` 欄位。
- 解析用 awk 單次掃描（沿用 `devlog-md.sh` 的標題判斷規則，含 code fence 內的
  `##` 不算標題），不對每個 Round 反覆 grep。
- JSON 跳脫：把 `lessons-subagent-start.sh` 裡的區域函式 `json_escape` 搬到
  `json-field.sh` 共用；awk 內需要同一套規則（`\`、`"`、控制字元、換行）。

### `commands/report.md`

跑預設模式，把 stdout 翻成幾行給人看；不改任何檔。列入
`core/scripts/round-start.sh` 的 admin 指令清單（不開 Round）。

### `npx devlog-tracker report [--json] [--all-branches]`

`cli/core-script.js`（report 與 timeline 共用）用 `child_process.spawnSync('bash', [script, ...args])`，
`DEVLOG_PROJECT_DIR=process.cwd()`。script 優先用專案 vendored 的
`.devlog-tracker/core/scripts/report-devlog.sh`，沒有就用套件內附的
`core/scripts/report-devlog.sh`。stdout／exit code 原樣轉出。`bin/devlog-tracker.js`
的 usage 同步更新。

## C：HTML 時間軸

`init` 只 vendoring `core/scripts/`，不帶 `cli/`；renderer 要讓 plugin 與 vendored
使用者的指令都叫得到，所以放在 core。

### `core/scripts/timeline-devlog.sh [--all-branches] [--out <path>]`

1. `command -v node` 失敗 → `NO_NODE`，exit 0（Claude plugin 使用者不一定有 Node）。
2. 沒有 `.devlog/` → `NOT_STARTED`。
3. `report-devlog.sh --json --rounds [--all-branches] | node timeline-render.js > out`。
   預設 out 是 `.devlog/timeline.html`（`.devlog/` 通常已被 gitignore，沒有的話別把它 commit）。
4. 輸出 `OUT=<絕對路徑>`。

### `core/scripts/timeline-render.js`

零相依，stdin 讀 report JSON，stdout 輸出一份自足 HTML。

- **安全性：** 所有文字先 HTML 跳脫再做 Markdown 轉換；連結只允許 `http:`、
  `https:` 與相對路徑，其他 scheme（`javascript:`、`data:` 等）輸出成純文字；不輸出
  任何來自 devlog 的原始 HTML。
- **Markdown 子集：** `#`–`####` 標題、`-`／`1.` 清單（一層巢狀）、code fence、
  行內 code、粗體、連結、GFM 表格；其餘當段落文字。
- **版面：** 頁首統計列（Round 數、各 Status、時間範圍、branch）；下方依時間排序的
  Round 卡片（Status 色標、Round 編號、時間、branch 標籤、Summary），用
  `<details>` 展開 Reply／Handoff／Segments；Checkpoint 以不同樣式依位置穿插。
  頂部有 Status／branch 篩選與關鍵字篩選（小段內嵌 JS；沒 JS 時全部照常顯示）。
- **樣式：** `:root` color token，`prefers-color-scheme: dark` 深色模式，窄螢幕可讀；
  不引用任何外部資源。

### 入口

- `commands/timeline.md`：跑腳本、回報 `OUT` 路徑或 `NO_NODE`。列入 admin 指令清單
  （只寫通常已被 gitignore 的衍生檔，沒有的話別把它 commit）。
- `npx devlog-tracker timeline [--all-branches] [--out <path>]`：同樣經 `cli/core-script.js`
  轉呼 `timeline-devlog.sh`。

## A：PR 描述產生器

### `core/scripts/pr-context.sh`（純讀取）

- 不是 git repo → `NOT_A_REPO`。以 `git symbolic-ref --short HEAD` 判斷：detached HEAD →
  `DETACHED_HEAD`；`main`／`master`（不分大小寫，同 `devlog_resolve_paths`）→
  `ON_DEFAULT_BRANCH`；皆 exit 0。
- 輸出：
  - `BRANCH=`
  - `BASE=`／`BASE_REF=`：`refs/remotes/origin/HEAD` 存在時 `BASE` 為去掉 `origin/` 的名稱、
    `BASE_REF=origin/<name>`（`git log`／`rev-list` 用）；否則依序試本地 `main`、`master`，
    `BASE=BASE_REF=<name>`；都沒有 → `NO_BASE`，exit 0。
  - `DEVLOG_FILE=<絕對路徑>`：`devlog_resolve_paths` 的結果。
  - `ROUNDS=<空白分隔的起始行號>`；檔案不存在或沒有 Round → 改印
    `NO_BRANCH_DEVLOG`（其餘欄位照印）。
  - `COMMITS=<git rev-list --count BASE_REF..HEAD>`
  - `GH=yes|no`：`gh` 存在且 `gh auth status` 成功。
  - `PR=<number>|none`：`GH=yes` 時 `gh pr view --json number -q .number`，失敗或
    `GH=no` 皆為 `none`。

### `commands/pr.md`

1. 跑 `pr-context.sh`；`ON_DEFAULT_BRANCH`／`DETACHED_HEAD`／`NO_BASE` 就說明後結束。
2. 讀 `DEVLOG_FILE` 裡 `ROUNDS` 的 Round 與 `git log BASE_REF..HEAD`，用 Round 的
   `#### 檔案` 對照 commit。`NO_BRANCH_DEVLOG` 時只依 git log 產生，並在對話說明這是
   降級結果。
3. 產生 PR body，四節固定，語言跟使用者一致：
   - **Summary**：這個 branch 做了什麼，2–4 條。
   - **Decisions**：取自 `#### 決策`，只留最終版本，被後續 Round 推翻的不列。
   - **Changes**：依 commit 或檔案分組。
   - **Test plan**：取自 Round 裡的驗證紀錄；沒有就寫「未記錄」，不捏造。
   不貼 `User Input` 原文。專案 CLAUDE.md／AGENTS.md 若規定 PR 結尾格式就照做；指令
   本身不加簽名。
4. Write 到 `.devlog/pr-body.md`，並在對話顯示全文。
5. **停下來等確認。** 確認後：
   - `PR=none`：提議標題、等使用者確認，再 `gh pr create --base <BASE> --title … --body-file .devlog/pr-body.md`。
   - `PR=<n>`：提醒會覆寫現有描述，確認後 `gh pr edit <n> --body-file .devlog/pr-body.md`。
   - `GH=no`：停在步驟 4，告知檔案路徑。

不列入 admin 清單：會觸發對外動作，照常記 Round。

## D：規範回流（promote）

### 受管區塊

```
<!-- devlog-tracker:rules:begin -->
## devlog-tracker 沉澱的規範

- <規則>（來源：devlog.<name>.md「<標題>」）
<!-- devlog-tracker:rules:end -->
```

獨立於 `init` 管理的 `<!-- devlog-tracker:begin/end -->` 區塊：`init` 每次整塊覆寫
自己的區塊，規則若寫在那裡會被洗掉。`cli/agents-md.js` 的 `indexOf(BEGIN)` 不會
誤中 `rules:begin`，但要補測試鎖住「`init` 前後 rules 區塊逐字不變」。

### `core/scripts/promote-sources.sh`（純讀取）

- `FILE=<絕對路徑> KIND=kept EXISTS=0|1`：沿用 `devlog_kept_index_lines`。
- `FILE=<絕對路徑> KIND=lessons EXISTS=0|1`：沿用 `devlog_lessons_index_lines`。
- `CHECKPOINT=<絕對路徑>:<行號>`：目前 branch 主檔裡每個 `## Checkpoint` 標題（compact
  不搬 Checkpoint，archive 不會有）；模型只讀其下 `### 決策`。
- 三者皆無 → `NO_SOURCES`。

### `core/scripts/promote-target.sh`

依序：
1. 專案有 `.codex/hooks.json`（或 `.agents/skills/devlog-*`）且沒有 `CLAUDE.md` → `AGENTS.md`。
2. `CLAUDE.md` 去掉空白行後只剩 `@AGENTS.md` → `AGENTS.md`。
3. 其他 → `CLAUDE.md`（不存在時新建）。

輸出 `TARGET=<絕對路徑>`；目標檔已有 rules 區塊時另印 `EXISTING=<區塊內規則行數>`。

### `core/scripts/promote-write.sh <target> <rules-file>`

- `rules-file` 每行一條規則（`- ` 開頭；沒有就補）。
- 取 `devlog-lock.sh` 的鎖。沒有 rules 區塊 → 在檔尾（空一行後）新增；有 → 在
  `rules:end` 前追加。與區塊內既有行逐字相同的跳過。
- 輸出 `ADDED=<n> SKIPPED_DUP=<m> TARGET=<路徑>`。

### `commands/promote.md`

1. 跑 `promote-sources.sh`；`NO_SOURCES` 就說明後結束。
2. 跑 `promote-target.sh`，讀目標檔既有 rules 區塊（已在區塊裡的不再列為候選）。
3. 讀 `EXISTS=1` 的檔案與 Checkpoint 的 `### 決策`，挑出「之後應該一直遵守」的內容
   （不是單次任務細節、不是被後續內容推翻的決定）；列成編號候選，每條一行 + 來源。
   沒有夠格的就說沒有，不硬湊。
4. **停下來等使用者選**（編號、可要求改寫）。沒有明確選擇就不寫。
5. Write 選定規則到 `.devlog/.promote-rules.tmp`，跑 `promote-write.sh`，刪暫存檔，
   回報 `ADDED`／`SKIPPED_DUP` 與目標路徑。

不列入 admin 清單：會改專案檔案，照常記 Round。`overview` 不變（仍純讀取）。

## 跨功能收尾

- `core/scripts/round-start.sh` admin 清單：加 `report`、`timeline`。
- `cli/agents-md.js` 的 Codex 對照表與 `cli/platforms/claude.js` 的 Claude 對照表：加上四個指令。`skills-from-commands.js` 自動轉
  `commands/*.md`，測試確認新檔都生成對應 skill。
- README.md／README.zh-TW.md 指令表補四列；`bin/devlog-tracker.js` usage 加
  `report`、`timeline`。
- `package.json`：`"test"` glob 加 `core/scripts/*.test.js`（順手補上原本沒被跑到的
  `cli/platforms/*.test.js`）；`"files"` 已含
  `core/scripts`，`timeline-render.js` 自動打包。
- `run-tests.sh` 以 `tests/test-*.sh` glob 自動納入新增的 `test-report.sh`、`test-timeline.sh`、
  `test-pr-context.sh`、`test-promote.sh`；shellcheck 範圍不變。

## 測試重點

- report：空檔、只有 archive、多 branch、無 Status 的 Round、code fence 內的
  `## Round`、含 `"`／`\`／換行／CJK 的 JSON 跳脫（用 `node -e JSON.parse` 驗）。
- timeline：`<script>`、`javascript:` 連結被中和；CJK；Status 分類；`NO_NODE`
  （PATH 裡沒有 node）。
- pr-context：default branch、detached、無 base、無 branch 檔；`gh` 用 PATH 上的
  假腳本模擬 `GH=yes`／`PR=<n>`。
- promote：無來源、ghost row、target 判斷三種情況、新增區塊、追加、逐字去重、
  `init` 後 rules 區塊不變。

## Non-goals

- 不做 L2／L3（見 `devlog-as-ssot-assessment.md`）。
- 不解析 transcript、不自動 compact、不對 Summary 做語意評分（`optimization-plans.md`
  的 don't-do 清單不變）。
- promote 不自動刪除或改寫已在 rules 區塊裡的規則；要改由使用者手動編輯。
- timeline 不做伺服器、不做即時更新；每次重跑產生靜態檔。
