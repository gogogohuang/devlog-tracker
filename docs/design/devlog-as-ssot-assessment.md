# Devlog SSOT Review

Reviewed: 2026-09-11 16:32
HEAD: `07f65ed` on `main` (plugin **0.11.0**)
HEAD commit: 2026-09-11 16:27 — Merge pull request #10 from `feat/files-verify`

Verdict: **`devlog.md` is SSOT for cross-session handoff continuity**
(decisions, blockers, next step), for **one developer on one machine**.

**The goal is not to become git.** The goal is an honest Handoff at
close. Stop reads git and checks `#### 工作區` and `#### 檔案`. Git
stays SSOT for the live tree. `devlog.md` caches a checked claim. It
does not replace git. Calling "not SSOT for file state" a remaining
gap is a category error.

It is also not a transcript, not literally one file after compact/keep,
and not a team-shared durable store (`.devlog/` is gitignored).

File times below are git last-commit author time (`YYYY-MM-DD hh:mm`,
`+0800`).

## What Stop enforces at close (2026-09-11 16:15)

`hooks/scripts/enforce-devlog.sh` last commit: 2026-09-11 16:15.

A turn cannot end until the last Round has:

1. `### Summary` and `### Handoff` with non-empty bodies
2. Legal `### Status`: `DONE` | `IN_PROGRESS` | `BLOCKED` | `INTERRUPTED`
3. Non-empty `#### 下一步` when Status is `IN_PROGRESS` or `BLOCKED`
4. Present Handoff subsections in order
   決策 → 檔案 → 工作區 → 現況 → 下一步, no duplicates
5. `#### 工作區` matching `workspace-snapshot.sh` (2026-09-11 10:15)
   when Status is `IN_PROGRESS` / `BLOCKED`, and when Status is `DONE`
   with a non-empty `#### 檔案`
6. Non-empty `#### 檔案` matching `files-snapshot.sh` (2026-09-11 15:50)

Slogan: **structure plus two machine-verified cache fields
(`工作區`, `檔案`).** Summary / 決策 / 現況 prose is still on Claude.

## Four phases

