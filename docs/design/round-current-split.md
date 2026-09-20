# Round-Current Split (`.devlog/.round-current.md`)

A performance fix for devlog SSOT: pull "the round that's currently open"
out of `devlog.md` into its own bounded scratch file. Implemented and
landed (`round-current-split` branch) — this document records what
actually shipped, not a not-yet-built proposal.

## Problem

While a round is in progress, Claude and the hooks read/hash `devlog.md`
far more than once:

- `round-start.sh` writes the skeleton when it opens a new round;
- Round Segments' Segment Watch, every time this round's silence crosses
  the threshold, requires Claude to Read the whole file before appending
  a segment;
- the workspace-mismatch check, once it detects the previous round's
  `#### 工作區` no longer matches git, also requires Claude to Read the
  whole file before appending a section explaining claimed-vs-actual.

`devlog.md` is the project's whole accumulated history — it only grows,
never shrinks (nothing auto-moves content out of it before `compact`/
`keep` are run). All of the operations above conceptually only need this
round's content, but because both Claude and the hooks operate against
the entire `devlog.md` (the Stop hook also `cksum`s it every round), the
cost scales with **the total size of project history**, not with **the
size of the current round**. The longer a project runs and the more
rounds it accumulates, the more expensive it gets to repeatedly read and
write this ever-growing file — even when the current round itself is
just a few lines.

## Decision

Split into two files:

- **`.devlog/.round-current.md` (hot, bounded):** holds only "the round
  that's currently open" (skeleton, segments, and the closing
  Summary/Handoff/Status), sized proportionally to this round's content,
  independent of project history. While the round is open, this is what
  Claude should Read/Edit, and it's what PreToolUse (Segment Watch, the
  workspace-mismatch backstop) and Stop hash against — not `devlog.md`.
- **`.devlog/devlog.md` (cold, append-only, historical SSOT):** keeps its
  original role as the source of truth for round-by-round history. While
  a round is still open, `devlog.md` has no visibility into it at all;
  only once the round closes (normal completion or a determined
  interruption) does `.round-current.md`'s content get appended to
  `devlog.md`'s tail, after which `.round-current.md` is cleared.

At any given moment, a round's content lives in exactly one of the two
files, never both — even the "Reopen" case described below cuts that
block out of `devlog.md` and writes it into `.round-current.md` (removing
it from `devlog.md` in the same step), rather than copying it.

## When content merges back into `devlog.md`

Two places perform the merge, both by calling the new
`devlog_merge_round_current(devlog, current)` in `core/scripts/devlog-md.sh`
(appends `current`'s content to `devlog`'s tail, separated by one blank
line, then deletes `current`; a no-op if `current` is absent or empty):

1. **`enforce-devlog.sh`'s Stop closes the round successfully.** Once the
   hash comparison proves this round actually wrote something, and
   `enforce-devlog.sh` has run the full set of format/machine checks
   against `.round-current.md` (`### Summary`/`### Handoff` present and
   non-empty, Handoff subsection order, `#### 工作區`/`#### 檔案` machine
   verification, ...) and all of them pass, it calls
   `devlog_merge_round_current`, appending `.round-current.md` into
   `devlog.md` and clearing it. This step is deliberately placed
   **before** the Checkpoint-count check: if this round's content already
   carries a Claude-written `## Checkpoint`, it gets counted toward that
   check immediately after merging, instead of waiting for the next
   round to notice it.

2. **`close-open-round.sh` decides the round is finished — either way it
   decides that, it merges.** This hook has exactly two possible
   outcomes by the time it finishes, and **both merge**:
   - **Stamping `INTERRUPTED`:** the round genuinely never closed
     (`.round-open` is still present, and the content is missing
     `### Summary` or `### Handoff`) — the awk block rewrites
     `.round-current.md`: fills in Summary/Handoff stubs, stamps
     `### Status` as `INTERRUPTED` with a trailing `[reason: ...]` line
     (awk returns 0).
   - **Recovered (it had actually already finished writing, the
     interrupt signal just arrived late):** the awk block detects that
     `.round-current.md` already has both Summary and Handoff, and that
     the content hash differs from what `.turn-start` recorded (meaning
     Claude had, in fact, already finished writing its close-out before
     the interrupt signal arrived) — it leaves the content untouched and
     returns 3 immediately.
   - The caller merges on either `AWK_RC` value (`0` or `3`) via
     `devlog_merge_round_current`. Whether the round got stamped
     `INTERRUPTED` or had actually already closed normally and only the
     detection was late, both cases mean "this round is now definitely
     finished," and both must be merged into the history file — there is
     no third state of "finished but not merged" allowed to sit in
     `.round-current.md`.

