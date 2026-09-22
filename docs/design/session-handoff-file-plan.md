# Session Handoff File Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop extracts `### Session Handoff` from each finished `IN_PROGRESS`／`BLOCKED` round into a branch-scoped `.devlog/handoff[.branch].md`; SessionStart injects that file first; `DONE` deletes it.

**Architecture:** Claude authors `### Session Handoff` (決策／待解問題／失敗嘗試) inside `.round-current.md`. `enforce-devlog.sh` hard-checks it on unfinished statuses before merge, then calls `handoff-file.sh` after merge to overwrite or delete `$HANDOFF_FILE` (set by `devlog_resolve_paths`). SessionStart prefixes a non-empty handoff file onto the existing excerpt. No multi-agent lock.

**Tech Stack:** bash, awk (fence-aware), existing hook self-check style (`assert_exit`／`PASS`／`FAIL`), `run-tests.sh` glob discovery.

**Spec:** `docs/design/session-handoff-file.md`

## Global Constraints

- Do **not** bump version (`package.json` / plugin.json / README version lines).
- Do **not** add file locking for concurrent writers (Known limitation in the spec).
- Do **not** rename `handoff.md` → `handoff.<branch>.md` on first branch resolve (intentional divergence from `devlog.md` migration).
- Claude must never be instructed to Edit／Write `handoff.md` directly — only Round `### Session Handoff`.
- Validate Session Handoff **before** merge; write／clear **after** successful merge; I/O errors on write／clear are fail-open (stderr only).
- Span quiet ticks that exit early never hit these checks (unchanged).
- `DONE` does not require `### Session Handoff`; if present, ignore content; still `rm -f "$HANDOFF_FILE"`.
- `INTERRUPTED`／`close-open-round.sh` never touch `$HANDOFF_FILE`.
- This repo gitignores `docs/superpowers/`; this plan lives under `docs/design/`.
- Skip every **Commit** step unless the human has explicitly asked to commit in this conversation; leave changes uncommitted.
- After code changes, before finishing: run the three CI steps from `AGENTS.md` (`shellcheck`, `bash core/scripts/run-tests.sh`, `npm test`).

## File Structure

| File | Responsibility |
|---|---|
| `core/scripts/devlog-path.sh` | Also set `HANDOFF_FILE` beside `DEVLOG_FILE` |
| `core/scripts/handoff-file.sh` | Extract／validate-order helpers, `handoff_write`, `handoff_clear` |
| `core/scripts/enforce-devlog.sh` | Hard-check on `IN_PROGRESS`／`BLOCKED`; post-merge write／clear |
| `core/scripts/session-start-devlog.sh` | Prefix-inject non-empty `$HANDOFF_FILE` |
| `core/scripts/clean-devlog.sh` | `rm -f "$HANDOFF_FILE"` on clean |
| `core/scripts/tests/test-handoff-file.sh` | Unit tests for helper |
| `core/scripts/tests/test-enforce-devlog-session-handoff.sh` | Enforce integration |
| `core/scripts/tests/test-devlog-path.sh` | Assert `HANDOFF_FILE` mapping |
| `core/scripts/tests/test-session-start-devlog.sh` | Injection order |
| `core/scripts/tests/test-clean-devlog.sh` | Clean removes handoff |
| Existing `test-enforce-devlog*.sh` that close `IN_PROGRESS`／`BLOCKED` | Add minimal `### Session Handoff` so they keep passing |
| `skills/devlog-tracker/SKILL.md` + `references/contract.md` + `references/checkpoint-mode.md` | Authoring + hard-check contract |
| `README.md`／`README.zh-TW.md` | Short SessionStart mention |

---

### Task 1: `HANDOFF_FILE` in `devlog_resolve_paths`

**Files:**
- Modify: `core/scripts/devlog-path.sh`
- Modify: `core/scripts/tests/test-devlog-path.sh`

**Interfaces:**
- Consumes: existing `devlog_resolve_paths`, `_devlog_sanitize_name`
- Produces: after `devlog_resolve_paths "$dir"`, `HANDOFF_FILE` is set:
  - shared cases → `$DEVLOG_DIR/handoff.md`
  - branch cases → `$DEVLOG_DIR/handoff.<same-name-as-devlog-suffix>.md`
  - **no** rename migration of an existing `handoff.md`

