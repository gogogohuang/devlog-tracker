# Continue (explicit resume after empty context)

`/devlog-tracker:continue` reads `.devlog/devlog.md` and resumes from
the last Round's Handoff. It is the only resume path after `/clear`.

`/clear` still wipes the conversation. SessionStart (`source=clear`)
may stamp a dangling open Round `INTERRUPTED`, but it prints nothing
to stdout, so Claude Code injects no additionalContext. A later
`startup` / `resume` / `compact` / `fork` still injects the last 8
rounds, as before.

This is a slash command (plus the skill matching 接續 / continue /
繼續上一題). No new hooks.

## Motivation

Auto-injecting the log on `/clear` made clear look like it had not
cleared. The file remains the source of truth; the user opts in to
reload it.

`/devlog-tracker:start` is the wrong resume button: it enables
enforcement and confirms progress. Continue actually does the next
step.

## SessionStart

| `source` | Heal dangling `.round-open` | Inject last 8 rounds + span note |
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
3. Act on the last **historical** Round (not the continue-turn skeleton):
   - `IN_PROGRESS` / `INTERRUPTED` → do Handoff `下一步` immediately.
   - `BLOCKED` → state the missing input; wait.
   - `DONE` → say the previous ask finished; wait for a new ask.
4. Close this turn on the open Round as usual (Summary / Handoff / Status).

## Files

| File | Role |
|---|---|
| `hooks/scripts/session-start-devlog.sh` | `source=clear` heals then exits without stdout |
| `hooks/scripts/test-session-start-devlog.sh` | silent clear; resume still injects |
| `commands/continue.md` | Authoring instructions |
| `skills/devlog-tracker/SKILL.md` | Clear is empty; continue is the resume path |
| `docs/design/continue.md` | This spec |
