# Per-round Summary + Handoff

Split each Round's former `### Response` blob into two audience-specific
blocks, and have the Stop hook verify that both headings exist on the last
Round before the turn can end.

- **`### Summary`** is for a human skimming `devlog.md`: a short conclusion
  of this round, including whether work is stuck.
- **`### Handoff`** is for the next Claude: structured facts needed to
  continue without reading the conversation transcript.
- **`### Status`** is `DONE | IN_PROGRESS | BLOCKED | INTERRUPTED`. The "what
  to do next" sentence that used to live under Status moves into Handoff's
  `下一步`. `INTERRUPTED` is hook-only (unexpected interrupt), not a Claude
  close choice; interrupt stubs do not require Summary/Handoff quality checks.

This is independent of Checkpoint Mode. A Checkpoint is still a *cross-round*
human landmark; Summary is the *per-round* human skim. Neither replaces the
other.

## Motivation

`### Response` tried to serve both readers at once and served neither well.
A human scanning recent rounds had to wade through file lists and skill
names; the next session's Claude had to reconstruct "what do I actually do
now" from a narrative, with the only dedicated next-step sentence buried
under Status and omitted on `DONE`.

The two audiences need different information:

| Reader | Needs | Does not need |
|---|---|---|
| Human | Conclusion, stuck-or-not | Paths, hashes, skill names, stepwise commands |
| Next Claude | Decisions, files, workspace state, next concrete action | Prose restating the conclusion |

## Round format

```markdown
## Round <N> — <ISO 8601 timestamp with offset>

### User Input
<close to the user's wording; existing rules unchanged>

### 段落 1 - HH:MM
<optional; only when the round has meaningful phase results>

### Summary
<2–4 sentences for a human. Conclusion of this round, and whether it is stuck.
No file paths, commit hashes, skill names, or stepwise commands.>

### Handoff
#### 決策
<choices that affect later direction, with reasons. Omit the whole subsection
if no choice was made.>

#### 檔案
<added / modified / deleted paths. If a commit happened, say so (hash or
subject). If files changed but were not committed, say that. Omit the whole
subsection if no files changed.>

#### 現況
<the actual workspace / task state the next Claude should assume. Almost
every round should have this.>

#### 下一步
<the first concrete action of the next turn, specific enough to start
without re-deriving it (paths, commands, which skill to reload). Required
when Status is IN_PROGRESS or BLOCKED. Omit when Status is DONE and there
is nothing further to do.>

### Status
DONE | IN_PROGRESS | BLOCKED | INTERRUPTED
```

Top-level headings stay English (`User Input`, `Summary`, `Handoff`,
`Status`) to match the rest of the Round schema. Handoff subsections use
the Chinese labels above, in that fixed order.

Round numbering, timestamps, and User Input rules are unchanged.

## Writing rules

1. **Split the two readers.** Summary is only for humans. Handoff is only
   for the next Claude. Do not restate the same content in both.
2. **Summary is 2–4 sentences.** Conclusion and blockers only. Forbidden
   in Summary: file paths, commit hashes, skill names, stepwise commands.
3. **Handoff subsections are ordered and optional-by-absence.** Order is
   always 決策 → 檔案 → 現況 → 下一步. A subsection that did not occur is
   omitted entirely — do not write a heading whose body is 「無」.
   `現況` should be present on almost every round. `下一步` is required
   for `IN_PROGRESS` and `BLOCKED`, and must be concrete enough that the
   next turn can start from it; do not write 「繼續完成」.
4. **Status is only the enum.**
   - `IN_PROGRESS`: work remains and can proceed.
   - `BLOCKED`: work cannot proceed without external input.
   - `DONE`: this round's request is finished.
   - `INTERRUPTED`: hook-only stamp for unexpected interrupt (Esc, non-usage
     API error, SessionEnd, dangling `.round-open`). Claude must not choose
     this when closing normally. Interrupt stubs are not subject to
     Summary/Handoff quality checks.
   The former "接下來要做什麼" sentence no longer belongs under Status.
5. **Trivial rounds still get a full Round block.** One-sentence Summary;
   Handoff keeps only `現況` (one sentence); Status is usually `DONE`.
   Both `### Summary` and `### Handoff` headings are still required.
