# Session Handoff File (`.devlog/handoff.md`)

SessionStart today injects the last Checkpoint (if any), Kept／Lessons
indexes, and the last two rounds' Summary／Handoff／Status. That excerpt
is the full three-reader Round shape — useful for history, expensive and
noisy when the next session only needs "what is still open right now."
There is no dedicated surface that says "this is the cross-session
handoff payload," as opposed to "this round's permanent record."

This design adds a small, overwriteable file that carries only that
payload. It follows the same layering already used for archive
(`devlog.md` = recent, `devlog.archive.md` = history): a tiny current-
state file for injection, the main file for durable rounds.

## Decisions (grilling session, 2026-09-22)

1. **Route A — independent file**, not a maintained `## Handoff` block
   inside `devlog.md`. SessionStart reads one small file; no parse of
   the whole main file just to find the handoff. Matches the
   recent-vs-archive split already in place.
2. **Authoring path C — Round subsection → Stop copies.** Claude writes
   `### Session Handoff` inside `.round-current.md` (same turn as
   Summary／Reply／Handoff). Stop, after validation passes, extracts that
   subsection and overwrites the independent file. Claude does **not**
   edit `handoff.md` directly.
3. **Overwrite policy C:**
   - `IN_PROGRESS`／`BLOCKED` → overwrite `$HANDOFF_FILE` with the
     extracted content
   - `DONE` → delete `$HANDOFF_FILE` (absence = no open handoff)
   - `INTERRUPTED` → leave `$HANDOFF_FILE` untouched (hook stub must not
     wipe a still-useful prior snapshot)
4. **SessionStart injection A:** if `$HANDOFF_FILE` exists and is
   non-empty, print it first (with a short header), then keep today's
   excerpt (last Checkpoint／Kept／Lessons／last two rounds) and the
   existing `.round-current.md` surface. `source=clear` still injects
   nothing.
