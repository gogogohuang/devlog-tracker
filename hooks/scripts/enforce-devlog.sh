#!/usr/bin/env bash
# Stop hook：Claude 想結束這一輪回應時執行。
# 檢查 devlog.md 的內容雜湊有沒有在這一輪開始之後變過，沒有就擋下來（exit 2），
# 逼 Claude 先依 SKILL.md 格式補寫這一輪的 Round 區塊，才能真正結束。
# 這是保證每輪都記錄的關鍵：不依賴 Claude 自行判斷「值不值得記錄」。
#
# 用內容雜湊（cksum）取代舊版的 mtime 比對：mtime 只有整秒精度，快速連續的
# 對話很容易讓「上一輪的寫入」跟「這一輪的開始」落在同一秒，導致誤判成
# 「已經寫過」而放行。雜湊直接比對內容有沒有變，不受時間精度影響，也不需要
# 再處理 GNU/BSD stat 的跨平台差異。
#
# 兩個穩健性設計，參考 agfnow/agentflow 的 stop-hook.js：
# 1. loop guard：讀 stdin 的 stop_hook_active 欄位，這是 Claude Code 官方標準欄位，
#    代表「這輪已經被本支 hook 擋下來、Claude 正在重跑」，此時直接放行，避免無窮迴圈
#    （Claude Code 本身也有連續擋 8 次的上限保護，這裡是多一層保險，且能更快恢復）。
# 2. fail-open：不用 set -e，每一步可能失敗的地方都明確接住、失敗就直接放行（exit 0），
#    絕不讓這支腳本自己的錯誤意外卡死使用者的 session——這支腳本的職責是「檢查」，
#    不該因為自己壞掉就變成「阻擋」。

set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"
# shellcheck source=devlog-lock.sh
. "$SCRIPT_DIR/devlog-lock.sh"

