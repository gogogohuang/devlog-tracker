# Is `devlog.md` a single source of truth?

An assessment of the claim in `skills/devlog-tracker/SKILL.md`
("devlog.md 是 single source of truth"). Conclusion: **yes, but only
for a scoped kind of truth** — cross-session handoff continuity
(decisions, current blockers, next step), for a **single developer on
one machine**. It is not SSOT for code/file state, not a complete
record of what happened, not literally single once a project uses
compact/keep, and not durable or shared the way SSOT usually implies.
SKILL.md's 核心原則 already scopes the claim that way.

## Review (2026-09-10)

Re-evaluated against the three implementation plans. Phases 1–3 have
landed:

- `docs/superpowers/plans/2026-09-10-devlog-ssot-phase1-workspace-verify.md`
- `docs/superpowers/plans/2026-09-10-devlog-ssot-phase2-handoff-order.md`
- `docs/superpowers/plans/2026-09-10-devlog-ssot-phase3-kept-index.md`

Verdict after those plans: the **scoped** claim still holds, and the
evidence for it gets stronger. The original roadmap overclaimed two
closures:

- Phase 1 does **not** close gap #1. It makes `#### 工作區` a write-time
  verified **cache** of git; git remains SSOT for the live tree.
- Phase 3 does **not** close gap #4. It makes keep files discoverable
  from `devlog.md`; history still fragments, and keep *content* is still
  never auto-injected.

`#### 工作區` is a cache of the environment (git), not a second source of
truth. Write-time verification (Phase 1) makes the cache honest at
`T_close`. Read-time verification (`continue` / `resume`) still has to
run, because the tree can change after close.

## What holds up (HEAD)

- **Enforced writing.** The Stop hook (`enforce-devlog.sh`) blocks a turn
  from ending until the last Round has `### Summary` and `### Handoff`
  with non-empty bodies, a legal `### Status`, and a non-empty `#### 下一步`
  when Status is `IN_PROGRESS` / `BLOCKED` (heading-substance), and
  `#### 工作區` matches a snapshot Stop computed (`workspace-snapshot.sh`,
  Phase 1). Unlike a wiki that people are supposed to remember to update,
  this one has write-compliance.
- **Structured handoff.** Decisions / files / git snapshot / current state
  / next step, in a fixed order, is lower-ambiguity than free-form prose
  or a raw transcript. Order of present subsections is hook-checked
  (Phase 2); unrecognized `#### ` headings are ignored.
