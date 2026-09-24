#!/usr/bin/env bash
# Self-check for pr-context.sh (docs/design/read-side-and-promote.md A).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
FAIL=0
assert_line() {
  local desc="$1" expected="$2" out="$3"
  if printf '%s\n' "$out" | grep -qxF "$expected"; then echo "PASS: $desc"
  else echo "FAIL: $desc (missing [$expected] in: $out)"; FAIL=1; fi
}
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then echo "PASS: $desc"
  else echo "FAIL: $desc (expected [$expected] got [$actual])"; FAIL=1; fi
}

# gh stubs: one that is not logged in, one that is and has PR #42.
GH_OFF="$TMP_ROOT/gh-off"; GH_ON="$TMP_ROOT/gh-on"
mkdir -p "$GH_OFF" "$GH_ON"
printf '#!/usr/bin/env bash\nexit 1\n' > "$GH_OFF/gh"
cat > "$GH_ON/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "auth status") exit 0 ;;
  "pr view") echo 42 ;;
  *) echo "unexpected gh call: $*" >&2; exit 9 ;;
esac
EOF
chmod +x "$GH_OFF/gh" "$GH_ON/gh"
ctx() { PATH="$1:$PATH" CLAUDE_PROJECT_DIR="$2" bash "$SCRIPT_DIR/pr-context.sh"; }

# --- Not a git repo -------------------------------------------------------------
PLAIN="$TMP_ROOT/plain"; mkdir -p "$PLAIN"
assert_eq "not a repo" "NOT_A_REPO" "$(ctx "$GH_OFF" "$PLAIN")"

# --- Repo fixture ------------------------------------------------------------------
REPO="$TMP_ROOT/repo"; mkdir -p "$REPO"
gitc() { git -C "$REPO" -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false "$@"; }
gitc init -q -b main
echo a > "$REPO/a.txt"; gitc add a.txt; gitc commit -qm init

assert_eq "on main" "ON_DEFAULT_BRANCH" "$(ctx "$GH_OFF" "$REPO")"
gitc checkout -q -b MASTER
assert_eq "on MASTER (case-insensitive)" "ON_DEFAULT_BRANCH" "$(ctx "$GH_OFF" "$REPO")"
gitc checkout -q main
gitc checkout -q --detach
assert_eq "detached" "DETACHED_HEAD" "$(ctx "$GH_OFF" "$REPO")"
gitc checkout -q main

# --- Feature branch, no devlog, gh logged out --------------------------------------
gitc checkout -q -b feat/x
echo b > "$REPO/b.txt"; gitc add b.txt; gitc commit -qm "feat: b"
OUT="$(ctx "$GH_OFF" "$REPO")"
assert_line "branch" "BRANCH=feat/x" "$OUT"
assert_line "base from local main" "BASE=main" "$OUT"
assert_line "base ref" "BASE_REF=main" "$OUT"
assert_line "devlog file is branch-scoped + absolute" "DEVLOG_FILE=$(cd "$REPO" && pwd)/.devlog/devlog.feat-x.md" "$OUT"
assert_line "no branch devlog" "NO_BRANCH_DEVLOG" "$OUT"
assert_line "commit count" "COMMITS=1" "$OUT"
assert_line "gh logged out" "GH=no" "$OUT"
assert_line "no pr" "PR=none" "$OUT"

# --- Branch devlog with rounds + gh logged in -------------------------------------
mkdir -p "$REPO/.devlog"
cat > "$REPO/.devlog/devlog.feat-x.md" <<'EOF'
## Round 1 — 2026-09-01T10:00:00+0800

### Summary
one

### Status
DONE

## Round 2 — 2026-09-02T10:00:00+0800

### Summary
two

### Status
DONE
EOF
OUT="$(ctx "$GH_ON" "$REPO")"
assert_line "round start lines" "ROUNDS=1 9" "$OUT"
assert_line "gh logged in" "GH=yes" "$OUT"
assert_line "existing pr number" "PR=42" "$OUT"

# --- origin/HEAD wins over local main ---------------------------------------------
gitc update-ref refs/remotes/origin/main main
gitc symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
OUT="$(ctx "$GH_OFF" "$REPO")"
assert_line "base from origin/HEAD" "BASE=main" "$OUT"
assert_line "base ref is remote" "BASE_REF=origin/main" "$OUT"

# --- No main/master and no origin/HEAD -> NO_BASE ------------------------------
REPO2="$TMP_ROOT/repo2"; mkdir -p "$REPO2"
git -C "$REPO2" -c user.email=t@example.com -c user.name=t init -q -b trunk
echo a > "$REPO2/a.txt"; git -C "$REPO2" add a.txt
git -C "$REPO2" -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false commit -qm init
git -C "$REPO2" checkout -q -b dev
OUT="$(ctx "$GH_OFF" "$REPO2")"
assert_line "no base: branch still printed" "BRANCH=dev" "$OUT"
assert_line "no base" "NO_BASE" "$OUT"

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
