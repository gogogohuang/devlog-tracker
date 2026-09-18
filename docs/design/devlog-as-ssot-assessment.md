# Devlog SSOT Review

Reviewed: 2026-09-15 10:15 (+0800)
Branch: `feat/l1-ssot-handoff` (uncommitted L1 contract work on top of
`9e50382` / plugin **0.14.0** on `main`)
Previous review: 2026-09-11 16:52 against `3cc1341` (plugin **0.11.0**,
Phases 1–4 only)

Verdict: `devlog.md` remains SSOT for **cross-session handoff continuity**
on **one developer / one machine**, and is now also the **L1 handoff
entry**: after a human `continue` (or SessionStart inject), an agent can
act from the file + live git **and must write the turn back**.

**The goal is still not to become git.** Stop reads git and checks
`#### 工作區` and `#### 檔案`. Git stays SSOT for the live tree.
`devlog.md` caches checked claims plus authoring fields (`Reply`,
`完成條件`, prose) that git cannot verify.

## Layered SSOTs (unchanged ontology)

| Layer | SSOT for | L1 role |
|---|---|---|
| git | live working tree | verify-then-act baseline |
| `.devlog/devlog.md` | handoff continuity + write-back | main entry |
| `docs/design/*.md` | design decisions | read when Handoff / `下一步` points here |
| code + tests | implementation truth | final acceptance |
| transcript | verbatim chat | not required after `/clear` |
| keep / archive / lessons | named topic / old DONE / process lessons | only if `下一步` names them |

## L1 hard rules

1. **Verify then act.** Compare last historical Round’s `#### 工作區` to
   `workspace-snapshot.sh` stdout; act from the live tree
   (`docs/design/continue.md`, `commands/continue.md`).
2. **Write back.** Close the **current** Round with `### Summary` /
   `### Reply` / `### Handoff` / `### Status`. When still open, also
   `#### 工作區` / `#### 完成條件` / `#### 下一步`. Do not edit historical
   Rounds. Reading without writing back is an L1 failure.
3. **Enforcement vs duty.** With `.enabled`, Stop blocks incomplete
   closes. Without Stop / before `start` / Cursor without hooks, the
   agent still must write. Subagents that only change code leave
   write-back to the parent (or the brief must require it).

**Not L1**

- **L2:** unattended wake (cron / loop without human continue). Span
  Mode stays a narrow automated-continuation tool, not L2.
- **L3:** portable / shared `.devlog/` (gitignore, one machine).

## What Stop enforces at close (L1 branch)

`hooks/scripts/enforce-devlog.sh` (working tree on this branch).

A turn cannot end until the last Round has:

1. `### Summary`, `### Reply`, and `### Handoff` with non-empty bodies
2. Legal `### Status`: `DONE` | `IN_PROGRESS` | `BLOCKED` | `INTERRUPTED`
3. Non-empty `#### 完成條件` and `#### 下一步` when Status is
   `IN_PROGRESS` or `BLOCKED`
4. Present Handoff subsections in order  
   決策 → 檔案 → 工作區 → 現況 → 完成條件 → 下一步, no duplicates
5. `#### 下一步` not a pure filler blacklist phrase
   (`docs/design/next-step-blacklist.md`)
6. `IN_PROGRESS` only: light actionable lint on `#### 下一步` (path,
   backtick command, file-ish token, or skill mention)
7. `BLOCKED` only: missing-input phrase in `現況` or `下一步`
   (缺／等待／等使用者／出現即 …)
8. `#### 工作區` matching `workspace-snapshot.sh` when Status is
   `IN_PROGRESS` / `BLOCKED`, and when Status is `DONE` with a non-empty
   `#### 檔案`
9. Non-empty `#### 檔案` matching `files-snapshot.sh` (commit exact;
   uncommitted one-directional subset)

Slogan: **structure + two machine-verified caches (`工作區`, `檔案`) +
L1 presence/lint fields (`Reply`, `完成條件`, actionable / 缺件).**
Summary / Reply / 決策 / 現況 / 完成條件 *wording quality* is still on
Claude — Stop does not score prose.

