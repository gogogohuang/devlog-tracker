# Recording Moments

Record each interactive round at three moments, on **the same Round
block**: user submit, normal turn end, and unexpected interrupt. Usage
exhaustion is not an interrupt.

This spec is written against `feat/jinze/improve_response_content` as of
2026-09-09: Rounds already use `### Summary` / `### Handoff` (not
`### Response`); Stop already checks those headings after a content-hash
change; Segment Watch already blocks a 15-minute silent PreToolUse; Span
and Checkpoint are unchanged in purpose.

## Motivation

Stop only runs when Claude tries to finish a turn. Combined with
`round-start.sh` only snapshotting a hash, a round that is killed,
Esc'd, or hit by an API error can vanish entirely — including the user
request. Segment Watch covers *long silence during tools*; it does not
cover "the user already spoke" or "the turn never reached Stop".

The three moments:

1. **User prompt submitted** — persist User Input immediately.
2. **Turn completed normally** — Claude fills Summary / Handoff / Status
   on that same Round; Stop still blocks if the close is missing.
3. **Unexpected interrupt** — mark that same Round `INTERRUPTED`. Do
   **not** do this for usage exhaustion (`rate_limit`, `billing_error`,
   `account_on_hold`).

## Design constraints (from this branch)

- **Same Round, patched.** One user message is one `## Round N`. Submit
  creates it; complete or interrupt edits it. Do not append a second
  Round for the same message. Historical rounds stay untouched (compact
  still only moves). Span *closeout* is still a **new** Round, as
  `docs/design/span-mode.md`.
- **Authoring exception.** `docs/design/segment-watch.md` says hooks
  must not author `devlog.md`. That stays true for Segment Watch (it
  only checks). This feature is the exception: `UserPromptSubmit`
  writes the skeleton, and interrupt paths patch Status. Claude still
  writes Summary, Handoff, `### 段落`, and Checkpoint.
- **Completeness is Summary + Handoff**, already enforced in
  `enforce-devlog.sh`. Skeleton Rounds omit those headings on purpose
  so Stop still blocks a normal finish. Do not revert to a
  `### Response` check.
- **Keep the hash snapshot, take it after the skeleton write.** If
  `.turn-start` were captured *before* the skeleton, Stop would see a
  hash change from the hook itself and skip the "you must write"
  message. Capture *after* append so Claude still has to change the
  file (add Summary/Handoff or a segment). Span budget expiry still
  uses this hash path.
- **`.round-open` is the open-round lock.** Hash + headings cannot tell
  "skeleton IN_PROGRESS" from "closed IN_PROGRESS, work continues".
  The marker file can. Interrupt and dangling-heal only run when it
  exists.
- **Fail-open** on every new script, same as existing hooks. Missing
  `.enabled` → no-op, no new `.devlog` files.
- **No transcript parse.** SessionEnd's plugin budget is ~1.5s.

## Round format

Submit (hook) appends:

```markdown
## Round <N> — <ISO 8601 timestamp with offset, best-effort `date`>

### User Input
<submitted prompt; see encoding rules>

### Status
IN_PROGRESS
```

Normal complete (Claude, Write/Edit on the **last** Round, do not
duplicate User Input):

```markdown
## Round <N> — <same heading>

### User Input
<unchanged>

### 段落 …          ← optional, as today

### Summary
…

### Handoff
#### …
…

### Status
DONE | IN_PROGRESS | BLOCKED
```

Unexpected interrupt (hook) on that same block:

- Set Status to `INTERRUPTED`.
- One-line reason under Status (source + detail, e.g. `StopFailure:server_error`,
  `user_interrupt`, `SessionEnd:other`, `dangling:session_start`).
- If `### Summary` / `### Handoff` are missing, add stubs so a later
  Stop heading check on this block (should it become last again) does
  not freeze an unrelated turn:
  - Summary: `這輪意外中斷。`
  - Handoff: `#### 現況` plus one sentence that it did not close normally.
