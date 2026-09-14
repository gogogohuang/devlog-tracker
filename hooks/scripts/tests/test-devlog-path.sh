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
