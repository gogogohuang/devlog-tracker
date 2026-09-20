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
# shellcheck source=redact-prompt.sh
. "$HOOKS_DIR/redact-prompt.sh"
# shellcheck source=devlog-lock.sh
. "$HOOKS_DIR/devlog-lock.sh"
# shellcheck source=devlog-md.sh
. "$HOOKS_DIR/devlog-md.sh"
# shellcheck source=workspace-snapshot.sh
. "$HOOKS_DIR/workspace-snapshot.sh"
# shellcheck source=detect-pending-question.sh
. "$HOOKS_DIR/detect-pending-question.sh"
# shellcheck source=devlog-path.sh
. "$HOOKS_DIR/devlog-path.sh"
# shellcheck source=lessons-advisory-state.sh
. "$HOOKS_DIR/lessons-advisory-state.sh"
PROJECT_DIR="${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
[ -f "$PROJECT_DIR/.devlog/.enabled" ] || exit 0
devlog_resolve_paths "$PROJECT_DIR"
ROUND_CURRENT="$DEVLOG_DIR/.round-current.md"
SPAN_FILE="$DEVLOG_DIR/.span-open"
CHECKPOINT_FILE="$DEVLOG_DIR/.checkpoint-state"
SEGMENT_FILE="$DEVLOG_DIR/.segment-state"
ROUND_OPEN="$DEVLOG_DIR/.round-open"
AWAITING_FILE="$DEVLOG_DIR/.awaiting-reply"
ADVISORY_FILE="$DEVLOG_DIR/.lessons-advisory-state"

devlog_lock_acquire
trap 'devlog_lock_release' EXIT

INPUT="$(cat 2>/dev/null || true)"
SESSION_ID="$(json_str_field "$INPUT" session_id)"

if [ -f "$ROUND_OPEN" ]; then
  DANGLING_DETAIL=""
  if [ -n "$(detect_pending_question "$(json_str_field "$INPUT" transcript_path)")" ]; then
    DANGLING_DETAIL="awaiting_question"
  fi
  bash "$HOOKS_DIR/close-open-round.sh" "dangling:next_prompt" "$DANGLING_DETAIL" || true
fi

FOLD_ROUND=""
FOLD_NOTE="（回覆上一輪的問題）"
if [ -f "$AWAITING_FILE" ]; then
  AWAIT_ROUND="$(json_int_get "$AWAITING_FILE" round)"
  rm -f "$AWAITING_FILE" 2>/dev/null || true
  case "$AWAIT_ROUND" in
    ''|*[!0-9]*) AWAIT_ROUND='' ;;
  esac
  if [ -n "$AWAIT_ROUND" ] && [ -f "$DEVLOG_FILE" ]; then
    CURRENT_LAST="$(devlog_list_round_starts "$DEVLOG_FILE" | awk 'END { print $2 }')"
    if [ "$CURRENT_LAST" = "$AWAIT_ROUND" ]; then
      FOLD_ROUND="$AWAIT_ROUND"
    fi
  fi
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

PROMPT="$(json_str_field "$INPUT" prompt)"

# 背景 task-notification（例如子 agent 完成通知）不是使用者真的打字：不留原始
# XML，換成精簡摘要；也不當成新話題開新 Round，改折進最後一個 Round 當段落。
TASK_NOTIF=0
case "$PROMPT" in
  *'<task-notification>'*'</task-notification>'*) TASK_NOTIF=1 ;;
esac
if [ "$TASK_NOTIF" -eq 1 ]; then
  NOTIF_SUMMARY="$(printf '%s\n' "$PROMPT" | sed -n 's/.*<summary>\(.*\)<\/summary>.*/\1/p' | head -1)"
  NOTIF_STATUS="$(printf '%s\n' "$PROMPT" | sed -n 's/.*<status>\(.*\)<\/status>.*/\1/p' | head -1)"
  NOTIF_TASKID="$(printf '%s\n' "$PROMPT" | sed -n 's/.*<task-id>\(.*\)<\/task-id>.*/\1/p' | head -1)"
  [ -n "$NOTIF_SUMMARY" ] || NOTIF_SUMMARY="背景任務通知"
  NOTIF_META=""
  [ -n "$NOTIF_STATUS" ] && NOTIF_META="status=$NOTIF_STATUS"
  if [ -n "$NOTIF_TASKID" ]; then
    if [ -n "$NOTIF_META" ]; then NOTIF_META="$NOTIF_META, task-id=$NOTIF_TASKID"
    else NOTIF_META="task-id=$NOTIF_TASKID"
    fi
  fi
  if [ -n "$NOTIF_META" ]; then
    PROMPT="${NOTIF_SUMMARY}（${NOTIF_META}）"
  else
    PROMPT="$NOTIF_SUMMARY"
  fi
fi

if [ "$SPAN_SKIP" -eq 1 ]; then
  FOLD_ROUND=""
