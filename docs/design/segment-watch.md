# Segment Watch (mid-round silence valve)

Round Segments stay a judgment call: Claude writes a `### 段落` when a
meaningful stage result exists, not on a timer. Segment Watch is a
safety valve for the remaining case — a single round that runs a long
time with **no** `devlog.md` change. After 15 minutes of silence it
blocks the next tool (`PreToolUse`, exit 2) until Claude appends
something, even one line.

This is not Span Mode (automated wakeups) and not Checkpoint Mode
(cross-round summaries). Those mechanisms stay unchanged.

## Motivation

The Stop hook only runs when Claude tries to end the turn. A long
interactive round can do a lot of work, crash or be killed, and leave
no mid-round trace even though SKILL.md already asks for `### 段落`.
The convention is the precise path; without a hook, nothing forces a
write until the turn ends.

Claude Code has no background timer during a turn. The valve can only
run when a tool is about to fire, and compare wall-clock time against
the last time `devlog.md`'s content hash changed.

## Design constraint

- **Precision first.** Do not require `### 段落` headings, and do not
  block just because the round has lasted 15 minutes. Only silence
  (no hash change) trips the valve. A short round, or a long round
  that already wrote segments, is unaffected.
- **Fail-open.** Same as every other hook in this plugin: missing
  files, unreadable JSON, non-numeric fields, or a failed `cksum` /
  `date` mean exit 0.
- **Do not author `devlog.md` from a hook.** Claude writes; the hook
  only checks.
- **Allow the write that satisfies the block.** If the upcoming tool
  is Write or Edit targeting this project's `.devlog/devlog.md`, pass
  even when the timer has expired — otherwise Claude cannot unblock
  itself.

## Mechanism

### `.devlog/.segment-state`

Created by `/devlog-tracker:start` alongside `.enabled` and
`.checkpoint-state`. Hooks own the file (Claude may edit
`max_silent_seconds` directly, same as `max_silent_rounds`). If the
file already exists, start must not reset `max_silent_seconds`.

```json
{ "last_change_epoch": 0, "last_seen_cksum": "", "max_silent_seconds": 900 }
```

| Field | Meaning |
|---|---|
| `last_change_epoch` | Unix seconds. `round-start.sh` sets this to now at the start of every round. `segment-watch.sh` sets it to now whenever `devlog.md`'s cksum differs from `last_seen_cksum`. |
| `last_seen_cksum` | Last observed `cksum` of `devlog.md` (or `MISSING` if the file is absent). Used only to detect a change; not a second copy of `.turn-start`. |
| `max_silent_seconds` | Default `900` (15 minutes). No enforced range. |

`/devlog-tracker:pause` deletes `.enabled` (and `.span-open`, as
today) but leaves `.segment-state` in place so the threshold survives
a later start.

A malformed or missing `.segment-state` is treated as "no segment
watch" at every read site.

### Hook behavior

- **`round-start.sh`** (`UserPromptSubmit`): existing behavior
  unchanged, plus: if `.enabled` exists and `.segment-state` is
  well-formed, set `last_change_epoch` to now and `last_seen_cksum` to
  the current `devlog.md` cksum (or `MISSING`). Do not rewrite
  `max_silent_seconds`.
- **`segment-watch.sh`** (`PreToolUse`): after the `.enabled` switch
  check, if `.segment-state` is well-formed:
  1. Compute the current `devlog.md` cksum. If it differs from
     `last_seen_cksum`, persist the new cksum and `last_change_epoch =
     now`, then exit 0.
  2. If the incoming tool is `Write` or `Edit` and `tool_input.file_path`
     is exactly `.devlog/devlog.md` or ends with `/.devlog/devlog.md`,
     exit 0. No `realpath`; string suffix only.
  3. If `now - last_change_epoch >= max_silent_seconds`, print a
     stderr message asking Claude to append a `### 段落` (one line is
     enough) to `.devlog/devlog.md`, then exit 2.
  4. Otherwise exit 0.

Stdin is the standard Claude Code PreToolUse payload
(`tool_name`, `tool_input`). Parse with `jq` when present; otherwise
string-match the same fields. Unreadable stdin is fail-open.

Blocking uses `exit 2` + stderr, matching `enforce-devlog.sh`. Do not
use the JSON `permissionDecision` path.

### Interaction with Span Mode

Do **not** disable this valve while a span is open. Span Mode's
`max_silent_ticks` skips the Stop-hook write on short automated
wakeups. If a single wakeup then spends 15+ minutes of tool use
without touching `devlog.md`, that is the same mid-round silence
problem this valve exists for.

`round-start.sh` still resets `last_change_epoch` on every
`UserPromptSubmit`, including automated ticks. A loop that wakes
every few minutes and does little work will not trip the 15-minute
valve; a single long tick can.

### Interaction with Checkpoint Mode

None beyond shared `.enabled`. A mid-round segment write changes
`devlog.md`'s hash (good for Stop) but is not a `## Checkpoint`
heading, so it does not reset `rounds_since_checkpoint`.

## Lifecycle

Always on once `/devlog-tracker:start` has run — no per-task opt-in.
Pause stops it because `.enabled` is gone. There is no slash command
to open or close a watch.

## Known Limitations

- **No background alarm.** If Claude thinks for 15 minutes without
  calling a tool, the valve does not fire.
- **Bash (and other tools) that rewrite `devlog.md` are not
  allowlisted.** Only Write/Edit on that path pass while expired.
  After such a Bash write, the next PreToolUse would see a hash
  change and reset the timer — but the Bash call itself would still
  be blocked if already expired. Considered acceptable: SKILL.md
  already tells Claude to use Write/Edit for `devlog.md`.
- **Any hash change resets the timer.** Same trust level as the Stop
  hook: presence of a write, not quality of a `### 段落`.
- **Subagents / other cwd.** The script uses `CLAUDE_PROJECT_DIR`.
  If a tool's `file_path` is a different spelling of the same file
  that does not suffix-match `.devlog/devlog.md`, it is not
  allowlisted.
- **Subagent tool calls share the parent round's valve.** PreToolUse
  also runs for subagent tool calls that share the parent round's
  `.segment-state`; a subagent has no UserPromptSubmit reset and may
  be asked to write a `### 段落` it cannot contextualize. This is
  accepted for now (same valve, no subagent exemption).

## Files

| File | Role |
|---|---|
| `hooks/scripts/round-start.sh` | Reset `last_change_epoch` / `last_seen_cksum` each round |
| `hooks/scripts/segment-watch.sh` | New PreToolUse checker |
| `hooks/scripts/test-segment-watch.sh` | Self-check (no `.enabled`; fresh round; expired + Bash blocks; expired + Write `devlog.md` passes; hash change then Bash passes; expired + Write other file blocks; malformed state fail-open) |
| `hooks/hooks.json` | Register PreToolUse → `segment-watch.sh` |
| `commands/start.md` | Create `.segment-state` if missing |
| `skills/devlog-tracker/SKILL.md` | Document the 15-minute valve under Round Segments |
| `docs/design/checkpoint-mode.md` | Point Round Segments' "mechanism: none" at this valve |
| `README.md` | Mention the mid-round silence valve |

`enforce-devlog.sh` is unchanged. Stop still only requires a hash
change (and existing heading / checkpoint checks) at end of turn.
