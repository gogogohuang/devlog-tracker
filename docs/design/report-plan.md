# report（統計）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `report-devlog.sh`：輸出 devlog 統計（`KEY=VALUE` 或 `--json`），並可用 `--rounds` 輸出每個 Round／Checkpoint 的結構化資料，供 timeline 使用；外加 `/devlog-tracker:report` 與 `npx devlog-tracker report`。

**Architecture:** 一支 awk 掃描器 `report-scan.awk` 單次掃過一個 devlog 檔，每個 Round 印一行 `R\t…\tjson`、每個 Checkpoint 印一行 `C\t…\tjson`；`report-devlog.sh` 決定掃哪些檔、彙總計數、組 JSON。npx 端用共用的 `cli/core-script.js` 呼叫 vendored（或套件內附）的腳本。

**Tech Stack:** bash（相容 macOS bash 3.2）、POSIX awk（CI 是 ubuntu 的 mawk，本機是 BSD awk）、Node ≥18 `node:test`。

**Spec:** [`read-side-and-promote.md`](read-side-and-promote.md) §B

## Global Constraints

- 一般 PR 不改版號（`package.json`、`.claude-plugin/*.json`、README 版本行都不動）。
- 零 runtime 相依：不新增 npm dependencies。
- awk 只用 POSIX 功能：清空陣列用 `split("", arr)`，不用 `delete arr`；不用 gawk 專屬函式。
- bash 3.2 相容：`set -u` 下展開可能為空的陣列用 `${arr[@]+"${arr[@]}"}`。
- 輸出預設不含 `User Input`；只有 `--with-input` 才加 `input` 欄位。
- 驗證三步都要過：`shellcheck --external-sources --source-path=SCRIPTDIR -S warning core/scripts/*.sh core/scripts/tests/*.sh cursor/hooks/*.sh codex/hooks/*.sh`、`bash core/scripts/run-tests.sh`、`npm test`。
- Commit 訊息結尾加 `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `core/scripts/json-field.sh` | Modify | 新增共用 `json_escape` |
| `core/scripts/lessons-subagent-start.sh` | Modify | 移除區域 `json_escape`，改用共用版 |
| `core/scripts/report-scan.awk` | Create | 單檔掃描，輸出 R／C 記錄 |
| `core/scripts/report-devlog.sh` | Create | 選檔、彙總、輸出 KEY=VALUE／JSON |
| `core/scripts/tests/test-report.sh` | Create | report 的 fixture 測試 |
| `core/scripts/tests/test-json-field.sh` | Modify | `json_escape` 測試 |
| `cli/core-script.js` | Create | 找 vendored／套件腳本並執行 |
| `cli/core-script.test.js` | Create | 上者的測試 |
| `bin/devlog-tracker.js` | Modify | 加 `report` 子命令 |
| `commands/report.md` | Create | 指令文件 |
| `core/scripts/round-start.sh` | Modify | admin 清單加 `devlog-tracker:report` |
| `core/scripts/tests/test-round-start.sh` | Modify | report 被豁免的測試 |
| `cli/agents-md.js`、`cli/platforms/claude.js` | Modify | 對照表加 report 列 |
| `skills/devlog-tracker/SKILL.md` | Modify | admin 清單文字加 `report` |
| `README.md`、`README.zh-TW.md` | Modify | 指令表加一列 |

## 記錄格式（Task 2 產出，Task 3–4 與 timeline-plan 依賴）

`report-scan.awk` 每行一筆，tab 分隔（JSON 內的 tab 已跳脫成 `\t`，所以 tab 分欄安全）：

```
R<TAB><status><TAB><at><TAB><branch><TAB><round-json>
C<TAB><branch><TAB><checkpoint-json>
```

- `<status>`：`DONE`／`IN_PROGRESS`／`BLOCKED`／`INTERRUPTED`，取 `### Status` 下第一個非空行（去掉空白、反引號、`*`），不是這四個就空字串。
- `<round-json>`：`{"branch","file","line","n","at","status","summary","reply","handoff","segments":[...]}`，`--with-input` 時多 `"input"`。`line` 是 `## Round` 標題的行號。`segments` 每個元素是 `段落 <標題>\n<內容>`。
- `<checkpoint-json>`：`{"branch","file","line","heading","body"}`，`heading` 是去掉 `## ` 的標題行。

`report-devlog.sh --json --rounds` 的頂層鍵：`started, branch, rounds_total, rounds_main, rounds_archive, status_done, status_in_progress, status_blocked, status_interrupted, blocked_ratio, checkpoints, kept_topics, lessons_topics, lessons_advisory, first_round_at, last_round_at, rounds, checkpoint_blocks`（`checkpoints` 是計數，陣列叫 `checkpoint_blocks`）。

---

### Task 1: 共用 `json_escape`

**Files:**
- Modify: `core/scripts/json-field.sh`（檔尾 `slugify` 之後）
- Modify: `core/scripts/lessons-subagent-start.sh:25-33`（刪除區域函式）
- Test: `core/scripts/tests/test-json-field.sh`

**Interfaces:**
- Produces: `json_escape <string>` → stdout 印出跳脫後、不含外層引號的 JSON 字串內容（`\` `"` tab CR 跳脫，換行轉 `\n`，不印結尾換行）。

- [ ] **Step 1: 寫失敗測試**

在 `core/scripts/tests/test-json-field.sh` 的 `slugify` 三行 assert 之後、最後的 `if [ "$FAIL" -eq 0 ]` 之前插入：

```bash
assert_eq "json_escape quotes and backslash" 'a \"q\" \\ b' "$(json_escape 'a "q" \ b')"
assert_eq "json_escape tab" 'x\ty' "$(json_escape "$(printf 'x\ty')")"
assert_eq "json_escape newline" 'l1\nl2' "$(json_escape "$(printf 'l1\nl2')")"
assert_eq "json_escape CJK passthrough" '中文' "$(json_escape '中文')"
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `bash core/scripts/tests/test-json-field.sh`
Expected: 四行 `FAIL: json_escape ...`（`json_escape: command not found`）

- [ ] **Step 3: 實作**

在 `core/scripts/json-field.sh` 檔尾加：

```bash

