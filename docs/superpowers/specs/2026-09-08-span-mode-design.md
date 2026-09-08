# Span Mode: Multi-Tick Round Spanning — Design Spec

## Problem

devlog-tracker's Stop hook currently treats every user message as its own
round: `round-start.sh` records `.devlog/devlog.md`'s content hash at the
start of each turn, and `enforce-devlog.sh` blocks (exit 2) unless that hash
has changed by the time Claude tries to end the turn. This is correct for
normal interactive chat, but breaks down for long-running automated work —
a `/loop` dynamic-mode run, a multi-phase `Workflow`, or any task where
Claude is woken up repeatedly by its own scheduling (`ScheduleWakeup`,
background-task notifications) rather than by a human typing a new message.
Under the current model, every one of those automated wakeups is a "round"
that demands a full devlog write or the turn gets blocked — for a loop
ticking every few minutes over hours, this either forces meaningless
writes on every tick or fights the enforcement mechanism.

The user wants an escape hatch modeled on `agfnow/agentflow`'s Ask/Reply
concept — one logical unit of work ("Ask") that can span many automated
continuations before it's genuinely done — without requiring a full devlog
write at every single one of those continuations.

## Constraint established during design

Claude Code's hook payloads (`UserPromptSubmit`, `Stop`) do not include any
field that distinguishes a genuine human-typed message from an automated
continuation (`ScheduleWakeup` firing, a background task notification,
etc.) — confirmed against the official hooks reference. `SessionStart` has
a `source` field (`startup`/`resume`/`clear`/`compact`/`fork`); no
equivalent exists for `UserPromptSubmit` or `Stop`. This rules out any
design that relies on the hook scripts detecting a tick's origin
structurally. The design below instead relies on Claude explicitly
declaring "I'm opening a span" and the hook mechanically enforcing a
tick-count-based safety valve — it does not attempt to distinguish an
automated tick from a genuine human message during an open span (see
Non-Goals).

## Goal

Let Claude declare "this Ask will span multiple automated continuations,"
during which the Stop hook does not require a devlog.md write on every
tick — but still guarantees devlog.md gets a lightweight write at least
every `max_silent_ticks` ticks, bounding how much work a mid-span crash can
lose.

## Non-Goals

- Detecting whether a given tick was triggered by automation vs. a genuine
  human message. Not possible today (see Constraint above) and explicitly
  out of scope for this iteration: while a span is open, ANY
  `UserPromptSubmit` — automated or human — is counted as one tick,
  uniformly. If a human interrupts an open span with an unrelated request,
  that interruption is not specially recognized; SKILL.md documents this
  as a known limitation (see Edge Cases).
- Editing a previously-written Round block. The closing write for a span
  is always a brand-new Round entry (see Decision: New Round on Close).
- A new slash command. Opening, maintaining, and closing a span is Claude's
  own responsibility per SKILL.md instructions, using the Write/Edit tools
  directly — consistent with how Round-writing itself already works today
  (no command gates the actual writing, only the overall `.enabled` switch
  does).

## Mechanism

### New file: `.devlog/.span-open`

JSON, written and maintained directly by Claude (not by a hook script):

```json
{
  "round": 12,
  "opened_at": "2026-09-08T21:40:00+08:00",
  "ticks_since_checkin": 0,
  "max_silent_ticks": 5
}
```

- `round`: the Round number (already written normally, Status
  `IN_PROGRESS`) that this span belongs to — used only for the
  SessionStart resume-context message, not for hook enforcement logic.
- `opened_at`: ISO 8601 timestamp, for the same resume-context message.
- `ticks_since_checkin`: integer, starts at 0 when Claude creates the file.
  Incremented by `round-start.sh`, reset to 0 by `enforce-devlog.sh` when a
  required write happens.
- `max_silent_ticks`: integer Claude chooses when opening the span (a
  reasonable default — e.g. 5 — unless the task's nature suggests
  otherwise). Not enforced to be within any particular range; a malformed
  or missing value is handled by the fail-open rule below.

