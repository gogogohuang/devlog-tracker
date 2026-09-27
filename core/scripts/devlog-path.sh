#!/usr/bin/env bash
# Sourced helper: resolves the branch-scoped devlog file for the branch
# currently checked out in a working directory. See
# docs/design/branch-scoped-devlog.md.

_DEVLOG_PATH_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=devlog-lock.sh
. "$_DEVLOG_PATH_DIR/devlog-lock.sh"
# shellcheck source=devlog-md.sh
. "$_DEVLOG_PATH_DIR/devlog-md.sh"
# shellcheck source=json-field.sh
. "$_DEVLOG_PATH_DIR/json-field.sh"

# Every platform that can own per-round state. Claude keeps the pre-0.x
# un-suffixed names; the others add "@<platform>" (docs/design/
# multi-platform-concurrency.md). "@" never survives _devlog_sanitize_name,
# so a branch named "codex" cannot collide with platform Codex.
DEVLOG_PLATFORMS="claude codex cursor"

devlog_platform() {
  case "${DEVLOG_PLATFORM:-}" in
    codex|cursor) printf '%s\n' "$DEVLOG_PLATFORM" ;;
    *) printf 'claude\n' ;;
  esac
}

# $1 stem (".round-current", "handoff.feat-x"), $2 extension (".md" or ""),
# $3 platform. Prints a basename.
devlog_platform_file() {
  if [ "$3" = claude ]; then printf '%s%s\n' "$1" "$2"
  else printf '%s@%s%s\n' "$1" "$3" "$2"; fi
}

_devlog_set_state_paths() {
  local p="$1" d="$DEVLOG_DIR"
  # shellcheck disable=SC2034 # consumed by callers
  ROUND_CURRENT="$d/$(devlog_platform_file .round-current .md "$p")"
  # shellcheck disable=SC2034 # consumed by callers
  ROUND_OPEN="$d/$(devlog_platform_file .round-open '' "$p")"
  # shellcheck disable=SC2034 # consumed by callers
  TURN_MARKER="$d/$(devlog_platform_file .turn-start '' "$p")"
  # shellcheck disable=SC2034 # consumed by callers
  SEGMENT_FILE="$d/$(devlog_platform_file .segment-state '' "$p")"
  # shellcheck disable=SC2034 # consumed by callers
  AWAITING_FILE="$d/$(devlog_platform_file .awaiting-reply '' "$p")"
  # shellcheck disable=SC2034 # consumed by callers
  INTERRUPTED_FLAG="$d/$(devlog_platform_file .interrupted '' "$p")"
  # shellcheck disable=SC2034 # consumed by callers
  SPAN_FILE="$d/$(devlog_platform_file .span-open '' "$p")"
  # shellcheck disable=SC2034 # consumed by callers
  MISMATCH_FILE="$d/$(devlog_platform_file .workspace-mismatch '' "$p")"
}

# First resolve after upgrade: before this change every platform wrote the
# un-suffixed names. The platform that resolves first most likely wrote
# them, so a non-Claude first resolver renames them to its own names.
# .segment-state is configuration (start-devlog.sh creates it), not round
# state, so it stays. Runs once; .platform-claimed stops it.
_devlog_claim_legacy_state() {
  local p="$1" d="$DEVLOG_DIR" name f stem
  [ -f "$d/.enabled" ] && [ ! -e "$d/.platform-claimed" ] || return 0
  devlog_lock_acquire
  if [ ! -e "$d/.platform-claimed" ]; then
    if [ "$p" != claude ]; then
      for name in .round-open .turn-start .awaiting-reply .interrupted .span-open .workspace-mismatch; do
        [ -e "$d/$name" ] && [ ! -e "$d/$name@$p" ] && mv "$d/$name" "$d/$name@$p" 2>/dev/null
      done
      [ -e "$d/.round-current.md" ] && [ ! -e "$d/.round-current@$p.md" ] \
        && mv "$d/.round-current.md" "$d/.round-current@$p.md" 2>/dev/null
      for f in "$d"/handoff.md "$d"/handoff.*.md; do
        [ -f "$f" ] || continue
        case "${f##*/}" in *@*) continue ;; esac
        stem="${f%.md}"
        [ -e "$stem@$p.md" ] || mv "$f" "$stem@$p.md" 2>/dev/null
      done
    fi
    : > "$d/.platform-claimed" 2>/dev/null || true
  fi
  devlog_lock_release
}

