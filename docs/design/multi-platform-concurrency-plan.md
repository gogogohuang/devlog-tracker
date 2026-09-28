# Multi-platform concurrency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude Code, Codex, and Cursor can run devlog-tracker in the same worktree at the same time without closing, overwriting, or renumbering each other's rounds.

**Architecture:** `devlog_resolve_paths` becomes the single owner of every per-round state path and picks names by platform (`DEVLOG_PLATFORM`; Claude keeps today's names, others add `@<p>`). Round numbers are reserved at open time under the existing `.devlog/.lock`, looking at every platform's `.round-open*`. Places that read "the last round" read "my platform's last round" through new `devlog-md.sh` helpers.

**Tech Stack:** bash + awk (core scripts, tests are plain assert scripts), node (keep-all.js, sync script).

**Spec:** `docs/design/multi-platform-concurrency.md`

## Global Constraints

- Platforms: exactly `claude`, `codex`, `cursor`. Unset/other `DEVLOG_PLATFORM` = `claude`.
- Claude file names are unchanged (`.round-current.md`, `.round-open`, `handoff.md`, `handoff.<b>.md`, …). Other platforms: `<claude name without .md>@<p>[.md]`, e.g. `.round-current@codex.md`, `.round-open@codex`, `handoff.feat-x@cursor.md`.
- Non-Claude round headings: `## Round <n> — <timestamp> · <p>` (` · ` is space, U+00B7, space). Claude headings unchanged. A heading with no valid ` · [a-z]+` suffix belongs to `claude`.
- Every hook script stays fail-open (exit 0 on its own errors); only existing `exit 2` paths block.
- Do not bump versions (AGENTS.md). `.devlog/` and `docs/superpowers/` are never committed.
- Before every commit run the three CI steps from AGENTS.md:
  ```bash
  shellcheck --external-sources --source-path=SCRIPTDIR -S warning \
   core/scripts/*.sh core/scripts/tests/*.sh cursor/hooks/*.sh codex/hooks/*.sh
  bash core/scripts/run-tests.sh
  npm test
  ```
- After editing `commands/` or `skills/devlog-tracker/`, run `node scripts/sync-codex-plugin.js` (npm test checks it).

## File Structure

| File | Responsibility after this plan |
|---|---|
| `core/scripts/devlog-path.sh` | platform identity, every per-platform path, legacy claim, open-round listing, other-platform handoff listing |
| `core/scripts/devlog-md.sh` | per-platform round lookup, reopen by number, platform-aware workspace claim |
| `core/scripts/round-start.sh` | number reservation, heading suffix, own-platform fold / mismatch / lessons |
| `core/scripts/enforce-devlog.sh`, `close-open-round.sh`, `segment-watch.sh`, `session-start-devlog.sh`, `await-open.sh`, `span-open.sh`, `span-close.sh`, `segment-watch-set.sh`, `on-tool-failure.sh`, `status-devlog.sh` | consume path variables instead of literals |
| `core/scripts/pause-devlog.sh`, `clean-devlog.sh`, `keep-move.sh`, `keep-all.sh`, `keep-all.js`, `migrate-handoff.sh` | act on every platform |
| `codex/hooks/*.sh`, `cursor/hooks/*.sh` | export `DEVLOG_PLATFORM` |
| `core/scripts/tests/test-multi-platform.sh` (new) | end-to-end interleave scenario |
| `skills/devlog-tracker/**`, `commands/{span,clean}.md`, `skills/devlog-tracker/references/reply-fold.md`, `README*.md`, `docs/design/*.md` | docs |

---

### Task 1: Platform identity and per-platform paths in `devlog-path.sh`

**Files:**
- Modify: `core/scripts/devlog-path.sh`
- Test: `core/scripts/tests/test-devlog-path.sh`

**Interfaces:**
- Produces (all later tasks rely on these exact names):
  - `DEVLOG_PLATFORMS="claude codex cursor"` (constant)
  - `devlog_platform` → prints validated platform
  - `devlog_platform_file <stem> <ext> <platform>` → prints a basename (`.round-open` `''` `codex` → `.round-open@codex`; `handoff.feat` `.md` `claude` → `handoff.feat.md`)
  - After `devlog_resolve_paths`: `DEVLOG_PLATFORM`, `ROUND_CURRENT`, `ROUND_OPEN`, `TURN_MARKER`, `SEGMENT_FILE`, `AWAITING_FILE`, `INTERRUPTED_FLAG`, `SPAN_FILE`, `MISMATCH_FILE`, `HANDOFF_STEM` (absolute path without `.md`, e.g. `$DEVLOG_DIR/handoff.feat-x`), `HANDOFF_FILE` (caller's)
  - `devlog_open_rounds` → one line per existing `.round-open*` marker: `<platform>\t<round>\t<file field>`
  - `devlog_other_handoffs` → one line per other platform's non-empty handoff for `HANDOFF_STEM`: `<platform>\t<absolute path>`

- [ ] **Step 1: Write failing tests** — append before the final summary block of `core/scripts/tests/test-devlog-path.sh`:

```bash
# --- platform identity ---------------------------------------------------
assert_path() {
  if [ "$2" = "$3" ]; then echo "PASS: $1"; else echo "FAIL: $1 (expected [$2], got [$3])"; FAIL=1; fi
}
assert_path "unset platform is claude" claude "$(unset DEVLOG_PLATFORM; devlog_platform)"
assert_path "codex platform" codex "$(DEVLOG_PLATFORM=codex devlog_platform)"
assert_path "unknown platform falls back to claude" claude "$(DEVLOG_PLATFORM='x;rm' devlog_platform)"
assert_path "claude keeps plain name" .round-current.md "$(devlog_platform_file .round-current .md claude)"
assert_path "codex gets @ suffix" .round-current@codex.md "$(devlog_platform_file .round-current .md codex)"
assert_path "extensionless @ suffix" .round-open@cursor "$(devlog_platform_file .round-open '' cursor)"

# --- per-platform state paths --------------------------------------------
PLATREPO="$TMP/platrepo"
mkdir -p "$PLATREPO"
git_setup "$PLATREPO"
git -C "$PLATREPO" branch -M main
DEVLOG_PLATFORM=codex devlog_resolve_paths "$PLATREPO"
assert_path "codex ROUND_CURRENT" "$PLATREPO/.devlog/.round-current@codex.md" "$ROUND_CURRENT"
assert_path "codex ROUND_OPEN" "$PLATREPO/.devlog/.round-open@codex" "$ROUND_OPEN"
assert_path "codex TURN_MARKER" "$PLATREPO/.devlog/.turn-start@codex" "$TURN_MARKER"
assert_path "codex SEGMENT_FILE" "$PLATREPO/.devlog/.segment-state@codex" "$SEGMENT_FILE"
assert_path "codex AWAITING_FILE" "$PLATREPO/.devlog/.awaiting-reply@codex" "$AWAITING_FILE"
assert_path "codex INTERRUPTED_FLAG" "$PLATREPO/.devlog/.interrupted@codex" "$INTERRUPTED_FLAG"
assert_path "codex SPAN_FILE" "$PLATREPO/.devlog/.span-open@codex" "$SPAN_FILE"
assert_path "codex MISMATCH_FILE" "$PLATREPO/.devlog/.workspace-mismatch@codex" "$MISMATCH_FILE"
assert_path "codex main HANDOFF_FILE" "$PLATREPO/.devlog/handoff@codex.md" "$HANDOFF_FILE"
assert_path "codex DEVLOG_FILE shared" "$PLATREPO/.devlog/devlog.md" "$DEVLOG_FILE"
unset DEVLOG_PLATFORM
devlog_resolve_paths "$PLATREPO"
assert_path "claude ROUND_CURRENT unchanged" "$PLATREPO/.devlog/.round-current.md" "$ROUND_CURRENT"
assert_path "claude ROUND_OPEN unchanged" "$PLATREPO/.devlog/.round-open" "$ROUND_OPEN"
assert_path "claude HANDOFF_FILE unchanged" "$PLATREPO/.devlog/handoff.md" "$HANDOFF_FILE"
git -C "$PLATREPO" checkout -q -b codex
DEVLOG_PLATFORM=cursor devlog_resolve_paths "$PLATREPO"
assert_path "branch named codex + cursor platform" "$PLATREPO/.devlog/handoff.codex@cursor.md" "$HANDOFF_FILE"
assert_path "HANDOFF_STEM" "$PLATREPO/.devlog/handoff.codex" "$HANDOFF_STEM"
unset DEVLOG_PLATFORM

# --- legacy claim ----------------------------------------------------------
CLAIMREPO="$TMP/claimrepo"
mkdir -p "$CLAIMREPO/.devlog"
git_setup "$CLAIMREPO"
git -C "$CLAIMREPO" branch -M main
touch "$CLAIMREPO/.devlog/.enabled"
echo "open round" > "$CLAIMREPO/.devlog/.round-current.md"
printf '{"round": 3, "opened_at": "t", "file": "devlog.md"}\n' > "$CLAIMREPO/.devlog/.round-open"
echo "legacy handoff" > "$CLAIMREPO/.devlog/handoff.md"
echo "segment cfg" > "$CLAIMREPO/.devlog/.segment-state"
DEVLOG_PLATFORM=codex devlog_resolve_paths "$CLAIMREPO"
if [ -f "$CLAIMREPO/.devlog/.round-current@codex.md" ] && [ ! -f "$CLAIMREPO/.devlog/.round-current.md" ] \
  && [ -f "$CLAIMREPO/.devlog/.round-open@codex" ] \
  && grep -q "legacy handoff" "$CLAIMREPO/.devlog/handoff@codex.md" \
  && [ -f "$CLAIMREPO/.devlog/.segment-state" ] \
  && [ -f "$CLAIMREPO/.devlog/.platform-claimed" ]; then
  echo "PASS: first non-claude platform claims legacy state (segment config stays)"
else
  echo "FAIL: legacy claim"; ls -a "$CLAIMREPO/.devlog"; FAIL=1
fi
echo "later claude round" > "$CLAIMREPO/.devlog/.round-current.md"
DEVLOG_PLATFORM=cursor devlog_resolve_paths "$CLAIMREPO"
if [ -f "$CLAIMREPO/.devlog/.round-current.md" ] && [ ! -f "$CLAIMREPO/.devlog/.round-current@cursor.md" ]; then
  echo "PASS: marker stops later claims"
else
  echo "FAIL: second claim happened"; FAIL=1
fi
unset DEVLOG_PLATFORM

CLAUDEFIRST="$TMP/claudefirst"
mkdir -p "$CLAUDEFIRST/.devlog"
git_setup "$CLAUDEFIRST"
git -C "$CLAUDEFIRST" branch -M main
touch "$CLAUDEFIRST/.devlog/.enabled"
echo "open round" > "$CLAUDEFIRST/.devlog/.round-current.md"
devlog_resolve_paths "$CLAUDEFIRST"
if [ -f "$CLAUDEFIRST/.devlog/.round-current.md" ] && [ -f "$CLAUDEFIRST/.devlog/.platform-claimed" ]; then
  echo "PASS: claude-first claims nothing, writes marker"
else
  echo "FAIL: claude-first claim"; FAIL=1
fi

NOTENABLED="$TMP/notenabled"
mkdir -p "$NOTENABLED/.devlog"
echo "x" > "$NOTENABLED/.devlog/.round-current.md"
DEVLOG_PLATFORM=codex devlog_resolve_paths "$NOTENABLED"
if [ -f "$NOTENABLED/.devlog/.round-current.md" ] && [ ! -e "$NOTENABLED/.devlog/.platform-claimed" ]; then
  echo "PASS: no claim without .enabled"
else
  echo "FAIL: claimed while disabled"; FAIL=1
fi
unset DEVLOG_PLATFORM

# --- open rounds / other handoffs -----------------------------------------
LISTREPO="$TMP/listrepo"
mkdir -p "$LISTREPO/.devlog"
git_setup "$LISTREPO"
git -C "$LISTREPO" branch -M main
touch "$LISTREPO/.devlog/.enabled" "$LISTREPO/.devlog/.platform-claimed"
printf '{"round": 5, "opened_at": "t", "file": "devlog.md"}\n' > "$LISTREPO/.devlog/.round-open"
printf '{"round": 6, "opened_at": "t", "file": "devlog.md"}\n' > "$LISTREPO/.devlog/.round-open@codex"
echo "claude h" > "$LISTREPO/.devlog/handoff.md"
echo "cursor h" > "$LISTREPO/.devlog/handoff@cursor.md"
: > "$LISTREPO/.devlog/handoff@codex.md"
DEVLOG_PLATFORM=codex devlog_resolve_paths "$LISTREPO"
assert_path "open rounds listing" "$(printf 'claude\t5\tdevlog.md\ncodex\t6\tdevlog.md')" "$(devlog_open_rounds)"
assert_path "other handoffs (non-empty, not own)" \
  "$(printf 'claude\t%s\ncursor\t%s' "$LISTREPO/.devlog/handoff.md" "$LISTREPO/.devlog/handoff@cursor.md")" \
  "$(devlog_other_handoffs)"
unset DEVLOG_PLATFORM

# --- branch tail migration moves every platform's handoff -----------------
PTAIL="$TMP/ptail"
mig_repo "$PTAIL"
write_main_devlog "$PTAIL/.devlog/devlog.md" 1:DONE 2:IN_PROGRESS
touch "$PTAIL/.devlog/.platform-claimed"
echo "claude handoff" > "$PTAIL/.devlog/handoff.md"
echo "codex handoff" > "$PTAIL/.devlog/handoff@codex.md"
git -C "$PTAIL" checkout -q -b feature-p
devlog_resolve_paths "$PTAIL"
if grep -q "claude handoff" "$PTAIL/.devlog/handoff.feature-p.md" \
  && grep -q "codex handoff" "$PTAIL/.devlog/handoff.feature-p@codex.md" \
  && [ ! -f "$PTAIL/.devlog/handoff@codex.md" ]; then
  echo "PASS: tail migration moves every platform's handoff"
else
  echo "FAIL: platform handoff tail migration"; ls -a "$PTAIL/.devlog"; FAIL=1
fi
```

`mig_repo` / `write_main_devlog` already exist earlier in this file (used by the tail tests); if `mig_repo` does not create `.enabled`, add `touch "$PTAIL/.devlog/.enabled"` after it.

- [ ] **Step 2: Run to verify failure**

Run: `bash core/scripts/tests/test-devlog-path.sh`
Expected: FAIL lines for `devlog_platform: command not found` and every new path assertion.

- [ ] **Step 3: Implement** in `core/scripts/devlog-path.sh`.

Add after the `devlog-md.sh` source line:

```bash
# shellcheck source=json-field.sh
. "$_DEVLOG_PATH_DIR/json-field.sh"

# Every platform that can own per-round state. Claude keeps the pre-0.x
# un-suffixed names; the others add "@<platform>" (docs/design/
# multi-platform-concurrency.md). "@" never survives _devlog_sanitize_name,
# so a branch named "codex" cannot collide with platform Codex.
DEVLOG_PLATFORMS="claude codex cursor"

devlog_platform() {
  case "${DEVLOG_PLATFORM:-}" in
    codex|cursor) printf '%s\n' "$DEVLOG_PLATFORM" ;;
    *) printf 'claude\n' ;;
  esac
}

# $1 stem (".round-current", "handoff.feat-x"), $2 extension (".md" or ""),
# $3 platform. Prints a basename.
devlog_platform_file() {
  if [ "$3" = claude ]; then printf '%s%s\n' "$1" "$2"
  else printf '%s@%s%s\n' "$1" "$3" "$2"; fi
}

_devlog_set_state_paths() {
  local p="$1" d="$DEVLOG_DIR"
  ROUND_CURRENT="$d/$(devlog_platform_file .round-current .md "$p")"
  ROUND_OPEN="$d/$(devlog_platform_file .round-open '' "$p")"
  TURN_MARKER="$d/$(devlog_platform_file .turn-start '' "$p")"
  SEGMENT_FILE="$d/$(devlog_platform_file .segment-state '' "$p")"
  AWAITING_FILE="$d/$(devlog_platform_file .awaiting-reply '' "$p")"
  INTERRUPTED_FLAG="$d/$(devlog_platform_file .interrupted '' "$p")"
  SPAN_FILE="$d/$(devlog_platform_file .span-open '' "$p")"
  MISMATCH_FILE="$d/$(devlog_platform_file .workspace-mismatch '' "$p")"
}

# First resolve after upgrade: before this change every platform wrote the
# un-suffixed names. The platform that resolves first most likely wrote
# them, so a non-Claude first resolver renames them to its own names.
# .segment-state is configuration (start-devlog.sh creates it), not round
# state, so it stays. Runs once; .platform-claimed stops it.
_devlog_claim_legacy_state() {
  local p="$1" d="$DEVLOG_DIR" name f stem
  [ -f "$d/.enabled" ] && [ ! -e "$d/.platform-claimed" ] || return 0
  devlog_lock_acquire
  if [ ! -e "$d/.platform-claimed" ]; then
    if [ "$p" != claude ]; then
      for name in .round-open .turn-start .awaiting-reply .interrupted .span-open .workspace-mismatch; do
        [ -e "$d/$name" ] && [ ! -e "$d/$name@$p" ] && mv "$d/$name" "$d/$name@$p" 2>/dev/null
      done
      [ -e "$d/.round-current.md" ] && [ ! -e "$d/.round-current@$p.md" ] \
        && mv "$d/.round-current.md" "$d/.round-current@$p.md" 2>/dev/null
      for f in "$d"/handoff.md "$d"/handoff.*.md; do
        [ -f "$f" ] || continue
        case "${f##*/}" in *@*) continue ;; esac
        stem="${f%.md}"
        [ -e "$stem@$p.md" ] || mv "$f" "$stem@$p.md" 2>/dev/null
      done
    fi
    : > "$d/.platform-claimed" 2>/dev/null || true
  fi
  devlog_lock_release
}

# One line per existing .round-open marker: platform, round, file field.
devlog_open_rounds() {
  local q f
  for q in $DEVLOG_PLATFORMS; do
    f="$DEVLOG_DIR/$(devlog_platform_file .round-open '' "$q")"
    [ -f "$f" ] || continue
    printf '%s\t%s\t%s\n' "$q" "$(json_int_get "$f" round)" "$(json_str_get "$f" file)"
  done
}

# One line per other platform's non-empty handoff for this branch.
devlog_other_handoffs() {
  local q f
  for q in $DEVLOG_PLATFORMS; do
    [ "$q" = "$DEVLOG_PLATFORM" ] && continue
    f="$HANDOFF_STEM.md"
    [ "$q" = claude ] || f="$HANDOFF_STEM@$q.md"
    [ -s "$f" ] && printf '%s\t%s\n' "$q" "$f"
  done
  return 0
}
```

In `_devlog_migrate_unfinished_tail`, change the handoff arguments from files to stems and move every platform's file. Replace the signature comment's `$4 (handoff.md) moves to $5` with `every platform's handoff under stem $4 moves to stem $5`, and replace:

```bash
    if [ -f "$src_handoff" ] && [ ! -f "$dst_handoff" ]; then
      mv "$src_handoff" "$dst_handoff" 2>/dev/null || true
    fi
```

with:

```bash
    local q suffix
    for q in $DEVLOG_PLATFORMS; do
      suffix="$(devlog_platform_file '' .md "$q")"
      if [ -f "$src_handoff$suffix" ] && [ ! -f "$dst_handoff$suffix" ]; then
        mv "$src_handoff$suffix" "$dst_handoff$suffix" 2>/dev/null || true
      fi
    done
```

(`devlog_platform_file '' .md codex` prints `@codex.md`, `… claude` prints `.md`; `$src_handoff` / `$dst_handoff` are now stems such as `$DEVLOG_DIR/handoff` and `$DEVLOG_DIR/handoff.feature-y`.)

In `devlog_resolve_paths`:

```bash
devlog_resolve_paths() {
  local dir="${1:-.}"
  DEVLOG_DIR="$dir/.devlog"
  DEVLOG_FILE="$DEVLOG_DIR/devlog.md"
  DEVLOG_PLATFORM="$(devlog_platform)"
  HANDOFF_STEM="$DEVLOG_DIR/handoff"
  DEVLOG_ORIGIN=""
  _devlog_set_state_paths "$DEVLOG_PLATFORM"
  _devlog_claim_legacy_state "$DEVLOG_PLATFORM"
  HANDOFF_FILE="$DEVLOG_DIR/$(devlog_platform_file handoff .md "$DEVLOG_PLATFORM")"
  … (branch detection unchanged; every early `return 0` keeps the main values above)
  local resolved="$DEVLOG_DIR/devlog.$name.md"
  local resolved_stem="$DEVLOG_DIR/handoff.$name"
  if [ -f "$DEVLOG_DIR/.enabled" ] && [ ! -f "$resolved" ] && [ -s "$DEVLOG_FILE" ]; then
    devlog_lock_acquire
    [ -f "$resolved" ] || _devlog_migrate_unfinished_tail \
      "$dir" "$DEVLOG_FILE" "$resolved" "$HANDOFF_STEM" "$resolved_stem" "$origin"
    devlog_lock_release
  fi
  DEVLOG_FILE="$resolved"
  HANDOFF_STEM="$resolved_stem"
  HANDOFF_FILE="$DEVLOG_DIR/$(devlog_platform_file "handoff.$name" .md "$DEVLOG_PLATFORM")"
  DEVLOG_ORIGIN="$origin"
}
```

Add `# shellcheck disable=SC2034 # consumed by callers` above each new assignment group (the file already does this for `HANDOFF_FILE`). `DEVLOG_PLATFORM` is intentionally assigned the validated value so child scripts inherit it only when exported by an adapter; do not `export` it here.

- [ ] **Step 4: Run tests**

Run: `bash core/scripts/tests/test-devlog-path.sh && bash core/scripts/run-tests.sh`
Expected: all PASS. The full run matters: every Claude test now gets a `.platform-claimed` file in `.devlog/`. If a test asserts an exact directory listing, add `.platform-claimed` to its expectation (and nothing else).

- [ ] **Step 5: shellcheck + commit**

```bash
git add core/scripts/devlog-path.sh core/scripts/tests/test-devlog-path.sh
git commit -m "feat: resolve per-platform devlog state paths"
```

---

### Task 2: Per-platform round lookup in `devlog-md.sh`

**Files:**
- Modify: `core/scripts/devlog-md.sh`
- Test: `core/scripts/tests/test-devlog-md.sh`

**Interfaces:**
- Produces:
  - `devlog_list_round_starts_of <file> <platform>` → `NR N` lines, only that platform's rounds (same format as `devlog_list_round_starts`)
  - `devlog_round_start_by_number <file> <n>` → line number of `## Round <n>` (last match), empty if none
  - `devlog_reopen_round <devlog> <current> <n>` → moves round `<n>` from anywhere in `<devlog>` into `<current>`; return 1 and touch nothing if absent. Replaces `devlog_reopen_last_round` (deleted).
  - `workspace_claim_state <dir> <file> [platform]` → as today, but evaluates the platform's last round (default `claude`).

- [ ] **Step 1: Write failing tests** — replace the `devlog_reopen_last_round` section (around line 518) of `core/scripts/tests/test-devlog-md.sh` with:

```bash
# --- per-platform round lookup --------------------------------------------
MP="$TMP_ROOT/mp.md"
cat > "$MP" <<'EOF'
# 專案摘要

## Round 1 — 2026-09-27T10:00:00+0800

### Status
DONE

## Round 3 — 2026-09-27T10:05:00+0800 · codex

### Status
IN_PROGRESS

## Round 2 — 2026-09-27T10:01:00+0800

```text
## Round 9 — fenced · codex
```

### Status
DONE

## Round 4 — 2026-09-27T10:09:00+0800 · cursor

### Status
DONE
EOF
assert_eq "claude rounds" "3 1
13 2" "$(devlog_list_round_starts_of "$MP" claude)"
assert_eq "codex rounds (fenced ignored)" "8 3" "$(devlog_list_round_starts_of "$MP" codex)"
assert_eq "cursor rounds" "22 4" "$(devlog_list_round_starts_of "$MP" cursor)"
assert_eq "by number: middle round" "8" "$(devlog_round_start_by_number "$MP" 3)"
assert_eq "by number: missing" "" "$(devlog_round_start_by_number "$MP" 8)"

# --- devlog_reopen_round ----------------------------------------------------
REOPEN_MAIN="$TMP_ROOT/reopen.md"
REOPEN_CUR="$TMP_ROOT/reopen-cur.md"
cp "$MP" "$REOPEN_MAIN"
devlog_reopen_round "$REOPEN_MAIN" "$REOPEN_CUR" 3
assert_eq "reopen middle: returns 0" "0" "$?"
assert_contains "reopen middle: current has round 3" "## Round 3 — 2026-09-27T10:05:00+0800 · codex" "$(cat "$REOPEN_CUR")"
assert_not_contains "reopen middle: devlog lost round 3" "## Round 3 " "$(cat "$REOPEN_MAIN")"
assert_eq "reopen middle: others stay in order" "1 2 4 " "$(devlog_list_round_starts "$REOPEN_MAIN" | awk '{printf "%s ", $2}')"
devlog_reopen_round "$REOPEN_MAIN" "$TMP_ROOT/should-not-exist.md" 3
assert_eq "reopen missing: returns 1" "1" "$?"
assert_file_absent "reopen missing: no current file" "$TMP_ROOT/should-not-exist.md"
```

Keep the file's existing `devlog_reopen_last_round` assertions only if they cover cases above not already covered (empty devlog → return 1); rewrite them to call `devlog_reopen_round "$EMPTY_MAIN" … 1`.

Add a workspace-claim test next to the existing `workspace_claim_state` tests (search the file for `workspace_claim_state`; reuse its git-repo fixture variables). The fixture has a last round with `<workspace>` matching live git; append a codex round whose `<workspace>` is `bogus` and assert:

```bash
assert_eq "claude claim ignores codex's later round" "MATCH" "$(workspace_claim_state "$WS_REPO" "$WS_FILE" claude)"
assert_eq "codex claim sees its own round" "MISMATCH" "$(workspace_claim_state "$WS_REPO" "$WS_FILE" codex)"
```

(Use the fixture's actual variable names; the appended round must have `### Status` `IN_PROGRESS` and a `### Handoff` `<handoff><workspace>bogus</workspace></handoff>` block.)

- [ ] **Step 2: Run to verify failure**

Run: `bash core/scripts/tests/test-devlog-md.sh`
Expected: FAIL (`devlog_list_round_starts_of: command not found`, …).

- [ ] **Step 3: Implement** in `core/scripts/devlog-md.sh`.

After `devlog_list_round_starts`:

```bash
# Same output as devlog_list_round_starts, only rounds owned by platform $2:
# a heading ending in " · <platform>" (lowercase word) belongs to it; any
# other heading (every pre-upgrade round) belongs to claude.
devlog_list_round_starts_of() {
  awk -v p="$2" '
    /^[ \t]*```/ { fence = !fence; next }
    !fence && /^## Round [0-9]+/ {
      owner = $0
      if (!(sub(/.* · /, "", owner) && owner ~ /^[a-z]+$/)) owner = "claude"
      if (owner != p) next
      round = $0
      sub(/^## Round /, "", round)
      sub(/[^0-9].*$/, "", round)
      print NR, round
    }
  ' "$1"
}

devlog_round_start_by_number() {
  devlog_list_round_starts "$1" | awk -v n="$2" '$2 == n { s = $1 } END { if (s) print s }'
}
```

Replace `devlog_reopen_last_round` with:

```bash
devlog_reopen_round() {
  # Moves the "## Round $3" block (wherever it sits in $1) into $2, removing
  # it from $1. Returns 1 and touches neither file if $1 has no such round.
  local devlog="$1" current="$2" start end
  start="$(devlog_round_start_by_number "$devlog" "$3")"
  [ -n "$start" ] || return 1
  end="$(devlog_block_end "$devlog" "$start")"
  awk -v start="$start" -v end="$end" 'NR >= start && NR <= end' "$devlog" > "$current" 2>/dev/null || return 1
  awk -v start="$start" -v end="$end" 'NR < start || NR > end' "$devlog" > "$devlog.tmp" 2>/dev/null \
    && mv "$devlog.tmp" "$devlog" 2>/dev/null || { rm -f "$devlog.tmp" "$current" 2>/dev/null; return 1; }
  return 0
}
```

In `workspace_claim_state`, change the signature line and the `start=` line:

```bash
workspace_claim_state() {
  local dir="$1" file="$2" platform="${3:-claude}" start end status claimed live
  …
  start="$(devlog_list_round_starts_of "$file" "$platform" | awk 'END { print $1 }')"
```

Update `round-start.sh:217` in the same commit so nothing calls the deleted function (the fold path is rewritten in Task 4; for now):

```bash
  devlog_reopen_round "$DEVLOG_FILE" "$ROUND_CURRENT" "$FOLD_ROUND" || : > "$ROUND_CURRENT"
```

- [ ] **Step 4: Run tests**

Run: `bash core/scripts/tests/test-devlog-md.sh && bash core/scripts/run-tests.sh`
Expected: all PASS (Claude-only fixtures have no suffixes, so behavior is identical).

- [ ] **Step 5: shellcheck + commit**

```bash
git add core/scripts/devlog-md.sh core/scripts/round-start.sh core/scripts/tests/test-devlog-md.sh
git commit -m "feat: look up rounds per platform and reopen by number"
```

---

### Task 3: Hook scripts read state paths from `devlog_resolve_paths` (refactor, no behavior change for Claude)

**Files:**
- Modify: `core/scripts/round-start.sh`, `enforce-devlog.sh`, `close-open-round.sh`, `segment-watch.sh`, `session-start-devlog.sh`, `await-open.sh`, `span-open.sh`, `span-close.sh`, `segment-watch-set.sh`, `on-tool-failure.sh`, `status-devlog.sh`
- Test: `core/scripts/tests/test-multi-platform.sh` (new; grows in Tasks 4–6), `core/scripts/tests/test-segment-watch-set.sh`

**Interfaces:**
- Consumes: Task 1 variables.

- [ ] **Step 1: Write the failing test** — create `core/scripts/tests/test-multi-platform.sh`:

```bash
#!/usr/bin/env bash
# Two platforms in one worktree (docs/design/multi-platform-concurrency.md).
# Run: bash core/scripts/tests/test-multi-platform.sh
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

new_project() {
  P="$TMP_ROOT/$1"
  mkdir -p "$P/.devlog"
  git -C "$P" init -q
  git -C "$P" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m init
  git -C "$P" branch -M main
  echo '.devlog/' > "$P/.gitignore"
  git -C "$P" add .gitignore
  git -C "$P" -c user.email=t@t.t -c user.name=t commit -q -m ignore
  touch "$P/.devlog/.enabled" "$P/.devlog/.platform-claimed"
  D="$P/.devlog"
}
submit() { # platform prompt
  printf '{"prompt":"%s","session_id":"%s-1"}' "$2" "$1" \
    | DEVLOG_PLATFORM="$1" DEVLOG_PROJECT_DIR="$P" bash "$SCRIPT_DIR/round-start.sh"
}

# --- Task 3: codex writes only @codex files ---------------------------------
new_project refactor
submit codex "hello from codex" >/dev/null
check "codex round file" '[ -f "$D/.round-current@codex.md" ] && grep -q "hello from codex" "$D/.round-current@codex.md"'
check "codex marker" '[ -f "$D/.round-open@codex" ] && [ -f "$D/.turn-start@codex" ]'
check "claude files untouched" '[ ! -e "$D/.round-current.md" ] && [ ! -e "$D/.round-open" ] && [ ! -e "$D/.turn-start" ]'

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
```

- [ ] **Step 2: Run to verify failure**

Run: `bash core/scripts/tests/test-multi-platform.sh`
Expected: FAIL "codex round file" (round-start still writes `.round-current.md`).

- [ ] **Step 3: Replace local path definitions** with the resolved variables. Exact edits:

| File | Remove / replace |
|---|---|
| `round-start.sh:32-37` | delete the `ROUND_CURRENT=`, `SPAN_FILE=`, `SEGMENT_FILE=`, `ROUND_OPEN=`, `AWAITING_FILE=` lines (keep `CHECKPOINT_FILE`, `ADVISORY_FILE`); delete `MISMATCH_FILE=` at line 168; lines 309/311 `"$DEVLOG_DIR/.turn-start"` → `"$TURN_MARKER"` |
| `close-open-round.sh:38-41` | delete `ROUND_OPEN=`, `INTERRUPTED_FLAG=`, `ROUND_CURRENT=`, `TURN_MARKER=` |
| `enforce-devlog.sh` | line 54-55: `rm -f "$PROJECT_DIR"/.devlog/.interrupted "$PROJECT_DIR"/.devlog/.interrupted@* 2>/dev/null \|\| true` (drop the `if`); delete line 62 `ROUND_CURRENT=`; lines 63/65 `"$DEVLOG_DIR/.interrupted"` → `"$INTERRUPTED_FLAG"`; delete line 92 `TURN_MARKER=` and line 107 `SPAN_FILE=`; line 564 → `rm -f "$MISMATCH_FILE"`; lines 584/597 `"$DEVLOG_DIR/.round-open"` → `"$ROUND_OPEN"`; line 141 message: `.devlog/.round-current.md` → `.devlog/${ROUND_CURRENT##*/}`; line 556 message: `.devlog/handoff.md` → `.devlog/${HANDOFF_FILE##*/}` |
| `segment-watch.sh` | delete lines 19-20 and 85 definitions; allowlist line 69 → `".devlog/${ROUND_CURRENT##*/}"\|*"/.devlog/${ROUND_CURRENT##*/}") return 0 ;;`; messages at lines 106 and 193: `.devlog/.round-current.md` → `.devlog/${ROUND_CURRENT##*/}` (every occurrence) |
| `session-start-devlog.sh:38-39` | delete both; line 46 `"$DEVLOG_DIR/.round-open"` → `"$ROUND_OPEN"`; line 67 `.devlog/.span-open` → `.devlog/${SPAN_FILE##*/}`; line 158 `.devlog/.round-current.md` → `.devlog/${ROUND_CURRENT##*/}` |
| `await-open.sh` | `"$DEVLOG_DIR/.awaiting-reply"` → `"$AWAITING_FILE"`, `"$DEVLOG_DIR/.round-open"` → `"$ROUND_OPEN"` (all occurrences) |
| `span-open.sh` | `"$DEVLOG_DIR/.span-open"` → `"$SPAN_FILE"`, `"$DEVLOG_DIR/.round-open"` → `"$ROUND_OPEN"` |
| `status-devlog.sh` | `"$DEVLOG_DIR/.span-open"` → `"$SPAN_FILE"`, `"$DEVLOG_DIR/.segment-state"` → `"$SEGMENT_FILE"` |

`span-close.sh` and `on-tool-failure.sh` don't resolve paths today. Make them:

```bash
# span-close.sh (whole file)
#!/usr/bin/env bash
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"
devlog_resolve_paths "${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
if [ ! -e "$SPAN_FILE" ]; then
  echo "NOT_OPEN"
  exit 0
fi
rm -f "$SPAN_FILE" || exit 1
echo "CLOSED"
```

In `on-tool-failure.sh`, source `devlog-path.sh` the same way after the `.enabled` gate, call `devlog_resolve_paths "$PROJECT_DIR"`, and write `: > "$INTERRUPTED_FLAG"`.

`segment-watch-set.sh` applies project-wide (the threshold is a setting, not round state). Replace its `if [ -f "$DEVLOG_DIR/.segment-state" ]; then … fi` block (lines 27-44) with:

```bash
APPLIED_ANY=0
for SEG in "$DEVLOG_DIR"/.segment-state "$DEVLOG_DIR"/.segment-state@*; do
  [ -f "$SEG" ] || continue
  APPLIED_ANY=1
  json_int_set "$SEG" max_silent_seconds "$SECONDS_ARG"
  APPLIED="$(json_int_get "$SEG" max_silent_seconds)"
  if [ "$APPLIED" != "$SECONDS_ARG" ]; then
    # Existing file didn't have a matching max_silent_seconds key to patch
    # (malformed / hand-edited) -- rebuild it fresh rather than leave the
    # requested value silently unapplied.
    LAST_EPOCH="$(json_int_get "$SEG" last_change_epoch)"
    LAST_SUM="$(json_str_get "$SEG" last_seen_cksum)"
    SESSION="$(json_str_get "$SEG" session_id)"
    case "$LAST_EPOCH" in ''|*[!0-9]*) LAST_EPOCH=0 ;; esac
    printf '%s\n' "{\"last_change_epoch\": ${LAST_EPOCH}, \"last_seen_cksum\": \"${LAST_SUM}\", \"max_silent_seconds\": ${SECONDS_ARG}, \"session_id\": \"${SESSION}\"}" \
      > "$SEG" || exit 1
  fi
done
if [ "$APPLIED_ANY" -eq 0 ]; then
  printf '%s\n' "{\"last_change_epoch\": 0, \"last_seen_cksum\": \"\", \"max_silent_seconds\": ${SECONDS_ARG}, \"session_id\": \"\"}" \
    > "$DEVLOG_DIR/.segment-state" || exit 1
fi
```

The final `echo` keeps reading `"$DEVLOG_DIR/.segment-state"`. Add to `core/scripts/tests/test-segment-watch-set.sh`: create `.segment-state@codex` with `max_silent_seconds` 600, run the script with `300`, assert both files now hold 300.

- [ ] **Step 4: Run tests**

Run: `bash core/scripts/tests/test-multi-platform.sh && bash core/scripts/run-tests.sh`
Expected: all PASS. Codex/Cursor adapter tests may now FAIL because adapters don't export a platform yet — they still resolve to Claude names, so they should still pass; if one fails, stop and investigate (it means a literal path was missed).

- [ ] **Step 5: grep guard, shellcheck, commit**

Run: `rg -n '\$DEVLOG_DIR/\.(round-current\.md|round-open|turn-start|awaiting-reply|interrupted|span-open|workspace-mismatch)' core/scripts --glob '!tests/**'`
Expected: matches only in `clean-devlog.sh`, `keep-move.sh`, `keep-all.sh`, `pause-devlog.sh`, `migrate-handoff.sh` (Task 6).

```bash
git add core/scripts
git commit -m "refactor: read per-round state paths from devlog_resolve_paths"
```

---

### Task 4: Round numbering, heading source, own-platform lookups in `round-start.sh`

**Files:**
- Modify: `core/scripts/round-start.sh`
- Test: `core/scripts/tests/test-multi-platform.sh`, `core/scripts/tests/test-round-start.sh`

**Interfaces:**
- Consumes: `devlog_open_rounds`, `devlog_list_round_starts_of`, `devlog_round_start_by_number`, `devlog_reopen_round`, `workspace_claim_state … "$DEVLOG_PLATFORM"`.

- [ ] **Step 1: Write failing tests** — insert before the summary block of `test-multi-platform.sh`:

```bash
# --- Task 4: the other platform's open round survives, numbers are unique -
new_project interleave
submit claude "claude task" >/dev/null
OUT="$(submit codex "codex task")"
check "claude round still open" '[ -f "$D/.round-open" ] && grep -q "claude task" "$D/.round-current.md"'
check "claude round not INTERRUPTED" '! grep -q INTERRUPTED "$D/.round-current.md" && [ ! -s "$D/devlog.md" ]'
check "claude heading has no suffix" 'head -1 "$D/.round-current.md" | grep -q "^## Round 1 — " && ! head -1 "$D/.round-current.md" | grep -q " · "'
check "codex reserved round 2 with suffix" 'grep -q "^## Round 2 — .* · codex$" "$D/.round-current@codex.md"'
check "codex told its file" 'case "$OUT" in *".devlog/.round-current@codex.md"*) true ;; *) false ;; esac'
OUT_C="$(submit cursor "cursor task")"
check "cursor reserved round 3" 'grep -q "^## Round 3 — .* · cursor$" "$D/.round-current@cursor.md"'

# Codex's own next prompt closes only codex's round.
submit codex "codex second" >/dev/null
check "codex dangling round merged as INTERRUPTED" 'grep -q "^## Round 2 — .* · codex$" "$D/devlog.md" && grep -q INTERRUPTED "$D/devlog.md"'
check "claude still open after codex re-submit" 'grep -q "claude task" "$D/.round-current.md"'
check "codex second is round 4" 'grep -q "^## Round 4 — .* · codex$" "$D/.round-current@codex.md"'
check "non-claude segment state seeded" '[ ! -f "$D/.segment-state" ] || [ -f "$D/.segment-state@codex" ]'

# Reply Fold finds codex's round by number even when it is not last.
new_project fold
cat > "$D/devlog.md" <<'EOF'
## Round 1 — 2026-09-27T10:00:00+0800 · codex

### Summary
asked a question

### Reply
q?

### Handoff
<handoff>
<state>
waiting
</state>
</handoff>

### Status
DONE

## Round 2 — 2026-09-27T10:02:00+0800

### Summary
claude work

### Reply
ok

### Handoff
<handoff>
<state>
done
</state>
</handoff>

### Status
DONE
EOF
printf '{"round": 1, "opened_at": "t"}\n' > "$D/.awaiting-reply@codex"
submit codex "the answer" >/dev/null
check "fold reopened codex round 1" 'grep -q "^## Round 1 — .* · codex$" "$D/.round-current@codex.md" && grep -q "the answer" "$D/.round-current@codex.md"'
check "claude round 2 stays in devlog" 'grep -q "^## Round 2 " "$D/devlog.md" && ! grep -q "^## Round 1 " "$D/devlog.md"'
```

Also create a `.segment-state` in `new_project interleave` right after `new_project` so the seed assertion is meaningful:

```bash
printf '%s\n' '{"last_change_epoch": 0, "last_seen_cksum": "", "max_silent_seconds": 600, "session_id": ""}' > "$D/.segment-state"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash core/scripts/tests/test-multi-platform.sh`
Expected: FAIL on "codex reserved round 2" (it gets 1), "codex told its file", fold checks.

- [ ] **Step 3: Implement** in `core/scripts/round-start.sh`.

Reply Fold detection (replace the `CURRENT_LAST=…` block):

```bash
  if [ -n "$AWAIT_ROUND" ] && [ -f "$DEVLOG_FILE" ] \
    && [ -n "$(devlog_round_start_by_number "$DEVLOG_FILE" "$AWAIT_ROUND")" ]; then
    FOLD_ROUND="$AWAIT_ROUND"
  fi
```

Task-notification target:

```bash
  TASK_NOTIF_LAST="$(devlog_list_round_starts_of "$DEVLOG_FILE" "$DEVLOG_PLATFORM" | awk 'END { print $2 }')"
```

Workspace mismatch block:

```bash
  CLAIM_ST="$(workspace_claim_state "$PROJECT_DIR" "$DEVLOG_FILE" "$DEVLOG_PLATFORM" 2>/dev/null || echo NO_CLAIM)"
  if [ "$CLAIM_ST" = "MISMATCH" ]; then
    LAST_START="$(devlog_list_round_starts_of "$DEVLOG_FILE" "$DEVLOG_PLATFORM" | awk 'END { print $1 }')"
```

and append to the first notice `printf` string (before `\n`): `（若同一工作樹還有其他平台在跑，差異可能來自它。）`.

Lessons BLOCKED block: `BLOCKED_ROUND_STARTS="$(devlog_list_round_starts_of "$DEVLOG_FILE" "$DEVLOG_PLATFORM")"`.

Numbering (after the `LAST_N` awk, before `NEXT_N=`):

```bash
  # Another platform's still-open round already owns its number
  # (docs/design/multi-platform-concurrency.md "Round numbering").
  RESERVED_N="$(devlog_open_rounds | awk -F '\t' -v f="${DEVLOG_FILE##*/}" '
    ($3 == f || $3 == "") && $2 ~ /^[0-9]+$/ && $2 + 0 > m { m = $2 + 0 }
    END { print m + 0 }')"
  [ "$RESERVED_N" -gt "$LAST_N" ] && LAST_N="$RESERVED_N"
```

Heading:

```bash
  HEADING_SOURCE=""
  [ "$DEVLOG_PLATFORM" = claude ] || HEADING_SOURCE=" · $DEVLOG_PLATFORM"
  {
    printf '## Round %s — %s%s\n\n' "$NEXT_N" "$TS" "$HEADING_SOURCE"
```

File notice, right after the `.round-open` write in the new-round branch **and** after the fold branch's `.round-open` write:

```bash
  [ "$DEVLOG_PLATFORM" = claude ] || printf '這一輪寫在 .devlog/%s。\n' "${ROUND_CURRENT##*/}"
```

Segment seed, right before `if [ -f "$SEGMENT_FILE" ]; then` near the end:

```bash
CLAUDE_SEGMENT="$DEVLOG_DIR/.segment-state"
if [ "$SEGMENT_FILE" != "$CLAUDE_SEGMENT" ] && [ ! -f "$SEGMENT_FILE" ] && [ -f "$CLAUDE_SEGMENT" ]; then
  SEED_MAX="$(json_int_get "$CLAUDE_SEGMENT" max_silent_seconds)"
  printf '{"last_change_epoch": 0, "last_seen_cksum": "", "max_silent_seconds": %s, "session_id": ""}\n' \
    "${SEED_MAX:-600}" > "$SEGMENT_FILE" 2>/dev/null || true
fi
```

- [ ] **Step 4: Run tests**

Run: `bash core/scripts/tests/test-multi-platform.sh && bash core/scripts/run-tests.sh`
Expected: all PASS. `test-round-start.sh`'s mismatch tests assert the old notice text with `assert_contains` on a prefix; if one compares the full line, extend its expectation with the new hint sentence.

- [ ] **Step 5: shellcheck + commit**

```bash
git add core/scripts/round-start.sh core/scripts/tests/test-multi-platform.sh core/scripts/tests/test-round-start.sh
git commit -m "feat: reserve round numbers across platforms and tag non-Claude rounds"
```

---

### Task 5: Stop / interrupt / SessionStart / await-open per platform

**Files:**
- Modify: `core/scripts/session-start-devlog.sh`, `core/scripts/await-open.sh`, `core/scripts/span-open.sh`
- Test: `core/scripts/tests/test-multi-platform.sh`, `core/scripts/tests/test-session-start-devlog.sh`, `core/scripts/tests/test-await-open.sh`

**Interfaces:**
- Consumes: `devlog_other_handoffs`, `devlog_list_round_starts_of`.

- [ ] **Step 1: Write failing tests.**

Append to `test-multi-platform.sh` (before summary):

```bash
# --- Task 5: both Stop in either order, handoffs coexist -------------------
close_round() { # platform status file
  local f="$3"
  cat >> "$f" <<EOF

### Summary
closed by $1

### Reply
ok

### Handoff
<handoff>
<workspace>
$(workspace_snapshot "$P")
</workspace>
<state>
$1 state
</state>
<done-when>
tests pass
</done-when>
<next>
run \`bash core/scripts/run-tests.sh\`
</next>
</handoff>

### Session Handoff
<session-handoff>
<decisions>
- $1 decision
</decisions>
<open-questions>
- （無）
</open-questions>
<failed-attempts>
- （無）
</failed-attempts>
</session-handoff>
EOF
  # Replace the skeleton's Status with the requested one.
  awk -v st="$2" '/^### Status$/ { print; getline; print st; next } { print }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  printf '{}' | DEVLOG_PLATFORM="$1" DEVLOG_PROJECT_DIR="$P" bash "$SCRIPT_DIR/enforce-devlog.sh"
}
new_project stops
submit claude "claude task" >/dev/null
submit codex "codex task" >/dev/null
close_round codex IN_PROGRESS "$D/.round-current@codex.md" 2>"$TMP_ROOT/err1"
check "codex Stop passes" '[ $? -eq 0 ] || { cat "$TMP_ROOT/err1"; false; }'
check "codex merged, claude still open" 'grep -q "closed by codex" "$D/devlog.md" && [ -f "$D/.round-open" ] && [ ! -e "$D/.round-open@codex" ]'
check "codex handoff written" 'grep -q "codex decision" "$D/handoff@codex.md"'
close_round claude IN_PROGRESS "$D/.round-current.md" 2>"$TMP_ROOT/err2"
check "claude Stop passes" '[ $? -eq 0 ] || { cat "$TMP_ROOT/err2"; false; }'
check "file order is close order, numbers unique" '[ "$(grep -o "^## Round [0-9]*" "$D/devlog.md" | tr "\n" ",")" = "## Round 2,## Round 1," ]'
check "handoffs coexist" 'grep -q "claude decision" "$D/handoff.md" && grep -q "codex decision" "$D/handoff@codex.md"'
check "neither INTERRUPTED" '! grep -q INTERRUPTED "$D/devlog.md"'

OUT="$(printf '{"source":"startup"}' | DEVLOG_PLATFORM=codex DEVLOG_PROJECT_DIR="$P" bash "$SCRIPT_DIR/session-start-devlog.sh")"
check "codex SessionStart injects own handoff" 'case "$OUT" in *"codex decision"*) true ;; *) false ;; esac'
check "codex SessionStart does not inject claude handoff" 'case "$OUT" in *"claude decision"*) false ;; *) true ;; esac'
check "codex SessionStart notes claude handoff" 'case "$OUT" in *"另一個平台（claude）有未完成的交接：.devlog/handoff.md"*) true ;; *) false ;; esac'

# Interrupt of one platform does not touch the other.
new_project interrupt
submit claude "claude task" >/dev/null
submit codex "codex task" >/dev/null
DEVLOG_PLATFORM=codex DEVLOG_PROJECT_DIR="$P" bash "$SCRIPT_DIR/close-open-round.sh" "Interrupt:cancelled"
check "codex interrupted round merged" 'grep -q "^## Round 2 — .* · codex$" "$D/devlog.md" && grep -q "Interrupt:cancelled" "$D/devlog.md"'
check "claude untouched by codex interrupt" '[ -f "$D/.round-open" ] && grep -q "claude task" "$D/.round-current.md"'
```

Add `. "$SCRIPT_DIR/workspace-snapshot.sh"` (with a `# shellcheck source=../workspace-snapshot.sh` line) at the top of the test file for `workspace_snapshot`. The `$?` inside `check` refers to the `close_round` just before it because `check`'s `eval` runs first thing; keep each `close_round` immediately followed by its `check`. If Stop rejects this fixture for a reason unrelated to platforms (its stderr is in `$TMP_ROOT/err1`), align the fixture with the passing `IN_PROGRESS` fixture in `test-enforce-devlog-session-handoff.sh` rather than loosening Stop.

Append to `test-await-open.sh` (before summary):

```bash
# --- platform: codex falls back to its own last round ----------------------
rm -f "$DEVLOG_DIR/.round-open" "$DEVLOG_DIR/.awaiting-reply" "$DEVLOG_DIR/.awaiting-reply@codex"
printf '## Round 7 — t · codex\n\n### Status\nDONE\n\n## Round 8 — t\n\n### Status\nDONE\n' > "$DEVLOG_DIR/devlog.md"
touch "$DEVLOG_DIR/.platform-claimed"
OUT="$(DEVLOG_PLATFORM=codex bash "$SCRIPT_DIR/await-open.sh")"
assert_contains "codex await-open uses its own last round" "OPENED=7" "$OUT"
[ -f "$DEVLOG_DIR/.awaiting-reply@codex" ] && [ ! -f "$DEVLOG_DIR/.awaiting-reply" ] \
  && echo "PASS: codex awaiting file" || { echo "FAIL: codex awaiting file"; FAIL=1; }
```

- [ ] **Step 2: Run to verify failure**

Run: `bash core/scripts/tests/test-multi-platform.sh; bash core/scripts/tests/test-await-open.sh`
Expected: FAIL on the SessionStart notice and `OPENED=7` (gets 8). Stop/interrupt checks should already pass after Task 3 — if they don't, fix the missed path before continuing.

- [ ] **Step 3: Implement.**

`await-open.sh` and `span-open.sh` fallback line:

```bash
  ROUND="$(devlog_list_round_starts_of "$DEVLOG_FILE" "$DEVLOG_PLATFORM" | awk 'END { print $2 }')"
```

`session-start-devlog.sh`, right after the block that prints `$HANDOFF_FILE`:

```bash
devlog_other_handoffs | while IFS="$(printf '\t')" read -r OTHER_PLATFORM OTHER_FILE; do
  echo "另一個平台（${OTHER_PLATFORM}）有未完成的交接：.devlog/${OTHER_FILE##*/}"
  echo ""
done
```

- [ ] **Step 4: Run tests**

Run: `bash core/scripts/run-tests.sh`
Expected: all PASS.

- [ ] **Step 5: shellcheck + commit**

```bash
git add core/scripts
git commit -m "feat: keep Stop, interrupts, and Session Handoff per platform"
```

---

### Task 6: Commands that act on every platform

**Files:**
- Modify: `core/scripts/pause-devlog.sh`, `clean-devlog.sh`, `keep-move.sh`, `keep-all.sh`, `keep-all.js`, `migrate-handoff.sh`
- Test: `core/scripts/tests/test-multi-platform.sh`, `core/scripts/keep-all.test.js`

**Interfaces:**
- Consumes: `devlog_open_rounds`, `devlog_platform_file`, `HANDOFF_STEM`.
- Produces: `devlog_single_open_round` (in `devlog-path.sh`) → prints `<platform>\t<round>` of the only open round; prints nothing and returns 0 when none; prints `其他平台還有進行中的輪次（<p1>、<p2>），等它們收尾再執行。` to stderr and returns 2 when two or more.

- [ ] **Step 1: Write failing tests** — append to `test-multi-platform.sh`:

```bash
# --- Task 6: whole-devlog commands --------------------------------------
new_project cmds
submit claude "claude task" >/dev/null
submit codex "codex task" >/dev/null
DEVLOG_PROJECT_DIR="$P" bash "$SCRIPT_DIR/clean-devlog.sh" --confirmed >/dev/null 2>"$TMP_ROOT/cleanerr"
check "clean refuses with two open rounds" '[ $? -ne 0 ] && grep -q "其他平台還有進行中的輪次" "$TMP_ROOT/cleanerr" && [ -f "$D/.round-current@codex.md" ]'

DEVLOG_PROJECT_DIR="$P" bash "$SCRIPT_DIR/pause-devlog.sh" >/dev/null
check "pause clears every platform's markers" '[ ! -e "$D/.round-open" ] && [ ! -e "$D/.round-open@codex" ]'

new_project clean1
printf '## Round 1 — t\n\n### Status\nDONE\n\n## Round 2 — t\n\n### Status\nDONE\n' > "$D/devlog.md"
submit codex "only codex" >/dev/null
check "codex got round 3 before clean" 'grep -q "^## Round 3 — .* · codex$" "$D/.round-current@codex.md"'
echo "old claude handoff" > "$D/handoff.md"
echo "old codex handoff" > "$D/handoff@codex.md"
DEVLOG_PROJECT_DIR="$P" bash "$SCRIPT_DIR/clean-devlog.sh" --confirmed >/dev/null 2>&1
check "clean keeps the single open codex round as Round 1" 'grep -q "^## Round 1 — .* · codex$" "$D/.round-current@codex.md"'
check "clean removes every platform handoff" '[ ! -e "$D/handoff.md" ] && [ ! -e "$D/handoff@codex.md" ]'
```

Add to `core/scripts/keep-all.test.js` (next to the existing `.span-open` test at line ~218), mirroring its fixture setup:

```js
test('apply clears a platform .span-open@codex when its round moved out of current', () => {
  // same fixture as the .span-open test above, but write '.span-open@codex'
  // and assert it is removed after apply
});
```

Fill the body by copying the test above it verbatim and replacing both `'.span-open'` literals with `'.span-open@codex'`.

- [ ] **Step 2: Run to verify failure**

Run: `bash core/scripts/tests/test-multi-platform.sh; npm test`
Expected: FAIL on the clean/pause checks and the new keep-all test.

- [ ] **Step 3: Implement.**

In `devlog-path.sh`:

```bash
devlog_single_open_round() {
  local rows count
  rows="$(devlog_open_rounds)"
  [ -n "$rows" ] || return 0
  count="$(printf '%s\n' "$rows" | grep -c .)"
  if [ "$count" -gt 1 ]; then
    echo "其他平台還有進行中的輪次（$(printf '%s\n' "$rows" | cut -f1 | paste -sd '、' -)），等它們收尾再執行。" >&2
    return 2
  fi
  printf '%s\n' "$rows" | cut -f1,2
}
```

`pause-devlog.sh` (globs; unmatched globs stay literal and `rm -f` ignores them):

```bash
rm -f "$DEVLOG_DIR/.enabled" \
  "$DEVLOG_DIR"/.span-open "$DEVLOG_DIR"/.span-open@* \
  "$DEVLOG_DIR"/.round-open "$DEVLOG_DIR"/.round-open@* \
  "$DEVLOG_DIR"/.interrupted "$DEVLOG_DIR"/.interrupted@* \
  "$DEVLOG_DIR"/.awaiting-reply "$DEVLOG_DIR"/.awaiting-reply@*
```

`clean-devlog.sh` — replace the `ROUND_OPEN=` / `ROUND_CURRENT=` lines with:

```bash
OPEN_ROW="$(devlog_single_open_round)" || exit 1
if [ -n "$OPEN_ROW" ]; then
  OPEN_PLATFORM="${OPEN_ROW%%	*}"
  ROUND_OPEN="$DEVLOG_DIR/$(devlog_platform_file .round-open '' "$OPEN_PLATFORM")"
  ROUND_CURRENT="$DEVLOG_DIR/$(devlog_platform_file .round-current .md "$OPEN_PLATFORM")"
fi
```

(the separator inside `%%` is a literal tab). The `sub("^## Round " open, "## Round 1")` rewrite keeps the ` · codex` suffix because it only replaces the prefix. The no-open branch becomes `rm -f "$MAIN" "$DEVLOG_DIR"/.round-current.md "$DEVLOG_DIR"/.round-current@*.md || exit 1`. Line 62-63 become:

```bash
rm -f "$DEVLOG_DIR"/.span-open "$DEVLOG_DIR"/.span-open@* \
  "$DEVLOG_DIR"/.interrupted "$DEVLOG_DIR"/.interrupted@* \
  "$DEVLOG_DIR"/.awaiting-reply "$DEVLOG_DIR"/.awaiting-reply@*
rm -f "$HANDOFF_STEM.md" "$HANDOFF_STEM"@*.md
```

`keep-move.sh` and `keep-all.sh` — replace the `OPEN=` line:

```bash
OPEN_ROW="$(devlog_single_open_round)" || exit 1
OPEN="$(printf '%s' "$OPEN_ROW" | cut -f2)"
OPEN_MARKER="$DEVLOG_DIR/$(devlog_platform_file .round-open '' "${OPEN_ROW%%	*}")"
```

In `keep-move.sh` (`FULL` branch): `rm -f "$DEVLOG_DIR"/.span-open "$DEVLOG_DIR"/.span-open@*` and `[ -z "$OPEN_ROW" ] || json_int_set "$OPEN_MARKER" round 1`; the partial branch loops `for SPAN in "$DEVLOG_DIR"/.span-open "$DEVLOG_DIR"/.span-open@*; do [ -f "$SPAN" ] || continue; …existing check with "$SPAN"…; done`. (`keep-all.sh` only needs `OPEN`; drop `OPEN_MARKER` there if unused, to keep shellcheck quiet.)

`keep-all.js` (~line 411):

```js
  for (const name of fs.readdirSync(c.devlogDir).filter(f => /^\.span-open(@[a-z]+)?$/.test(f))) {
    const span = path.join(c.devlogDir, name);
    const m = fs.readFileSync(span, 'utf8').match(/"round"\s*:\s*(\d+)/);
    if (m && movedFromCurrent.has(Number(m[1]))) fs.rmSync(span, { force: true });
  }
```

`migrate-handoff.sh` line 76: `for f in "$DEVLOG_DIR"/.round-current.md "$DEVLOG_DIR"/.round-current@*.md "$DEVLOG_DIR/devlog.md" "$CUR_DEVLOG"; do`; line 84: add `"$DEVLOG_DIR"/handoff@*.md` to the list (`handoff.*.md` already matches `handoff.<b>@<p>.md`; `first_visit` dedups).

- [ ] **Step 4: Run tests**

Run: `bash core/scripts/run-tests.sh && npm test`
Expected: all PASS.

- [ ] **Step 5: shellcheck + commit**

```bash
git add core/scripts
git commit -m "feat: make pause, clean, keep, and migrate platform-aware"
```

---

### Task 7: Adapters export their platform

**Files:**
- Modify: every `codex/hooks/on-*.sh` and `cursor/hooks/on-*.sh` that has `export DEVLOG_PROJECT_DIR="$ROOT"` (13 files); `codex/hooks/on-pre-tool.sh`
- Test: `codex/hooks/test-adapters.sh`, `cursor/hooks/test-adapters.sh`

- [ ] **Step 1: Update adapter tests first.** In both `test-adapters.sh`, every fixture path that a hook-under-test reads or writes changes to the platform name: `.round-current.md` → `.round-current@codex.md` (cursor: `@cursor`), `.round-open` → `.round-open@codex`, `.turn-start` → `.turn-start@codex`, `.segment-state` → `.segment-state@codex`, `.workspace-mismatch` → `.workspace-mismatch@codex`, `.interrupted` → `.interrupted@codex`, and the apply_patch fixtures' `*** Update File: .devlog/.round-current.md` → `.devlog/.round-current@codex.md`. Add `touch "$SUBMIT/.devlog/.platform-claimed"` next to each `touch …/.enabled` so fixtures aren't claimed. Add one negative case to `codex/hooks/test-adapters.sh` next to the existing apply_patch cases:

```bash
# A patch to Claude's round file is not Codex's own file: still blocked.
PATCH="$(printf '*** Begin Patch\n*** Update File: .devlog/.round-current.md\n@@\n-a\n+b\n*** End Patch')"
```

and assert exit 2, copying the surrounding case's invocation/assert lines.

- [ ] **Step 2: Run to verify failure**

Run: `bash codex/hooks/test-adapters.sh; bash cursor/hooks/test-adapters.sh`
Expected: FAIL (adapters still write Claude names).

- [ ] **Step 3: Implement.** After every `export DEVLOG_PROJECT_DIR="$ROOT"` line add `export DEVLOG_PLATFORM=codex` (codex/hooks) or `export DEVLOG_PLATFORM=cursor` (cursor/hooks). In `codex/hooks/on-pre-tool.sh` add after the export:

```bash
ROUND_FILE=".devlog/.round-current@codex.md"
```

and replace every literal `.devlog/.round-current.md` in that file (payload at line 20, both `cat` cases, the awk `normalize(root "/…")`, the final hint) with `$ROUND_FILE` (inside the awk program, pass it as `-v round_file="$ROUND_FILE"` and use `normalize(root "/" round_file)`).

- [ ] **Step 4: Run tests**

Run: `bash core/scripts/run-tests.sh`
Expected: all PASS.

- [ ] **Step 5: shellcheck + commit**

```bash
git add codex/hooks cursor/hooks
git commit -m "feat: tag Codex and Cursor hooks with their platform"
```

---

### Task 8: Docs and generated Codex files

**Files:**
- Modify: `skills/devlog-tracker/SKILL.md`, `skills/devlog-tracker/references/{contract,round-segments,reply-fold}.md`, `commands/span.md`, `README.md`, `README.zh-TW.md`, `docs/design/recording-moments.md`, `docs/design/session-handoff-file.md`, `docs/design/multi-platform-concurrency.md`
- Regenerate: `codex/skills/**`

- [ ] **Step 1: SKILL + references.** In `skills/devlog-tracker/SKILL.md`「檔案位置」, replace the `.round-current.md` entry with:

```markdown
- `.devlog/.round-current.md`（Claude Code）／`.devlog/.round-current@codex.md`（Codex）／`.devlog/.round-current@cursor.md`（Cursor）：這一輪還沒收尾時寫在這裡，只寫你所在平台那一份；hook 的提示會寫出確切檔名。同一個工作樹可以有多個平台同時在跑，別的平台的檔案不要讀寫。
```

Then in SKILL.md and the three references, every instruction that says to Read/Edit `.round-current.md` becomes `你所在平台的 round 檔（見「檔案位置」）`. Mention once in SKILL.md that non-Claude headings end in ` · codex`／` · cursor`, written by the hook — don't add or remove it.

- [ ] **Step 2: Commands run by the LLM.** In `skills/devlog-tracker/references/reply-fold.md` (await-open) and `commands/span.md` (span-open / span-close), prefix the command with `DEVLOG_PLATFORM="<你所在的平台：claude／codex／cursor>" `.

- [ ] **Step 3: README + design docs.** Add to both READMEs' limitation/FAQ area one short paragraph: same-worktree multi-platform use is supported; each platform keeps its own open round and Session Handoff; same-platform multiple windows are not. In `recording-moments.md` update the "Concurrent sessions" bullet to point at `multi-platform-concurrency.md`; in `session-handoff-file.md` "Out of scope" replace the multi-agent bullet with "Resolved for different platforms by `multi-platform-concurrency.md`". Change the spec's `Status:` line to `implemented`.

- [ ] **Step 4: Regenerate and verify**

```bash
node scripts/sync-codex-plugin.js
shellcheck --external-sources --source-path=SCRIPTDIR -S warning \
 core/scripts/*.sh core/scripts/tests/*.sh cursor/hooks/*.sh codex/hooks/*.sh
bash core/scripts/run-tests.sh
npm test
```

Expected: all pass, no sync problems.

- [ ] **Step 5: Commit**

```bash
git add skills commands codex/skills README.md README.zh-TW.md docs/design
git commit -m "docs: document per-platform round files"
```