`close-open-round.sh` interrupt stubs now include a `### Reply` stub so
INTERRUPTED rounds still satisfy the three-heading shape if they become
last again.

## Phases

| Phase | Status | Buys | Not a goal / still open |
|---|---|---|---|
| 1. Machine-verify `#### 工作區` | ✅ `main` | Write-time honesty of the git cache | Replacing git; trivial `DONE` with no `#### 檔案`; `INTERRUPTED` stubs |
| 2. Handoff order + duplicates | ✅ `main` (extended on this branch for `完成條件`) | Cheap structure on recognized `####` names | Semantic quality of Summary / Reply / 決策 / 現況 |
| 3. `## Kept 索引` in `devlog.md` | ✅ `main` | Keep *files* discoverable without injecting content | Auto-inject keep body; archive index; ghost rows |
| 4. Machine-verify `#### 檔案` | ✅ `main` | Write-time honesty of this Round’s change list | Read-time re-check of `檔案`; prose truthfulness |
| 5. L1 handoff contract | ✅ this branch (working tree) | Reply + 完成條件 + write-back duty + light next-step / BLOCKED lint so a successor agent can finish without re-asking “做到哪” | L2 wake; L3 sharing; semantic scoring of 完成條件 / Reply |

### Phase 4 rules (unchanged; `docs/design/files-verify.md`)

- Runs when `#### 檔案` is non-empty, independent of Status.
- `commit <hash>：` — exact, bidirectional, category-precise.
- `尚未 commit：` — one-directional subset. Claimed paths must be dirty.
  Extra dirty paths from earlier Rounds are not an error.
- Rename = 刪除 + 新增. `.devlog/` excluded.
- Bad grammar blocks the turn (not fail-open).
- `continue` / `resume` do **not** re-check `檔案`. Live cache is
  `工作區` only.

### Phase 5 rules (this branch)

- `### Reply`: required non-empty on every normal close (trivial rounds
  included). Records what was said / promised to the user.
- `#### 完成條件`: required when `IN_PROGRESS` / `BLOCKED`. Observable
  DONE predicate for the next agent. Omit on finished `DONE`.
- User Input: verbatim-first at hook write; Claude must not rewrite
  (`docs/design/recording-moments.md`). Truncate / redact remain the
  only allowed fidelity loss.
- `AskUserQuestion`: in-round `### 段落（AskUserQuestion）` (no
  `await-open.sh`). Plain-text cross-turn Q&A still uses Reply Fold.
- Authoring write-back spelled in `commands/continue.md` step 6,
  `commands/resume.md`, and SKILL「L1 寫回義務」— including no-Stop
  paths and subagent responsibility.

## Write vs read

- **Write — `工作區`:** Stop vs `workspace-snapshot.sh`. Required for
  `IN_PROGRESS` / `BLOCKED`, and for `DONE` when `#### 檔案` is
  non-empty. Fact at `T_close`.
- **Write — `檔案`:** Stop vs `files-snapshot.sh` when non-empty. Fact
  at `T_close` for claimed paths.
- **Write — `Reply` / `完成條件` / actionable / 缺件:** presence and
  pattern checks only. Not git-backed.
- **Read — `工作區` only:** `continue` / `resume` / same-session next
  message. Cache may be stale; live git is the fact. Last-Round `DONE`
  skips the same-session gate. Re-check exists because the tree can
  change — not because the goal is to stop using git.
- **Read — `完成條件` / `下一步` / `Reply`:** successor trusts authoring;
  no machine re-score.

## Non-goals (design, not leftover work)

1. **Become git.** Git is live-tree SSOT. `devlog.md` reads it.
2. **Become a transcript.** User Input is hook-verbatim with truncate /
   redact; unwritten `### 段落` are dropped; Claude replies are
   summarized in `### Reply`, not full chat dumps.
3. **Become portable / shared (L3).** `.devlog/` is gitignored.
4. **Become the project knowledge base.** Design lives in
   `docs/design/*.md`. Code is the code.
5. **L2 unattended wake.** Human opt-in `continue` (and SessionStart
   inject without auto-start on `/clear`) stays intentional.

## Still open (honesty, not ontology)

