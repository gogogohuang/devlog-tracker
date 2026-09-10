# Keep Topic Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite `/devlog-tracker:keep` so it scans all of `.devlog/devlog.md`, partitions historical Rounds into topic segments, drops thin ones, and proposes every keep-worthy segment at once — instead of only ever proposing the latest stretch.

**Architecture:** No new hooks or scripts. `hooks/scripts/keep-move.sh` keeps its existing single-range contract; `commands/keep.md` now calls it once per confirmed segment, oldest Round first. Everything new (partitioning, filtering, batch confirmation, per-segment edit grammar) is prompt logic inside `commands/keep.md`, the same way the original design put move rules there instead of in a hook.

**Tech Stack:** Claude Code plugin commands (`commands/*.md`), markdown skill/README.

**Spec:** `docs/design/keep.md` (updated 2026-09-10 for the topic-split behavior).

## Global Constraints

- Do not add hooks, hook tests, or `hooks/hooks.json` changes.
- `hooks/scripts/keep-move.sh` is unchanged. It still accepts exactly one `--from`/`--to`/`--name` per invocation and has no notion of a batch.
- Each named file is still one contiguous range. A batch run may produce several named files, but no single file spans non-contiguous Rounds.
- The open Round (`.devlog/.round-open` `round` if that file exists, otherwise there is no open Round at all — every `## Round` is historical) is never part of any segment.
- Segments in a confirmed batch must not overlap each other and must not include the open Round.
- Write-then-delete per segment: create the named file, verify it, only then delete from `devlog.md`. Delete-first is forbidden. On failure, stop the whole batch — do not roll back segments already written, and do not attempt the remaining queued segments.
- Reserved filename `<name>`: `archive`. Never overwrite an existing named file, and never let two segments in the same batch resolve to the same path — both count as a collision (see spec's Collision section).
- Compact and keep do not read or write each other's targets (`devlog.archive.md` vs `devlog.<name>.md`). No changes to `commands/compact.md` in this plan — it already ignores `devlog.<name>.md`.
- Do not auto-run keep. Do not inject kept files on SessionStart. Do not bump plugin version or touch `.claude-plugin/*.json`.
- This repo gitignores `docs/superpowers/`. Plans live under `docs/design/`.
- Command copy is Traditional Chinese, matching `commands/compact.md`. Spec stays English.

## File Structure

| File | Responsibility |
|---|---|
| `commands/keep.md` | Full rewrite: partition into segments, filter thin ones, batch confirmation, per-segment edit grammar, sequential `keep-move.sh` calls |
| `skills/devlog-tracker/SKILL.md` | Reword the existing `具名保存` section to say keep scans and splits by topic |
| `README.md` | Reword the existing keep table row the same way |
| `docs/design/keep.md` | Already rewritten (previous turn); do not edit unless a task finds a contradiction |
| `hooks/scripts/keep-move.sh` | No changes |
| `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | No changes |

---

### Task 1: Rewrite `commands/keep.md` for topic-split batching

**Files:**
- Modify: `commands/keep.md` (full body rewrite; frontmatter `description` changes too)

**Interfaces:**
- Consumes: `.devlog/devlog.md`, optional `.devlog/.round-open`, optional `.devlog/.span-open`; `hooks/scripts/keep-move.sh` unchanged CLI (`--from <int> --to <int> --name <str>`, stdout `KEPT=<path> ROUNDS=<from>-<to> REMAINING=<int>` on success, exit 1 with a Chinese error line on stderr on failure).
- Produces: zero or more `.devlog/devlog.<name>.md` files per invocation (previously always at most one); deletes the corresponding blocks from `devlog.md`; may rewrite the leftover open Round heading to `## Round 1` and delete `.span-open` if the last segment processed happens to be a full keep (unchanged `keep-move.sh` behavior, now reachable from a batch).

- [ ] **Step 1: Replace `commands/keep.md` with the batch version**

Write this file verbatim (this replaces the entire current file):

```markdown
---
description: 掃描整份 devlog.md，把值得留名的主題段落一次分別搬成 devlog.<name>.md；也可只抽出一段或合併成全部歷史一個檔
---

請執行 devlog keep（具名搬走）。這是使用者主動執行 `/devlog-tracker:keep` 時才做的事，不要自動觸發。

確認之前不要寫任何檔。這一輪本身是開著的 Round，永遠不要把它搬走；這一輪結束前仍要補 `### Summary` / `### Handoff` / `### Status`。

## 1. 讀檔、找出開著的 Round

1. 讀取 `.devlog/devlog.md` 全文。若檔案不存在，告知「目前沒有東西可 keep」，不要建立 `.devlog/` 或任何新檔，結束。
2. 開著的 Round：若 `.devlog/.round-open` 存在且有 `"round"` 數字，用那個編號。若 `.round-open` 不存在（從未 start 或已 pause），表示沒有開著的 Round，檔案裡所有 `## Round` 都是歷史，不要把最後一個 Round 當成開著的 Round 來排除。
3. 歷史 Round = 檔案裡除了開著的 Round 以外的所有 `## Round`（判斷 `## ` 標題時，略過圍欄程式碼區塊 ``` 內的行，與 hook 腳本解析方式一致）。若沒有任何歷史 Round，告知「目前沒有東西可 keep」，不要建立新檔，結束。

## 2. 切出主題段落，過濾瑣碎段落

1. 依各輪 `### User Input` 與 `### Summary` 的主題變化，把**全部**歷史 Round（不含開著的 Round）切成連續、不重疊、涵蓋所有歷史 Round 的候選段落，由舊到新排列，不要留空隙。
2. 用 skills/devlog-tracker 判斷瑣碎程度的同一套訊號，評估每一個候選段落：有檔案異動、有影響後續的決策、有未完成工作、刪掉會接續不上 → 值得留名，列為候選；只有確認、閒聊、重複 → 偏低，直接丟掉，不列入建議清單，繼續留在 `devlog.md`，不用再嘗試併進相鄰段落。
3. 若一個候選段落都沒有，告知「目前沒有值得分主題留名的段落」，不要建立新檔，結束。
4. 對每個候選段落，用**那一段的內容**（不是留下的 Round）產生建議 `<name>`：小寫 ASCII kebab-case，2–4 段，只反映主題。不要加日期、不要加 `round-12-18`。例如 `span-mode`、`keep-plan`。這一批裡若兩段的建議 `<name>` 相同，比照步驟 4 的撞名規則先加上 `-2`/`-3` 分開，再一起列出。

## 3. 一次列出全部候選段落，然後停下來等

用這一則訊息列出所有候選段落（不要分開一段一段問）：

```
掃到 N 段值得留名：
  1. Round <from>–<to>　<一句這段在做什麼>　→ devlog.<name>.md
  2. Round <from>–<to>　<一句這段在做什麼>　→ devlog.<name>.md
  ...
其餘 Round（<留下的範圍，或「無」>）偏瑣碎，留在 devlog.md。

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
- `from` > `to`、輪次不存在於檔案、範圍含開著的 Round、或跟同批另一段重疊 → 說明原因，請使用者改，不要寫檔。

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

```bash
CLAUDE_PROJECT_DIR="$(pwd)" bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/keep-move.sh" \
  --from <from> --to <to> --name "<name>"
```

`<from>`、`<to>`、`<name>` 必須使用該段步驟 4 確認後的值。腳本是搬移、Checkpoint 歸屬、full keep 重編與 checkpoint counter reset 的唯一實作來源；它一次只認一段範圍，完全不知道這是批次的一部分，`commands/keep.md` 自己負責依序呼叫。

任一段的腳本 exit 1：立刻停止整批，原樣顯示那一段的 stderr，不要自行重試刪除，也不要手動補做搬移，也不要繼續跑後面還沒處理的段落。已經成功搬走的段落不要回滾。

如果這批段落最終涵蓋了 `devlog.md` 目前剩下的所有歷史 Round（沒有瑣碎段落留下），跑到最後一段（Round 號碼最新的那一段）時，腳本會自動判定為 full keep：專案摘要併入那一檔、開著的 Round 重編號成 1、`.span-open` 刪除、checkpoint counter 歸零。這是預期行為，不用特別處理，也不用另外判斷「這是不是 full keep」。

## 6. 處理腳本結果

每段成功時記下 stdout 給的具名檔路徑與 `ROUNDS=<from>-<to>`，等這批全部段落都跑完（或某段失敗中止）後，一次在步驟 7 回報。

## 7. 回報並收尾這一輪

依段落回報：每個具名檔路徑、搬走幾輪（哪些編號）；再回報 `devlog.md` 目前剩幾輪。若中途因某段腳本失敗而中止，清楚列出哪些段落已經搬走（連檔名）、哪些完全沒嘗試。不要讀寫 `devlog.archive.md`。

若 `.round-open` 存在：在開著的那一輪補上 `### Summary` / `### Handoff` / `### Status` 再結束（Stop hook 仍會檢查）。若沒有開著的 Round：不要改寫歷史 Round 的收尾。
```

- [ ] **Step 2: Verify the new command file against the spec**

From the repo root:

```bash
test -f commands/keep.md
grep -q '掃描整份 devlog.md' commands/keep.md
grep -q '切出主題段落，過濾瑣碎段落' commands/keep.md
grep -q '偏低，直接丟掉' commands/keep.md
grep -q '目前沒有值得分主題留名的段落' commands/keep.md
grep -q '一次列出全部候選段落' commands/keep.md
grep -q '改第 N 段範圍' commands/keep.md
grep -q '改第 N 段檔名' commands/keep.md
grep -q '移除第 N 段' commands/keep.md
grep -q '全部歷史合併成一個檔' commands/keep.md
grep -q '任兩段的範圍不可重疊' commands/keep.md
grep -q '不要讓兩段寫進同一個檔' commands/keep.md
grep -q '依序跑搬移腳本' commands/keep.md
grep -q 'keep-move.sh' commands/keep.md
grep -q '已經成功搬走的段落不要回滾' commands/keep.md
grep -q 'full keep' commands/keep.md
grep -q '.round-open' commands/keep.md
grep -q 'archive' commands/keep.md
grep -q '### Summary' commands/keep.md
```

Expected: `test` exits 0; every `grep -q` exits 0. If any grep fails, the corresponding rule got dropped from the rewrite — add it back before committing.

- [ ] **Step 3: Commit**

```bash
git add commands/keep.md
git commit -m "$(cat <<'EOF'
feat: split keep into a full-file topic scan

/devlog-tracker:keep now partitions all historical Rounds into topic
segments, drops thin ones, and proposes every keep-worthy segment at
once. Each segment still moves through the unchanged keep-move.sh one
at a time, oldest first; a batch that happens to cover all of history
still lets the last segment trigger the existing full-keep behavior.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Reword SKILL.md and README.md for the new behavior

**Files:**
- Modify: `skills/devlog-tracker/SKILL.md:422` (the `具名保存` section body)
- Modify: `README.md:48` (the keep row in the command table)

**Interfaces:**
- Consumes: nothing new — this task only changes prose describing Task 1's already-shipped behavior.
- Produces: doc text that no longer implies keep only ever handles one segment.

- [ ] **Step 1: Reword `skills/devlog-tracker/SKILL.md`**

Find this line (currently line 422, under the `## 具名保存：\`/devlog-tracker:keep\`` heading):

```markdown
把一段（或全部歷史）從 `devlog.md` **搬走**成 `.devlog/devlog.<name>.md`，讓有主題的紀錄可以單獨留名。這不是 compact：compact 把舊的 `DONE` 輪次 append 進 `devlog.archive.md`；keep 寫的是一個主題一個檔，且從不寫 archive。步驟見 `commands/keep.md`。不要自動觸發。
```

Replace it with:

```markdown
掃描整份 `devlog.md`，把值得留名的主題段落一次分別**搬走**成 `.devlog/devlog.<name>.md`（也可只抽出一段，或合併成全部歷史一個檔）。這不是 compact：compact 把舊的 `DONE` 輪次 append 進 `devlog.archive.md`；keep 寫的是一個主題一個檔，且從不寫 archive。步驟見 `commands/keep.md`。不要自動觸發。
```

- [ ] **Step 2: Reword `README.md`**

Find this row (currently line 48):

```markdown
| `/devlog-tracker:keep` | 確認後由腳本把有主題的一段搬走成 `devlog.<name>.md`。不是 compact。細節見 [`docs/design/keep.md`](docs/design/keep.md)。 |
```

Replace it with:

```markdown
| `/devlog-tracker:keep` | 掃全檔分主題，一次列出建議，確認後把各段各自搬走成 `devlog.<name>.md`；也可抽出一段或合併成全部歷史一檔。不是 compact。細節見 [`docs/design/keep.md`](docs/design/keep.md)。 |
```

- [ ] **Step 3: Verify**

```bash
grep -q '掃描整份 `devlog.md`，把值得留名的主題段落一次分別' skills/devlog-tracker/SKILL.md
grep -q '掃全檔分主題，一次列出建議' README.md
```

Expected: both `grep -q` exit 0.

- [ ] **Step 4: Commit**

```bash
git add skills/devlog-tracker/SKILL.md README.md
git commit -m "$(cat <<'EOF'
docs: describe keep's topic-split scan in SKILL and README

Both pointers previously described keep as always moving one segment;
reword to match the batch topic scan from the previous commit.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Spec coverage (self-review)

| Spec section (`docs/design/keep.md`) | Task |
|---|---|
| Command flow §1 (missing file / no historical Rounds) | Task 1 §1 |
| Command flow §2–5 (partition, filter, propose all at once) | Task 1 §2, §3 |
| Editing the batch (accept / edit range / edit name / drop / merge-to-one / cancel) | Task 1 §3 |
| Range (contiguous per segment, no overlap, open Round excluded) | Task 1 §4 |
| Filenames: suggest, normalize, reject list, collision incl. within-batch | Task 1 §2, §4 |
| Execution order and full keep (oldest first, last segment can trigger full keep) | Task 1 §5 |
| Write order and failures (stop batch on first failure, no rollback, no auto-retry) | Task 1 §5, §7 |
| Report per file + remaining count; close open Round | Task 1 §7 |
| Boundary with compact / SessionStart / no auto-run | Already true (unchanged files); Task 1 header line |
| SKILL.md / README wording | Task 2 |

No gaps found. No placeholders in either task. `keep-move.sh`'s CLI (`--from`/`--to`/`--name`, stdout/stderr contract) is referenced identically in Task 1 Step 1 and Step 2 — no signature drift, since the script itself is unmodified.
