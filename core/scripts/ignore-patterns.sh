#!/usr/bin/env bash
# User-invoked: /devlog-tracker:ignore filesystem side.
# Manages $PROJECT_DIR/.devlogignore.
#   list (default) | add <pattern> | remove <pattern> | check <path>
# Does not require .devlog/.enabled.
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"

PROJECT_DIR="${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
IGNORE_FILE="$PROJECT_DIR/.devlogignore"

usage() {
  echo "usage: ignore-patterns.sh [list | add <pattern> | remove <pattern> | check <path>]" >&2
  exit 1
}

CMD="${1:-list}"
case "$CMD" in
  list)
    [ "$#" -le 1 ] || usage
    if [ ! -f "$IGNORE_FILE" ]; then
      echo "no .devlogignore at $IGNORE_FILE"
      exit 0
    fi
    echo "$IGNORE_FILE"
    n=0
    while IFS= read -r line || [ -n "$line" ]; do
      n=$((n + 1))
      printf '%d: %s\n' "$n" "$line"
    done < "$IGNORE_FILE"
    [ "$n" -gt 0 ] || echo "(empty)"
    ;;
  add)
    [ "$#" -eq 2 ] && [ -n "$2" ] || usage
    PAT="$2"
    case "$PAT" in *$'\n'*) echo "pattern must be a single line" >&2; exit 1 ;; esac
    if [ -f "$IGNORE_FILE" ]; then
      while IFS= read -r line || [ -n "$line" ]; do
        if [ "$line" = "$PAT" ]; then
          echo "already present: $PAT"
          exit 0
        fi
      done < "$IGNORE_FILE"
      # ensure trailing newline before appending
      if [ -s "$IGNORE_FILE" ] && [ -n "$(tail -c 1 "$IGNORE_FILE")" ]; then
        printf '\n' >> "$IGNORE_FILE" || exit 1
      fi
    fi
    printf '%s\n' "$PAT" >> "$IGNORE_FILE" || { echo "cannot write $IGNORE_FILE" >&2; exit 1; }
    echo "added: $PAT"
    ;;
  remove)
    [ "$#" -eq 2 ] && [ -n "$2" ] || usage
    PAT="$2"
    if [ ! -f "$IGNORE_FILE" ]; then
      echo "not found: $PAT (no .devlogignore)"
      exit 0
    fi
    TMPF="$(mktemp "${IGNORE_FILE}.XXXXXX")" || { echo "cannot create temp file next to $IGNORE_FILE" >&2; exit 1; }
    found=0
    while IFS= read -r line || [ -n "$line" ]; do
      if [ "$line" = "$PAT" ]; then
        found=1
        continue
      fi
      printf '%s\n' "$line" >> "$TMPF"
    done < "$IGNORE_FILE"
    if [ "$found" -eq 1 ]; then
      mv "$TMPF" "$IGNORE_FILE" || { rm -f "$TMPF"; exit 1; }
      echo "removed: $PAT"
    else
      rm -f "$TMPF"
      echo "not found: $PAT"
    fi
    ;;
  check)
    [ "$#" -eq 2 ] && [ -n "$2" ] || usage
    if [ ! -f "$SCRIPT_DIR/devlog-ignore.sh" ]; then
      echo "matching unavailable: $SCRIPT_DIR/devlog-ignore.sh not found"
      exit 0
    fi
    # shellcheck source=/dev/null
    . "$SCRIPT_DIR/devlog-ignore.sh"
    if devlog_ignored "$PROJECT_DIR" "$2"; then
      echo "ignored: $2"
    else
      echo "not ignored: $2"
    fi
    ;;
  *) usage ;;
esac
exit 0