6. **Handoff describes what already happened**, except `下一步`, which is
   the only place future tense is allowed.

## Round Segments, Checkpoint, Span

**Round Segments** stay a mid-round authoring convention: write `### 段落`
blocks between User Input and the closing Summary / Handoff as phases
complete. Do not copy segment bodies into Summary or Handoff.

**Checkpoint Mode** is unchanged as a mechanism. Its *content* should
align with the intervening rounds' Summaries (human landmarks), not become
a concatenation of Handoffs. A Checkpoint does not replace per-round
Summary.

**Span Mode** is unchanged as a mechanism. The Round that opens a span,
quiet ticks under `max_silent_ticks`, a one-line write when the budget
expires, and a *new* closing Round are all as today. The closing Round
uses this format to summarize the whole automated stretch.

A one-line span check-in still satisfies heading enforcement if it
*appends* to a last Round that already contains `### Summary` and
`### Handoff`. A newly opened Round always needs both headings, including
trivial rounds.

## Stop-hook enforcement

After the existing content-hash check passes (the file changed this turn),
`enforce-devlog.sh` extracts the **last Round block**: from the last line
matching `^## Round ` through the line before the next `^## ` heading, or
through EOF if none follows (so a trailing `## Checkpoint` is not part of
the Round). That block must contain both:

- a line starting with `### Summary`
- a line starting with `### Handoff`

Missing either blocks the turn (`exit 2`) with a message asking Claude to
add the missing heading(s) to that last Round.

Details:

- **Presence only, not quality.** The hook does not check that Summary is
  2–4 sentences, that Handoff has the four subsections, or that bodies are
  non-empty. Same trust level as Checkpoint's `^## Checkpoint` marker.
- **Last Round is the unit.** A turn that only appends a Checkpoint, or a
  Span budget-expiry one-liner, passes as long as the last Round already
  has both headings.
- **No `## Round` found after a hash-changing write:** fail-open (do not
  block). The heading check is additional enforcement, not a new way to
  freeze a session.
- **Loop guard unchanged.** `stop_hook_active` still exits 0 on retry, so
  this check, like the hash check, is one opportunity per turn.
- **Check order:** existing loop guard → enabled → span under-budget pass
  → hash comparison → **heading check** → span tick reset → checkpoint
  check.

The hash-miss message should name `User Input / Summary / Handoff / Status`
instead of `User Input / Response / Status`.

## Files

| File | Role |
|---|---|
| `skills/devlog-tracker/SKILL.md` | Authoring instructions: format, writing rules, Status, trivial rounds, span closing Round |
| `README.md` | Feature blurb and "格式固定" line |
| `commands/start.md` | Mentions of the three-field Round shape |
| `hooks/scripts/enforce-devlog.sh` | Heading check after a successful hash comparison |
| `hooks/scripts/test-enforce-devlog.sh` | Coverage for missing Summary, missing Handoff, both present, fail-open when no Round, span one-liner on a Round that already has headings |
| `docs/design/summary-handoff.md` | This spec |

`session-start-devlog.sh`, `round-start.sh`, and compact's *move* rules
stay as they are: they already key off `## Round` / Status / `## Checkpoint`,
not off `### Response`.

## Known limitations

- **Heading text is the only verified signal.** A `### Handoff` line with
  an empty body, or a `### Summary` that is actually a file list, still
  counts. Substance stays on Claude, as with every other enforced heading
  in this plugin.
- **A heading written for other reasons still counts.** Quoting this spec
  into `devlog.md` under those exact heading lines would satisfy the hook.
  Acceptable: no plausible reason for those headings to appear except a
  real Summary / Handoff.
- **Last-Round targeting.** If the last Round is missing the headings,
  *any* hash-changing write this turn (including a Checkpoint-only append)
  is blocked until that last Round gains them. There is no exemption for
  "I only meant to write a Checkpoint."
- **One-shot loop guard.** Same as the hash check: after one block, the
  retry is released even if headings were not added.

## Out of scope

- Rewriting or migrating historical Rounds that still use `### Response`.
- Hook checks for subsection headings (`#### 決策` etc.), non-empty
  bodies, or Status/`下一步` consistency.
- Changing compact's retain rules.
