# Per-round Summary + Reply + Handoff

Split each Round's former `### Response` blob into audience-specific
blocks, and have the Stop hook verify that the required headings exist on
the last Round before the turn can end.

- **`### Summary`** is for a human skimming `devlog.md`: a short conclusion
  of this round, including whether work is stuck.
- **`### Reply`** is what Claude actually said / promised to the user this
  turn (conclusions, open questions). Next agent needs this for commitment
  boundaries; it is not a Handoff.
- **`### Handoff`** is for the next Claude: structured facts needed to
  continue without reading the conversation transcript — including
  `#### 完成條件` so L1 handoff can decide when the ask is `DONE`.
- **`### Status`** is `DONE | IN_PROGRESS | BLOCKED | INTERRUPTED`. The "what
  to do next" sentence that used to live under Status moves into Handoff's
  `下一步`. `INTERRUPTED` is hook-only (unexpected interrupt), not a Claude
  close choice; interrupt stubs do not require Summary/Reply/Handoff quality
  checks beyond presence stubs from `close-open-round.sh`.

This is independent of Checkpoint Mode. A Checkpoint is still a *cross-round*
human landmark; Summary is the *per-round* human skim. Neither replaces the
other.

## Motivation

`### Response` tried to serve both readers at once and served neither well.
A human scanning recent rounds had to wade through file lists and skill
names; the next session's Claude had to reconstruct "what do I actually do
now" from a narrative, with the only dedicated next-step sentence buried
under Status and omitted on `DONE`.

L1 auto-handoff also needs (1) what was promised to the user (`Reply`) and
(2) an observable done predicate (`完成條件`), neither of which lived in the
old two-block split.

| Reader | Needs | Does not need |
|---|---|---|
| Human | Conclusion, stuck-or-not | Paths, hashes, skill names, stepwise commands |
| Next Claude | Decisions, this-round files, git snapshot, task state, done criteria, next concrete action | Prose restating the conclusion |
| Commitment boundary | What was said / promised to the user | Git snapshots |

## Round format

```markdown
## Round <N> — <ISO 8601 timestamp with offset>

### User Input
<prefer the submitted prompt verbatim; see recording-moments + SKILL>

### 段落 1 - HH:MM
<optional; only when the round has meaningful phase results>

### Summary
<2–4 sentences for a human. Conclusion of this round, and whether it is stuck.
No file paths, commit hashes, skill names, or stepwise commands.>

### Reply
<What was said / promised to the user this turn. Short. Required even on
trivial rounds.>

### Handoff
#### 決策
<choices that affect later direction, with reasons. If a design doc is the
SSOT for the choice, name `docs/design/...`. Omit the whole subsection
if no choice was made.>

#### 檔案
<machine-checked block grammar (`docs/design/files-verify.md`): zero or more
`commit <hash>：` blocks in chronological order, each followed by up to
three category lines (`新增：`/`修改：`/`刪除：`, comma-joined paths, omit a
category with nothing to report), plus at most one trailing `尚未 commit：`
block in the same shape for whatever is still dirty. Omit the whole
subsection if no files changed outside `.devlog/`.>

#### 工作區
<git snapshot at close, for the next Claude to check against the real tree.
Required when Status is IN_PROGRESS or BLOCKED. Omit when Status is DONE
and there is nothing further to do, and on INTERRUPTED stubs. See writing
rule 3.>

#### 現況
<task state the next Claude should assume (how far the work got, what is
stuck). Git snapshot belongs in 工作區, not here. Almost every round
should have this. On BLOCKED, state what is missing and what “arrived”
looks like.>

#### 完成條件
<Required for IN_PROGRESS / BLOCKED. Observable predicate for DONE
(test command, file behavior, user-confirmed scope). Omit when Status is
DONE and there is nothing further.>

#### 下一步
<the first concrete action of the next turn, specific enough to start
without re-deriving it (paths, commands, which skill to reload). Required
when Status is IN_PROGRESS or BLOCKED. Omit when Status is DONE and there
is nothing further to do.>

### Status
DONE | IN_PROGRESS | BLOCKED | INTERRUPTED
```

Top-level headings stay English (`User Input`, `Summary`, `Reply`,
`Handoff`, `Status`) to match the rest of the Round schema. Handoff
subsections use the Chinese labels above, in that fixed order.

## Writing rules

1. **Split the three readers.** Summary is only for humans. Reply is only
   what was said to the user. Handoff is only for the next Claude. Do not
   restate the same content in all three.