- **Interrupts are stamped, not silently lost.** `INTERRUPTED` rounds
  exist even when a turn dies mid-work (see `docs/design/recording-moments.md`).
  The record is thin (see gap #3) but it exists.
- **Verify-before-act.** Stop already matched `#### 工作區` at close for
  `IN_PROGRESS` / `BLOCKED`. `continue` / `resume` re-derive live git
  because the cache may be stale (see `docs/design/continue.md`). Strongest
  evidence *for* honesty of the scoped claim, and *against* treating
  `devlog.md` as SSOT for git.

## What the three phases buy

| Phase | Status | Buys | Does not buy |
|---|---|---|---|
| 1. Machine-verify `#### 工作區` at Stop | ✅ in HEAD | Write-time honesty of the git cache for `IN_PROGRESS` / `BLOCKED` | SSOT for current git state (#1); check on `DONE` / `INTERRUPTED` |
| 2. Handoff subsection order + duplicates | ✅ in HEAD | Cheap structure on the five recognized `#### ` names. `下一步` non-empty is already in HEAD | Semantic quality of Summary / 決策 / 現況 / 檔案 |
| 3. `## Kept 索引` in `devlog.md`, surfaced by SessionStart | ✅ in HEAD | Discoverability of keep *files* without injecting their content | A literally single file; auto-injection of keep content; an archive index |

After Phase 1, verify-before-act splits into two moments: Stop already
matched the snapshot at close; `continue` / `resume` re-check because
the cache may be stale, not because the write was unverified.

After Phase 2, `docs/design/summary-handoff.md` no longer says
"Presence only, not quality." Accurate slogan: **structure plus one
machine-verified cache field; prose quality is still on Claude.**

## Where the unscoped claim breaks down

Accepted boundaries first — these are not defects to close. Then the
two slices the roadmap actually moves.

### Accepted design boundaries

1. **It defers to git for live tree state, by its own design.**
   `docs/design/continue.md`: "Handoff `#### 工作區` is a claim. It
   becomes a fact only after this turn's encoded snapshot matches it."
   A document that restates git is a cache of git. The working tree is
   SSOT for current file state; `devlog.md` holds a snapshot *about*
   that state at close. Phase 1 does not change this ontology — the
   hook's expected text *comes from* git. Same class of boundary as #5.

3. **It's a lossy summary, not a transcript.**
   User Input is "close to original wording... not strictly verbatim";
   segments capture only phases Claude judges "meaningful"; anything
   between tool calls that isn't written as a `### 段落` "仍會丟"
   (SKILL.md). Closing this would turn devlog into a transcript, against
   its purpose.

5. **It isn't durable or shared.** `.devlog/` is gitignored (raw
   prompts). It does not travel with `git clone`, does not follow
   `git worktree` / branch switches, is invisible in PR review, and has
   none of git's integrity. Fine for one developer on one machine;
   disqualifying for any team-wide "the" source of truth. This roadmap
   does not try to make it portable.

6. **Its scope is narrower than "the project."** It records what was
   decided and what's next, not the requirements, not the design spec
   (`docs/design/*.md`), not what the code currently does (the code is
   that). Closing this would turn it into a project knowledge base.

### Open at HEAD; narrowed by the plans

2. **Correctness is mostly unchecked.**
   HEAD already checks more than raw presence: non-empty Summary /
   Handoff, legal Status, non-empty `#### 下一步` for `IN_PROGRESS` /
   `BLOCKED`, and (Phase 1) `#### 工作區` matching live git for those
   statuses. Present Handoff subsections among 決策/檔案/工作區/現況/下一步
   must be in that order and not duplicated (Phase 2; unrecognized
   `#### ` headings stay fail-open). It still does not confirm Summary
   is accurate or Handoff prose is complete. A heading written for other
   reasons still counts (`docs/design/summary-handoff.md`).
   Remainder — prose quality — stays unverifiable by design.

4. **It isn't literally single.** History can fragment into
   `devlog.archive.md` (compact) and `devlog.<name>.md` (keep).
   SessionStart does not inject keep *files* (SKILL.md, 具名保存) — a
   topic's latest *content* can sit in a file the normal flow never
   surfaces. Phase 3 narrowed the *existence/location* slice: each keep
   leaves a one-line `## Kept 索引` entry in `devlog.md`, and the
   SessionStart excerpt now prints that block, not the keep file's body.
   Keep content is still never auto-injected, by design. Compact's
   archive stays unindexed (it is GC, not the handoff hot path). Index
   lines are not reconciled with the filesystem (a deleted keep file can
   leave a ghost row).

## Recommendation

Keep the SSOT framing, scoped:

> `devlog.md` is the SSOT for **cross-session handoff continuity** on
> one machine. Git is SSOT for the live working tree; `#### 工作區` is
> that tree's cache at close. A keep file is SSOT for a named topic's
> history; the main file only keeps a discovery pointer. The transcript
> and `docs/design/*.md` each own their own kind of truth.

HEAD SKILL.md 核心原則 uses the two-moment wording: write-time verified
cache for `IN_PROGRESS` / `BLOCKED`; read-time `continue` / `resume`
still re-check because the tree can change.

- **Write (`IN_PROGRESS` / `BLOCKED`):** Stop compares `#### 工作區` to
  a snapshot it computed (`hooks/scripts/workspace-snapshot.sh`).
  Mismatch blocks; the section is a fact at `T_close`.
- **Read (`continue` / `resume`):** the cache may be stale; live git is
  still the fact. `docs/design/continue.md`'s claim-vs-fact paragraph
  stays, as a *read-time* rule.

## Roadmap toward SSOT (single-machine scope)

Scope decision unchanged: **single developer, single machine** — not
team-shared. Gaps #1 (git is live-tree SSOT), #3 (lossy), #5
(gitignored), and #6 (not the project KB) are accepted boundaries.

That leaves **#2 and #4** as the actual roadmap. Original text listed
#1 as closable; that was a category error (write-time cache honesty ≠
replacing git).

