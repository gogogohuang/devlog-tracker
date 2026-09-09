# Checkpoint Mode (with Round Segments)

Two related additions to devlog-tracker's recording format, both aimed at
the same complaint: a long-running interaction (a single sprawling round,
or a session that's accumulated many rounds) leaves `devlog.md` hard to
reconstruct from — either because one round's closing summary is a single
end-of-round summary hiding everything that happened along the way, or
because skimming dozens of Round entries to find "what actually got done
in the last hour" is slow.

- **Round Segments** answer the first problem: within one round, write
  incremental sub-sections as work progresses instead of a single
  end-of-round summary.
- **Checkpoint Mode** answers the second: periodically insert a summary
  block covering the last stretch of rounds, with a hook-enforced safety
  net so it doesn't get skipped indefinitely on a long session.

## Round Segments

**Mechanism: authoring convention plus a silence valve.** When to write a
segment is still Claude's judgment. The Stop-hook content-hash check only
cares that `devlog.md` changed by end of turn. Mid-round, if the file's
hash is unchanged for `max_silent_seconds` (default 900), `segment-watch.sh`
blocks the next tool until something is appended — see
[`segment-watch.md`](segment-watch.md).

**Format** (added to `skills/devlog-tracker/SKILL.md`): for a round that
involves multiple distinct phases (exploration, a decision, an
implementation step, verification), write each as its own timestamped
sub-section under the round as that phase completes, instead of holding
everything until the final Summary / Handoff:

```markdown
## Round 15 — 2026-09-09T09:00:00+08:00

### User Input
幫我重構 XXX 模組

### 段落 1 - 09:12
讀完現有程式碼，發現三個地方耦合...

### 段落 2 - 09:20
決定拆成 A/B 兩個檔案，理由...

### 段落 3 - 09:35
完成拆分，跑測試全過

### Summary
把 XXX 模組拆成 A/B 兩個檔案，測試全過。

### Handoff
#### 決策
拆成 A/B，理由是三處耦合都集中在同一個檔。
#### 檔案
新增 a.ts、b.ts；刪除 xxx.ts。尚未 commit。
#### 現況
拆分完成，測試全過。

### Status
DONE
```

**When to write a segment** is Claude's judgment call — "a meaningful
stage result," the same bar `Status: IN_PROGRESS` already uses — not a
rule triggered by elapsed time or tool-call count. A short round with no
real phases still gets Summary / Handoff as today, with no segment headings; segments are for
rounds long enough that a single end-of-round summary would hide real
intermediate decisions.

**Side effect:** because segments are written as the round proceeds
rather than all at once at the end, a crash mid-round now loses at most
the in-progress segment, not the whole round's work — a smaller version
of the existing "round killed mid-flight" risk `SKILL.md` already
documents.

## Checkpoint Mode

### `.devlog/.checkpoint-state`

A JSON file, created by `/devlog-tracker:start` alongside `.enabled`,
fully owned and maintained by the hooks (unlike `.span-open`, which
Claude writes directly — there's no equivalent slash command or manual
step here):

```json
{ "rounds_since_checkpoint": 0, "max_silent_rounds": 20, "checkpoint_marker_count": 0 }
```

| Field | Meaning |
|---|---|
| `rounds_since_checkpoint` | Starts at 0. Incremented by `round-start.sh` on every `UserPromptSubmit` that isn't being silently skipped by an open Span Mode span (see Interaction with Span Mode below). Reset to 0 by `enforce-devlog.sh` whenever it detects a new `## Checkpoint` block was actually added (see below) — not just "some write happened," since every ordinary round already causes a write and would otherwise reset the counter every single round, defeating the threshold entirely. |
| `max_silent_rounds` | Default `20`. Claude may edit this file directly to change the threshold for a given project/session, the same way it chooses `max_silent_ticks` when opening a span — no dedicated slash command. |
| `checkpoint_marker_count` | Starts at 0. The last count of `^## Checkpoint` headings `enforce-devlog.sh` observed in `devlog.md`. Compared against the live count each time the hook runs to detect whether a *new* checkpoint block was just added, independent of ordinary round writes. |

### Hook behavior

- **`round-start.sh`** (`UserPromptSubmit`): existing behavior unchanged,
  plus: if `.enabled` exists, `.checkpoint-state` exists and is
  well-formed, and this tick is not one that an open, under-budget Span
  Mode span would cause `enforce-devlog.sh` to silently pass through,
  increment `rounds_since_checkpoint` by 1.
- **`enforce-devlog.sh`** (`Stop`): after the existing hash-comparison
  logic passes (the round's own content was written — this always runs
  first, unchanged), a new check runs: count `^## Checkpoint` headings in
  `devlog.md` and compare against the stored `checkpoint_marker_count`.
  - If the live count is **higher** — Claude added a new checkpoint block
    this round (whether proactively or after being blocked) — reset
    `rounds_since_checkpoint` to 0 and update `checkpoint_marker_count` to
    the new count.
  - Otherwise, if `rounds_since_checkpoint >= max_silent_rounds`, block
    (`exit 2`) with a message asking Claude to append a
    `## Checkpoint（Round X-Y 摘要）` block summarizing the rounds since
    the last checkpoint. Claude adds it and tries to end the turn again;
    this time the marker-count comparison above catches the new heading
    and resets the counter, so the retry passes.
- A malformed or missing `.checkpoint-state` is treated as "no checkpoint
  tracking" at every read site — fail-open, matching every other hook
  script in this plugin.

### Interaction with Span Mode

While a span is open and under its `max_silent_ticks` budget, Span Mode's
whole point is that the Stop hook does *not* demand a write every tick.
Checkpoint enforcement piling a second, independent demand on top of that
would defeat it. So: `rounds_since_checkpoint` is only incremented on
ticks that are *not* being silently passed through by an open span — i.e.
the same ticks where the normal hash-comparison logic actually runs.
Once the span closes (or expires past `max_silent_ticks` and falls
through to normal enforcement), checkpoint counting resumes as usual.

### Lifecycle

Checkpoint tracking is always on once `/devlog-tracker:start` has been
run (no separate opt-in, unlike Span Mode which is judgment-triggered per
task) — it's meant to backstop any long interactive session, not just
automated runs. `/devlog-tracker:pause` should also stop checkpoint
enforcement (mirroring how it stops round enforcement); `.checkpoint-state`
is left in place so counting resumes where it left off on
`/devlog-tracker:start` again, rather than resetting.

### Known Limitations

- **Heading text is the only verified signal.** The hook confirms a new
  line starting with `## Checkpoint` was added — it doesn't check the
  block has a `Round X-Y` range, a real summary, or accurate content.
  Getting the substance right is on Claude, same trust level as every
  other devlog entry this plugin enforces the presence of but not the
  quality of.
- **A checkpoint written for unrelated reasons still counts.** If Claude
  writes a line starting with `## Checkpoint` for any other reason (e.g.
  quoting this design doc into devlog.md), the counter resets exactly as
  if a genuine summary had been written. Considered acceptable: no
  plausible reason for that heading text to appear other than an actual
  checkpoint.

## Files

| File | Role |
|---|---|
| `hooks/scripts/round-start.sh` | Increments `rounds_since_checkpoint` (skipping ticks silently passed by an open span) |
| `hooks/scripts/enforce-devlog.sh` | Detects a new `## Checkpoint` heading (resets the counter) and enforces the threshold after normal round enforcement passes |
| `commands/start.md` | Creates `.checkpoint-state` alongside `.enabled` |
| `skills/devlog-tracker/SKILL.md` | Authoring instructions for Round Segments and Checkpoint blocks |
| `hooks/scripts/test-enforce-devlog.sh` | Self-check covering the checkpoint threshold (block, reset, paused during an open span) |
