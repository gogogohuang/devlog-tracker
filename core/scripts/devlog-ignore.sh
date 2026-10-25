#!/usr/bin/env bash
# shellcheck shell=bash
# Sourced by files-snapshot.sh and workspace-snapshot.sh
# (docs/design/devlog-ignore-session-baseline.md D1–D3, D7).
# User ignore file: $PROJECT_DIR/.devlogignore, a gitignore subset matched by
# our own awk matcher (NOT `git check-ignore`, which mixes in .gitignore).
#
# Usage:
#   devlog_ignore_filter DIR [plain|status|tab]
#       stdin lines -> stdout lines whose path is not ignored.
#       plain  (default): the whole line is the path
#       status: `git status --short` lines "<XY> <path>" (rename: new path)
#       tab:    `git diff-tree --name-status` lines "<code>\t<path>"
#       A path ending in "/" (untracked dir entry) is treated as a directory.
#   devlog_ignored DIR PATH     rc 0 = ignored, rc 1 = kept
#
# Fail-open: no/unreadable ignore file or any awk failure passes input through
# unchanged and never returns non-zero from the filter.

# status mode: git collapses an untracked dir to "?? dir/" even when every file
# inside is ignored by .devlogignore. Expand such entries and drop the ones whose
# children are all ignored; keep the line unchanged otherwise or on any failure.
_devlog_ignore_drop_dirs() {
  local dir="$1" text="$2" line path kids rest
  while IFS= read -r line; do
    case "$line" in
      "?? "*/)
        path="${line#\?\? }"
        case "$path" in
          \"*) printf '%s\n' "$line"; continue ;;
        esac
        if kids="$(git -C "$dir" ls-files -o --exclude-standard -- "$path" 2>/dev/null)" && [ -n "$kids" ]; then
          rest="$(printf '%s\n' "$kids" | devlog_ignore_filter "$dir")"
          [ -z "$rest" ] && continue
        fi
        ;;
    esac
    printf '%s\n' "$line"
  done <<EOF
$text
EOF
}

devlog_ignore_filter() {
  local dir="${1:-.}" mode="${2:-plain}" file input out
  file="$dir/.devlogignore"
  if [ ! -f "$file" ] || [ ! -r "$file" ]; then
    cat
    return 0
  fi
  input="$(cat; printf x)"
  input="${input%x}"
  if out="$(printf '%s' "$input" | awk -v pf="$file" -v mode="$mode" '
    function esc(c) { return (index(".+(){}|^$[]\\", c) > 0) ? "\\" c : c }
    function toregex(g,   i, n, c, r, rest) {
      r = ""; n = length(g); i = 1
      while (i <= n) {
        c = substr(g, i, 1)
        if (c == "*" && substr(g, i, 2) == "**") {
          if ((i == 1 || substr(g, i - 1, 1) == "/") && substr(g, i + 2, 1) == "/") {
            r = r "(.*/)?"; i += 3; continue
          }
          if (i > 1 && substr(g, i - 1, 1) == "/" && i + 1 == n) {
            r = r ".*"; i += 2; continue
          }
          r = r "[^/]*"; i += 2; continue
        }
        if (c == "*") r = r "[^/]*"
        else if (c == "?") r = r "[^/]"
        else r = r esc(c)
        i++
      }
      return r
    }
    BEGIN {
      np = 0
      while ((getline line < pf) > 0) {
        sub(/\r$/, "", line); sub(/[ \t]+$/, "", line)
        if (line == "" || substr(line, 1, 1) == "#") continue
        neg = 0
        if (substr(line, 1, 1) == "!") { neg = 1; line = substr(line, 2) }
        dironly = 0
        if (line ~ /\/$/) { dironly = 1; sub(/\/+$/, "", line) }
        anch = 0
        if (index(line, "/") > 0) { anch = 1; sub(/^\/+/, "", line) }
        if (line == "") continue
        np++
        P_re[np] = "^" toregex(line) "$"
        P_neg[np] = neg; P_dir[np] = dironly; P_anch[np] = anch
      }
      close(pf)
    }
    function ignored(path,   isdir, n, k, parts, prefix, i, comp, res, d) {
      isdir = 0
      if (path ~ /\/$/) { isdir = 1; sub(/\/+$/, "", path) }
      n = split(path, parts, "/")
      res = 0
      for (i = 1; i <= np; i++) {
        prefix = ""
        for (k = 1; k <= n; k++) {
          prefix = (k == 1 ? "" : prefix "/") parts[k]
          d = (k < n || isdir)
          if (P_dir[i] && !d) continue
          comp = P_anch[i] ? prefix : parts[k]
          if (comp ~ P_re[i]) { res = !P_neg[i]; break }
        }
      }
      return res
    }
    {
      line = $0; path = line
      if (mode == "status") {
        path = substr(line, 4)
        if ((k = index(path, " -> ")) > 0) path = substr(path, k + 4)
      } else if (mode == "tab") {
        k = index(line, "\t"); if (k > 0) path = substr(line, k + 1)
      }
      if (np == 0 || path == "" || !ignored(path)) print line
    }
  ' 2>/dev/null)"; then
    if [ -n "$out" ] && [ "$mode" = status ]; then
      out="$(_devlog_ignore_drop_dirs "$dir" "$out")"
    fi
    [ -z "$out" ] || printf '%s\n' "$out"
  else
    printf '%s' "$input"
  fi
  return 0
}

devlog_ignored() {
  local out
  out="$(printf '%s\n' "$2" | devlog_ignore_filter "$1")"
  [ -z "$out" ]
}
