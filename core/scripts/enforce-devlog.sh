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
# shellcheck source=workspace-snapshot.sh
. "$SCRIPT_DIR/workspace-snapshot.sh"
# shellcheck source=files-snapshot.sh
. "$SCRIPT_DIR/files-snapshot.sh"
# shellcheck source=devlog-md.sh
. "$SCRIPT_DIR/devlog-md.sh"

# --- loop guard -------------------------------------------------------
# 有 jq 就用 jq 精準解析；沒有 jq 就退化成字串比對（沒有更嚴謹的 parse，但
# 足以涵蓋 Claude Code 實際送出的 stop_hook_active 欄位形狀），兩種環境都要生效。
INPUT="$(cat 2>/dev/null || true)"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
# 沒下過 /devlog-tracker:start，代表這個專案沒啟動強制記錄，直接放行。
# 這是唯一的判斷依據——不猜這輪是否呼叫了某個 skill，也不解析 transcript。
# 這個 gate 放在路徑解析之前，沒啟用時就不必付 git rev-parse 的成本；
# DEVLOG_DIR 永遠是 $PROJECT_DIR/.devlog，與分支無關，所以兩者等價。
ENABLED_FLAG="$PROJECT_DIR/.devlog/.enabled"
if [ ! -f "$ENABLED_FLAG" ]; then
  # 沒啟用就不做任何強制，但仍要清掉殘留的 .interrupted，否則之後重新
  # /devlog-tracker:start 會繼承一個陳舊的中斷旗標。.interrupted 跟
  # DEVLOG_DIR 一樣與分支無關，所以這裡不必解析分支。
  if [ -f "$PROJECT_DIR/.devlog/.interrupted" ]; then
    rm -f "$PROJECT_DIR/.devlog/.interrupted" 2>/dev/null || true
  fi
  exit 0
fi
# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"
devlog_resolve_paths "$PROJECT_DIR"
ROUND_CURRENT="$DEVLOG_DIR/.round-current.md"
if [ -f "$DEVLOG_DIR/.interrupted" ]; then
  bash "$SCRIPT_DIR/close-open-round.sh" "user_interrupt" || true
  rm -f "$DEVLOG_DIR/.interrupted" 2>/dev/null || true
  # close-open-round.sh merges and removes .round-current.md whenever it
  # decided the round was finished (stamped INTERRUPTED, or recovered —
  # Claude had already written Summary/Handoff before the interrupt signal
  # arrived). Either way there is nothing left in .round-current.md for
  # this Stop invocation to validate. If .round-current.md still has
  # content, .round-open was stale/absent and close-open-round.sh was a
  # no-op — fall through to the normal flow below, which validates
  # whatever the user's actual in-progress turn wrote.
  if [ ! -s "$ROUND_CURRENT" ]; then
    exit 0
  fi
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
TURN_MARKER="$DEVLOG_DIR/.turn-start"

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

if [ -f "$ROUND_CURRENT" ]; then
  CURRENT_HASH="$(cksum < "$ROUND_CURRENT" 2>/dev/null || echo '')"
else
  CURRENT_HASH="MISSING"
fi
# 一樣的防呆：雜湊算不出來就放行，不要因為偵測異常反而卡住使用者。
[ -n "$CURRENT_HASH" ] || exit 0

if [ "$CURRENT_HASH" = "$TURN_START_HASH" ]; then
  if [ "$SPAN_VALID" -eq 1 ]; then
    echo "這一輪尚未寫入。請依 skills/devlog-tracker/SKILL.md 在 .devlog/.round-current.md 建立一個新的 ## Round（編號接在 devlog.md 目前最後一輪之後），包含 User Input / Summary / Reply / Handoff / Status；收尾成功後 hook 會自動併回 devlog.md，不要自己直接寫進 devlog.md。" >&2
  else
    echo "這一輪的 Round 只有 hook 寫的 User Input skeleton，還沒有收尾。請依 skills/devlog-tracker/SKILL.md 編輯最後一個 Round，補上 User Input / Summary / Reply / Handoff / Status。不要再新增一個 ## Round。" >&2
  fi
  exit 2
