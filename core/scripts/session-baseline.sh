#!/usr/bin/env bash
# shellcheck shell=bash
# Sourced library (docs/design/devlog-ignore-session-baseline.md D4–D7).
# A session baseline records which paths were already dirty (and their content
# hash) when a session began, so "尚未 commit" <files> claims and the hint list
# can be narrowed to what THIS session changed. Never used for <workspace>.
#
# File: $DIR/.devlog/.session-baseline[@platform]
#   # devlog-session-baseline v1
#   session_id=<id or empty>
#   <hash><TAB><path>          (hash = git blob hash | MISSING | cksum for dir/)
#
# Usage:
#   session_baseline_write DIR [SESSION_ID]   atomic (re)build; rc 1 = not written
#   session_baseline_valid DIR                rc 0 = header ok and readable
#   session_baseline_id DIR                   prints stored session_id
#   session_baseline_set_id DIR ID            rewrite only the session_id line
#   session_baseline_ensure DIR ID            round-start lazy create/adopt/rebuild
#   session_baseline_on_session_start DIR SOURCE ID
#   session_changes DIR    files_snapshot-format 新增/修改/刪除 lines of paths
#                          dirty now AND (absent from baseline OR hash differs),
#                          ignore + .devlog/ filtered. rc 3 = no valid baseline
#                          (prints nothing; caller falls back); rc 1 = git/hash
#                          failure (same fallback).
#
# Fail-open (D7): every function returns non-zero instead of aborting; callers
# treat any non-zero as "no baseline" and never fail the hook because of it.

_SB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=devlog-path.sh
. "$_SB_DIR/devlog-path.sh"
# shellcheck source=devlog-ignore.sh
. "$_SB_DIR/devlog-ignore.sh"
# shellcheck source=files-snapshot.sh
declare -F _files_categorize >/dev/null || . "$_SB_DIR/files-snapshot.sh"

_SB_HEADER='# devlog-session-baseline v1'

session_baseline_file() {
  printf '%s/.devlog/%s\n' "$1" "$(devlog_platform_file .session-baseline '' "$(devlog_platform)")"
}

# stdin: paths relative to $1 (existing files or symlinks), one per line.
# stdout: one git blob hash per line, in input order. A symlink hashes its link
# text (readlink, no -f, no newline), like git's own blob; regular files are batched.
_sb_blob_hashes() {
  local dir="$1" paths path queue='' n_q=0 hashes h
  paths="$(cat)"
  [ -n "$paths" ] || return 0
  while IFS= read -r path; do
    [ -L "$dir/$path" ] && continue
    queue="${queue}${path}
"
    n_q=$((n_q + 1))
  done <<< "$paths"
  hashes=''
  if [ "$n_q" -gt 0 ]; then
    hashes="$(printf '%s' "$queue" | git -C "$dir" hash-object --stdin-paths 2>/dev/null)" || return 1
    [ "$(printf '%s\n' "$hashes" | grep -c .)" = "$n_q" ] || return 1
  fi
  # shellcheck disable=SC2086 # hashes are hex words, no spaces or globs
  set -- $hashes
  while IFS= read -r path; do
    if [ -L "$dir/$path" ]; then
      h="$(printf '%s' "$(readlink "$dir/$path")" | git -C "$dir" hash-object --stdin 2>/dev/null)" || return 1
      [ -n "$h" ] || return 1
    else
      h="${1:-}"; [ -n "$h" ] || return 1; shift
    fi
    printf '%s\n' "$h"
  done <<< "$paths"
}

# hash of an untracked directory entry: cksum of sorted "<relpath>\t<blob hash>"
# lines, so swapping or renaming children changes it.
_sb_dir_hash() {
  local dir="$1" rel="$2" list sums
  list="$(git -C "$dir" ls-files -o --exclude-standard -- "$rel" 2>/dev/null)" || return 1
  if [ -z "$list" ]; then printf 'EMPTY\n'; return 0; fi
  sums="$(printf '%s\n' "$list" | _sb_blob_hashes "$dir")" || return 1
  paste <(printf '%s\n' "$list") <(printf '%s\n' "$sums") | LC_ALL=C sort | cksum | awk '{print $1}'
}

# stdin: `git status --short` lines. stdout: "<hash>\t<XY>\t<path>" per line.
_sb_hash_lines() {
  local dir="$1" lines line code path queue='' hashes
  lines="$(cat)"
  [ -n "$lines" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    path="${line:3}"
    case "$path" in */) continue ;; esac
    if [ -L "$dir/$path" ] || { [ ! -d "$dir/$path" ] && [ -e "$dir/$path" ]; }; then
      queue="${queue}${path}
"
    fi
  done <<< "$lines"
  hashes=''
  if [ -n "$queue" ]; then
    hashes="$(printf '%s' "$queue" | _sb_blob_hashes "$dir")" || return 1
  fi
  # shellcheck disable=SC2086 # hashes are hex words, no spaces or globs
  set -- $hashes
  local h
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    code="${line:0:2}"
    path="${line:3}"
    case "$path" in
      */) h="$(_sb_dir_hash "$dir" "$path")" || return 1 ;;
      *)
        if [ -L "$dir/$path" ]; then h="${1:-}"; shift
        elif [ -d "$dir/$path" ]; then h=DIR
        elif [ -e "$dir/$path" ]; then h="${1:-}"; shift
        else h=MISSING
        fi
        ;;
    esac
    printf '%s\t%s\t%s\n' "$h" "$code" "$path"
  done <<< "$lines"
}