- [ ] **Step 1: Write failing assertions**

Append to `core/scripts/tests/test-devlog-path.sh` (after the matching `DEVLOG_FILE` asserts, same fixtures):

```bash
# --- HANDOFF_FILE mirrors DEVLOG_FILE naming (no rename migration) --------
devlog_resolve_paths "$NONGIT"
[ "$HANDOFF_FILE" = "$NONGIT/.devlog/handoff.md" ] \
  && echo "PASS: non-git HANDOFF_FILE is handoff.md" \
  || { echo "FAIL: non-git HANDOFF_FILE=$HANDOFF_FILE"; FAIL=1; }

devlog_resolve_paths "$MAINREPO"
[ "$HANDOFF_FILE" = "$MAINREPO/.devlog/handoff.md" ] \
  && echo "PASS: main HANDOFF_FILE is handoff.md" \
  || { echo "FAIL: main HANDOFF_FILE=$HANDOFF_FILE"; FAIL=1; }

devlog_resolve_paths "$FEATREPO"
[ "$HANDOFF_FILE" = "$FEATREPO/.devlog/handoff.feature-x.md" ] \
  && echo "PASS: feature HANDOFF_FILE is handoff.feature-x.md" \
  || { echo "FAIL: feature HANDOFF_FILE=$HANDOFF_FILE"; FAIL=1; }

devlog_resolve_paths "$SLASHREPO"
[ "$HANDOFF_FILE" = "$SLASHREPO/.devlog/handoff.feature-foo.md" ] \
  && echo "PASS: slash branch HANDOFF_FILE sanitized" \
  || { echo "FAIL: slash HANDOFF_FILE=$HANDOFF_FILE"; FAIL=1; }

devlog_resolve_paths "$DETACHEDREPO"
[ "$HANDOFF_FILE" = "$DETACHEDREPO/.devlog/handoff.detached-repo.md" ] \
  && echo "PASS: detached HANDOFF_FILE uses worktree dirname" \
  || { echo "FAIL: detached HANDOFF_FILE=$HANDOFF_FILE"; FAIL=1; }

# migration must NOT move handoff.md
MIGHO="$TMP/mighandoff"
mkdir -p "$MIGHO/.devlog"
: > "$MIGHO/.devlog/.enabled"
git_setup "$MIGHO"
git -C "$MIGHO" checkout -q -b feature-h
echo "old handoff" > "$MIGHO/.devlog/handoff.md"
echo "## Round 1" > "$MIGHO/.devlog/devlog.md"
devlog_resolve_paths "$MIGHO"
if [ -f "$MIGHO/.devlog/handoff.md" ] \
  && [ ! -f "$MIGHO/.devlog/handoff.feature-h.md" ] \
  && [ "$HANDOFF_FILE" = "$MIGHO/.devlog/handoff.feature-h.md" ]; then
  echo "PASS: handoff.md is not renamed on first branch resolve"
else
  echo "FAIL: handoff migration diverged (HANDOFF_FILE=$HANDOFF_FILE)"
  FAIL=1
fi
```

- [ ] **Step 2: Run test — expect FAIL on HANDOFF_FILE asserts**

Run: `bash core/scripts/tests/test-devlog-path.sh`

Expected: existing `DEVLOG_FILE` cases still PASS; new `HANDOFF_FILE` asserts FAIL (`HANDOFF_FILE` empty／unset).

- [ ] **Step 3: Implement `HANDOFF_FILE` in `devlog_resolve_paths`**

In `core/scripts/devlog-path.sh`, inside `devlog_resolve_paths`:

1. Right after `DEVLOG_FILE="$DEVLOG_DIR/devlog.md"`, also set `HANDOFF_FILE="$DEVLOG_DIR/handoff.md"`.
2. On every early `return 0` that keeps the shared `devlog.md` (main／master／empty／reserved `archive`／`lessons.*`), leave `HANDOFF_FILE` as the shared `handoff.md`.
3. When assigning `DEVLOG_FILE="$resolved"` for a branch file `devlog.$name.md`, also set `HANDOFF_FILE="$DEVLOG_DIR/handoff.$name.md"`.
4. Do **not** add any `mv` involving `handoff.md`.

- [ ] **Step 4: Re-run test — expect all PASS**

