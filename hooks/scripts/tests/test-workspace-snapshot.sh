#!/usr/bin/env bash
# Self-check for workspace-snapshot.sh's workspace_snapshot(), covering the
# seven canonical `#### 工作區` formats from skills/devlog-tracker/SKILL.md.
# No framework — plain assert-and-exit, matching this repo's existing style.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$SCRIPT_DIR/workspace-snapshot.sh"
. "$SCRIPT_DIR/devlog-md.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FAIL=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc"
    printf '  expected: %s\n' "$expected"
    printf '  actual:   %s\n' "$actual"
    FAIL=1
  fi
}

# --- non-git directory ----------------------------------------------------
NONGIT="$TMP_ROOT/nongit"
mkdir -p "$NONGIT"
OUT="$(workspace_snapshot "$NONGIT")"
assert_eq "non-git directory" "非 git 工作區" "$OUT"

# --- clean branch -----------------------------------------------------------
REPO="$TMP_ROOT/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name test
echo hello > "$REPO/a.txt"
git -C "$REPO" add a.txt
git -C "$REPO" commit -q -m init
HASH="$(git -C "$REPO" rev-parse --short HEAD)"
OUT="$(workspace_snapshot "$REPO")"
assert_eq "clean branch" "main @ ${HASH}，工作樹乾淨" "$OUT"

# --- dirty branch, two files -------------------------------------------------
echo change >> "$REPO/a.txt"
echo new > "$REPO/b.txt"
OUT="$(workspace_snapshot "$REPO")"
EXPECTED="main @ ${HASH}
未提交：a.txt, b.txt"
assert_eq "dirty branch, two files" "$EXPECTED" "$OUT"

# --- detached, clean ----------------------------------------------------------
git -C "$REPO" reset --hard -q "$HASH"
git -C "$REPO" clean -fdq
git -C "$REPO" checkout -q "$HASH" 2>/dev/null
OUT="$(workspace_snapshot "$REPO")"
assert_eq "detached, clean" "HEAD detached @ ${HASH}" "$OUT"

# --- detached, dirty -----------------------------------------------------------
echo dirty >> "$REPO/a.txt"
OUT="$(workspace_snapshot "$REPO")"
EXPECTED="HEAD detached @ ${HASH}
未提交：a.txt"
assert_eq "detached, dirty" "$EXPECTED" "$OUT"

# --- unborn branch (git init, zero commits), clean --------------------------
UNBORN="$TMP_ROOT/unborn"
mkdir -p "$UNBORN"
git -C "$UNBORN" init -q -b main
OUT="$(workspace_snapshot "$UNBORN")"
assert_eq "unborn branch, clean" "main @ (尚無 commit)，工作樹乾淨" "$OUT"

# --- unborn branch, dirty (untracked file, still no commits) ----------------
echo new > "$UNBORN/c.txt"
OUT="$(workspace_snapshot "$UNBORN")"
EXPECTED_UNBORN="main @ (尚無 commit)
未提交：c.txt"
assert_eq "unborn branch, dirty" "$EXPECTED_UNBORN" "$OUT"

CLI_UNBORN="$(bash "$SCRIPT_DIR/workspace-snapshot.sh" "$UNBORN")"
FUNC_UNBORN="$(workspace_snapshot "$UNBORN")"
assert_eq "cli matches function (unborn dirty)" "$FUNC_UNBORN" "$CLI_UNBORN"

# --- executable entry matches the sourced function --------------------------
CLI_NONGIT="$(bash "$SCRIPT_DIR/workspace-snapshot.sh" "$NONGIT")"
assert_eq "cli non-git directory" "非 git 工作區" "$CLI_NONGIT"

CLI_DETACHED="$(bash "$SCRIPT_DIR/workspace-snapshot.sh" "$REPO")"
FUNC_DETACHED="$(workspace_snapshot "$REPO")"
assert_eq "cli matches function (detached dirty)" "$FUNC_DETACHED" "$CLI_DETACHED"

DEFAULT_DIR="$TMP_ROOT/default-dir"
mkdir -p "$DEFAULT_DIR"
CLI_DEFAULT="$(CLAUDE_PROJECT_DIR="$DEFAULT_DIR" bash "$SCRIPT_DIR/workspace-snapshot.sh")"
assert_eq "cli default dir is CLAUDE_PROJECT_DIR" "非 git 工作區" "$CLI_DEFAULT"

# --- claim state vs live snapshot ------------------------------------------
LIVE_NOW="$(workspace_snapshot "$REPO")"
cat > "$TMP_ROOT/round.md" <<EOF
## Round 1 — 2026-09-11T00:00:00+08:00

### Handoff
#### 工作區
${LIVE_NOW}

### Status
IN_PROGRESS
EOF
assert_eq "claim MATCH on live snapshot" "MATCH" "$(workspace_claim_state "$REPO" "$TMP_ROOT/round.md")"
cat > "$TMP_ROOT/stale.md" <<'EOF'
## Round 1 — 2026-09-11T00:00:00+08:00

### Handoff
#### 工作區
main @ deadbeef，工作樹乾淨

### Status
IN_PROGRESS
EOF
assert_eq "claim MISMATCH on stale hash" "MISMATCH" "$(workspace_claim_state "$REPO" "$TMP_ROOT/stale.md")"

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
