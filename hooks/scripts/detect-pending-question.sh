# shellcheck shell=bash
# sourced by hook scripts. Do not execute.
#
# Best-effort only, used to make the dangling-heal stub message more useful —
# not part of the enable/detection logic itself. 專案原則是不解析 transcript
# 來判斷「這輪有沒有記錄」（見 SKILL.md），這裡不違反：偵測不到／沒有 jq／
# 檔案讀不到，一律回傳空字串，退回原本的通用 stub 文字，不影響任何強制流程。
#
# detect_pending_question <transcript_path>
# 印出 "1" 代表：transcript 裡最後一筆 assistant/user 訊息，是一個還沒拿到
# 回答的 AskUserQuestion tool_use（also 是整份 transcript 的最後一筆有意義
# 紀錄）——最典型的訊號是「process 在等使用者選答案時被中斷」。其餘一律印出
# 空字串。
detect_pending_question() {
  local transcript="$1"
  [ -n "$transcript" ] || { echo ''; return 0; }
  [ -f "$transcript" ] || { echo ''; return 0; }
  command -v jq >/dev/null 2>&1 || { echo ''; return 0; }
  tail -n 200 "$transcript" 2>/dev/null | jq -rs '
    map(select(.type == "assistant" or .type == "user"))
    | if length == 0 then ""
      else
        (.[-1]) as $last
        | if $last.type == "assistant"
             and ($last.message.content // [] | any(.type == "tool_use" and .name == "AskUserQuestion"))
          then "1"
          else ""
          end
      end
  ' 2>/dev/null || echo ''
}
