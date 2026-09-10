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
turn's command output matches it (or after a mismatch is recorded).

Run the same commands used to *write* 工作區: `git status --short`,
`git rev-parse --abbrev-ref HEAD`, `git rev-parse --short HEAD`. Not a
git repo → treat live state as `非 git 工作區`. Do not re-run the test
suite unless `下一步` is itself a test command. Do not ask 「上次做到哪」.

Compare to that historical Round's `#### 工作區` (branch, short HEAD,
dirty list or 工作樹乾淨). Missing subsection (older rounds,
`INTERRUPTED` stubs) → no snapshot; live output is the fact.

- **Match** → `IN_PROGRESS` / `INTERRUPTED`: do `下一步` (or derive it
  from 現況 + live tree if `下一步` is absent). `BLOCKED`: state the
  missing input and wait unless verify shows it is now present.
- **Mismatch or no snapshot** → append a `### 段落` on *this* round
  (claim vs live: branch / HEAD / dirty). Then act from the live tree.

`/devlog-tracker:resume` uses this same check, then still waits for
confirmation before starting work. SessionStart still does not inject
git; if the injected excerpt leads Claude to act on `下一步`, it must
run this check first. `/devlog-tracker:start` only summarises; no check.

## Files

| File | Role |
|---|---|
| `hooks/scripts/session-start-devlog.sh` | `source=clear` heals then exits without stdout |
| `hooks/scripts/test-session-start-devlog.sh` | silent clear; resume still injects |
| `commands/continue.md` | Authoring instructions, including verify-then-act |
| `commands/resume.md` | Same verify, then wait for confirm |
| `skills/devlog-tracker/SKILL.md` | Clear is empty; continue is the resume path; fallback also verifies |
| `docs/design/continue.md` | This spec |