fi

# --- 標題檢查（Summary + Reply + Handoff）---------------------------------
# 雜湊已經證明這輪有寫入。.round-current.md 理論上恰好裝著這一輪（且只有
# 這一輪），但不能整份 cat 進來當作要驗證的內容：Claude 收尾這一輪時可能
# 已經在同一個檔案尾端接著寫了一段「## Checkpoint」（見下面 Step 9 的
# merge，會把整個檔案一起併進 devlog.md），而內容裡如果完全沒有
# `## Round ` 這一行（例如只是一段雜訊文字），代表根本沒有 Round 可驗——
# 兩種情況都必須比照舊版 last_round_block() 的
# 邊界規則來擷取：找第一行 `## Round `（fence 之外），一路擷取到下一個
# 不在 fence 裡的 `## ` 為止（或檔尾），把後面接的 Checkpoint 等區段排除
# 在外。完全找不到 `## Round ` 這一行：fail-open（LAST_ROUND 留空，不擋），
# 對應舊版 `if (start == 0) exit 0` 的行為。
LAST_ROUND="$(awk '
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
' "$ROUND_CURRENT" 2>/dev/null || true)"
if [ -n "$LAST_ROUND" ]; then
  HAS_SUMMARY=0
  HAS_REPLY=0
  HAS_HANDOFF=0
  printf '%s\n' "$LAST_ROUND" | grep -q '^### Summary' && HAS_SUMMARY=1
  printf '%s\n' "$LAST_ROUND" | grep -q '^### Reply' && HAS_REPLY=1
  printf '%s\n' "$LAST_ROUND" | grep -q '^### Handoff' && HAS_HANDOFF=1
  if [ "$HAS_SUMMARY" -eq 0 ] || [ "$HAS_REPLY" -eq 0 ] || [ "$HAS_HANDOFF" -eq 0 ]; then
    echo "最後一個 Round 缺少 \`### Summary\`、\`### Reply\` 或 \`### Handoff\`。請依 skills/devlog-tracker/SKILL.md 補上這三個標題（Summary 給人掃、Reply 記對使用者說過的話、Handoff 給下一輪接續），寫在同一個 Round 裡，不要再新增一個 ## Round。" >&2
    exit 2
  fi

  # Fence-aware: a heading-looking line inside a ``` fence (e.g. a markdown
  # example quoting #### 決策 / #### 現況) must not be mistaken for a real
  # heading, but its fenced content is still part of the body once grab has
  # started.
  #
  # NOFENCE 防呆：如果這個 Round 裡 ``` 記號的數量是奇數（代表圍欄沒有正常
  # 收尾——真的寫錯了，不是刻意的範例），fence 變數會在這輪剩下的內容裡卡在
  # 1，導致下面三段 fence-aware awk 把明明存在的內容誤判成「被吃掉、看起來
  # 是空的」而擋下使用者（exit 2、訊息卻說「是空的」）。這違反本專案的
  # fail-open 原則，也重現了 Task 1 想解決的那種卡死。NOFENCE=1 時強制
  # fence 變數維持 0，讓這三段退化回 Task 1 之前的單純掃描行為——退化後
  # 「卡住的圍欄」不可能吃掉內容，是 fail-open 安全的；圍欄成雙成對（含 0
  # 個）時，NOFENCE=0，Task 1 加入的 fence-aware 行為完全不變。
  FENCE_MARKER_COUNT="$(printf '%s\n' "$LAST_ROUND" | grep -c '^[ \t]*```')"
  NOFENCE=0
  [ $((FENCE_MARKER_COUNT % 2)) -eq 0 ] || NOFENCE=1

  section_body() {
    local heading="$1"
    printf '%s\n' "$LAST_ROUND" | awk -v h="$heading" -v nofence="$NOFENCE" '
      /^[ \t]*```/ { if (!nofence) fence = !fence; if (grab) print; next }
      !fence && $0 ~ h { grab=1; next }
      grab && !fence && /^### / { exit }
      grab && !fence && /^## / { exit }
      grab { print }
    '
  }

  handoff_subsection_body() {
    local heading="$1"
    printf '%s\n' "$LAST_ROUND" | awk -v h="$heading" -v nofence="$NOFENCE" '
      /^[ \t]*```/ { if (!nofence) fence = !fence; if (grab) print; next }
      !fence && $0 ~ h { grab=1; next }
      grab && !fence && /^#### / { exit }
      grab && !fence && /^### / { exit }
      grab && !fence && /^## / { exit }
      grab { print }
    '
  }

  nonempty_body() {
    section_body "$1" | grep -q '[^[:space:]]'
  }

  SUM_BODY_OK=0
  REPLY_BODY_OK=0
  HAN_BODY_OK=0
  nonempty_body '^### Summary' && SUM_BODY_OK=1
  nonempty_body '^### Reply' && REPLY_BODY_OK=1
  nonempty_body '^### Handoff' && HAN_BODY_OK=1
  if [ "$SUM_BODY_OK" -eq 0 ] || [ "$REPLY_BODY_OK" -eq 0 ] || [ "$HAN_BODY_OK" -eq 0 ]; then
    echo "最後一個 Round 的 ### Summary、### Reply 或 ### Handoff 是空的。請依 skills/devlog-tracker/SKILL.md 寫上內容（不要只留標題），寫在同一個 Round 裡，不要再新增一個 ## Round。" >&2
    exit 2
  fi

  # --- Handoff subsection order check (docs/design/devlog-as-ssot-assessment.md,
  # Phase 2 + L1 完成條件). 決策 → 檔案 → 工作區 → 現況 → 完成條件 → 下一步
  # is a fixed order. Detect a present-but-reordered or duplicated recognized
  # subsection. Unrecognized #### headings are ignored.
  HANDOFF_BODY="$(section_body '^### Handoff')"
  ORDER_ERR="$(printf '%s\n' "$HANDOFF_BODY" | awk -v nofence="$NOFENCE" '
    BEGIN {
      order["決策"] = 1; order["檔案"] = 2; order["工作區"] = 3
      order["現況"] = 4; order["完成條件"] = 5; order["下一步"] = 6
      last = 0; prev_name = ""
    }
    /^[ \t]*```/ { if (!nofence) fence = !fence; next }
    fence { next }
    /^#### / {
      name = $0
      sub(/^#### [ \t]*/, "", name)
      sub(/[ \t]+$/, "", name)
      if (!(name in order)) next
      idx = order[name]
      if (seen[name]) { print "duplicate:" name; exit }
      seen[name] = 1
      if (idx < last) { print "order:" prev_name ">" name; exit }
      last = idx
      prev_name = name
    }
  ')"
  if [ -n "$ORDER_ERR" ]; then
    case "$ORDER_ERR" in
      duplicate:*)
        DUP_NAME="${ORDER_ERR#duplicate:}"
        echo "Handoff 的「#### ${DUP_NAME}」出現超過一次。請合併成一節。" >&2
        ;;
      order:*)
        echo "Handoff 小節順序錯了（應該是 決策 → 檔案 → 工作區 → 現況 → 完成條件 → 下一步）：${ORDER_ERR#order:}" >&2
        ;;
    esac
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
    HAS_DONE_CRITERIA=0
    printf '%s\n' "$LAST_ROUND" | grep -q '^#### 完成條件' && HAS_DONE_CRITERIA=1
    DONE_CRITERIA_OK=0
    if [ "$HAS_DONE_CRITERIA" -eq 1 ]; then
      handoff_subsection_body '^#### 完成條件' | grep -q '[^[:space:]]' && DONE_CRITERIA_OK=1
    fi
    if [ "$DONE_CRITERIA_OK" -eq 0 ]; then
      echo "Status 是 IN_PROGRESS 或 BLOCKED 時，Handoff 必須有「#### 完成條件」且後面有內容（可觀察的做完判準）。" >&2
      exit 2
    fi

    HAS_NEXT=0
    printf '%s\n' "$LAST_ROUND" | grep -q '^#### 下一步' && HAS_NEXT=1
    NEXT_OK=0
    if [ "$HAS_NEXT" -eq 1 ]; then
      handoff_subsection_body '^#### 下一步' | grep -q '[^[:space:]]' && NEXT_OK=1
    fi
    if [ "$NEXT_OK" -eq 0 ]; then
      echo "Status 是 IN_PROGRESS 或 BLOCKED 時，Handoff 必須有「#### 下一步」且後面有內容。" >&2
      exit 2
    fi

    # --- 下一步 filler blacklist (docs/design/next-step-blacklist.md):
    # non-semantic string match, not prose scoring. Only fires when the
    # entire trimmed body is a single line that exactly equals one of a
    # fixed set of known-empty phrases (a real 下一步 with extra content
    # around one of these phrases always passes — see the design doc's
    # Match rule). Deliberately scoped to 下一步 only, never Summary/
    # 決策/現況.
    NEXT_BODY_TRIMMED="$(handoff_subsection_body '^#### 下一步' \
      | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
      | grep -v '^$' || true)"
    NEXT_LINE_COUNT="$(printf '%s\n' "$NEXT_BODY_TRIMMED" | grep -c '.' || true)"
    if [ "$NEXT_LINE_COUNT" -eq 1 ]; then
      NEXT_STRIPPED="$(printf '%s' "$NEXT_BODY_TRIMMED" | sed -e 's/[。.！!]*$//')"
      case "$NEXT_STRIPPED" in
        繼續完成|持續完成|持續優化|持續改進|之後再看|視情況調整|待確認|繼續|持續推進|繼續處理)
          echo "「#### 下一步」目前只寫了「${NEXT_STRIPPED}」，這是空話，不算具體下一步。請寫清楚下一輪打開就能做的具體動作（路徑／指令／要載入的 skill）。" >&2
          exit 2
          ;;
      esac
    fi

    # --- IN_PROGRESS only: light actionable lint for 下一步 (L1).
    # Pass if body shows a path (/), backtick command, file-ish token, or
    # skill mention. False negatives OK; avoid scoring prose.
    if [ "$STATUS_VAL" = "IN_PROGRESS" ]; then
      if ! printf '%s\n' "$NEXT_BODY_TRIMMED" | grep -qE '/|`|\.[A-Za-z0-9]{1,10}([^A-Za-z0-9]|$)|[Ss][Kk][Ii][Ll][Ll]|hooks/|docs/|commands/|skills/'; then
        echo "Status 是 IN_PROGRESS 時，「#### 下一步」須含可執行跡象（路徑、反引號指令、檔名或 skill）。請寫到下一輪打開就能做。" >&2
        exit 2
      fi
    fi

    # --- BLOCKED: 缺件句式 in 現況 or 下一步 (binary check for next agent).
    if [ "$STATUS_VAL" = "BLOCKED" ]; then
      BLOCKED_HINT="$( {
        handoff_subsection_body '^#### 現況'
        handoff_subsection_body '^#### 下一步'
      } | tr '\n' ' ')"
      if ! printf '%s\n' "$BLOCKED_HINT" | grep -qE '缺|等待|等使用者|需要.*提供|尚未|出現.*算|出現即'; then
        echo "Status 是 BLOCKED 時，「#### 現況」或「#### 下一步」須寫清楚缺什麼、出現長怎樣（缺件句式），讓下一輪能判斷缺件是否已到。" >&2
        exit 2
      fi
    fi
  fi

  # --- 工作區 machine-verify (docs/design/devlog-as-ssot-assessment.md,
  # Phase 1 + DONE-with-檔案 extension): #### 工作區 must match a freshly
  # computed git snapshot exactly. Turns it from an unverified claim into a
  # write-time fact instead of something only continue/resume catch on the
  # next turn.
  #
  # Required for IN_PROGRESS/BLOCKED (unchanged from Phase 1) and for DONE
  # only when this round's Handoff has a non-empty #### 檔案 — i.e. it
  # claims to have touched/committed files. Without this, "已 commit 完成，
  # Status: DONE" was never checked against live git: the single most
  # common false-completion claim, and one prose-quality checks elsewhere
  # in this file explicitly leave unverified. A trivial DONE round with no
  # #### 檔案 still omits 工作區 entirely per SKILL.md's 瑣碎輪 convention —
  # unaffected.
  #
  # git unavailable -> fail-open, skip this check like every other one here.
  NEEDS_WORKSPACE_CHECK=0
  case "$STATUS_VAL" in
    IN_PROGRESS|BLOCKED) NEEDS_WORKSPACE_CHECK=1 ;;
    DONE)
      handoff_subsection_body '^#### 檔案' | grep -q '[^[:space:]]' && NEEDS_WORKSPACE_CHECK=1
      ;;
  esac
  if [ "$NEEDS_WORKSPACE_CHECK" -eq 1 ] && command -v git >/dev/null 2>&1; then
    EXPECTED_WS="$(workspace_snapshot "$PROJECT_DIR" 2>/dev/null || true)"
    if [ -n "$EXPECTED_WS" ]; then
      ACTUAL_WS="$(handoff_subsection_body '^#### 工作區' | sed -e '/^[[:space:]]*$/d')"
      if [ "$ACTUAL_WS" != "$EXPECTED_WS" ]; then
        echo "#### 工作區 跟目前 git 狀態不符（或缺漏）。請把這一節內容換成以下逐字內容：" >&2
        echo "" >&2
        printf '%s\n' "$EXPECTED_WS" >&2
        exit 2
      fi
    fi
  fi

  # --- 檔案 machine-verify (docs/design/files-verify.md, devlog ssot
  # Phase 4): #### 檔案 must describe real git changes. Runs whenever this
  # round's Handoff has a non-empty #### 檔案, independent of Status — a
  # trivial round with no #### 檔案 (the 瑣碎輪 convention) is unaffected.
  #
  # Grammar: zero or more "commit <hash>：" blocks (checked exactly,
  # category-precise, against files_snapshot $PROJECT_DIR $hash) followed
  # by at most one "尚未 commit：" block (checked one-directionally: every
  # claimed path must be in files_snapshot $PROJECT_DIR's current dirty
  # set; extra unclaimed dirty paths are not an error — cross-round
  # residue, see docs/design/files-verify.md Decision 4). A line that
  # isn't a recognized header or category line is a format violation and
  # blocks (not fail-open — Claude is expected to produce this grammar,
  # same as #### 工作區's seven formats). git unavailable, or a commit
  # hash that doesn't resolve, skips just that check (fail-open).
  FILES_BODY="$(handoff_subsection_body '^#### 檔案')"
  if printf '%s\n' "$FILES_BODY" | grep -q '[^[:space:]]' && command -v git >/dev/null 2>&1; then
    FILES_ERR=""
    CUR_KIND=""
    CUR_HASH=""
    CUR_CLAIM=""
    UNCOMMITTED_CLAIM_PATHS=""
    # Printed after a format-violation message so Claude has the exact
    # grammar to correct against, same rigor #### 工作區 already gets on
    # mismatch (it prints its own EXPECTED_WS). Category lines can be
    # omitted per block for a category with nothing to report, same as
    # files-snapshot.sh's own output.
    FILES_GRAMMAR="正確格式（照這個結構寫，分類行可依實際情況省略沒有變更的類別）：