### `hooks/scripts/round-start.sh` (UserPromptSubmit)

Existing behavior (write `.turn-start` with `cksum < devlog.md`) is
unchanged. New addition: if `.devlog/.span-open` exists, increment its
`ticks_since_checkin` field by 1 (read, parse, increment, write back).
Fail-open: any failure to read/parse/write `.span-open` here is silently
ignored — this script's existing fail-open discipline (never block
message submission) extends to this new logic.

### `hooks/scripts/enforce-devlog.sh` (Stop)

New branch inserted after the existing `開關檢查` (`.enabled` check) and
before the existing turn-marker/hash comparison logic:

- If `.devlog/.span-open` does not exist, or exists but is malformed
  (missing/non-numeric `ticks_since_checkin` or `max_silent_ticks`) →
  fall through to the existing hash-comparison logic unchanged (fail-open:
  a broken span file behaves as if there were no span).
- If `.span-open` exists, is well-formed, and
  `ticks_since_checkin < max_silent_ticks` → exit 0 immediately. devlog.md
  is not required to have changed this tick.
- If `.span-open` exists, is well-formed, and
  `ticks_since_checkin >= max_silent_ticks` → fall through to the existing
  hash-comparison logic (devlog.md must have changed since this tick's
  `.turn-start` marker, or block with exit 2 same as today). If that check
  passes (a write happened), additionally reset `.span-open`'s
  `ticks_since_checkin` to 0 before exiting 0.

No change to the block ordering established in the current file (loop
guard → 開關檢查 → per-check fail-open logic) — this is a new sub-branch
inside the existing 開關檽查-gated section, not a reordering.

### `hooks/scripts/session-start-devlog.sh` (SessionStart)

If `.devlog/.span-open` exists at session start (any matcher source:
startup/resume/clear/compact), prepend this fixed template (with `round`
and `opened_at` interpolated from the file's JSON) to the injected context,
before the Round history — this is a literal string the script echoes, not
Claude-composed prose:

```
⚠️ 有一個開啟中的 span：Round <round>，從 <opened_at> 開始，
還沒有正式結束。請先確認要繼續這個自動化任務，還是要明確關閉它
（刪除 .devlog/.span-open 並補寫收尾的 Round）。
```

Fail-open: if `.span-open` exists but is unreadable/malformed, skip this
note silently (existing script behavior — missing devlog.md already
exits 0 with no output; extend the same tolerance here).

### `skills/devlog-tracker/SKILL.md`

New section documenting:
- When to open a span: Claude judges that the current Ask is about to
  become a multi-tick automated run (starting a `/loop` dynamic-mode task,
  kicking off a `Workflow`, or any other self-scheduled continuation chain)
  — not for ordinary interactive back-and-forth.
- How to open one: write the current Round's number, `opened_at`, `0`, and
  a chosen `max_silent_ticks` to `.devlog/.span-open`, immediately after
  writing that Round's normal entry (Status `IN_PROGRESS`).
- What happens automatically while it's open (tick counting, the
  `max_silent_ticks` forced-write fallback) — so Claude understands it
  doesn't need to manually write anything on ordinary ticks, but MUST
  write something if the hook blocks (that means the silent-tick budget
  ran out).
- How to close one: once the Ask is genuinely done, write a **new** Round
  entry (Status `DONE`, Response summarizing the whole spanned period,
  User Input noting it's an automated continuation closeout — see Decision
  below) and delete `.devlog/.span-open`.
- The known limitation: a genuine human message arriving while a span is
  open is not specially detected — it's counted as an ordinary tick. If
  Claude notices mid-span that a new message is actually an unrelated
  human request (not a continuation of the automated task), it should
  close the span itself (delete `.span-open`, write a closing Round) before
  addressing the new request, rather than silently absorbing it into the
  open span.

## Decision: New Round on Close (not editing the opening Round)