Run: `bash core/scripts/tests/test-devlog-path.sh`

Expected: all PASS including the no-rename case.

- [ ] **Step 5: Commit** (skip unless user asked)

```bash
git add core/scripts/devlog-path.sh core/scripts/tests/test-devlog-path.sh
git commit -m "$(cat <<'EOF'
feat: resolve branch-scoped HANDOFF_FILE beside DEVLOG_FILE

EOF
)"
```

---

### Task 2: `handoff-file.sh` helper

**Files:**
- Create: `core/scripts/handoff-file.sh`
- Create: `core/scripts/tests/test-handoff-file.sh`

**Interfaces:**
- Consumes: nothing from Task 1 at runtime (path is an argument); sourced by enforce later
- Produces (bash functions, sourced):
  - `handoff_session_section_ok "$round_blob"` → exit 0 if `### Session Handoff` has `#### 決策`／`#### 待解問題`／`#### 失敗嘗試` in order, each with a non-empty body line; else exit 1
  - `handoff_extract_file_body "$round_blob"` → stdout = independent-file markdown (`## Session Handoff` + three `###` sections); empty／fail → exit 1
  - `handoff_write "$path" "$round_blob"` → extract + atomic write (`mktemp` in same dir + `mv`); fail-open style: return non-zero on I/O but caller decides
  - `handoff_clear "$path"` → `rm -f "$path"`

- [ ] **Step 1: Write failing unit test**

Create `core/scripts/tests/test-handoff-file.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../handoff-file.sh
. "$SCRIPT_DIR/handoff-file.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0

GOOD_ROUND='## Round 1 — 2026-09-22T00:00:00+08:00

### Summary
s

### Reply
r

### Handoff
#### 現況
c
#### 完成條件
done when tests pass
#### 下一步
edit core/scripts/handoff-file.sh

### Session Handoff

#### 決策
- pick route A

#### 待解問題
- （無）

#### 失敗嘗試
- tried parse-in-place

### Status
IN_PROGRESS
'

BAD_ORDER='### Session Handoff
#### 待解問題
- x
#### 決策
- y
#### 失敗嘗試
- z
'

MISSING='### Session Handoff
#### 決策
- x
#### 失敗嘗試
- z
'

if handoff_session_section_ok "$GOOD_ROUND"; then
  echo "PASS: good round validates"
else
  echo "FAIL: good round should validate"; FAIL=1
fi

if handoff_session_section_ok "$BAD_ORDER"; then
  echo "FAIL: bad order should fail"; FAIL=1
else
  echo "PASS: bad order rejected"
fi

if handoff_session_section_ok "$MISSING"; then
  echo "FAIL: missing 待解問題 should fail"; FAIL=1
else
  echo "PASS: missing subsection rejected"
fi

OUT="$(handoff_extract_file_body "$GOOD_ROUND")" || { echo "FAIL: extract exited $?"; FAIL=1; OUT=""; }
case "$OUT" in
  *"## Session Handoff"*### 決策*pick route A*### 待解問題*（無）*### 失敗嘗試*tried parse-in-place*)
    echo "PASS: extract shape"
    ;;
  *)
    echo "FAIL: extract shape, got: $OUT"; FAIL=1
    ;;
esac

TARGET="$TMP/handoff.md"
handoff_write "$TARGET" "$GOOD_ROUND" || { echo "FAIL: write"; FAIL=1; }
[ -s "$TARGET" ] && grep -q 'pick route A' "$TARGET" \
  && echo "PASS: write creates file" \
  || { echo "FAIL: write"; FAIL=1; }

handoff_clear "$TARGET"
[ ! -f "$TARGET" ] && echo "PASS: clear removes file" \
  || { echo "FAIL: clear left file"; FAIL=1; }

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

- [ ] **Step 2: Run — expect FAIL** (source／functions missing)

Run: `bash core/scripts/tests/test-handoff-file.sh`

Expected: FAIL／error sourcing `handoff-file.sh`.

- [ ] **Step 3: Implement `core/scripts/handoff-file.sh`**

Requirements:

- Fence-aware (` ``` ` toggles) when scanning headings, same spirit as `session-start-devlog.sh`／`enforce-devlog.sh`.
- `handoff_session_section_ok`: find `### Session Handoff` … next `### ` or `## `; inside that span require the three `####` names in order 1→2→3, no duplicates among the three, each name followed by at least one non-whitespace body line before the next `####`／`###`／`##`.
- `handoff_extract_file_body`: same span; emit:

