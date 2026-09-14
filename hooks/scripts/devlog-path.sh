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

  local branch raw name
  branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"

  case "$branch" in
    ''|[Mm][Aa][Ii][Nn]|[Mm][Aa][Ss][Tt][Ee][Rr])
      return 0
      ;;
    HEAD)
      raw="$(basename "$(cd "$dir" 2>/dev/null && pwd)" 2>/dev/null || echo '')"
      ;;
    *)
      raw="$branch"
      ;;
  esac
  [ -n "$raw" ] || return 0

  name="$(_devlog_sanitize_name "$raw")"
  if [ -z "$name" ]; then
    # Sanitizing stripped every character (e.g. an all-CJK branch name).
    # Falling back to the shared devlog.md here would silently defeat this
    # whole feature for exactly the case it's most likely to hit in a
    # Chinese-language project. Derive a short, stable, ASCII-safe name
    # from the original string instead.
    name="b-$(printf '%s' "$raw" | cksum | awk '{print $1}')"
  fi

  # Reserved namespace: devlog.archive.md and devlog.lessons.*.md already
  # mean something else in this plugin. A branch name that sanitizes to
  # one of these shares the plain devlog.md instead of colliding with them.
  case "$name" in
    archive|lessons.*) return 0 ;;
  esac

  local resolved="$DEVLOG_DIR/devlog.$name.md"
  if [ -f "$DEVLOG_DIR/.enabled" ] && [ ! -f "$resolved" ] && [ -f "$DEVLOG_FILE" ]; then
    devlog_lock_acquire
    mv "$DEVLOG_FILE" "$resolved" 2>/dev/null || true
    devlog_lock_release
  fi
  DEVLOG_FILE="$resolved"
}
