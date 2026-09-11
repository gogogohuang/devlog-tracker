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
| Trigger | Claude declares a span | round count threshold | BLOCKED→resolved, or a self-judged detour |
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

Only while `.lessons-enabled` exists. Two trigger signals, both **advisory
— never hook-enforced**:

1. **`BLOCKED` → resolved.** The previous historical Round's `### Status`
   was `BLOCKED` and this Round's `### Status` is not. This is the one
   mechanically observable signal (a plain Status-string comparison), but
   it is *not* used to force a write — it is only a prompt to Claude, in
   the same SKILL.md sense as "Round Segments: 有意義的階段性結果" already
   is a self-judged, undetected-if-skipped convention.
2. **Self-judged detour.** Claude decides, at Round close, that this round
   took a real wrong turn before landing on the right approach, and that
   future-Claude would benefit from knowing to skip the wrong turn.

Writing an entry is **never required** to close a Round (unlike
`#### 工作區`/`#### 檔案`, which are machine-verified when applicable).
Skipping it is not an error and produces no warning.

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

`hooks/scripts/lessons-append.sh --topic <topic> --text <text>`:

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

This script is **never wired into `hooks/hooks.json`** — nothing calls it
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
- **No cross-topic search.** `/devlog-tracker:lessons <topic>` requires
  knowing (or reading the index for) the topic name; there is no
  full-text search across all lesson files.

## Non-goals

- Becoming a design/architecture knowledge base — `docs/design/*.md`
  stays the SSOT for that (unchanged from
  `devlog-as-ssot-assessment.md`).
- Any hook-level enforcement of when an entry must be written.
- A compaction/archive mechanism for `devlog.lessons.*.md` in v1.
- Fixed subsections within an entry (no `問題`/`原因`/`解法` template) —
  free prose only.
- A user-tunable "how many silent Rounds before nudging a lessons entry"
  counter — unlike Checkpoint Mode, there is no silent-count nudge here
  at all; writing is opt-in per Round, not periodically demanded.

## Files

| File | Role |
|---|---|
| `commands/lessons-on.md` | `/devlog-tracker:lessons-on`: create `.lessons-enabled`, refuse if `.enabled` absent |
| `commands/lessons-off.md` | `/devlog-tracker:lessons-off`: remove `.lessons-enabled` only |
| `commands/lessons.md` | `/devlog-tracker:lessons [<topic>]`: index or full-file read |
| `hooks/scripts/lessons-on.sh` / `lessons-off.sh` | Flag-file scripts, mirroring `start-devlog.sh` / `pause-devlog.sh` |
| `hooks/scripts/lessons-append.sh` | Create/append a topic file; rebuild `## Lessons 索引` |
| `hooks/scripts/session-start-devlog.sh` | Track `last_lessons` alongside `last_kept`; surface `## Lessons 索引` in the excerpt |
| `skills/devlog-tracker/SKILL.md` | New section: what Lessons Mode is, the two trigger signals, that it is opt-in and never hook-enforced |
| `docs/design/lessons-mode.md` | This spec |

No `hooks/hooks.json` changes beyond what `session-start-devlog.sh` already
does — `lessons-append.sh` is Claude-invoked only, same as `keep-move.sh`.
