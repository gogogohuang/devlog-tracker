#!/usr/bin/env bash
# Sourced helper: field access for ### Handoff／### Session Handoff in both
# the legacy `#### 決策` form and the line-based XML form. Tag name == key.
# Not real XML — see docs/design/handoff-xml.md before changing anything.

# shellcheck disable=SC2034 # consumed by sourcing scripts
HANDOFF_KEYS="decisions files workspace state done-when next"
# shellcheck disable=SC2034
SESSION_HANDOFF_KEYS="decisions open-questions failed-attempts"

handoff_key_heading() {
  case "$1" in
    decisions) printf '決策' ;;
    files) printf '檔案' ;;
    workspace) printf '工作區' ;;
    state) printf '現況' ;;
    done-when) printf '完成條件' ;;
    next) printf '下一步' ;;
    open-questions) printf '待解問題' ;;
    failed-attempts) printf '失敗嘗試' ;;
    *) return 1 ;;
  esac
}

# 1 when $1 has an odd number of ``` markers (unclosed fence): callers then
# stop tracking fences, same fail-open as devlog-md.sh／enforce-devlog.sh.
_hf_nofence() {
  local n
  n="$(printf '%s\n' "$1" | grep -c '^[ \t]*```' 2>/dev/null || true)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  if [ $((n % 2)) -eq 1 ]; then echo 1; else echo 0; fi
}

handoff_section_of() {
  local blob="$1" name="$2" nofence
  nofence="$(_hf_nofence "$blob")"
  printf '%s\n' "$blob" | awk -v h="### $name" -v nofence="$nofence" '
    /^[ \t]*```/ { if (!nofence) fence = !fence; if (grab) print; next }
    !fence && !grab { t = $0; sub(/[ \t]+$/, "", t); if (t == h) { grab = 1; next } }
    grab && !fence && /^###? / { exit }
    grab { print }
  '
}

handoff_format() {
  local first nofence
  first="$(printf '%s\n' "$1" | awk 'NF { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, ""); print; exit }')"
  case "$first" in
    '<handoff>'|'<session-handoff>') echo xml; return 0 ;;
  esac
  nofence="$(_hf_nofence "$1")"
  if printf '%s\n' "$1" | awk -v nofence="$nofence" '
    /^[ \t]*```/ { if (!nofence) fence = !fence; next }
    !fence && /^#### / { found = 1; exit }
    END { exit(found ? 0 : 1) }
  '; then
    echo md
  else
    echo none
  fi
}

