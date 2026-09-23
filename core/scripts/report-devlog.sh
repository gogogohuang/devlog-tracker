#!/usr/bin/env bash
# Stats + structured Round data for /devlog-tracker:report, `npx devlog-tracker
# report`, and timeline-devlog.sh (docs/design/read-side-and-promote.md B).
# Plain read only: never edits a devlog file. devlog_resolve_paths may still
# do its documented first-resolve rename, same as every other reader.
set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"
# shellcheck source=devlog-md.sh
. "$SCRIPT_DIR/devlog-md.sh"
# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"

JSON=0
ROUNDS=0
ALL=0
WITH_INPUT=0
# shellcheck disable=SC2034  # ROUNDS and ALL prepared for Task 3/4
for arg in "$@"; do
  case "$arg" in
    --json) JSON=1 ;;
    --rounds) ROUNDS=1 ;;
    --all-branches) ALL=1 ;;
    --with-input) WITH_INPUT=1 ;;
    *) echo "UNKNOWN_ARG=$arg" >&2; exit 2 ;;
  esac
done

devlog_resolve_paths "${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
if [ ! -d "$DEVLOG_DIR" ]; then
  if [ "$JSON" -eq 1 ]; then echo '{"started":false}'; else echo "NOT_STARTED"; fi
  exit 0
fi

# devlog.md -> main, devlog.archive.md -> archive, devlog.<x>.md -> <x>.
branch_of_file() {
  local leaf="${1##*/}"
  case "$leaf" in
    devlog.md) printf 'main' ;;
    devlog.archive.md) printf 'archive' ;;
    *) leaf="${leaf#devlog.}"; printf '%s' "${leaf%.md}" ;;
  esac
}

# Archive first (oldest), then the branch file(s).
FILES=()
[ -f "$DEVLOG_DIR/devlog.archive.md" ] && FILES+=("$DEVLOG_DIR/devlog.archive.md")
if [ "$ALL" -eq 1 ]; then
  : # filled in by Task 4
else
  [ -f "$DEVLOG_FILE" ] && FILES+=("$DEVLOG_FILE")
fi

SCAN="$(mktemp "${TMPDIR:-/tmp}/devlog-report.XXXXXX")" || exit 1
trap 'rm -f "$SCAN"' EXIT
for f in ${FILES[@]+"${FILES[@]}"}; do
  awk -v branch="$(branch_of_file "$f")" -v label="${f##*/}" -v with_input="$WITH_INPUT" \
    -f "$SCRIPT_DIR/report-scan.awk" "$f" >> "$SCAN"
done

count_status() { awk -F'\t' -v s="$1" '$1 == "R" && $2 == s { c++ } END { print c + 0 }' "$SCAN"; }
BRANCH="$(branch_of_file "$DEVLOG_FILE")"
ROUNDS_TOTAL="$(awk -F'\t' '$1 == "R" { c++ } END { print c + 0 }' "$SCAN")"
ROUNDS_ARCHIVE="$(awk -F'\t' '$1 == "R" && $4 == "archive" { c++ } END { print c + 0 }' "$SCAN")"
ROUNDS_MAIN=$((ROUNDS_TOTAL - ROUNDS_ARCHIVE))
STATUS_DONE="$(count_status DONE)"
STATUS_IN_PROGRESS="$(count_status IN_PROGRESS)"
STATUS_BLOCKED="$(count_status BLOCKED)"
STATUS_INTERRUPTED="$(count_status INTERRUPTED)"
BLOCKED_RATIO=0
[ "$ROUNDS_TOTAL" -gt 0 ] && BLOCKED_RATIO=$((STATUS_BLOCKED * 100 / ROUNDS_TOTAL))
CHECKPOINTS="$(awk -F'\t' '$1 == "C" { c++ } END { print c + 0 }' "$SCAN")"
KEPT_TOPICS=0
if [ -f "$DEVLOG_FILE" ]; then
  KEPT_TOPICS="$(devlog_kept_index_lines "$DEVLOG_FILE" | grep -c '^- `devlog\.' || true)"
fi
LESSONS_TOPICS=0
for f in "$DEVLOG_DIR"/devlog.lessons.*.md; do
  [ -f "$f" ] && LESSONS_TOPICS=$((LESSONS_TOPICS + 1))
done
ADVISORY=""
if [ -f "$DEVLOG_DIR/.lessons-advisory-state" ]; then
  a_count="$(json_int_get "$DEVLOG_DIR/.lessons-advisory-state" count)"
  a_max="$(json_int_get "$DEVLOG_DIR/.lessons-advisory-state" threshold)"
  ADVISORY="${a_count:-0}/${a_max:-3}"
fi
FIRST_ROUND_AT="$(awk -F'\t' '$1 == "R" && $3 != "" { print $3 }' "$SCAN" | sort | head -1)"
LAST_ROUND_AT="$(awk -F'\t' '$1 == "R" && $3 != "" { print $3 }' "$SCAN" | sort | tail -1)"
[ -n "$FIRST_ROUND_AT" ] || FIRST_ROUND_AT=none
[ -n "$LAST_ROUND_AT" ] || LAST_ROUND_AT=none

if [ "$JSON" -eq 0 ]; then
  printf 'BRANCH=%s\n' "$BRANCH"
  printf 'ROUNDS_TOTAL=%s\nROUNDS_MAIN=%s\nROUNDS_ARCHIVE=%s\n' "$ROUNDS_TOTAL" "$ROUNDS_MAIN" "$ROUNDS_ARCHIVE"
  printf 'STATUS_DONE=%s\nSTATUS_IN_PROGRESS=%s\nSTATUS_BLOCKED=%s\nSTATUS_INTERRUPTED=%s\n' \
    "$STATUS_DONE" "$STATUS_IN_PROGRESS" "$STATUS_BLOCKED" "$STATUS_INTERRUPTED"
  printf 'BLOCKED_RATIO=%s\nCHECKPOINTS=%s\nKEPT_TOPICS=%s\nLESSONS_TOPICS=%s\n' \
    "$BLOCKED_RATIO" "$CHECKPOINTS" "$KEPT_TOPICS" "$LESSONS_TOPICS"
  [ -n "$ADVISORY" ] && printf 'LESSONS_ADVISORY=%s\n' "$ADVISORY"
  printf 'FIRST_ROUND_AT=%s\nLAST_ROUND_AT=%s\n' "$FIRST_ROUND_AT" "$LAST_ROUND_AT"
  exit 0
fi

# JSON output: filled in by Task 3.
exit 0
