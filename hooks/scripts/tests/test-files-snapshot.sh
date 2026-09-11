#!/usr/bin/env bash
# Self-check for files-snapshot.sh's files_snapshot(), covering the
# uncommitted branch (git status), the committed branch (git diff-tree),
# rename-as-delete+add, and .devlog/ exclusion in both branches.
# No framework — plain assert-and-exit, matching this repo's existing style.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$SCRIPT_DIR/files-snapshot.sh"

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
OUT="$(files_snapshot "$NONGIT")"
assert_eq "non-git directory" "" "$OUT"

# --- repo setup -------------------------------------------------------------
REPO="$TMP_ROOT/repo"
mkdir -p "$REPO/.devlog"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name test
echo one > "$REPO/a.txt"
echo two > "$REPO/b.txt"
echo bookkeeping > "$REPO/.devlog/devlog.md"
git -C "$REPO" add a.txt b.txt .devlog/devlog.md
git -C "$REPO" commit -q -m init

# --- clean tree -> empty ------------------------------------------------------
OUT="$(files_snapshot "$REPO")"
assert_eq "clean tree" "" "$OUT"

# --- untracked file -> 新增 ----------------------------------------------------
echo new > "$REPO/c.txt"
OUT="$(files_snapshot "$REPO")"
assert_eq "untracked file" "新增：c.txt" "$OUT"
rm -f "$REPO/c.txt"

# --- modified tracked file -> 修改 ---------------------------------------------
echo changed >> "$REPO/a.txt"
OUT="$(files_snapshot "$REPO")"
assert_eq "modified tracked file" "修改：a.txt" "$OUT"
git -C "$REPO" checkout -q -- a.txt

# --- deleted tracked file -> 刪除 ----------------------------------------------
rm -f "$REPO/b.txt"
OUT="$(files_snapshot "$REPO")"
assert_eq "deleted tracked file" "刪除：b.txt" "$OUT"
git -C "$REPO" checkout -q -- b.txt

# --- mixed: new + modified + deleted, fixed category order --------------------
echo new > "$REPO/c.txt"
echo changed >> "$REPO/a.txt"
rm -f "$REPO/b.txt"
OUT="$(files_snapshot "$REPO")"
EXPECTED="新增：c.txt
修改：a.txt
刪除：b.txt"
assert_eq "mixed changes, fixed category order" "$EXPECTED" "$OUT"
rm -f "$REPO/c.txt"
git -C "$REPO" checkout -q -- a.txt b.txt

# --- .devlog/ excluded, real change still reported -----------------------------
echo bookkeeping change >> "$REPO/.devlog/devlog.md"
echo real change >> "$REPO/a.txt"
OUT="$(files_snapshot "$REPO")"
assert_eq ".devlog/ excluded (uncommitted branch)" "修改：a.txt" "$OUT"
git -C "$REPO" checkout -q -- a.txt .devlog/devlog.md

# --- rename shows as delete+add (no -M anywhere) --------------------------------
git -C "$REPO" mv a.txt a-renamed.txt
OUT="$(files_snapshot "$REPO")"
EXPECTED="新增：a-renamed.txt
刪除：a.txt"
assert_eq "rename -> delete+add" "$EXPECTED" "$OUT"
git -C "$REPO" reset -q --hard HEAD

# --- committed branch: add + modify + delete in one commit -----------------------
echo new-committed > "$REPO/d.txt"
echo changed-committed >> "$REPO/a.txt"
rm -f "$REPO/b.txt"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m "mixed commit"
HASH="$(git -C "$REPO" rev-parse --short HEAD)"
OUT="$(files_snapshot "$REPO" "$HASH")"
EXPECTED="新增：d.txt
修改：a.txt
刪除：b.txt"
assert_eq "committed branch, mixed" "$EXPECTED" "$OUT"

# --- committed branch: .devlog/ excluded there too --------------------------------
echo bookkeeping2 >> "$REPO/.devlog/devlog.md"
echo e > "$REPO/e.txt"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m "with devlog bookkeeping"
HASH2="$(git -C "$REPO" rev-parse --short HEAD)"
OUT="$(files_snapshot "$REPO" "$HASH2")"
assert_eq ".devlog/ excluded (committed branch)" "新增：e.txt" "$OUT"

# --- unresolvable hash -> empty (fail-open) ---------------------------------------
OUT="$(files_snapshot "$REPO" "0000000")"
assert_eq "unresolvable hash -> empty" "" "$OUT"

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