- Do not invent 決策 / 檔案 / 下一步.

`Status` enum becomes four values: `DONE | IN_PROGRESS | BLOCKED | INTERRUPTED`.

### User Input encoding

- Source: `UserPromptSubmit` stdin field `prompt` (`jq` if present,
  else the same loose string match as other hooks).
- Truncate at 4000 characters; if truncated, append a one-line notice.
- Wrap the body in a fenced `text` block so prompt lines matching
  `^## ` / `^### ` do not break last-Round extraction (this branch
  already ignores fenced headings in `enforce-devlog.sh`).
- If the prompt itself contains a triple-backtick fence, replace that
  fence with a single-line marker before wrapping so the wrapper stays
  closed.

## Marker files

### `.devlog/.round-open`

JSON, hook-owned:

```json
{ "round": 15, "opened_at": "2026-09-09T12:00:00+08:00" }
```

Created when a skeleton Round is appended. Deleted when Stop accepts a
normal close (headings present) or when an interrupt path finishes
patching. Malformed / unreadable → treat as absent (fail-open: do not
interrupt-stamp, do not block Stop solely on this file).

### `.devlog/.interrupted`

Presence file, written by `PostToolUseFailure` when `is_interrupt` is
true (best-effort — Esc does not reliably fire this event). Stop sees
it: if the last Round is still incomplete, patches `INTERRUPTED`,
deletes this file and `.round-open`, **exits 0**. If Summary+Handoff
are already present and the hash moved, clears the marker and takes the
normal success path instead. This recovered-complete rule is implemented
inside `close-open-round.sh`, so SessionEnd, next prompt, and SessionStart
share it. Fail-open if stdin cannot be parsed.

### `.devlog/.turn-start`

Unchanged role: `cksum` of `devlog.md` at the start of the *Claude*
portion of the turn. Written **after** the skeleton append (or
unchanged when a span tick writes no skeleton).

## Hook behavior

All paths require `.enabled`.

### `round-start.sh` (`UserPromptSubmit`)

Current Span tick increment, Checkpoint increment, and Segment Watch
reset stay. Add, in this order:

1. If `.round-open` exists: run the shared interrupt close with reason
   `dangling:next_prompt` (even if a span is also open — do not leave a
   stale lock across automated ticks).
2. If `.span-open` is well-formed: **do not** append a Round, **do not**
   write `.round-open`. Then existing tick / checkpoint / segment-reset
   (segment reset uses the current file hash, which may now include the
   dangling stamp). Automated ticks must not become empty User Input
   Rounds.
3. Else append the next `## Round N` skeleton from `prompt`. `N` is last
   fence-aware `## Round ` number + 1, or 1 if none.
4. Write `.round-open` (same timestamp as the Round heading).
5. Write `.turn-start` from the **new** file hash.
6. Existing Checkpoint increment (this UserPromptSubmit still counts
   once, including the dangling-close+new-Round case).
7. Segment Watch reset **after** the skeleton write, so
   `last_seen_cksum` includes it. The 15-minute valve then measures
   silence *after* submit, which is what we want. On the span path,
   reset still runs, using whatever hash exists after step 1.

Unreadable / missing `prompt`: still open a Round with a placeholder
User Input (`（無 prompt）`) rather than skip recording — empty stdin
is fail-open for *blocking* the user, not for skipping the write if
`.enabled` is on. If the append itself fails, skip `.round-open` and
leave `.turn-start` as today's pre-write snapshot (Stop then behaves
as on current mainline).

### `enforce-devlog.sh` (`Stop`)

New order:

1. Read stdin (as today).
2. If `.interrupted` exists: if the last Round already has `### Summary`
   and `### Handoff` **and** the current hash differs from `.turn-start`,
   clear `.interrupted` and fall through (do not stamp — Claude
   recovered). Otherwise shared interrupt close `user_interrupt`, exit
   0. Do this **before** the loop guard so an incomplete Esc path is
   not converted into "please write Summary". Fail-open: if completeness
   cannot be determined, keep the stamp behavior.