json_escape() {
  printf '%s' "$1" | awk '
    BEGIN { ORS = "" }
    {
      gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); gsub(/\r/, "\\r")
      if (NR > 1) print "\\n"
      print
    }'
}
```

刪掉 `core/scripts/lessons-subagent-start.sh` 裡同名的 `json_escape() { … }` 區塊（第 25–33 行）。確認該檔開頭已 source `json-field.sh`：

Run: `grep -n 'json-field.sh' core/scripts/lessons-subagent-start.sh`
Expected: 有一行 `. "$…/json-field.sh"`。若沒有，在其他 `.` source 行旁補：

```bash
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"
```

（變數名照該檔既有的 script 目錄變數；用 `grep -n 'SCRIPT_DIR\|HOOKS_DIR' core/scripts/lessons-subagent-start.sh` 確認。）

- [ ] **Step 4: 跑測試確認通過**

Run: `bash core/scripts/tests/test-json-field.sh && bash core/scripts/tests/test-lessons-subagent-hooks.sh`
Expected: 兩支都 `All checks passed.`

- [ ] **Step 5: Commit**

```bash
git add core/scripts/json-field.sh core/scripts/lessons-subagent-start.sh core/scripts/tests/test-json-field.sh
git commit -m "refactor: share json_escape via json-field.sh

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `report-scan.awk` + `report-devlog.sh`（KEY=VALUE）

**Files:**
- Create: `core/scripts/report-scan.awk`
- Create: `core/scripts/report-devlog.sh`
- Test: `core/scripts/tests/test-report.sh`

**Interfaces:**
- Consumes: `json_escape`（Task 1）、`devlog_resolve_paths`、`devlog_kept_index_lines`、`json_int_get`。
- Produces: 上面「記錄格式」；`report-devlog.sh` 的 KEY=VALUE 輸出（順序固定）：`BRANCH ROUNDS_TOTAL ROUNDS_MAIN ROUNDS_ARCHIVE STATUS_DONE STATUS_IN_PROGRESS STATUS_BLOCKED STATUS_INTERRUPTED BLOCKED_RATIO CHECKPOINTS KEPT_TOPICS LESSONS_TOPICS [LESSONS_ADVISORY] FIRST_ROUND_AT LAST_ROUND_AT`。

- [ ] **Step 1: 寫失敗測試**

Create `core/scripts/tests/test-report.sh`：

```bash
#!/usr/bin/env bash
# Self-check for report-devlog.sh (docs/design/read-side-and-promote.md B).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
export CLAUDE_PROJECT_DIR="$TMP_ROOT"
DEVLOG_DIR="$TMP_ROOT/.devlog"
FAIL=0
assert_line() {
  local desc="$1" expected="$2" out="$3"
  if printf '%s\n' "$out" | grep -qxF "$expected"; then echo "PASS: $desc"
  else echo "FAIL: $desc (missing line [$expected] in: $out)"; FAIL=1; fi
}
assert_no_line_prefix() {
  local desc="$1" prefix="$2" out="$3"
  if printf '%s\n' "$out" | grep -q "^$prefix"; then echo "FAIL: $desc (found $prefix)"; FAIL=1
  else echo "PASS: $desc"; fi
}
jcheck() {
  local desc="$1" json="$2" expr="$3"
  if ! command -v node >/dev/null 2>&1; then echo "SKIP: $desc (no node)"; return 0; fi
  if printf '%s' "$json" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8')); process.exit(($expr)?0:1)"; then
    echo "PASS: $desc"
  else echo "FAIL: $desc"; FAIL=1; fi
}

# --- No .devlog -> NOT_STARTED ----------------------------------------------
OUT="$(bash "$SCRIPT_DIR/report-devlog.sh")"
assert_line "no .devlog -> NOT_STARTED" "NOT_STARTED" "$OUT"

# --- Fixture ------------------------------------------------------------------
mkdir -p "$DEVLOG_DIR"
{
  cat <<'EOF'
## Round 1 — 2026-09-01T10:00:00+0800

### User Input
secret-input-text

### Summary
EOF
  printf 'first "quoted" \\ back\ttab 中文\n'
  cat <<'EOF'

### Handoff
#### 現況
x

### Status
DONE

## Round 2 — 2026-09-02T10:00:00+0800

### Summary
blocked one
```
## Round 9 fake inside fence
```

### Status
BLOCKED

## Checkpoint（Round 1-2）
### 決策
- keep it

## Round 3 — 2026-09-03T10:00:00+0800

### Summary
in progress

### 段落 探索
seg body

### Status
INTERRUPTED
[reason: dangling:next_prompt]

## Kept 索引
- `devlog.topic-a.md`：Round 5-5，kept_at 2026-09-05T00:00:00+0800，topic a
EOF
} > "$DEVLOG_DIR/devlog.md"
cat > "$DEVLOG_DIR/devlog.archive.md" <<'EOF'
## Round 0 — 2026-08-31T10:00:00+0800

### Summary
archived

### Status
DONE
EOF
cat > "$DEVLOG_DIR/devlog.topic-a.md" <<'EOF'
## Round 5 — 2026-09-05T10:00:00+0800

### Summary
kept topic

### Status
DONE
EOF
cat > "$DEVLOG_DIR/devlog.feat-x.md" <<'EOF'
## Round 1 — 2026-09-04T10:00:00+0800

### Summary
branch work

### Status
IN_PROGRESS
EOF
printf '# Lessons: foo\n\n## 2026-09-01T00:00:00+0800\nlesson.\n' > "$DEVLOG_DIR/devlog.lessons.foo.md"

# --- Default KEY=VALUE --------------------------------------------------------
OUT="$(bash "$SCRIPT_DIR/report-devlog.sh")"
assert_line "branch" "BRANCH=main" "$OUT"
assert_line "total rounds = archive + main, fenced fake ignored" "ROUNDS_TOTAL=4" "$OUT"
assert_line "main rounds" "ROUNDS_MAIN=3" "$OUT"
assert_line "archive rounds" "ROUNDS_ARCHIVE=1" "$OUT"
assert_line "done count" "STATUS_DONE=2" "$OUT"
assert_line "in-progress count (branch file not scanned)" "STATUS_IN_PROGRESS=0" "$OUT"
assert_line "blocked count" "STATUS_BLOCKED=1" "$OUT"
assert_line "interrupted count despite reason line" "STATUS_INTERRUPTED=1" "$OUT"
assert_line "blocked ratio" "BLOCKED_RATIO=25" "$OUT"
assert_line "checkpoints" "CHECKPOINTS=1" "$OUT"
assert_line "kept topics" "KEPT_TOPICS=1" "$OUT"
assert_line "lessons topics" "LESSONS_TOPICS=1" "$OUT"
assert_line "first round at" "FIRST_ROUND_AT=2026-08-31T10:00:00+0800" "$OUT"
assert_line "last round at" "LAST_ROUND_AT=2026-09-03T10:00:00+0800" "$OUT"
assert_no_line_prefix "no advisory state -> no LESSONS_ADVISORY" "LESSONS_ADVISORY=" "$OUT"

printf '%s\n' '{"count": 2, "threshold": 3}' > "$DEVLOG_DIR/.lessons-advisory-state"
OUT="$(bash "$SCRIPT_DIR/report-devlog.sh")"
assert_line "advisory state present" "LESSONS_ADVISORY=2/3" "$OUT"
rm -f "$DEVLOG_DIR/.lessons-advisory-state"

# --- Empty devlog dir: zeros and none ----------------------------------------
EMPTY_ROOT="$(mktemp -d)"
mkdir -p "$EMPTY_ROOT/.devlog"
OUT="$(CLAUDE_PROJECT_DIR="$EMPTY_ROOT" bash "$SCRIPT_DIR/report-devlog.sh")"
assert_line "empty: zero rounds" "ROUNDS_TOTAL=0" "$OUT"
assert_line "empty: zero ratio" "BLOCKED_RATIO=0" "$OUT"
assert_line "empty: first none" "FIRST_ROUND_AT=none" "$OUT"
rm -rf "$EMPTY_ROOT"

# --- Unknown arg -> exit 2 ------------------------------------------------------
bash "$SCRIPT_DIR/report-devlog.sh" --bogus >/dev/null 2>&1
RC=$?
if [ "$RC" -eq 2 ]; then echo "PASS: unknown arg exits 2"; else echo "FAIL: unknown arg exit $RC"; FAIL=1; fi

# @@JSON_TESTS@@

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
```

