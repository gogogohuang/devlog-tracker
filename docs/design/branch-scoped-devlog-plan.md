# Branch-Scoped Devlog Files Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the devlog file that hooks read/write depend on the git branch currently checked out in the project directory, so switching branches in the same worktree no longer mixes unrelated work into one `devlog.md`.

**Architecture:** A new sourced helper, `hooks/scripts/devlog-path.sh`, exposes one function, `devlog_resolve_paths <dir>`, that sets `DEVLOG_DIR` and `DEVLOG_FILE` based on the branch checked out in `<dir>` (main/master keep `devlog.md`; other branches get `devlog.<sanitized-branch>.md`; detached HEAD falls back to the working directory's basename; anything undetectable falls back to `devlog.md`), performing a one-time rename-migration of an existing `devlog.md` the first time a branch's file doesn't exist yet. Every hook script that currently hardcodes `DEVLOG_DIR="$PROJECT_DIR/.devlog"` + `DEVLOG_FILE="$DEVLOG_DIR/devlog.md"` (or `MAIN="$DEVLOG_DIR/devlog.md"`) switches to sourcing this helper and calling the function instead.

**Tech Stack:** POSIX-ish bash (matching the rest of `hooks/scripts/`), `git`, `sed`, `mv`, the existing `devlog-lock.sh` mutual-exclusion helper.

**Spec:** `docs/design/branch-scoped-devlog.md`

## Global Constraints

- Only scripts that actually read or write `devlog.md`'s *content* need to change. `DEVLOG_DIR` itself (`$PROJECT_DIR/.devlog`) is never branch-scoped — only the filename inside it. Scripts that merely touch `.enabled`/`.span-open`/`.checkpoint-state`/`.segment-state`/`.lessons-enabled` and never reference `devlog.md` (`pause-devlog.sh`, `checkpoint-set.sh`, `segment-watch-set.sh`, `lessons-on.sh`, `span-close.sh`, `on-tool-failure.sh`) are **out of scope** — this corrects the design doc's file list, which over-included them; see note below.
- `resume-devlog.sh` is also **out of scope**: it already operates on an explicitly-named `devlog.<NAME>.md` via `--name`, never on "the" current branch file, so nothing about it changes.
- Every hook script keeps its existing fail-open posture: if `devlog_resolve_paths` can't determine a branch (not a git repo, `git` missing, detached with no resolvable dirname), it must leave `DEVLOG_FILE` pointing at plain `devlog.md`, exactly like today.
- `main`/`master` (any case) always keep `devlog.md` — never `devlog.main.md`.
- Sanitizing a name for `devlog.<name>.md`: replace anything outside `[A-Za-z0-9._-]` with `-`, collapse repeats, trim leading/trailing `-`.
- The one-time migration (`devlog.md` → `devlog.<name>.md`) is a **rename**, not a copy, and only fires when the resolved file doesn't already exist. It runs under `devlog-lock.sh`'s `devlog_lock_acquire`/`devlog_lock_release`.
- Do not change `DEVLOG_DIR`'s value or location. Do not touch `devlog.archive.md`, `/devlog-tracker:keep`'s `devlog.<name>.md`, or `devlog.lessons.<topic>.md` semantics.
- Every script's existing test file in `hooks/scripts/tests/` must still pass unmodified after that script's edit (its fixtures are plain temp directories, not git repos, so `devlog_resolve_paths` falls back to `devlog.md` there — see Task 1 rationale).
- Follow this repo's shellcheck-source-comment convention (`# shellcheck source=devlog-path.sh`) on every new `.` sourcing line, matching neighboring lines in the same file.
- Plan and spec live under `docs/design/` (this repo gitignores `docs/superpowers/`).

**Note on spec correction:** `docs/design/branch-scoped-devlog.md`'s "Files touched" table lists 18 scripts; actually inspecting each script for real `devlog.md` references narrows this to 13 scripts that need code changes (listed in Tasks 2–14) plus `resume-devlog.sh`, which needs none. `DEVLOG_DIR` is unaffected by this feature, so any script that never reads/writes `devlog.md` itself has nothing to change.

---

## Task 1: `devlog-path.sh` helper + its own tests

**Files:**
- Create: `hooks/scripts/devlog-path.sh`
- Create: `hooks/scripts/tests/test-devlog-path.sh`

**Interfaces:**
- Produces: `devlog_resolve_paths <dir>` — a shell function. Side effect: sets (in the caller's shell) `DEVLOG_DIR="<dir>/.devlog"` and `DEVLOG_FILE` (either `$DEVLOG_DIR/devlog.md` or `$DEVLOG_DIR/devlog.<name>.md`). No return value is meaningful; always returns 0.
- Consumes: `devlog_lock_acquire` / `devlog_lock_release` from `devlog-lock.sh` (sourced internally, not by the caller).

- [ ] **Step 1: Write the failing test file**

Create `hooks/scripts/tests/test-devlog-path.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$SCRIPT_DIR/devlog-path.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0

git_setup() {
  git -C "$1" init -q
  git -C "$1" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m init
}

# --- non-git directory: falls back to devlog.md -------------------------
NONGIT="$TMP/nongit"
mkdir -p "$NONGIT"
devlog_resolve_paths "$NONGIT"
[ "$DEVLOG_FILE" = "$NONGIT/.devlog/devlog.md" ] \
  && echo "PASS: non-git falls back to devlog.md" \
  || { echo "FAIL: non-git got $DEVLOG_FILE"; FAIL=1; }

# --- main branch: devlog.md ----------------------------------------------
MAINREPO="$TMP/mainrepo"
mkdir -p "$MAINREPO"
git_setup "$MAINREPO"
git -C "$MAINREPO" branch -M main
devlog_resolve_paths "$MAINREPO"
[ "$DEVLOG_FILE" = "$MAINREPO/.devlog/devlog.md" ] \
  && echo "PASS: main branch keeps devlog.md" \
  || { echo "FAIL: main got $DEVLOG_FILE"; FAIL=1; }

# --- master branch: devlog.md --------------------------------------------
MASTERREPO="$TMP/masterrepo"
mkdir -p "$MASTERREPO"
git_setup "$MASTERREPO"
git -C "$MASTERREPO" branch -M master
devlog_resolve_paths "$MASTERREPO"
[ "$DEVLOG_FILE" = "$MASTERREPO/.devlog/devlog.md" ] \
  && echo "PASS: master branch keeps devlog.md" \
  || { echo "FAIL: master got $DEVLOG_FILE"; FAIL=1; }

# --- feature branch: devlog.<branch>.md ----------------------------------
FEATREPO="$TMP/featrepo"
mkdir -p "$FEATREPO"
git_setup "$FEATREPO"
git -C "$FEATREPO" checkout -q -b feature-x
devlog_resolve_paths "$FEATREPO"
[ "$DEVLOG_FILE" = "$FEATREPO/.devlog/devlog.feature-x.md" ] \
  && echo "PASS: feature branch maps to devlog.feature-x.md" \
  || { echo "FAIL: feature-x got $DEVLOG_FILE"; FAIL=1; }

# --- branch with slash: sanitized ----------------------------------------
SLASHREPO="$TMP/slashrepo"
mkdir -p "$SLASHREPO"
git_setup "$SLASHREPO"
git -C "$SLASHREPO" checkout -q -b feature/foo
devlog_resolve_paths "$SLASHREPO"
[ "$DEVLOG_FILE" = "$SLASHREPO/.devlog/devlog.feature-foo.md" ] \
  && echo "PASS: slash in branch name sanitized to -" \
  || { echo "FAIL: feature/foo got $DEVLOG_FILE"; FAIL=1; }

# --- detached HEAD: falls back to worktree dirname -----------------------
DETACHEDREPO="$TMP/detached-repo"
mkdir -p "$DETACHEDREPO"
git_setup "$DETACHEDREPO"
git -C "$DETACHEDREPO" checkout -q --detach
devlog_resolve_paths "$DETACHEDREPO"
[ "$DEVLOG_FILE" = "$DETACHEDREPO/.devlog/devlog.detached-repo.md" ] \
  && echo "PASS: detached HEAD falls back to worktree dirname" \
  || { echo "FAIL: detached got $DEVLOG_FILE"; FAIL=1; }

# --- migration: existing devlog.md content moves to branch file ----------
MIGREPO="$TMP/migrepo"
mkdir -p "$MIGREPO/.devlog"
git_setup "$MIGREPO"
git -C "$MIGREPO" checkout -q -b feature-y
echo "## Round 1 existing content" > "$MIGREPO/.devlog/devlog.md"
devlog_resolve_paths "$MIGREPO"
if [ "$DEVLOG_FILE" = "$MIGREPO/.devlog/devlog.feature-y.md" ] \
  && [ -f "$DEVLOG_FILE" ] \
  && [ ! -f "$MIGREPO/.devlog/devlog.md" ] \
  && grep -q "existing content" "$DEVLOG_FILE"; then
  echo "PASS: migration renames devlog.md into branch file"
else
  echo "FAIL: migration file=$DEVLOG_FILE"
  FAIL=1
fi

# --- migration is idempotent: second call doesn't re-move or error -------
echo "## Round 2 written after migration" >> "$MIGREPO/.devlog/devlog.feature-y.md"
devlog_resolve_paths "$MIGREPO"
if [ "$DEVLOG_FILE" = "$MIGREPO/.devlog/devlog.feature-y.md" ] \
  && grep -q "Round 2 written after migration" "$DEVLOG_FILE"; then
  echo "PASS: second resolve is a no-op, content preserved"
else
  echo "FAIL: second resolve altered state, got $DEVLOG_FILE"
  FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash hooks/scripts/tests/test-devlog-path.sh`
Expected: FAIL immediately — `devlog-path.sh` doesn't exist yet, so sourcing it errors out (`No such file or directory`) and the script exits nonzero before printing any PASS/FAIL lines.

- [ ] **Step 3: Implement `devlog-path.sh`**

Create `hooks/scripts/devlog-path.sh`:

```bash
#!/usr/bin/env bash
# Sourced helper: resolves the branch-scoped devlog file for the branch
# currently checked out in a working directory. See
# docs/design/branch-scoped-devlog.md.

_DEVLOG_PATH_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=devlog-lock.sh
. "$_DEVLOG_PATH_DIR/devlog-lock.sh"

# Turns an arbitrary branch/worktree name into a safe devlog.<name>.md
# filename segment: anything outside [A-Za-z0-9._-] becomes '-', repeats
# collapse, leading/trailing '-' trimmed.
_devlog_sanitize_name() {
  printf '%s' "$1" | sed -E 's/[^A-Za-z0-9._-]/-/g; s/-+/-/g; s/^-+//; s/-+$//'
}

# Sets DEVLOG_DIR and DEVLOG_FILE for the branch currently checked out in
# $1 (defaults to "."). main/master (any case) and anything that isn't a
# git repo or has no resolvable branch keep the shared devlog.md. Any
# other branch gets devlog.<sanitized-branch>.md; a detached HEAD (or an
# unborn branch, which git also reports as "HEAD" here) falls back to the
# working directory's own basename. The first time a branch resolves to a
# file that doesn't exist yet while devlog.md already has content, the
# existing devlog.md is renamed (not copied) into that branch's file.
devlog_resolve_paths() {
  local dir="${1:-.}"
  DEVLOG_DIR="$dir/.devlog"
  DEVLOG_FILE="$DEVLOG_DIR/devlog.md"

  local branch name
  branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"

  case "$branch" in
    ''|[Mm][Aa][Ii][Nn]|[Mm][Aa][Ss][Tt][Ee][Rr])
      return 0
      ;;
    HEAD)
      name="$(basename "$(cd "$dir" 2>/dev/null && pwd)" 2>/dev/null || echo '')"
      ;;
    *)
      name="$branch"
      ;;
  esac

  name="$(_devlog_sanitize_name "$name")"
  [ -n "$name" ] || return 0

  local resolved="$DEVLOG_DIR/devlog.$name.md"
  if [ ! -f "$resolved" ] && [ -f "$DEVLOG_FILE" ]; then
    devlog_lock_acquire
    mv "$DEVLOG_FILE" "$resolved" 2>/dev/null || true
    devlog_lock_release
  fi
  DEVLOG_FILE="$resolved"
}
```

- [ ] **Step 4: Run the test again to verify it passes**

Run: `bash hooks/scripts/tests/test-devlog-path.sh`
Expected: every line printed is `PASS: ...`, ending with `All checks passed.`, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add hooks/scripts/devlog-path.sh hooks/scripts/tests/test-devlog-path.sh
git commit -m "feat: add devlog_resolve_paths for branch-scoped devlog files"
```

---

## Task 2: `round-start.sh`

**Files:**
- Modify: `hooks/scripts/round-start.sh:19-20,25-28`
- Test: `hooks/scripts/tests/test-round-start.sh` (existing, unmodified)

**Interfaces:**
- Consumes: `devlog_resolve_paths <dir>` from Task 1.

- [ ] **Step 1: Confirm the existing test currently passes (baseline)**

Run: `bash hooks/scripts/tests/test-round-start.sh`
Expected: `All checks passed.` (establishes the pre-change baseline; its fixture is a plain `mktemp -d` directory, not a git repo, so after this task it will still resolve to `devlog.md`).

- [ ] **Step 2: Edit the sourcing block and path assignment**

In `hooks/scripts/round-start.sh`, add the new source line to the existing block (currently lines 11–24):

```diff
 # shellcheck source=detect-pending-question.sh
 . "$HOOKS_DIR/detect-pending-question.sh"
+# shellcheck source=devlog-path.sh
+. "$HOOKS_DIR/devlog-path.sh"
 PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
-DEVLOG_DIR="$PROJECT_DIR/.devlog"
+devlog_resolve_paths "$PROJECT_DIR"
 ENABLED_FLAG="$DEVLOG_DIR/.enabled"
-DEVLOG_FILE="$DEVLOG_DIR/devlog.md"
 SPAN_FILE="$DEVLOG_DIR/.span-open"
```

- [ ] **Step 3: Run the existing test to verify no regression**

Run: `bash hooks/scripts/tests/test-round-start.sh`
Expected: `All checks passed.` (identical output to Step 1's baseline).

- [ ] **Step 4: Commit**

```bash
git add hooks/scripts/round-start.sh
git commit -m "refactor: round-start.sh uses devlog_resolve_paths"
```

---

## Task 3: `enforce-devlog.sh`

**Files:**
- Modify: `hooks/scripts/enforce-devlog.sh:59-61,90`
- Test: `hooks/scripts/tests/test-enforce-devlog.sh`, `test-enforce-devlog-files.sh`, `test-enforce-devlog-handoff-order.sh`, `test-enforce-devlog-workspace.sh` (existing, unmodified)

**Interfaces:**
- Consumes: `devlog_resolve_paths <dir>` from Task 1.

- [ ] **Step 1: Confirm existing tests currently pass (baseline)**

Run:
```bash
bash hooks/scripts/tests/test-enforce-devlog.sh
bash hooks/scripts/tests/test-enforce-devlog-files.sh
bash hooks/scripts/tests/test-enforce-devlog-handoff-order.sh
bash hooks/scripts/tests/test-enforce-devlog-workspace.sh
```
Expected: `All checks passed.` (or this suite's equivalent success line) for all four.

- [ ] **Step 2: Edit the two assignment sites**

Lines 59–61 currently:

```sh
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
DEVLOG_FILE="$DEVLOG_DIR/devlog.md"
```

become:

```sh
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"
devlog_resolve_paths "$PROJECT_DIR"
```

Line 90 (`DEVLOG_FILE="$DEVLOG_DIR/devlog.md"`, a redundant re-assignment a few lines later, right after `ENABLED_FLAG`/`TURN_MARKER`) is deleted outright — `DEVLOG_FILE` is already set by Step 2's call and nothing between the two sites changes the branch.

- [ ] **Step 3: Run the existing tests to verify no regression**

Run the same four commands as Step 1.
Expected: identical success output to the Step 1 baseline.

- [ ] **Step 4: Commit**

```bash
git add hooks/scripts/enforce-devlog.sh
git commit -m "refactor: enforce-devlog.sh uses devlog_resolve_paths"
```

---

## Task 4: `segment-watch.sh` (reorder + dynamic self-file check)

**Files:**
- Modify: `hooks/scripts/segment-watch.sh:7-18,65-71`
- Test: `hooks/scripts/tests/test-segment-watch.sh` (existing, unmodified)

**Interfaces:**
- Consumes: `devlog_resolve_paths <dir>` from Task 1.

- [ ] **Step 1: Confirm the existing test currently passes (baseline)**

Run: `bash hooks/scripts/tests/test-segment-watch.sh`
Expected: `All checks passed.`

- [ ] **Step 2: Reorder the header so `SCRIPT_DIR` exists before path resolution**

Lines 7–18 currently:

```sh
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
ENABLED_FLAG="$DEVLOG_DIR/.enabled"
DEVLOG_FILE="$DEVLOG_DIR/devlog.md"
SEGMENT_FILE="$DEVLOG_DIR/.segment-state"

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"
# shellcheck source=devlog-md.sh
. "$SCRIPT_DIR/devlog-md.sh"
```

become:

```sh
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"
# shellcheck source=devlog-md.sh
. "$SCRIPT_DIR/devlog-md.sh"
# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
devlog_resolve_paths "$PROJECT_DIR"
ENABLED_FLAG="$DEVLOG_DIR/.enabled"
SEGMENT_FILE="$DEVLOG_DIR/.segment-state"
```

- [ ] **Step 3: Make `is_devlog_tool_allowed`'s file-path check branch-aware**

Line 65–71 currently:

```sh
is_devlog_tool_allowed() {
  case "$1" in
    Write|Edit|StrReplace|Read|Grep)
      case "$2" in
        .devlog/devlog.md|*/.devlog/devlog.md) return 0 ;;
      esac
      ;;
    Bash)
      is_safe_readonly_git_command "$3" && return 0
      ;;
  esac
  return 1
}
```

becomes (matches whatever `DEVLOG_FILE` currently resolves to, not a hardcoded `devlog.md`):

```sh
is_devlog_tool_allowed() {
  local devlog_leaf="${DEVLOG_FILE##*/}"
  case "$1" in
    Write|Edit|StrReplace|Read|Grep)
      case "$2" in
        .devlog/"$devlog_leaf"|*/.devlog/"$devlog_leaf") return 0 ;;
      esac
      ;;
    Bash)
      is_safe_readonly_git_command "$3" && return 0
      ;;
  esac
  return 1
}
```

- [ ] **Step 4: Run the existing test to verify no regression**

Run: `bash hooks/scripts/tests/test-segment-watch.sh`
Expected: `All checks passed.`, identical to Step 1's baseline (its fixture directory is not a git repo, so `devlog_leaf` still resolves to `devlog.md`).

- [ ] **Step 5: Commit**

```bash
git add hooks/scripts/segment-watch.sh
git commit -m "refactor: segment-watch.sh uses devlog_resolve_paths"
```

---

## Task 5: `session-start-devlog.sh` (reorder)

**Files:**
- Modify: `hooks/scripts/session-start-devlog.sh:19-29`
- Test: `hooks/scripts/tests/test-session-start-devlog.sh` (existing, unmodified)

**Interfaces:**
- Consumes: `devlog_resolve_paths <dir>` from Task 1.

- [ ] **Step 1: Confirm the existing test currently passes (baseline)**

Run: `bash hooks/scripts/tests/test-session-start-devlog.sh`
Expected: `All checks passed.`

- [ ] **Step 2: Reorder the header**

Lines 19–29 currently:

```sh
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
DEVLOG_FILE="$DEVLOG_DIR/devlog.md"
SPAN_FILE="$DEVLOG_DIR/.span-open"