3. Loop guard `stop_hook_active` → exit 0 (unchanged: one block, then
   release). A released skeleton stays open; the next prompt or
   SessionStart heals it.
4. `.enabled` missing → exit 0.
5. Span under `max_silent_ticks` → exit 0 (no heading requirement).
6. Hash vs `.turn-start` unchanged → exit 2, message still names
   `User Input / Summary / Handoff / Status`.
7. Last-Round heading check unchanged (`### Summary` and `### Handoff`,
   fence-aware awk already in tree). Missing either → exit 2, and
   **do not** delete `.round-open`, **do not** reset span ticks.
8. Success: delete `.round-open` if present; then span tick reset;
   then Checkpoint as today.

A span budget-expiry one-liner still passes headings if it appends to a
Round that already has them. That Round is not `.round-open` (the
opening turn already closed). Hash still has to change.

### `segment-watch.sh` (`PreToolUse`)

No logic change. Skeleton write is a hash change at round start, so
the timer starts at submit. Hooks writing `devlog.md` do not go through
PreToolUse.

### StopFailure

No matcher. Script reads `error` from stdin. If it is `rate_limit`,
`billing_error`, or `account_on_hold`, exit 0 without touching the
Round. Any other error (including `unknown` and future types) →
shared interrupt close `StopFailure:<error>`. Observability-only
event: ignore exit codes from Claude Code's point of view.

### SessionEnd

If `.round-open` exists, shared interrupt close `SessionEnd:<reason>`.
`reason` values are whatever Claude Code sends (`clear`, `resume`,
`logout`, `prompt_input_exit`, `other`, …). `/clear` with a still-open
Round is a lost turn, so it is stamped. A Round already closed at Stop
has no marker → no-op. Keep the script small (plugin SessionEnd
budget).

### SessionStart (`session-start-devlog.sh`)

Before injecting the SessionStart excerpt (last Checkpoint if any, plus
the last two Rounds' Summary / Handoff / Status — see
`session-start-devlog.sh`): if `.round-open` exists **and**
stdin `source` is `startup` / `resume` / `clear` / `fork`, shared
interrupt close `dangling:session_start`. Skip heal when `source` is
`compact` or missing/unreadable (mid-turn auto-compact must not cancel
Stop). Then, for every source **except `clear`**, the existing span
warning + excerpt. `source=clear` exits 0 after heal with empty
stdout — `/clear` must leave context empty; resume is
`/devlog-tracker:continue` (see `docs/design/continue.md`). Crash
recovery for Status still happens on disk; User Input was already on
disk at submit.

### PostToolUseFailure

If `.enabled` and `is_interrupt` is true, create `.interrupted`. Do
not patch `devlog.md` here (Stop / SessionEnd / next prompt will).

### `/devlog-tracker:pause`

Also delete `.round-open` and `.interrupted` (same rationale as
deleting `.span-open`). Do not rewrite the skeleton Round; it stays
`IN_PROGRESS` without being labelled a crash.

## Shared helper

`hooks/scripts/close-open-round.sh`, invoked by other hook scripts
(not a second copy of the awk):

- No-op unless `.enabled` and `.round-open` exist and `devlog.md` is
  writable.
- Locate the last fence-aware `## Round ` block (copy the awk already
  in `enforce-devlog.sh`; do not fork a second algorithm).
- If that block's number does not match `.round-open`'s `round`,
  fail-open (delete the marker, do not edit the wrong Round).
- If the last Round already has `### Summary` and `### Handoff` **and**
  `devlog.md`'s `cksum` differs from `.turn-start`, delete the markers
  and do not edit Status (recovered-complete). Missing or equal
  `.turn-start` still stamps.