5. **Stop enforcement A:** on `IN_PROGRESS`／`BLOCKED`, `### Session
   Handoff` is required with all three subsections present, in fixed
   order; empty body of a subsection must still be the explicit
   `- （無）` line (same convention as Checkpoint). Missing／wrong order
   → exit 2. `DONE` does not require the subsection (clearing is the
   hook's job). `INTERRUPTED` stubs never write it.
6. **Branch scope B:** path resolution mirrors `devlog-path.sh` —
   `main`／`master` → `handoff.md`; other branches →
   `handoff.<sanitized>.md`. **No** first-checkout rename of an
   existing `handoff.md` into the branch file (unlike `devlog.md`):
   handoff is a current-state snapshot, not history; the next
   `IN_PROGRESS`／`BLOCKED` round on that branch overwrites naturally.

## Round format

Sibling of `### Summary`／`### Reply`／`### Handoff`, placed between
`### Handoff` and `### Status`:

```markdown
### Session Handoff

#### 決策
- <choices that affect later direction; or `- （無）`>

#### 待解問題
- <what the next session should look at first; or `- （無）`>

#### 失敗嘗試
- <tried-and-abandoned approaches; or `- （無）`>
```

Same three fields as Checkpoint Mode (`docs/design/checkpoint-mode.md`
and `skills/devlog-tracker/references/checkpoint-mode.md`), so one
mental model covers both "periodic cross-round waypoint" and "current
session handoff." Checkpoint stays inside `devlog.md` as a durable
marker; Session Handoff is the volatile snapshot for the next session.

`### Session Handoff` is **not** a copy of `### Handoff`'s six
subsections (決策／檔案／工作區／現況／完成條件／下一步). Those remain
the per-round L1 contract. Session Handoff is the condensed
"still-open" view: decisions that still matter, open questions, and
failed attempts worth not repeating. **待解問題** is the primary cue
for the next session (same priority as in Checkpoint).

## Independent file shape

Written by Stop (never by Claude's Edit／Write tools):

```markdown
## Session Handoff

### 決策
- …

### 待解問題
- …

### 失敗嘗試
- …
```

No Round number, no Status line, no User Input. The file is either
absent (no open handoff / last close was `DONE`) or exactly this
skeleton with the three bodies from the last successful
`IN_PROGRESS`／`BLOCKED` close.

## Path resolution

Extend `devlog_resolve_paths` (or a thin sibling sourced with it) so
callers also get `HANDOFF_FILE`:

| Checkout | `HANDOFF_FILE` |
|---|---|
| `main`／`master` (any case), non-git, empty branch | `$DEVLOG_DIR/handoff.md` |
| other branch | `$DEVLOG_DIR/handoff.<sanitized>.md` |
| detached／unborn (`HEAD`) | `$DEVLOG_DIR/handoff.<worktree-basename>.md` (same sanitize／fallback as `DEVLOG_FILE`) |

Reserved-name collision with `archive`／`lessons.*` follows the same
fallback-to-shared-file rule as `DEVLOG_FILE` (share `handoff.md`
rather than collide). Sanitize helper is reused (`_devlog_sanitize_name`
／`b-<cksum>` for all-CJK names).

**Migration:** do **not** rename `handoff.md` → `handoff.<branch>.md` on
first resolve. Document as intentional divergence from `devlog.md`
migration.

## Stop hook (`enforce-devlog.sh`)

**Validate with the other hard checks (before merge).** **Write／clear
only after a successful merge** of `.round-current.md` into
`DEVLOG_FILE` (same window as today's post-merge housekeeping). Span
Mode quiet ticks that exit early without a real write never reach these
checks — same as Summary／Handoff today.

1. Read Status of the round being closed.
2. If `IN_PROGRESS`／`BLOCKED`:
   - Require `### Session Handoff` with subsections `#### 決策`,
     `#### 待解問題`, `#### 失敗嘗試` in that order, no duplicates, each
     with at least one non-empty body line (including the literal
     `- （無）`). Missing／wrong order → exit 2 (blocks before merge).
   - After merge succeeds: extract bodies; write `$HANDOFF_FILE`
     atomically (temp + `mv`) using the independent-file skeleton.
3. If `DONE`:
   - Do **not** require `### Session Handoff`. If Claude included one
     anyway, ignore it (no order／body lint).
   - After merge succeeds: `rm -f "$HANDOFF_FILE"`.
4. If `INTERRUPTED`: no-op on `$HANDOFF_FILE` (close-open-round path
   never calls the writer).
5. Fail-open on I/O errors writing／deleting the handoff file after
   merge — a handoff I/O failure must not undo a valid round close
   (stderr only, continue).

Prefer a small sourced helper (`handoff-file.sh`) with: extract from a
Round blob, write, clear. Path comes from `devlog_resolve_paths`
(`HANDOFF_FILE`). Keep extraction fence-aware (same awk style as
session-start／enforce).

## SessionStart (`session-start-devlog.sh`)

For `startup`／`resume`／`compact`／`fork` (not `clear`):

1. Existing span reminder (unchanged).
2. **New:** if `[ -s "$HANDOFF_FILE" ]`, print a one-line header
   (e.g. that this is the current Session Handoff snapshot, not the
   full log) and `cat` the file, then a blank line.
3. Existing `DEVLOG_FILE` excerpt (Checkpoint／Kept／Lessons／last two
   rounds) — unchanged.
4. Existing `.round-current.md` surface — unchanged.

If `HANDOFF_FILE` is missing or empty, skip step 2 silently.

## Peripheral commands

| Command／event | `$HANDOFF_FILE` |
|---|---|
| `clean-devlog.sh --confirmed` | Delete current-branch `$HANDOFF_FILE` along with the main file clear |
| `pause-devlog.sh` | Leave untouched (pause does not erase history) |
| `compact-devlog.sh`／`keep-move.sh` | Leave untouched |
| `close-open-round.sh` → `INTERRUPTED` | Leave untouched |
| `start-devlog.sh` | Do not create an empty handoff file |

## SKILL / docs updates

- `skills/devlog-tracker/SKILL.md`: file-location bullet; Round format
  adds `### Session Handoff`; Stop-check paragraph; SessionStart
  injection list; explicit note that `DONE` deletes the file so Claude
  must not treat `handoff.md` as durable history.
- `skills/devlog-tracker/references/contract.md`: hard-check row for
  Session Handoff on `IN_PROGRESS`／`BLOCKED`.
- `skills/devlog-tracker/references/checkpoint-mode.md`: one-line
  cross-link — same three fields, different lifetime (durable marker
  vs volatile snapshot).
- `README.md`／`README.zh-TW.md`: short mention under SessionStart /
  recording flow.
- This file is the normative design.

## Testing

| Test | Covers |
|---|---|
| `test-handoff-file.sh` (new) | Extract／write／clear; branch path mapping; atomic write; missing subsection detection helpers if exported |
| `test-enforce-devlog-*.sh` (extend or new `test-enforce-devlog-session-handoff.sh`) | `IN_PROGRESS` without Session Handoff → blocked; with three subsections → pass and file written; `DONE` → file removed; `BLOCKED` same as in-progress; wrong subsection order → blocked |
| `test-session-start-devlog.sh` (extend) | Non-empty handoff printed before Checkpoint excerpt; missing handoff → excerpt-only; `clear` still silent |
| `test-devlog-path.sh` (extend) | `HANDOFF_FILE` set alongside `DEVLOG_FILE` for main／feature／detached |
| `test-clean-devlog.sh` (extend) | Clean removes `$HANDOFF_FILE` |

## Out of scope

- Multi-agent／multi-session file locking on `handoff.md` (Known
  limitation; revisit if Codex + Claude write the same worktree
  concurrently).
- Claude editing `handoff.md` directly.
- Replacing or dropping the last-two-rounds SessionStart excerpt.
- Renaming `handoff.md` into a branch-scoped file on first checkout.
- Formal "typed, owned, claimed exactly once" handoff protocols
  (ai-memory style).
- Changing Checkpoint's three-field schema.

## Implementation touch list

| Path | Change |
|---|---|
| `core/scripts/devlog-path.sh` | Set `HANDOFF_FILE` in `devlog_resolve_paths` |
| `core/scripts/handoff-file.sh` (new) | Extract／write／clear helpers |
| `core/scripts/enforce-devlog.sh` | Validate + write／clear after pass |
| `core/scripts/session-start-devlog.sh` | Prefixed injection |
| `core/scripts/clean-devlog.sh` | `rm -f "$HANDOFF_FILE"` |
| `core/scripts/tests/*` | As in Testing |
| `skills/devlog-tracker/SKILL.md` + references + READMEs | As in SKILL／docs |

## Related

| Doc | Relation |
|---|---|
| `docs/design/checkpoint-mode.md` | Shared three-field schema |
| `docs/design/summary-handoff.md` | Per-round `### Handoff` (six subsections) stays separate |
| `docs/design/branch-scoped-devlog.md` | Path sanitize／reserved names; handoff skips rename migration |
| `docs/design/session-start-excerpt-plan.md` | Current excerpt behavior preserved under this file |
| `docs/design/continue.md` | Continue still reads main file + workspace check; handoff file is an injection aid, not a replace for continue |