| Phase | Status | Buys | Not a goal / still open | Landed |
|---|---|---|---|---|
| 1. Machine-verify `#### 工作區` | ✅ on `main` | Write-time honesty of the git cache | Replacing git; trivial `DONE` with no `#### 檔案`; `INTERRUPTED` stubs | `ed4a6e4`; DONE-with-檔案 `98a76ee` 2026-09-11 14:42 |
| 2. Handoff order + duplicates | ✅ on `main` | Cheap structure on the five `####` names | Semantic quality of Summary / 決策 / 現況 | `ab0e68c` |
| 3. `## Kept 索引` in `devlog.md` | ✅ on `main` | Keep *files* discoverable without injecting content | One literal file; auto-inject keep body; archive index; ghost rows | `keep-move.sh` 2026-09-10 23:51; SessionStart 2026-09-10 23:52 |
| 4. Machine-verify `#### 檔案` | ✅ on `main` (PR #10, 2026-09-11 16:27) | Write-time honesty of this Round's change list | Replacing git; read-time re-check of `檔案`; Summary / 決策 / 現況 | spec 2026-09-11 15:11; producer 2026-09-11 15:50; Stop 2026-09-11 16:15 |

### Phase 4 rules (`docs/design/files-verify.md`, 2026-09-11 15:11)

- Runs when `#### 檔案` is non-empty, independent of Status.
- `commit <hash>：` — exact, bidirectional, category-precise.
- `尚未 commit：` — one-directional subset. Claimed paths must be dirty.
  Extra dirty paths from earlier Rounds are not an error. Category not
  checked on this block.
- Rename = 刪除 + 新增. `.devlog/` excluded.
- Bad grammar blocks the turn (not fail-open).
- `continue` / `resume` do **not** re-check `檔案`. It is historical.
  Live cache is `工作區` only.

## Write vs read

- **Write — `工作區` (2026-09-11 14:42 / 16:15):** Stop vs
  `workspace-snapshot.sh`. Required for `IN_PROGRESS` / `BLOCKED`, and
  for `DONE` when `#### 檔案` is non-empty. Fact at `T_close`.
- **Write — `檔案` (2026-09-11 16:15):** Stop vs `files-snapshot.sh`
  when the section is non-empty. Fact at `T_close` for claimed paths.
- **Read — `工作區` only (2026-09-11 11:14):** `continue` / `resume` /
  same-session next message. Cache may be stale; live git is the fact.
  Last-Round `DONE` skips the same-session gate. Re-check exists
  because the tree can change — not because the goal is to stop using
  git.

## Non-goals (design, not leftover work)

1. **Become git.** Git is live-tree SSOT. `devlog.md` reads it.
3. **Become a transcript.** User Input is close, truncated, redacted.
   Unwritten `### 段落` are dropped.
5. **Become portable / shared.** `.devlog/` is gitignored.
6. **Become the project knowledge base.** Design lives in
   `docs/design/*.md`. Code is the code.

## Still open (in scope of honesty, not ontology)

- Summary / 決策 / 現況 prose quality — unverifiable by git.
- Ghost `## Kept 索引` rows vs deleted keep files.
- Same-session `工作區` gate skips turns with no tools; SessionStart
  does not inject live git; `.devlog/.lock` is 2s fail-open
  (`devlog-lock.sh` 2026-09-09 16:09).
- Unclosed fence can skip heading extraction (`devlog-md.sh`
  2026-09-11 14:42).

## Doc lag vs HEAD (2026-09-11, resolved this pass)

Four docs were behind `main`'s write-time rules. All four are fixed in this
same working-tree pass (not yet committed as of this review):

| File | Was | Fix |
|---|---|---|
| `skills/devlog-tracker/SKILL.md` | `#### 工作區` format note still said `DONE`／`INTERRUPTED` 不受影響 | Now says `DONE` 若「檔案」有內容也核對，只有沒動檔的 `DONE` 與 `INTERRUPTED` 不受影響 |
| `docs/design/summary-handoff.md` | Known limitations said `DONE` / `INTERRUPTED` do not require `#### 工作區` | Now scopes that to a trivial `DONE` with no `#### 檔案` |
| `docs/design/keep.md` | No `## Kept 索引` section | Added a "Kept index" section describing `keep-move.sh`'s rebuild-and-append behavior and SessionStart's surfacing of it |
| `.claude-plugin/plugin.json` / `marketplace.json` | Description named 工作區 verify; omitted `檔案` verify | Both descriptions now mention 檔案 content-verify (commit exact, uncommitted one-directional) |

## Recommendation

Keep the scoped framing:

> `devlog.md` is the SSOT for **cross-session handoff continuity** on
> one machine. Git is SSOT for the live working tree. `#### 工作區` is
> that tree's cache at close. `#### 檔案` is this Round's change-list
> cache at close. A keep file is SSOT for a named topic; the main file
> only keeps a discovery pointer.

Do not add a phase whose success criterion is "devlog becomes git".

## Files (git last-commit)

| File | Updated | Role |
|---|---|---|
| `docs/design/devlog-as-ssot-assessment.md` | 2026-09-11 16:32 | This review (working tree; last git commit 2026-09-11 15:54) |
| `skills/devlog-tracker/SKILL.md` | 2026-09-11 15:54 | Scoped SSOT claim; `檔案` grammar |
| `docs/design/files-verify.md` | 2026-09-11 15:11 | Phase 4 spec |
| `docs/design/continue.md` | 2026-09-11 11:14 | Read-time `工作區` claim-vs-fact; same-session gate |
| `docs/design/summary-handoff.md` | 2026-09-11 16:15 | Structure + two cache fields |
| `docs/design/recording-moments.md` | 2026-09-10 18:11 | Three recording moments; lock; redact |
| `docs/design/keep.md` | 2026-09-10 17:58 | Keep move; missing Kept 索引 |
| `docs/design/segment-watch.md` | 2026-09-11 14:44 | PreToolUse gate; read-only git |
| `README.md` | 2026-09-11 16:23 | Product surface; 0.11.0; both verifies |
| `.claude-plugin/plugin.json` | 2026-09-11 16:23 | Version 0.11.0 |
| `hooks/scripts/workspace-snapshot.sh` | 2026-09-11 10:15 | `工作區` producer |
| `hooks/scripts/files-snapshot.sh` | 2026-09-11 15:50 | `檔案` producer |
| `hooks/scripts/enforce-devlog.sh` | 2026-09-11 16:15 | Stop checks |
| `hooks/scripts/round-start.sh` | 2026-09-11 11:06 | Skeleton; same-session `工作區` |
| `hooks/scripts/session-start-devlog.sh` | 2026-09-10 23:52 | Excerpt; Kept 索引; no live git |
| `hooks/scripts/keep-move.sh` | 2026-09-10 23:51 | Trailing `## Kept 索引` |
| `hooks/scripts/devlog-md.sh` | 2026-09-11 14:42 | Round/fence helpers |
| `hooks/scripts/devlog-lock.sh` | 2026-09-09 16:09 | `.devlog/.lock`; 2s fail-open |
| `commands/continue.md` | 2026-09-11 10:15 | Verify-then-act for `工作區` |
| `commands/resume.md` | 2026-09-11 09:41 | Same verify; wait before `下一步` |
| `commands/keep.md` | 2026-09-10 18:03 | Keep authoring |