- Patch Status → `INTERRUPTED` + reason; add Summary/Handoff stubs if
  missing.
- Delete `.round-open` and `.interrupted`.
- Always exit 0.

## Interactions

| Mechanism | Interaction |
|---|---|
| **Summary / Handoff** | Stop still requires both headings on the last Round after a hash change. Skeletons omit them. Interrupt stubs satisfy presence-only. |
| **Segment Watch** | Timer starts after skeleton. Mid-round `### 段落` still Claude-authored. Valve still does not write `devlog.md`. |
| **Span Mode** | Open span: no new Round on UserPromptSubmit. Quiet ticks and hash-based expiry unchanged. Human-vs-auto still indistinguishable. Closeout still a new Round written by Claude (that tick had no skeleton). |
| **Checkpoint** | Still +1 per non-passthrough UserPromptSubmit. Dangling-close + new Round is one increment. SessionStart heal does not increment. `INTERRUPTED` is not a Checkpoint. |
| **Compact** | Retain `INTERRUPTED` the same as `IN_PROGRESS` / `BLOCKED` (unfinished). |
| **Trivial rounds** | Skeleton still appears at submit. Claude still owes one-line Summary + Handoff `現況` + Status `DONE`. |

## SKILL.md authoring changes

- Submit is hook-owned: Claude must **edit the last Round**, not append
  a duplicate `## Round` for the same user message.
- Do not rewrite User Input unless the hook placeholder was
  `（無 prompt）`.
- Status documents `INTERRUPTED` as hook-only; Claude does not choose
  it on a normal close.
- Replace the "only normal Stop is guaranteed" boundary with: User
  Input is guaranteed at submit; mid-round `### 段落` still only exist
  if Claude (or Segment Watch) wrote them; Status `INTERRUPTED` is
  patched on interrupt or on the next SessionStart / next prompt.

## Testing (TDD, existing assert-and-exit style)

Extend `test-enforce-devlog.sh` and add focused scripts rather than a
framework.

`round-start.sh`:

- Disabled (no `.enabled`) → no `devlog.md`, no `.round-open`.
- Empty project → Round 1 skeleton + `.round-open` + `.turn-start`
  hash matches file after write.
- Existing Round 1 → Round 2.
- Open span under budget → no new Round, ticks increment.
- Dangling `.round-open` → previous Round becomes `INTERRUPTED`, then
  a new Round is appended; checkpoint +1 once.
- Prompt truncation and fence wrapping; inner ` ``` ` neutralized.
- Segment `last_seen_cksum` equals post-skeleton hash.

`enforce-devlog.sh`:

- Skeleton only (hash equal to post-write `.turn-start`) → exit 2.
- Summary+Handoff added → exit 0, `.round-open` removed.
- `.interrupted` → `INTERRUPTED`, exit 0, even without headings
  beforehand (stubs added).
- Span under budget still exit 0 without headings.
- Span over budget still requires hash change; headings already on
  last Round → pass.
- Loop guard still exit 0 on retry; `.round-open` remains.
- Existing heading / checkpoint / fence-in-User-Input cases still pass.

`close-open-round.sh` + StopFailure / SessionEnd / SessionStart:

- `rate_limit` / `billing_error` / `account_on_hold` → no Status
  change.
- `server_error` → `INTERRUPTED` + reason.
- SessionEnd with marker → stamp; without marker → no-op.
- SessionStart with marker → stamp; `startup` / `resume` / `fork` (and
  `compact`, which does not heal) still print the log excerpt; `clear`
  stamps on disk then prints nothing.
- Wrong `round` in marker vs last heading → delete marker, do not
  edit.

`compact-devlog.sh` + `commands/compact.md` move older DONE rounds to
`devlog.archive.md`. Retain `INTERRUPTED` rounds in the main file per
compact rules. Do not invent a second compact mechanism.

## Known limitations

- **Hard kill:** User Input is on disk; `INTERRUPTED` waits for
  SessionStart (`startup` / `resume` / `clear` / `fork`) or the next prompt.
  Unwritten `### 段落` are still lost. Segment Watch does not help if
  no further tool call happens.