# Extracts the last "## Round N ..." block from $1 (fence-aware: a line
# starting with ``` — optionally indented — toggles in/out of a code
# fence, and headings inside a fence don't end the block). Used twice
# below: once for the interrupt-heal check, once for the Summary/Handoff
# title check.
last_round_block() {
  awk '
    /^[ \t]*```/ { fence = !fence }
    !fence && /^## Round / { start = NR }
    { lines[NR] = $0; infence[NR] = fence }
    END {
      if (start == 0) exit 0
      end = NR
      for (i = start + 1; i <= NR; i++) {
        if (!infence[i] && lines[i] ~ /^## /) { end = i - 1; break }
      }
      for (i = start; i <= end; i++) print lines[i]
    }
  ' "$1"
}

# --- loop guard -------------------------------------------------------
# 有 jq 就用 jq 精準解析；沒有 jq 就退化成字串比對（沒有更嚴謹的 parse，但
# 足以涵蓋 Claude Code 實際送出的 stop_hook_active 欄位形狀），兩種環境都要生效。
INPUT="$(cat 2>/dev/null || true)"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
DEVLOG_FILE="$DEVLOG_DIR/devlog.md"
if [ -f "$DEVLOG_DIR/.interrupted" ]; then
  bash "$SCRIPT_DIR/close-open-round.sh" "user_interrupt" || true
  rm -f "$DEVLOG_DIR/.interrupted" 2>/dev/null || true
  # Helper is silent. If it stamped, the last Round now has
  # INTERRUPTED + user_interrupt — exit 0 so Esc is not converted
  # into "please write Summary". Recovered-complete or a stale flag
  # leaves Status alone; fall through to hash / headings / checkpoint.
  _LAST_ROUND="$(last_round_block "$DEVLOG_FILE" 2>/dev/null || true)"
  case "$_LAST_ROUND" in
    *$'\nINTERRUPTED\nuser_interrupt'*) exit 0 ;;
  esac
fi

if command -v jq >/dev/null 2>&1; then
  STOP_HOOK_ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
else
  case "$INPUT" in
    *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) STOP_HOOK_ACTIVE=true ;;
    *)                                                          STOP_HOOK_ACTIVE=false ;;
  esac
fi
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# --- 開關檢查 -----------------------------------------------------------
ENABLED_FLAG="$DEVLOG_DIR/.enabled"
TURN_MARKER="$DEVLOG_DIR/.turn-start"
DEVLOG_FILE="$DEVLOG_DIR/devlog.md"

# 沒下過 /devlog-tracker:start，代表這個專案沒啟動強制記錄，直接放行。
# 這是唯一的判斷依據——不猜這輪是否呼叫了某個 skill，也不解析 transcript。
[ -f "$ENABLED_FLAG" ] || exit 0
devlog_lock_acquire
trap 'devlog_lock_release' EXIT

# --- span 檢查（Span Mode：橫跨多次自動續接的長任務）---------------------
# Claude 主動宣告的 .devlog/.span-open 存在時（見 SKILL.md），這個 tick 不
# 強制要求 devlog.md 有變動，只要求 ticks_since_checkin（由 round-start.sh
# 每個 tick 遞增）沒有累積超過 max_silent_ticks。超過門檻就退回下面正常的
# 雜湊比對，逼這輪真的寫點東西；寫成功後把計數器歸零。span 檔案壞掉、缺欄位
# 或不是數字，一律當作沒有 span，直接往下走正常流程——fail-open。
SPAN_FILE="$DEVLOG_DIR/.span-open"
SPAN_VALID=0
if [ -f "$SPAN_FILE" ]; then
  SPAN_TICKS="$(json_int_get "$SPAN_FILE" ticks_since_checkin)"
  SPAN_MAX="$(json_int_get "$SPAN_FILE" max_silent_ticks)"
  case "$SPAN_TICKS" in ''|*[!0-9]*) SPAN_TICKS='' ;; esac
  case "$SPAN_MAX" in ''|*[!0-9]*) SPAN_MAX='' ;; esac
  if [ -n "$SPAN_TICKS" ] && [ -n "$SPAN_MAX" ]; then
    SPAN_VALID=1
  fi
fi

if [ "$SPAN_VALID" -eq 1 ] && [ "$SPAN_TICKS" -lt "$SPAN_MAX" ]; then
  exit 0
fi

# 還沒有 turn marker，代表 UserPromptSubmit hook 這次沒跑到（例如剛裝上、
# 或是某種特殊情況），直接放行避免卡住——fail-open。
[ -f "$TURN_MARKER" ] || exit 0

TURN_START_HASH="$(cat "$TURN_MARKER" 2>/dev/null || echo '')"
# marker 內容讀不出來（讀取失敗、被意外改壞等）就當作沒有可靠依據，放行。
[ -n "$TURN_START_HASH" ] || exit 0

if [ -f "$DEVLOG_FILE" ]; then
  CURRENT_HASH="$(cksum < "$DEVLOG_FILE" 2>/dev/null || echo '')"
else
  CURRENT_HASH="MISSING"
fi
# 一樣的防呆：雜湊算不出來就放行，不要因為偵測異常反而卡住使用者。
[ -n "$CURRENT_HASH" ] || exit 0

if [ "$CURRENT_HASH" = "$TURN_START_HASH" ]; then
  if [ "$SPAN_VALID" -eq 1 ]; then
    echo "這一輪尚未寫入 devlog.md。請依 skills/devlog-tracker/SKILL.md 在檔案尾端追加一個新的 ## Round，包含 User Input / Summary / Handoff / Status。" >&2
  else
    echo "這一輪的 Round 只有 hook 寫的 User Input skeleton，還沒有收尾。請依 skills/devlog-tracker/SKILL.md 編輯最後一個 Round，補上 User Input / Summary / Handoff / Status。不要再新增一個 ## Round。" >&2
  fi
  exit 2
fi

# --- 標題檢查（Summary + Handoff）-----------------------------------------
# 雜湊已經證明這輪有寫入。接著取出最後一個 Round 區塊：從最後一個
# 「## Round 」行起到下一條「## 」標題之前（或 EOF）。圍欄（```）內的
# 行不參與起迄判定，避免 User Input / Handoff 引用 `## Round` 或 `## 安裝`
# 範例時把有效的最後一個 Round 誤切成缺標題。這個區塊必須同時有
# 以 ### Summary、### Handoff 開頭的行。只驗標題存在，不驗內容。
# 解析不到任何 ## Round：fail-open（不擋），避免把「寫了但不是 Round」
# 變成新的卡死理由。
LAST_ROUND="$(last_round_block "$DEVLOG_FILE" 2>/dev/null || true)"
if [ -n "$LAST_ROUND" ]; then
  HAS_SUMMARY=0
  HAS_HANDOFF=0
  printf '%s\n' "$LAST_ROUND" | grep -q '^### Summary' && HAS_SUMMARY=1
  printf '%s\n' "$LAST_ROUND" | grep -q '^### Handoff' && HAS_HANDOFF=1
  if [ "$HAS_SUMMARY" -eq 0 ] || [ "$HAS_HANDOFF" -eq 0 ]; then
    echo "最後一個 Round 缺少 \`### Summary\` 或 \`### Handoff\`。請依 skills/devlog-tracker/SKILL.md 補上這兩個標題（Summary 給人掃、Handoff 給下一輪接續），寫在同一個 Round 裡，不要再新增一個 ## Round。" >&2
    exit 2
  fi

  section_body() {
    local heading="$1"
    printf '%s\n' "$LAST_ROUND" | awk -v h="$heading" '
      $0 ~ h { grab=1; next }
      grab && /^### / { exit }
      grab && /^## / { exit }
      grab { print }
    '
  }

  nonempty_body() {
    section_body "$1" | grep -q '[^[:space:]]'
  }

  SUM_BODY_OK=0
  HAN_BODY_OK=0
  nonempty_body '^### Summary' && SUM_BODY_OK=1
  nonempty_body '^### Handoff' && HAN_BODY_OK=1
  if [ "$SUM_BODY_OK" -eq 0 ] || [ "$HAN_BODY_OK" -eq 0 ]; then
    echo "最後一個 Round 的 ### Summary 或 ### Handoff 是空的。請依 skills/devlog-tracker/SKILL.md 寫上內容（不要只留標題），寫在同一個 Round 裡，不要再新增一個 ## Round。" >&2
    exit 2
  fi

  STATUS_VAL="$(printf '%s\n' "$LAST_ROUND" | awk '
    /^### Status/ { grab=1; val=""; next }
    grab && /^### / { grab=0 }
    grab && /^## / { grab=0 }
    grab && $0 ~ /[^[:space:]]/ && val == "" { val=$0 }
    END { print val }
  ')"
  case "$STATUS_VAL" in
    DONE|IN_PROGRESS|BLOCKED|INTERRUPTED) ;;
    *)
      echo "### Status 必須是 DONE、IN_PROGRESS、BLOCKED、INTERRUPTED 其中一個。" >&2
      exit 2
      ;;
  esac

  if [ "$STATUS_VAL" = "IN_PROGRESS" ] || [ "$STATUS_VAL" = "BLOCKED" ]; then
    HAS_NEXT=0
    printf '%s\n' "$LAST_ROUND" | grep -q '^#### 下一步' && HAS_NEXT=1
    NEXT_OK=0
    if [ "$HAS_NEXT" -eq 1 ]; then
      printf '%s\n' "$LAST_ROUND" | awk '
        /^#### 下一步/ { grab=1; next }
        grab && /^#### / { exit }
        grab && /^### / { exit }
        grab && /^## / { exit }
        grab { print }
      ' | grep -q '[^[:space:]]' && NEXT_OK=1
    fi
    if [ "$NEXT_OK" -eq 0 ]; then
      echo "Status 是 IN_PROGRESS 或 BLOCKED 時，Handoff 必須有「#### 下一步」且後面有內容。" >&2
      exit 2
    fi
  fi
