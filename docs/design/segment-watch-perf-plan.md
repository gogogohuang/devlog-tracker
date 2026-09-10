# Segment Watch perf Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On PreToolUse, skip full-file `cksum` when `devlog.md` mtime+size match the last persisted identity; silence semantics unchanged.

**Architecture:** Extend `.segment-state` with `last_seen_mtime` and `last_seen_size` (strings/ints). `segment-watch.sh` short-circuits to the stored cksum when identity matches; otherwise cksum and persist identity + cksum + epoch as today. `round-start.sh` reset path must clear or refresh identity fields consistently.

**Tech Stack:** bash, `cksum`, `stat` (portable via `stat -f` / `stat -c` detection already common in shell; prefer one portable form).

## Global Constraints

- Spec: [`polish-0.9.0-design.md`](polish-0.9.0-design.md) §3 and [`segment-watch.md`](segment-watch.md).
- Do not change default `max_silent_seconds`, allowlist, fail-open rules, or stderr sentence.
- Do not lock `.segment-state`.
- Missing/malformed identity fields → fall through to full `cksum` (fail-open toward correctness, not skip).
- Do not bump version.
- This plan lives under `docs/design/`.

## File Structure

| File | Responsibility |
|---|---|
| `hooks/scripts/segment-watch.sh` | mtime/size gate before cksum |
| `hooks/scripts/test-segment-watch.sh` | prove skip path + silence still blocks |
| `hooks/scripts/round-start.sh` | when resetting segment clock, also set/clear identity fields |
| `docs/design/segment-watch.md` | document identity short-circuit |

**Portable identity helper** (inline in `segment-watch.sh` or tiny sourced function):

```bash
devlog_file_identity() {
  # prints: "<mtime_epoch> <size_bytes>" or empty on failure
  local f="$1" mt sz
  if mt="$(stat -f '%m' "$f" 2>/dev/null)" && sz="$(stat -f '%z' "$f" 2>/dev/null)"; then
    printf '%s %s\n' "$mt" "$sz"
    return 0
  fi
  if mt="$(stat -c '%Y' "$f" 2>/dev/null)" && sz="$(stat -c '%s' "$f" 2>/dev/null)"; then
    printf '%s %s\n' "$mt" "$sz"
    return 0
  fi
  return 1
}
```

---

### Task 1: Tests for identity short-circuit

**Files:**
- Modify: `hooks/scripts/test-segment-watch.sh`

- [ ] **Step 1: Add scenarios**

1. **Unchanged file skips re-hash but still blocks when expired:** Seed `.segment-state` with matching `last_seen_cksum`, `last_seen_mtime`, `last_seen_size`, old epoch, and `session_id`. Invoke PreToolUse with a non-allowlisted tool. Expect exit 2. (Optionally spy: replace `cksum` in PATH with a script that increments a counter and execs real cksum — assert counter stays 0 when identity matches.)

2. **Identity mismatch forces cksum and clears silence:** Same setup but append a byte to `devlog.md` (mtime/size change) **or** set wrong stored mtime. Expect exit 0 and updated `last_seen_cksum` / identity fields.

3. **Missing identity fields:** State has cksum+epoch but no mtime/size keys → still works via cksum (exit 0 or 2 per elapsed); must not crash.

For the cksum-counter spy (scenario 1), use:

```bash
SPY="$TMP/spybin"
mkdir -p "$SPY"
REAL_CKSUM="$(command -v cksum)"
cat > "$SPY/cksum" <<EOF
#!/usr/bin/env bash
echo 1 >> "$TMP/cksum_count"
exec "$REAL_CKSUM" "\$@"
EOF
chmod +x "$SPY/cksum"
# PATH="$SPY:$PATH" bash segment-watch.sh …
# [ ! -f "$TMP/cksum_count" ] && PASS skip
```

- [ ] **Step 2: Run — FAIL** until implementation lands.

```bash
bash hooks/scripts/test-segment-watch.sh
```

---

### Task 2: Implement short-circuit

**Files:**
- Modify: `hooks/scripts/segment-watch.sh`
- Modify: `hooks/scripts/round-start.sh` (segment reset block only)

- [ ] **Step 1: Update `persist_seen`**

When persisting after a real hash:

```bash
persist_seen() {
  local epoch="$1" sum="$2" mt="$3" sz="$4"
  json_int_set "$SEGMENT_FILE" last_change_epoch "$epoch"
  json_str_set "$SEGMENT_FILE" last_seen_cksum "$sum"
  json_str_set "$SEGMENT_FILE" last_seen_mtime "$mt"
  json_str_set "$SEGMENT_FILE" last_seen_size "$sz"
}
```

(Use `json_int_set` for size/mtime if values are purely numeric — either is fine if tests assert via grep.)

- [ ] **Step 2: Replace unconditional cksum block**

```bash
if [ -f "$DEVLOG_FILE" ]; then
  ID="$(devlog_file_identity "$DEVLOG_FILE" || true)"
  ID_MT="${ID%% *}"
  ID_SZ="${ID#* }"
  STORED_MT="$(json_str_get "$SEGMENT_FILE" last_seen_mtime 2>/dev/null || true)"
  STORED_SZ="$(json_str_get "$SEGMENT_FILE" last_seen_size 2>/dev/null || true)"
  if [ -n "$ID_MT" ] && [ -n "$ID_SZ" ] && [ "$ID_MT" = "$STORED_MT" ] && [ "$ID_SZ" = "$STORED_SZ" ] && [ -n "$SEG_SUM" ]; then
    CURRENT="$SEG_SUM"
  else
    CURRENT="$(cksum < "$DEVLOG_FILE" 2>/dev/null | tr -d '\n' || echo '')"
  fi
else
  CURRENT="MISSING"
  ID_MT=""; ID_SZ=""
fi
```

When `CURRENT != SEG_SUM`, call `persist_seen "$NOW" "$CURRENT" "$ID_MT" "$ID_SZ"` (recompute identity after hash if needed).

When identity matched and CURRENT==SEG_SUM, do **not** rewrite state (same as today when hash unchanged).

- [ ] **Step 3: round-start reset**

Wherever round-start resets `last_change_epoch` / `last_seen_cksum` for a new round, also set `last_seen_mtime` / `last_seen_size` from the file after the skeleton write (or clear them so the next PreToolUse re-cksums once). Prefer set-from-file so the first tool call can skip.

- [ ] **Step 4: Tests pass + `run-tests.sh`**

```bash
bash hooks/scripts/test-segment-watch.sh
bash hooks/scripts/run-tests.sh
```

- [ ] **Step 5: Doc + commit**

Update `docs/design/segment-watch.md` Known behavior: PreToolUse may skip `cksum` when mtime+size match `last_seen_*`.

```bash
git add hooks/scripts/segment-watch.sh hooks/scripts/round-start.sh \
  hooks/scripts/test-segment-watch.sh docs/design/segment-watch.md
git commit -m "$(cat <<'EOF'
perf: skip segment-watch cksum when devlog mtime+size unchanged

EOF
)"
```