_src="${BASH_SOURCE[0]}"
HOOKS_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$HOOKS_DIR/json-field.sh"
# shellcheck source=detect-pending-question.sh
. "$HOOKS_DIR/detect-pending-question.sh"
```

become:

```sh
_src="${BASH_SOURCE[0]}"
HOOKS_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$HOOKS_DIR/json-field.sh"
# shellcheck source=detect-pending-question.sh
. "$HOOKS_DIR/detect-pending-question.sh"
# shellcheck source=devlog-path.sh
. "$HOOKS_DIR/devlog-path.sh"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
devlog_resolve_paths "$PROJECT_DIR"
SPAN_FILE="$DEVLOG_DIR/.span-open"
```

- [ ] **Step 3: Run the existing test to verify no regression**

Run: `bash hooks/scripts/tests/test-session-start-devlog.sh`
Expected: `All checks passed.`

- [ ] **Step 4: Commit**

```bash
git add hooks/scripts/session-start-devlog.sh
git commit -m "refactor: session-start-devlog.sh uses devlog_resolve_paths"
```

---

## Task 6: `close-open-round.sh` (reorder)

**Files:**
- Modify: `hooks/scripts/close-open-round.sh:16-31`
- Test: `hooks/scripts/tests/test-close-open-round.sh` (existing, unmodified)

**Interfaces:**
- Consumes: `devlog_resolve_paths <dir>` from Task 1.

- [ ] **Step 1: Confirm the existing test currently passes (baseline)**

Run: `bash hooks/scripts/tests/test-close-open-round.sh`
Expected: `All checks passed.`

- [ ] **Step 2: Reorder the header**

Lines 16–31 currently:

```sh
REASON="${1:-unknown}"
DETAIL="${2:-}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
ENABLED_FLAG="$DEVLOG_DIR/.enabled"
ROUND_OPEN="$DEVLOG_DIR/.round-open"
INTERRUPTED_FLAG="$DEVLOG_DIR/.interrupted"
DEVLOG_FILE="$DEVLOG_DIR/devlog.md"
TURN_MARKER="$DEVLOG_DIR/.turn-start"

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"
# shellcheck source=devlog-lock.sh
. "$SCRIPT_DIR/devlog-lock.sh"
```

become:

```sh
REASON="${1:-unknown}"
DETAIL="${2:-}"

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"
# shellcheck source=devlog-lock.sh
. "$SCRIPT_DIR/devlog-lock.sh"
# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
devlog_resolve_paths "$PROJECT_DIR"
ENABLED_FLAG="$DEVLOG_DIR/.enabled"
ROUND_OPEN="$DEVLOG_DIR/.round-open"
INTERRUPTED_FLAG="$DEVLOG_DIR/.interrupted"
TURN_MARKER="$DEVLOG_DIR/.turn-start"
```

- [ ] **Step 3: Run the existing test to verify no regression**

Run: `bash hooks/scripts/tests/test-close-open-round.sh`
Expected: `All checks passed.`

- [ ] **Step 4: Commit**

```bash
git add hooks/scripts/close-open-round.sh
git commit -m "refactor: close-open-round.sh uses devlog_resolve_paths"
```

---

## Task 7: `lessons-append.sh`

**Files:**
- Modify: `hooks/scripts/lessons-append.sh:9-29`
- Test: `hooks/scripts/tests/test-lessons-append.sh` (existing, unmodified)

**Interfaces:**
- Consumes: `devlog_resolve_paths <dir>` from Task 1.

- [ ] **Step 1: Confirm the existing test currently passes (baseline)**

Run: `bash hooks/scripts/tests/test-lessons-append.sh`
Expected: `All checks passed.`

- [ ] **Step 2: Edit the sourcing block and MAIN assignment**

Line 13 area (existing source block) gains one line, and lines 27–29 change:

```diff
 # shellcheck source=devlog-lock.sh
 . "$SCRIPT_DIR/devlog-lock.sh"