```markdown
## Session Handoff

### 決策
<body lines>

### 待解問題
<body lines>

### 失敗嘗試
<body lines>
```

- `handoff_write`: `dir=$(dirname "$path")`; `tmp=$(mktemp "$dir/.handoff.XXXXXX")`; write extract to tmp; `mv "$tmp" "$path"`.
- `handoff_clear`: `rm -f "$path"`.
- No `set -e`; functions return status explicitly.

- [ ] **Step 4: Run — expect all PASS**

Run: `bash core/scripts/tests/test-handoff-file.sh`

- [ ] **Step 5: Commit** (skip unless user asked)

```bash
git add core/scripts/handoff-file.sh core/scripts/tests/test-handoff-file.sh
git commit -m "$(cat <<'EOF'
feat: add handoff-file extract/write/clear helpers

EOF
)"
```

---

### Task 3: Wire Stop enforcement + post-merge write／clear

**Files:**
- Modify: `core/scripts/enforce-devlog.sh`
- Create: `core/scripts/tests/test-enforce-devlog-session-handoff.sh`
- Modify: every existing test that successfully closes an `IN_PROGRESS`／`BLOCKED` round via `enforce-devlog.sh` so the fixture includes a minimal `### Session Handoff` (otherwise they regress to exit 2). Known touch list:
  - `core/scripts/tests/test-enforce-devlog-workspace.sh` (`write_round`)
  - `core/scripts/tests/test-enforce-devlog.sh` (any IN_PROGRESS／BLOCKED success paths)
  - `core/scripts/tests/test-enforce-devlog-files.sh` (if it closes unfinished statuses)
  - Grep `enforce-devlog.sh` callers under `core/scripts/tests/` and fix any remaining.

**Interfaces:**
- Consumes: `handoff_session_section_ok`, `handoff_write`, `handoff_clear`, `$HANDOFF_FILE` from `devlog_resolve_paths`
- Produces: unfinished rounds blocked without Session Handoff; success writes／clears file

- [ ] **Step 1: Write failing integration test**

Create `core/scripts/tests/test-enforce-devlog-session-handoff.sh` modeled on `test-enforce-devlog-workspace.sh`:

- Temp git repo, `.enabled`, `round-start.sh`, then overwrite `.round-current.md`.
- Helper `write_unfinished_round` with: Summary／Reply／Handoff（現況＋完成條件＋下一步＋正確 `#### 工作區`）、optional Session Handoff、Status `IN_PROGRESS` or `BLOCKED`.
- Cases:
  1. `IN_PROGRESS` **without** Session Handoff → exit 2; stderr mentions `Session Handoff`
  2. `IN_PROGRESS` **with** three subsections → exit 0; `$DEVLOG_DIR/handoff.md` contains `## Session Handoff` and a decision bullet
  3. `BLOCKED` with Session Handoff → exit 0; handoff file updated
  4. Pre-create `handoff.md`, then `DONE` round (no Session Handoff, no 工作區 needed if no 檔案) → exit 0; `handoff.md` **gone**
  5. Pre-create `handoff.md`, wrong Session Handoff order on `IN_PROGRESS` → exit 2; `handoff.md` **unchanged** (validate before merge／write)

Minimal Session Handoff block for success fixtures:

```markdown
### Session Handoff

#### 決策
- （無）

#### 待解問題
- still wiring enforce

#### 失敗嘗試
- （無）
```

- [ ] **Step 2: Run new test — expect FAIL**

Run: `bash core/scripts/tests/test-enforce-devlog-session-handoff.sh`

Expected: cases that need the new check FAIL (exit 0 when expecting 2, or file not written).

- [ ] **Step 3: Source helper + validate before merge in `enforce-devlog.sh`**

Near other sourced helpers at top:

```bash
# shellcheck source=handoff-file.sh
. "$HOOKS_DIR/handoff-file.sh"
```

After Status is known and the existing `IN_PROGRESS`／`BLOCKED` Handoff checks (完成條件／下一步／工作區／…) pass, add:

```bash
if [ "$STATUS_VAL" = "IN_PROGRESS" ] || [ "$STATUS_VAL" = "BLOCKED" ]; then
  if ! handoff_session_section_ok "$LAST_ROUND"; then
    echo "Status 是 IN_PROGRESS 或 BLOCKED 時，必須有 \`### Session Handoff\`，且依序包含 \`#### 決策\`／\`#### 待解問題\`／\`#### 失敗嘗試\`（可寫 \`- （無）\`）。寫完後 hook 會覆寫 .devlog/handoff.md 給下一 session。" >&2
    exit 2
  fi
fi
```

Do **not** lint Session Handoff on `DONE`.

- [ ] **Step 4: Post-merge write／clear**

Immediately after successful `devlog_merge_round_current` (where `.round-open` is cleared), using the Status already computed for this turn (keep it in a variable that survives to this point — if today Status is only inside a subshell, hoist it):

```bash
case "$STATUS_VAL" in
  IN_PROGRESS|BLOCKED)
    handoff_write "$HANDOFF_FILE" "$LAST_ROUND" 2>/dev/null || \
      echo "警告：無法寫入 Session Handoff 檔（$HANDOFF_FILE），本輪仍已收尾。" >&2
    ;;
  DONE)
    handoff_clear "$HANDOFF_FILE" 2>/dev/null || \
      echo "警告：無法清除 Session Handoff 檔（$HANDOFF_FILE），本輪仍已收尾。" >&2
    ;;
esac
```

`INTERRUPTED` omitted. If merge was skipped (fail-open empty `LAST_ROUND`), skip this block entirely.

- [ ] **Step 5: Update existing unfinished-status fixtures**

Add the minimal Session Handoff block to every `write_round`／fixture that expects `enforce-devlog.sh` exit 0 with `IN_PROGRESS`／`BLOCKED`. Place it **after** `### Handoff` body and **before** `### Status`.

- [ ] **Step 6: Run targeted tests**

```bash
bash core/scripts/tests/test-enforce-devlog-session-handoff.sh
bash core/scripts/tests/test-enforce-devlog-workspace.sh
bash core/scripts/tests/test-enforce-devlog.sh
bash core/scripts/tests/test-enforce-devlog-files.sh
bash core/scripts/tests/test-enforce-devlog-handoff-order.sh
```

Expected: all PASS.

- [ ] **Step 7: Commit** (skip unless user asked)

```bash
git add core/scripts/enforce-devlog.sh core/scripts/tests/test-enforce-devlog-session-handoff.sh \
  core/scripts/tests/test-enforce-devlog-workspace.sh core/scripts/tests/test-enforce-devlog.sh \
  core/scripts/tests/test-enforce-devlog-files.sh
git commit -m "$(cat <<'EOF'
feat: enforce Session Handoff and sync handoff.md on Stop

EOF
)"
```

---

### Task 4: SessionStart prefix injection

**Files:**
- Modify: `core/scripts/session-start-devlog.sh`
- Modify: `core/scripts/tests/test-session-start-devlog.sh`

**Interfaces:**
- Consumes: `$HANDOFF_FILE` from `devlog_resolve_paths` (already sourced)
- Produces: non-empty handoff printed after span note, before the `DEVLOG_FILE` excerpt header

- [ ] **Step 1: Add failing scenarios to `test-session-start-devlog.sh`**