handoff_field() {
  local body="$1" key="$2" heading nofence
  case "$(handoff_format "$body")" in
    xml)
      printf '%s\n' "$body" | awk -v tag="$key" '
        { t = $0; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t) }
        !grab && t == "<" tag ">" { grab = 1; next }
        grab && t == "</" tag ">" { exit }
        grab { print }
      '
      ;;
    md)
      heading="$(handoff_key_heading "$key")" || return 0
      nofence="$(_hf_nofence "$body")"
      printf '%s\n' "$body" | awk -v h="$heading" -v nofence="$nofence" '
        /^[ \t]*```/ { if (!nofence) fence = !fence; if (grab) print; next }
        !fence && /^#### / {
          if (grab) exit
          name = $0; sub(/^#### [ \t]*/, "", name); sub(/[ \t]+$/, "", name)
          if (name == h) grab = 1
          next
        }
        grab && !fence && /^###? / { exit }
        grab { print }
      '
      ;;
  esac
}

handoff_xml_check() {
  local body="$1" kind="$2" keys
  case "$kind" in
    handoff) keys="$HANDOFF_KEYS" ;;
    session-handoff) keys="$SESSION_HANDOFF_KEYS" ;;
    *) return 1 ;;
  esac
  printf '%s\n' "$body" | awk -v kind="$kind" -v keys="$keys" '
    function fail(msg) { print msg; failed = 1; exit 1 }
    function order_str(   i, s) { s = k[1]; for (i = 2; i <= n; i++) s = s " → " k[i]; return s }
    BEGIN { n = split(keys, k, " "); for (i = 1; i <= n; i++) ord[k[i]] = i; st = "before"; cur = ""; last = 0 }
    {
      t = $0; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
      if (st == "before") {
        if (t == "") next
        if (t == "<" kind ">") { st = "in"; next }
        fail("第一個非空行必須是 <" kind ">（標籤自己一行），目前是：" t)
      }
      if (st == "after") {
        if (t == "") next
        fail("</" kind "> 外面不能有其他內容：" t)
      }
      if (cur != "") {
        if (t == "</" cur ">") {
          if (!body) fail("<" cur "> 是空的；沒有內容就整個標籤省略")
          cur = ""; next
        }
        if (match(t, /^<\/?[a-z][a-z_-]*>/)) {
          tag = substr(t, 1, RLENGTH); name = tag; gsub(/[<\/>]/, "", name)
          if ((name in ord) || name == kind) {
            if (t == tag) fail("<" cur "> 還沒用 </" cur "> 關閉就出現了 " tag)
            fail(tag " 要自己一行：內容寫在下一行，結尾標籤另起一行。看不懂這一行：" t)
          }
        }
        if (t != "") body = 1
        next
      }
      if (t == "") next
      if (t == "</" kind ">") { st = "after"; next }
      if (t ~ /^<[a-z][a-z_-]*>$/) {
        name = substr(t, 2, length(t) - 2)
        if (!(name in ord)) fail("不認得的標籤 <" name ">；<" kind "> 裡可用的標籤：" keys)
        if (seen[name]) fail("<" name "> 出現超過一次，請合併成一個")
        if (ord[name] < last) fail("標籤順序錯了（應該是 " order_str() "）：<" name "> 寫在 <" prev "> 後面")
        seen[name] = 1; last = ord[name]; prev = name; cur = name; body = 0
        next
      }
      if (t ~ /^<\/[a-z][a-z_-]*>$/) fail(t " 前面沒有對應的開頭標籤")
      if (match(t, /^<\/?[a-z][a-z_-]*>/)) {
        tag = substr(t, 1, RLENGTH); name = tag; gsub(/[<\/>]/, "", name)
        if (name in ord) fail(tag " 要自己一行：內容寫在下一行，結尾標籤另起一行。看不懂這一行：" t)
        fail("不認得的標籤 " tag "；<" kind "> 裡可用的標籤：" keys)
      }
      fail("<" kind "> 裡的內容要放在欄位標籤裡面，看不懂這一行：" t)
    }
    END {
      if (failed) exit 1
      if (st == "before") { print "缺少 <" kind "> 區塊"; exit 1 }
      if (cur != "") { print "<" cur "> 還沒用 </" cur "> 關閉"; exit 1 }
      if (st == "in") { print "缺少結尾的 </" kind ">"; exit 1 }
      if (kind == "session-handoff") {
        for (i = 1; i <= n; i++) if (!seen[k[i]]) { print "<session-handoff> 必須依序有 " keys "（沒有就寫 - （無）），缺 <" k[i] ">"; exit 1 }
      }
    }
  '
}

handoff_xml_template() {
  case "$1" in
    handoff)
      cat <<'EOF'
### Handoff
<handoff>
<decisions>
影響後續方向的選擇與理由（沒做選擇就整個標籤省略）
</decisions>
<files>
尚未 commit：
修改：path/to/file
</files>
<workspace>
main @ a1b2c3d，工作樹乾淨
</workspace>
<state>
任務做到哪、卡在哪
</state>
<done-when>
可觀察的做完判準（IN_PROGRESS／BLOCKED 必寫）
</done-when>
<next>
下一輪第一件具體要做的事（IN_PROGRESS／BLOCKED 必寫）
</next>
</handoff>
EOF
      ;;
    session-handoff)
      cat <<'EOF'
### Session Handoff
<session-handoff>
<decisions>
- 仍影響後續方向的選擇；沒有就寫 - （無）
</decisions>
<open-questions>
- 下一 session 最該先看的卡點；沒有就寫 - （無）
</open-questions>
<failed-attempts>
- 試過但放棄的做法；沒有就寫 - （無）
</failed-attempts>
</session-handoff>
EOF
      ;;
  esac
}

handoff_legacy_message() {
  local migrate="$1" project="$2"
  printf '%s\n' "Handoff 還是舊的「#### 小節」格式，這一輪要改用 XML 標籤。先跑下面的指令，把 devlog 裡的舊格式 Handoff 一次轉好，再結束這一輪一次："
  printf '\n'
  printf 'DEVLOG_PROJECT_DIR="%s" bash "%s"\n' "$project" "$migrate"
  printf '\n'
  printf '%s\n' "輸出的 SKIP 若列出這一輪，就照下面的模板手動改寫（標籤自己一行、沒有的欄位整個省略）："
  printf '\n'
  handoff_xml_template handoff
  printf '\n'
  handoff_xml_template session-handoff
  printf '\n'
  printf '%s\n' "給使用者：如果 agent 每一輪都還是寫舊格式，代表專案裡的 devlog-tracker skill／指令文件是舊版。請重跑 \`npx devlog-tracker init\`（Claude Code plugin 使用者改成更新 plugin），再執行 \`/devlog-tracker:start\`。"
}