+# shellcheck source=devlog-path.sh
+. "$SCRIPT_DIR/devlog-path.sh"
 
 TOPIC=""
 TEXT=""
@@
 PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
-DEVLOG_DIR="$PROJECT_DIR/.devlog"
-MAIN="$DEVLOG_DIR/devlog.md"
+devlog_resolve_paths "$PROJECT_DIR"
+MAIN="$DEVLOG_FILE"
```

- [ ] **Step 3: Run the existing test to verify no regression**

Run: `bash hooks/scripts/tests/test-lessons-append.sh`
Expected: `All checks passed.`

- [ ] **Step 4: Commit**

```bash
git add hooks/scripts/lessons-append.sh
git commit -m "refactor: lessons-append.sh uses devlog_resolve_paths"
```

---

## Task 8: `lessons-read.sh`

**Files:**
- Modify: `hooks/scripts/lessons-read.sh:9-17`
- Test: `hooks/scripts/tests/test-lessons-read.sh` (existing, unmodified)

**Interfaces:**
- Consumes: `devlog_resolve_paths <dir>` from Task 1.

- [ ] **Step 1: Confirm the existing test currently passes (baseline)**

Run: `bash hooks/scripts/tests/test-lessons-read.sh`
Expected: `All checks passed.`

- [ ] **Step 2: Edit the sourcing block and MAIN assignment**

```diff
 # shellcheck source=devlog-md.sh
 . "$SCRIPT_DIR/devlog-md.sh"
