#!/usr/bin/env bash
# shellcheck shell=bash
# Sourced by enforce-devlog.sh (docs/design/files-verify.md, devlog ssot
# Phase 4). Computes the canonical #### 檔案 category lines — 新增/修改/刪除,
# comma-joined per category, omitting empty ones — for either the current
# uncommitted tree state or a single commit, so enforce-devlog.sh can
# compare Claude's claim against something computed independently.
#
# Usage:
#   files_snapshot "$PROJECT_DIR"          # uncommitted branch (git status)
#   files_snapshot "$PROJECT_DIR" "$HASH"  # committed branch (git diff-tree)
#
# Echoes up to three lines in fixed order (新增, then 修改, then 刪除).
# Echoes nothing if there's nothing to report outside .devlog/, or if $dir
# isn't a git repo, or (committed branch) $HASH doesn't resolve to a commit
# — all fail-open, matching this hook suite's design.
#
# Renames are never detected: no -M/--find-renames anywhere below (per
# docs/design/files-verify.md Decision 5), so git reports a rename as a
# plain delete+add pair, which is exactly the desired 刪除+新增 split.
# A status code this function doesn't specifically recognize (e.g. a copy,
# git status's `C`) is categorized conservatively as 修改 — see
# docs/design/files-verify.md's Known Limitations.
#
# Known limitation: a changed path containing a space is not exactly
# reversible from the comma-joined output below — same limitation
# workspace-snapshot.sh's 未提交 list already has.
files_snapshot() {
  local dir="${1:-.}" hash="${2:-}"
  if ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi

  local raw
  if [ -n "$hash" ]; then
    git -C "$dir" rev-parse --verify -q "${hash}^{commit}" >/dev/null 2>&1 || return 0
    raw="$(git -C "$dir" diff-tree --no-commit-id --name-status -r --root "$hash" 2>/dev/null || true)"
  else
    raw="$(git -C "$dir" status --short --no-renames 2>/dev/null || true)"
  fi
  [ -n "$raw" ] || return 0

  local added='' modified='' deleted='' line code path
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ -n "$hash" ]; then
      # diff-tree --name-status: "<code>\t<path>" (single-letter code)
      code="${line%%$'\t'*}"
      path="${line#*$'\t'}"
    else
      # git status --short: "<XY> <path>" (XY is always exactly 2 chars)
      code="${line:0:2}"
      path="${line:3}"
    fi
    case "$path" in
      .devlog/*) continue ;;
    esac
    case "$code" in
      '??') added="${added:+$added, }$path" ;;
      *A*) added="${added:+$added, }$path" ;;
      *D*) deleted="${deleted:+$deleted, }$path" ;;
      *) modified="${modified:+$modified, }$path" ;;
    esac
  done <<< "$raw"

  [ -n "$added" ] && printf '新增：%s\n' "$added"
  [ -n "$modified" ] && printf '修改：%s\n' "$modified"
  [ -n "$deleted" ] && printf '刪除：%s\n' "$deleted"
  return 0
}