（`# @@JSON_TESTS@@` 是 Task 3／4 插入測試的定位行，Task 4 結束時刪掉。`jcheck` 在 Task 3 才用到。）

- [ ] **Step 2: 跑測試確認失敗**

Run: `bash core/scripts/tests/test-report.sh`
Expected: `FAIL`（`report-devlog.sh: No such file or directory`）

- [ ] **Step 3: 實作 `core/scripts/report-scan.awk`**

```awk
# One pass over one devlog file for report-devlog.sh
# (docs/design/read-side-and-promote.md B). POSIX awk only (mawk / BSD awk).
# Vars: branch, label (file leaf name), with_input (0|1).
# Emits one line per block:
#   R<TAB>status<TAB>at<TAB>branch<TAB>round-json
#   C<TAB>branch<TAB>checkpoint-json
# Headings inside ``` fences are content, not structure (same rule as
# devlog-md.sh).
function esc(s) {
  gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s)
  gsub(/\t/, "\\t", s); gsub(/\r/, "\\r", s); gsub(/\n/, "\\n", s)
  return s
}
function trim_nl(s) { sub(/^\n+/, "", s); sub(/\n+$/, "", s); return s }
function flush_section() {
  if (sec == "") return
  if (sec == "segment") segs[nseg++] = trim_nl(buf)
  else part[sec] = trim_nl(buf)
  sec = ""; buf = ""
}
function flush_block(   i, st, js) {
  flush_section()
  if (kind == "round") {
    st = part["status"]; sub(/\n.*/, "", st); gsub(/[ \t`*]/, "", st)
    if (st !~ /^(DONE|IN_PROGRESS|BLOCKED|INTERRUPTED)$/) st = ""
    js = "{\"branch\":\"" esc(branch) "\",\"file\":\"" esc(label) "\",\"line\":" rline ",\"n\":" rn
    js = js ",\"at\":\"" esc(at) "\",\"status\":\"" st "\""
    js = js ",\"summary\":\"" esc(part["summary"]) "\",\"reply\":\"" esc(part["reply"]) "\""
    js = js ",\"handoff\":\"" esc(part["handoff"]) "\",\"segments\":["
    for (i = 0; i < nseg; i++) js = js (i ? "," : "") "\"" esc(segs[i]) "\""
    js = js "]"
    if (with_input) js = js ",\"input\":\"" esc(part["input"]) "\""
    js = js "}"
    printf "R\t%s\t%s\t%s\t%s\n", st, at, branch, js
  } else if (kind == "checkpoint") {
    printf "C\t%s\t{\"branch\":\"%s\",\"file\":\"%s\",\"line\":%d,\"heading\":\"%s\",\"body\":\"%s\"}\n", \
      branch, esc(branch), esc(label), cline, esc(cheading), esc(trim_nl(buf_cp))
  }
  kind = ""; split("", part); split("", segs); nseg = 0; buf_cp = ""
}
/^[ \t]*```/ { fence = !fence }
!fence && /^## / {
  flush_block()
  if ($0 ~ /^## Round [0-9]+/) {
    kind = "round"; rline = NR
    rn = $0; sub(/^## Round /, "", rn); sub(/[^0-9].*$/, "", rn)
    at = ""
    if (index($0, "— ")) at = substr($0, index($0, "— ") + length("— "))
  } else if ($0 ~ /^## Checkpoint/) {
    kind = "checkpoint"; cline = NR; cheading = substr($0, 4)
  }
  next
}
kind == "checkpoint" { buf_cp = buf_cp $0 "\n"; next }
kind == "round" && !fence && /^### / {
  flush_section()
  h = substr($0, 5)
  if (h ~ /^User Input[ \t]*$/) sec = "input"
  else if (h ~ /^Summary[ \t]*$/) sec = "summary"
  else if (h ~ /^Reply[ \t]*$/) sec = "reply"
  else if (h ~ /^Handoff[ \t]*$/) sec = "handoff"
  else if (h ~ /^Status[ \t]*$/) sec = "status"
  else if (h ~ /^段落 /) { sec = "segment"; buf = h "\n"; next }
  else sec = "other"
  next
}
kind == "round" && sec != "" { buf = buf $0 "\n" }
END { flush_block() }
```

- [ ] **Step 4: 實作 `core/scripts/report-devlog.sh`**

```bash
#!/usr/bin/env bash
# Stats + structured Round data for /devlog-tracker:report, `npx devlog-tracker
# report`, and timeline-devlog.sh (docs/design/read-side-and-promote.md B).
# Plain read only: never edits a devlog file. devlog_resolve_paths may still
# do its documented first-resolve rename, same as every other reader.
set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"
# shellcheck source=devlog-md.sh
. "$SCRIPT_DIR/devlog-md.sh"
# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"

JSON=0
ROUNDS=0
ALL=0
WITH_INPUT=0
for arg in "$@"; do
  case "$arg" in
    --json) JSON=1 ;;
    --rounds) ROUNDS=1 ;;
    --all-branches) ALL=1 ;;
    --with-input) WITH_INPUT=1 ;;
    *) echo "UNKNOWN_ARG=$arg" >&2; exit 2 ;;
  esac
