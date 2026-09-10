# Continue (explicit resume after empty context)

`/devlog-tracker:continue` reads `.devlog/devlog.md` and resumes from
the last Round's Handoff after checking `#### 工作區` against the live
tree. It is the only resume path after `/clear`.

`/clear` still wipes the conversation. SessionStart (`source=clear`)
may stamp a dangling open Round `INTERRUPTED`, but it prints nothing
to stdout, so Claude Code injects no additionalContext. A later
`startup` / `resume` / `compact` / `fork` still injects the SessionStart excerpt (last Checkpoint + last two Rounds' close), as `session-start-devlog.sh` does.

This is a slash command (plus the skill matching 接續 / continue /
繼續上一題). No new hooks.

## Motivation

Auto-injecting the log on `/clear` made clear look like it had not
cleared. The file remains the source of truth; the user opts in to
reload it.

`/devlog-tracker:start` is the wrong resume button: it enables
enforcement and confirms progress. Continue actually does the next
step, after the cheap git check below.

## SessionStart

| `source` | Heal dangling `.round-open` | Inject excerpt + span note |
|---|---|---|
| `startup` / `resume` / `fork` | yes | yes |
| `compact` | no | yes |
| `clear` | yes | **no** (exit 0 after heal) |

After `/clear`, a generic new request must not read `devlog.md` to
pick up old work. Only continue (or start, which only summarises).

## Command flow

1. Missing `devlog.md` → say there is nothing to continue; write nothing.
2. Open `.span-open` → mention it; continue the span unless the user
   asked to close it.
3. Read recent rounds (and the last Checkpoint if any). Do not read
   archive or keep files unless `下一步` names them.
4. Last **historical** Round (not the continue-turn skeleton):
   - `DONE` → say the previous ask finished; wait. No git check.
   - `IN_PROGRESS` / `INTERRUPTED` / `BLOCKED` → **verify, then act**.
5. Close this turn on the open Round as usual (Summary / Handoff /
   Status, including `#### 工作區` when the new Status is `IN_PROGRESS`
   or `BLOCKED`). Do not edit the historical Round.

## Verify before acting

Handoff `#### 工作區` is a claim. It becomes a fact only after this
turn's encoded snapshot matches it (or after a mismatch is recorded).

Run the same commands used to *write* 工作區 — the exact commands and
output format are canonical in `skills/devlog-tracker/SKILL.md`
(`#### 工作區`) and mirrored verbatim in `commands/continue.md` step
5.1, not respelled here. Encode the live command output in those four
formats (clean / dirty / not a git repo / detached HEAD), then compare
that snapshot to the historical Round's `#### 工作區` body. Not a git
repo → treat live state as `非 git 工作區`. Do not re-run the test
suite unless `下一步` is itself a test command. Do not ask 「上次做到哪」.

- **Missing subsection** (older rounds, `INTERRUPTED` stubs) → no
  snapshot, so there is no claim to compare. Do not append a `### 段落`;
  the encoded live snapshot is simply the fact.
- **Present but mismatched** → append a `### 段落` on *this* round
  (claim vs live, in the same four formats).
- **Present and matching** → no `### 段落` needed.
- **Then act from the live tree**, not from the claimed `工作區` /
  `現況` wording:
  - `IN_PROGRESS` / `INTERRUPTED`: do `下一步` (or derive it from 現況
    + live tree if `下一步` is absent).
  - `BLOCKED`: whether the missing external input is now present is
    independent of the git check. If present, proceed; else state it
    and wait. A matching or mismatching `工作區` does not prove the
    input arrived.

`/devlog-tracker:resume` runs the same git check (steps 5.1–5.2) and
writes a `### 段落` on mismatch, then still waits for confirmation
before doing `下一步`. It must not follow continue's immediate-act
step (5.3). SessionStart still does not inject git; if the injected
excerpt leads Claude to act on `下一步`, it must run this check first.
`/devlog-tracker:start` only summarises; no check.

## Files

| File | Role |
|---|---|
| `hooks/scripts/session-start-devlog.sh` | `source=clear` heals then exits without stdout |
| `hooks/scripts/test-session-start-devlog.sh` | silent clear; resume still injects |
| `commands/continue.md` | Authoring instructions, including verify-then-act |
| `commands/resume.md` | Same verify, then wait for confirm |
| `skills/devlog-tracker/SKILL.md` | Clear is empty; continue is the resume path; fallback also verifies |
| `docs/design/continue.md` | This spec |
