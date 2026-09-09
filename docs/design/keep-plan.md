# Keep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `/devlog-tracker:keep` so Claude can move a named stretch of `.devlog/devlog.md` into `.devlog/devlog.<name>.md` after the user confirms value, range, and filename.

**Architecture:** Same shape as compact: a slash command markdown file is the executable spec. No new hooks, no new scripts. SessionStart still injects only `devlog.md`. Discoverability is a short SKILL pointer plus README and plugin description.

**Tech Stack:** Claude Code plugin commands (`commands/*.md`), markdown skill/README, JSON plugin manifests.

## Global Constraints

- Spec: `docs/design/keep.md`. Do not add hooks, hook tests, or `hooks/hooks.json` changes.
- Always a move. Write the named file first; delete from `devlog.md` only after that write is verified. Delete-first is forbidden.
- The open Round is never moved: `.devlog/.round-open` `round` if that file exists, otherwise the last `## Round N` in `devlog.md`.
- Range is contiguous inclusive Round numbers. Non-contiguous picks are out of scope.
- Reserved filename `<name>`: `archive`. Never write `.devlog/devlog.md` via keep. Never overwrite an existing named file.
- Compact and keep do not read or write each other's targets (`devlog.archive.md` vs `devlog.<name>.md`).
- Do not auto-run keep. Do not inject kept files on SessionStart. Do not bump plugin version.
- Do not copy instead of move. Do not put kept files in a subdirectory. Do not pull from archive.
- This repo gitignores `docs/superpowers/`. Plans live under `docs/design/`.
- Command copy is Traditional Chinese, matching `commands/compact.md`. Spec stays English.

## File Structure

| File | Responsibility |
|---|---|
| `commands/keep.md` | Steps Claude runs on `/devlog-tracker:keep` (source of truth at run time) |
| `skills/devlog-tracker/SKILL.md` | File-location bullet, keep section, description trigger terms |
| `commands/compact.md` | One line: do not touch `devlog.<name>.md` |
| `README.md` | User-facing keep blurb, usage snippet, directory tree |
| `.claude-plugin/plugin.json` | Description lists keep |
| `.claude-plugin/marketplace.json` | Same description |
| `docs/design/keep.md` | Already written; do not rewrite unless a task finds a contradiction |

Do not create hook scripts. Do not edit `hooks/`.

---

### Task 1: Command file

**Files:**
- Create: `commands/keep.md`
- Test: none (spec: no new hook self-checks; compact has none). Verify with the grep checklist in Step 2.

**Interfaces:**
- Consumes: `.devlog/devlog.md`, optional `.devlog/.round-open`, optional `.devlog/.span-open`.
- Produces: `.devlog/devlog.<name>.md` after confirm; edits `devlog.md` by deleting moved blocks; may rewrite the leftover open Round heading to `## Round 1` on full keep; may delete `.span-open`. Never creates `.devlog/` when `devlog.md` is missing.

- [ ] **Step 1: Create `commands/keep.md`**

Write this file verbatim:

```markdown
---
description: 若這段 devlog 值得單獨留名，把它從 devlog.md 搬走成 devlog.<name>.md；可抽出一段或全部歷史
---

請執行 devlog keep（具名搬走）。這是使用者主動執行 `/devlog-tracker:keep` 時才做的事，不要自動觸發。

確認之前不要寫任何檔。這一輪本身是開著的 Round，永遠不要把它搬走；這一輪結束前仍要補 `### Summary` / `### Handoff` / `### Status`。

## 1. 讀檔、找出開著的 Round

1. 讀取 `.devlog/devlog.md` 全文。若檔案不存在，告知「目前沒有東西可 keep」，不要建立 `.devlog/` 或任何新檔，結束。
2. 開著的 Round：若 `.devlog/.round-open` 存在且有 `"round"` 數字，用那個編號；否則用 `devlog.md` 最後一個 `## Round <N>`。
3. 歷史 Round = 檔案裡除了開著的 Round 以外的所有 `## Round`。若沒有任何歷史 Round，告知「目前沒有東西可 keep」，不要建立新檔，結束。

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

## 5. 決定要搬走哪些區塊

**Full keep** = 確認後的範圍涵蓋每一個歷史 Round。否則是 episode keep。

**Round：** 把 `from`–`to` 裡每一個完整的 `## Round <N> — ...` 區塊（到下一個 `## ` 標題或檔案結尾、但不要吃進不該搬的區塊）列入搬走名單。不要改寫 Round 本文。