When `enforce-devlog.sh`'s Stop first encounters `.devlog/.interrupted`,
it also calls `close-open-round.sh` up front (taking path 2 above), and
only afterward checks whether `.round-current.md` still has content left
to validate (which only happens when `close-open-round.sh` was a no-op —
i.e. `.round-open` was already absent or stale). It does not re-implement
a second merge path of its own.

## Why Stop's validation can't just `cat .round-current.md` wholesale

Once `enforce-devlog.sh`'s hash comparison proves this round actually
wrote something, what it needs to validate is the "last Round"'s
Summary/Handoff/Status. In principle `.round-current.md` should hold
exactly this one round and nothing else, but the whole file's content
still can't be treated as the validation range as-is:

1. **A Checkpoint may already be appended to the same file's tail.**
   When Claude closes out this round, it may have already written a
   `## Checkpoint` section (the cross-round summary Checkpoint Mode
   requires) onto the tail of `.round-current.md` — if that content isn't
   excluded, it can contaminate the Summary/Handoff extraction range or
   throw off the boundary detection.
2. **The content might not contain a `## Round ` line at all.** For
   example, pure noise — in which case there is no Round to validate.

`enforce-devlog.sh` reuses the same boundary-extraction rule that
predates the split, just pointed at `.round-current.md` instead: a
fence-aware awk block finds the first non-fenced `## Round ` line as the
start, then scans forward to the next non-fenced `## ` line (or end of
file) as the boundary, extracting only that range — a trailing
`## Checkpoint` section is naturally excluded. **When no `## Round ` line
exists at all, it fails open** (the extraction result is empty,
`LAST_ROUND` evaluates empty, and the whole validation block is skipped
rather than blocking the turn) — this is a design property that predates
the split, carried over intact from the old `last_round_block()`'s
`if (start == 0) exit 0`. After the split to `.round-current.md`, this
rule is preserved exactly as-is, only the input file changed — it was
not simplified into a plain `cat` that would have quietly narrowed this
fail-open guarantee.

## Reopen: Reply Fold reopens a round to file its answer

Reply Fold (`skills/devlog-tracker/references/reply-fold.md`) folds
"Claude asks a question, the next message is the answer" into the same
Round, instead of the default behavior splitting it into two unrelated
Rounds. Post-split, this mechanism gained one extra step:

- **Detection logic is unchanged, still compared against `devlog.md`.**
  `round-start.sh` checks whether `.devlog/.awaiting-reply`'s recorded
  round number matches `devlog.md`'s current last `## Round` (via
  `devlog_list_round_starts`). It compares against `devlog.md` because,
  by the time the question was asked, that round should already have
  closed normally and merged back into `devlog.md` — Claude fully wrote
  a valid Summary/Handoff/Status before ending that turn — so at this
  point it only exists in `devlog.md`, never in `.round-current.md`.
  There is no reason for the detection side to change.
- **Before executing the fold, the round is pulled back out of
  `devlog.md`.** Once the round number matches, `round-start.sh` calls
  the new `devlog_reopen_last_round(devlog, current)`: it cuts
  `devlog.md`'s last `## Round` block out entirely (removed from
  `devlog.md`, written into `.round-current.md`), and only then inserts
  this reply's `### 段落` into `.round-current.md`.
- **The round becomes "open" again**, and everything downstream —
  validation, Segment Watch, the next close-out — behaves exactly like
  any other open round: when the turn holding this reply ends,
  `enforce-devlog.sh` still requires a valid Summary/Handoff to pass, and
  merges it back into `devlog.md` on success just like normal.