- **Esc / mid-turn cancel is not a reliable immediate stamp.** Unexpected
  cancel is usually marked `INTERRUPTED` on the **next prompt** or **next
  SessionStart (`startup` / `resume` / `clear` / `fork`)**. `PostToolUseFailure`
  `is_interrupt` is a best-effort extra if it fires — do not assume Esc
  immediately stamps via that event. When it does not fire, the first Stop
  may still demand Summary/Handoff; the loop guard then releases; heal on
  the next prompt / SessionStart.
- **SessionStart `compact` does not heal.** Mid-turn auto-compact also
  fires SessionStart; healing there would change the hash and silently
  cancel Stop's completeness check. Compact still injects the SessionStart excerpt (last Checkpoint + last
  two Rounds' close) only — it does not heal.
- **Usage skip is exact three `error` strings.** Other billing-adjacent
  types that are not those names get recorded.
- **Concurrent sessions** use a short `.devlog/.lock` around writes.
  Sessions can still interleave after the 2-second fail-open timeout;
  the lock covers the common overlapping-write window.
- **Secrets in the prompt** — common provider-prefix tokens are masked
  (`sk-ant-*`, OpenAI-style `sk-…`, `ghp_` / `github_pat_`, Slack `xox*`,
  `AKIA*`, `Bearer …`, JWT-shaped `eyJ…`, PEM private keys). Truncation at
  4000 characters still happens **before** redact, so a token split by
  truncate may remain. This is not a general secret scanner; other secrets
  still copy into the project file.
- **Span + unrelated human message** still not detected.
- **Pause mid-round** leaves an `IN_PROGRESS` skeleton without
  Summary; that is intentional, not `INTERRUPTED`.
- **Cursor cloud agents** do not run `sessionStart`, so they do not
  receive the automatic devlog excerpt.

## Out of scope

- Migrating historical `### Response` rounds.
- Quality checks on Summary/Handoff bodies (still presence-only).
- Parsing `transcript_path` on SessionEnd.
- Distinguishing automated vs human UserPromptSubmit.
- Plugin version bump.

## Files

| File | Role |
|---|---|
| `hooks/scripts/round-start.sh` | Skeleton append, dangling heal, hash after write, existing span/checkpoint/segment |
| `hooks/scripts/enforce-devlog.sh` | Interrupt short-circuit, then hash + headings; delete `.round-open` on success |
| `hooks/scripts/close-open-round.sh` | Shared `INTERRUPTED` patch |
| `hooks/scripts/on-stop-failure.sh` | Skip usage errors; else close-open |
| `hooks/scripts/on-session-end.sh` | Close-open with SessionEnd reason |
| `hooks/scripts/on-tool-failure.sh` | Set `.interrupted` when `is_interrupt` |
| `hooks/scripts/session-start-devlog.sh` | Heal then inject context, except `source=clear` (heal only, empty stdout) |
| `hooks/hooks.json` | Register StopFailure, SessionEnd, PostToolUseFailure |
| `hooks/scripts/test-*.sh` | Cases listed above |
| `skills/devlog-tracker/SKILL.md` | Same-Round edit, `INTERRUPTED`, timing |
| `commands/start.md` | Mention submit-time skeleton |
| `commands/pause.md` | Delete `.round-open` / `.interrupted` |
| `commands/compact.md` | Retain `INTERRUPTED` |
| `README.md` | Three moments + four Status values |
| `docs/design/segment-watch.md` | Note the authoring exception |
| `docs/design/summary-handoff.md` | Status enum includes `INTERRUPTED` (hook-only) |
| `docs/design/recording-moments.md` | This spec |

`segment-watch.sh` itself is unchanged.