# One line per existing .round-open marker: platform, round, file field.
devlog_open_rounds() {
  local q f
  for q in $DEVLOG_PLATFORMS; do
    f="$DEVLOG_DIR/$(devlog_platform_file .round-open '' "$q")"
    [ -f "$f" ] || continue
    printf '%s\t%s\t%s\n' "$q" "$(json_int_get "$f" round)" "$(json_str_get "$f" file)"
  done
}

# One line per other platform's non-empty handoff for this branch.
devlog_other_handoffs() {
  local q f
  for q in $DEVLOG_PLATFORMS; do
    [ "$q" = "$DEVLOG_PLATFORM" ] && continue
    f="$HANDOFF_STEM.md"
    [ "$q" = claude ] || f="$HANDOFF_STEM@$q.md"
    [ -s "$f" ] && printf '%s\t%s\n' "$q" "$f"
  done
  return 0
}

# Turns an arbitrary branch/worktree name into a safe devlog.<name>.md
# filename segment: anything outside [A-Za-z0-9._-] becomes '-', repeats
# collapse, leading/trailing '-' trimmed.
_devlog_sanitize_name() {
  printf '%s' "$1" | sed -E 's/[^A-Za-z0-9._-]/-/g; s/-+/-/g; s/^-+//; s/-+$//'
}

# Cuts the unfinished tail of $2 (the shared devlog.md) into $3 (a branch
# file that doesn't exist yet): every "## Round" block after the last one
# whose Status is DONE. Nothing moves when the last round is DONE, when
# there are no rounds, or when HEAD doesn't contain the local main/master
# tip (an older branch being checked out, not one just forked from the
# work in progress). When $6 (an origin like "branch=feat/x") is given,
# the branch file starts with its origin marker. The project header,
# Checkpoints, and Kept/Lessons
# indexes always stay in $2. When rounds move, every platform's handoff
# under stem $4 moves to stem $5 too, since it snapshots that same
# unfinished work. Caller holds the
# devlog lock.
_devlog_migrate_unfinished_tail() {
  local dir="$1" src="$2" dst="$3" src_handoff="$4" dst_handoff="$5" origin="${6:-}"
  [ -s "$src" ] || return 0

  # Cheap early exit first: until the branch file exists, every hook
  # re-resolves, so the common "main ended DONE" case must not scan every
  # round each time.
  local start end status
  start="$(devlog_list_round_starts "$src" | awk 'END { print $1 }')"
  [ -n "$start" ] || return 0
  end="$(devlog_block_end "$src" "$start")"
  status="$(devlog_round_status "$src" "$start" "$end" | tr -d '[:space:]')"
  [ "$status" != DONE ] || return 0

  local base
  base="$(git -C "$dir" for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null \
    | grep -ixE 'main|master' | head -1)"
  [ -n "$base" ] || return 0
  git -C "$dir" merge-base --is-ancestor "$base" HEAD 2>/dev/null || return 0

  local ranges=""
  for start in $(devlog_list_round_starts "$src" | awk '{ print $1 }'); do
    end="$(devlog_block_end "$src" "$start")"
    status="$(devlog_round_status "$src" "$start" "$end" | tr -d '[:space:]')"
    if [ "$status" = DONE ]; then ranges=""; else ranges="$ranges $start:$end"; fi
  done
  [ -n "$ranges" ] || return 0

  # Split in one pass: lines inside a moved range go to $dst, the rest stay.
  # Trailing blank lines are dropped from both so later appends keep the
  # usual single-blank-line separator.
  local drop_trailing_blanks='
    /^[ \t]*$/ { pending = pending $0 ORS; next }
    { printf "%s", pending; pending = ""; print }
  '
  awk -v ranges="$ranges" '
    BEGIN {
      n = split(ranges, r, " ")
      for (i = 1; i <= n; i++) { split(r[i], se, ":"); s[i] = se[1]; e[i] = se[2] }
    }
    {
      moved = 0
      for (i = 1; i <= n; i++) if (NR >= s[i] && NR <= e[i]) { moved = 1; break }
      print moved ? "M" $0 : "K" $0
    }
  ' "$src" > "$src.split" 2>/dev/null || { rm -f "$src.split"; return 0; }
  {
    [ -z "$origin" ] || { devlog_origin_line "$origin"; printf '\n'; }
    sed -n 's/^M//p' "$src.split" | awk "$drop_trailing_blanks"
  } > "$dst.tmp" 2>/dev/null
  sed -n 's/^K//p' "$src.split" | awk "$drop_trailing_blanks" > "$src.tmp" 2>/dev/null
  rm -f "$src.split"

  # Branch file first: if the second mv fails the tail is duplicated, never lost.
  if mv "$dst.tmp" "$dst" 2>/dev/null && mv "$src.tmp" "$src" 2>/dev/null; then
    local q suffix
    for q in $DEVLOG_PLATFORMS; do
      suffix="$(devlog_platform_file '' .md "$q")"
      if [ -f "$src_handoff$suffix" ] && [ ! -f "$dst_handoff$suffix" ]; then
        mv "$src_handoff$suffix" "$dst_handoff$suffix" 2>/dev/null || true
      fi
    done
  fi
  rm -f "$dst.tmp" "$src.tmp" 2>/dev/null || true
}