commit <hash>：
新增：<path>, <path>
修改：<path>
刪除：<path>

尚未 commit：
新增：<path>
修改：<path>
刪除：<path>"

    files_body_parse() {
      # Normalizes #### 檔案's body into tagged records, one per input
      # line (blank/whitespace-only lines dropped):
      #   HDR\tcommit\t<hash>
      #   HDR\tuncommitted
      #   CAT\t<新增|修改|刪除>\t<comma-space-joined paths>
      #   ERR\t<original line>   (anything else non-blank)
      awk '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        {
          line = $0
          if (trim(line) == "") next
          if (line ~ /^commit [0-9a-f]+：$/) {
            hash = line
            sub(/^commit /, "", hash); sub(/：$/, "", hash)
            print "HDR\tcommit\t" hash
            next
          }
          if (line ~ /^尚未 commit：$/) { print "HDR\tuncommitted"; next }
          if (line ~ /^新增：/) { rest = line; sub(/^新增：/, "", rest); print "CAT\t新增\t" rest; next }
          if (line ~ /^修改：/) { rest = line; sub(/^修改：/, "", rest); print "CAT\t修改\t" rest; next }
          if (line ~ /^刪除：/) { rest = line; sub(/^刪除：/, "", rest); print "CAT\t刪除\t" rest; next }
          print "ERR\t" line
        }
      '
    }

    check_commit_block() {
      # files_snapshot returns empty stdout for two different reasons: the
      # hash doesn't resolve at all, or it resolves fine but that commit's
      # diff is entirely inside .devlog/ (or the commit is empty). Only the
      # former is fail-open territory — a resolvable commit must still be
      # compared even when its expected content is genuinely empty, or a
      # claim naming fabricated paths against it would silently pass. So
      # resolve the hash here, separately from computing $expected, instead
      # of inferring "unresolvable" from empty output.
      local h="$1" claimed="$2" expected
      git -C "$PROJECT_DIR" rev-parse --verify -q "${h}^{commit}" >/dev/null 2>&1 || return 0
      expected="$(files_snapshot "$PROJECT_DIR" "$h" 2>/dev/null || true)"
      if [ "$claimed" != "$expected" ]; then
        FILES_ERR="commit ${h} 的內容跟宣稱不符。請把這個區塊換成以下逐字內容："
        if [ -n "$expected" ]; then
          FILES_ERR="$FILES_ERR
commit ${h}：
${expected}"
        else
          FILES_ERR="$FILES_ERR
這個 commit 在 .devlog/ 以外沒有變更，「#### 檔案」裡不該有這個 commit 區塊（或整節省略，如果沒有其他 commit／尚未 commit 內容要報）。"
        fi
      fi
    }

    path_in_list() {
      # $1 = needle path (already trimmed by the caller), $2 = comma-space
      # -joined haystack (may be empty — files_snapshot's join format, see
      # files-snapshot.sh). Array-free on purpose: bash 3.2 (macOS's system
      # bash, this suite's de-facto floor) makes "${arr[@]}" on a genuinely
      # empty array an unbound-variable error under `set -uo pipefail`, and
      # an empty haystack (clean tree) is exactly the case this check must
      # not crash on. Padding both sides with ", " avoids matching a needle
      # that is only a substring of a longer path (e.g. "a.txt" must not
      # match "za.txt" or "a.txt2").
      local needle="$1" haystack="$2"
      case ", $haystack, " in
        *", $needle, "*) return 0 ;;
      esac
      return 1
    }

    while IFS=$'\t' read -r tag a b; do
      [ -z "$FILES_ERR" ] || break
      case "$tag" in
        HDR)
          if [ "$CUR_KIND" = "commit" ]; then
            check_commit_block "$CUR_HASH" "$CUR_CLAIM"
          fi
          CUR_CLAIM=""
          CUR_KIND="$a"
          CUR_HASH="$b"
          ;;
        CAT)
          case "$CUR_KIND" in
            commit)
              CUR_CLAIM="${CUR_CLAIM:+$CUR_CLAIM$'\n'}${a}：${b}"
              ;;
            uncommitted)
              UNCOMMITTED_CLAIM_PATHS="${UNCOMMITTED_CLAIM_PATHS:+$UNCOMMITTED_CLAIM_PATHS, }${b}"
              ;;
            *)
              FILES_ERR="#### 檔案 格式不對：分類行出現在任何 commit/尚未 commit 標頭之前。

