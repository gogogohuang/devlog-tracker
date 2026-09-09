#!/usr/bin/env bash
# UserPromptSubmit hook：每次使用者送出新訊息時執行，
# 記下這一輪開始時 devlog.md 的內容雜湊，供 Stop hook 判斷這一輪有沒有寫過 devlog。
# 用雜湊而不是時間戳，避免同一秒內的寫入跟下一輪開始互相誤判（見 enforce-devlog.sh 註解）。
# fail-open：這支腳本本身出任何問題都不該影響使用者送出訊息，一律 exit 0。

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
ENABLED_FLAG="$DEVLOG_DIR/.enabled"
DEVLOG_FILE="$DEVLOG_DIR/devlog.md"
SPAN_FILE="$DEVLOG_DIR/.span-open"
CHECKPOINT_FILE="$DEVLOG_DIR/.checkpoint-state"
SEGMENT_FILE="$DEVLOG_DIR/.segment-state"

# 沒下過 /devlog-tracker:start（也就是沒有這個開關檔），代表這個專案沒啟動強制記錄，
# 直接放行，不留下任何 .devlog 檔案。
[ -f "$ENABLED_FLAG" ] || exit 0

if [ -f "$DEVLOG_FILE" ]; then
  cksum < "$DEVLOG_FILE" > "$DEVLOG_DIR/.turn-start" 2>/dev/null || true
else
  echo "MISSING" > "$DEVLOG_DIR/.turn-start" 2>/dev/null || true
fi

# Span Mode：.span-open 存在就把 ticks_since_checkin 遞增，供 Stop hook
# （enforce-devlog.sh）判斷這一輪要不要放寬檢查。讀不到或不是數字就跳過，
# 不動這個檔案——fail-open，讓 Stop hook 那邊的 malformed 判斷去處理。
# 同時記下「這個 tick 遞增後預期會不會被 Stop hook 的 Span Mode 早退放行」
# （span 有效、且遞增後的 ticks 還沒到 max_silent_ticks），供下面 Checkpoint
# Mode 判斷要不要把這個 tick 算進 rounds_since_checkpoint。
SPAN_WILL_PASS_THROUGH=0
if [ -f "$SPAN_FILE" ]; then
  SPAN_TICKS="$(grep -o '"ticks_since_checkin"[[:space:]]*:[[:space:]]*[0-9]\+' "$SPAN_FILE" 2>/dev/null | grep -o '[0-9]\+$' || echo '')"
  SPAN_MAX="$(grep -o '"max_silent_ticks"[[:space:]]*:[[:space:]]*[0-9]\+' "$SPAN_FILE" 2>/dev/null | grep -o '[0-9]\+$' || echo '')"
  case "$SPAN_TICKS" in ''|*[!0-9]*) SPAN_TICKS='' ;; esac
  case "$SPAN_MAX" in ''|*[!0-9]*) SPAN_MAX='' ;; esac
  if [ -n "$SPAN_TICKS" ]; then
    NEW_TICKS=$((SPAN_TICKS + 1))
    awk -v new="$NEW_TICKS" '{ gsub(/"ticks_since_checkin"[[:space:]]*:[[:space:]]*[0-9]+/, "\"ticks_since_checkin\": " new); print }' "$SPAN_FILE" > "$SPAN_FILE.tmp" 2>/dev/null \
      && mv "$SPAN_FILE.tmp" "$SPAN_FILE" 2>/dev/null || true
    if [ -n "$SPAN_MAX" ] && [ "$NEW_TICKS" -lt "$SPAN_MAX" ]; then
      SPAN_WILL_PASS_THROUGH=1
    fi
  fi
fi

# Checkpoint Mode：.checkpoint-state 存在就把 rounds_since_checkpoint +1——除非
# 這個 tick 預期會被上面判斷出來的 Span Mode 早退放行，這種情況下不計入，
# 避免自動續接期間被兩套機制疊加要求。讀不到或不是數字就跳過，fail-open。
if [ "$SPAN_WILL_PASS_THROUGH" -eq 0 ] && [ -f "$CHECKPOINT_FILE" ]; then
  CP_ROUNDS="$(grep -o '"rounds_since_checkpoint"[[:space:]]*:[[:space:]]*[0-9]\+' "$CHECKPOINT_FILE" 2>/dev/null | grep -o '[0-9]\+$' || echo '')"
  case "$CP_ROUNDS" in
    ''|*[!0-9]*) : ;;
    *)
      NEW_CP_ROUNDS=$((CP_ROUNDS + 1))
      awk -v new="$NEW_CP_ROUNDS" '{ gsub(/"rounds_since_checkpoint"[[:space:]]*:[[:space:]]*[0-9]+/, "\"rounds_since_checkpoint\": " new); print }' "$CHECKPOINT_FILE" > "$CHECKPOINT_FILE.tmp" 2>/dev/null \
        && mv "$CHECKPOINT_FILE.tmp" "$CHECKPOINT_FILE" 2>/dev/null || true
      ;;
  esac
fi

# Segment Watch：.segment-state 存在且欄位齊就重設 last_change_epoch / last_seen_cksum，
# 讓這一輪的 15 分鐘保底從現在起算。不動 max_silent_seconds。讀不到或不是數字就跳過。
if [ -f "$SEGMENT_FILE" ]; then
  SEG_EPOCH="$(grep -o '"last_change_epoch"[[:space:]]*:[[:space:]]*[0-9]\+' "$SEGMENT_FILE" 2>/dev/null | grep -o '[0-9]\+$' || echo '')"
  SEG_MAX="$(grep -o '"max_silent_seconds"[[:space:]]*:[[:space:]]*[0-9]\+' "$SEGMENT_FILE" 2>/dev/null | grep -o '[0-9]\+$' || echo '')"
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
          awk -v epoch="$SEG_NOW" -v sum="$SEG_CUR" '{
            gsub(/"last_change_epoch"[[:space:]]*:[[:space:]]*[0-9]+/, "\"last_change_epoch\": " epoch);
            gsub(/"last_seen_cksum"[[:space:]]*:[[:space:]]*"[^"]*"/, "\"last_seen_cksum\": \"" sum "\"");
            print
          }' "$SEGMENT_FILE" > "$SEGMENT_FILE.tmp" 2>/dev/null \
            && mv "$SEGMENT_FILE.tmp" "$SEGMENT_FILE" 2>/dev/null || true
        fi
        ;;
    esac
  fi
fi

exit 0
