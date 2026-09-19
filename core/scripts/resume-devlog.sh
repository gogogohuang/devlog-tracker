#!/usr/bin/env bash
set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"

NAME=""
if [ "${1:-}" = "--name" ]; then
  NAME="${2:-}"
else
  echo "MISSING_NAME" >&2
  exit 1
fi
case "$NAME" in devlog.md|*'/'*|*'\'*|*'..'*) echo "INVALID_NAME" >&2; exit 1 ;; esac
case "$NAME" in devlog.*) NAME="${NAME#devlog.}" ;; esac
case "$NAME" in *.md) NAME="${NAME%.md}" ;; esac
NAME="$(slugify "$NAME")"
[ -n "$NAME" ] && [ "$NAME" != "archive" ] && [ "${#NAME}" -le 64 ] \
  || { echo "INVALID_NAME" >&2; exit 1; }

DEVLOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.devlog"
FILE="$DEVLOG_DIR/devlog.$NAME.md"
if [ ! -f "$FILE" ]; then
  candidates=""
  shopt -s nullglob
  for path in "$DEVLOG_DIR"/devlog.*.md; do
    leaf="${path##*/}"
    case "$leaf" in devlog.md|devlog.archive.md) continue ;; esac
    candidate="${leaf#devlog.}"
    candidate="${candidate%.md}"
    [ -z "$candidates" ] || candidates="$candidates,"
    candidates="$candidates$candidate"
  done
  echo "MISSING"
  echo "CANDIDATES=$candidates"
  exit 1
fi
printf 'PATH=.devlog/devlog.%s.md\n' "$NAME"
cat "$FILE"