- Summary / Reply / 決策 / 現況 / 完成條件 prose quality — unverifiable
  by git; actionable / 缺件 checks are pattern-based (false negatives
  OK).
- Ghost `## Kept 索引` rows vs deleted keep files (`docs/design/keep.md`).
- Same-session `工作區` gate skips turns with no tools; SessionStart
  does not inject live git; `.devlog/.lock` is 2s fail-open.
- Unclosed fence can skip heading extraction (`devlog-md.sh`); Stop
  NOFENCE fail-open mitigates odd fence counts on body checks.
- `commands/keep.md` still does not mention `## Kept 索引` (design spec
  does). Optional lockstep, unchanged from 2026-09-11.
- Plugin / marketplace one-line description not yet mentioning Reply /
  完成條件 / L1 write-back (product surface lag on this branch).

## Doc lag vs this branch

| File | Status |
|---|---|
| `skills/devlog-tracker/SKILL.md` | Aligned: L1 write-back, Reply, 完成條件, verbatim User Input, AskUserQuestion 段落 |
| `docs/design/summary-handoff.md` | Aligned: three readers; six Handoff subsections; Stop L1 lint |
| `docs/design/continue.md` | Aligned: write-back hard rule |
| `commands/continue.md` / `resume.md` | Aligned: step 6 / post-confirm write-back |
| `docs/design/recording-moments.md` | Aligned: verbatim-first User Input |
| `docs/design/reply-fold.md` + skill reference | Aligned: AskUserQuestion in-round 段落 |
| `README.md` | Aligned: L1 framing + Round shape |
| `hooks/scripts/enforce-devlog.sh` + tests | Aligned: Reply / 完成條件 / actionable / 缺件 |
| `hooks/scripts/close-open-round.sh` | Aligned: Reply stub on interrupt |
| `.claude-plugin/plugin.json` / `marketplace.json` | Still 0.14.0 wording without L1 Reply／完成條件 (optional) |
| `commands/keep.md` | Was silent on `## Kept 索引` (pre-existing) as of this review; resolved since — `commands/keep.md` now references the index and `keep-move.sh --desc` writes into it (see `docs/design/keep.md`) |

## Recommendation

Keep the scoped framing, now including L1:

> `devlog.md` is the SSOT for **cross-session handoff continuity** on one
> machine, and the **L1 entry** for human-triggered continue: verify
> `工作區`, do `下一步` against `完成條件`, write Summary／Reply／Handoff／
> Status back. Git is SSOT for the live working tree. `#### 工作區` /
> `#### 檔案` are machine-checked caches at close. A keep file is SSOT
> for a named topic; the main file only keeps a discovery pointer.

Do not add a phase whose success criterion is "devlog becomes git" or
"devlog becomes L2/L3". Optional small locksteps: `commands/keep.md`
Kept 索引; plugin description Mentions for Reply／完成條件 after merge.

## Files (roles on this review)

| File | Role |
|---|---|
| `docs/design/devlog-as-ssot-assessment.md` | This review |
| `skills/devlog-tracker/SKILL.md` | Authoring + L1 write-back |
| `docs/design/summary-handoff.md` | Round shape + Stop enforcement spec |
| `docs/design/continue.md` | Read-time verify + write-back |
| `docs/design/files-verify.md` | Phase 4 `檔案` grammar |
| `docs/design/recording-moments.md` | Submit / close / interrupt; verbatim User Input |
| `docs/design/reply-fold.md` | Plain-text fold + AskUserQuestion 段落 |
| `docs/design/next-step-blacklist.md` | Filler blacklist (non-semantic) |
| `README.md` | Product surface; L1 framing |
| `hooks/scripts/enforce-devlog.sh` | Stop checks |
| `hooks/scripts/close-open-round.sh` | INTERRUPTED stubs incl. Reply |
| `hooks/scripts/workspace-snapshot.sh` | `工作區` producer |
| `hooks/scripts/files-snapshot.sh` | `檔案` producer |
| `commands/continue.md` | Verify-then-act + write-back |
| `commands/resume.md` | Verify, wait, then write-back on confirm |