+# shellcheck source=devlog-path.sh
+. "$SCRIPT_DIR/devlog-path.sh"
 
 PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
-DEVLOG_DIR="$PROJECT_DIR/.devlog"
-MAIN="$DEVLOG_DIR/devlog.md"
+devlog_resolve_paths "$PROJECT_DIR"
+MAIN="$DEVLOG_FILE"
```

- [ ] **Step 3: Run the existing test to verify no regression**

Run: `bash hooks/scripts/tests/test-lessons-read.sh`
Expected: `All checks passed.`

- [ ] **Step 4: Commit**

```bash
git add hooks/scripts/lessons-read.sh
git commit -m "refactor: lessons-read.sh uses devlog_resolve_paths"
```

---

## Task 9: `keep-move.sh`

**Files:**
- Modify: `hooks/scripts/keep-move.sh:6-8,32,35`
- Test: `hooks/scripts/tests/test-keep-move.sh` (existing, unmodified)

**Interfaces:**
- Consumes: `devlog_resolve_paths <dir>` from Task 1.

- [ ] **Step 1: Confirm the existing test currently passes (baseline)**

Run: `bash hooks/scripts/tests/test-keep-move.sh`
Expected: `All checks passed.`

- [ ] **Step 2: Edit the sourcing block and path assignments**

Lines 6–8 gain a source line:

```diff
 . "$SCRIPT_DIR/devlog-md.sh"
 . "$SCRIPT_DIR/json-field.sh"
 . "$SCRIPT_DIR/devlog-lock.sh"