```bash
# --- handoff.md present: printed before excerpt header --------------------
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/handoff.md" "$DEVLOG_DIR/.span-open"
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 1 — 2026-09-22T00:00:00+08:00

### Summary
summary 1

### Handoff
#### 現況
handoff 1

### Status
DONE
EOF
cat > "$DEVLOG_DIR/handoff.md" <<'EOF'
## Session Handoff

### 決策
- keep route A

### 待解問題
- open Q

### 失敗嘗試
- （無）
EOF
OUTPUT="$(echo '{"source":"startup"}' | bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
assert_contains "handoff header present" "Session Handoff" "$OUTPUT"
assert_contains "handoff body present" "open Q" "$OUTPUT"
assert_contains "excerpt still present" "接手摘要" "$OUTPUT"
# ordering: handoff marker before excerpt marker
HOFF_POS="$(printf '%s\n' "$OUTPUT" | grep -n 'open Q' | head -1 | cut -d: -f1)"
EX_POS="$(printf '%s\n' "$OUTPUT" | grep -n '接手摘要' | head -1 | cut -d: -f1)"
if [ -n "$HOFF_POS" ] && [ -n "$EX_POS" ] && [ "$HOFF_POS" -lt "$EX_POS" ]; then
  echo "PASS: handoff prints before devlog excerpt"
else
  echo "FAIL: handoff should precede excerpt (hoff=$HOFF_POS ex=$EX_POS)"
  FAIL=1
fi

# --- no handoff.md: excerpt only -----------------------------------------
rm -f "$DEVLOG_DIR/handoff.md"
OUTPUT="$(echo '{"source":"startup"}' | bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
assert_not_contains "no handoff file -> no open Q" "open Q" "$OUTPUT"
assert_contains "excerpt still works" "接手摘要" "$OUTPUT"

# --- clear: still silent even with handoff.md ----------------------------
cat > "$DEVLOG_DIR/handoff.md" <<'EOF'
## Session Handoff
### 決策
- should not inject
EOF
OUTPUT="$(echo '{"source":"clear"}' | bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
if [ -z "$OUTPUT" ]; then
  echo "PASS: clear stays silent with handoff.md present"
else
  echo "FAIL: clear should be silent, got: $OUTPUT"; FAIL=1
fi
```

Place these where other startup scenarios live; reuse `assert_contains`／`assert_not_contains`.

- [ ] **Step 2: Run — expect FAIL on ordering／header**

Run: `bash core/scripts/tests/test-session-start-devlog.sh`

- [ ] **Step 3: Implement injection**

In `session-start-devlog.sh`, after the span-open block and **before** `if [ -f "$DEVLOG_FILE" ]; then`, insert:

```bash
if [ -s "${HANDOFF_FILE:-}" ]; then
  echo "以下是目前的 Session Handoff 快照（.devlog/${HANDOFF_FILE##*/}；精簡狀態，不是全文）："
  echo ""
  cat "$HANDOFF_FILE" 2>/dev/null || true
  echo ""
fi
```

`HANDOFF_FILE` must already be set by the existing `devlog_resolve_paths` call at the top. `clear` returns earlier — unchanged.

- [ ] **Step 4: Re-run — expect PASS**

Run: `bash core/scripts/tests/test-session-start-devlog.sh`

- [ ] **Step 5: Commit** (skip unless user asked)

```bash
git add core/scripts/session-start-devlog.sh core/scripts/tests/test-session-start-devlog.sh
git commit -m "$(cat <<'EOF'
feat: SessionStart injects handoff.md before devlog excerpt

EOF
)"
```

---

### Task 5: `clean` removes `$HANDOFF_FILE`

**Files:**
- Modify: `core/scripts/clean-devlog.sh`
- Modify: `core/scripts/tests/test-clean-devlog.sh`

- [ ] **Step 1: Failing assert**

In a no-open-round clean scenario that already deletes `devlog.md`, also:

```bash
echo "## Session Handoff" > "$DEVLOG_DIR/handoff.md"
# ... run clean --confirmed ...
[ ! -f "$DEVLOG_DIR/handoff.md" ] \
  && echo "PASS: clean removes handoff.md" \
  || { echo "FAIL: handoff.md survived clean"; FAIL=1; }
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

After resolving paths, in both clean branches (open round kept / fully cleared), add `rm -f "$HANDOFF_FILE"` alongside removing `$MAIN` (or right after the successful clear). Prefer once at the end of a successful clean so both paths share it.

- [ ] **Step 4: Re-run — expect PASS**

- [ ] **Step 5: Commit** (skip unless user asked)

```bash
git add core/scripts/clean-devlog.sh core/scripts/tests/test-clean-devlog.sh
git commit -m "$(cat <<'EOF'
feat: clean also deletes branch-scoped handoff file

EOF
)"
```

---

### Task 6: Docs — SKILL／contract／checkpoint／README

**Files:**
- Modify: `skills/devlog-tracker/SKILL.md`
- Modify: `skills/devlog-tracker/references/contract.md`
- Modify: `skills/devlog-tracker/references/checkpoint-mode.md`
- Modify: `README.md`
- Modify: `README.zh-TW.md`

- [ ] **Step 1: SKILL.md**

1. **檔案位置** — add bullet:
   - Session Handoff 快照：`.devlog/handoff.md`（`main`／`master`）；其他分支 `.devlog/handoff.<branch>.md`。由 Stop 覆寫／`DONE` 時刪除；Claude 只寫 Round 內 `### Session Handoff`，不要直接編這個檔。
