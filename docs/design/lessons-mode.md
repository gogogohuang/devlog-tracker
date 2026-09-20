# Lessons Mode（開發歷程教訓，非架構知識庫）

An opt-in, default-off mode that lets Claude record *process* lessons —
difficulties hit and how they were resolved, decisions that took a detour
before landing — so a future session can avoid repeating them. This is
explicitly **not** a knowledge base for design/architecture decisions;
`docs/design/*.md` stays the SSOT for those
(`docs/design/devlog-as-ssot-assessment.md` Non-goals #6 is unchanged by
this doc). Lessons Mode is about the *development process itself*, not
the *system being developed*.

## Relationship to existing modes

| | Span Mode | Checkpoint Mode | Lessons Mode |
|---|---|---|---|
| Manages | quiet ticks during automated continuation | periodic cross-round progress digest | cross-time process pitfalls, opt-in |
| Default | off (opened per task) | on once `.enabled` is set | **off**, separate opt-in even after `.enabled` |
| Trigger | Claude declares a span | round count threshold | BLOCKED→resolved or a self-judged detour (self-judged); cumulative workspace-drift or BLOCKED-round signals sharing one mechanical counter, plus a separate one-shot mechanical BLOCKED→resolved print (see below) |
| Enforced by hook? | yes (tick budget) | yes (round budget) | **no** — fully Claude's discretion |
| Storage | `devlog.md` inline | `devlog.md` inline (`## Checkpoint`) | separate per-topic files |

## Enable / disable

- New state flag: `.devlog/.lessons-enabled`.
- **Nested under the main switch**: `/devlog-tracker:lessons-on` requires
  `.devlog/.enabled` to already exist. If it does not, refuse with a
  message telling the user to `/devlog-tracker:start` first — there is no
  Round/Status data to detect a "BLOCKED→resolved" transition against
  without the main switch on.
- `/devlog-tracker:lessons-off` removes `.lessons-enabled` only. It never
  touches `devlog.lessons.*.md` files or the `## Lessons 索引` block —
  same non-destructive posture as `/devlog-tracker:pause` toward
  `devlog.md`.
- `/devlog-tracker:pause` (the main switch) does **not** implicitly
  disable Lessons Mode's flag file, but since Lessons Mode's trigger logic
  only runs during Round close and Stop enforcement is what pause turns
  off, a paused project produces no new lessons regardless — consistent
  with "no Round activity to learn from."

## When Claude should consider writing a lessons entry

Only while `.lessons-enabled` exists. Four trigger signals: two advisory
(self-judged, hook cannot detect them), two mechanical (hook-counted,
print-only, sharing one counter — see 「機制性訊號：共用計數器」below), plus
one further mechanical print that is not counted (see 「機制性提示：
BLOCKED→解開」below).

1. **`BLOCKED` → resolved (self-judged framing).** The previous historical
   Round's `### Status` was `BLOCKED` and this Round's `### Status` is not.
   Since 2026-09-20 this transition is *also* mechanically detected and
   printed by `round-start.sh` at the start of the next Round (see 「機制性
   提示：BLOCKED→解開」below) — the self-judged version above still applies
   in the same Round where the transition happens, before the hook gets a
   chance to say anything one Round later.
2. **Self-judged detour.** Claude decides, at Round close, that this round
   took a real wrong turn before landing on the right approach, and that
   future-Claude would benefit from knowing to skip the wrong turn.

Writing an entry is **never required** to close a Round (unlike
`#### 工作區`/`#### 檔案`, which are machine-verified when applicable).
Skipping it is not an error and produces no warning.

## 機制性訊號：共用計數器（顧問式，非強制）

第三、四種考慮寫一筆的訊號，跟上面兩種不同：不是 Claude 自我判斷，而是 hook 用既有的機器
訊號累積計數、達門檻才印一句**建議**——依然不強制寫、不阻擋任何工具。兩個來源共用同一個
狀態檔、同一個計數器、同一個門檻——達門檻時印出的訊息不分辨是哪個來源觸發的（或兩者都有
貢獻），這是刻意的簡化。

- **來源一：工作區漂移**。`round-start.sh` 既有的工作區漂移偵測（`docs/design/continue.md`
  「同輪工作區漂移偵測」）。每次偵測到上一輪 Handoff 的「工作區」跟目前 git 狀態不符
  （跟產生 `.workspace-mismatch` 同一時機），只要 `.lessons-enabled` 存在，就把計數器 +1。
- **來源二：BLOCKED 輪次累積**。`round-start.sh` 開新一輪時，讀「剛收尾那一輪」的
  `### Status`；只要 `.lessons-enabled` 存在且該值是 `BLOCKED`，就把同一個計數器 +1——
  不要求「這輪沒寫 lessons 才算」，只要 Status 是 `BLOCKED` 就算一次，不 correlate 是否
  隨後呼叫過 `lessons-append.sh`。
