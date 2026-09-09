# Segment Watch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a PreToolUse silence valve that blocks the next tool after 15 minutes with no `devlog.md` hash change, until Claude appends a mid-round note.

**Architecture:** Authoring stays judgment-based `### 段落` in SKILL.md. Enforcement is a new `segment-watch.sh` on PreToolUse, using `.devlog/.segment-state` (`last_change_epoch`, `last_seen_cksum`, `max_silent_seconds`). `round-start.sh` resets the clock each `UserPromptSubmit`. Stop / span / checkpoint logic is unchanged.

**Tech Stack:** bash hooks, `cksum`, `date +%s`, optional `jq` for PreToolUse stdin; existing assert-and-exit self-check style.

## Global Constraints

- Spec: `docs/design/segment-watch.md`. Do not invent extra checks (no `### 段落` heading requirement, no background timer, no hook-authored `devlog.md`, no JSON `permissionDecision`).
- Block only on silence: `now - last_change_epoch >= max_silent_seconds` and the current `devlog.md` cksum still equals `last_seen_cksum`.
- Default `max_silent_seconds` is `900`. No enforced range. `/start` must not overwrite it when the file already exists.
- Allowlist while expired: `tool_name` is `Write` or `Edit`, and `tool_input.file_path` is exactly `.devlog/devlog.md` or ends with `/.devlog/devlog.md`. String suffix only; no `realpath`.
- Fail-open (`exit 0`): missing `.enabled`, missing/malformed `.segment-state`, non-numeric epoch/max, failed `date`/`cksum`, unreadable stdin.
- Block with `exit 2` + stderr, same as `enforce-devlog.sh`.
- Do not skip the valve when a span is open. Do not reset `rounds_since_checkpoint` on a segment write.
- Do not change `enforce-devlog.sh`. Do not bump plugin version.
- This repo gitignores `docs/superpowers/`. Plans live under `docs/design/`.
- Block stderr (exact): `這一輪已經 ${ELAPSED} 秒沒有更新 .devlog/devlog.md（門檻 ${SEG_MAX} 秒）。請先追加一段「### 段落」（一行也可以），寫完再繼續呼叫工具。`

## File Structure

| File | Responsibility |
|---|---|
| `hooks/scripts/segment-watch.sh` | PreToolUse: detect hash change, allowlist Write/Edit on `devlog.md`, else enforce the silence threshold |
| `hooks/scripts/test-segment-watch.sh` | Self-check for the above plus `round-start.sh` clock reset |
| `hooks/scripts/round-start.sh` | Each enabled round: reset `last_change_epoch` / `last_seen_cksum`, keep `max_silent_seconds` |
| `hooks/hooks.json` | Register PreToolUse → `segment-watch.sh` |
| `commands/start.md` | Create `.segment-state` if missing |
| `commands/pause.md` | State that `.segment-state` is left in place |
| `skills/devlog-tracker/SKILL.md` | Document the 15-minute valve under Round Segments |
| `docs/design/checkpoint-mode.md` | Point Round Segments at this valve |
| `README.md` | User-facing mention + directory tree |

Do not create a new language or test framework. Do not modify `enforce-devlog.sh`.

---

### Task 1: PreToolUse silence valve

**Files:**
- Create: `hooks/scripts/test-segment-watch.sh`
- Create: `hooks/scripts/segment-watch.sh`
- Test: `bash hooks/scripts/test-segment-watch.sh`

**Interfaces:**
- Consumes: `CLAUDE_PROJECT_DIR`, `.enabled`, `.devlog/devlog.md`, `.segment-state`, PreToolUse stdin JSON (`tool_name`, `tool_input.file_path`).
- Produces: `exit 0` when disabled, fail-open, hash changed, Write/Edit on `devlog.md`, or elapsed `< max`; `exit 2` with the exact stderr sentence above when silent too long; persists `last_change_epoch` + `last_seen_cksum` on hash change (does not rewrite `max_silent_seconds`).