# Sets DEVLOG_DIR, DEVLOG_FILE, and HANDOFF_FILE for the branch currently
# checked out in $1 (defaults to "."). main/master (any case) and anything
# that isn't a git repo or has no resolvable branch keep the shared
# devlog.md / handoff.md. Any other branch gets
# devlog.<sanitized-branch>.md and handoff.<sanitized-branch>.md; a
# detached HEAD (or an unborn branch, which git also reports as "HEAD"
# here) falls back to the working directory's own basename. The first
# time a branch resolves to a file that doesn't exist yet, only
# devlog.md's unfinished tail is cut into it (see
# _devlog_migrate_unfinished_tail); main's own history stays in devlog.md.
# Also sets DEVLOG_ORIGIN ("branch=<raw name>" / "detached=<dir>", empty
# for devlog.md): the first line written into a new branch file records it
# as an origin marker (docs/design/keep-all.md "Origin marker").
devlog_resolve_paths() {
  local dir="${1:-.}"
  DEVLOG_DIR="$dir/.devlog"
  DEVLOG_FILE="$DEVLOG_DIR/devlog.md"
  DEVLOG_PLATFORM="$(devlog_platform)"
  HANDOFF_STEM="$DEVLOG_DIR/handoff"
  DEVLOG_ORIGIN=""
  _devlog_set_state_paths "$DEVLOG_PLATFORM"
  _devlog_claim_legacy_state "$DEVLOG_PLATFORM"
  # shellcheck disable=SC2034 # consumed by callers (e.g. enforce-devlog.sh), not used in this file
  HANDOFF_FILE="$DEVLOG_DIR/$(devlog_platform_file handoff .md "$DEVLOG_PLATFORM")"

  local branch raw name origin
  branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"

  case "$branch" in
    ''|[Mm][Aa][Ii][Nn]|[Mm][Aa][Ss][Tt][Ee][Rr])
      return 0
      ;;
    HEAD)
      raw="$(basename "$(cd "$dir" 2>/dev/null && pwd)" 2>/dev/null || echo '')"
      origin="detached=$raw"
      ;;
    *)
      raw="$branch"
      origin="branch=$raw"
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
  local resolved_stem="$DEVLOG_DIR/handoff.$name"
  if [ -f "$DEVLOG_DIR/.enabled" ] && [ ! -f "$resolved" ] && [ -s "$DEVLOG_FILE" ]; then
    devlog_lock_acquire
    [ -f "$resolved" ] || _devlog_migrate_unfinished_tail \
      "$dir" "$DEVLOG_FILE" "$resolved" "$HANDOFF_STEM" "$resolved_stem" "$origin"
    devlog_lock_release
  fi
  DEVLOG_FILE="$resolved"
  HANDOFF_STEM="$resolved_stem"
  # shellcheck disable=SC2034 # consumed by callers (e.g. enforce-devlog.sh), not used in this file
  HANDOFF_FILE="$DEVLOG_DIR/$(devlog_platform_file "handoff.$name" .md "$DEVLOG_PLATFORM")"
  DEVLOG_ORIGIN="$origin"
}