In other words, only **executing the fold** (moving content into
`.round-current.md`, inserting the segment) changed its target file;
**deciding whether to fold** did not change what it compares against at
all. This design exists so that a user taking a long time to reply
doesn't leave the data inconsistent across the two files for an extended
period: during the window between the question going out and the answer
arriving, the round genuinely has already closed and is sitting complete
in `devlog.md`'s history — it is not left dangling in `.round-current.md`
pretending to still be open. Only once the next message actually arrives
and is judged to be the answer does it get briefly reopened, folded, and
immediately merged back.

## What this split does not affect

The following paths are guaranteed to only ever see content that has
already fully merged back into `devlog.md`, because every path that
could precede them (a successful Stop, or `close-open-round.sh`'s
stamp-or-recovered determination) closes and merges first:

- `/devlog-tracker:continue`, `/devlog-tracker:resume`,
  `/devlog-tracker:compact`, `/devlog-tracker:keep`,
  `/devlog-tracker:status`
- `/devlog-tracker:clean` — with one exception: if a round happens to be
  open when it's invoked, `clean-devlog.sh` reads that round's content
  from `.round-current.md`, renumbers it to `## Round 1`, and writes it
  back into `.round-current.md` (never into `devlog.md`, which is
  emptied/removed instead) — the rest of history is wiped entirely,
  nothing else is kept. This keeps the split's invariant intact:
  `.round-open` still points at round 1, and that round's content still
  lives only in `.round-current.md`, exactly like any other open round.
  Stop validates and merges it normally when the turn closes.

**Exception: SessionStart's handoff-excerpt injection**
(`core/scripts/session-start-devlog.sh`) is *not* guaranteed to see only
merged content. `startup` / `resume` / `fork` heal a dangling
`.round-open` before printing the excerpt, so by the time it runs
`.round-current.md` is normally already empty. But `source=compact`
deliberately skips that heal (see the script's header comment — healing
would change `.round-current.md`'s hash and let Stop silently pass), so a
mid-turn auto-compact can genuinely hit this injection while a round is
still open and its content still sits only in `.round-current.md`. To
avoid silently dropping the round Claude is in the middle of,
`session-start-devlog.sh` prints the `devlog.md` excerpt as before and
then, whenever `.round-current.md` is non-empty (for any of
startup/resume/compact/fork — harmless no-op in the healed cases), prints
its content too, clearly labeled as the still-open round.

## New helpers

`core/scripts/devlog-md.sh` gained two functions:

- `devlog_merge_round_current(devlog, current)`: appends `current`'s
  content to `devlog`'s tail (one blank-line separator) and deletes
  `current`; a no-op if `current` is absent or empty.
- `devlog_reopen_last_round(devlog, current)`: cuts `devlog`'s last
  `## Round` block out and writes it into `current` (creating that file),
  removing the same block from `devlog`; returns 1 and leaves both files
  untouched if `devlog` has no Round to cut.

## Files

| File | Role |
|---|---|
| `core/scripts/devlog-md.sh` | New `devlog_merge_round_current` / `devlog_reopen_last_round` |
| `core/scripts/round-start.sh` | Opening a new round and executing the Reply Fold both write into `.round-current.md`; round numbering and Reply Fold detection still read `devlog.md` |
| `core/scripts/enforce-devlog.sh` | Hashes and does fence-aware bounded-extraction validation against `.round-current.md`; calls `devlog_merge_round_current` on success |
| `core/scripts/close-open-round.sh` | Whether it stamps `INTERRUPTED` or determines the round was recovered, both outcomes call `devlog_merge_round_current` |
| `core/scripts/segment-watch.sh` | Silence detection and the PreToolUse allowlist target both switched to `.round-current.md` |
| `core/scripts/session-start-devlog.sh` | After printing the `devlog.md` excerpt, also prints `.round-current.md`'s content (labeled as the still-open round) whenever it's non-empty — needed for `source=compact`, which skips dangling-heal |
| `core/scripts/clean-devlog.sh` | Reads `.round-current.md` to recover an open round's content |
| `skills/devlog-tracker/SKILL.md` | 「檔案位置」 gained `.round-current.md`; the mandatory-recording steps and the writing-to-devlog sections now point at `.round-current.md` |
| `skills/devlog-tracker/references/round-segments.md` | Segment Watch's silence backstop now says Read `.round-current.md` |
| `skills/devlog-tracker/references/reply-fold.md` | Documents that folding actually happens against `.round-current.md`, and the reopen mechanism |