- [ ] **Step 1: Write the failing self-check**

Create `hooks/scripts/test-segment-watch.sh` with this exact content:

```bash
#!/usr/bin/env bash
# Self-check for segment-watch.sh (+ round-start.sh clock reset in later
# scenarios). No framework — plain assert-and-exit. Run directly:
#   bash hooks/scripts/test-segment-watch.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export CLAUDE_PROJECT_DIR="$TMP_ROOT"
DEVLOG_DIR="$TMP_ROOT/.devlog"
mkdir -p "$DEVLOG_DIR"
touch "$DEVLOG_DIR/.enabled"
printf 'seed\n' > "$DEVLOG_DIR/devlog.md"
SEED_CKSUM="$(cksum < "$DEVLOG_DIR/devlog.md" | tr -d '\n')"

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

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*) echo "PASS: $desc" ;;
    *) echo "FAIL: $desc (missing: $needle)"; FAIL=1 ;;
  esac
}

write_state() {
  local epoch="$1" sum="$2" max="$3"
  printf '{"last_change_epoch": %s, "last_seen_cksum": "%s", "max_silent_seconds": %s}\n' \
    "$epoch" "$sum" "$max" > "$DEVLOG_DIR/.segment-state"
}

NOW="$(date +%s)"
EXPIRED="$((NOW - 960))"
BASH_PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"echo hi"}}'
WRITE_REL='{"tool_name":"Write","tool_input":{"file_path":".devlog/devlog.md"}}'
WRITE_ABS="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.devlog/devlog.md"}}' "$TMP_ROOT")"
WRITE_OTHER='{"tool_name":"Write","tool_input":{"file_path":"src/foo.ts"}}'
EDIT_REL='{"tool_name":"Edit","tool_input":{"file_path":".devlog/devlog.md"}}'

# --- Scenario 1: no .enabled -> exit 0 ------------------------------------
rm -f "$DEVLOG_DIR/.enabled"
write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' "$BASH_PAYLOAD" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "no .enabled -> allowed" 0 $?
touch "$DEVLOG_DIR/.enabled"

# --- Scenario 2: fresh clock, Bash immediately -> exit 0 --------------------
write_state "$NOW" "$SEED_CKSUM" 900
printf '%s' "$BASH_PAYLOAD" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "fresh epoch, Bash -> allowed" 0 $?

# --- Scenario 3: expired + Bash -> exit 2 + stderr phrase -------------------
write_state "$EXPIRED" "$SEED_CKSUM" 900
ERR="$(printf '%s' "$BASH_PAYLOAD" | bash "$SCRIPT_DIR/segment-watch.sh" 2>&1 >/dev/null)"
assert_exit "expired + Bash -> blocked" 2 $?
assert_contains "block message names ### 段落" "### 段落" "$ERR"
assert_contains "block message names 門檻 900" "門檻 900 秒" "$ERR"

# --- Scenario 4: expired + Write relative devlog.md -> exit 0 ---------------
write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' "$WRITE_REL" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + Write .devlog/devlog.md -> allowed" 0 $?

# --- Scenario 5: expired + Write absolute path ending in /.devlog/devlog.md -
write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' "$WRITE_ABS" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + Write absolute /.devlog/devlog.md -> allowed" 0 $?

# --- Scenario 6: expired + Edit relative devlog.md -> exit 0 -----------------
write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' "$EDIT_REL" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + Edit .devlog/devlog.md -> allowed" 0 $?

# --- Scenario 7: expired + Write other file -> exit 2 -----------------------
write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' "$WRITE_OTHER" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + Write other file -> blocked" 2 $?

# --- Scenario 8: hash changed since last_seen -> exit 0 and persist ---------
write_state "$EXPIRED" "stale-sum" 900
printf '%s' "$BASH_PAYLOAD" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "hash differs from last_seen_cksum -> allowed" 0 $?
SEEN_AFTER="$(grep -o '"last_seen_cksum"[[:space:]]*:[[:space:]]*"[^"]*"' "$DEVLOG_DIR/.segment-state" | sed 's/.*"last_seen_cksum"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
EPOCH_AFTER="$(grep -o '"last_change_epoch"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.segment-state" | grep -o '[0-9]\+$')"
MAX_AFTER="$(grep -o '"max_silent_seconds"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.segment-state" | grep -o '[0-9]\+$')"
if [ "$SEEN_AFTER" = "$SEED_CKSUM" ] && [ "$EPOCH_AFTER" -ge "$NOW" ] && [ "$MAX_AFTER" = "900" ]; then
  echo "PASS: hash-change persist updated cksum/epoch and left max_silent_seconds=900"
else
  echo "FAIL: persist expected cksum=$SEED_CKSUM epoch>=$NOW max=900, got cksum=$SEEN_AFTER epoch=$EPOCH_AFTER max=$MAX_AFTER"
  FAIL=1
fi

# --- Scenario 9: malformed state -> fail-open --------------------------------
echo 'not json' > "$DEVLOG_DIR/.segment-state"
printf '%s' "$BASH_PAYLOAD" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "malformed .segment-state -> allowed" 0 $?

# --- Scenario 10: missing .segment-state -> fail-open ------------------------
rm -f "$DEVLOG_DIR/.segment-state"
printf '%s' "$BASH_PAYLOAD" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "missing .segment-state -> allowed" 0 $?

# --- Scenario 11: span open does NOT disable the valve ----------------------
write_state "$EXPIRED" "$SEED_CKSUM" 900
cat > "$DEVLOG_DIR/.span-open" <<'SPANEOF'
{"round": 1, "opened_at": "2026-09-09T00:00:00+08:00", "ticks_since_checkin": 1, "max_silent_ticks": 5}
SPANEOF
printf '%s' "$BASH_PAYLOAD" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + open under-budget span + Bash -> still blocked" 2 $?
rm -f "$DEVLOG_DIR/.span-open"

# --- Scenario 12: no jq, expired + Bash still blocks ------------------------
PATH_NO_JQ="$TMP_ROOT/no-jq-path"
mkdir -p "$PATH_NO_JQ"
for bin in bash cat printf cksum date grep sed awk mv tr head; do
  bin_path="$(command -v "$bin" 2>/dev/null || true)"
  [ -n "$bin_path" ] && ln -sf "$bin_path" "$PATH_NO_JQ/$bin"
done
write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' "$BASH_PAYLOAD" | PATH="$PATH_NO_JQ" bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + Bash without jq -> blocked" 2 $?
write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' "$WRITE_REL" | PATH="$PATH_NO_JQ" bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + Write without jq -> allowed" 0 $?

# --- Scenario 13: round-start.sh resets clock and preserves max -------------
write_state 1 "old-sum" 600
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
RS_EPOCH="$(grep -o '"last_change_epoch"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.segment-state" | grep -o '[0-9]\+$')"
RS_SUM="$(grep -o '"last_seen_cksum"[[:space:]]*:[[:space:]]*"[^"]*"' "$DEVLOG_DIR/.segment-state" | sed 's/.*"last_seen_cksum"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
RS_MAX="$(grep -o '"max_silent_seconds"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.segment-state" | grep -o '[0-9]\+$')"
if [ "$RS_EPOCH" -ge "$NOW" ] && [ "$RS_SUM" = "$SEED_CKSUM" ] && [ "$RS_MAX" = "600" ]; then
  echo "PASS: round-start.sh reset epoch/cksum and kept max_silent_seconds=600"
else
  echo "FAIL: round-start expected epoch>=$NOW cksum=$SEED_CKSUM max=600, got epoch=$RS_EPOCH cksum=$RS_SUM max=$RS_MAX"
  FAIL=1
fi
printf '%s' "$BASH_PAYLOAD" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "immediately after round-start.sh, Bash -> allowed" 0 $?

# --- Scenario 14: missing last_seen_cksum key -> fail-open ------------------
printf '{"last_change_epoch": 1, "max_silent_seconds": 900}\n' > "$DEVLOG_DIR/.segment-state"
printf '%s' "$BASH_PAYLOAD" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "segment-state missing last_seen_cksum key -> allowed" 0 $?

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
```

