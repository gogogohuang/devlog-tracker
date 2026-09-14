#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0

REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m init
git -C "$REPO" branch -M main
mkdir -p "$REPO/.devlog"
: > "$REPO/.devlog/.enabled"
export CLAUDE_PROJECT_DIR="$REPO"

git -C "$REPO" checkout -q -b fix-issue-123

# --- round-start.sh opens a Round in the branch-scoped file --------------
OUT="$(echo '{"prompt":"hello"}' | bash "$SCRIPT_DIR/round-start.sh" 2>&1)"
BRANCH_FILE="$REPO/.devlog/devlog.fix-issue-123.md"
if [ -f "$BRANCH_FILE" ] && grep -q '^## Round 1' "$BRANCH_FILE" && [ ! -f "$REPO/.devlog/devlog.md" ]; then
  echo "PASS: round-start.sh opens Round 1 in devlog.fix-issue-123.md, not devlog.md"
else
  echo "FAIL: round-start.sh output=$OUT branch_file_exists=$([ -f "$BRANCH_FILE" ] && echo y || echo n)"
  FAIL=1
fi

# --- segment-watch.sh: Read of the CORRECT branch file is allowed --------
INPUT='{"tool_name":"Read","tool_input":{"file_path":".devlog/devlog.fix-issue-123.md"}}'
if echo "$INPUT" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1; then
  echo "PASS: segment-watch.sh allows Read of the branch-scoped file"
else
  echo "FAIL: segment-watch.sh denied Read of the correct branch-scoped file"
  FAIL=1
fi

# --- segment-watch.sh: its own deny message names the branch file, not devlog.md ---
# Force a stale segment-state so the silence-timeout path fires. The stored
# cksum must MATCH the branch file as it is right now: a mismatch means
# "the devlog just changed", which resets the timer and exits 0 instead of
# ever reaching the deny message we're trying to assert on.
SEEN_SUM="$(cksum < "$BRANCH_FILE" | tr -d '\n')"
cat > "$REPO/.devlog/.segment-state" <<JSON
{"last_change_epoch": 1, "last_seen_cksum": "$SEEN_SUM", "max_silent_seconds": 1}
JSON
DENY_INPUT='{"tool_name":"Bash","tool_input":{"command":"echo hi"}}'
DENY_MSG="$(echo "$DENY_INPUT" | bash "$SCRIPT_DIR/segment-watch.sh" 2>&1 1>/dev/null)"
DENY_RC=0
echo "$DENY_INPUT" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>/dev/null || DENY_RC=$?
if [ "$DENY_RC" -eq 2 ] && printf '%s' "$DENY_MSG" | grep -q 'devlog.fix-issue-123.md' \
  && ! printf '%s' "$DENY_MSG" | grep -qE '\.devlog/devlog\.md[^.]'; then
  echo "PASS: segment-watch.sh deny message names the branch-scoped file, not devlog.md"
else
  echo "FAIL: segment-watch.sh deny message rc=$DENY_RC msg=$DENY_MSG"
  FAIL=1
fi

# --- enforce-devlog.sh: Stop hook checks the branch-scoped file's hash ----
CKSUM_BEFORE="$(cksum < "$BRANCH_FILE")"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
ENFORCE_RC=$?
if [ "$ENFORCE_RC" -eq 2 ]; then
  echo "PASS: enforce-devlog.sh blocks when the branch-scoped file's Round has no Summary/Handoff yet"
else
  echo "FAIL: enforce-devlog.sh unexpected rc=$ENFORCE_RC (expected 2, unchanged branch file with only User Input)"
  FAIL=1
fi

# --- devlog_resolve_paths: reserved name and CJK fallback (Fix 2 / Fix 3) ---
. "$SCRIPT_DIR/devlog-path.sh"

ARCHREPO="$TMP/archrepo"
mkdir -p "$ARCHREPO"
git -C "$ARCHREPO" init -q
git -C "$ARCHREPO" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m init
git -C "$ARCHREPO" checkout -q -b archive
devlog_resolve_paths "$ARCHREPO"
if [ "$DEVLOG_FILE" = "$ARCHREPO/.devlog/devlog.md" ]; then
  echo "PASS: branch named 'archive' falls back to shared devlog.md, doesn't collide with devlog.archive.md"
else
  echo "FAIL: 'archive' branch got $DEVLOG_FILE"
  FAIL=1
fi

CJKREPO="$TMP/cjkrepo"
mkdir -p "$CJKREPO"
git -C "$CJKREPO" init -q
git -C "$CJKREPO" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m init
git -C "$CJKREPO" checkout -q -b 修復登入問題
devlog_resolve_paths "$CJKREPO"
case "$DEVLOG_FILE" in
  "$CJKREPO"/.devlog/devlog.b-*.md)
    echo "PASS: all-CJK branch name gets a stable hash-derived file, not shared devlog.md"
    ;;
  *)
    echo "FAIL: CJK branch got $DEVLOG_FILE"
    FAIL=1
    ;;
esac

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