2. **Summary is 2–4 sentences.** Conclusion and blockers only. Forbidden
   in Summary: file paths, commit hashes, skill names, stepwise commands.
3. **Handoff subsections are ordered and optional-by-absence.** Order is
   always 決策 → 檔案 → 工作區 → 現況 → 完成條件 → 下一步, and the Stop hook
   rejects a present-but-reordered or duplicated recognized subsection
   (structure only — it does not check whether the content itself is
   correct). A subsection that did not occur is omitted entirely — do not
   write a heading whose body is 「無」.
   `現況` should be present on almost every round. `工作區`, `完成條件`, and
   `下一步` are required for `IN_PROGRESS` and `BLOCKED`. Omit them when
   Status is `DONE` and there is nothing further to do. `下一步` must be
   concrete enough that the next turn can start from it; do not write
   「繼續完成」. On `IN_PROGRESS`, Stop also applies a light actionable lint
   (path, backtick command, file-ish token, or skill mention). On
   `BLOCKED`, `現況` or `下一步` must include a missing-input phrase
   (缺／等待／等使用者／出現即 …).
   `工作區` is the git snapshot at close, written from command output,
   not from memory. The exact commands and output formats are canonical
   in `skills/devlog-tracker/SKILL.md` (`#### 工作區`) — not respelled
   here. Interrupt stubs omit `工作區`. The Stop hook requires this
   heading to match a live git snapshot when Status is `IN_PROGRESS` or
   `BLOCKED` (`hooks/scripts/workspace-snapshot.sh`). Continue / resume
   encode live git in that same format set, then compare that snapshot
   to this block before acting on `下一步` (`docs/design/continue.md`).
4. **Status is only the enum.**
   - `IN_PROGRESS`: work remains and can proceed.
   - `BLOCKED`: work cannot proceed without external input.
   - `DONE`: this round's request is finished (完成條件 met, or the ask
     itself ended).
   - `INTERRUPTED`: hook-only stamp for unexpected interrupt (Esc, non-usage
     API error, SessionEnd, dangling `.round-open`). Claude must not choose
     this when closing normally. Interrupt stubs get Summary/Reply/Handoff
     stubs from `close-open-round.sh`.
   The former "接下來要做什麼" sentence no longer belongs under Status.
5. **Trivial rounds still get a full Round block.** One-sentence Summary;
   one-sentence Reply; Handoff keeps only `現況` (one sentence, no `工作區`);
   Status is usually `DONE`. `### Summary`, `### Reply`, and `### Handoff`
   are all still required.
6. **Handoff describes what already happened**, except `下一步` and
   `完成條件`, which may describe the future predicate / next action.
7. **L1 write-back.** After continue / injected handoff work, the same
   Round must close with Summary / Reply / Handoff / Status. Reading
   without writing back is an L1 failure (`docs/design/continue.md`).

## Round Segments, Checkpoint, Span

**Round Segments** stay a mid-round authoring convention: write `### 段落`
blocks between User Input and the closing Summary / Reply / Handoff as
phases complete. Do not copy segment bodies into Summary, Reply, or Handoff.

**Checkpoint Mode** is unchanged as a mechanism. Its *content* should
align with the intervening rounds' Summaries (human landmarks), not become
a concatenation of Handoffs. A Checkpoint does not replace per-round
Summary.

**Span Mode** is unchanged as a mechanism. The Round that opens a span,
quiet ticks under `max_silent_ticks`, a one-line write when the budget
expires, and a *new* closing Round are all as today. The closing Round
uses this format to summarize the whole automated stretch.

A one-line span check-in still satisfies heading enforcement if it
*appends* to a last Round that already contains `### Summary`,
`### Reply`, and `### Handoff`. A newly opened Round always needs all
three headings, including trivial rounds.

## Stop-hook enforcement

After the existing content-hash check passes (the file changed this turn),
`enforce-devlog.sh` extracts the **last Round block**: from the last line
matching `^## Round ` through the line before the next `^## ` heading, or
through EOF if none follows (so a trailing `## Checkpoint` is not part of
the Round). That block must contain:

- a line starting with `### Summary`
- a line starting with `### Reply`
- a line starting with `### Handoff`

Missing any blocks the turn (`exit 2`) with a message asking Claude to
add the missing heading(s) to that last Round.

Details:

- **Presence plus a light structure check, plus two machine-verified
  fields, plus L1 lint.** The hook does not check that Summary is 2–4
  sentences or that 決策／現況／Reply prose is accurate. Present Handoff
  subsections among 決策/檔案/工作區/現況/完成條件/下一步 must be in that
  order and not duplicated. `IN_PROGRESS` / `BLOCKED` require non-empty
  `#### 完成條件` and `#### 下一步`. `IN_PROGRESS` / `BLOCKED` `#### 工作區`
  is compared to a snapshot the hook computes (`workspace-snapshot.sh`); a
  non-empty `#### 檔案` is compared to git via `files-snapshot.sh`
  (`docs/design/files-verify.md`) — commit blocks exactly, the
  uncommitted block as a one-directional subset check. Bodies must be
  non-empty. `#### 下一步` gets the filler blacklist plus, for
  `IN_PROGRESS` only, a light actionable lint. `BLOCKED` gets a missing-
  input phrase check on `現況` or `下一步`.
- **Last Round is the unit.** A turn that only appends a Checkpoint, or a
  Span budget-expiry one-liner, passes as long as the last Round already
  has the three headings.
- **No `## Round` found after a hash-changing write:** fail-open (do not
  block). The heading check is additional enforcement, not a new way to
  freeze a session.
- **Loop guard unchanged.** `stop_hook_active` still exits 0 on retry, so
  this check, like the hash check, is one opportunity per turn.
- **Check order:** enabled → `.interrupted` short-circuit → existing loop
  guard → span under-budget pass → hash comparison → **heading check** →
  span tick reset → checkpoint check.

The hash-miss message should name
`User Input / Summary / Reply / Handoff / Status`.

## Files

| File | Role |
|---|---|
| `skills/devlog-tracker/SKILL.md` | Authoring instructions: format, writing rules, Status, trivial rounds, span closing Round, L1 write-back |
| `README.md` | Feature blurb and SSOT / L1 framing |
| `commands/continue.md` | Verify-then-act + write-back |
| `hooks/scripts/enforce-devlog.sh` | Heading / order / L1 lint after a successful hash comparison |
| `hooks/scripts/close-open-round.sh` | Interrupt stubs include Reply |
| `hooks/scripts/tests/test-enforce-devlog.sh` | Coverage for Reply / 完成條件 / actionable / BLOCKED 缺件 |
| `docs/design/summary-handoff.md` | This spec |
| `docs/design/devlog-as-ssot-assessment.md` | L1 scope vs non-goals |

`session-start-devlog.sh`, `round-start.sh`, and compact's *move* rules
stay as they are: they already key off `## Round` / Status / `## Checkpoint`,
not off `### Response`.

## Known limitations

- **Presence plus a light structure check.** Headings must exist, Summary /
  Reply / Handoff bodies must contain a non-whitespace line, Status must be
  one of `DONE` / `IN_PROGRESS` / `BLOCKED` / `INTERRUPTED`, and
  `IN_PROGRESS` / `BLOCKED` require non-empty `#### 完成條件` and
  `#### 下一步`. Actionable lint and BLOCKED 缺件 checks are pattern-based,
  not semantic scoring of prose quality. `IN_PROGRESS` / `BLOCKED` also
  require `#### 工作區` to match a git snapshot the hook computes itself
  (`hooks/scripts/workspace-snapshot.sh`,
  `docs/design/devlog-as-ssot-assessment.md` Phase 1) — content-verified,
  not just presence-checked. `DONE` requires it too when `#### 檔案` is
  non-empty (a round claiming file changes); a trivial `DONE` with no
  `#### 檔案`, and `INTERRUPTED`, do not require it.
  A non-empty `#### 檔案`, independent of Status, is likewise
  content-verified against git (`hooks/scripts/files-snapshot.sh`,
  `docs/design/files-verify.md`) — commit blocks exactly, the trailing
  uncommitted block as a one-directional subset check; a body that
  doesn't parse into the block grammar blocks the turn rather than
  failing open. Handoff subsection order and duplicates among
  決策/檔案/工作區/現況/完成條件/下一步 are also checked; unrecognized
  `#### ` headings are ignored. Prose quality elsewhere (Summary, Reply,
  決策, 現況, 完成條件 wording) is still on Claude — `#### 檔案`
  verification is path-level only. `#### 下一步` gets one additional,
  non-semantic check: when its entire trimmed body is a single line that
  exactly equals a known filler phrase ("繼續完成" etc., see
  `docs/design/next-step-blacklist.md`), the turn is blocked.
