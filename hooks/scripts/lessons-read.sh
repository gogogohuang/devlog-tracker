#!/usr/bin/env bash
# Filesystem side of /devlog-tracker:lessons [<topic>] (docs/design/
# lessons-mode.md「Reading lessons on demand」). Plain read only -- no
# workspace verification, no wait-for-confirmation flow (a lessons file is
# reference material, not a paused work topic, unlike resume-devlog.sh).
set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"
# shellcheck source=devlog-md.sh
. "$SCRIPT_DIR/devlog-md.sh"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
MAIN="$DEVLOG_DIR/devlog.md"

TOPIC="${1:-}"

if [ -z "$TOPIC" ]; then
  if [ ! -f "$MAIN" ]; then
    echo "NO_INDEX"
    exit 0
  fi
  LINES="$(devlog_lessons_index_lines "$MAIN")"
  if [ -z "$LINES" ]; then
    echo "NO_INDEX"
  else
    printf '%s' "$LINES"
  fi
  exit 0
fi

case "$TOPIC" in *'/'*|*'\'*|*'..'*) echo "INVALID_TOPIC" >&2; exit 1 ;; esac
case "$TOPIC" in devlog.lessons.*) TOPIC="${TOPIC#devlog.lessons.}" ;; esac
case "$TOPIC" in devlog.*) TOPIC="${TOPIC#devlog.}" ;; esac
case "$TOPIC" in *.md) TOPIC="${TOPIC%.md}" ;; esac
TOPIC="$(slugify "$TOPIC")"
[ -n "$TOPIC" ] && [ "${#TOPIC}" -le 64 ] || { echo "INVALID_TOPIC" >&2; exit 1; }

FILE="$DEVLOG_DIR/devlog.lessons.$TOPIC.md"
if [ ! -f "$FILE" ]; then
  candidates=""
  shopt -s nullglob
  for path in "$DEVLOG_DIR"/devlog.lessons.*.md; do
    leaf="${path##*/}"
    candidate="${leaf#devlog.lessons.}"
    candidate="${candidate%.md}"
    [ -z "$candidates" ] || candidates="$candidates,"
    candidates="$candidates$candidate"
  done
  echo "MISSING"
  echo "CANDIDATES=$candidates"
  exit 1
fi
printf 'PATH=.devlog/devlog.lessons.%s.md\n' "$TOPIC"
cat "$FILE"
