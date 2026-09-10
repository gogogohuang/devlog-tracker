# Hook JSON helper Implementation Plan

> **HISTORICAL.** Part of the 0.4→0.5 batch (`optimization-plans.md`). Do not re-execute.


> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One sourced helper for the flat JSON state files (`.span-open`, `.checkpoint-state`, `.segment-state`, `.round-open`) so hooks stop duplicating grep/awk `gsub`.

**Architecture:** `hooks/scripts/json-field.sh` is sourced, never executed as a hook. Integer and quoted-string get/set. Prefer `jq` when present; otherwise the same grep/awk the scripts use today. Callers stay fail-open: empty get means "malformed".

**Tech Stack:** bash, optional `jq`, existing hook self-checks.

## Global Constraints

- State files stay one-object JSON with scalar fields. No nested objects.
- `json_int_get` must reject zero-padded values that bash would treat as octal (`08`). Treat them as empty (fail-open), matching span-mode known limitation.
- Set writes via temp file + `mv`, same as today.
- Do not bump version. Batch release is **0.5.0** after all optimization plans (`docs/design/version-0.5.0-plan.md`).
- After migrating a caller, that caller's existing `test-*.sh` must still pass unchanged (except tests that grepped implementation details).
- This repo gitignores `docs/superpowers/`. This plan lives under `docs/design/`.

## File Structure

| File | Responsibility |
|---|---|
| `hooks/scripts/json-field.sh` | `json_int_get`, `json_str_get`, `json_int_set`, `json_str_set` |
| `hooks/scripts/test-json-field.sh` | helper self-check |
| `hooks/scripts/round-start.sh` | source helper; replace span/checkpoint/segment/round-open writes |
| `hooks/scripts/enforce-devlog.sh` | source helper for span + checkpoint |
| `hooks/scripts/segment-watch.sh` | source helper |
| `hooks/scripts/session-start-devlog.sh` | source helper for span note |
| `hooks/scripts/close-open-round.sh` | source helper for `"round"` |

---

### Task 1: Helper + tests

**Files:**
- Create: `hooks/scripts/json-field.sh`
- Create: `hooks/scripts/test-json-field.sh`

**Interfaces:**
- `json_int_get FILE KEY` → stdout digits or empty; exit 0
- `json_str_get FILE KEY` → stdout string (no quotes) or empty; exit 0
- `json_int_set FILE KEY VALUE` → rewrite file; VALUE must be `[0-9]+` with no leading zeros unless the value is `0`
- `json_str_set FILE KEY VALUE` → quoted JSON string; VALUE must not contain `"` or newlines (callers pass cksum / ISO timestamps)

- [ ] **Step 1: Write `hooks/scripts/test-json-field.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
FAIL=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then echo "PASS: $desc"
  else echo "FAIL: $desc (expected [$expected] got [$actual])"; FAIL=1; fi
}

printf '%s\n' '{"ticks_since_checkin": 2, "max_silent_ticks": 5}' > "$TMP"
assert_eq "int get" "2" "$(json_int_get "$TMP" ticks_since_checkin)"
assert_eq "int get max" "5" "$(json_int_get "$TMP" max_silent_ticks)"
assert_eq "missing key" "" "$(json_int_get "$TMP" no_such)"

printf '%s\n' '{"ticks_since_checkin": 08}' > "$TMP"
assert_eq "reject octal pad" "" "$(json_int_get "$TMP" ticks_since_checkin)"

printf '%s\n' '{"opened_at": "2026-09-08T21:40:00+08:00", "round": 12}' > "$TMP"
assert_eq "str get" "2026-09-08T21:40:00+08:00" "$(json_str_get "$TMP" opened_at)"
assert_eq "int round" "12" "$(json_int_get "$TMP" round)"

printf '%s\n' '{"ticks_since_checkin": 2, "max_silent_ticks": 5}' > "$TMP"
json_int_set "$TMP" ticks_since_checkin 0
assert_eq "int set" "0" "$(json_int_get "$TMP" ticks_since_checkin)"
assert_eq "int set preserves sibling" "5" "$(json_int_get "$TMP" max_silent_ticks)"

printf '%s\n' '{"last_seen_cksum": "old", "last_change_epoch": 1}' > "$TMP"
json_str_set "$TMP" last_seen_cksum "123 2"
assert_eq "str set" "123 2" "$(json_str_get "$TMP" last_seen_cksum)"
assert_eq "str set preserves epoch" "1" "$(json_int_get "$TMP" last_change_epoch)"

printf '%s\n' 'not json' > "$TMP"
assert_eq "malformed int" "" "$(json_int_get "$TMP" round)"
assert_eq "malformed str" "" "$(json_str_get "$TMP" opened_at)"

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
```

- [ ] **Step 2: Run to verify it fails**

```bash
bash hooks/scripts/test-json-field.sh
```

Expected: fail (missing `json-field.sh` or missing functions).

- [ ] **Step 3: Write `hooks/scripts/json-field.sh`**