done

devlog_resolve_paths "${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
if [ ! -d "$DEVLOG_DIR" ]; then
  if [ "$JSON" -eq 1 ]; then echo '{"started":false}'; else echo "NOT_STARTED"; fi
  exit 0
fi

# devlog.md -> main, devlog.archive.md -> archive, devlog.<x>.md -> <x>.
branch_of_file() {
  local leaf="${1##*/}"
  case "$leaf" in
    devlog.md) printf 'main' ;;
    devlog.archive.md) printf 'archive' ;;
    *) leaf="${leaf#devlog.}"; printf '%s' "${leaf%.md}" ;;
  esac
}

# Archive first (oldest), then the branch file(s).
FILES=()
[ -f "$DEVLOG_DIR/devlog.archive.md" ] && FILES+=("$DEVLOG_DIR/devlog.archive.md")
if [ "$ALL" -eq 1 ]; then
  : # filled in by Task 4
else
  [ -f "$DEVLOG_FILE" ] && FILES+=("$DEVLOG_FILE")
fi

SCAN="$(mktemp "${TMPDIR:-/tmp}/devlog-report.XXXXXX")" || exit 1
trap 'rm -f "$SCAN"' EXIT
for f in ${FILES[@]+"${FILES[@]}"}; do
  awk -v branch="$(branch_of_file "$f")" -v label="${f##*/}" -v with_input="$WITH_INPUT" \
    -f "$SCRIPT_DIR/report-scan.awk" "$f" >> "$SCAN"
done

count_status() { awk -F'\t' -v s="$1" '$1 == "R" && $2 == s { c++ } END { print c + 0 }' "$SCAN"; }
BRANCH="$(branch_of_file "$DEVLOG_FILE")"
ROUNDS_TOTAL="$(awk -F'\t' '$1 == "R" { c++ } END { print c + 0 }' "$SCAN")"
ROUNDS_ARCHIVE="$(awk -F'\t' '$1 == "R" && $4 == "archive" { c++ } END { print c + 0 }' "$SCAN")"
ROUNDS_MAIN=$((ROUNDS_TOTAL - ROUNDS_ARCHIVE))
STATUS_DONE="$(count_status DONE)"
STATUS_IN_PROGRESS="$(count_status IN_PROGRESS)"
STATUS_BLOCKED="$(count_status BLOCKED)"
STATUS_INTERRUPTED="$(count_status INTERRUPTED)"
BLOCKED_RATIO=0
[ "$ROUNDS_TOTAL" -gt 0 ] && BLOCKED_RATIO=$((STATUS_BLOCKED * 100 / ROUNDS_TOTAL))
CHECKPOINTS="$(awk -F'\t' '$1 == "C" { c++ } END { print c + 0 }' "$SCAN")"
KEPT_TOPICS=0
if [ -f "$DEVLOG_FILE" ]; then
  KEPT_TOPICS="$(devlog_kept_index_lines "$DEVLOG_FILE" | grep -c '^- `devlog\.' || true)"
fi
LESSONS_TOPICS=0
for f in "$DEVLOG_DIR"/devlog.lessons.*.md; do
  [ -f "$f" ] && LESSONS_TOPICS=$((LESSONS_TOPICS + 1))
done
ADVISORY=""
if [ -f "$DEVLOG_DIR/.lessons-advisory-state" ]; then
  a_count="$(json_int_get "$DEVLOG_DIR/.lessons-advisory-state" count)"
  a_max="$(json_int_get "$DEVLOG_DIR/.lessons-advisory-state" threshold)"
  ADVISORY="${a_count:-0}/${a_max:-3}"
fi
FIRST_ROUND_AT="$(awk -F'\t' '$1 == "R" && $3 != "" { print $3 }' "$SCAN" | sort | head -1)"
LAST_ROUND_AT="$(awk -F'\t' '$1 == "R" && $3 != "" { print $3 }' "$SCAN" | sort | tail -1)"
[ -n "$FIRST_ROUND_AT" ] || FIRST_ROUND_AT=none
[ -n "$LAST_ROUND_AT" ] || LAST_ROUND_AT=none

