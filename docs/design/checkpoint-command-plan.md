# Checkpoint command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `/devlog-tracker:checkpoint <N>` that sets `max_silent_rounds` on `.checkpoint-state`, mirroring `/devlog-tracker:segment-watch` / `segment-watch-set.sh`.

**Architecture:** New `checkpoint-set.sh` + `test-checkpoint-set.sh` + `commands/checkpoint.md`. Stop enforcement formula unchanged. Update SKILL, README, `checkpoint-mode.md`, and optionally `status-devlog.sh` output.

**Tech Stack:** bash, `json-field.sh`, Claude Code command markdown.

## Global Constraints

- Spec: [`polish-0.9.0-design.md`](polish-0.9.0-design.md) §7; behavior mirror [`commands/segment-watch.md`](../commands/segment-watch.md) + `segment-watch-set.sh`.
- No `.enabled` → stdout `NOT_STARTED`, exit 0 (do not create files).
- Argument: positive integer rounds only (same validation style as seconds in segment-watch-set).
- Changing max must **not** reset `rounds_since_checkpoint` or `checkpoint_marker_count`.
- If `.checkpoint-state` missing but `.enabled` exists: create file with `rounds_since_checkpoint: 0`, `checkpoint_marker_count: 0`, requested max (same spirit as segment-watch-set creating segment-state).
- If file exists but patch misses key: rebuild preserving counters (copy segment-watch-set rebuild pattern).
- Do not bump version.
- PLUGIN_ROOT pattern from plan 2: `${CLAUDE_PLUGIN_ROOT:-${DEVLOG_TRACKER_ROOT:-}}`.
- This plan lives under `docs/design/`.

## File Structure

| File | Responsibility |
|---|---|
| `hooks/scripts/checkpoint-set.sh` | set `max_silent_rounds` |
| `hooks/scripts/test-checkpoint-set.sh` | self-check |
| `hooks/scripts/run-tests.sh` | register new test |
| `commands/checkpoint.md` | slash UX |
| `skills/devlog-tracker/SKILL.md` | document command |
| `README.md` | command table + Cursor one-liner |
| `docs/design/checkpoint-mode.md` | replace “no dedicated slash” |
| `hooks/scripts/status-devlog.sh` | optional: print current max |

---

### Task 1: `checkpoint-set.sh` TDD

**Files:**
- Create: `hooks/scripts/test-checkpoint-set.sh`
- Create: `hooks/scripts/checkpoint-set.sh`
- Modify: `hooks/scripts/run-tests.sh`

- [ ] **Step 1: Write failing self-check** (model on `test-segment-watch-set.sh`):

```bash
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# NOT_STARTED
OUT="$(CLAUDE_PROJECT_DIR="$TMP" bash "$SCRIPT_DIR/checkpoint-set.sh" 25)"
[ "$OUT" = "NOT_STARTED" ] && echo "PASS: not started" || { echo "FAIL: $OUT"; FAIL=1; }

mkdir -p "$TMP/.devlog"
touch "$TMP/.devlog/.enabled"
printf '%s\n' '{"rounds_since_checkpoint": 7, "max_silent_rounds": 20, "checkpoint_marker_count": 2}' \
  > "$TMP/.devlog/.checkpoint-state"

OUT="$(CLAUDE_PROJECT_DIR="$TMP" bash "$SCRIPT_DIR/checkpoint-set.sh" 30)"
case "$OUT" in *CHECKPOINT_MAX_SILENT_ROUNDS=30*) echo "PASS: set 30" ;; *) echo "FAIL: $OUT"; FAIL=1 ;; esac
grep -q '"rounds_since_checkpoint": 7' "$TMP/.devlog/.checkpoint-state" \
  && echo "PASS: rounds preserved" || { echo "FAIL: rounds reset"; FAIL=1; }
grep -q '"checkpoint_marker_count": 2' "$TMP/.devlog/.checkpoint-state" \
  && echo "PASS: markers preserved" || { echo "FAIL: markers reset"; FAIL=1; }
grep -q '"max_silent_rounds": 30' "$TMP/.devlog/.checkpoint-state" \
  && echo "PASS: max written" || { echo "FAIL: max"; FAIL=1; }

CLAUDE_PROJECT_DIR="$TMP" bash "$SCRIPT_DIR/checkpoint-set.sh" 0 >/dev/null 2>&1
[ $? -eq 1 ] && echo "PASS: reject 0" || { echo "FAIL: accepted 0"; FAIL=1; }

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
```

