#!/usr/bin/env bash
# UserPromptSubmit hook：每次使用者送出新訊息時執行。
# 互動輪次：先（如有）把上一輪未收尾標成 INTERRUPTED，再追加本輪 User Input
# skeleton，然後把 .turn-start 設成「寫完 skeleton 之後」的雜湊，供 Stop hook
# 判斷 Claude 有沒有再寫 Summary/Handoff。
# Span 開著且檔案格式有效時不開新 Round。
# fail-open：這支腳本本身出任何問題都不該影響使用者送出訊息，一律 exit 0。

set -uo pipefail

_src="${BASH_SOURCE[0]}"
HOOKS_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$HOOKS_DIR/json-field.sh"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
ENABLED_FLAG="$DEVLOG_DIR/.enabled"
DEVLOG_FILE="$DEVLOG_DIR/devlog.md"
SPAN_FILE="$DEVLOG_DIR/.span-open"
CHECKPOINT_FILE="$DEVLOG_DIR/.checkpoint-state"
SEGMENT_FILE="$DEVLOG_DIR/.segment-state"
ROUND_OPEN="$DEVLOG_DIR/.round-open"

[ -f "$ENABLED_FLAG" ] || exit 0

INPUT="$(cat 2>/dev/null || true)"
SESSION_ID=""
if command -v jq >/dev/null 2>&1; then
  SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo '')"
  [ "$SESSION_ID" = "null" ] && SESSION_ID=""
else
  SESSION_ID="$(printf '%s' "$INPUT" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo '')"
fi

if [ -f "$ROUND_OPEN" ]; then
  bash "$HOOKS_DIR/close-open-round.sh" "dangling:next_prompt" || true
fi

SPAN_SKIP=0
if [ -f "$SPAN_FILE" ]; then
  SPAN_TICKS="$(json_int_get "$SPAN_FILE" ticks_since_checkin)"
  SPAN_MAX="$(json_int_get "$SPAN_FILE" max_silent_ticks)"
  case "$SPAN_TICKS" in ''|*[!0-9]*) SPAN_TICKS='' ;; esac
  case "$SPAN_MAX" in ''|*[!0-9]*) SPAN_MAX='' ;; esac
  if [ -n "$SPAN_TICKS" ] && [ -n "$SPAN_MAX" ]; then
    SPAN_SKIP=1
  fi
fi

PROMPT=""
if command -v jq >/dev/null 2>&1; then
  PROMPT="$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || echo '')"
  if [ "$PROMPT" = "null" ]; then PROMPT=""; fi
else
  PROMPT="$(printf '%s' "$INPUT" | grep -o '"prompt"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo '')"
fi

if [ "$SPAN_SKIP" -eq 0 ]; then
  if [ -z "$PROMPT" ]; then
    PROMPT="（無 prompt）"
  fi
  TRUNC_NOTE=""
  if [ "${#PROMPT}" -gt 4000 ]; then
    PROMPT="${PROMPT:0:4000}"
    TRUNC_NOTE="（後略，已截斷至 4000 字）"
  fi
  PROMPT="$(printf '%s' "$PROMPT" | sed 's/```/⟨fence⟩/g')"

  LAST_N=0
  if [ -f "$DEVLOG_FILE" ]; then
    LAST_N="$(awk '
      /^[ \t]*```/ { fence = !fence }
      !fence && /^## Round / {
        split($0, parts, /[ \t]+/)
        n = parts[3] + 0
        if (n > last) last = n
      }
      END { print last + 0 }
    ' "$DEVLOG_FILE" 2>/dev/null || echo 0)"
    case "$LAST_N" in ''|*[!0-9]*) LAST_N=0 ;; esac
  fi
  NEXT_N=$((LAST_N + 1))
  TS="$(date +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || echo unknown)"

  {
    printf '\n## Round %s — %s\n\n' "$NEXT_N" "$TS"
    printf '### User Input\n'
    printf '```text\n'
    printf '%s\n' "$PROMPT"
    printf '```\n'
    if [ -n "$TRUNC_NOTE" ]; then
      printf '%s\n' "$TRUNC_NOTE"
    fi
    printf '\n### Status\nIN_PROGRESS\n'
  } >> "$DEVLOG_FILE" 2>/dev/null || true

  if [ -f "$DEVLOG_FILE" ]; then
    printf '{"round": %s, "opened_at": "%s"}\n' "$NEXT_N" "$TS" > "$ROUND_OPEN" 2>/dev/null || true
  fi