${FILES_GRAMMAR}"
              ;;
          esac
          ;;
        ERR)
          FILES_ERR="#### 檔案 格式不對，看不懂這一行：${a}

${FILES_GRAMMAR}"
          ;;
      esac
    done < <(printf '%s\n' "$FILES_BODY" | files_body_parse)

    if [ -z "$FILES_ERR" ] && [ "$CUR_KIND" = "commit" ]; then
      check_commit_block "$CUR_HASH" "$CUR_CLAIM"
    fi

    if [ -z "$FILES_ERR" ] && [ -n "$UNCOMMITTED_CLAIM_PATHS" ]; then
      ACTUAL_DIRTY="$(files_snapshot "$PROJECT_DIR" 2>/dev/null || true)"
      ACTUAL_JOINED="$(printf '%s\n' "$ACTUAL_DIRTY" | sed -E 's/^(新增|修改|刪除)：//' | awk 'BEGIN{ORS=""} NF{print (out?", ":"") $0; out=1}')"
      IFS=',' read -ra _CLAIMED_ARR <<< "$UNCOMMITTED_CLAIM_PATHS"
      for _p in "${_CLAIMED_ARR[@]}"; do
        _p="$(printf '%s' "$_p" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [ -n "$_p" ] || continue
        if ! path_in_list "$_p" "$ACTUAL_JOINED"; then
          FILES_ERR="#### 檔案 的「尚未 commit」宣稱了 ${_p}，但它目前不在實際變更的檔案裡。目前實際的未提交變更是：
