# Start / pause scripts and gitignore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `/devlog-tracker:start` and `/pause` create or delete switch files via bash, and tell the user if the consumer repo should gitignore `.devlog/`.

**Architecture:** Two new scripts own the filesystem mutations. The command markdown files only invoke the script, then (start only) summarise `devlog.md` and optionally append `.devlog/` to `.gitignore` after the user agrees. Do not auto-edit `.gitignore`.

**Tech Stack:** bash, existing assert-and-exit self-checks, Claude Code command markdown.

## Global Constraints

- Fail-open is for *hooks*. These scripts are user-invoked; they may `exit 1` on real errors (cannot mkdir).
- Do not rewrite `devlog.md`. Do not create `devlog.md` on start.
- If `.checkpoint-state` / `.segment-state` already exist, do not reset `max_silent_rounds` / `max_silent_seconds`.
- Pause deletes `.enabled`, `.span-open`, `.round-open`, `.interrupted` only.
- Do not bump version. Batch release is **0.5.0** after all optimization plans (`docs/design/version-0.5.0-plan.md`).
- Command copy is Traditional Chinese.
- This repo gitignores `docs/superpowers/`. This plan lives under `docs/design/`.
- Script path in commands: `bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/start-devlog.sh"` (plugin env). If that variable is empty, Claude uses this plugin's root (the directory that contains `.claude-plugin/plugin.json`).

## File Structure

| File | Responsibility |
|---|---|
| `hooks/scripts/start-devlog.sh` | mkdir `.devlog`, touch `.enabled`, create missing state JSON |
| `hooks/scripts/pause-devlog.sh` | delete switch files |
| `hooks/scripts/test-start-pause-devlog.sh` | self-check |
| `commands/start.md` | run script, summarise log, ask about gitignore |
| `commands/pause.md` | run script, report |

---

### Task 1: start / pause scripts and tests

**Files:**
- Create: `hooks/scripts/start-devlog.sh`
- Create: `hooks/scripts/pause-devlog.sh`
- Create: `hooks/scripts/test-start-pause-devlog.sh`

**Interfaces:**
- Consumes: `CLAUDE_PROJECT_DIR` (default `.`); consumer `.gitignore` (read-only)
- Produces: stdout lines Claude can relay. Start always prints `GITIGNORE_DEVLOG=yes` or `GITIGNORE_DEVLOG=no`.

- [ ] **Step 1: Write the failing self-check**

