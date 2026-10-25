#!/usr/bin/env bash
# .devlogignore applied end-to-end (design D3/D7): files_snapshot (both
# modes), workspace_snapshot, enforce-devlog.sh <workspace>/<files>, and
# round-start drift detection. Matcher table lives in test-devlog-ignore.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/xml-fixture.sh
. "$SCRIPT_DIR/tests/lib/xml-fixture.sh"
# shellcheck source=files-snapshot.sh
. "$SCRIPT_DIR/files-snapshot.sh"
# shellcheck source=workspace-snapshot.sh
. "$SCRIPT_DIR/workspace-snapshot.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FAIL=0
assert_eq() {
  if [ "$3" = "$2" ]; then echo "PASS: $1"
  else echo "FAIL: $1"; printf '  expected: %s\n  actual:   %s\n' "$2" "$3"; FAIL=1; fi
}

R="$TMP_ROOT/repo"
mkdir -p "$R/.devlog"
touch "$R/.devlog/.enabled"
git -C "$R" init -q -b main
git -C "$R" config user.email test@example.com
git -C "$R" config user.name test
echo '.devlog/' > "$R/.gitignore"
echo one > "$R/a.txt"
echo lock > "$R/yarn.lock"
git -C "$R" add -A
git -C "$R" commit -q -m init
HASH="$(git -C "$R" rev-parse --short HEAD)"

# --- baseline: no .devlogignore -> lockfile is reported (current behaviour) ---
echo more >> "$R/yarn.lock"
assert_eq "no ignore file: ws lists lockfile" "main @ ${HASH}
未提交：yarn.lock" "$(workspace_snapshot "$R")"
assert_eq "no ignore file: files lists lockfile" "修改：yarn.lock" "$(files_snapshot "$R")"

# --- with ignore file ---------------------------------------------------------
printf '*.lock\ngen/\n' > "$R/.devlogignore"
git -C "$R" add .devlogignore; git -C "$R" commit -q -m ign0
HASH="$(git -C "$R" rev-parse --short HEAD)"
assert_eq "ignored-only dirty -> ws clean format" "main @ ${HASH}，工作樹乾淨" "$(workspace_snapshot "$R")"
assert_eq "files: only ignored lockfile dirty -> empty" "" "$(files_snapshot "$R")"
mkdir "$R/gen"; echo x > "$R/gen/o.js"; echo two >> "$R/a.txt"
assert_eq "ws: ignored untracked dir dropped, others kept" "main @ ${HASH}
未提交：a.txt" "$(workspace_snapshot "$R")"
assert_eq "files: ignored dir dropped" "修改：a.txt" "$(files_snapshot "$R")"

# rename: new path decides
git -C "$R" checkout -q -- a.txt
git -C "$R" mv a.txt b.lock
assert_eq "ws: rename to ignored path dropped" "main @ ${HASH}，工作樹乾淨" "$(workspace_snapshot "$R")"
git -C "$R" mv b.lock a.txt

# commit mode
echo l2 >> "$R/yarn.lock"; git -C "$R" add yarn.lock; git -C "$R" commit -q -m lock
C1="$(git -C "$R" rev-parse --short HEAD)"
echo three >> "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -q -m both
assert_eq "commit mode: only-ignored commit is empty" "" "$(files_snapshot "$R" "$C1")"
assert_eq "commit mode: mixed commit keeps real file" "修改：a.txt" "$(files_snapshot "$R" HEAD)"

# fail-open: unreadable/garbage ignore file never errors
printf '\377\376[\n' > "$R/.devlogignore"
files_snapshot "$R" >/dev/null; assert_eq "garbage ignore: files rc 0" 0 $?
workspace_snapshot "$R" >/dev/null; assert_eq "garbage ignore: ws rc 0" 0 $?
printf '*.lock\ngen/\n' > "$R/.devlogignore"

HASH="$(git -C "$R" rev-parse --short HEAD)"
# --- enforce: ignored dirty lockfile must not block <workspace> --------------
export CLAUDE_PROJECT_DIR="$R"
D="$R/.devlog"
write_round() {
  # $1 = workspace body, $2 = optional <files> body (raw lines, after xml_fixture)
  {
    echo "## Round 1 — 2026-09-10T00:00:00+08:00"; echo
    echo "### Summary"; echo "fixture"; echo
    echo "### Reply"; echo "fixture reply."; echo
    echo "### Handoff"
    echo "#### 工作區"; printf '%s\n' "$1"
    echo "#### 現況"; echo "fixture"
    echo "#### 完成條件"; echo "observable done via test."
    echo "#### 下一步"; echo "edit hooks/scripts/enforce-devlog.sh"; echo
    echo "### Session Handoff"; echo
    echo "#### 決策"; echo "- （無）"; echo
    echo "#### 待解問題"; echo "- fixture open"; echo
    echo "#### 失敗嘗試"; echo "- （無）"; echo
    echo "### Status"; echo "IN_PROGRESS"
  } > "$D/.round-current.md"
  xml_fixture "$D/.round-current.md"
}
echo dirty >> "$R/yarn.lock"
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "main @ ${HASH}，工作樹乾淨"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_eq "enforce: ignored dirty lockfile -> clean <workspace> accepted" 0 $?

