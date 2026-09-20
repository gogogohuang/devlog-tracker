#!/usr/bin/env bash
# Claude-invoked only (docs/design/lessons-mode.md), never wired into
# claude/hooks.json — same posture as keep-move.sh. Appends one free-prose
# entry to .devlog/devlog.lessons.<topic>.md (creating it if new), then
# rebuilds the trailing "## Lessons 索引" block in devlog.md.
set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"
# shellcheck source=devlog-md.sh
. "$SCRIPT_DIR/devlog-md.sh"
# shellcheck source=devlog-lock.sh
. "$SCRIPT_DIR/devlog-lock.sh"
# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"

TOPIC=""
TEXT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --topic) TOPIC="${2:-}"; shift 2 ;;
    --text) TEXT="${2:-}"; shift 2 ;;
    *) echo "未知參數：$1" >&2; exit 1 ;;
  esac
done

PROJECT_DIR="${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
devlog_resolve_paths "$PROJECT_DIR"
MAIN="$DEVLOG_FILE"

[ -f "$DEVLOG_DIR/.enabled" ] || { echo "NOT_ENABLED" >&2; exit 1; }
[ -f "$DEVLOG_DIR/.lessons-enabled" ] || { echo "LESSONS_NOT_ENABLED" >&2; exit 1; }
[ -n "$TEXT" ] || { echo "缺少 --text" >&2; exit 1; }
[ -f "$MAIN" ] || { echo "devlog.md 不存在" >&2; exit 1; }

# --- Normalize <topic>，跟 keep/resume 的 <name> 同一套規則
# (docs/design/keep.md「Filenames」/ docs/design/lessons-mode.md「Storage」),
# 外加保留 lessons 這個 infix 本身當名字。
case "$TOPIC" in *'/'*|*'\'*|*'..'*) echo "TOPIC 無效" >&2; exit 1 ;; esac
case "$TOPIC" in devlog.lessons.*) TOPIC="${TOPIC#devlog.lessons.}" ;; esac
case "$TOPIC" in devlog.*) TOPIC="${TOPIC#devlog.}" ;; esac
case "$TOPIC" in *.md) TOPIC="${TOPIC%.md}" ;; esac
TOPIC="$(slugify "$TOPIC")"
[ -n "$TOPIC" ] && [ "$TOPIC" != "archive" ] && [ "$TOPIC" != "lessons" ] && [ "${#TOPIC}" -le 64 ] \
  || { echo "TOPIC 無效" >&2; exit 1; }

devlog_lock_acquire
trap 'devlog_lock_release' EXIT

TARGET="$DEVLOG_DIR/devlog.lessons.$TOPIC.md"
TS="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"

IS_NEW_TOPIC=0
if [ ! -f "$TARGET" ]; then
  printf '# Lessons: %s\n\n- source: `.devlog/devlog.md`\n' "$TOPIC" > "$TARGET" || exit 1
  IS_NEW_TOPIC=1
fi
{
  printf '\n## %s\n' "$TS"
  printf '%s\n' "$TEXT"
} >> "$TARGET" || exit 1

# --- Rebuild "## Lessons 索引" in devlog.md: one line per topic file,
# re-derived from disk each call (docs/design/lessons-mode.md「## Lessons
# 索引」). Title = first non-empty line after the LAST "## <timestamp>"
# heading in that file, truncated at the first 。/. (whichever comes
# first); no truncation if neither appears.
INDEX_LINES=""
OTHER_TOPICS=""
shopt -s nullglob
for f in "$DEVLOG_DIR"/devlog.lessons.*.md; do
  [ -f "$f" ] || continue
  leaf="${f##*/}"
  n="$(grep -c '^## ' "$f" 2>/dev/null || echo 0)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  [ "$n" -gt 0 ] || continue
  if [ "$leaf" = "devlog.lessons.$TOPIC.md" ]; then
    THIS_TOPIC_COUNT="$n"
  else
    OTHER_TOPIC_NAME="${leaf#devlog.lessons.}"
    OTHER_TOPIC_NAME="${OTHER_TOPIC_NAME%.md}"
    OTHER_TOPICS="${OTHER_TOPICS:+$OTHER_TOPICS, }${OTHER_TOPIC_NAME}"
  fi
  last_ln="$(grep -n '^## ' "$f" | tail -1 | cut -d: -f1)"
  updated_at="$(sed -n "${last_ln}p" "$f" | sed -E 's/^## //')"
  title="$(awk -v start="$last_ln" 'NR>start && $0 ~ /[^[:space:]]/ {print; exit}' "$f")"
  title="$(printf '%s' "$title" | sed -E 's/([。.]).*$/\1/')"
  LINE="- \`${leaf}\`：${n} 則，最新一則「${title}」（updated_at ${updated_at}）"
  INDEX_LINES="${INDEX_LINES:+$INDEX_LINES$'\n'}$LINE"
done

STRIPPED="$(mktemp "${TMPDIR:-/tmp}/devlog-lessons.XXXXXX")" || exit 1
trap 'rm -f "$STRIPPED"; devlog_lock_release' EXIT
devlog_strip_lessons_index "$MAIN" "$STRIPPED"
{
  cat "$STRIPPED"
  printf '\n## Lessons 索引\n'
  [ -n "$INDEX_LINES" ] && printf '%s\n' "$INDEX_LINES"
} > "$STRIPPED.new" && mv "$STRIPPED.new" "$MAIN" || exit 1

printf 'PATH=.devlog/devlog.lessons.%s.md\n' "$TOPIC"
if [ -n "${THIS_TOPIC_COUNT:-}" ] && [ $((THIS_TOPIC_COUNT % 3)) -eq 0 ]; then
  printf '[Lessons Mode 提示] 這個主題已經累積 %s 則。可考慮升級成 docs/design/*.md 的正式決策，不強制。\n' "$THIS_TOPIC_COUNT"
fi
if [ "$IS_NEW_TOPIC" -eq 1 ] && [ -n "${OTHER_TOPICS:-}" ]; then
  printf 'NEW_TOPIC。既有主題：%s（如果內容其實屬於這些主題之一，改用 --topic 該名稱重跑，避免同一件事分裂成兩個檔案）。\n' "$OTHER_TOPICS"
fi