Create `hooks/scripts/test-start-pause-devlog.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
export CLAUDE_PROJECT_DIR="$TMP_ROOT"
FAIL=0
assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" -eq "$expected" ]; then echo "PASS: $desc"
  else echo "FAIL: $desc (expected $expected got $actual)"; FAIL=1; fi
}
assert_file() {
  local desc="$1" path="$2"
  if [ -f "$path" ]; then echo "PASS: $desc"
  else echo "FAIL: $desc"; FAIL=1; fi
}
assert_not_file() {
  local desc="$1" path="$2"
  if [ ! -f "$path" ]; then echo "PASS: $desc"
  else echo "FAIL: $desc"; FAIL=1; fi
}

# start on empty project
OUT="$(bash "$SCRIPT_DIR/start-devlog.sh")"
assert_exit "start empty -> 0" 0 $?
assert_file ".enabled" "$TMP_ROOT/.devlog/.enabled"
assert_file "checkpoint" "$TMP_ROOT/.devlog/.checkpoint-state"
assert_file "segment" "$TMP_ROOT/.devlog/.segment-state"
assert_not_file "no devlog.md created" "$TMP_ROOT/.devlog/devlog.md"
case "$OUT" in
  *"GITIGNORE_DEVLOG=no"*) echo "PASS: reports missing gitignore entry" ;;
  *) echo "FAIL: expected GITIGNORE_DEVLOG=no, got $OUT"; FAIL=1 ;;
esac
grep -q '"max_silent_rounds": 20' "$TMP_ROOT/.devlog/.checkpoint-state" \
  && echo "PASS: default checkpoint" || { echo "FAIL: checkpoint defaults"; FAIL=1; }
grep -q '"max_silent_seconds": 900' "$TMP_ROOT/.devlog/.segment-state" \
  && echo "PASS: default segment" || { echo "FAIL: segment defaults"; FAIL=1; }

# preserve thresholds on second start
printf '%s\n' '{"rounds_since_checkpoint": 7, "max_silent_rounds": 3, "checkpoint_marker_count": 1}' \
  > "$TMP_ROOT/.devlog/.checkpoint-state"
printf '%s\n' '{"last_change_epoch": 1, "last_seen_cksum": "x", "max_silent_seconds": 60}' \
  > "$TMP_ROOT/.devlog/.segment-state"
bash "$SCRIPT_DIR/start-devlog.sh" >/dev/null
grep -q '"max_silent_rounds": 3' "$TMP_ROOT/.devlog/.checkpoint-state" \
  && echo "PASS: start does not reset max_silent_rounds" || { echo "FAIL: checkpoint reset"; FAIL=1; }
grep -q '"max_silent_seconds": 60' "$TMP_ROOT/.devlog/.segment-state" \
  && echo "PASS: start does not reset max_silent_seconds" || { echo "FAIL: segment reset"; FAIL=1; }

# gitignore already has .devlog/
echo '.devlog/' > "$TMP_ROOT/.gitignore"
OUT="$(bash "$SCRIPT_DIR/start-devlog.sh")"
case "$OUT" in
  *"GITIGNORE_DEVLOG=yes"*) echo "PASS: detects gitignore entry" ;;
  *) echo "FAIL: expected GITIGNORE_DEVLOG=yes, got $OUT"; FAIL=1 ;;
esac

# pause
touch "$TMP_ROOT/.devlog/.span-open" "$TMP_ROOT/.devlog/.round-open" "$TMP_ROOT/.devlog/.interrupted"
echo 'keep me' > "$TMP_ROOT/.devlog/devlog.md"
OUT="$(bash "$SCRIPT_DIR/pause-devlog.sh")"
assert_exit "pause -> 0" 0 $?
assert_not_file "enabled gone" "$TMP_ROOT/.devlog/.enabled"
assert_not_file "span gone" "$TMP_ROOT/.devlog/.span-open"
assert_not_file "round-open gone" "$TMP_ROOT/.devlog/.round-open"
assert_not_file "interrupted gone" "$TMP_ROOT/.devlog/.interrupted"
assert_file "log kept" "$TMP_ROOT/.devlog/devlog.md"
assert_file "checkpoint kept" "$TMP_ROOT/.devlog/.checkpoint-state"

# pause when never started
rm -rf "$TMP_ROOT/.devlog"
OUT="$(bash "$SCRIPT_DIR/pause-devlog.sh")"
assert_exit "pause never-started -> 0" 0 $?
case "$OUT" in
  *"NOT_ENABLED"*) echo "PASS: pause reports NOT_ENABLED" ;;
  *) echo "FAIL: expected NOT_ENABLED, got $OUT"; FAIL=1 ;;
esac

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
```

chmod +x is not required; tests run via `bash`.

- [ ] **Step 2: Run it to verify it fails**

```bash
bash hooks/scripts/test-start-pause-devlog.sh
```

Expected: FAIL because `start-devlog.sh` / `pause-devlog.sh` are missing.

- [ ] **Step 3: Write `hooks/scripts/start-devlog.sh`**

```bash
#!/usr/bin/env bash
# User-invoked: /devlog-tracker:start filesystem side.
set -uo pipefail
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
mkdir -p "$DEVLOG_DIR" || exit 1
if [ ! -f "$DEVLOG_DIR/.enabled" ]; then
  date -Iseconds > "$DEVLOG_DIR/.enabled" 2>/dev/null || echo enabled > "$DEVLOG_DIR/.enabled"
fi
if [ ! -f "$DEVLOG_DIR/.checkpoint-state" ]; then
  printf '%s\n' '{"rounds_since_checkpoint": 0, "max_silent_rounds": 20, "checkpoint_marker_count": 0}' \
    > "$DEVLOG_DIR/.checkpoint-state" || exit 1
fi
if [ ! -f "$DEVLOG_DIR/.segment-state" ]; then
  printf '%s\n' '{"last_change_epoch": 0, "last_seen_cksum": "", "max_silent_seconds": 900}' \
    > "$DEVLOG_DIR/.segment-state" || exit 1
fi
GITIGNORE_DEVLOG=no
if [ -f "$PROJECT_DIR/.gitignore" ] && grep -E -q '(^|/)\.devlog(/|$)' "$PROJECT_DIR/.gitignore"; then
  GITIGNORE_DEVLOG=yes
fi
echo "ENABLED=$DEVLOG_DIR/.enabled"
echo "GITIGNORE_DEVLOG=$GITIGNORE_DEVLOG"
exit 0
```