if [ "$JSON" -eq 0 ]; then
  printf 'BRANCH=%s\n' "$BRANCH"
  printf 'ROUNDS_TOTAL=%s\nROUNDS_MAIN=%s\nROUNDS_ARCHIVE=%s\n' "$ROUNDS_TOTAL" "$ROUNDS_MAIN" "$ROUNDS_ARCHIVE"
  printf 'STATUS_DONE=%s\nSTATUS_IN_PROGRESS=%s\nSTATUS_BLOCKED=%s\nSTATUS_INTERRUPTED=%s\n' \
    "$STATUS_DONE" "$STATUS_IN_PROGRESS" "$STATUS_BLOCKED" "$STATUS_INTERRUPTED"
  printf 'BLOCKED_RATIO=%s\nCHECKPOINTS=%s\nKEPT_TOPICS=%s\nLESSONS_TOPICS=%s\n' \
    "$BLOCKED_RATIO" "$CHECKPOINTS" "$KEPT_TOPICS" "$LESSONS_TOPICS"
  [ -n "$ADVISORY" ] && printf 'LESSONS_ADVISORY=%s\n' "$ADVISORY"
  printf 'FIRST_ROUND_AT=%s\nLAST_ROUND_AT=%s\n' "$FIRST_ROUND_AT" "$LAST_ROUND_AT"
  exit 0
fi

# JSON output: filled in by Task 3.
exit 0
```

`chmod +x core/scripts/report-devlog.sh`（其他 core 腳本都是 755：`ls -l core/scripts/kept-list.sh` 確認）。

- [ ] **Step 5: 跑測試確認通過**

Run: `bash core/scripts/tests/test-report.sh`
Expected: 全部 `PASS`，`All checks passed.`

- [ ] **Step 6: shellcheck**

Run: `shellcheck --external-sources --source-path=SCRIPTDIR -S warning core/scripts/report-devlog.sh core/scripts/tests/test-report.sh`
Expected: 無輸出

- [ ] **Step 7: Commit**

```bash
git add core/scripts/report-scan.awk core/scripts/report-devlog.sh core/scripts/tests/test-report.sh
git commit -m "feat: add report-devlog.sh with KEY=VALUE devlog stats

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `--json`、`--rounds`、`--with-input`

**Files:**
- Modify: `core/scripts/report-devlog.sh`（取代 `# JSON output: filled in by Task 3.` 那段）
- Test: `core/scripts/tests/test-report.sh`（在 `# @@JSON_TESTS@@` 之前插入）

**Interfaces:**
- Consumes: Task 2 的 `$SCAN` 記錄與各計數變數。
- Produces: 「記錄格式」一節定義的 JSON 頂層鍵；`timeline-plan.md` 依賴 `rounds[].{branch,file,line,n,at,status,summary,reply,handoff,segments}` 與 `checkpoint_blocks[].{branch,file,line,heading,body}`。

- [ ] **Step 1: 寫失敗測試**

在 `test-report.sh` 的 `# @@JSON_TESTS@@` 之前插入：

```bash
# --- --json (no rounds) -------------------------------------------------------
J="$(bash "$SCRIPT_DIR/report-devlog.sh" --json)"
jcheck "json: started + counts are numbers" "$J" 'd.started===true && d.rounds_total===4 && d.status_blocked===1 && d.blocked_ratio===25'
jcheck "json: branch + times" "$J" 'd.branch==="main" && d.first_round_at==="2026-08-31T10:00:00+0800"'
jcheck "json: no advisory -> null" "$J" 'd.lessons_advisory===null'
jcheck "json: no rounds array without --rounds" "$J" '!("rounds" in d) && !("checkpoint_blocks" in d)'

# --- --json --rounds ------------------------------------------------------------
J="$(bash "$SCRIPT_DIR/report-devlog.sh" --json --rounds)"
jcheck "rounds: 4 entries, archive first" "$J" 'd.rounds.length===4 && d.rounds[0].branch==="archive" && d.rounds[0].n===0'
jcheck "rounds: escaping survives quote/backslash/tab/CJK" "$J" 'd.rounds[1].summary.includes("\"quoted\"") && d.rounds[1].summary.includes("\\") && d.rounds[1].summary.includes("\t") && d.rounds[1].summary.includes("中文")'
jcheck "rounds: fenced fake heading stays inside summary" "$J" 'd.rounds[2].summary.includes("## Round 9 fake inside fence")'
jcheck "rounds: status parsed despite reason line" "$J" 'd.rounds[3].status==="INTERRUPTED"'
jcheck "rounds: segments captured" "$J" 'd.rounds[3].segments.length===1 && d.rounds[3].segments[0]==="段落 探索\nseg body"'
jcheck "rounds: handoff keeps #### lines" "$J" 'd.rounds[1].handoff.startsWith("#### 現況")'
jcheck "rounds: line numbers" "$J" 'd.rounds[1].line===1 && d.rounds[1].file==="devlog.md"'
jcheck "rounds: no input by default" "$J" 'd.rounds.every(r => !("input" in r))'
jcheck "checkpoint_blocks: one block with body" "$J" 'd.checkpoint_blocks.length===1 && d.checkpoint_blocks[0].heading==="Checkpoint（Round 1-2）" && d.checkpoint_blocks[0].body.includes("keep it")'

J="$(bash "$SCRIPT_DIR/report-devlog.sh" --json --rounds --with-input)"
jcheck "with-input: input field present" "$J" 'd.rounds[1].input==="secret-input-text"'

# --- --json on NOT_STARTED ------------------------------------------------------
NS_ROOT="$(mktemp -d)"
J="$(CLAUDE_PROJECT_DIR="$NS_ROOT" bash "$SCRIPT_DIR/report-devlog.sh" --json)"
jcheck "json NOT_STARTED" "$J" 'd.started===false'
rm -rf "$NS_ROOT"
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `bash core/scripts/tests/test-report.sh`
Expected: 新增的 `json:`／`rounds:` 檢查 `FAIL`（輸出是空字串，`JSON.parse` 失敗）；`json NOT_STARTED` PASS。

- [ ] **Step 3: 實作**

把 `report-devlog.sh` 結尾的

```bash
# JSON output: filled in by Task 3.
exit 0
```

換成：

```bash
jstr() {
  if [ -z "$1" ] || [ "$1" = none ]; then printf 'null'
  else printf '"%s"' "$(json_escape "$1")"; fi
}
{
  printf '{"started":true,"branch":"%s"' "$(json_escape "$BRANCH")"
  printf ',"rounds_total":%s,"rounds_main":%s,"rounds_archive":%s' "$ROUNDS_TOTAL" "$ROUNDS_MAIN" "$ROUNDS_ARCHIVE"
  printf ',"status_done":%s,"status_in_progress":%s,"status_blocked":%s,"status_interrupted":%s' \
    "$STATUS_DONE" "$STATUS_IN_PROGRESS" "$STATUS_BLOCKED" "$STATUS_INTERRUPTED"
  printf ',"blocked_ratio":%s,"checkpoints":%s,"kept_topics":%s,"lessons_topics":%s' \
    "$BLOCKED_RATIO" "$CHECKPOINTS" "$KEPT_TOPICS" "$LESSONS_TOPICS"
  printf ',"lessons_advisory":%s,"first_round_at":%s,"last_round_at":%s' \
    "$(jstr "$ADVISORY")" "$(jstr "$FIRST_ROUND_AT")" "$(jstr "$LAST_ROUND_AT")"
  if [ "$ROUNDS" -eq 1 ]; then
    printf ',"rounds":['
    awk -F'\t' '$1 == "R" { printf "%s%s", (n++ ? "," : ""), $5 }' "$SCAN"
    printf '],"checkpoint_blocks":['
    awk -F'\t' '$1 == "C" { printf "%s%s", (n++ ? "," : ""), $3 }' "$SCAN"
    printf ']'
  fi
  printf '}\n'
}
exit 0
```

- [ ] **Step 4: 跑測試確認通過**

Run: `bash core/scripts/tests/test-report.sh`
Expected: `All checks passed.`（沒有 node 的環境 JSON 檢查會是 `SKIP`；本機與 CI 都有 node，必須是 `PASS`）

- [ ] **Step 5: Commit**

```bash
git add core/scripts/report-devlog.sh core/scripts/tests/test-report.sh
git commit -m "feat: report-devlog.sh --json/--rounds structured output

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `--all-branches`

