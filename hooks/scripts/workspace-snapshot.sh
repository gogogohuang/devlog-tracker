#!/usr/bin/env bash
# shellcheck shell=bash
# Sourced by enforce-devlog.sh (docs/design/devlog-as-ssot-assessment.md,
# Phase 1). Computes the canonical `#### 工作區` text using the exact
# commands and five output formats defined in skills/devlog-tracker/SKILL.md
# (`#### 工作區`) and mirrored in docs/design/continue.md step 5.1 — fix the
# formats there if they ever change, this function is the only place that
# produces them at write time.
#
# Usage: workspace_snapshot "$PROJECT_DIR"
# Echoes 1 line (clean / non-git / detached-clean) or 2 lines (dirty /
# detached-dirty). Never fails: any git command error degrades toward
# "非 git 工作區", matching this hook suite's fail-open design.
#
# Known limitation: a dirty file path containing a space is not exactly
# reversible from `git status --short`'s last-field extraction below — same
# limitation the hand-written 工作區 convention already has.
workspace_snapshot() {
  local dir="${1:-.}"
  if ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '非 git 工作區\n'
    return 0
  fi
  local branch hash label status_out dirty_files
  branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
  hash="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo '')"
  [ -n "$hash" ] || { printf '非 git 工作區\n'; return 0; }
  if [ "$branch" = "HEAD" ] || [ -z "$branch" ]; then
    label="HEAD detached"
  else
    label="$branch"
  fi
  status_out="$(git -C "$dir" status --short 2>/dev/null || echo '')"
  if [ -z "$status_out" ]; then
    if [ "$label" = "HEAD detached" ]; then
      printf '%s @ %s\n' "$label" "$hash"
    else
      printf '%s @ %s，工作樹乾淨\n' "$label" "$hash"
    fi
  else
    dirty_files="$(printf '%s\n' "$status_out" | awk '{printf "%s%s", (NR>1?", ":""), $NF}')"
    printf '%s @ %s\n未提交：%s\n' "$label" "$hash" "$dirty_files"
  fi
}