- [ ] **Step 2: Run the self-check and confirm it fails**

Run: `bash hooks/scripts/test-segment-watch.sh`

Expected: fails immediately (`No such file or directory: .../segment-watch.sh`) or later FAIL on Scenario 13 if you create an empty `segment-watch.sh` that only `exit 0`. Do not implement yet. Current `round-start.sh` does not write `.segment-state`, so Scenario 13 would FAIL even after a stub that always exits 0.

- [ ] **Step 3: Implement `segment-watch.sh`**

Create `hooks/scripts/segment-watch.sh` with this exact content:

```bash
#!/usr/bin/env bash
# PreToolUse hook：同一輪若太久沒改 devlog.md，擋住下一個工具，逼補 ### 段落。
# fail-open：這支腳本自己出錯一律 exit 0，不該卡死使用者的 session。

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
ENABLED_FLAG="$DEVLOG_DIR/.enabled"
DEVLOG_FILE="$DEVLOG_DIR/devlog.md"
SEGMENT_FILE="$DEVLOG_DIR/.segment-state"

[ -f "$ENABLED_FLAG" ] || exit 0
[ -f "$SEGMENT_FILE" ] || exit 0

INPUT="$(cat 2>/dev/null || true)"

SEG_EPOCH="$(grep -o '"last_change_epoch"[[:space:]]*:[[:space:]]*[0-9]\+' "$SEGMENT_FILE" 2>/dev/null | grep -o '[0-9]\+$' || echo '')"
SEG_MAX="$(grep -o '"max_silent_seconds"[[:space:]]*:[[:space:]]*[0-9]\+' "$SEGMENT_FILE" 2>/dev/null | grep -o '[0-9]\+$' || echo '')"
SEG_SUM="$(grep -o '"last_seen_cksum"[[:space:]]*:[[:space:]]*"[^"]*"' "$SEGMENT_FILE" 2>/dev/null | sed 's/.*"last_seen_cksum"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo '')"
SEG_SUM_KEY="$(grep -o '"last_seen_cksum"[[:space:]]*:' "$SEGMENT_FILE" 2>/dev/null || echo '')"

case "$SEG_EPOCH" in ''|*[!0-9]*) exit 0 ;; esac
case "$SEG_MAX" in ''|*[!0-9]*) exit 0 ;; esac
[ -n "$SEG_SUM_KEY" ] || exit 0

persist_seen() {
  local epoch="$1" sum="$2"
  awk -v epoch="$epoch" -v sum="$sum" '{
    gsub(/"last_change_epoch"[[:space:]]*:[[:space:]]*[0-9]+/, "\"last_change_epoch\": " epoch);
    gsub(/"last_seen_cksum"[[:space:]]*:[[:space:]]*"[^"]*"/, "\"last_seen_cksum\": \"" sum "\"");
    print
  }' "$SEGMENT_FILE" > "$SEGMENT_FILE.tmp" 2>/dev/null \
    && mv "$SEGMENT_FILE.tmp" "$SEGMENT_FILE" 2>/dev/null || true
}

NOW="$(date +%s 2>/dev/null || echo '')"
case "$NOW" in ''|*[!0-9]*) exit 0 ;; esac

if [ -f "$DEVLOG_FILE" ]; then
  CURRENT="$(cksum < "$DEVLOG_FILE" 2>/dev/null | tr -d '\n' || echo '')"
else
  CURRENT="MISSING"
fi
[ -n "$CURRENT" ] || exit 0

if [ "$CURRENT" != "$SEG_SUM" ]; then
  persist_seen "$NOW" "$CURRENT"
  exit 0
fi

TOOL_NAME=""
FILE_PATH=""
if command -v jq >/dev/null 2>&1; then
  TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo '')"
  FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo '')"
else
  case "$INPUT" in
    *'"tool_name":"Write"'*|*'"tool_name": "Write"'*) TOOL_NAME=Write ;;
    *'"tool_name":"Edit"'*|*'"tool_name": "Edit"'*)   TOOL_NAME=Edit ;;
  esac
  FILE_PATH="$(printf '%s' "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo '')"
fi

if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ]; then
  case "$FILE_PATH" in
    .devlog/devlog.md|*/.devlog/devlog.md) exit 0 ;;
  esac
fi

ELAPSED=$((NOW - SEG_EPOCH))
if [ "$ELAPSED" -ge "$SEG_MAX" ]; then
  echo "這一輪已經 ${ELAPSED} 秒沒有更新 .devlog/devlog.md（門檻 ${SEG_MAX} 秒）。請先追加一段「### 段落」（一行也可以），寫完再繼續呼叫工具。" >&2
  exit 2
fi

exit 0
```