**Files:**
- Modify: `core/scripts/report-devlog.sh`（`if [ "$ALL" -eq 1 ]; then : # filled in by Task 4` 那段）
- Test: `core/scripts/tests/test-report.sh`

**Interfaces:**
- Produces: `--all-branches` 時掃 `.devlog/devlog*.md`，排除 archive（已另外加入）、`devlog.lessons.*.md`、任何 Kept 索引列出的 `devlog.<name>.md`。

- [ ] **Step 1: 寫失敗測試**

在 `# @@JSON_TESTS@@` 之前插入：

```bash
# --- --all-branches ---------------------------------------------------------------
OUT="$(bash "$SCRIPT_DIR/report-devlog.sh" --all-branches)"
assert_line "all-branches: branch file added, kept file excluded" "ROUNDS_TOTAL=5" "$OUT"
assert_line "all-branches: in-progress from branch file" "STATUS_IN_PROGRESS=1" "$OUT"
assert_line "all-branches: last round from branch file" "LAST_ROUND_AT=2026-09-04T10:00:00+0800" "$OUT"
J="$(bash "$SCRIPT_DIR/report-devlog.sh" --json --rounds --all-branches)"
jcheck "all-branches: feat-x rounds tagged" "$J" 'd.rounds.some(r => r.branch==="feat-x" && r.summary==="branch work")'
jcheck "all-branches: no kept or lessons rounds" "$J" 'd.rounds.every(r => r.branch!=="topic-a" && !r.branch.startsWith("lessons."))'
```

然後刪掉 `# @@JSON_TESTS@@` 這行。

- [ ] **Step 2: 跑測試確認失敗**

Run: `bash core/scripts/tests/test-report.sh`
Expected: `all-branches:` 相關 `FAIL`（`ROUNDS_TOTAL=1`，只掃到 archive）

- [ ] **Step 3: 實作**

把

```bash
if [ "$ALL" -eq 1 ]; then
  : # filled in by Task 4
else
```

換成：

```bash
if [ "$ALL" -eq 1 ]; then
  shopt -s nullglob
  KEPT_NAMES=" "
  for f in "$DEVLOG_DIR"/devlog*.md; do
    while IFS= read -r name; do
      [ -n "$name" ] && KEPT_NAMES="$KEPT_NAMES$name "
    done < <(devlog_kept_index_lines "$f" | sed -nE 's/.*`devlog\.([^`]+)\.md`.*/\1/p')
  done
  for f in "$DEVLOG_DIR"/devlog*.md; do
    case "${f##*/}" in devlog.archive.md|devlog.lessons.*.md) continue ;; esac
    case "$KEPT_NAMES" in *" $(branch_of_file "$f") "*) continue ;; esac
    FILES+=("$f")
  done
  shopt -u nullglob
else
```

（`LESSONS_TOPICS` 迴圈在這段之後；它自己用 `[ -f "$f" ]` 擋掉沒有展開的 glob，不受 `nullglob` 影響。）

- [ ] **Step 4: 跑測試確認通過**

Run: `bash core/scripts/tests/test-report.sh && shellcheck --external-sources --source-path=SCRIPTDIR -S warning core/scripts/report-devlog.sh core/scripts/tests/test-report.sh`
Expected: `All checks passed.`，shellcheck 無輸出

- [ ] **Step 5: Commit**

```bash
git add core/scripts/report-devlog.sh core/scripts/tests/test-report.sh
git commit -m "feat: report-devlog.sh --all-branches

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: `cli/core-script.js` + `npx devlog-tracker report`

