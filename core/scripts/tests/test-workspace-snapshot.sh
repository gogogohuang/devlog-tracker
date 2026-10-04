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

# --- .devlog/ changes are ignored (same rule as files-snapshot.sh) ----------
# The devlog is rewritten every round, so counting it would make every
# snapshot dirty and every Handoff 工作區 drift on its own write.
DL="$TMP_ROOT/devlog-ignored"
mkdir -p "$DL"
git -C "$DL" init -q -b main
git -C "$DL" config user.email test@example.com
git -C "$DL" config user.name test
echo hello > "$DL/a.txt"
mkdir -p "$DL/.devlog"
echo tracked > "$DL/.devlog/devlog.md"
git -C "$DL" add a.txt .devlog/devlog.md
git -C "$DL" commit -q -m init
DL_HASH="$(git -C "$DL" rev-parse --short HEAD)"
echo more >> "$DL/.devlog/devlog.md"
echo round > "$DL/.devlog/.round-current.md"
OUT="$(workspace_snapshot "$DL")"
assert_eq ".devlog-only changes count as clean" "main @ ${DL_HASH}，工作樹乾淨" "$OUT"

echo change >> "$DL/a.txt"
OUT="$(workspace_snapshot "$DL")"
EXPECTED="main @ ${DL_HASH}
未提交：a.txt"
assert_eq ".devlog changes omitted from 未提交" "$EXPECTED" "$OUT"

DL_UNBORN="$TMP_ROOT/devlog-unborn"
mkdir -p "$DL_UNBORN/.devlog"
git -C "$DL_UNBORN" init -q -b main
echo x > "$DL_UNBORN/.devlog/devlog.md"
OUT="$(workspace_snapshot "$DL_UNBORN")"
assert_eq "unborn with untracked .devlog/ only is clean" "main @ (尚無 commit)，工作樹乾淨" "$OUT"

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

# --- branch label differs only (AC-1, AC-2, AC-6, AC-9) ----------------------
write_claim() {
  cat > "$2" <<EOF2
## Round 1 — 2026-09-11T00:00:00+08:00

### Handoff
#### 工作區
$1

### Status
IN_PROGRESS
EOF2
}
new_repo() {
  mkdir -p "$1"
  git -C "$1" init -q -b main
  git -C "$1" config user.email test@example.com
  git -C "$1" config user.name test
}

R1="$TMP_ROOT/label1"; new_repo "$R1"
echo x > "$R1/a.txt"; git -C "$R1" add a.txt; git -C "$R1" commit -q -m init
write_claim "$(workspace_snapshot "$R1")" "$TMP_ROOT/label1.md"
git -C "$R1" checkout -q -b other
assert_eq "AC-1: other branch, same hash, clean -> MATCH" "MATCH" "$(workspace_claim_state "$R1" "$TMP_ROOT/label1.md")"

R2="$TMP_ROOT/label2"; new_repo "$R2"
echo x > "$R2/a.txt"; git -C "$R2" add a.txt; git -C "$R2" commit -q -m init
echo 1 > "$R2/package-lock.json"
write_claim "$(workspace_snapshot "$R2")" "$TMP_ROOT/label2.md"
git -C "$R2" checkout -q -b other
assert_eq "AC-2: other branch, same uncommitted -> MATCH" "MATCH" "$(workspace_claim_state "$R2" "$TMP_ROOT/label2.md")"
echo y > "$R2/extra.txt"
assert_eq "AC-2: other branch, different uncommitted -> MISMATCH" "MISMATCH" "$(workspace_claim_state "$R2" "$TMP_ROOT/label2.md")"

R3="$TMP_ROOT/label3"; new_repo "$R3"
echo x > "$R3/a.txt"; git -C "$R3" add a.txt; git -C "$R3" commit -q -m init
write_claim "$(workspace_snapshot "$R3")" "$TMP_ROOT/label3.md"
git -C "$R3" checkout -q --detach
assert_eq "AC-6: detached vs named branch -> MISMATCH" "MISMATCH" "$(workspace_claim_state "$R3" "$TMP_ROOT/label3.md")"

R4="$TMP_ROOT/label4"; new_repo "$R4"
write_claim "$(workspace_snapshot "$R4")" "$TMP_ROOT/label4.md"
git -C "$R4" checkout -q -b other
assert_eq "AC-9: unborn other branch, clean -> MATCH" "MATCH" "$(workspace_claim_state "$R4" "$TMP_ROOT/label4.md")"

R5="$TMP_ROOT/label5"; new_repo "$R5"
echo x > "$R5/a.txt"; git -C "$R5" add a.txt; git -C "$R5" commit -q -m init
write_claim "$(workspace_snapshot "$R5")" "$TMP_ROOT/label5.md"
git -C "$R5" checkout -q -b other
echo y > "$R5/a.txt"; git -C "$R5" add a.txt; git -C "$R5" commit -q -m second
assert_eq "AC-3: other branch, different hash -> MISMATCH" "MISMATCH" "$(workspace_claim_state "$R5" "$TMP_ROOT/label5.md")"

R6="$TMP_ROOT/label6"; new_repo "$R6"
echo x > "$R6/a.txt"; git -C "$R6" add a.txt; git -C "$R6" commit -q -m init
echo one > "$R6/claimed.txt"
write_claim "$(workspace_snapshot "$R6")" "$TMP_ROOT/label6.md"
git -C "$R6" checkout -q -b other
rm "$R6/claimed.txt"
echo two > "$R6/live.txt"
assert_eq "AC-4: other branch, same hash, different uncommitted files -> MISMATCH" "MISMATCH" "$(workspace_claim_state "$R6" "$TMP_ROOT/label6.md")"

R7="$TMP_ROOT/label7"; new_repo "$R7"
echo x > "$R7/a.txt"; git -C "$R7" add a.txt; git -C "$R7" commit -q -m init
write_claim "$(workspace_snapshot "$R7")" "$TMP_ROOT/label7.md"
echo y > "$R7/a.txt"; git -C "$R7" add a.txt; git -C "$R7" commit -q -m second
assert_eq "AC-5: same branch, different hash -> MISMATCH" "MISMATCH" "$(workspace_claim_state "$R7" "$TMP_ROOT/label7.md")"

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