Then `chmod +x hooks/scripts/segment-watch.sh hooks/scripts/test-segment-watch.sh`.

- [ ] **Step 4: Implement the `round-start.sh` clock reset**

In `hooks/scripts/round-start.sh`, add `SEGMENT_FILE` next to the other path variables:

```bash
SEGMENT_FILE="$DEVLOG_DIR/.segment-state"
```

Immediately before the final `exit 0`, add:

```bash
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
```

- [ ] **Step 5: Run both self-checks**

Run:

```
bash hooks/scripts/test-segment-watch.sh
bash hooks/scripts/test-enforce-devlog.sh
bash hooks/scripts/test-session-start-devlog.sh
```

Expected: all three print `All checks passed.`

- [ ] **Step 6: Commit**

```bash
git add hooks/scripts/segment-watch.sh hooks/scripts/test-segment-watch.sh hooks/scripts/round-start.sh
git commit -m "$(cat <<'EOF'
Add a 15-minute mid-round PreToolUse valve for silent devlog writes.

EOF
)"
```

---

### Task 2: Wire start/pause, hooks.json, and docs

**Files:**
- Modify: `hooks/hooks.json`
- Modify: `commands/start.md`
- Modify: `commands/pause.md`
- Modify: `skills/devlog-tracker/SKILL.md`
- Modify: `docs/design/checkpoint-mode.md`
- Modify: `README.md`
- Test: `bash hooks/scripts/test-segment-watch.sh` (still green; this task is wiring + copy)