- **狀態檔**：`.devlog/.lessons-advisory-state`，欄位 `count`（累積次數）、`threshold`
  （門檻，預設 3）。命名刻意語意中性（不叫 `drift`），因為它現在涵蓋兩種來源。
- **門檻**：`threshold` 欄位，預設 3，可用 `/devlog-tracker:lessons-drift <次數>` 調整
  （跟 `checkpoint`/`segment-watch` 同款指令，隸屬 Lessons Mode：沒開會回報
  `LESSONS_NOT_ENABLED`）。
- **達門檻時**：`round-start.sh` 印一行建議（「流程訊號已累積出現 N 次（門檻 M），可考慮
  用 lessons-append.sh 記一筆流程教訓，非強制。」），並把 `count` 重置為 0——Claude 仍可
  略過不寫，這一輪的收尾完全不受影響。
- **累積而非連續**：計數不要求連續發生，任何時間點的訊號都算一次；`.lessons-advisory-state`
  跨 Round 持續存在，只有達門檻印完那次才歸零。
- **只在 Lessons Mode 開著時計數**：`.lessons-enabled` 不存在時，`round-start.sh`
  完全不碰 `.lessons-advisory-state`——沒開 Lessons Mode 就沒有任何額外開銷或提示。
- **狀態檔建立時機**：`/devlog-tracker:lessons-on` 每次執行時，若 `.lessons-advisory-state`
  不存在就建立（`{"count": 0, "threshold": 3}`）——涵蓋「剛開 Lessons Mode」跟「舊專案升級
  到這個版本」兩種情況。`/devlog-tracker:lessons-off` 不動這個檔案，維持既有的非破壞性原則。
- **`/devlog-tracker:status`** 會多印一行 `LESSONS_ADVISORY=<count>/<threshold>`。

### 舊檔名遷移：`.lessons-drift-state` → `.lessons-advisory-state`

這個狀態檔以前只有工作區漂移一種來源，叫 `.lessons-drift-state`（欄位
`mismatch_count`）。加入 BLOCKED 累積這第二種來源後改名成語意中性的
`.lessons-advisory-state`（欄位 `count`）。既有專案不會歸零重來：`round-start.sh` 跟
`lessons-drift-set.sh` 在讀寫新檔之前，都會先呼叫共用的 `lessons_advisory_migrate`
（`core/scripts/lessons-advisory-state.sh`）——只有新檔不存在且舊檔存在時才搬遷（讀舊欄位、
寫新檔、刪舊檔），冪等、只在 `.lessons-enabled` 存在時處理。

## 機制性提示：BLOCKED→解開

跟上面「共用計數器」的兩個來源不同，這個訊號**每次偵測到就印，不經過門檻計數**——因為它
本身是一次性事件（一次轉變），不是可以累積的次數。`round-start.sh` 開新一輪時，額外比對
「上上一輪」跟「剛收尾那一輪」的 `### Status`：上上一輪是 `BLOCKED`、剛收尾那一輪不是
`BLOCKED`，就印一句提示（「上一輪從 BLOCKED 解開了。可考慮用 lessons-append.sh 記一筆這次
卡在哪、怎麼解開，非強制。」）。只在 `.lessons-enabled` 存在時檢查；需要兩輪歷史紀錄才能
判斷，剛開 Lessons Mode 或 devlog.md 只有一輪歷史時不會出現（冷啟動限制）。

**這個提示天生晚一輪出現**：`enforce-devlog.sh`（Stop hook）exit 0 時印的內容不會送回
Claude 的對話 context，只有 `round-start.sh`（UserPromptSubmit）的 stdout 不論 exit code
都會被注入 context——所以這個訊號必須放在下一輪開始時印，而不是在 BLOCKED 解開的那一輪
Stop 當下。

## Storage: per-topic files, mirroring `keep`

Path: `.devlog/devlog.lessons.<topic>.md`, same directory as `devlog.md`
and the `keep`-produced `devlog.<name>.md` files, but a distinct
`lessons.` infix so the two families never collide on disk or in naming
rules.

`<topic>` follows the same normalization and rejection rules as `keep`'s
`<name>` (`docs/design/keep.md` "Filenames"): lowercase ASCII kebab-case
suggested by Claude from the entry's content, 2–4 segments; user-typed
input strips a leading `devlog.lessons.` / trailing `.md`; rejects empty,
containing `/`, `\`, `..`, or over 64 characters. `archive` and `lessons`
(the bare infix) are additionally reserved topic names.

### File shape

```markdown
# Lessons: <topic>

