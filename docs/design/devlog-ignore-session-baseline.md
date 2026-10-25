# 使用者自訂 ignore（`.devlogignore`）與本次 session 改動基準

狀態：已定案（實作中）。相關：`docs/design/files-verify.md`、`core/scripts/files-snapshot.sh`、`core/scripts/workspace-snapshot.sh`、`core/scripts/enforce-devlog.sh`、`core/scripts/devlog-md.sh`（`workspace_claim_state`）。

## 問題

Stop hook 與 round-start 的工作區比對只硬編碼略過 `.devlog/`，而且「尚未 commit」的檔案集合是整個工作區目前的 dirty 狀態。使用者開 session 前就有的未 commit 修改、生成檔、lockfile 都會被當成這一輪／這個 session 的改動：`<workspace>` 必須抄進去、`<files>` 的提示清單也會列它們。

## 決策

### D1. Ignore 檔放在專案根目錄 `.devlogignore`

- 位置：`$PROJECT_DIR/.devlogignore`，跟 `.devlog/` 同層（`$PROJECT_DIR` 是 hook 判定的專案目錄，也是 `git status` 路徑的相對基準）。
- 為什麼不放 `.devlog/.devlogignore`：`/devlog-tracker:start` 會建議把整個 `.devlog/` 加進 `.gitignore`，放進去就不能被版本控制。根目錄已有同類先例 `.devlog-session-context`。
- 檔案不存在或讀不到：行為和現在完全一樣（只略過 `.devlog/`）。

### D2. Pattern 語法：gitignore 的子集，自己實作 matcher（不呼叫 `git check-ignore`）

