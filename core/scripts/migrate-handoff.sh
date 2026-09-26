#!/usr/bin/env bash
# Converts legacy `#### ` Handoff／Session Handoff in the live devlog files to
# XML (docs/design/handoff-xml.md「Migrate」). Run by the agent when Stop
# blocks on a legacy Handoff, or by /devlog-tracker:migrate.
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=handoff-convert.sh
. "$SCRIPT_DIR/handoff-convert.sh"
# shellcheck source=devlog-lock.sh
. "$SCRIPT_DIR/devlog-lock.sh"

PROJECT_DIR="${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
[ -d "$DEVLOG_DIR" ] || { echo NO_DEVLOG; exit 1; }

devlog_lock_acquire
trap 'devlog_lock_release' EXIT
if [ -n "${LOCK_CONTENDED_BY:-}" ]; then echo "LOCKED ${LOCK_CONTENDED_BY}"; exit 1; fi

MIGRATED=0
SKIPPED=0
LINES=""
add_line() { LINES="${LINES}${1}"$'\n'; }

migrate_round_file() {
  local f="$1" name rep n
  name="${f##*/}"
  rep="$(mktemp "$DEVLOG_DIR/.migrate.XXXXXX")" || return 0
  handoff_convert_file "$f" "$f.migrate-tmp" "$rep" || { rm -f "$f.migrate-tmp" "$rep"; return 0; }
  n="$(grep -c '^MIGRATED ' "$rep" || true)"
  while read -r tag round reason; do
    [ "$tag" = SKIP ] || continue
    SKIPPED=$((SKIPPED + 1))
    add_line "SKIP $name Round $round: $reason"
  done < "$rep"
  rm -f "$rep"
  if [ "${n:-0}" -gt 0 ]; then
    cp "$f" "$f.pre-migrate" && mv "$f.migrate-tmp" "$f" || { rm -f "$f.migrate-tmp"; return 0; }
    MIGRATED=$((MIGRATED + n))
    add_line "BACKUP=$f.pre-migrate"
  else
    rm -f "$f.migrate-tmp"
  fi
}

migrate_snapshot_file() {
  local f="$1" rc
  handoff_convert_snapshot "$f" "$f.migrate-tmp"; rc=$?
  if [ "$rc" -eq 0 ]; then
    cp "$f" "$f.pre-migrate" && mv "$f.migrate-tmp" "$f" || { rm -f "$f.migrate-tmp"; return 0; }
    add_line "BACKUP=$f.pre-migrate"
  else
    rm -f "$f.migrate-tmp"
    [ "$rc" -eq 1 ] && add_line "SKIP ${f##*/}: 看不懂的 handoff 快照格式，保留原樣"
  fi
}

for f in "$DEVLOG_DIR/.round-current.md" "$DEVLOG_DIR/devlog.md"; do
  [ -s "$f" ] && migrate_round_file "$f"
done
for f in "$DEVLOG_DIR"/devlog.*.md; do
  [ -s "$f" ] || continue
  head -n 1 "$f" | grep -q '^<!-- devlog-origin: ' || continue
  migrate_round_file "$f"
done
for f in "$DEVLOG_DIR"/handoff.md "$DEVLOG_DIR"/handoff.*.md; do
  [ -s "$f" ] && migrate_snapshot_file "$f"
done

echo "MIGRATED=$MIGRATED"
echo "SKIPPED=$SKIPPED"
printf '%s' "$LINES"
exit 0