2. **每一輪的紀錄格式** — insert `### Session Handoff` template between Handoff and Status (three `####` fields, `- （無）` allowed). State: required when Status is `IN_PROGRESS`／`BLOCKED`; omitted on `DONE`; not written on `INTERRUPTED` stubs.
3. **Stop 檢查段落** — add hard check for Session Handoff on unfinished statuses; note post-merge sync／clear of `$HANDOFF_FILE`.
4. **SessionStart 自動注入** — step list: handoff snapshot first (if present), then Checkpoint／Kept／Lessons／last two rounds.
5. Explicit: `DONE` deletes the file — not durable history.

- [ ] **Step 2: `references/contract.md`**

Add a Hard row: Session Handoff required on `IN_PROGRESS`／`BLOCKED` → Stop `enforce-devlog.sh` + `handoff-file.sh`; pointer to `docs/design/session-handoff-file.md`.

- [ ] **Step 3: `references/checkpoint-mode.md`**

One short cross-link after the three-field template: same fields as Session Handoff file; Checkpoint is a durable marker inside `devlog.md`, Session Handoff is the volatile `.devlog/handoff.md` snapshot (`docs/design/session-handoff-file.md`).

- [ ] **Step 4: README.md + README.zh-TW.md**

Under SessionStart／recording flow: mention that a non-empty branch-scoped `handoff.md` is injected first, then the existing excerpt; Stop keeps it in sync on unfinished rounds and deletes it on `DONE`. Link `docs/design/session-handoff-file.md`. Do **not** change the `**Version**`／`**版本**` lines.

- [ ] **Step 5: Commit** (skip unless user asked)

```bash
git add skills/devlog-tracker/SKILL.md skills/devlog-tracker/references/contract.md \
  skills/devlog-tracker/references/checkpoint-mode.md README.md README.zh-TW.md
git commit -m "$(cat <<'EOF'
docs: document Session Handoff file authoring and injection

EOF
)"
```

---

### Task 7: Full CI gate

- [ ] **Step 1: shellcheck**

```bash
shellcheck --external-sources --source-path=SCRIPTDIR -S warning \
  core/scripts/*.sh core/scripts/tests/*.sh cursor/hooks/*.sh codex/hooks/*.sh
```

Expected: no new warnings on `handoff-file.sh`／touched scripts.

- [ ] **Step 2: hook self-checks**

```bash
bash core/scripts/run-tests.sh
```

Expected: `All hook self-checks passed.`

- [ ] **Step 3: npm test**

```bash
npm test
```

Expected: pass.

- [ ] **Step 4: Commit** only if the human asked to commit the whole feature as one or more commits; otherwise stop with a short summary of files changed.

---

## Spec coverage (self-review)

| Spec requirement | Task |
|---|---|
| Independent `handoff[.branch].md` | 1, 2, 3 |
| Round `### Session Handoff` authoring | 3, 6 |
| Overwrite on IN_PROGRESS／BLOCKED | 3 |
| Delete on DONE | 3 |
| Untouched on INTERRUPTED | 3 (omit) + covered by not calling writer from close-open-round |
| SessionStart prefix + keep excerpt | 4 |
| Hard enforce three subsections | 2, 3 |
| No handoff.md rename migration | 1 |
| clean deletes handoff | 5 |
| Docs／SKILL／contract | 6 |
| Out of scope: locks, drop last-2-rounds, Claude edits file | Global Constraints |

## Placeholder scan

No TBD／TODO／"similar to Task N" left in steps.

## Type／name consistency

- File helper: `handoff-file.sh` with `handoff_session_section_ok`／`handoff_extract_file_body`／`handoff_write`／`handoff_clear`
- Env path: `HANDOFF_FILE` from `devlog_resolve_paths`
- Round heading: `### Session Handoff` with `#### 決策`／`#### 待解問題`／`#### 失敗嘗試`
- Independent file heading: `## Session Handoff` with `###` subsections
