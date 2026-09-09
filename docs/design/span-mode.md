# Span Mode

Span Mode lets Claude declare an open "span" during long-running automated
work — a `/loop` dynamic-mode run, a multi-phase `Workflow`, or any task
where Claude is woken up repeatedly by its own scheduling (`ScheduleWakeup`,
background-task notifications) rather than by a human typing a new message.
While a span is open, the Stop hook does not require a devlog write on every
automated tick, but still guarantees one at least every `max_silent_ticks`
ticks — bounding how much work a mid-span crash can lose.

## Motivation

devlog-tracker's Stop hook normally treats every user message as its own
round: `round-start.sh` records `.devlog/devlog.md`'s content hash at the
start of each turn, and `enforce-devlog.sh` blocks (exit 2) unless that hash
has changed by the time Claude tries to end the turn. This is correct for
interactive chat, but breaks down for long-running automated work: every
automated wakeup would otherwise demand a full devlog write or the turn
gets blocked — for a loop ticking every few minutes over hours, this either
forces meaningless writes on every tick or fights the enforcement
mechanism.

Span Mode is a narrow, purpose-built answer to that one problem, modeled
loosely on `agfnow/agentflow`'s Ask/Reply concept (an Ask can span many
actions before it's genuinely done) but implemented independently for this
plugin's own constraints — see below.

## Design constraint

Claude Code's hook payloads (`UserPromptSubmit`, `Stop`) carry no field
that distinguishes a genuine human-typed message from an automated
continuation. `SessionStart` has a `source` field
(`startup`/`resume`/`clear`/`compact`/`fork`); no equivalent exists for
`UserPromptSubmit` or `Stop`. This rules out any mechanism that tries to
detect a tick's origin structurally — the design below instead relies on
Claude explicitly declaring an open span, with the hook enforcing a
tick-count safety valve rather than trying to infer intent.

One direct consequence: while a span is open, Span Mode does **not**
distinguish an automated tick from a genuine human message arriving
mid-span — both are counted the same way. A human interrupting an open
span with an unrelated request is not specially recognized; see Known
Limitations below.

## Mechanism

### `.devlog/.span-open`

A JSON file, written and maintained directly by Claude (via Write/Edit —
there is no dedicated slash command for this), never by a hook script:

```json
{
  "round": 12,
  "opened_at": "2026-09-08T21:40:00+08:00",
  "ticks_since_checkin": 0,
  "max_silent_ticks": 5
}
```

| Field | Meaning |
|---|---|
| `round` | The Round number (already written normally, Status `IN_PROGRESS`) this span belongs to. Used only for the SessionStart resume note, not for enforcement. |
| `opened_at` | ISO 8601 timestamp, also only for the resume note. |
| `ticks_since_checkin` | Starts at 0. Incremented by `round-start.sh` on every `UserPromptSubmit` while the file exists; reset to 0 by `enforce-devlog.sh` whenever a forced write succeeds. |
| `max_silent_ticks` | Chosen by Claude when opening the span — how many ticks it may stay silent before a write is forced. No enforced range; a reasonable default is in the single digits. |

### Hook behavior

- **`round-start.sh`** (`UserPromptSubmit`): unchanged existing behavior
  (record `devlog.md`'s content hash to `.turn-start`), plus: if
  `.span-open` exists and its `ticks_since_checkin` is a valid integer,
  increment it by 1.
- **`enforce-devlog.sh`** (`Stop`): a new check runs after the existing
  `.enabled` switch check and before the existing hash-comparison logic —
  if `.span-open` exists, is well-formed, and `ticks_since_checkin` is
  still below `max_silent_ticks`, the hook exits 0 immediately; devlog.md
  is not required to have changed. Once the counter reaches the threshold,
  the hook falls through to the normal hash comparison (forcing a write or
  blocking with exit 2 as usual), and resets the counter to 0 once a write
  succeeds.
- **`session-start-devlog.sh`** (`SessionStart`): if `.span-open` exists at
  session start (any source — startup/resume/clear/compact), a warning is
  prepended to the injected context naming the Round and open timestamp, so
  a resumed session knows there's an unclosed span.

A malformed or unreadable `.span-open` (missing fields, non-numeric values)
is treated as if no span exists at every read site — fail-open, matching
the rest of this plugin's hook scripts.

## Lifecycle

**Opening a span** is a judgment call, not a per-round default: Claude opens
one only when it knows the current Ask is about to become a multi-tick
automated run (starting a `/loop` dynamic-mode task, kicking off a
`Workflow`, or any other self-scheduled continuation chain) — never for
ordinary interactive back-and-forth. It writes the current Round's normal
entry first (Status `IN_PROGRESS`), then creates `.span-open` with that
Round's number, the current timestamp, `0`, and a chosen `max_silent_ticks`.

**While open**, nothing needs to be written manually on ordinary ticks — the
hooks handle the counting and the threshold automatically. If a tick gets
blocked, that means the silent-tick budget ran out; any write (even one
line) resolves it and resumes normal silent operation.

**Closing a span**, once the Ask is genuinely done, always means writing a
**new** Round entry — never editing the Round that opened the span. This
keeps the append-only convention the rest of devlog.md follows (`/compact`
only ever moves content, nothing edits a past Round in place). The closing
Round's User Input can note that it's an automated-continuation closeout
(e.g. "（自動續接收尾，接續 Round 12）"); its Summary (human) and Handoff
(next Claude) summarize the whole spanned period. `.span-open` is deleted once this closing Round is written.

## Known Limitations

- **No human-vs-automated distinction.** As noted above, this is a
  fundamental constraint of the current hook API, not an oversight. If
  Claude notices mid-span that an incoming message is an unrelated human
  request rather than a continuation of the automated task, it should close
  the span itself (delete `.span-open`, write a closing Round) before
  addressing the new request, rather than silently absorbing it into the
  open span.
- **Bounded, not zero, data loss on crash.** If a session crashes while a
  span is open, at most `max_silent_ticks` ticks' worth of activity is
  unrecorded — never the whole span's duration, however long it's been
  open. This is a smaller, quantifiable version of the same risk
  `skills/devlog-tracker/SKILL.md` already documents for an ordinary round
  killed mid-flight; Span Mode doesn't change that existing risk, it adds a
  second, tick-bounded version of it for the silent-tick period.
- **Zero-padded tick values aren't handled.** If `.span-open` is
  hand-edited into a state where `ticks_since_checkin` is a zero-padded
  numeral (e.g. `"08"`), bash's arithmetic evaluation reads it as octal and
  errors on invalid digits — `round-start.sh` stops incrementing that span's
  counter (fail-open holds: no crash propagates, no block occurs, and the
  span self-heals once the stalled value crosses `max_silent_ticks` via the
  normal fallback path). Not reachable via the documented write path, since
  neither script ever writes a zero-padded value.

## Files

| File | Role |
|---|---|
| `hooks/scripts/round-start.sh` | Increments the tick counter |
| `hooks/scripts/enforce-devlog.sh` | Checks the counter, enforces the threshold, resets on write |
| `hooks/scripts/session-start-devlog.sh` | Resume-context note when a span is left open |
| `hooks/scripts/test-enforce-devlog.sh` | Self-check covering the tick-threshold behavior |
| `hooks/scripts/test-session-start-devlog.sh` | Self-check covering the resume-note behavior |
| `skills/devlog-tracker/SKILL.md` | Authoring instructions for Claude (when/how to open, maintain, and close a span) |