- 一行一個 pattern。空行與 `#` 開頭的行略過；CRLF 的 `\r` 與行尾空白會去掉。
- `!pat` 是否定。由上往下比對，**最後一個命中的 pattern 決定結果**。
- 結尾 `/`（如 `dist/`）：只比對目錄。命中的是該目錄本身和其下所有路徑。
- 開頭 `/`，或中間含 `/`（如 `/build`、`src/gen/*.ts`）：錨定在專案根目錄，比對完整相對路徑。
- 不含 `/`（如 `*.lock`、`node_modules`）：比對路徑的**任一層**名稱（檔名或任一祖先目錄名）。
- `*` 比對 `/` 以外任意字元，`?` 比對 `/` 以外的單一字元。`**` 可跨目錄，支援 `**/x`、`x/**`、`a/**/b` 三種形式。
- 不支援：`[...]` 字元類別、`\` 跳脫。不支援的語法照字面比對，不會報錯。
- 為什麼不用 `git check-ignore`：它一定會把 `.gitignore`／`info/exclude` 一起算進去，而且 `.gitignore` 的優先序高於 `core.excludesFile`，否定規則的結果會被汙染。自己用 awk 實作，行為才可預期，也才能單元測試。
- 壞掉的 pattern 或讀檔失敗：當作沒有這條 pattern（fail-open），絕不讓 hook 失敗。

### D3. Ignore 套用在每一個 git 變動來源

共用函式在 `core/scripts/devlog-ignore.sh`（被 source）。介面是 `devlog_ignore_filter DIR`：stdin 每行一個路徑，stdout 輸出沒被 ignore 的路徑。同一個檔也提供 `devlog_ignored DIR PATH`，回傳碼 0 表示被 ignore。

- `files_snapshot`：兩種模式都套用（未 commit 模式與 `commit <h>` 模式）。這樣 commit 區塊的雙向精確比對也會一起排除 ignored 路徑。
- `workspace_snapshot`：`未提交：` 清單會排除 ignored 路徑。如果所有 dirty 路徑都被 ignore，就輸出「工作樹乾淨」那個格式。
- 改名行 `R old -> new` 用新路徑判斷。
- 只有這兩個函式會呼叫 `git status`／`diff-tree`，所以 `<workspace>` 精確比對、`<files>` 檢查、round-start 漂移（`workspace_claim_state`，含 linked worktree）都會自動一致。
- 已知後果：加入 ignore 之後，舊 Round 裡列過 ignored 路徑的 `<workspace>` 宣稱會跟新的 snapshot 不符，下一輪 round-start 可能報一次漂移。照漂移流程確認一次即可。

### D4. Session 基準（baseline）：session 開始時記下 dirty 路徑和內容 hash

- 檔案：`.devlog/.session-baseline[@platform]`，經由 `devlog_platform_file` 取得。Claude 用不帶後綴的名稱，Codex／Cursor 帶 `@codex`／`@cursor`，所以多個平台同時開也互不干擾。
- 格式（純文字）：

  ```
  # devlog-session-baseline v1
  session_id=<id 或空>
  <hash><TAB><path>
  ...
  ```

- 列舉方式：`git status --short --no-renames`，排除 `.devlog/`，**不**套 ignore。這樣 session 中途改 `.devlogignore` 仍然正確，因為 ignore 是在讀取時才套用。
- hash 的算法：
  - 存在的檔案：`git hash-object`，用 `--stdin-paths` 一次批次算完。二進位檔也能算，macOS 和 Linux 結果一致。
  - 已刪除的路徑：記成 `MISSING`。
  - symlink：先判斷 `-L`，再判斷 `-d`／`-f`。hash 是連結文字（`readlink`，不加 `-f`，去掉結尾換行）經 `git hash-object --stdin` 算出的值；一般目標與 git 自己存的 symlink blob 一致（目標字串結尾帶換行的例外，見已知限制）。所以改指向內容相同的另一個目標也算改動，指向目錄的 symlink 也不會被併成 `DIR`。
  - untracked 目錄條目（`?? dir/`）：對 `git ls-files -o --exclude-standard -- dir/` 列出的每個檔，產生 `<relpath><TAB><blob hash>` 一行（檔案與 symlink 規則同上），整批排序後取 `cksum`。路徑和內容綁在同一行，所以兩個檔互換內容、或子檔改名，都會改變 hash。
- 判定規則：一條目前 dirty 的路徑，如果不在基準裡，或 hash 跟基準不同，就算**本次 session 的改動**。所以開 session 前就 dirty、session 內又改過的檔也算改動。
- 有效的基準必須同時符合：第一行 header 正確，而且檔案可以讀。不符合就視為沒有基準。

### D5. 基準只用在「檔案變動」判斷，不用在 `<workspace>`

- 用到基準的地方：
  - enforce 的 `<files>`「尚未 commit」檢查：宣稱的路徑必須是本次 session 改動的子集合。
  - 擋下時印出的「實際改動」清單。
  - `bash core/scripts/files-snapshot.sh [dir]` 直接執行時的輸出，讓人或 agent 查本 session 的改動。
- 宣稱了一個開 session 前就 dirty、而且之後沒動過的路徑，會被擋下，訊息會說明「它在本 session 開始前就已存在且未變動」。
- `commit <h>` 區塊不套用基準，因為 session 內產生的 commit 本來就是本 session 的改動。
- `<workspace>`（工作區**狀態**：branch @ hash + 未提交清單）和漂移判斷**不**套用基準，只套用 ignore。原因：`/devlog-tracker:continue` 會在**另一個** session 用 `workspace-snapshot.sh` 核對上一輪的 `<workspace>`。新 session 的基準會把上一個 session 的成果當成「既有」。如果 `<workspace>` 跟著基準過濾，跨 session 接續就一定會不一致。狀態描述必須跟 session 無關。
- 不想在 `<workspace>` 裡看到的長期 dirty 檔（生成檔、lockfile），請用 `.devlogignore` 排除。

### D6. 基準的生命週期

只在 `.devlog/.enabled` 存在時運作。所有步驟出錯都靜默略過，絕不 exit 2。

| 時機 | 行為 |
|---|---|
| SessionStart `startup`／`clear` | 重建基準（新對話） |
| SessionStart `resume`／`compact` | 保留既有基準。沒有就建立 |
| SessionStart `fork` | 保留既有基準內容，把 `session_id` 改成新 id（分支後的對話繼承上一段的成果）。沒有就建立 |
| UserPromptSubmit（round-start）| 沒有有效基準就建立（lazy）。基準的 `session_id` 為空、而 payload 有 id，就寫入該 id。兩邊都有 id 但不同，就重建 |
| `/devlog-tracker:pause` | 刪除 `.session-baseline*` |
| SessionEnd | 不刪除，讓 resume 可以沿用 |

- 基準處理放在 `session-start-devlog.sh` 的 `.devlog-session-context = off` 提早結束**之後**。context 為 `off` 時，SessionStart 維持既有契約：不讀也不改任何 `.devlog` 狀態，所以不會碰基準。此時只靠 round-start 的 lazy 路徑（建立、補空 id、id 不同就重建）。fork 會產生新的 session id，所以 context 為 `off` 時 fork 會得到全新的基準，而不是沿用舊內容。
- Codex／Cursor 的 SessionStart wrapper 不傳 `session_id`（Cursor 也一律傳 `startup`）。這時會建立 `session_id` 為空的基準，再由 round-start 補上 id。

> 實作備註（D4/D6）：`.session-baseline*` 是新檔名，沒有舊版殘留，所以不需要加進 `_devlog_claim_legacy_state`。基準檔的 header 之後第二行固定是 `session_id=`；`session_changes` 回傳碼 3 表示沒有有效基準、1 表示 git／hash 失敗，兩者都由呼叫端退回現行行為。submodule 這類不帶 `/` 的目錄條目 hash 記為 `DIR`。

### D7. Fail-open

下列情況一律退回現行行為：沒有基準、header 壞掉、讀不到檔、git 不可用、hash 指令失敗。退回後「尚未 commit」比對整個 dirty 工作區。必須重建的時機（SessionStart `startup`／`clear`，或 round-start 看到 id 不同）若重建失敗（`hash-object`／git 錯誤、寫檔或 `mv` 失敗），會把舊基準檔刪掉，讓呼叫端退回現行行為，不留下過期的基準。刪除本身也是 best-effort，刪不掉就維持原狀。`.devlogignore` 壞掉時只會少套某些 pattern。新增的程式碼路徑都不會讓 hook 非零結束（Stop 的正常擋下除外）。

### D8. 管理指令 `/devlog-tracker:ignore`

- 用法：`list`（預設）、`add <pattern>`、`remove <pattern>`、`check <path>`（顯示這個路徑會不會被 ignore；不顯示命中哪一行，因為 matcher 只回傳結果）。
- 腳本是 `core/scripts/ignore-patterns.sh`。它會建立或編輯 `.devlogignore`：`add` 不加入重複的行，`remove` 只刪掉完全相同的行。
- 不需要 `.devlog/.enabled`，因為 ignore 檔跟有沒有啟用無關。
- 檔案三件組：`commands/ignore.md` 是來源，`codex/skills/devlog-ignore/SKILL.md` 由 `node scripts/sync-codex-plugin.js` 產生，`skills/devlog-tracker/` 的指令表也要更新。另外要把 `devlog-tracker:ignore` 加進 round-start 的略過清單，呼叫這個指令時才不會開新的 Round。
- 手動編輯 `.devlogignore` 一樣有效。這個指令只是方便查看和確認。

## 已知限制

- symlink 目標字串若以換行結尾，`$(readlink …)` 會吃掉結尾換行，把 `target` 改指向 `target\n` 不會被當成改動。這種目標極少見，後果只是該 symlink 不被列為本 session 改動（宣稱它時會被擋，可改不列它或刪掉基準退回現行行為），因此不處理。
- 路徑含空白的限制跟既有的兩個 snapshot 一樣（請見 `files-verify.md`）。
- 在 session 中途才 `/devlog-tracker:start`：基準會在下一次送出 prompt 時建立。啟用前在這個 session 已做的改動，會被當成「既有」。
- 拿不到 session id 的平台（Codex、Cursor 的 SessionStart）只能靠 SessionStart 的 source 判斷要不要重建。Cursor 每次都傳 `startup`，所以每個新的 Cursor session 都會重建，這是預期行為。
- linked worktree 的漂移判斷會套用 ignore，不套用基準（D5）。
- matcher 是 gitignore 子集（D2），不支援字元類別與跳脫。
- 用 `.devlogignore` 排除的檔案，連 `commit <h>` 區塊也看不到；commit 裡如果只有 ignored 檔，files_snapshot 輸出為空：`check_commit_block` 不會硬擋——只寫 `commit <h>` 標頭、不列分類行的區塊（宣稱為空）會通過；如果仍宣稱了 ignored 路徑，會被擋下，訊息請對方刪掉這個區塊或分類行（沿用「.devlog/ 以外沒有變更」的既有路徑，訊息文字已補上 `.devlogignore`）。
- 整個目錄都是 ignored 的未追蹤目錄（git 併成 `?? dir/`）：status 模式的 filter 會用 `git ls-files -o --exclude-standard -- dir/` 展開，所有子檔都被 ignore 才丟掉這一行（含巢狀併合）；失敗時保留（fail-open）。部分 ignored 的目錄仍列成 `dir/`，它在 session 基準裡的指紋也包含 ignored 的子檔，所以只動 ignored 子檔也會讓該目錄被當成本 session 改動。