**Interfaces:**
- Consumes: Task 1 scripts and `.segment-state` shape `{last_change_epoch, last_seen_cksum, max_silent_seconds}`.
- Produces: PreToolUse registration; `/start` creates the state file if missing; SKILL/README/checkpoint-mode describe the valve without changing Stop-hook behavior.

- [ ] **Step 1: Register PreToolUse in `hooks/hooks.json`**

Replace the file with:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/session-start-devlog.sh\""
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/round-start.sh\""
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/segment-watch.sh\""
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/enforce-devlog.sh\""
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Create `.segment-state` from `/devlog-tracker:start`**

In `commands/start.md`, insert this as a new step 4 and renumber the old 4→5 and 5→6:

```markdown
4. 建立（若已存在就略過，尤其不要改掉已有的 `max_silent_seconds`）`.devlog/.segment-state`，內容是：
   ```json
   {"last_change_epoch": 0, "last_seen_cksum": "", "max_silent_seconds": 900}
   ```
   這個檔案讓 PreToolUse hook 能追蹤「這一輪多久沒改 `devlog.md`」。預設 900 秒
   （15 分鐘）沒動就會擋住下一個工具、要求先補 `### 段落`；可以直接編輯
   `max_silent_seconds` 調整門檻，見 `skills/devlog-tracker/SKILL.md` 的段落說明。