${ACTUAL_DIRTY:-（沒有，工作樹乾淨）}"
          break
        fi
      done
    fi

    if [ -n "$FILES_ERR" ]; then
      echo "$FILES_ERR" >&2
      exit 2
    fi
  fi
fi

rm -f "$DEVLOG_DIR/.workspace-mismatch" 2>/dev/null || true

# 這一輪通過所有驗證，正式收尾：把 .round-current.md 併回 devlog.md（併完
# 就地刪除 .round-current.md）。放在 checkpoint 計數檢查之前，這樣如果這輪
# 內容裡本來就有 Claude 寫的「## Checkpoint」，併進去之後馬上就會被下面的
# 數量比對算到，不用再等下一輪。
#
# 只有 LAST_ROUND 非空（代表上面真的抓到、驗證過一個 `## Round `）才併入。
# LAST_ROUND 是空的代表整個驗證區塊 fail-open 跳過了（.round-current.md
# 裡完全沒有 `## Round ` 這一行，例如純雜訊）——這種情況併入只會把未結構化
# 的內容寫進 devlog.md 的永久歷史，所以刻意保留 .round-current.md 原封不動，
# 讓之後的輪次或人工介入還能回頭處理，而不是併進去就再也分不出來。
#
# .round-open 只有在真的併入成功之後才刪除：devlog_merge_round_current
# 失敗時（例如寫入失敗）保留 .round-open，讓既有的 dangling-heal 機制
# （close-open-round.sh，下次 UserPromptSubmit / SessionStart 都會跑到）
# 之後還有機會重試，而不是內容被孤立在 .round-current.md 卻沒有任何機制
# 知道要去救它。
if [ -n "$LAST_ROUND" ]; then
  if devlog_merge_round_current "$DEVLOG_FILE" "$ROUND_CURRENT"; then
    rm -f "$DEVLOG_DIR/.round-open" 2>/dev/null || true
  fi
else
  rm -f "$DEVLOG_DIR/.round-open" 2>/dev/null || true
fi

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
      echo "已經 ${CP_ROUNDS} 輪沒有寫 checkpoint 摘要了（門檻 ${CP_MAX}）。請在 .devlog/${DEVLOG_FILE##*/} 追加一段「## Checkpoint（Round X-Y 摘要）」，總結這段期間做了什麼，寫完再結束這一輪。" >&2
      exit 2
    fi
  fi
fi

exit 0