# Current dirty status lines: .devlog/ excluded; ignore applied only if $2=ignore.
_sb_status() {
  local dir="$1" raw
  raw="$(git -C "$dir" status --short --no-renames 2>/dev/null)" || return 1
  [ -n "$raw" ] || return 0
  printf '%s\n' "$raw" | grep -v '^.. \.devlog/'
  return 0
}

# Rebuild; on any failure the old baseline is removed (best-effort) so a stale
# one is never kept (D7). Callers only invoke this when a rebuild is required.
session_baseline_write() {
  _session_baseline_write "$@" && return 0
  rm -f "$(session_baseline_file "${1:-.}")" 2>/dev/null
  return 1
}

_session_baseline_write() {
  local dir="${1:-.}" id="${2:-}" file tmp status body
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  [ -d "$dir/.devlog" ] || return 1
  file="$(session_baseline_file "$dir")"
  status="$(_sb_status "$dir")" || return 1
  body=''
  if [ -n "$status" ]; then
    body="$(printf '%s\n' "$status" | _sb_hash_lines "$dir")" || return 1
    body="$(printf '%s\n' "$body" | awk -F'\t' '{print $1 "\t" $3}')"
  fi
  tmp="$file.tmp.$$"
  { printf '%s\nsession_id=%s\n' "$_SB_HEADER" "$id"; [ -z "$body" ] || printf '%s\n' "$body"; } > "$tmp" 2>/dev/null \
    || { rm -f "$tmp" 2>/dev/null; return 1; }
  mv -f "$tmp" "$file" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  return 0
}

session_baseline_valid() {
  local file
  file="$(session_baseline_file "${1:-.}")"
  [ -f "$file" ] && [ -r "$file" ] || return 1
  [ "$(head -n 1 "$file" 2>/dev/null)" = "$_SB_HEADER" ]
}

session_baseline_id() {
  local file
  file="$(session_baseline_file "${1:-.}")"
  sed -n '2s/^session_id=//p' "$file" 2>/dev/null
}

session_baseline_set_id() {
  local dir="${1:-.}" id="${2:-}" file tmp
  session_baseline_valid "$dir" || return 1
  file="$(session_baseline_file "$dir")"
  tmp="$file.tmp.$$"
  { printf '%s\nsession_id=%s\n' "$_SB_HEADER" "$id"; tail -n +3 "$file"; } > "$tmp" 2>/dev/null \
    || { rm -f "$tmp" 2>/dev/null; return 1; }
  mv -f "$tmp" "$file" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
}

# round-start (D6): lazy create / adopt empty id / rebuild on differing ids.
session_baseline_ensure() {
  local dir="${1:-.}" id="${2:-}" cur
  [ -f "$dir/.devlog/.enabled" ] || return 0
  if ! session_baseline_valid "$dir"; then
    session_baseline_write "$dir" "$id"
    return 0
  fi
  [ -n "$id" ] || return 0
  cur="$(session_baseline_id "$dir")"
  if [ -z "$cur" ]; then session_baseline_set_id "$dir" "$id"
  elif [ "$cur" != "$id" ]; then session_baseline_write "$dir" "$id"
  fi
  return 0
}

# SessionStart (D6 table)
session_baseline_on_session_start() {
  local dir="${1:-.}" source="${2:-}" id="${3:-}"
  [ -f "$dir/.devlog/.enabled" ] || return 0
  case "$source" in
    startup|clear) session_baseline_write "$dir" "$id" ;;
    fork)
      if session_baseline_valid "$dir"; then session_baseline_set_id "$dir" "$id"
      else session_baseline_write "$dir" "$id"; fi
      ;;
    *)
      session_baseline_valid "$dir" || session_baseline_write "$dir" "$id"
      ;;
  esac
  return 0
}

session_changes() {
  local dir="${1:-.}" file status cur changed
  session_baseline_valid "$dir" || return 3
  file="$(session_baseline_file "$dir")"
  status="$(_sb_status "$dir")" || return 1
  if [ -n "$status" ]; then
    status="$(printf '%s\n' "$status" | devlog_ignore_filter "$dir" status)"
  fi
  [ -n "$status" ] || return 0
  cur="$(printf '%s\n' "$status" | _sb_hash_lines "$dir")" || return 1
  changed="$(printf '%s\n' "$cur" | awk -F'\t' -v bf="$file" '
    BEGIN { n = 0
      while ((getline l < bf) > 0) {
        if (++n <= 2) continue
        i = index(l, "\t"); if (i > 0) base[substr(l, i + 1)] = substr(l, 1, i - 1)
      }
    }
    NF { p = $3; if (!(p in base) || base[p] != $1) print $2 " " p }
  ')" || return 1
  [ -n "$changed" ] || return 0
  printf '%s\n' "$changed" | _files_categorize status
  return 0
}
