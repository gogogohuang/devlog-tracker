# Segment Watch (mid-round silence valve)

Round Segments stay a judgment call: Claude writes a `### 段落` when a
meaningful stage result exists, not on a timer. Segment Watch is a
safety valve for the remaining case — a single round that runs a long
time with **no** `devlog.md` change. After 10 minutes of silence
(default; adjustable, see below) it blocks the next tool (`PreToolUse`,
exit 2) until Claude appends something, even one line.

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
  block just because the round has lasted 10 minutes. Only silence
  (no hash change) trips the valve. A short round, or a long round
  that already wrote segments, is unaffected.
- **Fail-open.** Same as every other hook in this plugin: missing
  files, unreadable JSON, non-numeric fields, or a failed `cksum` /
  `date` mean exit 0.
- **Do not author `devlog.md` from a hook.** Claude writes; the hook
  only checks.
  Exception (see `docs/design/recording-moments.md`): `UserPromptSubmit` writes the
  Round skeleton, and interrupt helpers patch Status to `INTERRUPTED`. Segment Watch
  itself still only checks.
- **Allow the write that satisfies the block.** If the upcoming tool
  is Write or Edit targeting this project's `.devlog/devlog.md`, pass
  even when the timer has expired — otherwise Claude cannot unblock
  itself.

## Mechanism

### `.devlog/.segment-state`

Created by `/devlog-tracker:start` alongside `.enabled` and
`.checkpoint-state`. Hooks own the file; `/devlog-tracker:start` itself
must not reset `max_silent_seconds` on an existing file. The dedicated
`/devlog-tracker:segment-watch <time length>` command is the supported way
to change the threshold (see "Adjusting the threshold" below); Claude may
still edit `max_silent_seconds` directly in a pinch, same as
`max_silent_rounds`.

```json
{ "last_change_epoch": 0, "last_seen_cksum": "", "max_silent_seconds": 600 }
```

| Field | Meaning |
|---|---|
| `last_change_epoch` | Unix seconds. `round-start.sh` sets this to now at the start of every round. `segment-watch.sh` sets it to now whenever `devlog.md`'s cksum differs from `last_seen_cksum`. |
| `last_seen_cksum` | Last observed `cksum` of `devlog.md` (or `MISSING` if the file is absent). Used only to detect a change; not a second copy of `.turn-start`. |
| `last_seen_mtime` / `last_seen_size` | Optional cheap identity. When both match the live file, PreToolUse may skip re-running `cksum` and reuse `last_seen_cksum`. Missing keys fall through to a full `cksum`. |
| `max_silent_seconds` | Default `600` (10 minutes). No enforced range. |

### Adjusting the threshold

A dedicated command, `/devlog-tracker:segment-watch <time length>`, sets
`max_silent_seconds` without touching anything else `/devlog-tracker:start`
manages. `commands/segment-watch.md` tells Claude to get a time length from
the user (asking if none was given — never guessing one), convert it to a
positive integer number of seconds, and run:

```bash
hooks/scripts/segment-watch-set.sh <seconds>
```

`segment-watch-set.sh` behavior:

- `.devlog/.enabled` missing (project never started): print `NOT_STARTED`
  and exit 0 — no files created or changed. `commands/segment-watch.md`
  offers to run `/devlog-tracker:start` instead of guessing a threshold
  for a project that isn't tracking yet.
- `$1` is not a positive integer (missing, non-digit, or `0`): exit 1 with
  a stderr message; no files are created or changed.
