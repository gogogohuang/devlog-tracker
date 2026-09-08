# Fix devlog-tracker Hook Bugs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the three bugs found by `/code-review` in devlog-tracker's hook scripts: a same-second race that can silently skip the mandatory devlog write, a loop-guard that goes dark without `jq`, and a missing `compact` SessionStart matcher.

**Architecture:** No new files beyond one self-check script. Task 1 replaces the mtime-based staleness check in `enforce-devlog.sh` / `round-start.sh` with a content-hash (`cksum`) check — this removes the race by construction instead of patching the boundary condition, and as a side effect deletes the cross-platform GNU/BSD `stat` shim that existed only to support the old approach. Task 2 adds a plain-text fallback for the `stop_hook_active` loop guard when `jq` is absent. Task 3 is a one-line `hooks.json` config change.

**Tech Stack:** POSIX-ish Bash (`#!/usr/bin/env bash`, no bashisms beyond what's already in the repo), `cksum` (POSIX/coreutils, present on macOS and Linux by default — no new dependency), optional `jq`. No test framework in this repo; verification is a plain `assert`-based bash self-check, matching the project's existing style.

**Spec:** No separate spec file — this is a TINY (11-file) repo with no `docs/` beyond this plan. The spec is the three findings from the `/code-review` run in this conversation, reproduced verbatim in each task below.

## Global Constraints

- Every script must stay **fail-open**: any detection failure (missing command, unreadable file, empty value) must `exit 0`, never block a user's turn on the plugin's own bug. This is an existing repo-wide rule (see current `enforce-devlog.sh`/`round-start.sh` comments) — preserve it in every edit.
- No new external dependencies. `cksum` ships with coreutils on both macOS and Linux; do not reach for `md5sum`/`shasum` (less portable) or a new binary.
- Keep comments in Traditional Chinese (zh-TW), matching 100% of existing comments in this repo.
- Preserve the existing `loop guard` → `開關檢查` → per-check fail-open ordering in `enforce-devlog.sh`; only change what's inside each block.
- Do not touch `commands/*.md`, `README.md`, or `skills/devlog-tracker/SKILL.md` — their descriptions ("modified after this round started") remain accurate at the conceptual level after these fixes; only the *how* changes, which is an implementation detail these docs don't describe.

---

### Task 1: Replace mtime race with content-hash check

**Files:**
- Modify: `hooks/scripts/enforce-devlog.sh` (full staleness-check block, currently lines 26-68)
- Modify: `hooks/scripts/round-start.sh` (marker-writing block, currently lines 8-18)
- Test: `hooks/scripts/test-enforce-devlog.sh` (new)

**Interfaces:**
- Consumes: `${CLAUDE_PROJECT_DIR}/.devlog/.enabled` (existence = enforcement on), `${CLAUDE_PROJECT_DIR}/.devlog/devlog.md` (the file being guarded).
- Produces: `${CLAUDE_PROJECT_DIR}/.devlog/.turn-start` now holds the **output of `cksum` on devlog.md at round start** (a string like `"1234567 890 /path/to/devlog.md"`), or the literal string `MISSING` if devlog.md didn't exist yet — replacing its old contents (an epoch-seconds integer). Task 2's loop-guard edit reads/writes a disjoint part of the same file (`enforce-devlog.sh`'s stdin `INPUT` var) and does not depend on this format change.

**Bug being fixed (from code review):**
> mtime comparison uses whole-second granularity, so a devlog write from the previous round and the next round's turn-start can land in the same second and wrongly pass the check. Round N ends and Claude writes devlog.md at wall-clock 14:23:10.9; the Stop hook records that mtime as integer 14:23:10. The user's next message arrives at 14:23:10.1 (same integer second), so round-start.sh writes TURN_START=14:23:10. Round N+1 ends without touching devlog.md; the check `[ "$DEVLOG_MTIME" -lt "$TURN_START" ]` compares 14:23:10 to 14:23:10, which is false, so the hook exits 0 and lets the round end without ever writing a Round N+1 entry — silently defeating the plugin's core guarantee.

- [ ] **Step 1: Write the failing self-check**

Create `hooks/scripts/test-enforce-devlog.sh`:

```bash
#!/usr/bin/env bash
# Self-check for round-start.sh + enforce-devlog.sh cooperating through the
# .devlog/.turn-start marker. No framework — plain assert-and-exit, matching
# this repo's existing style. Run directly:
#   bash hooks/scripts/test-enforce-devlog.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export CLAUDE_PROJECT_DIR="$TMP_ROOT"
DEVLOG_DIR="$TMP_ROOT/.devlog"
mkdir -p "$DEVLOG_DIR"
touch "$DEVLOG_DIR/.enabled"

FAIL=0
assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" -eq "$expected" ]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (expected exit $expected, got $actual)"
    FAIL=1
  fi
}

# --- Scenario 1: round starts, devlog never touched -> must block ---------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "no write during round -> blocked" 2 $?

# --- Scenario 2: round starts, devlog gets a new Round block -> must pass.
# This whole script runs in well under a second, so round-start.sh's marker
# capture and this write below routinely land in the same wall-clock second
# -- exactly the condition that used to race under the old mtime check.
echo "## Round 1 — 2026-09-08T00:00:00+08:00" >> "$DEVLOG_DIR/devlog.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "devlog written this round (same-second race) -> allowed" 0 $?

# --- Scenario 3: next round starts, devlog NOT touched again -> must block
# again, proving the marker was correctly refreshed and isn't just "always
# pass after the first write".
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "no write in the following round -> blocked again" 2 $?

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
```

- [ ] **Step 2: Run it to confirm it fails against the current (buggy) scripts**

Run: `chmod +x hooks/scripts/test-enforce-devlog.sh && bash hooks/scripts/test-enforce-devlog.sh`
Expected: Scenario 1 or 2 reports `FAIL` (exact failure depends on timing — the point is at least one assertion does not yet hold against the mtime-based implementation). If by chance all three pass on this run (timing-dependent race, may not always reproduce), proceed anyway — Step 4 verifies the fix is now correct *by construction*, not just by this run's luck.

- [ ] **Step 3: Implement the minimal fix**

Replace the marker-writing block in `hooks/scripts/round-start.sh` (currently just `date +%s > "$DEVLOG_DIR/.turn-start"`) with content-hash capture. Full new file:

```bash
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

# 沒下過 /devlog-tracker:godev（也就是沒有這個開關檔），代表這個專案沒啟動強制記錄，
# 直接放行，不留下任何 .devlog 檔案。
[ -f "$ENABLED_FLAG" ] || exit 0

if [ -f "$DEVLOG_FILE" ]; then
  cksum "$DEVLOG_FILE" > "$DEVLOG_DIR/.turn-start" 2>/dev/null || true
else
  echo "MISSING" > "$DEVLOG_DIR/.turn-start" 2>/dev/null || true
fi

exit 0
```

Replace the staleness-check block in `hooks/scripts/enforce-devlog.sh` (currently lines 26-68, from `# --- 開關檢查` through the final `exit 0`) — leave the loop-guard block above it untouched for now (Task 2 edits that separately). Full new file (loop guard shown as-is, staleness check rewritten):

```bash
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

# --- loop guard -------------------------------------------------------
INPUT="$(cat 2>/dev/null || true)"
if command -v jq >/dev/null 2>&1; then
  STOP_HOOK_ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
  if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
  fi
fi

# --- 開關檢查 -----------------------------------------------------------
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
ENABLED_FLAG="$DEVLOG_DIR/.enabled"
TURN_MARKER="$DEVLOG_DIR/.turn-start"
DEVLOG_FILE="$DEVLOG_DIR/devlog.md"

# 沒下過 /devlog-tracker:godev，代表這個專案沒啟動強制記錄，直接放行。
# 這是唯一的判斷依據——不猜這輪是否呼叫了某個 skill，也不解析 transcript。
[ -f "$ENABLED_FLAG" ] || exit 0

# 還沒有 turn marker，代表 UserPromptSubmit hook 這次沒跑到（例如剛裝上、
# 或是某種特殊情況），直接放行避免卡住——fail-open。
[ -f "$TURN_MARKER" ] || exit 0

TURN_START_HASH="$(cat "$TURN_MARKER" 2>/dev/null || echo '')"
# marker 內容讀不出來（讀取失敗、被意外改壞等）就當作沒有可靠依據，放行。
[ -n "$TURN_START_HASH" ] || exit 0

if [ -f "$DEVLOG_FILE" ]; then
  CURRENT_HASH="$(cksum "$DEVLOG_FILE" 2>/dev/null || echo '')"
else
  CURRENT_HASH="MISSING"
fi
# 一樣的防呆：雜湊算不出來就放行，不要因為偵測異常反而卡住使用者。
[ -n "$CURRENT_HASH" ] || exit 0

if [ "$CURRENT_HASH" = "$TURN_START_HASH" ]; then
  echo "這一輪還沒有寫進 .devlog/devlog.md。請依 skills/devlog-tracker/SKILL.md 的格式，在檔案尾端補上這一輪的 \`## Round <N>\`（User Input / Response / Status），寫完再結束這一輪。" >&2
  exit 2
fi

exit 0
```

(Task 2 below further edits only the `# --- loop guard` block of this same file.)

- [ ] **Step 4: Run the self-check to confirm it now passes**

Run: `bash hooks/scripts/test-enforce-devlog.sh`
Expected: all three `PASS` lines, then `All checks passed.`, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add hooks/scripts/enforce-devlog.sh hooks/scripts/round-start.sh hooks/scripts/test-enforce-devlog.sh
git commit -m "fix: replace mtime race with content-hash check in Stop hook

Round-start marker now stores cksum(devlog.md) (or MISSING) instead of
an epoch timestamp. Removes the same-second race where a previous
round's write and the next round's turn-start could collide at
whole-second granularity and wrongly let a round end unrecorded.
Also drops the now-unneeded cross-platform GNU/BSD stat shim."
```

---

### Task 2: Loop guard must work without `jq`

**Files:**
- Modify: `hooks/scripts/enforce-devlog.sh:19-24` (the `# --- loop guard` block written in Task 1, Step 3)
- Test: `hooks/scripts/test-enforce-devlog.sh` (extend, from Task 1)

**Interfaces:**
- Consumes: stdin JSON payload (`$INPUT`, already captured by the loop-guard block).
- Produces: same behavior contract as before (`STOP_HOOK_ACTIVE` = `"true"` short-circuits to `exit 0`), now guaranteed regardless of whether `jq` is installed. No other task depends on this internal variable.

**Bug being fixed (from code review):**
> The stop_hook_active loop-guard is silently skipped when `jq` is not installed, since the entire check is wrapped in `if command -v jq`. On a machine without jq, STOP_HOOK_ACTIVE is never set, so the early-exit that prevents re-triggering never fires — the documented "robustness design" silently degrades to a bounded retry storm on any host lacking jq.

- [ ] **Step 1: Extend the self-check with a failing jq-less scenario**

Append to `hooks/scripts/test-enforce-devlog.sh`, before the final `if [ "$FAIL" -eq 0 ]; then` block:

```bash
# --- Scenario 4: stop_hook_active guard must work even without jq --------
PATH_NO_JQ="$TMP_ROOT/no-jq-path"
mkdir -p "$PATH_NO_JQ"
for bin in bash cat printf cksum; do
  bin_path="$(command -v "$bin" 2>/dev/null || true)"
  [ -n "$bin_path" ] && ln -sf "$bin_path" "$PATH_NO_JQ/$bin"
done
echo '{"stop_hook_active":true}' | PATH="$PATH_NO_JQ" bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "stop_hook_active=true without jq -> exits 0 immediately" 0 $?
```

- [ ] **Step 2: Run it to confirm the new scenario fails**

Run: `bash hooks/scripts/test-enforce-devlog.sh`
Expected: `FAIL: stop_hook_active=true without jq -> exits 0 immediately (expected exit 0, got 2)` — the sandboxed `PATH_NO_JQ` has no `jq`, so `STOP_HOOK_ACTIVE` is never set under the current code and the empty devlog.md then trips the Task-1 staleness block instead, returning `2`.

- [ ] **Step 3: Implement the minimal fix**

In `hooks/scripts/enforce-devlog.sh`, replace the loop-guard block:

```bash
# --- loop guard -------------------------------------------------------
INPUT="$(cat 2>/dev/null || true)"
if command -v jq >/dev/null 2>&1; then
  STOP_HOOK_ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
  if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
  fi
fi
```

with:

```bash
# --- loop guard -------------------------------------------------------
# 有 jq 就用 jq 精準解析；沒有 jq 就退化成字串比對（沒有更嚴謹的 parse，但
# 足以涵蓋 Claude Code 實際送出的 stop_hook_active 欄位形狀），兩種環境都要生效。
INPUT="$(cat 2>/dev/null || true)"
if command -v jq >/dev/null 2>&1; then
  STOP_HOOK_ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
else
  case "$INPUT" in
    *'"stop_hook_active"'*true*) STOP_HOOK_ACTIVE=true ;;
    *)                           STOP_HOOK_ACTIVE=false ;;
  esac
fi
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi
```

- [ ] **Step 4: Run the self-check to confirm all scenarios now pass**

Run: `bash hooks/scripts/test-enforce-devlog.sh`
Expected: four `PASS` lines, then `All checks passed.`, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add hooks/scripts/enforce-devlog.sh hooks/scripts/test-enforce-devlog.sh
git commit -m "fix: loop guard now works without jq installed

Falls back to a plain string match on stop_hook_active when jq is
unavailable, instead of silently never triggering the guard."
```

---

### Task 3: Add `compact` to the SessionStart matcher

**Files:**
- Modify: `hooks/hooks.json:5`

**Interfaces:**
- Consumes: nothing (static config).
- Produces: nothing other consuming code reads — Claude Code's own hook dispatcher reads this matcher string.

**Bug being fixed (from code review):**
> SessionStart matcher is `"startup|resume|clear"`, omitting `compact`, so devlog context is not reinjected after a `/compact`. Claude Code's SessionStart hook supports a `compact` source specifically for reinserting context lost during compaction — exactly the moment the plugin's stated goal ("讓工作可以隨時中斷、隨時接續") is most needed.

This is a one-line config value with no branch or loop — trivial per this repo's own testing bar, no self-check needed.

- [ ] **Step 1: Verify `compact` is a valid SessionStart source in the installed Claude Code version**

Run: `claude --version` and check the Claude Code hooks reference (or `/help` inside a session) for the current list of valid `SessionStart` matcher values. If `compact` is not yet supported by the installed version, stop here and skip this task — do not add an untested matcher value.

- [ ] **Step 2: Make the change**

In `hooks/hooks.json`, change:

```json
        "matcher": "startup|resume|clear",
```

to:

```json
        "matcher": "startup|resume|clear|compact",
```

- [ ] **Step 3: Manually verify**

Run `/compact` inside a test project that has `.devlog/.enabled` and a non-empty `.devlog/devlog.md`, and confirm the devlog summary is printed as injected context right after compaction (same text `session-start-devlog.sh` produces on `startup`/`resume`/`clear`).

- [ ] **Step 4: Commit**

```bash
git add hooks/hooks.json
git commit -m "fix: reinject devlog context after /compact

SessionStart matcher was missing the compact source, so devlog
progress wasn't reinjected at the exact moment context gets
trimmed mid-session."
```

---

## Self-Review Notes

- **Spec coverage:** all three `/code-review` findings map 1:1 to Task 1, Task 2, Task 3. No gaps.
- **Placeholder scan:** no TBD/TODO; every step has full file contents or exact diffs, not descriptions.
- **Type/interface consistency:** `.devlog/.turn-start` content format (Task 1) is produced once by `round-start.sh` and consumed once by `enforce-devlog.sh`; both are rewritten together in the same task so they can't drift. Task 2 only touches a local shell variable (`STOP_HOOK_ACTIVE`) already scoped to `enforce-devlog.sh`. Task 3 touches unrelated config. No cross-task signature mismatches possible.