# without the ignore file the same claim is blocked (guards the test itself)
mv "$R/.devlogignore" "$TMP_ROOT/ign.bak"
bash "$SCRIPT_DIR/round-start.sh" < /dev/null >/dev/null
write_round "main @ ${HASH}，工作樹乾淨"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_eq "enforce: same claim blocked without ignore file" 2 $?
mv "$TMP_ROOT/ign.bak" "$R/.devlogignore"

# --- round-start drift: ignored dirty file is not drift ------------------------
rm -f "$D/.round-open" "$D/.round-current.md" "$D/.workspace-mismatch"
cat > "$D/devlog.md" <<EOT
## Round 1 — 2026-09-11T00:00:00+08:00

### Summary
s

### Reply
fixture reply.

### Handoff
#### 工作區
main @ ${HASH}，工作樹乾淨
#### 現況
going
#### 完成條件
done by test.
#### 下一步
do x

### Status
IN_PROGRESS
EOT
xml_fixture "$D/devlog.md"
OUT="$(printf '%s' '{"prompt":"keep going"}' | bash "$SCRIPT_DIR/round-start.sh" 2>/dev/null)"
case "$OUT" in *"宣稱："*) echo "FAIL: round-start reported drift for ignored lockfile"; FAIL=1 ;; *) echo "PASS: round-start: ignored dirty file is not drift" ;; esac
[ ! -f "$D/.workspace-mismatch" ] && echo "PASS: no .workspace-mismatch marker" || { echo "FAIL: marker written"; FAIL=1; }

# --- wholly-ignored untracked dir (git collapses it to "?? dir/") ---------------
# shellcheck source=session-baseline.sh
. "$SCRIPT_DIR/session-baseline.sh"
R="$TMP_ROOT/repo2"
mkdir -p "$R/.devlog"; touch "$R/.devlog/.enabled"
git -C "$R" init -q -b main
git -C "$R" config user.email test@example.com
git -C "$R" config user.name test
echo '.devlog/' > "$R/.gitignore"
printf '*.lock\nsrc/**/gen.ts\n' > "$R/.devlogignore"
echo one > "$R/a.txt"
git -C "$R" add -A; git -C "$R" commit -q -m init
HASH="$(git -C "$R" rev-parse --short HEAD)"
CLEAN="main @ ${HASH}，工作樹乾淨"
session_baseline_write "$R" sess-d
mkdir -p "$R/pkg" "$R/src/a"; echo 1 > "$R/pkg/yarn.lock"; echo 1 > "$R/src/a/gen.ts"
assert_eq "dir: ws drops wholly-ignored dirs" "$CLEAN" "$(workspace_snapshot "$R")"
assert_eq "dir: files drops wholly-ignored dirs" "" "$(files_snapshot "$R")"
assert_eq "dir: session_changes empty" "0:" "$(session_changes "$R" >"$TMP_ROOT/o" 2>&1; echo "$?:$(cat "$TMP_ROOT/o")")"
# nested collapse: src/ -> src/a/ -> src/a/b/gen.ts
mkdir -p "$R/src/a/b"; echo 1 > "$R/src/a/b/gen.ts"
assert_eq "dir: nested collapse dropped" "$CLEAN" "$(workspace_snapshot "$R")"
# enforce accepts a clean <workspace>; round-start shows no drift
export CLAUDE_PROJECT_DIR="$R"
D="$R/.devlog"
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "$CLEAN"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_eq "dir: enforce accepts clean <workspace>" 0 $?
rm -f "$D/.round-open" "$D/.round-current.md" "$D/.workspace-mismatch"
cat > "$D/devlog.md" <<EOT
## Round 1 — 2026-09-11T00:00:00+08:00

### Summary
s

### Reply
fixture reply.

### Handoff
#### 工作區
${CLEAN}
#### 現況
going
#### 完成條件
done by test.
#### 下一步
do x

### Status
IN_PROGRESS
EOT
xml_fixture "$D/devlog.md"
OUT="$(printf '%s' '{"prompt":"keep going"}' | bash "$SCRIPT_DIR/round-start.sh" 2>/dev/null)"
case "$OUT" in *"宣稱："*) echo "FAIL: round-start drift for ignored dirs"; FAIL=1 ;; *) echo "PASS: dir: round-start no drift" ;; esac
# mixed dir: one ignored + one kept child stays listed as dir/
mkdir "$R/mix"; echo 1 > "$R/mix/x.lock"; echo 1 > "$R/mix/keep.txt"
assert_eq "dir: mixed dir stays listed" "main @ ${HASH}
未提交：mix/" "$(workspace_snapshot "$R")"
assert_eq "dir: mixed dir in files" "新增：mix/" "$(files_snapshot "$R")"

exit $FAIL