+. "$SCRIPT_DIR/devlog-path.sh"
```

Line 32 (`DEVLOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.devlog"`) becomes:

```sh
devlog_resolve_paths "${CLAUDE_PROJECT_DIR:-.}"
```

(this line stays immediately before the existing `devlog_lock_acquire` / `trap` pair at what were lines 33–34 — leave those two lines as they are, they lock for this script's own subsequent read/rewrite of `MAIN`, separate from the internal lock `devlog_resolve_paths` already took and released for its own migration check)

Line 35 (`MAIN="$DEVLOG_DIR/devlog.md"`) becomes:

```sh
MAIN="$DEVLOG_FILE"
```

- [ ] **Step 3: Run the existing test to verify no regression**

Run: `bash hooks/scripts/tests/test-keep-move.sh`
Expected: `All checks passed.`

- [ ] **Step 4: Commit**

```bash
git add hooks/scripts/keep-move.sh
git commit -m "refactor: keep-move.sh uses devlog_resolve_paths"
```

---

## Task 10: `compact-devlog.sh`

**Files:**
- Modify: `hooks/scripts/compact-devlog.sh:6-7,9,12`
- Test: `hooks/scripts/tests/test-compact-devlog.sh` (existing, unmodified)

**Interfaces:**
- Consumes: `devlog_resolve_paths <dir>` from Task 1.

- [ ] **Step 1: Confirm the existing test currently passes (baseline)**

Run: `bash hooks/scripts/tests/test-compact-devlog.sh`
Expected: `All checks passed.`

- [ ] **Step 2: Edit the sourcing block and path assignments**

```diff
 . "$SCRIPT_DIR/devlog-md.sh"
 . "$SCRIPT_DIR/devlog-lock.sh"
+. "$SCRIPT_DIR/devlog-path.sh"
 
-DEVLOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.devlog"
+devlog_resolve_paths "${CLAUDE_PROJECT_DIR:-.}"
 devlog_lock_acquire
 trap 'devlog_lock_release' EXIT
-MAIN="$DEVLOG_DIR/devlog.md"
+MAIN="$DEVLOG_FILE"
 ARCHIVE="$DEVLOG_DIR/devlog.archive.md"
```

- [ ] **Step 3: Run the existing test to verify no regression**

Run: `bash hooks/scripts/tests/test-compact-devlog.sh`
Expected: `All checks passed.`

- [ ] **Step 4: Commit**

```bash
git add hooks/scripts/compact-devlog.sh
git commit -m "refactor: compact-devlog.sh uses devlog_resolve_paths"
```

---

## Task 11: `clean-devlog.sh`

**Files:**
- Modify: `hooks/scripts/clean-devlog.sh:6-8,15,18`
- Test: `hooks/scripts/tests/test-clean-devlog.sh` (existing, unmodified)

**Interfaces:**
- Consumes: `devlog_resolve_paths <dir>` from Task 1.

- [ ] **Step 1: Confirm the existing test currently passes (baseline)**

Run: `bash hooks/scripts/tests/test-clean-devlog.sh`
Expected: `All checks passed.`

- [ ] **Step 2: Edit the sourcing block and path assignments**

```diff
 . "$SCRIPT_DIR/devlog-md.sh"
 . "$SCRIPT_DIR/json-field.sh"
 . "$SCRIPT_DIR/devlog-lock.sh"
+. "$SCRIPT_DIR/devlog-path.sh"
@@
-DEVLOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.devlog"
+devlog_resolve_paths "${CLAUDE_PROJECT_DIR:-.}"
 devlog_lock_acquire
 trap 'devlog_lock_release' EXIT
-MAIN="$DEVLOG_DIR/devlog.md"
+MAIN="$DEVLOG_FILE"
 [ -f "$MAIN" ] || { echo "devlog.md 不存在" >&2; exit 1; }
```

Note: `NEW_MAIN="$TMP_DIR/devlog.md"` (line 35) stays as-is — it's a temp-file name inside a private `mktemp -d` directory, unrelated to which branch file is being rewritten.

- [ ] **Step 3: Run the existing test to verify no regression**

Run: `bash hooks/scripts/tests/test-clean-devlog.sh`
Expected: `All checks passed.`

- [ ] **Step 4: Commit**

```bash
git add hooks/scripts/clean-devlog.sh
git commit -m "refactor: clean-devlog.sh uses devlog_resolve_paths"
```

---

## Task 12: `status-devlog.sh`

**Files:**
- Modify: `hooks/scripts/status-devlog.sh:5-8,29-33`
- Test: `hooks/scripts/tests/test-status-span.sh` (existing, unmodified)

**Interfaces:**
- Consumes: `devlog_resolve_paths <dir>` from Task 1.

- [ ] **Step 1: Confirm the existing test currently passes (baseline)**

Run: `bash hooks/scripts/tests/test-status-span.sh`
Expected: `All checks passed.`

- [ ] **Step 2: Edit the sourcing block and path assignment**

```diff
 . "$SCRIPT_DIR/json-field.sh"
 . "$SCRIPT_DIR/devlog-md.sh"
+. "$SCRIPT_DIR/devlog-path.sh"
 
-DEVLOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.devlog"
+devlog_resolve_paths "${CLAUDE_PROJECT_DIR:-.}"
 [ -d "$DEVLOG_DIR" ] || { echo "NOT_STARTED"; exit 0; }
```

- [ ] **Step 3: Replace the four inline `devlog.md` references**

Lines 29–33 currently:

```sh
status="none"
if [ -f "$DEVLOG_DIR/devlog.md" ]; then
  last="$(devlog_list_round_starts "$DEVLOG_DIR/devlog.md" | awk 'END { print $1 }')"
  if [ -n "$last" ]; then
    end="$(devlog_block_end "$DEVLOG_DIR/devlog.md" "$last")"
    found="$(devlog_round_status "$DEVLOG_DIR/devlog.md" "$last" "$end")"
```

become:

```sh
status="none"
if [ -f "$DEVLOG_FILE" ]; then
  last="$(devlog_list_round_starts "$DEVLOG_FILE" | awk 'END { print $1 }')"
  if [ -n "$last" ]; then
    end="$(devlog_block_end "$DEVLOG_FILE" "$last")"
    found="$(devlog_round_status "$DEVLOG_FILE" "$last" "$end")"
```

- [ ] **Step 4: Run the existing test to verify no regression**

Run: `bash hooks/scripts/tests/test-status-span.sh`
Expected: `All checks passed.`

- [ ] **Step 5: Commit**

```bash
git add hooks/scripts/status-devlog.sh
git commit -m "refactor: status-devlog.sh uses devlog_resolve_paths"
```

---

## Task 13: `span-open.sh`

**Files:**
- Modify: `hooks/scripts/span-open.sh:5-8,13-14`
- Test: `hooks/scripts/tests/test-status-span.sh` (existing, unmodified — covers span-open.sh too)

**Interfaces:**
- Consumes: `devlog_resolve_paths <dir>` from Task 1.

- [ ] **Step 1: Confirm the existing test currently passes (baseline)**

Run: `bash hooks/scripts/tests/test-status-span.sh`
Expected: `All checks passed.`

- [ ] **Step 2: Edit the sourcing block, path assignment, and inline references**

```diff
 . "$SCRIPT_DIR/json-field.sh"
 . "$SCRIPT_DIR/devlog-md.sh"
+. "$SCRIPT_DIR/devlog-path.sh"
 
-DEVLOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.devlog"
+devlog_resolve_paths "${CLAUDE_PROJECT_DIR:-.}"
 [ -f "$DEVLOG_DIR/.enabled" ] || { echo "NOT_ENABLED" >&2; exit 1; }
 [ ! -e "$DEVLOG_DIR/.span-open" ] || { echo "ALREADY_OPEN" >&2; exit 1; }
 ROUND=""
 [ ! -f "$DEVLOG_DIR/.round-open" ] || ROUND="$(json_int_get "$DEVLOG_DIR/.round-open" round)"
-if [ -z "$ROUND" ] && [ -f "$DEVLOG_DIR/devlog.md" ]; then
-  ROUND="$(devlog_list_round_starts "$DEVLOG_DIR/devlog.md" | awk 'END { print $2 }')"
+if [ -z "$ROUND" ] && [ -f "$DEVLOG_FILE" ]; then
+  ROUND="$(devlog_list_round_starts "$DEVLOG_FILE" | awk 'END { print $2 }')"
 fi
```

- [ ] **Step 3: Run the existing test to verify no regression**

Run: `bash hooks/scripts/tests/test-status-span.sh`
Expected: `All checks passed.`

- [ ] **Step 4: Commit**

```bash
git add hooks/scripts/span-open.sh
git commit -m "refactor: span-open.sh uses devlog_resolve_paths"
```

---

## Task 14: `await-open.sh`

**Files:**
- Modify: `hooks/scripts/await-open.sh:5-10,15-16`
- Test: `hooks/scripts/tests/test-await-open.sh` (existing, unmodified)

**Interfaces:**
- Consumes: `devlog_resolve_paths <dir>` from Task 1.

- [ ] **Step 1: Confirm the existing test currently passes (baseline)**

Run: `bash hooks/scripts/tests/test-await-open.sh`
Expected: `All checks passed.`

- [ ] **Step 2: Edit the sourcing block, path assignment, and inline references**

```diff
 . "$SCRIPT_DIR/json-field.sh"
 . "$SCRIPT_DIR/devlog-md.sh"
+. "$SCRIPT_DIR/devlog-path.sh"
 
-DEVLOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.devlog"
+devlog_resolve_paths "${CLAUDE_PROJECT_DIR:-.}"
 [ -f "$DEVLOG_DIR/.enabled" ] || { echo "NOT_ENABLED"; exit 1; }
 [ ! -e "$DEVLOG_DIR/.awaiting-reply" ] || { echo "ALREADY_OPEN"; exit 1; }
 ROUND=""
 [ ! -f "$DEVLOG_DIR/.round-open" ] || ROUND="$(json_int_get "$DEVLOG_DIR/.round-open" round)"
-if [ -z "$ROUND" ] && [ -f "$DEVLOG_DIR/devlog.md" ]; then
-  ROUND="$(devlog_list_round_starts "$DEVLOG_DIR/devlog.md" | awk 'END { print $2 }')"
+if [ -z "$ROUND" ] && [ -f "$DEVLOG_FILE" ]; then
+  ROUND="$(devlog_list_round_starts "$DEVLOG_FILE" | awk 'END { print $2 }')"
 fi
```

- [ ] **Step 3: Run the existing test to verify no regression**

Run: `bash hooks/scripts/tests/test-await-open.sh`
Expected: `All checks passed.`

- [ ] **Step 4: Commit**

```bash
git add hooks/scripts/await-open.sh
git commit -m "refactor: await-open.sh uses devlog_resolve_paths"
```

---

## Task 15: Documentation

**Files:**
- Modify: `skills/devlog-tracker/SKILL.md` (「檔案位置」section)
- Modify: `README.md`

**Interfaces:** none (docs only).

- [ ] **Step 1: Update SKILL.md's "檔案位置" section**

Find this block in `skills/devlog-tracker/SKILL.md`:

```markdown
## 檔案位置

- 主檔：`.devlog/devlog.md`
- 歸檔：`.devlog/devlog.archive.md`
- 具名保存：`.devlog/devlog.<name>.md`（`/devlog-tracker:keep` 搬走的主題檔；SessionStart 不讀這些檔）

第一次使用時，若 `.devlog/` 不存在就建立它。
```

Replace with:

```markdown
## 檔案位置

- 主檔：`.devlog/devlog.md`——在 `main`／`master` 分支上工作時使用
- 分支主檔：`.devlog/devlog.<branch>.md`——在同一個 worktree 裡切換到其他分支時，主檔會依目前 checkout 的分支自動分開（斜線轉成 `-`）；detached HEAD 退回用 worktree 目錄名。另開一個 `git worktree`（不同目錄）本來就有自己獨立的 `.devlog/`，不受這個機制影響。第一次在某分支偵測到還沒有專屬檔案、且 `.devlog/devlog.md` 已有內容時，會把它改名（非複製）成該分支的檔案。細節見 `docs/design/branch-scoped-devlog.md`。
- 歸檔：`.devlog/devlog.archive.md`
- 具名保存：`.devlog/devlog.<name>.md`（`/devlog-tracker:keep` 搬走的主題檔；SessionStart 不讀這些檔）

第一次使用時，若 `.devlog/` 不存在就建立它。
```

- [ ] **Step 2: Update README.md**

`README.md`'s `## Hook 會自動做的事` section ends with a `#### Reply Fold` subsection (the last of five `####` items, right before `## 測試`). Its last lines currently read:

```markdown
#### Reply Fold

Claude 用純文字結尾提出問題、下一則訊息才拿到答案時，不用開新 Round——提問前先手動記一段問題原文再跑 `await-open.sh` 標記，下一則訊息（答案）就會自動折進同一個 Round 當一段 `### 段落`，不是拆成兩個不相關的 Round。連續多輪一問一答（例如 grilling）時，中途每題只記問題段落，不必每題重寫 Summary/Handoff/Status，等整場問答真正結束才收尾一次。跟 `AskUserQuestion` 工具無關（同一 turn 內問答，本來就不會產生第二個 Round）。背景 task-notification（子 agent 完成通知）也會自動走同一套折疊機制，不留原始 XML，只記精簡摘要。細節見 [`docs/design/reply-fold.md`](docs/design/reply-fold.md)。

## 測試
```

Insert a new subsection between them (this is not a fifth entry in the four-mechanism table above it — that table is specifically scoped to relaxing the one-round-per-message rule; this is a different axis, which *file* gets written):

```markdown
#### Reply Fold

Claude 用純文字結尾提出問題、下一則訊息才拿到答案時，不用開新 Round——提問前先手動記一段問題原文再跑 `await-open.sh` 標記，下一則訊息（答案）就會自動折進同一個 Round 當一段 `### 段落`，不是拆成兩個不相關的 Round。連續多輪一問一答（例如 grilling）時，中途每題只記問題段落，不必每題重寫 Summary/Handoff/Status，等整場問答真正結束才收尾一次。跟 `AskUserQuestion` 工具無關（同一 turn 內問答，本來就不會產生第二個 Round）。背景 task-notification（子 agent 完成通知）也會自動走同一套折疊機制，不留原始 XML，只記精簡摘要。細節見 [`docs/design/reply-fold.md`](docs/design/reply-fold.md)。

#### 分支各自的 devlog 檔

同一個工作目錄裡切換分支時，主檔會依目前 checkout 的分支自動分開：`main`／`master` 繼續用 `.devlog/devlog.md`，其他分支各自用 `.devlog/devlog.<branch>.md`（斜線轉成 `-`）。另開一個 `git worktree`（不同目錄）本來就有自己獨立的 `.devlog/`，不受這個機制影響。第一次在某分支偵測到還沒有專屬檔案、且 `devlog.md` 已有內容時，會把它改名（非複製）成該分支的檔案。細節見 [`docs/design/branch-scoped-devlog.md`](docs/design/branch-scoped-devlog.md)。

## 測試
```

- [ ] **Step 3: Commit**

```bash
git add skills/devlog-tracker/SKILL.md README.md
git commit -m "docs: document branch-scoped devlog files"
```

---

## Task 16: Full suite verification

**Files:** none (verification only).

- [ ] **Step 1: Run the complete hook self-check suite**

Run: `bash hooks/scripts/run-tests.sh`
Expected: every `=== test-*.sh ===` block ends in that file's own success line, and the script prints `All hook self-checks passed.` with exit code 0.

- [ ] **Step 2: If anything fails, fix forward**

Re-open the specific task above whose script the failure points to, fix it, re-run that script's test, then re-run the full suite from Step 1 again — do not skip straight to committing a fix without re-running the full suite.

- [ ] **Step 3: Manual smoke test of the actual behavior**

```bash
TMP="$(mktemp -d)"
cd "$TMP"
git init -q
git -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m init
git branch -M main
mkdir -p .devlog
: > .devlog/.enabled
export CLAUDE_PROJECT_DIR="$TMP"
git checkout -q -b fix-issue-123
echo '{"prompt":"hello"}' | bash /path/to/hooks/scripts/round-start.sh
ls .devlog/
```

Expected: `ls .devlog/` shows `devlog.fix-issue-123.md` (not `devlog.md`), and `cat .devlog/devlog.fix-issue-123.md` shows the new `## Round 1` skeleton with the `hello` prompt. Replace `/path/to` with this repo's actual absolute path. Clean up with `rm -rf "$TMP"` afterward.

- [ ] **Step 4: No commit for this task** (verification only — if Step 2 required fixes, those were already committed by their own task's flow).
