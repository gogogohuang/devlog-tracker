#!/usr/bin/env bash
# Context for /devlog-tracker:pr (docs/design/read-side-and-promote.md A).
# Plain read only: git is only queried, and gh is only asked `auth status`
# and `pr view` -- creating/editing the PR is the command doc's job, after
# the user confirms.
set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=devlog-md.sh
. "$SCRIPT_DIR/devlog-md.sh"
# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"

PROJECT_DIR="$(cd "${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}" 2>/dev/null && pwd)" || { echo "NOT_A_REPO"; exit 0; }
git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1 || { echo "NOT_A_REPO"; exit 0; }

BRANCH="$(git -C "$PROJECT_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || echo '')"
case "$BRANCH" in
  '') echo "DETACHED_HEAD"; exit 0 ;;
  [Mm][Aa][Ii][Nn]|[Mm][Aa][Ss][Tt][Ee][Rr]) echo "ON_DEFAULT_BRANCH"; exit 0 ;;
esac

BASE=""
BASE_REF=""
ORIGIN_HEAD="$(git -C "$PROJECT_DIR" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo '')"
if [ -n "$ORIGIN_HEAD" ]; then
  BASE="${ORIGIN_HEAD#origin/}"
  BASE_REF="$ORIGIN_HEAD"
else
  for candidate in main master; do
    if git -C "$PROJECT_DIR" rev-parse --verify --quiet "refs/heads/$candidate" >/dev/null; then
      BASE="$candidate"
      BASE_REF="$candidate"
      break
    fi
  done
fi

echo "BRANCH=$BRANCH"
[ -n "$BASE" ] || { echo "NO_BASE"; exit 0; }
echo "BASE=$BASE"
echo "BASE_REF=$BASE_REF"

devlog_resolve_paths "$PROJECT_DIR"
echo "DEVLOG_FILE=$DEVLOG_FILE"
ROUNDS=""
if [ -f "$DEVLOG_FILE" ]; then
  ROUNDS="$(devlog_list_round_starts "$DEVLOG_FILE" | awk '{ printf "%s%s", (n++ ? " " : ""), $1 }')"
fi
if [ -n "$ROUNDS" ]; then echo "ROUNDS=$ROUNDS"; else echo "NO_BRANCH_DEVLOG"; fi

COMMITS="$(git -C "$PROJECT_DIR" rev-list --count "$BASE_REF..HEAD" 2>/dev/null || echo 0)"
echo "COMMITS=$COMMITS"

GH=no
PR=none
if command -v gh >/dev/null 2>&1 && (cd "$PROJECT_DIR" && gh auth status >/dev/null 2>&1); then
  GH=yes
  n="$(cd "$PROJECT_DIR" && gh pr view --json number -q .number 2>/dev/null || echo '')"
  case "$n" in ''|*[!0-9]*) ;; *) PR="$n" ;; esac
fi
echo "GH=$GH"
echo "PR=$PR"
