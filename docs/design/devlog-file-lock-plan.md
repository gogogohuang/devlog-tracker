# Devlog file lock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Serialize writes to `devlog.md` and sibling state files across concurrent sessions using `mkdir` as an exclusive lock.

**Architecture:** `hooks/scripts/devlog-lock.sh` defines `devlog_with_lock cmd...`. Writers `mkdir .devlog/.lock` (atomic). Retry every 0.1s until 2.0s then **fail-open** (run the command anyway) so a crashed holder cannot freeze the user. `trap` removes the lock directory if this process created it.

**Tech Stack:** bash `mkdir`, `date +%s`.

## Global Constraints

- Lock directory is `$DEVLOG_DIR/.lock` (a directory, not a file).
- Fail-open after 2 seconds. Never `exit 2` because of lock contention.
- Do not lock `status-devlog.sh` (read-only).
- Wrap: `round-start.sh` (whole script body after `.enabled` check), `close-open-round.sh`, `compact-devlog.sh` / `keep-move.sh` if they exist, `enforce-devlog.sh` only the branches that `awk` rewrite state files (span reset / checkpoint). Simplest correct approach: wrap the entire `enforce-devlog.sh` body after `.enabled` (reads + possible writes).
- Do not bump version. Batch release is **0.5.0** after all optimization plans (`docs/design/version-0.5.0-plan.md`).
- Update `docs/design/recording-moments.md` concurrent-sessions limitation.
- This repo gitignores `docs/superpowers/`. This plan lives under `docs/design/`.

## File Structure

| File | Responsibility |
|---|---|
| `hooks/scripts/devlog-lock.sh` | `devlog_lock_acquire` / `devlog_lock_release` / `devlog_with_lock` |
| `hooks/scripts/test-devlog-lock.sh` | contention + timeout fail-open |
| writer scripts listed above | source and wrap |
| `docs/design/recording-moments.md` | limitation |

---

### Task 1: Lock helper + tests

```bash
devlog_lock_acquire() {
  local dir="${DEVLOG_DIR:-.}/.lock"
  local start now
  start="$(date +%s 2>/dev/null || echo 0)"
  LOCK_HELD=0
  while true; do
    if mkdir "$dir" 2>/dev/null; then
      LOCK_HELD=1
      return 0
    fi
    now="$(date +%s 2>/dev/null || echo 0)"
    if [ $((now - start)) -ge 2 ]; then
      return 0
    fi
    sleep 0.1 2>/dev/null || true
  done
}
devlog_lock_release() {
  if [ "${LOCK_HELD:-0}" -eq 1 ]; then
    rmdir "${DEVLOG_DIR:-.}/.lock" 2>/dev/null || true
    LOCK_HELD=0
  fi
}
```

Test: acquire twice in one process — second `mkdir` fails; after `release`, second acquire works. Test: hold lock dir from the test, call acquire, measure it returns within ~3s and `LOCK_HELD=0`.

- [ ] Implement, pass, commit `feat: add mkdir-based .devlog/.lock helper`

---

### Task 2: Wrap writers

At the top of each writer, after `DEVLOG_DIR` is set:

```bash
. "$SCRIPT_DIR/devlog-lock.sh"
devlog_lock_acquire
trap 'devlog_lock_release' EXIT
```

`round-start.sh` uses `HOOKS_DIR` not `SCRIPT_DIR` — source from that.

Existing tests must still pass. Do not add a cross-process race test to CI (flaky). The unit test is enough.

- [ ] Commit `feat: serialize hook writes with .devlog/.lock`

Spec: concurrent sessions still *can* interleave after the 2s fail-open; the lock only covers the common overlapping-write window.