**專案摘要**（第一個 `## Round` 之前的文字）：

- episode keep：留在 `devlog.md`
- full keep：列入搬走名單，寫進具名檔時放在出處標頭之後、第一個 `## Round` 之前

**`## Checkpoint`：**

- 標題可解析出 `Round X-Y`（例如 `## Checkpoint（Round 10-20 摘要）`）：
  - X–Y 完全落在 `from`–`to` 內 → 搬走
  - 完全在外面 → 留在主檔
  - 橫跨切點 → 留在主檔，也不複製到具名檔
- 標題沒有可解析的 `Round X-Y`：只有當這塊位於「第一個被搬的 `## Round` 標題」與「最後一個被搬的 Round 結尾」之間時才搬走，否則留下。

不要改 `.checkpoint-state`。

## 6. 先寫具名檔，再改主檔

具名檔路徑：`.devlog/devlog.<name>.md`。開頭固定為：

```markdown
# Kept log

- source: `.devlog/devlog.md`
- rounds: <from>-<to>
- kept_at: <ISO 8601 時間戳，含時區>
```

`rounds` 是實際搬走的含端點範圍（不含開著的 Round）。`kept_at` 用現在時間。

接著依原順序、原文原樣接上步驟 5 的區塊。

然後：

1. 確認具名檔存在，且裡面有那些 `## Round` 標題。這一步失敗就停止，`devlog.md` 維持原樣。
2. 才從 `devlog.md` 刪掉已搬走的區塊。其餘保持原樣（除了下面 full keep 的標題改寫）。禁止先刪後寫。若刪除失敗、具名檔已寫成：告訴使用者兩份都還在，不要盲目重試刪除。
3. **Full keep：** 把留下的那一個開著 Round 的標題改成 `## Round 1`，時間戳與本文不動；若 `.devlog/.span-open` 存在就刪掉它。
4. **Episode keep：** 不要重編留下的 Round 編號（缺號可以）。若 `.span-open` 的 `round` 落在搬走範圍內，刪掉 `.span-open`；否則不要動它。
5. 不要動 `.enabled`、不要動 `.round-open`。

## 7. 回報並收尾這一輪

回報：具名檔路徑、搬走幾輪（哪些編號）、主檔目前剩幾輪。不要讀寫 `devlog.archive.md`。

然後在開著的那一輪補上 `### Summary` / `### Handoff` / `### Status` 再結束（Stop hook 仍會檢查）。
```

- [ ] **Step 2: Verify the command file against the spec**

From the repo root:

```bash
test -f commands/keep.md
grep -q 'description: 若這段 devlog 值得單獨留名' commands/keep.md
grep -q '確認之前不要寫任何檔' commands/keep.md
grep -q '.round-open' commands/keep.md
grep -q '仍要存' commands/keep.md
grep -q 'archive' commands/keep.md
grep -q '不要覆寫' commands/keep.md
grep -q '# Kept log' commands/keep.md
grep -q '禁止先刪後寫' commands/keep.md
grep -q '## Round 1' commands/keep.md
grep -q 'devlog.archive.md' commands/keep.md
grep -q '### Summary' commands/keep.md
```

Expected: `test` exits 0; every `grep -q` exits 0. If any grep fails, the omitted rule is missing — add it before committing.

- [ ] **Step 3: Commit**

```bash
git add commands/keep.md
git commit -m "$(cat <<'EOF'
feat: add /devlog-tracker:keep command

Let a named stretch of the working log move to devlog.<name>.md after confirm.
EOF
)"
```

---

### Task 2: Skill pointer and compact boundary

**Files:**
- Modify: `skills/devlog-tracker/SKILL.md` (frontmatter description; 檔案位置; new keep section after compact; agentflow table)
- Modify: `commands/compact.md` (one do-not-touch line)

**Interfaces:**
- Consumes: Task 1 `commands/keep.md` as the run-time steps keep should point at.
- Produces: SKILL description and body that mention keep; compact that will not sweep kept files.

- [ ] **Step 1: Point SKILL.md at keep**

In `skills/devlog-tracker/SKILL.md`, replace the frontmatter `description` with this exact one-line value (439 characters, under 1024):

```yaml
description: 在專案根目錄維護一份 devlog.md，把每一輪的請求、所做的決策與結果寫成永久紀錄。使用者下 /devlog-tracker:start 啟動這個專案的強制記錄後，Stop hook 會卡住每一輪的結束動作，逼 Claude 先把這輪寫進 devlog.md 才能結束；SessionStart hook 在 startup / resume / clear / compact / fork 時自動讀檔補齊進度；/devlog-tracker:pause 可暫停強制、/devlog-tracker:compact 可手動壓縮歸檔、/devlog-tracker:keep 可把有主題的一段搬走成 devlog.<name>.md；長任務有 Span Mode、長對話有 Checkpoint Mode 定期摘要。當使用者提到「devlog」「start」「keep」「記錄這輪」，或整個對話呈現需要長期追蹤、跨多個 session 接續的多輪開發工作時，主動使用此技能。
```

In `## 檔案位置`, after the archive bullet, add:

```markdown
- 具名保存：`.devlog/devlog.<name>.md`（`/devlog-tracker:keep` 搬走的主題檔；SessionStart 不讀這些檔）
```

Immediately after the compact section (after `只搬移，不刪除、不改寫內容`，before `## 跟原版 agentflow 的差異`) insert:

```markdown
## 具名保存：`/devlog-tracker:keep`

把一段（或全部歷史）從 `devlog.md` **搬走**成 `.devlog/devlog.<name>.md`，讓有主題的紀錄可以單獨留名。這不是 compact：compact 把舊的 `DONE` 輪次 append 進 `devlog.archive.md`；keep 寫的是一個主題一個檔，且從不寫 archive。步驟見 `commands/keep.md`。不要自動觸發。
```

In the agentflow 差異 table, change the last row from:

```markdown
| 歸檔觸發 | 依大小自動判斷 | 使用者主動下 `/devlog-tracker:compact` |
```

to:

```markdown
| 歸檔觸發 | 依大小自動判斷 | 使用者主動下 `/devlog-tracker:compact`；有主題要留名時用 `/devlog-tracker:keep` |
```

- [ ] **Step 2: Tell compact to leave kept files alone**

In `commands/compact.md`, append this sentence to the final paragraph (the one that starts with `不要在使用者沒有要求的情況下自動觸發`) so the paragraph becomes:

```markdown
不要在使用者沒有要求的情況下自動觸發這個流程；這是使用者主動執行 `/devlog-tracker:compact` 時才做的事。不要讀取或寫入 `.devlog/devlog.<name>.md` 具名檔（那是 `/devlog-tracker:keep` 的產物）。
```

Do not change compact's retain/move rules.

- [ ] **Step 3: Verify**

```bash
grep -q '/devlog-tracker:keep' skills/devlog-tracker/SKILL.md
grep -q 'devlog.<name>.md' skills/devlog-tracker/SKILL.md
grep -q '具名保存' skills/devlog-tracker/SKILL.md
grep -q '不要讀取或寫入' commands/compact.md
python3 -c "
import pathlib, re
text = pathlib.Path('skills/devlog-tracker/SKILL.md').read_text()
m = re.search(r'^description:\s*(.*)$', text, re.M)
assert m, 'missing description'
assert len(m.group(1)) <= 1024, len(m.group(1))
print('description length', len(m.group(1)))
"
```

Expected: all greps exit 0; python prints `description length` and a number `<= 1024`.

- [ ] **Step 4: Commit**

```bash
git add skills/devlog-tracker/SKILL.md commands/compact.md
git commit -m "$(cat <<'EOF'
docs: point the skill and compact command at keep

Keep is the named-move path; compact must not touch devlog.<name>.md.
EOF
)"
```

---

### Task 3: README and plugin listings

**Files:**
- Modify: `README.md` (特色 bullet, 使用 snippet, 目錄結構)
- Modify: `.claude-plugin/plugin.json` (`description`)
- Modify: `.claude-plugin/marketplace.json` (`plugins[0].description`)

**Interfaces:**
- Consumes: command name `/devlog-tracker:keep` from Task 1.
- Produces: user-facing and marketplace text that list keep next to start / pause / compact. Version stays `0.2.0`.

- [ ] **Step 1: README 特色 and 使用**

In `README.md`, immediately after the compact bullet (the line that starts with `- **\`/devlog-tracker:compact\`**`), insert:

```markdown
- **`/devlog-tracker:keep`**：若這段紀錄值得單獨留名，確認後把一段（或全部歷史）從 `devlog.md` 搬走成 `.devlog/devlog.<name>.md`。Claude 會依內容建議範圍與檔名，也可自訂。不是 compact（compact 仍是把舊的 `DONE` 輪次 append 進 `devlog.archive.md`）。細節見 [`docs/design/keep.md`](docs/design/keep.md)。
```

In `## 使用`, immediately after the compact fenced block and before `（以上都是完整的 namespace 形式…）`, insert this block (a prose line, then a fenced `/devlog-tracker:keep`, same pattern as the compact snippet above it):

````markdown
這段開發紀錄值得單獨留名時：

```
/devlog-tracker:keep
```
````

In `## 目錄結構` → `docs/design/`, add `keep.md` to the tree (keep the existing files, add one line):

```
│   ├── recording-moments.md   # 送出時 skeleton、正常收尾、意外 INTERRUPTED
│   └── keep.md                # 具名搬走成 devlog.<name>.md
```

Change `commands/` from:

```
    ├── start.md            # 開啟強制記錄（建立 .enabled、.checkpoint-state、.segment-state）
    ├── pause.md            # 暫停強制記錄
    └── compact.md          # 壓縮歸檔（保留 Checkpoint 區塊，不搬進 archive）
```

to:

```
    ├── start.md            # 開啟強制記錄（建立 .enabled、.checkpoint-state、.segment-state）
    ├── pause.md            # 暫停強制記錄
    ├── compact.md          # 壓縮歸檔（保留 Checkpoint 區塊，不搬進 archive）
    └── keep.md             # 具名搬走（確認後寫 devlog.<name>.md，再從主檔刪）
```

Do not list `keep-plan.md` in the tree (other `*-plan.md` files are also omitted).

- [ ] **Step 2: Plugin and marketplace descriptions**

In `.claude-plugin/plugin.json`, replace the `description` string with:

```json
"description": "在專案中維護 .devlog/devlog.md 逐輪對話紀錄；用 /devlog-tracker:start 明確開啟強制記錄，Stop hook 保證每輪都寫入，/devlog-tracker:pause 暫停、/devlog-tracker:compact 壓縮歸檔、/devlog-tracker:keep 把有主題的一段具名搬走；/clear 或開新 session 時自動讀檔補齊進度；長任務有 Span Mode、長對話有 Checkpoint Mode 定期摘要。"
```

In `.claude-plugin/marketplace.json`, replace the nested plugin `description` with the **same** string. Leave `"version": "0.2.0"` unchanged in both files.

- [ ] **Step 3: Verify**

```bash
grep -q '/devlog-tracker:keep' README.md
grep -q 'commands/keep.md' README.md || grep -q 'keep.md' README.md
grep -q 'docs/design/keep.md' README.md
python3 -c "
import json
p = json.load(open('.claude-plugin/plugin.json'))
m = json.load(open('.claude-plugin/marketplace.json'))
assert p['version'] == '0.2.0'
assert m['plugins'][0]['version'] == '0.2.0'
assert '/devlog-tracker:keep' in p['description']
assert p['description'] == m['plugins'][0]['description']
print('ok')
"
```

Expected: greps exit 0; python prints `ok`.

- [ ] **Step 4: Commit**

```bash
git add README.md .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "$(cat <<'EOF'
docs: list /devlog-tracker:keep in README and plugin manifests

EOF
)"
```

---

## Spec coverage (self-review)

| Spec section | Task |
|---|---|
| Command flow, confirm-then-write | Task 1 `commands/keep.md` §1–3, 6 |
| Open Round / nothing to keep | Task 1 §1 |
| Range, unfinished rounds, full vs episode | Task 1 §2, 4, 5 |
| Checkpoints + no `.checkpoint-state` edit | Task 1 §5 |
| Filename suggest / normalize / reserved / collision | Task 1 §2, 4 |
| Named file provenance header | Task 1 §6 |
| Write-named-first, full-keep Round 1, `.span-open` | Task 1 §6 |
| Boundary with compact / SessionStart / no auto-run | Task 1 §7; Task 2 SKILL + compact.md |
| SKILL / README / plugin.json / marketplace.json | Task 2, Task 3 |
| No new hooks or hook tests | Global Constraints; no hook tasks |
| Non-goals (copy, subdirectory, archive pull, second command) | Global Constraints; not implemented |

`docs/design/keep.md` already exists from brainstorming; no task rewrites it.