fi

rm -f "$DEVLOG_DIR/.round-open" 2>/dev/null || true

# 這輪真的有寫東西：如果剛剛因為 span 過期才走到這裡，把計數器歸零，
# 讓 span 繼續正常運作而不是每輪都卡在「超過門檻」。
if [ "$SPAN_VALID" -eq 1 ]; then
  json_int_set "$SPAN_FILE" ticks_since_checkin 0
fi

# --- checkpoint 檢查（Checkpoint Mode）----------------------------------
# 這輪確實寫了東西（上面的雜湊比對通過）之後，才檢查 checkpoint 狀態。
# 用「## Checkpoint 標題數量有沒有變多」當作可驗證的訊號，而不是「有沒有
# 寫東西」——因為每輪本來就一定會寫東西（上面的雜湊檢查已經保證），用寫入
# 當訊號會讓計數器每輪都被歸零，永遠到不了門檻。
CHECKPOINT_FILE="$DEVLOG_DIR/.checkpoint-state"
if [ -f "$CHECKPOINT_FILE" ]; then
  CP_ROUNDS="$(json_int_get "$CHECKPOINT_FILE" rounds_since_checkpoint)"
  CP_MAX="$(json_int_get "$CHECKPOINT_FILE" max_silent_rounds)"
  CP_SEEN="$(json_int_get "$CHECKPOINT_FILE" checkpoint_marker_count)"
  case "$CP_ROUNDS" in ''|*[!0-9]*) CP_ROUNDS='' ;; esac
  case "$CP_MAX" in ''|*[!0-9]*) CP_MAX='' ;; esac
  case "$CP_SEEN" in ''|*[!0-9]*) CP_SEEN='' ;; esac

  if [ -n "$CP_ROUNDS" ] && [ -n "$CP_MAX" ] && [ -n "$CP_SEEN" ]; then
    CURRENT_MARKER_COUNT="$(grep -c '^## Checkpoint' "$DEVLOG_FILE" 2>/dev/null || echo 0)"
    case "$CURRENT_MARKER_COUNT" in ''|*[!0-9]*) CURRENT_MARKER_COUNT=0 ;; esac

    # 下修同步：如果現在看到的數量比上次記的還少（compact 把 checkpoint 搬走了，
    # 或有人手動改了 devlog.md），代表 CP_SEEN 是過期的高估值，往下的 -gt 比對
    # 會永遠卡住（真的新寫的 checkpoint 也追不上這個虛高的門檻）。這裡必須立刻
    # 把 checkpoint_marker_count 寫回檔案修正——這支腳本每次 Stop hook 都是全新
    # process，只改 shell 變數不寫檔的話，下一次呼叫又會從檔案讀回舊的高估值，
    # 等於什麼都沒修到。只動 checkpoint_marker_count 這個欄位，不動
    # rounds_since_checkpoint——單純「數量變少」不代表寫了 checkpoint，不該歸零
    # 沉默輪數計數器。同時更新本次呼叫用的 CP_SEEN 變數，讓下面這次 invocation
    # 的 -gt / elif 判斷也立刻用修正後的值。
    if [ "$CURRENT_MARKER_COUNT" -lt "$CP_SEEN" ]; then
      json_int_set "$CHECKPOINT_FILE" checkpoint_marker_count "$CURRENT_MARKER_COUNT"
      CP_SEEN="$CURRENT_MARKER_COUNT"
    fi

    if [ "$CURRENT_MARKER_COUNT" -gt "$CP_SEEN" ]; then
      json_int_set "$CHECKPOINT_FILE" rounds_since_checkpoint 0
      json_int_set "$CHECKPOINT_FILE" checkpoint_marker_count "$CURRENT_MARKER_COUNT"
    elif [ "$CP_ROUNDS" -ge "$CP_MAX" ]; then
      echo "已經 ${CP_ROUNDS} 輪沒有寫 checkpoint 摘要了（門檻 ${CP_MAX}）。請在 .devlog/devlog.md 追加一段「## Checkpoint（Round X-Y 摘要）」，總結這段期間做了什麼，寫完再結束這一輪。" >&2
      exit 2
    fi
  fi
fi

exit 0
