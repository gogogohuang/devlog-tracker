# Reply Fold

Reply Fold lets Claude declare, right after closing out a Round, that the
Round ended specifically because it asked the user a plain-text question and
is waiting for their very next message to answer it. When that next message
arrives, `round-start.sh` folds it into the *same* Round as a `### 段落`
block instead of opening a new `## Round` — so a "Claude asks, user answers"
exchange reads as one continuous Round instead of being split across two.

## Motivation

devlog-tracker normally treats every `UserPromptSubmit` as the start of a
new Round: one user message, one `## Round`. That is the right default for
ordinary requests, but it splits a single logical exchange in two whenever
Claude ends a turn with a clarifying question instead of a tool call — Stop
fires, the Round closes with its own Summary/Handoff/Status, and the user's
answer becomes a brand-new Round with no structural link back to the
question it's answering. Reading the log back, the question and its answer
look like two unrelated turns.

This does **not** cover Claude asking via the `AskUserQuestion` tool: that
tool call and its result both happen inside one turn (no Stop in between,
no new `UserPromptSubmit`), so no second Round is ever created and there is
nothing to fold. Reply Fold only matters when Claude ends the *entire* turn
on a plain-text question and the answer arrives as a separate message.

## Design constraint

Same constraint as Span Mode (`docs/design/span-mode.md`): hook payloads
carry no field that tells `round-start.sh` "this message answers a pending
question" versus "this message starts something new." The design below
follows Span Mode's precedent — Claude explicitly declares the expectation
via a marker file; the hook honors it only when it still matches the
current state, and silently drops it otherwise. No content parsing, no
transcript inspection.

## Mechanism

### `hooks/scripts/await-open.sh`

A small script, modeled on `span-open.sh`, that Claude runs directly via
Bash right after finishing a Round's Summary/Handoff/Status — no slash
command wraps it, because opening this marker is a frequent, fine-grained
action (potentially every clarifying question), not a deliberate mode
switch like Span Mode.

- `NOT_ENABLED` if `.devlog/.enabled` is missing.
- `ALREADY_OPEN` if `.devlog/.awaiting-reply` already exists.
- Otherwise resolves the current Round number (last `## Round` in
  `devlog.md` via `devlog_list_round_starts`) and writes:

```json
{"round": 15, "opened_at": "2026-09-09T14:30:00+08:00"}
```

### `round-start.sh`

After the existing `.round-open` dangling-heal step and before the Span
Mode check, `round-start.sh` reads `.devlog/.awaiting-reply` if present:

1. Parse its `round` field. Compare against the last `## Round N` actually
   in `devlog.md` right now (fence-aware, via the existing
   `devlog_list_round_starts` helper).
2. Delete `.awaiting-reply` unconditionally — it is a one-shot marker,
   consumed whether or not it matched.
3. If it matched, skip opening a new `## Round` entirely. Instead:
   - Locate that Round's line range (`devlog_block_end`).
   - Count existing `### 段落` headings inside that range to number the
     new one.
   - Insert, immediately before that Round's `### Summary` line:
     ```
     ### 段落 <k> - HH:MM（回覆上一輪的問題）
     ```text
     <this prompt, same placeholder/truncation/fence-neutralize/redact
     handling already applied to User Input>
     ```
     ```
   - Rewrite `.devlog/.round-open` with this Round's number, so an
     interruption during this reply-handling turn still heals normally
     (`close-open-round.sh` finds Summary/Handoff already present and only
     rewrites Status, per its existing "already has headings" path).
4. If it did not match (stale/mismatched round, malformed marker, or
   `devlog.md` missing), fall through to the normal new-`## Round` path
   unchanged.

If both `.span-open` and `.awaiting-reply` are present at once (not an
expected combination — Span Mode is for automated continuations, not
interactive Q&A), Span Mode wins: the tick is skipped entirely and
`.awaiting-reply` is simply consumed with no effect.

`.turn-start` is still snapshotted *after* whichever of the three paths ran
(new Round / folded segment / span-skip), so `enforce-devlog.sh` keeps
demanding a further edit exactly as it does today.

### Checkpoint Mode interaction

A folded tick does not open a new Round, so it does not count as one:
`rounds_since_checkpoint` is **not** incremented on a fold, the same
treatment a Span-Mode-skipped tick already gets.

### `enforce-devlog.sh` / `close-open-round.sh`

Unchanged. Both already operate on "whatever the last `## Round` in the
file is" — they don't need to know whether that Round was freshly opened or
reopened by a fold.

### `/devlog-tracker:pause`

`pause-devlog.sh` deletes `.awaiting-reply` alongside the existing
`.span-open` / `.round-open` / `.interrupted` cleanup, so a paused project
never resumes into a stale fold.

## Lifecycle

**Opening**: after Stop would otherwise let a Round close (Summary/Handoff/
Status all written), if that Status reflects "waiting on the user's answer
to a specific question asked this turn" — whether written as `BLOCKED` or
`IN_PROGRESS` — Claude runs `await-open.sh` before ending the turn.

**Consuming**: fully automatic. The very next `UserPromptSubmit` either
folds into that Round (marker matched) or is silently ignored and a normal
new Round opens (marker stale). Either way the marker is gone after one
use — there is no explicit "close" step, unlike Span Mode's multi-tick span.

**After a fold**: Claude edits the reopened Round like any other — update
Summary/Handoff/Status to reflect what the answer resolved, same as editing
any Round that isn't done yet. Stop still requires Summary/Handoff to be
present with content, exactly as before.

## Known Limitations

- **No way to verify the guess.** Same class of limitation as Span Mode's
  human-vs-automated blind spot: honoring `.awaiting-reply` is an
  assumption, not a fact the hook can check. If Claude opens the marker and
  the user's next message is actually an unrelated new request, it still
  gets folded in as a `### 段落` of the old Round. Recovery is manual and
  the same shape as Span Mode's: Claude notices, says so inside that
  folded segment, and opens a genuine new `## Round` itself — nothing
  about the automatic fold prevents Claude from doing that afterward.
- **Persists across `/clear` and session boundaries.** `.awaiting-reply` is
  a plain file; it does not know a `/clear` happened and will still try to
  fold the next message it sees, even into a Round from a context Claude
  no longer remembers. This is the same class of risk `.round-open`'s
  dangling-heal already carries across those same boundaries — Reply Fold
  doesn't add a new kind of risk, just a second file exposed to it.

## Files

| File | Role |
|---|---|
| `hooks/scripts/await-open.sh` | Writes `.devlog/.awaiting-reply` for the current Round |
| `hooks/scripts/test-await-open.sh` | Self-check for `await-open.sh` |
| `hooks/scripts/round-start.sh` | Reads/consumes `.awaiting-reply`; folds a matching reply into the last Round instead of opening a new one |
| `hooks/scripts/test-round-start.sh` | Self-check covering fold-match, fold-miss, and checkpoint-counter behavior |
| `hooks/scripts/pause-devlog.sh` | Also deletes `.awaiting-reply` on pause |
| `skills/devlog-tracker/SKILL.md` | Authoring instructions for Claude (when to open the marker, how a folded segment looks, the `AskUserQuestion` distinction) |