fi

if [ -f "$DEVLOG_FILE" ]; then
  cksum < "$DEVLOG_FILE" > "$DEVLOG_DIR/.turn-start" 2>/dev/null || true
else
  echo "MISSING" > "$DEVLOG_DIR/.turn-start" 2>/dev/null || true
fi

SPAN_WILL_PASS_THROUGH=0
if [ -f "$SPAN_FILE" ]; then
  SPAN_TICKS="$(json_int_get "$SPAN_FILE" ticks_since_checkin)"
  SPAN_MAX="$(json_int_get "$SPAN_FILE" max_silent_ticks)"
  case "$SPAN_TICKS" in ''|*[!0-9]*) SPAN_TICKS='' ;; esac
  case "$SPAN_MAX" in ''|*[!0-9]*) SPAN_MAX='' ;; esac
  if [ -n "$SPAN_TICKS" ]; then
    NEW_TICKS=$((SPAN_TICKS + 1))
    json_int_set "$SPAN_FILE" ticks_since_checkin "$NEW_TICKS"
    if [ -n "$SPAN_MAX" ] && [ "$NEW_TICKS" -lt "$SPAN_MAX" ]; then
      SPAN_WILL_PASS_THROUGH=1
    fi
  fi
fi

if [ "$SPAN_WILL_PASS_THROUGH" -eq 0 ] && [ -f "$CHECKPOINT_FILE" ]; then
  CP_ROUNDS="$(json_int_get "$CHECKPOINT_FILE" rounds_since_checkpoint)"
  case "$CP_ROUNDS" in
    ''|*[!0-9]*) : ;;
    *)
      NEW_CP_ROUNDS=$((CP_ROUNDS + 1))
      json_int_set "$CHECKPOINT_FILE" rounds_since_checkpoint "$NEW_CP_ROUNDS"
      ;;
  esac
fi

if [ -f "$SEGMENT_FILE" ]; then
  SEG_EPOCH="$(json_int_get "$SEGMENT_FILE" last_change_epoch)"
  SEG_MAX="$(json_int_get "$SEGMENT_FILE" max_silent_seconds)"
  SEG_SUM_KEY="$(grep -o '"last_seen_cksum"[[:space:]]*:' "$SEGMENT_FILE" 2>/dev/null || echo '')"
  case "$SEG_EPOCH" in ''|*[!0-9]*) SEG_EPOCH='' ;; esac
  case "$SEG_MAX" in ''|*[!0-9]*) SEG_MAX='' ;; esac
  if [ -n "$SEG_EPOCH" ] && [ -n "$SEG_MAX" ] && [ -n "$SEG_SUM_KEY" ]; then
    SEG_NOW="$(date +%s 2>/dev/null || echo '')"
    case "$SEG_NOW" in
      ''|*[!0-9]*) : ;;
      *)
        if [ -f "$DEVLOG_FILE" ]; then
          SEG_CUR="$(cksum < "$DEVLOG_FILE" 2>/dev/null | tr -d '\n' || echo '')"
        else
          SEG_CUR="MISSING"
        fi
        if [ -n "$SEG_CUR" ]; then
          json_int_set "$SEGMENT_FILE" last_change_epoch "$SEG_NOW"
          json_str_set "$SEGMENT_FILE" last_seen_cksum "$SEG_CUR"
          if [ -n "$SESSION_ID" ]; then
            json_str_set "$SEGMENT_FILE" session_id "$SESSION_ID"
            SEG_SESSION="$(json_str_get "$SEGMENT_FILE" session_id)"
            if [ "$SEG_SESSION" != "$SESSION_ID" ]; then
              printf '{"last_change_epoch": %s, "last_seen_cksum": "%s", "max_silent_seconds": %s, "session_id": "%s"}\n' \
                "$SEG_NOW" "$SEG_CUR" "$SEG_MAX" "$SESSION_ID" > "$SEGMENT_FILE" 2>/dev/null || true
            fi
          fi
        fi
        ;;
    esac
  fi
fi

exit 0