```bash
# sourced by hook scripts. Do not execute.
json_int_get() {
  local file="$1" key="$2" raw=""
  [ -f "$file" ] || { echo ''; return 0; }
  if command -v jq >/dev/null 2>&1; then
    raw="$(jq -r --arg k "$key" '.[$k] | tostring' "$file" 2>/dev/null || echo '')"
    [ "$raw" = "null" ] && raw=""
  else
    raw="$(grep -o "\"$key\"[[:space:]]*:[[:space:]]*[0-9]\\+" "$file" 2>/dev/null | grep -o '[0-9]\\+$' || echo '')"
  fi
  case "$raw" in
    ''|*[!0-9]*) echo ''; return 0 ;;
    0) echo 0; return 0 ;;
    0*) echo ''; return 0 ;;
    *) echo "$raw"; return 0 ;;
  esac
}

json_str_get() {
  local file="$1" key="$2" raw=""
  [ -f "$file" ] || { echo ''; return 0; }
  if command -v jq >/dev/null 2>&1; then
    raw="$(jq -r --arg k "$key" '.[$k] // empty' "$file" 2>/dev/null || echo '')"
    [ "$raw" = "null" ] && raw=""
    printf '%s' "$raw"
    echo
    return 0
  fi
  raw="$(grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" 2>/dev/null | head -1 || echo '')"
  printf '%s' "$raw" | sed -E "s/^.*\"$key\"[[:space:]]*:[[:space:]]*\"//; s/\"$//"
  echo
}

json_int_set() {
  local file="$1" key="$2" val="$3"
  [ -f "$file" ] || return 0
  case "$val" in ''|*[!0-9]*) return 0 ;; esac
  awk -v key="$key" -v val="$val" '{
    pat = "\"" key "\"[[:space:]]*:[[:space:]]*[0-9]+"
    repl = "\"" key "\": " val
    gsub(pat, repl)
    print
  }' "$file" > "$file.tmp" 2>/dev/null && mv "$file.tmp" "$file" 2>/dev/null || true
}

json_str_set() {
  local file="$1" key="$2" val="$3"
  [ -f "$file" ] || return 0
  case "$val" in *\"*|*[$'\n']*) return 0 ;; esac
  awk -v key="$key" -v val="$val" '{
    pat = "\"" key "\"[[:space:]]*:[[:space:]]*\"[^\"]*\""
    repl = "\"" key "\": \"" val "\""
    gsub(pat, repl)
    print
  }' "$file" > "$file.tmp" 2>/dev/null && mv "$file.tmp" "$file" 2>/dev/null || true
}
```

Note: in the real file, grep character classes are `[0-9]\+` (single backslash inside double quotes in the script as it exists on disk). Copy the grep lines from `round-start.sh` today if the escaped version above is ambiguous.

- [ ] **Step 4: Run tests**

```bash
bash hooks/scripts/test-json-field.sh
```

Expected: `All checks passed.`

- [ ] **Step 5: Commit**

```bash
git add hooks/scripts/json-field.sh hooks/scripts/test-json-field.sh
git commit -m "$(cat <<'EOF'
feat: add a shared JSON field helper for hook state files

EOF
)"
```

---

### Task 2: Migrate callers

**Files:**
- Modify: `hooks/scripts/round-start.sh` (after `SCRIPT_DIR` / `HOOKS_DIR`, add `. "$HOOKS_DIR/json-field.sh"`)
- Modify: `hooks/scripts/enforce-devlog.sh`
- Modify: `hooks/scripts/segment-watch.sh`
- Modify: `hooks/scripts/session-start-devlog.sh`
- Modify: `hooks/scripts/close-open-round.sh`

**Interfaces:**
- Same on-disk JSON. Replace each `grep -o '"ticks_since_checkin"'` block with `json_int_get`. Replace `awk gsub` sets with `json_int_set` / `json_str_set`.
- `round-open` write in `round-start.sh` may stay as `printf '{"round": %s, "opened_at": "%s"}\n'` (creates the file). Reading `"round"` in `close-open-round.sh` uses `json_int_get "$ROUND_OPEN" round`.

- [ ] **Step 1: Migrate one file, run its test, repeat**

Order: `close-open-round.sh` → `test-close-open-round.sh`; `segment-watch.sh` → `test-segment-watch.sh`; `round-start.sh` → `test-round-start.sh`; `enforce-devlog.sh` → `test-enforce-devlog.sh`; `session-start-devlog.sh` → `test-session-start-devlog.sh`.

Example replacement in `enforce-devlog.sh` span block:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"
# ...
SPAN_TICKS="$(json_int_get "$SPAN_FILE" ticks_since_checkin)"
SPAN_MAX="$(json_int_get "$SPAN_FILE" max_silent_ticks)"
# reset:
json_int_set "$SPAN_FILE" ticks_since_checkin 0
```

Checkpoint block:

```bash
CP_ROUNDS="$(json_int_get "$CHECKPOINT_FILE" rounds_since_checkpoint)"
CP_MAX="$(json_int_get "$CHECKPOINT_FILE" max_silent_rounds)"
CP_SEEN="$(json_int_get "$CHECKPOINT_FILE" checkpoint_marker_count)"
json_int_set "$CHECKPOINT_FILE" checkpoint_marker_count "$CURRENT_MARKER_COUNT"
json_int_set "$CHECKPOINT_FILE" rounds_since_checkpoint 0
```

- [ ] **Step 2: Run the full hook suite**

```bash
bash hooks/scripts/test-json-field.sh && \
bash hooks/scripts/test-close-open-round.sh && \
bash hooks/scripts/test-round-start.sh && \
bash hooks/scripts/test-enforce-devlog.sh && \
bash hooks/scripts/test-segment-watch.sh && \
bash hooks/scripts/test-session-start-devlog.sh && \
bash hooks/scripts/test-on-interrupt.sh
```

Expected: each prints `All checks passed.`

- [ ] **Step 3: Commit**

```bash
git add hooks/scripts/*.sh
git commit -m "$(cat <<'EOF'
refactor: read and write hook state JSON through json-field.sh

EOF
)"
```