```

Also extend the user-facing sentence in the (now) step 6 so it mentions the mid-round valve:

```markdown
6. 告訴使用者：從現在開始，每一輪結束前都會被要求先把這輪寫進 `.devlog/devlog.md`
   （User Input / Summary / Handoff / Status）；同一輪若連續約 15 分鐘沒改這個檔，
   下一個工具會被要求先補一段 `### 段落`；累積到一定輪數沒寫 checkpoint 摘要時也會被
   提醒補上，可以用 `/devlog-tracker:pause` 隨時關掉這個強制機制。
```

- [ ] **Step 3: Tell `/pause` not to delete `.segment-state`**

In `commands/pause.md`, after the existing `.span-open` bullet, add:

```markdown
3. 不要刪 `.devlog/.segment-state` 或 `.devlog/.checkpoint-state`——暫停只關強制，
   門檻數字要留到下次 `/devlog-tracker:start`。
```

Renumber the old "告知使用者" step from 3 to 4.

- [ ] **Step 4: Update Round Segments copy in SKILL.md**

In `skills/devlog-tracker/SKILL.md`, replace these two paragraphs:

```markdown
機制上不需要任何 hook 改動——現有的雜湊比對本來就只看 `devlog.md` 這輪結束時有
沒有變，不管中途寫了幾次。這純粹是格式規範，讓「邊做邊寫」變成預設習慣。

收尾時 Stop hook 仍會要求最後一個 Round 上看得到 `### Summary` 與 `### Handoff`。
```

with:

```markdown
主路徑仍是判斷何時寫段落，不是照時間機械切段。另外有一道保底：`/devlog-tracker:start`
之後，同一輪若連續 15 分鐘（`max_silent_seconds`，預設 900）都沒改 `devlog.md`，
下一個工具會被 PreToolUse hook 擋住，要求先追加一段 `### 段落`（一行也可以）。
寫了任何內容計時就歸零。被擋時用 Write／Edit 改 `.devlog/devlog.md`，不要用 Bash
繞過。沒呼叫工具就不會響。門檻可直接改 `.devlog/.segment-state` 的
`max_silent_seconds`。

