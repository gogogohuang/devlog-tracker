# Handoff XML Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `### Handoff`／`### Session Handoff` 改用以行為單位的 XML 標籤；讀取端相容舊 `####` 格式；Stop 只收 XML；新增 `/devlog-tracker:migrate`。

**Architecture:** 新的 sourced helper `core/scripts/handoff-fields.sh` 是唯一知道「key ↔ 中文小節名 ↔ 標籤」與兩種格式解析的地方（標籤名 = key）。`core/scripts/handoff-convert.sh` 做純轉換（檔案進、檔案出），`migrate-handoff.sh` 在它外面包鎖、備份、目標檔列舉。Stop hook、`handoff-file.sh`、`devlog-md.sh` 改成透過 access layer 讀欄位，驗證邏輯本身不動。

**Tech Stack:** bash 3.2 相容 + awk（BSD／GNU 都要能跑）、node ≥18（`node:test`）。

**Spec:** `docs/design/handoff-xml.md`（先讀完再動手）

## Global Constraints

- bash 3.2（macOS 系統 bash）：不要用 associative array、`mapfile`、`${var,,}`；`set -uo pipefail` 下空陣列展開會炸，能不用陣列就不用。
- awk 只用 POSIX 功能（`match`/`RSTART`/`RLENGTH`/`substr`/`split` 可以；`gensub`、`asort` 不行）。
- Hook 一律 fail-open：helper 本身出錯不能讓 Stop 卡死使用者；只有「確定格式不對」才 exit 2。
- 標籤名就是 key：`decisions files workspace state done-when next`（handoff）、`decisions open-questions failed-attempts`（session-handoff）。
- 標籤只有「整行」才算結構（前後空白可）；XML 區塊內不追蹤 ``` fence。
- 使用者／agent 看到的訊息用繁體中文，跟現有 hook 訊息同風格。
- 不改版號（AGENTS.md）。`.devlog/`、`docs/superpowers/` 不 commit。
- 每個 task 結束前跑該 task 的測試；Task 9 跑 AGENTS.md 的三步完整驗證。
- Commit 訊息結尾加 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。

## File Map

| 檔案 | 動作 | 責任 |
|---|---|---|
| `core/scripts/handoff-fields.sh` | 新增 | 對照表、格式偵測、取欄位、XML 檢查、模板、舊格式擋下訊息、取 section |
| `core/scripts/handoff-convert.sh` | 新增 | 舊格式 → XML 的純轉換（Round 檔、handoff.md 快照） |
| `core/scripts/migrate-handoff.sh` | 新增 | 列目標檔、上鎖、備份、呼叫轉換、輸出報告 |
| `core/scripts/enforce-devlog.sh` | 修改 | 格式閘門、XML 檢查、欄位改走 `handoff_field`、Session Handoff |
| `core/scripts/handoff-file.sh` | 修改 | `handoff.md` 寫 XML 區塊原文 |
| `core/scripts/devlog-md.sh` | 修改 | `devlog_round_workspace_body` 走 access layer |
| `core/scripts/close-open-round.sh` | 修改 | INTERRUPTED stub 寫 XML |
| `core/scripts/round-start.sh`、`segment-watch.sh` | 修改 | 訊息字樣 |
| `core/scripts/timeline-render.js` | 修改 | XML Handoff 轉小標題再渲染 |
| `core/scripts/tests/lib/xml-fixture.sh` | 新增 | 測試用：把舊格式 fixture 就地轉 XML |
| `core/scripts/tests/test-handoff-fields.sh`、`test-migrate-handoff.sh` | 新增 | |
| `commands/migrate.md` | 新增 | |
| `skills/devlog-tracker/SKILL.md`、`commands/*.md`、`cli/agents-md.js`、`README*.md` | 修改 | 文件 |

---

### Task 1: Access layer `handoff-fields.sh`

**Files:**
- Create: `core/scripts/handoff-fields.sh`
- Test: `core/scripts/tests/test-handoff-fields.sh`

**Interfaces:**
- Produces（後續 task 全部靠這些名字）：
  - `HANDOFF_KEYS`、`SESSION_HANDOFF_KEYS`（空白分隔字串）
  - `handoff_key_heading <key>` → 印中文名（不換行）；未知 key return 1
  - `handoff_section_of <round-blob> <Handoff|Session Handoff>` → 印該 `###` 標題下的內容（不含標題），fence-aware、odd fence 退化成不追蹤
  - `handoff_format <section-body>` → 印 `xml`／`md`／`none`
  - `handoff_field <section-body> <key>` → 印欄位內容；沒有就印空
  - `handoff_xml_check <section-body> <handoff|session-handoff>` → 通過 return 0；失敗 stdout 印一行中文錯誤、return 1
  - `handoff_xml_template <handoff|session-handoff>` → 印模板（含 `### ` 標題行）
  - `handoff_legacy_message <migrate-script-abs-path> <project-dir-abs>` → 印舊格式被擋時的完整訊息

- [ ] **Step 1: 寫失敗的測試** `core/scripts/tests/test-handoff-fields.sh`

```bash
#!/usr/bin/env bash
# Self-check for handoff-fields.sh (docs/design/handoff-xml.md).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../handoff-fields.sh
. "$SCRIPT_DIR/handoff-fields.sh"
FAIL=0
eq() {
  if [ "$2" = "$3" ]; then echo "PASS: $1"; else printf 'FAIL: %s\n--- expected\n%s\n--- actual\n%s\n' "$1" "$2" "$3"; FAIL=1; fi
}
check_fails() {
  local desc="$1" body="$2" kind="$3" want="$4" out
  if out="$(handoff_xml_check "$body" "$kind")"; then
    echo "FAIL: $desc (expected check to fail)"; FAIL=1; return
  fi
  case "$out" in
    *"$want"*) echo "PASS: $desc" ;;
    *) echo "FAIL: $desc (message lacks '$want': $out)"; FAIL=1 ;;
  esac
}

XML='
<handoff>
<decisions>
pick A
</decisions>
<workspace>
main @ abc1234，工作樹乾淨
</workspace>
<next>
edit `core/scripts/x.sh`
```sh
### not a heading
```
</next>
</handoff>
'
MD='
#### 決策
pick A
#### 工作區
main @ abc1234，工作樹乾淨
#### 下一步
edit `core/scripts/x.sh`
'

eq "format xml" xml "$(handoff_format "$XML")"
eq "format md" md "$(handoff_format "$MD")"
eq "format none" none "$(handoff_format 'just prose')"
eq "xml field decisions" "pick A" "$(handoff_field "$XML" decisions)"
eq "xml field workspace" "main @ abc1234，工作樹乾淨" "$(handoff_field "$XML" workspace)"
eq "xml field keeps fenced content" 'edit `core/scripts/x.sh`
```sh
### not a heading
```' "$(handoff_field "$XML" next)"
eq "xml missing field empty" "" "$(handoff_field "$XML" state)"
eq "md field workspace" "main @ abc1234，工作樹乾淨" "$(handoff_field "$MD" workspace)"
eq "md field next" 'edit `core/scripts/x.sh`' "$(handoff_field "$MD" next)"
eq "md heading exact match only" "" "$(handoff_field '#### 工作區（舊）
x' workspace)"
eq "md fenced heading ignored" "" "$(handoff_field '```
#### 工作區
fake
```' workspace)"

if handoff_xml_check "$XML" handoff >/dev/null; then echo "PASS: valid xml passes"; else echo "FAIL: valid xml"; FAIL=1; fi
check_fails "must open with tag" 'prose
<handoff>
</handoff>' handoff "<handoff>"
check_fails "text after block" '<handoff>
<state>
x
</state>
</handoff>
trailing' handoff "外面"
check_fails "unknown tag" '<handoff>
<done_when>
x
</done_when>
</handoff>' handoff "done_when"
check_fails "inline tag" '<handoff>
<next>做 X</next>
</handoff>' handoff "自己一行"
check_fails "unclosed field" '<handoff>
<state>
x
</handoff>' handoff "</state>"
check_fails "missing block close" '<handoff>
<state>
x
</state>' handoff "</handoff>"
check_fails "duplicate" '<handoff>
<state>
x
</state>
<state>
y
</state>
</handoff>' handoff "超過一次"
check_fails "order" '<handoff>
<next>
x
</next>
<state>
y
</state>
</handoff>' handoff "順序"
check_fails "empty field" '<handoff>
<state>
</state>
</handoff>' handoff "是空的"
check_fails "session requires all three" '<session-handoff>
<decisions>
- （無）
</decisions>
</session-handoff>' session-handoff "open-questions"
check_fails "session tag not allowed in handoff" '<handoff>
<open-questions>
x
</open-questions>
</handoff>' handoff "open-questions"

ROUND='## Round 1 — t

### Handoff
<handoff>
<state>
s
</state>
</handoff>

### Session Handoff
<session-handoff>
<decisions>
- d
</decisions>
</session-handoff>

### Status
DONE'
eq "section_of Handoff" "<handoff>
<state>
s
</state>
</handoff>" "$(handoff_section_of "$ROUND" Handoff | awk 'NF')"
eq "section_of Session Handoff" "<session-handoff>
<decisions>
- d
</decisions>
</session-handoff>" "$(handoff_section_of "$ROUND" 'Session Handoff' | awk 'NF')"

SKILL="$(cat "$SCRIPT_DIR/../../skills/devlog-tracker/SKILL.md")"
for kind in handoff session-handoff; do
  case "$SKILL" in
    *"$(handoff_xml_template "$kind")"*) echo "PASS: SKILL.md carries $kind template" ;;
    *) echo "FAIL: SKILL.md template for $kind differs from handoff_xml_template"; FAIL=1 ;;
  esac
done

MSG="$(handoff_legacy_message /abs/core/scripts/migrate-handoff.sh /abs/proj)"
case "$MSG" in
  *'DEVLOG_PROJECT_DIR="/abs/proj" bash "/abs/core/scripts/migrate-handoff.sh"'*) echo "PASS: legacy message has migrate command" ;;
  *) echo "FAIL: legacy message lacks migrate command: $MSG"; FAIL=1 ;;
esac
case "$MSG" in
  *"npx devlog-tracker init"*"/devlog-tracker:start"*) echo "PASS: legacy message has init/start hint" ;;
  *) echo "FAIL: legacy message lacks init/start hint"; FAIL=1 ;;
esac

[ "$FAIL" -eq 0 ] || exit 1
echo "All handoff-fields checks passed."
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `bash core/scripts/tests/test-handoff-fields.sh`
Expected: 失敗，`handoff-fields.sh: No such file or directory`。

- [ ] **Step 3: 實作** `core/scripts/handoff-fields.sh`

```bash
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
```

- [ ] **Step 4: 跑測試**

Run: `bash core/scripts/tests/test-handoff-fields.sh`
Expected: 只有兩條 `SKILL.md carries … template` FAIL（Task 7 才寫進 SKILL.md），其餘 PASS。暫時把這兩條留著失敗是刻意的：Task 7 會讓它轉綠。

- [ ] **Step 5: shellcheck + commit**

```bash
shellcheck --external-sources --source-path=SCRIPTDIR -S warning core/scripts/handoff-fields.sh core/scripts/tests/test-handoff-fields.sh
git add core/scripts/handoff-fields.sh core/scripts/tests/test-handoff-fields.sh
git commit -m "feat: add handoff-fields access layer for XML Handoff"
```

---

### Task 2: 純轉換 `handoff-convert.sh`

**Files:**
- Create: `core/scripts/handoff-convert.sh`
- Create: `core/scripts/tests/lib/xml-fixture.sh`
- Test: `core/scripts/tests/test-migrate-handoff.sh`（本 task 寫前半：轉換）

**Interfaces:**
- Consumes: `handoff_key_heading`（Task 1）
- Produces:
  - `handoff_convert_file <in> <out> <report>`：把 `<in>` 所有 Round 的舊格式 Handoff／Session Handoff 轉 XML 寫到 `<out>`；`<report>` 每行 `MIGRATED <N>` 或 `SKIP <N> <reason>`（N 是 Round 編號）。已是 XML 的 Round 不寫報告行。return 0。
  - `handoff_convert_snapshot <in> <out>`：把舊 `handoff.md`（`## Session Handoff` + `### 決策`／`### 待解問題`／`### 失敗嘗試`）轉成 `<session-handoff>` 區塊；已是 XML → 原樣複製、return 2；看不懂 → return 1、不寫 `<out>`；轉成功 return 0。
  - 測試 helper `xml_fixture <file>`：就地轉換一個 fixture 檔。

- [ ] **Step 1: 寫失敗的測試**（`core/scripts/tests/test-migrate-handoff.sh` 前半）

```bash
#!/usr/bin/env bash
# Self-check for handoff-convert.sh + migrate-handoff.sh (docs/design/handoff-xml.md).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../handoff-convert.sh
. "$SCRIPT_DIR/handoff-convert.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
eq() {
  if [ "$2" = "$3" ]; then echo "PASS: $1"; else printf 'FAIL: %s\n--- expected\n%s\n--- actual\n%s\n' "$1" "$2" "$3"; FAIL=1; fi
}

cat > "$TMP/in.md" <<'EOF'
# Project

## Round 1 — t1

### Summary
s1

### Handoff
#### 決策
pick A

#### 工作區
main @ abc1234，工作樹乾淨
#### 下一步
run `x`
```
#### 下一步
fenced, not a heading
```

### Session Handoff

#### 決策
- （無）

#### 待解問題
- q

#### 失敗嘗試
- （無）

### Status
IN_PROGRESS

## Checkpoint（Round 1-1 摘要）
### 決策
untouched

## Round 2 — t2

### Handoff
#### 自訂小節
x

### Status
DONE

## Round 3 — t3

### Handoff
<handoff>
<state>
already xml
</state>
</handoff>

### Status
DONE
EOF

cat > "$TMP/want.md" <<'EOF'
# Project

## Round 1 — t1

### Summary
s1

### Handoff
<handoff>
<decisions>
pick A
</decisions>
<workspace>
main @ abc1234，工作樹乾淨
</workspace>
<next>
run `x`
```
#### 下一步
fenced, not a heading
```
</next>
</handoff>

### Session Handoff
<session-handoff>
<decisions>
- （無）
</decisions>
<open-questions>
- q
</open-questions>
<failed-attempts>
- （無）
</failed-attempts>
</session-handoff>

### Status
IN_PROGRESS

## Checkpoint（Round 1-1 摘要）
### 決策
untouched

## Round 2 — t2

### Handoff
#### 自訂小節
x

### Status
DONE

## Round 3 — t3

### Handoff
<handoff>
<state>
already xml
</state>
</handoff>

### Status
DONE
EOF

handoff_convert_file "$TMP/in.md" "$TMP/out.md" "$TMP/report"
eq "convert output" "$(cat "$TMP/want.md")" "$(cat "$TMP/out.md")"
eq "report" "MIGRATED 1
SKIP 2 不認得的小節「#### 自訂小節」" "$(cat "$TMP/report")"

handoff_convert_file "$TMP/out.md" "$TMP/out2.md" "$TMP/report2"
eq "idempotent output" "$(cat "$TMP/out.md")" "$(cat "$TMP/out2.md")"
eq "idempotent report only repeats skip" "SKIP 2 不認得的小節「#### 自訂小節」" "$(cat "$TMP/report2")"

printf '## Round 4 — t\n\n### Handoff\n#### 現況\na\n#### 決策\nb\n' > "$TMP/order.md"
handoff_convert_file "$TMP/order.md" "$TMP/order.out" "$TMP/order.rep"
eq "bad order untouched" "$(cat "$TMP/order.md")" "$(cat "$TMP/order.out")"
case "$(cat "$TMP/order.rep")" in SKIP\ 4\ *) echo "PASS: bad order reported" ;; *) echo "FAIL: bad order report"; FAIL=1 ;; esac

printf '## Round 5 — t\n\n### Handoff\n#### 現況\n```\nunclosed\n' > "$TMP/fence.md"
handoff_convert_file "$TMP/fence.md" "$TMP/fence.out" "$TMP/fence.rep"
eq "odd fence untouched" "$(cat "$TMP/fence.md")" "$(cat "$TMP/fence.out")"

printf '## Session Handoff\n\n### 決策\n- a\n\n### 待解問題\n- b\n\n### 失敗嘗試\n- （無）\n' > "$TMP/h.md"
handoff_convert_snapshot "$TMP/h.md" "$TMP/h.out"; RC=$?
eq "snapshot rc" 0 "$RC"
eq "snapshot xml" "<session-handoff>
<decisions>
- a
</decisions>
<open-questions>
- b
</open-questions>
<failed-attempts>
- （無）
</failed-attempts>
</session-handoff>" "$(cat "$TMP/h.out")"
handoff_convert_snapshot "$TMP/h.out" "$TMP/h.out2"; RC=$?
eq "snapshot already xml rc" 2 "$RC"

# ---- migrate-handoff.sh (Task 3 appends below this line) ----

[ "$FAIL" -eq 0 ] || exit 1
echo "All migrate-handoff checks passed."
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `bash core/scripts/tests/test-migrate-handoff.sh`
Expected: `handoff-convert.sh: No such file or directory`。

- [ ] **Step 3: 實作** `core/scripts/handoff-convert.sh`

規則（與 spec「Migrate」一致）：Round = `## Round <N>` 起、到下一個 fence 外的 `## ` 止；整輪緩衝，轉換任一 section 失敗就整輪原樣輸出並報 SKIP。section = fence 外的 `### Handoff`／`### Session Handoff` 到下一個 fence 外 `### `／`## `。

```bash
#!/usr/bin/env bash
# Sourced helper: legacy `#### ` Handoff → line-based XML. Pure file-in /
# file-out; locking, backups and target discovery live in
# migrate-handoff.sh. Converts history as-is: never validates, fills or
# drops fields; a round it cannot map exactly is left byte-for-byte.
# docs/design/handoff-xml.md「Migrate」.

_HANDOFF_CONVERT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=handoff-fields.sh
. "$_HANDOFF_CONVERT_DIR/handoff-fields.sh"

_handoff_convert_awk() {
  # Heading → tag tables are generated from handoff-fields.sh so the map
  # lives in one place.
  local hmap="" smap="" k
  for k in $HANDOFF_KEYS; do hmap="$hmap $(handoff_key_heading "$k")=$k"; done
  for k in $SESSION_HANDOFF_KEYS; do smap="$smap $(handoff_key_heading "$k")=$k"; done
  awk -v hmap="$hmap" -v smap="$smap" -v report="$1" '
    function load(map, dst,   n, i, p, kv) {
      n = split(map, p, " ")
      for (i = 1; i <= n; i++) { split(p[i], kv, "="); dst[kv[1]] = kv[2]; dst["#" kv[1]] = i }
    }
    BEGIN { load(hmap, H); load(smap, S) }
    function emit_round(   i) { for (i = 1; i <= rn; i++) print rl[i] }
    # Converts section lines sl[a..b] (after the ### heading) into out[];
    # returns "" on success or a reason.
    function conv(a, b, sess,   i, t, name, key, idx, last, fences, lead, nf, j, e, open) {
      fences = 0
      for (i = a; i <= b; i++) if (rl[i] ~ /^[ \t]*```/) fences++
      if (fences % 2) return "fence 沒有成對"
      for (i = a; i <= b; i++) if (rl[i] ~ /[^ \t]/) break
      t = rl[i]; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
      if (i > b) return "EMPTY"
      if (t == "<handoff>" || t == "<session-handoff>") return "XML"
      on = 0; nf = 0; last = 0; fence = 0; delete seen
      for (i = a; i <= b; i++) {
        if (rl[i] ~ /^[ \t]*```/) fence = !fence
        else if (!fence && rl[i] ~ /^#### /) {
          name = rl[i]; sub(/^#### [ \t]*/, "", name); sub(/[ \t]+$/, "", name)
          key = sess ? S[name] : H[name]
          idx = sess ? S["#" name] : H["#" name]
          if (key == "") return "不認得的小節「#### " name "」"
          if (seen[key]) return "小節「#### " name "」重複"
          if (idx < last) return "小節順序不對（#### " name "）"
          seen[key] = 1; last = idx
          nf++; fk[nf] = key; fs[nf] = i + 1; fe[nf - 1] = i - 1
          continue
        }
        if (nf == 0 && rl[i] ~ /[^ \t]/) return "第一個 #### 小節前面有內容"
      }
      if (nf == 0) return "沒有 #### 小節"
      fe[nf] = b
      on = 0
      out[++on] = sess ? "<session-handoff>" : "<handoff>"
      for (j = 1; j <= nf; j++) {
        e = fe[j]
        while (e >= fs[j] && rl[e] !~ /[^ \t]/) e--
        s = fs[j]
        while (s <= e && rl[s] !~ /[^ \t]/) s++
        out[++on] = "<" fk[j] ">"
        for (i = s; i <= e; i++) out[++on] = rl[i]
        out[++on] = "</" fk[j] ">"
      }
      out[++on] = sess ? "</session-handoff>" : "</handoff>"
      return ""
    }
    function flush(   i, t, sec, sa, sb, r, conv_any, k, trail, m) {
      if (rn == 0) return
      if (!inround) { emit_round(); rn = 0; return }
      # locate sections
      ns = 0; fence = 0
      for (i = 1; i <= rn; i++) {
        if (rl[i] ~ /^[ \t]*```/) { fence = !fence; continue }
        if (fence) continue
        t = rl[i]; sub(/[ \t]+$/, "", t)
        if (rl[i] ~ /^### /) {
          if (ns && !se[ns]) se[ns] = i - 1
          if (t == "### Handoff" || t == "### Session Handoff") { ns++; sh[ns] = i; ss[ns] = (t == "### Session Handoff"); se[ns] = 0 }
        }
      }
      if (ns && !se[ns]) se[ns] = rn
      conv_any = 0; m = 0
      for (k = 1; k <= ns; k++) {
        # keep trailing blank lines of the section outside the tag block
        sb = se[k]; while (sb > sh[k] && rl[sb] !~ /[^ \t]/) sb--
        r = conv(sh[k] + 1, sb, ss[k])
        if (r == "XML" || r == "EMPTY") { cstart[k] = 0; continue }
        if (r != "") { print "SKIP " roundno " " r > report; emit_round(); rn = 0; return }
        cstart[k] = sh[k]; cend[k] = sb; conv_any = 1
        cn[k] = on; for (i = 1; i <= on; i++) cl[k, i] = out[i]
      }
      for (i = 1; i <= rn; i++) {
        for (k = 1; k <= ns; k++) if (cstart[k] && i == cstart[k] + 1) {
          for (m = 1; m <= cn[k]; m++) print cl[k, m]
          i = cend[k]; break
        }
        if (k <= ns && cstart[k] && i == cend[k]) continue
        print rl[i]
      }
      if (conv_any) print "MIGRATED " roundno > report
      rn = 0; delete cstart
    }
    {
      if ($0 ~ /^[ \t]*```/) gfence = !gfence
      if (!gfence && $0 ~ /^## /) {
        flush()
        inround = ($0 ~ /^## Round [0-9]+/)
        if (inround) { roundno = $0; sub(/^## Round /, "", roundno); sub(/[^0-9].*$/, "", roundno) }
      }
      rl[++rn] = $0
    }
    END { flush() }
  '
}

handoff_convert_file() {
  local in="$1" out="$2" report="$3"
  : > "$report"
  _handoff_convert_awk "$report" < "$in" > "$out"
}

handoff_convert_snapshot() {
  local in="$1" out="$2" first
  first="$(awk 'NF { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, ""); print; exit }' "$in")"
  if [ "$first" = "<session-handoff>" ]; then cp "$in" "$out"; return 2; fi
  [ "$first" = "## Session Handoff" ] || return 1
  awk '
    function tagof(n) { return n == "決策" ? "decisions" : n == "待解問題" ? "open-questions" : n == "失敗嘗試" ? "failed-attempts" : "" }
    function close_field(   e, s, i) {
      if (cur == "") return
      e = n; while (e > 0 && buf[e] !~ /[^ \t]/) e--
      s = 1; while (s <= e && buf[s] !~ /[^ \t]/) s++
      print "<" cur ">"; for (i = s; i <= e; i++) print buf[i]; print "</" cur ">"
      cur = ""; n = 0
    }
    BEGIN { print "<session-handoff>"; want = "decisions open-questions failed-attempts"; split(want, w, " "); wi = 1 }
    /^## Session Handoff[ \t]*$/ { next }
    /^### / {
      name = $0; sub(/^### [ \t]*/, "", name); sub(/[ \t]+$/, "", name)
      close_field(); cur = tagof(name)
      if (cur != w[wi]) { bad = 1; exit }
      wi++; next
    }
    { if (cur == "") { if ($0 ~ /[^ \t]/) { bad = 1; exit } ; next } buf[++n] = $0 }
    END { if (bad || wi != 4) exit 1; close_field(); print "</session-handoff>" }
  ' "$in" > "$out.tmp" || { rm -f "$out.tmp"; return 1; }
  mv "$out.tmp" "$out"
}
```

> 實作者注意：上面 `flush()` 的「整段替換」迴圈是最容易寫錯的地方。只要 Step 4 的 `convert output` 期望檔比對不過，就用 `diff <(cat "$TMP/want.md") "$TMP/out.md"` 看差異修到一致；期望檔是規格，不要改期望檔去遷就實作（除非發現期望檔違反 spec）。

`core/scripts/tests/lib/xml-fixture.sh`：

```bash
#!/usr/bin/env bash
# Test helper: convert a legacy-format fixture file to XML in place.
_XML_FIXTURE_DIR="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)"
# shellcheck source=../../handoff-convert.sh
. "$_XML_FIXTURE_DIR/handoff-convert.sh"
xml_fixture() {
  local f="$1"
  handoff_convert_file "$f" "$f.xml" "$f.xmlrep" && mv "$f.xml" "$f"
  rm -f "$f.xmlrep"
}
```

- [ ] **Step 4: 跑測試**

Run: `bash core/scripts/tests/test-migrate-handoff.sh`
Expected: 全部 PASS。

- [ ] **Step 5: shellcheck + commit**

```bash
shellcheck --external-sources --source-path=SCRIPTDIR -S warning core/scripts/handoff-convert.sh core/scripts/tests/test-migrate-handoff.sh core/scripts/tests/lib/xml-fixture.sh
git add core/scripts/handoff-convert.sh core/scripts/tests/lib/xml-fixture.sh core/scripts/tests/test-migrate-handoff.sh
git commit -m "feat: add legacy Handoff to XML converter"
```

---

### Task 3: `migrate-handoff.sh` 與 `/devlog-tracker:migrate`

**Files:**
- Create: `core/scripts/migrate-handoff.sh`、`commands/migrate.md`
- Modify: `cli/agents-md.js`（Codex 對照表加一列）、`cli/agents-md.test.js`（若它逐列比對）
- Test: `core/scripts/tests/test-migrate-handoff.sh`（後半）

**Interfaces:**
- Consumes: `handoff_convert_file`、`handoff_convert_snapshot`（Task 2）；`devlog_lock_acquire`／`devlog_lock_release`（`devlog-lock.sh`）
- Produces: 指令 `DEVLOG_PROJECT_DIR=<abs> bash core/scripts/migrate-handoff.sh`；stdout：
  - `MIGRATED=<總輪數>`
  - `SKIPPED=<總輪數>`
  - 每筆 `SKIP <檔名> Round <N>: <reason>`
  - 每個改動檔 `BACKUP=<路徑>`
  - `.devlog/` 不存在 → 印 `NO_DEVLOG`、exit 1。lock 被別的 session 拿著 → 印 `LOCKED <pid>`、exit 1。

目標檔：`$DEVLOG_DIR/.round-current.md`、`$DEVLOG_DIR/devlog.md`、有 `<!-- devlog-origin:` 首行的 `devlog.*.md`（branch 檔）、`$DEVLOG_DIR/handoff.md` 與 `handoff.*.md`。不碰 `devlog.archive.md`、沒有 origin 首行的 `devlog.<name>.md`（keep 檔）、`devlog.lessons.*.md`。

- [ ] **Step 1: 在 test-migrate-handoff.sh 的 `# ---- migrate-handoff.sh` 標記下方加測試**

```bash
P="$TMP/proj"; D="$P/.devlog"; mkdir -p "$D"
cp "$TMP/in.md" "$D/devlog.md"
{ printf '<!-- devlog-origin: branch=feat/x -->\n\n'; cat "$TMP/in.md"; } > "$D/devlog.feat-x.md"
cp "$TMP/in.md" "$D/devlog.archive.md"
cp "$TMP/in.md" "$D/devlog.mytopic.md"
cp "$TMP/h.md" "$D/handoff.md"
OUT="$(DEVLOG_PROJECT_DIR="$P" bash "$SCRIPT_DIR/migrate-handoff.sh")"; RC=$?
eq "migrate rc" 0 "$RC"
case "$OUT" in *"MIGRATED=2"*) echo "PASS: migrated count (main + branch)" ;; *) echo "FAIL: migrated count: $OUT"; FAIL=1 ;; esac
case "$OUT" in *"SKIP devlog.md Round 2: "*) echo "PASS: skip line" ;; *) echo "FAIL: skip line: $OUT"; FAIL=1 ;; esac
eq "main converted" "$(cat "$TMP/want.md")" "$(cat "$D/devlog.md")"
eq "backup kept original" "$(cat "$TMP/in.md")" "$(cat "$D/devlog.md.pre-migrate")"
grep -q '^<handoff>$' "$D/devlog.feat-x.md" && echo "PASS: branch file converted" || { echo "FAIL: branch file"; FAIL=1; }
eq "archive untouched" "$(cat "$TMP/in.md")" "$(cat "$D/devlog.archive.md")"
eq "keep file untouched" "$(cat "$TMP/in.md")" "$(cat "$D/devlog.mytopic.md")"
grep -q '^<session-handoff>$' "$D/handoff.md" && echo "PASS: handoff.md converted" || { echo "FAIL: handoff.md"; FAIL=1; }
OUT2="$(DEVLOG_PROJECT_DIR="$P" bash "$SCRIPT_DIR/migrate-handoff.sh")"
case "$OUT2" in *"MIGRATED=0"*) echo "PASS: second run migrates nothing" ;; *) echo "FAIL: second run: $OUT2"; FAIL=1 ;; esac
[ ! -d "$D/.lock" ] && echo "PASS: lock released" || { echo "FAIL: lock left behind"; FAIL=1; }
OUT3="$(DEVLOG_PROJECT_DIR="$TMP/nope" bash "$SCRIPT_DIR/migrate-handoff.sh")"; RC=$?
eq "no devlog rc" 1 "$RC"
eq "no devlog out" "NO_DEVLOG" "$OUT3"
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `bash core/scripts/tests/test-migrate-handoff.sh`
Expected: `migrate-handoff.sh: No such file or directory`。

- [ ] **Step 3: 實作** `core/scripts/migrate-handoff.sh`

```bash
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
```

注意 `for f in "$DEVLOG_DIR"/devlog.*.md` 在沒有檔案時會展開成字面字串；`[ -s "$f" ] || continue` 已經擋住。`handoff.*.md` 會吃到 `handoff.md.pre-migrate`？不會（副檔名是 `.pre-migrate`）。

`commands/migrate.md`：

````markdown
---
description: 把 .devlog 裡舊格式（#### 小節）的 Handoff／Session Handoff 轉成 XML 標籤格式；Stop hook 擋下舊格式時也會叫 agent 跑它
---

請執行 Handoff 格式遷移：

1. 決定 plugin 根目錄（有 `DEVLOG_TRACKER_ROOT` 用它；否則用 `CLAUDE_PLUGIN_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄），然後跑（不要自己改檔）：
   ```bash
   PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
   DEVLOG_PROJECT_DIR="<專案根目錄絕對路徑，不要用 $(pwd) 重新推>" bash "${PLUGIN_ROOT}/core/scripts/migrate-handoff.sh"
   ```
2. 依 stdout 回報一句話：
   - `NO_DEVLOG`：這個專案沒有 `.devlog/`，沒有東西要轉。
   - `LOCKED <pid>`：另一個 session 正在寫 devlog，稍後再跑一次。
   - 否則用 `MIGRATED=` 與 `SKIPPED=` 回報轉了幾輪、跳過幾輪；`BACKUP=` 是轉換前的備份。
3. 有 `SKIP ... Round <N>: <原因>` 時：歷史輪次保留原樣即可（讀取端相容舊格式）。只有**這一輪**（開著的 `.round-current.md`）被跳過時，才照 `skills/devlog-tracker/SKILL.md`「每一輪的紀錄格式」的 XML 模板手動改寫這一輪的 Handoff／Session Handoff。

只轉 `.round-current.md`、`devlog.md`、branch 檔（首行是 `<!-- devlog-origin: ... -->`）與 `handoff*.md`；不轉 `devlog.archive.md`、keep 產生的具名檔、lessons 檔。
````

`cli/agents-md.js` 的對照表，在 `| 清空重編 / clean …` 那列下面加：

```
| 舊格式 Handoff 轉 XML / migrate（Stop hook 擋下舊格式時直接跑） | \`commands/migrate.md\` |
```

- [ ] **Step 4: 跑測試**

Run: `bash core/scripts/tests/test-migrate-handoff.sh && node --test cli/agents-md.test.js cli/skills-from-commands.test.js`
Expected: 全部 PASS。若 node 測試有寫死指令數量或對照表內容，照新增的 migrate 更新測試期望值。

- [ ] **Step 5: shellcheck + commit**

```bash
shellcheck --external-sources --source-path=SCRIPTDIR -S warning core/scripts/migrate-handoff.sh core/scripts/tests/test-migrate-handoff.sh
git add core/scripts/migrate-handoff.sh commands/migrate.md cli/agents-md.js cli/*.test.js core/scripts/tests/test-migrate-handoff.sh
git commit -m "feat: add /devlog-tracker:migrate for legacy Handoff"
```

---

### Task 4: Stop hook — `### Handoff` 只收 XML

**Files:**
- Modify: `core/scripts/enforce-devlog.sh`（source 區、約 237–410 行的 order check／欄位檢查／工作區／檔案）
- Modify tests: `core/scripts/tests/test-enforce-devlog.sh`、`test-enforce-devlog-handoff-order.sh`、`test-enforce-devlog-workspace.sh`、`test-enforce-devlog-files.sh`、`cursor/hooks/test-adapters.sh`、`codex/hooks/test-adapters.sh`，以及任何跑 `enforce-devlog.sh` 期待 exit 0 的測試

**Interfaces:**
- Consumes: `handoff_section_of`、`handoff_format`、`handoff_field`、`handoff_xml_check`、`handoff_xml_template`、`handoff_legacy_message`（Task 1）；`xml_fixture`（Task 2）

- [ ] **Step 1: 新增失敗的測試**（加在 `test-enforce-devlog-handoff-order.sh` 尾端 `FAIL` 判斷之前；沿用該檔已有的 round-start／fixture 寫法與 `assert_exit`）

```bash
# --- XML gate (docs/design/handoff-xml.md) ---
write_handoff_round() {  # $1 = Handoff body lines (already formatted)
  {
    echo "## Round 1 — 2026-09-26T00:00:00+08:00"
    echo ""
    echo "### Summary"; echo "s"; echo ""
    echo "### Reply"; echo "r"; echo ""
    echo "### Handoff"
    printf '%s\n' "$1"
    echo ""
    echo "### Status"; echo "DONE"
  } > "$DEVLOG_DIR/.round-current.md"
}

bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_handoff_round '#### 現況
legacy'
MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "legacy Handoff blocked" 2 $?
case "$MSG" in
  *"migrate-handoff.sh"*"<handoff>"*"npx devlog-tracker init"*) echo "PASS: legacy message has migrate, template, init hint" ;;
  *) echo "FAIL: legacy message: $MSG"; FAIL=1 ;;
esac

bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_handoff_round '<handoff>
<state>
ok
</state>
</handoff>'
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "XML Handoff DONE passes" 0 $?

bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_handoff_round '<handoff>
<next>
x
</next>
<state>
y
</state>
</handoff>'
MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "XML order violation blocked" 2 $?
case "$MSG" in *"順序"*"### Handoff"*"<handoff>"*) echo "PASS: order message + template" ;; *) echo "FAIL: order msg: $MSG"; FAIL=1 ;; esac

bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_handoff_round '<handoff>
<state>
y
</state>'
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "unclosed handoff blocked" 2 $?
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `bash core/scripts/tests/test-enforce-devlog-handoff-order.sh`
Expected: 新增的 4 條中，`legacy Handoff blocked`、`order violation`（期待訊息）、`unclosed` FAIL（目前舊實作會放行或訊息不同）。

- [ ] **Step 3: 改 `enforce-devlog.sh`**

3a. source 區（`. "$SCRIPT_DIR/handoff-file.sh"` 下面）加：

```bash
# shellcheck source=handoff-fields.sh
. "$SCRIPT_DIR/handoff-fields.sh"
```

3b. 刪掉 `handoff_subsection_body()` 整個函式定義。

3c. 把從 `# --- Handoff subsection order check` 到 `esac; exit 2; fi`（ORDER_ERR 區塊結束）整段換成：

```bash
  # --- Handoff format gate (docs/design/handoff-xml.md): the round Stop
  # validates must use the XML form; legacy `#### ` rounds are history only.
  HANDOFF_BODY="$(section_body '^### Handoff')"
  if [ "$(handoff_format "$HANDOFF_BODY")" = "md" ]; then
    handoff_legacy_message "$SCRIPT_DIR/migrate-handoff.sh" "$(cd "$PROJECT_DIR" 2>/dev/null && pwd || printf '%s' "$PROJECT_DIR")" >&2
    exit 2
  fi
  if ! HANDOFF_ERR="$(handoff_xml_check "$HANDOFF_BODY" handoff)"; then
    {
      echo "Handoff 格式不對：${HANDOFF_ERR}"
      echo ""
      echo "正確格式（標籤自己一行、沒有的欄位整個省略）："
      handoff_xml_template handoff
    } >&2
    exit 2
  fi
  hf() { handoff_field "$HANDOFF_BODY" "$1"; }
```

3d. 欄位檢查逐一替換（邏輯不變，只換取值來源與訊息字樣）：

| 原本 | 改成 |
|---|---|
| `HAS_DONE_CRITERIA` 兩段（grep `^#### 完成條件` + `handoff_subsection_body '^#### 完成條件'`） | `DONE_CRITERIA_OK=0; hf done-when \| grep -q '[^[:space:]]' && DONE_CRITERIA_OK=1` |
| 訊息「Handoff 必須有「#### 完成條件」…」 | 「Handoff 必須有 `<done-when>`（完成條件）且裡面有內容（可觀察的做完判準）。」 |
| `HAS_NEXT` 兩段 | `NEXT_OK=0; hf next \| grep -q '[^[:space:]]' && NEXT_OK=1` |
| 訊息「必須有「#### 下一步」…」 | 「Handoff 必須有 `<next>`（下一步）且裡面有內容。」 |
| `NEXT_BODY_TRIMMED="$(handoff_subsection_body '^#### 下一步' \` | `NEXT_BODY_TRIMMED="$(hf next \` |
| 黑名單、IN_PROGRESS 訊息裡的「#### 下一步」 | 「`<next>`（下一步）」 |
| BLOCKED：`handoff_subsection_body '^#### 現況'`／`'^#### 下一步'` | `hf state`／`hf next`；訊息改「`<state>`（現況）或 `<next>`（下一步）」 |
| `DONE)` 分支：`handoff_subsection_body '^#### 檔案'` | `hf files` |
| `ACTUAL_WS="$(handoff_subsection_body '^#### 工作區' \| …)"` | `ACTUAL_WS="$(hf workspace \| sed -e '/^[[:space:]]*$/d')"` |
| 訊息「#### 工作區 跟目前 git 狀態不符…請把這一節內容換成」 | 「`<workspace>`（工作區）跟目前 git 狀態不符（或缺漏）。請把 `<workspace>` 裡的內容換成以下逐字內容：」 |
| `FILES_BODY="$(handoff_subsection_body '^#### 檔案')"` | `FILES_BODY="$(hf files)"` |
| `FILES_ERR` 訊息裡的「#### 檔案」與「「#### 檔案」裡不該有」 | 「`<files>`（檔案）」 |

改完 `grep -n 'handoff_subsection_body\|#### ' core/scripts/enforce-devlog.sh` 應該只剩註解（Session Handoff 那段 Task 5 處理）。

- [ ] **Step 4: 轉換既有 fixture**

跑 `bash core/scripts/run-tests.sh 2>&1 | grep -E '^(===|FAIL)'`，把失敗的測試逐一處理：
- 測的是**舊格式本身被擋以外的行為**（大多數）：在 fixture 寫進 `.round-current.md` 之後、跑 `enforce-devlog.sh` 之前，加一行 `xml_fixture "$DEVLOG_DIR/.round-current.md"`，並在檔頭 source：
  ```bash
  # shellcheck source=lib/xml-fixture.sh
  . "$SCRIPT_DIR/tests/lib/xml-fixture.sh"
  ```
  （`SCRIPT_DIR` 在這些測試裡指向 `core/scripts`；cursor／codex 的 `test-adapters.sh` 用它們自己算出的 core scripts 路徑。）有 `write_*` helper 的檔，把這行加在 helper 結尾一次即可。
- 測的是**順序錯／重複／看不懂的小節**（`test-enforce-devlog-handoff-order.sh` 既有案例）：converter 會跳過這些輪次，所以不能用 `xml_fixture`；改寫成直接寫 XML fixture，期待訊息改成 Step 3c 的新訊息（「順序」「超過一次」「不認得的標籤」）。舊的「未知 `####` 小節被忽略」案例刪掉（spec 規則 6：XML 下未知標籤一律擋）。
- 斷言訊息含「#### 工作區」「#### 檔案」「#### 下一步」的：改成 3d 表格的新字樣。
- 保留 `test-enforce-devlog.sh` 裡最少一個舊格式 fixture，斷言 exit 2 + 訊息含 `migrate-handoff.sh`（Step 1 已涵蓋，不用再加）。

- [ ] **Step 5: 跑測試**

Run: `bash core/scripts/run-tests.sh`
Expected: 除 `test-handoff-fields.sh` 的兩條 SKILL 模板檢查（Task 7 修）與 Session Handoff 相關（Task 5 修）外全部 PASS。記下仍失敗的檔名，在 Task 5 結束時必須清零。

- [ ] **Step 6: shellcheck + commit**

```bash
shellcheck --external-sources --source-path=SCRIPTDIR -S warning core/scripts/*.sh core/scripts/tests/*.sh cursor/hooks/*.sh codex/hooks/*.sh
git add -A core/scripts cursor/hooks codex/hooks
git commit -m "feat: require XML Handoff in Stop hook"
```

---

### Task 5: Session Handoff 與 `handoff.md`

**Files:**
- Modify: `core/scripts/enforce-devlog.sh`（`# Session Handoff → .devlog/handoff.md` 那段）
- Modify: `core/scripts/handoff-file.sh`
- Modify tests: `core/scripts/tests/test-handoff-file.sh`、`test-enforce-devlog-session-handoff.sh`、`test-session-start-devlog.sh`

**Interfaces:**
- Consumes: Task 1 全部
- Produces: `handoff_write <path> <round-blob>`（簽名不變；寫入內容改為 `<session-handoff>` 區塊原文）、`handoff_clear`（不變）。移除 `handoff_session_section_ok`、`handoff_extract_file_body`、`_handoff_nofence_flag`（先 `grep -rn` 確認沒有其他呼叫者）。

- [ ] **Step 1: 改測試成新期望**

`test-handoff-file.sh`：`GOOD_ROUND` 的 Handoff 與 Session Handoff 改成 XML：

```bash
### Handoff
<handoff>
<state>
c
</state>
<done-when>
done when tests pass
</done-when>
<next>
edit core/scripts/handoff-file.sh
</next>
</handoff>

### Session Handoff
<session-handoff>
<decisions>
- pick route A
</decisions>
<open-questions>
- （無）
</open-questions>
<failed-attempts>
- tried parse-in-place
</failed-attempts>
</session-handoff>
```

並把「寫出的 handoff.md」期望改成恰好等於：

```
<session-handoff>
<decisions>
- pick route A
</decisions>
<open-questions>
- （無）
</open-questions>
<failed-attempts>
- tried parse-in-place
</failed-attempts>
</session-handoff>
```

`BAD_ORDER`／`MISSING` 改成對應的 XML（`<open-questions>` 在 `<decisions>` 前；只有 `<decisions>`），斷言 `handoff_write` return 非 0 且不產生檔案。刪掉直接呼叫 `handoff_session_section_ok`／`handoff_extract_file_body` 的案例。

`test-enforce-devlog-session-handoff.sh`：`write_unfinished` 結尾加 `xml_fixture "$DEVLOG_DIR/.round-current.md"`（source 方式同 Task 4 Step 4）；斷言 `grep -q '^## Session Handoff' handoff.md` 改成 `grep -q '^<session-handoff>$'`；「缺 Session Handoff 被擋」的訊息斷言改成含 `<session-handoff>`。另加一案：

```bash
# legacy Session Handoff under an XML Handoff -> blocked with migrate hint
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_unfinished IN_PROGRESS "$SESSION_OK"
xml_fixture "$DEVLOG_DIR/.round-current.md"
# re-inject a legacy Session Handoff after conversion
awk '/^### Session Handoff/{skip=1; print "### Session Handoff\n#### 決策\n- x\n#### 待解問題\n- y\n#### 失敗嘗試\n- z\n"; next} skip && /^### /{skip=0} !skip' \
  "$DEVLOG_DIR/.round-current.md" > "$DEVLOG_DIR/.rc" && mv "$DEVLOG_DIR/.rc" "$DEVLOG_DIR/.round-current.md"
MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "legacy Session Handoff blocked" 2 $?
case "$MSG" in *"migrate-handoff.sh"*) echo "PASS: legacy session message" ;; *) echo "FAIL: $MSG"; FAIL=1 ;; esac
```

`test-session-start-devlog.sh`：加一案，`devlog.md` 最後一輪用 XML Handoff、`handoff.md` 是 XML 區塊，斷言 SessionStart 輸出同時含 `<next>` 那一行的內容與 `<session-handoff>`。

- [ ] **Step 2: 跑測試確認失敗**

Run: `bash core/scripts/tests/test-handoff-file.sh; bash core/scripts/tests/test-enforce-devlog-session-handoff.sh`
Expected: 新期望 FAIL（目前仍寫 `## Session Handoff` Markdown）。

- [ ] **Step 3: 實作**

`handoff-file.sh` 整份換成：

```bash
#!/usr/bin/env bash
# Sourced helper: write / clear the Session Handoff file. Content is the
# round's <session-handoff> block verbatim (docs/design/handoff-xml.md,
# docs/design/session-handoff-file.md).

_HANDOFF_FILE_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=handoff-fields.sh
. "$_HANDOFF_FILE_DIR/handoff-fields.sh"

# Prints the trimmed <session-handoff> block of Round blob $1; exit 1 when
# absent or invalid.
handoff_session_block() {
  local body
  body="$(handoff_section_of "$1" 'Session Handoff' | awk '
    { l[NR] = $0 } NF && !s { s = NR } NF { e = NR }
    END { for (i = s; s && i <= e; i++) print l[i] }
  ')"
  [ -n "$body" ] || return 1
  [ "$(handoff_format "$body")" = xml ] || return 1
  handoff_xml_check "$body" session-handoff >/dev/null || return 1
  printf '%s\n' "$body"
}

handoff_write() {
  local path="$1" blob="$2" dir tmp body
  body="$(handoff_session_block "$blob")" || return 1
  dir="$(dirname "$path")"
  mkdir -p "$dir" 2>/dev/null || true
  tmp="$(mktemp "$dir/.handoff.XXXXXX")" || return 1
  printf '%s\n' "$body" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$path" || { rm -f "$tmp"; return 1; }
  return 0
}

handoff_clear() {
  rm -f "$1"
}
```

`enforce-devlog.sh` 的 Session Handoff 段整段換成（位置不變，仍在所有 IN_PROGRESS／BLOCKED 檢查之後）：

```bash
  # Session Handoff → .devlog/handoff.md（docs/design/session-handoff-file.md,
  # docs/design/handoff-xml.md）。Present in any status → must be XML;
  # required for IN_PROGRESS／BLOCKED.
  SESSION_BODY="$(section_body '^### Session Handoff')"
  HAS_SESSION=0
  printf '%s\n' "$LAST_ROUND" | grep -q '^### Session Handoff' && HAS_SESSION=1
  if [ "$HAS_SESSION" -eq 1 ] && [ "$(handoff_format "$SESSION_BODY")" = "md" ]; then
    handoff_legacy_message "$SCRIPT_DIR/migrate-handoff.sh" "$(cd "$PROJECT_DIR" 2>/dev/null && pwd || printf '%s' "$PROJECT_DIR")" >&2
    exit 2
  fi
  NEED_SESSION=0
  case "$STATUS_VAL" in IN_PROGRESS|BLOCKED) NEED_SESSION=1 ;; esac
  if [ "$HAS_SESSION" -eq 1 ] || [ "$NEED_SESSION" -eq 1 ]; then
    if [ "$HAS_SESSION" -eq 0 ]; then
      SESSION_ERR="缺少 ### Session Handoff（Status 是 IN_PROGRESS 或 BLOCKED 時必寫）"
    elif SESSION_ERR="$(handoff_xml_check "$SESSION_BODY" session-handoff)"; then
      SESSION_ERR=""
    fi
    if [ -n "$SESSION_ERR" ]; then
      {
        echo "Session Handoff 格式不對：${SESSION_ERR}"
        echo ""
        echo "正確格式（三個標籤都要有，沒有內容就寫 - （無））。寫完後 hook 會覆寫 .devlog/handoff.md 給下一 session："
        handoff_xml_template session-handoff
      } >&2
      exit 2
    fi
  fi
```

- [ ] **Step 4: 跑測試**

Run: `bash core/scripts/run-tests.sh`
Expected: 只剩 `test-handoff-fields.sh` 的 SKILL 模板兩條 FAIL（Task 7）。Task 4 記下的失敗此時必須全部清零。

- [ ] **Step 5: shellcheck + commit**

```bash
shellcheck --external-sources --source-path=SCRIPTDIR -S warning core/scripts/*.sh core/scripts/tests/*.sh cursor/hooks/*.sh codex/hooks/*.sh
git add -A core/scripts
git commit -m "feat: XML Session Handoff and verbatim handoff.md"
```

---

### Task 6: 讀取端（工作區漂移、INTERRUPTED stub、timeline）

**Files:**
- Modify: `core/scripts/devlog-md.sh`（`devlog_round_workspace_body`、檔頭 source）
- Modify: `core/scripts/round-start.sh:168`、`core/scripts/segment-watch.sh:106`（訊息）
- Modify: `core/scripts/close-open-round.sh`（兩處 `print "#### 現況"`）
- Modify: `core/scripts/timeline-render.js`、`core/scripts/timeline-render.test.js`
- Modify tests: `test-devlog-md.sh`、`test-round-start.sh`、`test-segment-watch.sh`、`test-close-open-round.sh`

**Interfaces:**
- Consumes: `handoff_section_of`、`handoff_field`（Task 1）
- Produces: `devlog_round_workspace_body <file> <start> <end>`（簽名不變，新舊格式都讀）；JS `handoffToMarkdown(text)`、`HANDOFF_FIELDS`（由 `module.exports` 匯出）

- [ ] **Step 1: 寫失敗的測試**

`test-devlog-md.sh` 加（沿用該檔的 assert helper；若沒有就用 Task 1 的 `eq` 寫法）：

```bash
F="$TMP/xmlws.md"
cat > "$F" <<'EOF'
## Round 1 — t

### Handoff
<handoff>
<workspace>
main @ abc1234
未提交：a.txt
</workspace>
<next>
x
</next>
</handoff>

### Status
IN_PROGRESS
EOF
eq "workspace body from XML" "main @ abc1234
未提交：a.txt" "$(devlog_round_workspace_body "$F" 1 "$(wc -l < "$F" | tr -d ' ')")"
```

（舊格式的既有案例保留，證明相容。）

`test-round-start.sh`：複製一個既有「上一輪工作區 MISMATCH → 注入說明」案例，把 fixture 的 Handoff 改成 XML（可用 `xml_fixture` 轉 devlog.md），斷言同樣注入；把斷言訊息字樣「#### 工作區」改成「工作區（<workspace>」。

`test-close-open-round.sh:91`：`assert_contains "handoff stub heading" "#### 現況" "$BODY"` 改成 `assert_contains "handoff stub block" "<state>" "$BODY"`，並加 `assert_contains "handoff stub open" "<handoff>" "$BODY"`。

`timeline-render.test.js` 加：

```js
const { handoffToMarkdown, HANDOFF_FIELDS } = require('./timeline-render');

test('handoffToMarkdown turns XML fields into headings and drops block tags', () => {
  const md = handoffToMarkdown('<handoff>\n<state>\nok\n</state>\n<next>\nrun `x`\n</next>\n</handoff>');
  assert.equal(md, '#### 現況\nok\n#### 下一步\nrun `x`');
});

test('handoffToMarkdown leaves legacy Handoff untouched', () => {
  assert.equal(handoffToMarkdown('#### 現況\nok'), '#### 現況\nok');
});

test('XML Handoff renders as headings, never as raw tags', () => {
  const html = render({ rounds: [round({ handoff: '<handoff>\n<state>\nok\n</state>\n</handoff>' })], checkpoints: [] });
  assert.ok(!html.includes('&lt;state&gt;'));
  assert.ok(html.includes('現況'));
});

test('HANDOFF_FIELDS matches handoff-fields.sh', () => {
  const script = path.join(__dirname, 'handoff-fields.sh');
  const r = spawnSync('bash', ['-c', `. "${script}"; for k in $HANDOFF_KEYS $SESSION_HANDOFF_KEYS; do printf '%s=%s\\n' "$k" "$(handoff_key_heading "$k")"; done`], { encoding: 'utf8' });
  const fromBash = Object.fromEntries(r.stdout.trim().split('\n').map((l) => l.split('=')));
  assert.deepEqual(fromBash, HANDOFF_FIELDS);
});
```

（`render` 的輸入形狀以該檔既有測試為準；若 `checkpoints` 欄位名不同，照既有測試改。）

- [ ] **Step 2: 跑測試確認失敗**

Run: `bash core/scripts/tests/test-devlog-md.sh; bash core/scripts/tests/test-close-open-round.sh; node --test core/scripts/timeline-render.test.js`
Expected: 新案例 FAIL。

- [ ] **Step 3: 實作**

`devlog-md.sh`：檔頭 `_DEVLOG_MD_DIR=...` 下一行加

```bash
# shellcheck source=handoff-fields.sh
. "$_DEVLOG_MD_DIR/handoff-fields.sh"
```

`devlog_round_workspace_body` 換成：

```bash
devlog_round_workspace_body() {
  local blob body
  blob="$(awk -v start="$2" -v end="$3" 'NR >= start && NR <= end' "$1")"
  body="$(handoff_section_of "$blob" Handoff)"
  handoff_field "$body" workspace | sed -e '/^[[:space:]]*$/d'
}
```

`round-start.sh:168` 與 `segment-watch.sh:106` 的訊息：「上一輪 Handoff「#### 工作區」跟目前 git 不符」→「上一輪 Handoff 的工作區（`<workspace>`；舊格式是 `#### 工作區`）跟目前 git 不符」，其餘文字不變。

`close-open-round.sh` 兩處：

```awk
        if (!has_h) {
          print "### Handoff"
          print "<handoff>"
          print "<state>"
          print handoff_stub()
          print "</state>"
          print "</handoff>"
          print ""
        }
```

`timeline-render.js`：在 `statusOf` 前加

```js
const HANDOFF_FIELDS = {
  decisions: '決策', files: '檔案', workspace: '工作區', state: '現況',
  'done-when': '完成條件', next: '下一步', 'open-questions': '待解問題', 'failed-attempts': '失敗嘗試',
};
const HANDOFF_BLOCK_TAG = /^\s*<\/?(handoff|session-handoff)>\s*$/;
const HANDOFF_TAG = /^\s*<(\/?)([a-z-]+)>\s*$/;

// Line-based XML Handoff (docs/design/handoff-xml.md) → `#### 中文名`
// headings so renderMarkdown shows it like the legacy form. Legacy text
// passes through unchanged.
function handoffToMarkdown(text) {
  const out = [];
  for (const line of String(text).split('\n')) {
    if (HANDOFF_BLOCK_TAG.test(line)) continue;
    const m = HANDOFF_TAG.exec(line);
    if (m && HANDOFF_FIELDS[m[2]]) {
      if (!m[1]) out.push(`#### ${HANDOFF_FIELDS[m[2]]}`);
      continue;
    }
    out.push(line);
  }
  return out.join('\n').trim();
}
```

`roundCard` 裡 `renderMarkdown(r.handoff)` → `renderMarkdown(handoffToMarkdown(r.handoff))`；`module.exports` 加 `handoffToMarkdown, HANDOFF_FIELDS`。

> `handoffToMarkdown('#### 現況\nok')` 經 `.trim()` 仍是原字串，符合 legacy 測試。

- [ ] **Step 4: 跑測試**

Run: `bash core/scripts/run-tests.sh && npm test`
Expected: 除 SKILL 模板兩條外全 PASS。

- [ ] **Step 5: shellcheck + commit**

```bash
shellcheck --external-sources --source-path=SCRIPTDIR -S warning core/scripts/*.sh core/scripts/tests/*.sh
git add -A core/scripts
git commit -m "feat: read XML Handoff in drift check, stubs and timeline"
```

---

### Task 7: SKILL.md 與指令文件

**Files:**
- Modify: `skills/devlog-tracker/SKILL.md`
- Modify: `commands/pr.md`、`keep.md`、`keep-all.md`、`continue.md`、`resume.md`

**Interfaces:**
- Consumes: `handoff_xml_template` 的輸出必須逐字出現在 SKILL.md（`test-handoff-fields.sh` 會檢查）

- [ ] **Step 1: 確認失敗中的檢查**

Run: `bash core/scripts/tests/test-handoff-fields.sh | grep FAIL`
Expected: 兩條 `SKILL.md template ... differs`。

- [ ] **Step 2: 改 SKILL.md「每一輪的紀錄格式」**

把 ```` ```markdown ```` 範例區塊中 `### Handoff` 到 `### Status` 之前的部分，換成下面這段（`### User Input`／`### Summary`／`### Reply`／`### Status` 不動）。**`### Handoff` 與 `### Session Handoff` 兩塊必須和 `bash -c '. core/scripts/handoff-fields.sh; handoff_xml_template handoff; echo; handoff_xml_template session-handoff'` 的輸出逐字相同**——直接把該指令輸出貼進去。

範例區塊下方、「Round 編號：」之前，加：

```markdown
**Handoff／Session Handoff 用 XML 標籤（只有這兩節）：** 讀者是下一輪的 agent 與 Stop hook，不是人。規則：

- 標籤自己一行（`<next>`、`</next>` 各佔一行），內容寫在中間，照常用 Markdown；不要寫成 `<next>做 X</next>`。
- 標籤名固定、順序固定；沒發生的欄位整個標籤省略，不要留空標籤。
- 這不是真的 XML：不用跳脫 `<`、`&`，不要加屬性。
- 舊的 `#### 小節` 格式只會出現在歷史輪次，讀取時仍相容；這一輪寫舊格式會被 Stop 擋下，照訊息跑 `migrate-handoff.sh` 即可。

| 標籤 | 舊格式小節 | 所在區塊 |
|---|---|---|
| `<decisions>` | `#### 決策` | Handoff、Session Handoff |
| `<files>` | `#### 檔案` | Handoff |
| `<workspace>` | `#### 工作區` | Handoff |
| `<state>` | `#### 現況` | Handoff |
| `<done-when>` | `#### 完成條件` | Handoff |
| `<next>` | `#### 下一步` | Handoff |
| `<open-questions>` | `#### 待解問題` | Session Handoff |
| `<failed-attempts>` | `#### 失敗嘗試` | Session Handoff |

下文提到「決策」「檔案」「工作區」「現況」「完成條件」「下一步」時，指的就是對應標籤。
```

- [ ] **Step 3: 改 SKILL.md 其他提到 `####` 的地方**

`grep -n '####' skills/devlog-tracker/SKILL.md`，逐條處理：
- 第 27、159、164 行附近「`#### 工作區`」→「工作區（`<workspace>`）」。
- 寫入原則裡「Handoff 小節順序固定（決策 → 檔案 → …）」→「Handoff 標籤順序固定（`decisions` → `files` → `workspace` → `state` → `done-when` → `next`）」；「沒發生的整節省略，不要寫「無」」→「沒發生的整個標籤省略」。
- 「Session Handoff」原則：`- （無）` 規則保留；說明 hook 會把 `<session-handoff>` 區塊原樣寫進 `handoff.md`。
- 第 292 行 Stop hook 說明：開頭加「最後一輪的 Handoff／Session Handoff 必須是 XML 標籤格式（舊 `####` 格式會被擋，訊息附 migrate 指令與模板）」，並把其中 `#### X` 字樣改成對應標籤。
- 檔案 machine-verify 一節的 `#### 檔案` → `<files>`。
- 瑣碎輪一節「Handoff 只留「現況」一句」→「Handoff 只留 `<state>` 一句」。
- 指令列表若有，加 `/devlog-tracker:migrate`。

- [ ] **Step 4: 改指令文件**

- `commands/pr.md:27,35`：`#### 決策`、`#### 檔案`、`#### 現況` → 「`<decisions>`（舊格式 `#### 決策`）」等雙寫。
- `commands/keep.md:104-105` 與 `commands/keep-all.md:90`：可改寫清單 → 「`### Summary`、`### Reply`、`<decisions>`／`#### 決策`、`<state>`／`#### 現況` 的敘事」；不能動清單加入 `<workspace>`、`<files>`、`<done-when>`、`<next>`（與對應舊格式），並加一句「改寫 XML 欄位內容時，標籤行本身不動」。
- `commands/continue.md:17,18,25`：`#### 工作區` → 「工作區（`<workspace>`；舊格式 `#### 工作區`）」；第 25 行「照契約寫本輪的 `#### 工作區`、`#### 完成條件`、`#### 下一步`」→「照契約寫本輪的 `<workspace>`、`<done-when>`、`<next>`（XML 格式見 SKILL.md）」。
- `commands/resume.md`：「Handoff「下一步」」→「Handoff 的下一步（`<next>`；舊格式 `#### 下一步`）」，「現況」同理。
- `grep -rn '####' commands/` 確認剩下的只是 Checkpoint 的 `### 決策` 之類與 Handoff 無關的內容。

- [ ] **Step 5: 跑測試**

Run: `bash core/scripts/tests/test-handoff-fields.sh && npm test`
Expected: 全 PASS（`skills-from-commands` 若有 snapshot 測試，照新內容更新）。

- [ ] **Step 6: commit**

```bash
git add skills/devlog-tracker/SKILL.md commands/
git commit -m "docs: teach XML Handoff format in SKILL and commands"
```

---

### Task 8: README（英／中）

**Files:**
- Modify: `README.md`、`README.zh-TW.md`

- [ ] **Step 1: README.md**
  - 第 173 行 `Handoff` 條目後加一句：「`Handoff` and `Session Handoff` are written as line-based XML tags (`<handoff>` … `<next>` …) because only the next agent and the Stop hook read them; `Summary`/`Reply` stay Markdown for humans. See [`docs/design/handoff-xml.md`](docs/design/handoff-xml.md).」
  - 第 180 行 Stop 檢查清單：把「Handoff subsections must be in the order Decisions → … → Next steps」改成「Handoff must use the XML tag form, with tags in the order `decisions` → `files` → `workspace` → `state` → `done-when` → `next`」。
  - 指令表（第 115–126 行附近）加一列：`| /devlog-tracker:migrate | Converts legacy \`####\` Handoff/Session Handoff in \`devlog.md\`, branch files, the open round and \`handoff.md\` to XML (backups as \`*.pre-migrate\`). The Stop hook tells the agent to run it when it blocks a legacy Handoff. |`
  - 新增小節「Upgrading to XML Handoff」：舊輪次仍可讀；第一次被 Stop 擋下時 agent 會自己跑 migrate；如果 agent 一直寫舊格式，代表 vendored skill 是舊版，重跑 `npx devlog-tracker init`（plugin 使用者更新 plugin）再 `/devlog-tracker:start`。
- [ ] **Step 2: README.zh-TW.md** 對應位置做相同修改（中文）。用 `grep -n 'Handoff' README.zh-TW.md` 找對應行。
- [ ] **Step 3: 版本一致性沒被動到**

Run: `node scripts/sync-version.js --check`
Expected: 通過（這個 task 不應該動到 `**Version**`／`**版本**` 行）。

- [ ] **Step 4: commit**

```bash
git add README.md README.zh-TW.md
git commit -m "docs: document XML Handoff and migrate in READMEs"
```

---

### Task 9: 完整驗證

- [ ] **Step 1: AGENTS.md 三步**

```bash
shellcheck --external-sources --source-path=SCRIPTDIR -S warning \
  core/scripts/*.sh core/scripts/tests/*.sh cursor/hooks/*.sh codex/hooks/*.sh
bash core/scripts/run-tests.sh
npm test
```

Expected: shellcheck 無輸出；`All hook self-checks passed.`；node 測試全過。

- [ ] **Step 2: 手動煙霧測試**（在 scratch 目錄）
  1. `git init` 一個空 repo，`npx` 本地版 `node bin/devlog-tracker.js init --claude`（或直接用 plugin），`/devlog-tracker:start`。
  2. 放一份含舊格式 Round 的 `.devlog/devlog.md`，跑 `DEVLOG_PROJECT_DIR=$PWD bash <repo>/core/scripts/migrate-handoff.sh`，確認輸出、備份檔、`/devlog-tracker:timeline` 的 HTML 顯示「現況」等小標題而非 `<state>`。
- [ ] **Step 3: 對照 spec 逐節打勾**：`docs/design/handoff-xml.md` 的 Decisions 1–7、Format 規則 1–8、Access layer、Stop hook 1–6、Migrate、Readers 表、Docs、Tests 每一項都能指到一個已完成的 task。沒對到的補做。