fi

if [ "$TASK_NOTIF" -eq 1 ] && [ -z "$FOLD_ROUND" ] && [ "$SPAN_SKIP" -eq 0 ] && [ -f "$DEVLOG_FILE" ]; then
  TASK_NOTIF_LAST="$(devlog_list_round_starts "$DEVLOG_FILE" | awk 'END { print $2 }')"
  case "$TASK_NOTIF_LAST" in
    ''|*[!0-9]*) : ;;
    *)
      FOLD_ROUND="$TASK_NOTIF_LAST"
      FOLD_NOTE="（背景任務通知）"
      ;;
  esac
fi

MISMATCH_FILE="$DEVLOG_DIR/.workspace-mismatch"
rm -f "$MISMATCH_FILE" 2>/dev/null || true
if [ "$SPAN_SKIP" -eq 0 ] && [ "$TASK_NOTIF" -eq 0 ] && [ -f "$DEVLOG_FILE" ]; then
  CLAIM_ST="$(workspace_claim_state "$PROJECT_DIR" "$DEVLOG_FILE" 2>/dev/null || echo NO_CLAIM)"
  if [ "$CLAIM_ST" = "MISMATCH" ]; then
    LAST_START="$(devlog_list_round_starts "$DEVLOG_FILE" | awk 'END { print $1 }')"
    LAST_END="$(devlog_block_end "$DEVLOG_FILE" "$LAST_START")"
    CLAIMED_WS="$(devlog_round_workspace_body "$DEVLOG_FILE" "$LAST_START" "$LAST_END")"
    LIVE_WS="$(workspace_snapshot "$PROJECT_DIR")"
    if [ -n "$LIVE_WS" ]; then
      printf '%s\n' "$LIVE_WS" > "$MISMATCH_FILE" 2>/dev/null || true
      printf '%s\n' "上一輪 Handoff「#### 工作區」跟目前 git 不符。先在這一輪追加 ### 段落，寫宣稱 vs 實際（實際用下面「實際」逐字內容），再依實際工作樹行動，不要照上一輪「現況／下一步」的字面。"
      printf '\n宣稱：\n%s\n\n實際：\n%s\n' "$CLAIMED_WS" "$LIVE_WS"

      if [ -f "$DEVLOG_DIR/.lessons-enabled" ]; then
        lessons_advisory_migrate "$DEVLOG_DIR"
        lessons_advisory_bump "$ADVISORY_FILE"
      fi
    fi
  fi
fi

if [ -n "$FOLD_ROUND" ]; then
  devlog_reopen_last_round "$DEVLOG_FILE" "$ROUND_CURRENT" || : > "$ROUND_CURRENT"
  if [ -z "$PROMPT" ]; then
    PROMPT="（無 prompt）"
  fi
  TRUNC_NOTE=""
  if [ "${#PROMPT}" -gt 4000 ]; then
    PROMPT="${PROMPT:0:4000}"
    TRUNC_NOTE="（後略，已截斷至 4000 字）"
  fi
  PROMPT="$(printf '%s' "$PROMPT" | sed 's/```/⟨fence⟩/g')"
  PROMPT="$(printf '%s' "$PROMPT" | redact_prompt)"

  TS="$(date +%H:%M 2>/dev/null || echo unknown)"
  FULL_TS="$(date +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || echo unknown)"
  START_LINE="$(devlog_list_round_starts "$ROUND_CURRENT" | awk 'END { print $1 }')"
  END_LINE="$(devlog_block_end "$ROUND_CURRENT" "$START_LINE")"
  SEG_N=$(( $(devlog_count_segments "$ROUND_CURRENT" "$START_LINE" "$END_LINE") + 1 ))

  SEG_TMP="$DEVLOG_DIR/.segment-insert.tmp"
  {
    printf '### 段落 %s - %s%s\n' "$SEG_N" "$TS" "$FOLD_NOTE"
    printf '```text\n'
    printf '%s\n' "$PROMPT"
    printf '```\n'
    if [ -n "$TRUNC_NOTE" ]; then
      printf '%s\n' "$TRUNC_NOTE"
    fi
    printf '\n'
  } > "$SEG_TMP" 2>/dev/null || true

  if [ -f "$SEG_TMP" ]; then
    devlog_insert_before_summary "$ROUND_CURRENT" "$START_LINE" "$END_LINE" "$SEG_TMP" > "$ROUND_CURRENT.tmp" 2>/dev/null \
      && mv "$ROUND_CURRENT.tmp" "$ROUND_CURRENT" 2>/dev/null || rm -f "$ROUND_CURRENT.tmp" 2>/dev/null || true
    rm -f "$SEG_TMP" 2>/dev/null || true
  fi

  printf '{"round": %s, "opened_at": "%s", "file": "%s"}\n' "$FOLD_ROUND" "$FULL_TS" "${DEVLOG_FILE##*/}" > "$ROUND_OPEN" 2>/dev/null || true