收尾時 Stop hook 仍會要求最後一個 Round 上看得到 `### Summary` 與 `### Handoff`。
```

- [ ] **Step 5: Point `checkpoint-mode.md` at the valve**

In `docs/design/checkpoint-mode.md`, replace:

```markdown
**Mechanism: none — pure authoring convention.** The existing Stop-hook
content-hash check already only cares whether `devlog.md` changed since
the round started; it doesn't care how many edits happened or when. So
writing progressively during a round already satisfies enforcement today.
What's missing is purely the documented convention for *how* to do it.
```

with:

```markdown
**Mechanism: authoring convention plus a silence valve.** When to write a
segment is still Claude's judgment. The Stop-hook content-hash check only
cares that `devlog.md` changed by end of turn. Mid-round, if the file's
hash is unchanged for `max_silent_seconds` (default 900), `segment-watch.sh`
blocks the next tool until something is appended — see
[`segment-watch.md`](segment-watch.md).
```

- [ ] **Step 6: Update README feature blurb and tree**

In `README.md`, replace the 段落 bullet:

```markdown
- **段落記錄 + Checkpoint Mode（進階功能）**：單輪內有多個階段性結果時，邊做邊寫成 `### 段落` 子區塊而不是憋到最後；累積輪數夠多時，`Stop` hook 會提醒補上一段跨輪的 `## Checkpoint` 摘要（門檻預設 20 輪、可調），翻閱 `devlog.md` 不用逐輪爬完才知道進度。細節見 [`docs/design/checkpoint-mode.md`](docs/design/checkpoint-mode.md) 和 SKILL.md。
```

with:

```markdown
- **段落記錄 + Checkpoint Mode（進階功能）**：單輪內有多個階段性結果時，邊做邊寫成 `### 段落` 子區塊而不是憋到最後；同一輪若連續約 15 分鐘沒改 `devlog.md`，`PreToolUse` hook 會擋住下一個工具要求先補一段（門檻可調）。累積輪數夠多時，`Stop` hook 會提醒補上一段跨輪的 `## Checkpoint` 摘要（門檻預設 20 輪、可調）。細節見 [`docs/design/checkpoint-mode.md`](docs/design/checkpoint-mode.md)、[`docs/design/segment-watch.md`](docs/design/segment-watch.md) 和 SKILL.md。
```

In the directory tree, add `segment-watch.md` under `docs/design/`, change the `hooks.json` comment to mention PreToolUse, add `segment-watch.sh` / `test-segment-watch.sh`, and mention `.segment-state` on `start.md`:

```
├── docs/design/
│   ├── span-mode.md           # Span Mode 設計文件
│   ├── checkpoint-mode.md     # Checkpoint Mode 設計文件
│   ├── segment-watch.md       # 單輪沉默 15 分鐘保底
│   └── summary-handoff.md     # 每輪 Summary（人）+ Handoff（AI）設計文件
...
│   ├── hooks.json                       # SessionStart / UserPromptSubmit / PreToolUse / Stop
│   └── scripts/
│       ├── session-start-devlog.sh      # 自動接續（含 Span Mode 恢復提醒）
│       ├── round-start.sh               # 記錄每輪開始時的雜湊，遞增 Span/Checkpoint 計數，重設 Segment Watch 計時
│       ├── segment-watch.sh             # 同一輪太久沒寫 devlog 就擋住下一個工具
│       ├── enforce-devlog.sh            # 強制每輪結束前要寫 devlog（含 Span Mode、Checkpoint Mode 檢查）
│       ├── test-enforce-devlog.sh       # enforce + round-start 自我檢查
│       ├── test-segment-watch.sh        # segment-watch + round-start 計時自我檢查
│       └── test-session-start-devlog.sh # session-start-devlog.sh 的自我檢查
...
    ├── start.md            # 開啟強制記錄（建立 .enabled、.checkpoint-state、.segment-state）
```

- [ ] **Step 7: Re-run self-checks**

Run:

```
bash hooks/scripts/test-segment-watch.sh
bash hooks/scripts/test-enforce-devlog.sh
bash hooks/scripts/test-session-start-devlog.sh
```

Expected: all three print `All checks passed.`

- [ ] **Step 8: Commit**

```bash
git add hooks/hooks.json commands/start.md commands/pause.md skills/devlog-tracker/SKILL.md docs/design/checkpoint-mode.md README.md
git commit -m "$(cat <<'EOF'
Wire Segment Watch into start, hooks, and authoring docs.

EOF
)"
```

---

## Self-review

**Spec coverage**
- `.segment-state` fields, start-if-missing, preserve max → Task 2 start.md + Task 1 persist/round-start
- pause leaves the file → Task 2 pause.md
- `round-start.sh` reset → Task 1 Step 4 + Scenario 13
- `segment-watch.sh` hash / allowlist / threshold / fail-open / no jq → Task 1 Scenarios 1–12, 14
- span still enforces → Scenario 11
- exact stderr → Scenario 3
- hooks.json / SKILL / checkpoint-mode / README → Task 2
- `enforce-devlog.sh` untouched → Global Constraints + Task 2 tests still run the old script

**Placeholders:** none.

**Name consistency:** `last_change_epoch`, `last_seen_cksum`, `max_silent_seconds`, `segment-watch.sh`, `.segment-state` used throughout.