- `.segment-state` missing: create it fresh with `$1` as
  `max_silent_seconds` (matching `start-devlog.sh`'s default shape).
- `.segment-state` exists: patch just `max_silent_seconds` via
  `json_int_set`, preserving `last_change_epoch` / `last_seen_cksum` /
  `session_id`. If the existing file didn't have a matching key to patch
  (hand-edited / malformed), rebuild it fresh from whatever fields could
  still be read, rather than silently leaving the requested value
  unapplied.

The script always echoes `SEGMENT_MAX_SILENT_SECONDS=<n>` (the value now
in effect), so Claude can tell the user the threshold that's active
without a separate read of `.segment-state`.

This is a one-shot setter, not a mode toggle — nothing about it is
persisted differently from a hand-edit of `.segment-state`; it exists
purely so Claude doesn't have to touch that file directly.
`start-devlog.sh` itself takes no arguments and never resets an existing
threshold; `max_silent_seconds` now has the dedicated command
`checkpoint-mode.md`'s `max_silent_rounds` still doesn't.

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
  1. If PreToolUse `session_id` is non-empty and differs from the stored
     id, exit 0. If PreToolUse has a non-empty `agent_id` (Claude Code
     subagent / dynamic workflow), exit 0.
  2. Resolve the current `devlog.md` content identity: if on-disk
     mtime+size match `last_seen_mtime` / `last_seen_size` and
     `last_seen_cksum` is present, reuse that cksum (skip re-hash).
     Otherwise compute `cksum`. If it differs from `last_seen_cksum`,
     persist the new cksum, identity fields, and `last_change_epoch =
     now`, then exit 0.
  3. If the incoming tool is `Write`, `Edit`, `StrReplace`, `Read`, or
     `Grep`, and `tool_input.file_path` (or `tool_input.path` for Grep)
     is exactly `.devlog/devlog.md` or ends with `/.devlog/devlog.md`,
     exit 0. No `realpath`; string suffix only.
  4. If `now - last_change_epoch >= max_silent_seconds`, print a
     stderr message telling Claude to Read `.devlog/devlog.md` then
     Edit/StrReplace-append a `### 段落` (not full-file Write overwrite),
     then exit 2.
  5. Otherwise exit 0.

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
every few minutes and does little work will not trip the 10-minute
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

- **PreToolUse may skip `cksum`** when `devlog.md` mtime+size match
  `last_seen_mtime` / `last_seen_size`. Content changes that preserve
  both (rare) would not reset the timer until identity drifts.
- **No background alarm.** If Claude thinks for 10 minutes without
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
- **Subagent session isolation.** The valve skips a PreToolUse call when
  its non-empty `session_id` differs from the id stored at
  UserPromptSubmit. Missing or unreadable ids preserve the existing
  parent-round valve.
- **Claude Code dynamic workflow / subagents.** They usually share the
  parent `session_id`, so session_id isolation alone does not skip them.
  When PreToolUse includes a non-empty `agent_id`, Segment Watch exits 0
  (subagents must not append parent-round `### 段落` under this valve).
  Main-thread calls omit `agent_id` and still hit the valve.
- **Unblock without wiping.** Expired main-thread may Read/Grep
  `.devlog/devlog.md`, then Edit/StrReplace to append. Full-file Write
  overwrite remains technically allowlisted for legacy paths but SKILL
  and stderr forbid it — prefer append.

## Files

| File | Role |
|---|---|
| `hooks/scripts/round-start.sh` | Reset `last_change_epoch` / `last_seen_cksum` each round |
| `hooks/scripts/segment-watch.sh` | New PreToolUse checker |
| `hooks/scripts/test-segment-watch.sh` | Self-check (no `.enabled`; fresh round; expired + Bash blocks; expired + Write `devlog.md` passes; hash change then Bash passes; expired + Write other file blocks; malformed state fail-open) |
| `hooks/hooks.json` | Register PreToolUse → `segment-watch.sh` |
| `commands/start.md` | Create `.segment-state` if missing (default `600`) |
| `hooks/scripts/segment-watch-set.sh` | `/devlog-tracker:segment-watch` filesystem side: patch or create `.segment-state`'s `max_silent_seconds` |
| `commands/segment-watch.md` | Get a time length from the user, convert to seconds, call `segment-watch-set.sh` |
| `hooks/scripts/test-segment-watch-set.sh` | Self-check for `segment-watch-set.sh` (not started; fresh create; override preserves other fields; malformed-key rebuild; bad/zero/missing arg) |
| `skills/devlog-tracker/SKILL.md` | Document the 10-minute valve under Round Segments |
| `docs/design/checkpoint-mode.md` | Point Round Segments' "mechanism: none" at this valve |
| `README.md` | Mention the mid-round silence valve |

`enforce-devlog.sh` is unchanged. Stop still only requires a hash
change (and existing heading / checkpoint checks) at end of turn.