When a span concludes, Claude writes a **new** Round entry rather than
editing the original Round's Status/Response in place. Reasons:
- Consistent with the project's existing append-only ethos (`/compact`
  explicitly only moves content, never rewrites it; nothing elsewhere in
  SKILL.md edits a past Round).
- Avoids fragile mid-file string-editing to locate and rewrite an
  arbitrary earlier Round block.
- Cost is cosmetic only (one extra Round entry whose User Input reads
  something like "（自動續接收尾，接續 Round 12）" instead of literal user
  text) — SKILL.md already permits non-literal User Input text.

## Known Risk: Bounded Data Loss, Not Zero Loss

If a session crashes while a span is open, at most `max_silent_ticks`
ticks' worth of activity is unrecorded (bounded by the tick-count
mechanism) — never the entire span's duration, regardless of how long the
span has been open. This is a smaller, known, and quantifiable version of
the same risk the pre-existing `PostToolUse`-hook caveat in SKILL.md
already documents (a round in progress when the session is killed loses
that round's in-flight detail) — Span Mode does not change that
existing caveat's scope, it just adds a second, tick-bounded version of it
for the silent-tick period.

## Edge Cases

- **`/pause` while a span is open**: `.enabled` is deleted; `enforce-devlog.sh`
  exits before ever inspecting `.span-open`, so behavior is unaffected.
  `commands/pause.md` additionally deletes `.devlog/.span-open` if present,
  so a later `/start` doesn't inherit a stale span referencing an old
  Round number.
- **`/compact` while a span is open**: unaffected — `.span-open` lives
  outside `devlog.md`/`devlog.archive.md` and is never touched by compact.
  The still-`IN_PROGRESS` Round that opened the span is retained by
  compact's existing "keep all non-DONE rounds" rule, unchanged.
- **Malformed `.span-open`**: treated as absent (fail-open) at every read
  site (`round-start.sh`'s increment, `enforce-devlog.sh`'s check,
  `session-start-devlog.sh`'s resume note).
- **A human message arrives while a span is open**: counted as an ordinary
  tick (Non-Goal, documented limitation in SKILL.md — see above).

## Testing

Extend `hooks/scripts/test-enforce-devlog.sh` (plain bash `assert`-based
self-check, no framework, matching the project's existing style) with:

1. Span open, `ticks_since_checkin` below `max_silent_ticks`, devlog.md
   untouched this tick → Stop allowed (exit 0); after `round-start.sh` runs
   once, `ticks_since_checkin` in `.span-open` is confirmed incremented.
2. Span open, `ticks_since_checkin` at/above `max_silent_ticks`, devlog.md
   untouched this tick → Stop blocked (exit 2).
3. Span open, `ticks_since_checkin` at/above `max_silent_ticks`, devlog.md
   IS touched this tick → Stop allowed (exit 0); `.span-open`'s
   `ticks_since_checkin` confirmed reset to 0 afterward.
4. No `.span-open` present → all 6 existing scenarios from Task 1/2 of the
   prior bug-fix plan still pass unchanged (regression check).
5. Malformed `.span-open` (non-numeric `ticks_since_checkin`) → treated as
   absent, falls through to normal enforcement (same as scenario with no
   span present).

## Files Touched (summary)

- `hooks/scripts/round-start.sh` — increment tick counter when span open
- `hooks/scripts/enforce-devlog.sh` — new branch: skip/force-then-reset
  based on tick count vs. threshold
- `hooks/scripts/session-start-devlog.sh` — resume-context note when a span
  is open
- `hooks/scripts/test-enforce-devlog.sh` — 5 new scenarios
- `skills/devlog-tracker/SKILL.md` — new section documenting span
  lifecycle, plus the documented known limitation
- `commands/pause.md` — also delete `.devlog/.span-open` if present
- No changes to: `commands/start.md`, `commands/compact.md`,
  `hooks/hooks.json`, either plugin manifest