**Files:**
- Create: `cli/core-script.js`
- Create: `cli/core-script.test.js`
- Modify: `bin/devlog-tracker.js`（usage 字串與 `status` 分支之後）

**Interfaces:**
- Produces:
  - `resolveScript({ targetDir, repoRoot, name }) -> string`：`<targetDir>/.devlog-tracker/core/scripts/<name>` 存在就回傳它，否則 `<repoRoot>/core/scripts/<name>`。
  - `runCoreScript({ targetDir, repoRoot, name, args }) -> { status: number, stdout: string, stderr: string }`：以 `bash` 執行，`cwd=targetDir`，環境加 `DEVLOG_PROJECT_DIR=targetDir`。
  - `bin` 的 `CORE_COMMANDS` 物件（`timeline-plan.md` 會加一個鍵）。

- [ ] **Step 1: 寫失敗測試**

Create `cli/core-script.test.js`：

```js
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { resolveScript, runCoreScript } = require('./core-script');

function tmp() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'devlog-tracker-core-'));
}
function writeScript(dir, name, body) {
  const scripts = path.join(dir, 'core', 'scripts');
  fs.mkdirSync(scripts, { recursive: true });
  fs.writeFileSync(path.join(scripts, name), body);
}

test('prefers the vendored copy and passes DEVLOG_PROJECT_DIR + args', () => {
  const target = tmp();
  const repo = tmp();
  writeScript(path.join(target, '.devlog-tracker'), 'x.sh', 'echo "vendored $DEVLOG_PROJECT_DIR $*"\n');
  writeScript(repo, 'x.sh', 'echo packaged\n');
  assert.equal(resolveScript({ targetDir: target, repoRoot: repo, name: 'x.sh' }),
    path.join(target, '.devlog-tracker', 'core', 'scripts', 'x.sh'));
  const r = runCoreScript({ targetDir: target, repoRoot: repo, name: 'x.sh', args: ['--json'] });
  assert.equal(r.status, 0);
  assert.equal(r.stdout, `vendored ${target} --json\n`);
});

test('falls back to the packaged script when nothing is vendored', () => {
  const target = tmp();
  const repo = tmp();
  writeScript(repo, 'x.sh', 'echo packaged\n');
  const r = runCoreScript({ targetDir: target, repoRoot: repo, name: 'x.sh', args: [] });
  assert.equal(r.stdout, 'packaged\n');
});

test('propagates exit code and stderr', () => {
  const target = tmp();
  const repo = tmp();
  writeScript(repo, 'x.sh', 'echo oops >&2; exit 3\n');
  const r = runCoreScript({ targetDir: target, repoRoot: repo, name: 'x.sh', args: [] });
  assert.equal(r.status, 3);
  assert.equal(r.stderr, 'oops\n');
});

test('bin report runs the real packaged report-devlog.sh', () => {
  const cwd = tmp();
  const bin = path.join(__dirname, '..', 'bin', 'devlog-tracker.js');
  const r = spawnSync(process.execPath, [bin, 'report'], { cwd, encoding: 'utf8' });
  assert.equal(r.status, 0);
  assert.equal(r.stdout, 'NOT_STARTED\n');
});
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `node --test cli/core-script.test.js`
Expected: FAIL（`Cannot find module './core-script'`）

- [ ] **Step 3: 實作 `cli/core-script.js`**

```js
'use strict';
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

// npx 子命令（report／timeline）直接轉呼 core/scripts 的 bash 腳本：專案有
// vendored 版本就用它（與 hooks 同一份），否則用套件內附的版本。
function resolveScript({ targetDir, repoRoot, name }) {
  const vendored = path.join(targetDir, '.devlog-tracker', 'core', 'scripts', name);
  return fs.existsSync(vendored) ? vendored : path.join(repoRoot, 'core', 'scripts', name);
}

function runCoreScript({ targetDir, repoRoot, name, args }) {
  const script = resolveScript({ targetDir, repoRoot, name });
  const r = spawnSync('bash', [script, ...args], {
    cwd: targetDir,
    env: { ...process.env, DEVLOG_PROJECT_DIR: targetDir },
    encoding: 'utf8',
  });
  return { status: r.status === null ? 1 : r.status, stdout: r.stdout || '', stderr: r.stderr || '' };
}

module.exports = { resolveScript, runCoreScript };
```

- [ ] **Step 4: 接進 `bin/devlog-tracker.js`**

把 usage 那行改成：

```js
    console.log('Usage: devlog-tracker <init|status|report> [--codex] [--cursor] [--json] [--all-branches]');
