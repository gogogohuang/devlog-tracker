#!/usr/bin/env bash
# 偵測孤兒 vendored hook：專案的 hook 設定檔裡，指向不存在的 .devlog-tracker/
# 腳本的項目（`npx devlog-tracker init` 寫的，目錄被刪或換 worktree 後會留下）。
# 以 source 方式使用：devlog_stale_vendored_hooks <專案根目錄>，每個孤兒腳本印一行
# 「<設定檔>\t<腳本路徑>」；沒有就不印。純 grep，不依賴 jq，讀不到就當沒有（fail-open）。

devlog_stale_vendored_hooks() {
  local project_dir="$1" rel file script
  for rel in .claude/settings.local.json .claude/settings.json .codex/hooks.json .cursor/hooks.json; do
    file="$project_dir/$rel"
    [ -f "$file" ] || continue
    # JSON 裡 command 的路徑被 \" 包住：bash \"/abs/.devlog-tracker/core/scripts/x.sh\"
    { grep -oE '\\"[^"\\]*\.devlog-tracker/[^"\\]+' "$file" 2>/dev/null || true; } | sort -u |
      while IFS= read -r script; do
        script="${script#\\\"}"
        [ -e "$script" ] || printf '%s\t%s\n' "$rel" "$script"
      done
  done
}