- [ ] **Step 4: Write `hooks/scripts/pause-devlog.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
if [ ! -f "$DEVLOG_DIR/.enabled" ]; then
  echo "NOT_ENABLED"
  exit 0
fi
rm -f "$DEVLOG_DIR/.enabled" "$DEVLOG_DIR/.span-open" \
  "$DEVLOG_DIR/.round-open" "$DEVLOG_DIR/.interrupted"
echo "PAUSED"
exit 0
```

- [ ] **Step 5: Run tests**

```bash
bash hooks/scripts/test-start-pause-devlog.sh
```

Expected: `All checks passed.`

- [ ] **Step 6: Commit**

```bash
git add hooks/scripts/start-devlog.sh hooks/scripts/pause-devlog.sh hooks/scripts/test-start-pause-devlog.sh
git commit -m "$(cat <<'EOF'
feat: script start and pause so state files are not LLM-authored

EOF
)"
```

---

### Task 2: Command files

**Files:**
- Modify: `commands/start.md` (replace filesystem steps 1–4 with a script invocation)
- Modify: `commands/pause.md`

**Interfaces:**
- Consumes: script stdout `GITIGNORE_DEVLOG` / `NOT_ENABLED` / `PAUSED`
- Produces: user-facing Traditional Chinese; gitignore append only after explicit yes

- [ ] **Step 1: Replace `commands/start.md` with**

```markdown
---
description: 啟動這個專案的 devlog 強制記錄機制。之後每一輪結束前都會被 Stop hook 檢查，沒寫 devlog 就不能結束。
---

請執行以下步驟：

1. 跑這支腳本（環境變數 `CLAUDE_PLUGIN_ROOT` 若有值就用它；否則用這個 plugin 根目錄，也就是含 `.claude-plugin/plugin.json` 的那一層）：
   ```bash
   CLAUDE_PROJECT_DIR="$(pwd)" bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/start-devlog.sh"
   ```
   不要自己用手建 `.enabled` / `.checkpoint-state` / `.segment-state`。
2. 若 stdout 有 `GITIGNORE_DEVLOG=no`：告訴使用者 `.devlog/` 會含 prompt，建議把 `.devlog/` 加進專案 `.gitignore`。問要不要現在加。只有使用者明確說要，才在 `.gitignore` 末尾追加一行 `.devlog/`（檔案不存在就建立）。不要改其他行。
3. 讀取 `.devlog/devlog.md`（若存在）：
   - 有內容：摘要目前進度，跟使用者確認「上次做到哪、狀態是什麼」
   - 不存在：告知使用者這是全新開始，準備寫下 Round 1
4. 告訴使用者：從現在開始，每一則使用者訊息送出時就會先寫 User Input skeleton，結束前仍要補 Summary / Handoff；同一輪約 15 分鐘沒改這個檔，下一個工具會被要求先補 `### 段落`；可以用 `/devlog-tracker:pause` 關掉。

不要因為 `.enabled` 已經存在就跳過步驟 3。`/clear` 之後若要接著做上一題，用 `/devlog-tracker:continue`，不要用 start 開工。
```

- [ ] **Step 2: Replace `commands/pause.md` with**

```markdown
---
description: 暫停這個專案的 devlog 強制記錄機制。不會刪除任何歷史紀錄，只是之後 Stop 與 PreToolUse hook 都因 `.enabled` 移除而停止檢查。
---

請執行：

1. 跑：
   ```bash
   CLAUDE_PROJECT_DIR="$(pwd)" bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/pause-devlog.sh"
   ```
   不要自己刪 `.enabled`。
2. stdout 是 `NOT_ENABLED`：告知這個專案本來就沒有啟動強制記錄，結束。
3. stdout 是 `PAUSED`：告知強制記錄已暫停，歷史都還在，可用 `/devlog-tracker:start` 再開。

不要動 `.devlog/devlog.md`、`.checkpoint-state`、`.segment-state`。
```

- [ ] **Step 3: Grep checklist**

```bash
grep -q 'start-devlog.sh' commands/start.md && echo PASS || echo FAIL
grep -q 'pause-devlog.sh' commands/pause.md && echo PASS || echo FAIL
grep -q 'GITIGNORE_DEVLOG' commands/start.md && echo PASS || echo FAIL
```

Expected: three `PASS`.

- [ ] **Step 4: Commit**

```bash
git add commands/start.md commands/pause.md
git commit -m "$(cat <<'EOF'
feat: point start and pause commands at the new scripts

EOF
)"
```