```

在 `if (command === 'status') { … }` 區塊結束之後、`console.error(\`Unknown command: ${command}\`);` 之前加：

```js
  const CORE_COMMANDS = { report: 'report-devlog.sh' };
  if (Object.prototype.hasOwnProperty.call(CORE_COMMANDS, command)) {
    const { runCoreScript } = require('../cli/core-script');
    const r = runCoreScript({
      targetDir: process.cwd(),
      repoRoot: path.join(__dirname, '..'),
      name: CORE_COMMANDS[command],
      args: rest,
    });
    process.stdout.write(r.stdout);
    process.stderr.write(r.stderr);
    return r.status;
  }
```

- [ ] **Step 5: 跑測試確認通過**

Run: `node --test cli/core-script.test.js && npm test`
Expected: 全部 pass

- [ ] **Step 6: Commit**

```bash
git add cli/core-script.js cli/core-script.test.js bin/devlog-tracker.js
git commit -m "feat: npx devlog-tracker report

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: `/devlog-tracker:report` 指令與文件

**Files:**
- Create: `commands/report.md`
- Modify: `core/scripts/round-start.sh`（admin `case` 那一行）
- Modify: `core/scripts/tests/test-round-start.sh`（section 20 之前）
- Modify: `cli/agents-md.js`（`codexBlock` 表格）、`cli/platforms/claude.js`（`claudeBlock` 表格）
- Modify: `skills/devlog-tracker/SKILL.md:316-318`
- Modify: `README.md`、`README.zh-TW.md`（指令表 `search` 那列之後）

**Interfaces:**
- Consumes: `report-devlog.sh`（Task 2–4）。

- [ ] **Step 1: 寫失敗測試（admin 豁免）**

在 `core/scripts/tests/test-round-start.sh` 的 `# --- 20: a namespaced-but-different command name` 之前插入：

```bash
# --- 19b: report / timeline are admin (read-side) commands too -------------
for ADMIN_CMD in report; do
  rm -f "$DEVLOG_DIR/.round-current.md" "$DEVLOG_DIR/.round-open"
  printf '{"prompt":"<command-name>/devlog-tracker:%s</command-name>"}' "$ADMIN_CMD" | bash "$SCRIPT_DIR/round-start.sh"
  assert_file_absent "admin $ADMIN_CMD: no .round-current.md" "$DEVLOG_DIR/.round-current.md"
done
```

（`timeline-plan.md` 會把 `for ADMIN_CMD in report` 改成 `in report timeline`。）

Run: `bash core/scripts/tests/test-round-start.sh 2>&1 | grep 'admin report'`
Expected: `FAIL: admin report: no .round-current.md`（若 `assert_file_absent` 的 FAIL 訊息格式不同，以該檔既有格式為準）

同時 `npm test` 會因 `cli/agents-md.test.js` 的「block mentions every command doc」在 Step 2 建立 `commands/report.md` 後失敗，Step 4 修正。

- [ ] **Step 2: 建立 `commands/report.md`**

````markdown
---
description: 查看 devlog 統計：Round 數、各 Status、BLOCKED 比例、Checkpoint／keep／lessons 數量與時間範圍（純讀取）。
---

這是純讀取，不改任何檔。先決定 plugin 根目錄（有 `DEVLOG_TRACKER_ROOT` 用它；否則用 `CLAUDE_PLUGIN_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄），再跑：

```bash
PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
DEVLOG_PROJECT_DIR="$(pwd)" bash "${PLUGIN_ROOT}/core/scripts/report-devlog.sh"
```

使用者要看所有 branch 的合計時加 `--all-branches`。

- `NOT_STARTED`：告知還沒 `/devlog-tracker:start`，結束。
- 其他輸出是 `KEY=VALUE`，翻成幾行給人看：
  - `BRANCH`：統計的是哪個 branch 的檔案（`--all-branches` 時仍印目前 branch）。
  - `ROUNDS_TOTAL`／`ROUNDS_MAIN`／`ROUNDS_ARCHIVE`：Round 總數與主檔、archive 各自的數量。
  - `STATUS_*`：各 Status 的 Round 數；`BLOCKED_RATIO` 是 BLOCKED 佔總數的百分比（整數）。
  - `CHECKPOINTS`、`KEPT_TOPICS`、`LESSONS_TOPICS`：Checkpoint 區塊、已 keep 主題、Lessons 主題數。
  - `LESSONS_ADVISORY`（有才印）：Lessons Mode 機制性訊號累積次數／門檻。
  - `FIRST_ROUND_AT`／`LAST_ROUND_AT`：第一輪與最後一輪的時間；`none` 表示沒有 Round。

需要機器可讀的輸出（CI、儀表板）時，告訴使用者可以用 `npx devlog-tracker report --json`。
````

- [ ] **Step 3: admin 清單**

`core/scripts/round-start.sh` 的 admin `case` 行，在 `devlog-tracker:pause|` 之後插入 `devlog-tracker:report|`（保持字母序）：

```bash
  devlog-tracker:checkpoint|devlog-tracker:clean|devlog-tracker:compact|devlog-tracker:keep|devlog-tracker:lessons|devlog-tracker:lessons-drift|devlog-tracker:lessons-off|devlog-tracker:lessons-on|devlog-tracker:overview|devlog-tracker:pause|devlog-tracker:report|devlog-tracker:search|devlog-tracker:segment-watch|devlog-tracker:span|devlog-tracker:start|devlog-tracker:status)
```

`skills/devlog-tracker/SKILL.md` 第 316–318 行的清單，在 `` `pause`、`` 之後加 `` `report`、``。

- [ ] **Step 4: 對照表與 README**

`cli/agents-md.js` 的 `codexBlock()` 表格，在 `| 搜尋 / search | … |` 那列之後加：

```
| 統計 / report | \`commands/report.md\` |
```

`cli/platforms/claude.js` 的 `claudeBlock()` 表格，在 `| 長任務定期記錄 / span | … |` 那列之前加同一列。

`README.md` 指令表 `/devlog-tracker:search` 那列之後加：

```
| `/devlog-tracker:report` | Prints devlog stats: round counts (main + archive), per-Status counts, BLOCKED ratio, Checkpoint / kept / lessons counts, and first/last round time. `--all-branches` sums every branch file. Read-only. Also `npx devlog-tracker report [--json]` for machine-readable output. |
```

`README.zh-TW.md` 同位置加：

```
| `/devlog-tracker:report` | 印出 devlog 統計：Round 數（主檔 + archive）、各 Status 數、BLOCKED 比例、Checkpoint／keep／lessons 數量、第一輪與最後一輪時間。`--all-branches` 合計所有 branch 檔。純讀取。機器可讀輸出用 `npx devlog-tracker report [--json]`。 |
```

- [ ] **Step 5: 全部驗證**

Run:
```bash
shellcheck --external-sources --source-path=SCRIPTDIR -S warning \
  core/scripts/*.sh core/scripts/tests/*.sh cursor/hooks/*.sh codex/hooks/*.sh
bash core/scripts/run-tests.sh
npm test
```
Expected: shellcheck 無輸出；`All hook self-checks passed.`；npm test 全 pass

- [ ] **Step 6: Commit**

```bash
git add commands/report.md core/scripts/round-start.sh core/scripts/tests/test-round-start.sh \
  cli/agents-md.js cli/platforms/claude.js skills/devlog-tracker/SKILL.md README.md README.zh-TW.md
git commit -m "feat: /devlog-tracker:report command

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```