- [ ] **Step 2: Run — FAIL** (script missing).

- [ ] **Step 3: Implement `checkpoint-set.sh`**

Copy structure from `segment-watch-set.sh`, swapping:

- file: `.checkpoint-state`
- field: `max_silent_rounds`
- stdout: `CHECKPOINT_MAX_SILENT_ROUNDS=<n>`
- stderr validation: `max_silent_rounds must be a positive integer number of rounds, got: …`
- default create JSON: `{"rounds_since_checkpoint": 0, "max_silent_rounds": N, "checkpoint_marker_count": 0}`
- rebuild preserve: `rounds_since_checkpoint`, `checkpoint_marker_count`

- [ ] **Step 4: Register in `run-tests.sh`** next to other test invocations.

- [ ] **Step 5: Pass + commit**

```bash
bash hooks/scripts/test-checkpoint-set.sh
bash hooks/scripts/run-tests.sh
git add hooks/scripts/checkpoint-set.sh hooks/scripts/test-checkpoint-set.sh hooks/scripts/run-tests.sh
git commit -m "$(cat <<'EOF'
feat: add checkpoint-set.sh for max_silent_rounds

EOF
)"
```

---

### Task 2: Command + docs + status

**Files:**
- Create: `commands/checkpoint.md`
- Modify: `skills/devlog-tracker/SKILL.md`, `README.md`, `docs/design/checkpoint-mode.md`
- Optional: `hooks/scripts/status-devlog.sh` + its test

- [ ] **Step 1: `commands/checkpoint.md`**

```markdown
---
description: 調整 Checkpoint Mode 的沉默門檻——累積多少輪沒寫 ## Checkpoint 就要求補跨輪摘要。
---

取得使用者要設定的輪數（正整數）；沒帶就先問，不要用預設值硬猜。
跑：

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${DEVLOG_TRACKER_ROOT:-}}"
CLAUDE_PROJECT_DIR="$(pwd)" bash "${PLUGIN_ROOT}/hooks/scripts/checkpoint-set.sh" <rounds>
```

不要自己手改 `.devlog/.checkpoint-state`。

- stdout 是 `NOT_STARTED`：告知還沒 `/devlog-tracker:start`；問要不要現在 start，不要自己跑 start。
- stdout 有 `CHECKPOINT_MAX_SILENT_ROUNDS=<n>`：告知新門檻已生效。
- exit 1：原樣顯示 stderr，請使用者換正整數再試。
```

- [ ] **Step 2: README command table** — add row for `/devlog-tracker:checkpoint`. In Cursor manual section (from plan 2), add:

```bash
bash "$DEVLOG_TRACKER_ROOT/hooks/scripts/checkpoint-set.sh" 20
```

- [ ] **Step 3: SKILL** — short pointer next to segment-watch / checkpoint mode docs.

- [ ] **Step 4: `checkpoint-mode.md`** — replace “no dedicated slash command” on `max_silent_rounds` with pointer to `/devlog-tracker:checkpoint`.

- [ ] **Step 5 (optional but preferred): status** — if `status-devlog.sh` already prints segment max, also print checkpoint max; extend `test-status-span.sh`.

- [ ] **Step 6: Commit**

```bash
git add commands/checkpoint.md skills/devlog-tracker/SKILL.md README.md \
  docs/design/checkpoint-mode.md hooks/scripts/status-devlog.sh hooks/scripts/test-status-span.sh
git commit -m "$(cat <<'EOF'
feat: add /devlog-tracker:checkpoint to set max_silent_rounds

EOF
)"
```