- source: `.devlog/devlog.md`

## <ISO 8601 timestamp with offset>
<free prose, no fixed subsections — what went wrong / how it resolved /
what to do differently next time, in whatever length the content needs>

## <ISO 8601 timestamp with offset>
<next entry, same file, same topic, later in time>
```

One file accumulates every entry ever recorded under that topic, oldest
first. A new topic gets a new file; an existing topic's file gets a new
`##` block appended.

## `## Lessons 索引` in `devlog.md`

Mirrors `## Kept 索引` (`docs/design/keep.md` "Kept index") but at
**per-file**, not per-entry, granularity — an index rebuilt fully each
time an entry is written, summarizing that topic file's latest state:

```markdown
## Lessons 索引
- `devlog.lessons.<topic>.md`：<N> 則，最新一則「<最新一筆的第一句>」（updated_at <ISO 8601 timestamp>）
```

- **Always rebuilt, never duplicated** — same rule as `## Kept 索引`:
  strip any existing trailing `## Lessons 索引` block, re-derive one line
  per `devlog.lessons.*.md` file that currently exists on disk (by
  scanning its `## <timestamp>` headers: count = N, title = first
  non-empty line of the body under the *last* such heading), then
  reprint the whole block.
- **Title, not full text** (Q10): the index line is only the derived
  title of the most recent entry, not its full body — matches the
  "SessionStart injects title/summary, full text on demand" decision.
  There is no separate title field to author; it is always derived from
  the entry's own first sentence (up to the first `。`/`.`/newline).
- **Not reconciled with the filesystem.** A hand-deleted
  `devlog.lessons.<topic>.md` leaves a ghost line until the next
  lessons-append call happens to re-scan and notice it is gone — same
  known limitation as `## Kept 索引`'s ghost rows.
- **SessionStart surfaces this block**, not the named files' content —
  same mechanism `session-start-devlog.sh` already uses for
  `## Kept 索引` (track `last_lessons` alongside `last_kept`, print the
  block the same way). Full entry text requires the on-demand read below.

## Reading lessons on demand

New command `/devlog-tracker:lessons [<topic>]`:

- No argument: print the current `## Lessons 索引` block (or "沒有任何
  lessons 紀錄" if empty/absent).
- With `<topic>`: read and print `.devlog/devlog.lessons.<topic>.md` in
  full (all entries, oldest first). Unlike `/devlog-tracker:resume`, this
  is a **plain read** — no workspace/`工作區` verification, no "wait for
  confirmation before acting on 下一步" flow, because a lessons file is
  reference material, not a paused work topic. If the file does not
  exist, name the topics that do (from the index) and stop.

## Write mechanism

`core/scripts/lessons-append.sh --topic <topic> --text <text>`:

1. `[ -f .devlog/.enabled ]` else exit 1 (`NOT_ENABLED`).
2. `[ -f .devlog/.lessons-enabled ]` else exit 1 (`LESSONS_NOT_ENABLED`).
3. Normalize/validate `<topic>` per the rules above; exit 1 with reason on
   rejection.
4. Create `.devlog/devlog.lessons.<topic>.md` with the header shown above
   if it does not already exist.
5. Append a `## <ISO 8601 timestamp>` block with `<text>` as its body.
6. Rescan all `devlog.lessons.*.md` files and rebuild `## Lessons 索引` in
   `devlog.md` (strip old block if present, append the freshly derived
   one at the end of the file).

### Additional advisory output

Besides `PATH=...`, the script may print up to two more purely informational
lines (never blocking, never required):

- when the just-appended topic file's entry count is a multiple of 3, a
  line suggesting the topic is mature enough to become a
  `docs/design/*.md` decision instead;
- when this call created a **brand-new** topic file (the topic didn't exist
  before) and at least one other topic file already exists, a
  `NEW_TOPIC。既有主題：...` line listing the other topics, so Claude can
  choose to reuse one instead of fragmenting the same subject across
  files.

This script is **never wired into `claude/hooks.json`** — nothing calls it
automatically. Claude invokes it directly at Round close, the same way
`keep-move.sh` is only ever invoked by `commands/keep.md`, not a hook.
Failing to call it is not an error; there is no enforcement path that
would notice.

## Growth control

No compaction/archival mechanism is designed now (deliberately deferred —
see the grilling session that produced this doc, Q9). Two things already
bound growth without one:

1. **Default off, and writes are advisory** — an inactive or
   little-triggered project accumulates nothing.
2. **Per-topic splitting** (this doc's whole storage design) means growth
   is distributed across many small files instead of one ever-growing
   one, which is the direct answer to "檔案會一直變大" that motivated
   asking for per-topic storage in the first place.

If a topic file does grow large in practice, revisit then — not now.

## Known limitations

- **`BLOCKED`→resolved detection needs a historical Round to compare
  against.** The very first Round after `/devlog-tracker:lessons-on` has
  no prior Round in the same continuity to compare Status against if
  Lessons Mode was just turned on mid-stream; this is a cold-start gap,
  not a bug.
- **Self-judged detours are entirely unverifiable**, by design (Q1/Q5) —
  same posture as `#### 決策` today. A future session cannot tell whether
  a topic file's absence means "nothing went wrong" or "Claude judged it
  not worth writing."
- **Ghost `## Lessons 索引` rows** on manual file deletion, same as
  `## Kept 索引`.
- **BLOCKED→resolved 機械提示天生晚一輪出現**（見「機制性提示：BLOCKED→解開」），且需要
  兩輪歷史紀錄才能判斷——剛開 Lessons Mode 或 devlog.md 只有一輪歷史時不會出現。
- **共用計數器達門檻時無法分辨來源**——工作區漂移跟 BLOCKED 輪次累積打同一個計數器，印出的
  建議不會說是哪一種（或兩者都有貢獻），這是刻意的簡化（見「機制性訊號：共用計數器」）。

## Non-goals

- Becoming a design/architecture knowledge base — `docs/design/*.md`
  stays the SSOT for that (unchanged from
  `devlog-as-ssot-assessment.md`).
- Any hook-level enforcement of when an entry must be written.
- A compaction/archive mechanism for `devlog.lessons.*.md` in v1.
- Fixed subsections within an entry (no `問題`/`原因`/`解法` template) —
  free prose only.
- A user-tunable "how many silent Rounds before nudging a lessons entry"
  counter — unlike Checkpoint Mode, there is no silent-count nudge here at
  all; writing is opt-in per Round, not periodically demanded.
  **Revised** (see 「機制性訊號：共用計數器」above): this bullet
  excluded a *round-silence* counter specifically, mirroring Checkpoint
  Mode's shape. It did not anticipate differently-shaped signals —
  cumulative 工作區-mismatch occurrences, and separately, cumulative
  `BLOCKED`-round occurrences — each of which already has an
  unambiguous, existing machine signal (`.workspace-mismatch`,
  `docs/design/continue.md`; and the just-closed round's `### Status`
  value, respectively) that round-silence never had. A count-based
  *advisory print only*, sharing one counter/threshold across both
  sources, is added for those cases; round-silence counting and
  self-judged detours are otherwise unchanged by this revision.

## Files

| File | Role |
|---|---|
| `commands/lessons-on.md` | `/devlog-tracker:lessons-on`: create `.lessons-enabled`, refuse if `.enabled` absent |
| `commands/lessons-off.md` | `/devlog-tracker:lessons-off`: remove `.lessons-enabled` only |
| `commands/lessons.md` | `/devlog-tracker:lessons [<topic>]`: index or full-file read |
| `core/scripts/lessons-on.sh` / `lessons-off.sh` | Flag-file scripts, mirroring `start-devlog.sh` / `pause-devlog.sh` |
| `core/scripts/lessons-append.sh` | Create/append a topic file; rebuild `## Lessons 索引` |
| `core/scripts/session-start-devlog.sh` | Track `last_lessons` alongside `last_kept`; surface `## Lessons 索引` in the excerpt |
| `skills/devlog-tracker/SKILL.md` | New section: what Lessons Mode is, the two trigger signals, that it is opt-in and never hook-enforced |
| `docs/design/lessons-mode.md` | This spec |
| `commands/lessons-drift.md` | `/devlog-tracker:lessons-drift <次數>`: adjust the drift-nudge threshold |
| `core/scripts/lessons-advisory-state.sh` | Shared `lessons_advisory_migrate`/`lessons_advisory_bump` helpers, sourced by `round-start.sh` and `lessons-drift-set.sh` |
| `core/scripts/lessons-drift-set.sh` | Migrates then sets `.lessons-advisory-state`'s `threshold`, mirroring `checkpoint-set.sh` |
| `core/scripts/round-start.sh` | Bumps the shared `.lessons-advisory-state` counter on workspace-drift mismatch and on a just-closed BLOCKED round; prints a one-shot BLOCKED→resolved advisory |
| `core/scripts/lessons-on.sh` | Migrates, then creates `.lessons-advisory-state` with defaults if missing |
| `core/scripts/status-devlog.sh` | Also prints `LESSONS_ADVISORY=<count>/<threshold>` |
| `core/scripts/lessons-append.sh` | Also prints the topic-repeat and new-topic advisories described above |

No `claude/hooks.json` changes beyond what `session-start-devlog.sh` already
does — `lessons-append.sh` is Claude-invoked only, same as `keep-move.sh`.