1. **Machine-generated `#### 工作區`, not hand-typed.** ✅ Implemented
   (`hooks/scripts/workspace-snapshot.sh`, `docs/superpowers/plans/2026-09-10-devlog-ssot-phase1-workspace-verify.md`).
   (closes most of #2's git-state slice; does not close #1)
   `enforce-devlog.sh` computes the snapshot at Stop (same commands
   `continue.md` step 5.1 already runs) and blocks when Claude's
   `#### 工作區` does not match. Fact at write time; `continue` /
   `resume` still re-check at read time.

2. **Minimal structural checks beyond heading presence.** ✅ Implemented
   (Handoff subsection order + duplicate check;
   `docs/superpowers/plans/2026-09-10-devlog-ssot-phase2-handoff-order.md`).
   Remainder of #2's *structure* slice. Not semantic verification —
   that stays unverifiable. `下一步` non-empty is already in HEAD
   (heading-substance); this phase adds order + duplicates among
   決策 → 檔案 → 工作區 → 現況 → 下一步.

3. **Make `keep` files discoverable without full injection.** ✅ Implemented
   (`## Kept 索引` in `devlog.md`;
   `docs/superpowers/plans/2026-09-10-devlog-ssot-phase3-kept-index.md`).
   Narrows #4; does **not** make the log literally single.
   `keep-move.sh` rebuilds one `## Kept 索引` at the true end of
   `devlog.md`; SessionStart prints that block, not keep-file content.
   Independent of phases 1–2.

Phase 1 is still the highest-leverage starting point: it converts the
strongest *write-time* hole (`#### 工作區` as an unverified claim) into
a machine-checked cache, using commands `docs/design/continue.md`
already specifies.

### Optional leftover after phases 1–3

Not part of the original three-phase roadmap. Only the first is
worth picking off if the format starts to drift:

- **One snapshot producer.** ✅ Implemented
  (`workspace-snapshot.sh` is runnable; continue 5.1 runs it;
  `docs/superpowers/plans/2026-09-10-one-snapshot-producer.md`).
  SKILL.md remains the write-time format contract; the script is the
  only machine producer. `continue` / `resume` still re-check because
  the cache may be stale — they no longer re-encode by hand.
- **Ghost keep-index rows.** Phase 3 never reconciles the index with
  files on disk.
- **Archive index.** Out of scope — compact is GC, not handoff.
- **Semantic quality of Summary / 決策 / 現況 / 檔案.** Out of scope.

## Files

| File | Role |
|---|---|
| `skills/devlog-tracker/SKILL.md` | Scoped SSOT claim in 核心原則; 工作區 formats canonical here |
| `docs/design/devlog-as-ssot-assessment.md` | This assessment |
| `docs/design/continue.md` | Read-time claim-vs-fact for `#### 工作區` |
| `docs/design/summary-handoff.md` | Structure vs prose-quality limitation |
| `docs/superpowers/plans/2026-09-10-devlog-ssot-phase1-workspace-verify.md` | Phase 1 plan |
| `docs/superpowers/plans/2026-09-10-devlog-ssot-phase2-handoff-order.md` | Phase 2 plan |
| `docs/superpowers/plans/2026-09-10-devlog-ssot-phase3-kept-index.md` | Phase 3 plan |