elif [ "$SPAN_SKIP" -eq 0 ]; then
  if [ -z "$PROMPT" ]; then
    PROMPT="（無 prompt）"
  fi
  TRUNC_NOTE=""
  if [ "${#PROMPT}" -gt 4000 ]; then
    PROMPT="${PROMPT:0:4000}"
    TRUNC_NOTE="（後略，已截斷至 4000 字）"
  fi
  PROMPT="$(printf '%s' "$PROMPT" | sed 's/```/⟨fence⟩/g')"
  PROMPT="$(printf '%s' "$PROMPT" | redact_prompt)"

  # 救孤兒：正常情況下這裡 .round-current.md 應該已經是空的／不存在（上一輪
  # 已經正常收尾併回 devlog.md）。如果不是——例如上一次 Stop 或
  # close-open-round.sh 併入失敗，內容被孤立在這裡卻沒有任何機制知道要去
  # 救它——在下面用 `>` 蓋掉新 skeleton 之前，先把它搶救併回 devlog.md，
  # 而不是讓 `>` 直接蓋掉遺失。正常情況（檔案已空/不存在）這裡是 no-op。
  # 必須放在下面的 LAST_N 掃描之前：這樣被搶救回來的孤兒 Round 才會被算進
  # 編號，下一輪不會意外沿用它的號碼。
  devlog_merge_round_current "$DEVLOG_FILE" "$ROUND_CURRENT"

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
    printf '## Round %s — %s\n\n' "$NEXT_N" "$TS"
    printf '### User Input\n'
    printf '```text\n'
    printf '%s\n' "$PROMPT"
    printf '```\n'
    if [ -n "$TRUNC_NOTE" ]; then
      printf '%s\n' "$TRUNC_NOTE"
    fi
    printf '\n### Status\nIN_PROGRESS\n'
  } > "$ROUND_CURRENT" 2>/dev/null || true

  if [ -f "$ROUND_CURRENT" ]; then
    printf '{"round": %s, "opened_at": "%s", "file": "%s"}\n' "$NEXT_N" "$TS" "${DEVLOG_FILE##*/}" > "$ROUND_OPEN" 2>/dev/null || true
  fi
fi

if [ -f "$ROUND_CURRENT" ]; then
  cksum < "$ROUND_CURRENT" > "$DEVLOG_DIR/.turn-start" 2>/dev/null || true
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

if [ "$SPAN_WILL_PASS_THROUGH" -eq 0 ] && [ -z "$FOLD_ROUND" ] && [ -f "$CHECKPOINT_FILE" ]; then
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
        if [ -f "$ROUND_CURRENT" ]; then
          SEG_CUR="$(cksum < "$ROUND_CURRENT" 2>/dev/null | tr -d '\n' || echo '')"
        else
          SEG_CUR="MISSING"
        fi
        if [ -n "$SEG_CUR" ]; then
          json_int_set "$SEGMENT_FILE" last_change_epoch "$SEG_NOW"
          json_str_set "$SEGMENT_FILE" last_seen_cksum "$SEG_CUR"
          SEG_MT=""; SEG_SZ=""
          if [ -f "$ROUND_CURRENT" ]; then
            if SEG_ID="$(stat -f '%m %z' "$ROUND_CURRENT" 2>/dev/null || stat -c '%Y %s' "$ROUND_CURRENT" 2>/dev/null || true)"; then
              SEG_MT="${SEG_ID%% *}"
              SEG_SZ="${SEG_ID#* }"
            fi
          fi
          if [ -n "$SEG_MT" ] && [ -n "$SEG_SZ" ]; then
            if ! grep -q '"last_seen_mtime"' "$SEGMENT_FILE" 2>/dev/null; then
              SEG_SID="$(json_str_get "$SEGMENT_FILE" session_id 2>/dev/null || true)"
              if [ -n "$SESSION_ID" ]; then SEG_SID="$SESSION_ID"; fi
              printf '{"last_change_epoch": %s, "last_seen_cksum": "%s", "last_seen_mtime": "%s", "last_seen_size": "%s", "max_silent_seconds": %s, "session_id": "%s"}\n' \
                "$SEG_NOW" "$SEG_CUR" "$SEG_MT" "$SEG_SZ" "$SEG_MAX" "${SEG_SID}" > "$SEGMENT_FILE" 2>/dev/null || true
            else
              json_str_set "$SEGMENT_FILE" last_seen_mtime "$SEG_MT"
              json_str_set "$SEGMENT_FILE" last_seen_size "$SEG_SZ"
              if [ -n "$SESSION_ID" ]; then
                json_str_set "$SEGMENT_FILE" session_id "$SESSION_ID"
              fi
            fi
          elif [ -n "$SESSION_ID" ]; then
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
