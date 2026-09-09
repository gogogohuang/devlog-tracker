# Status and span commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/devlog-tracker:status` prints switch/span/checkpoint/segment/last Status. `/devlog-tracker:span` writes or deletes `.span-open` so Claude does not have to remember the JSON shape.

**Architecture:** `status-devlog.sh` is read-only stdout. `span-open.sh` / `span-close.sh` mutate `.span-open` only (never `devlog.md`). The span command still tells Claude to write a normal Round before open, and a **new** closing Round after close — scripts do not author rounds.

**Tech Stack:** bash, command markdown.

## Global Constraints

- Status does not create `.devlog/`. Missing dir → `NOT_STARTED`.
- Span open requires `.enabled` and a round number: `.round-open` `round` if present, else last unfenced `## Round N`. If neither exists, exit 1.
- `max_silent_ticks` default `5`. Do not overwrite an existing `.span-open` (exit 1 `ALREADY_OPEN`).
- Close deletes `.span-open` only. Exit 0 `NOT_OPEN` if missing.
- Do not bump version. Batch release is **0.5.0** after all optimization plans (`docs/design/version-0.5.0-plan.md`).
- Command copy Traditional Chinese.
- This repo gitignores `docs/superpowers/`. This plan lives under `docs/design/`.

## File Structure

| File | Responsibility |
|---|---|
| `hooks/scripts/status-devlog.sh` | print status |
| `hooks/scripts/span-open.sh` | write `.span-open` |
| `hooks/scripts/span-close.sh` | delete `.span-open` |
| `hooks/scripts/test-status-span.sh` | self-check |
| `commands/status.md` | run status script, relay |
| `commands/span.md` | open vs close |
| `skills/devlog-tracker/SKILL.md` | pointer: use `/devlog-tracker:span` not hand-written JSON |
| `README.md` | command table |

---

### Task 1: Scripts + tests

**Files:** create the three scripts + `test-status-span.sh`

**Interfaces:**
- `status-devlog.sh` stdout keys (one per line): `ENABLED=yes|no`, `SPAN=closed|round,opened_at,ticks,max`, `CHECKPOINT=rounds/max`, `SEGMENT=max_silent_seconds=N`, `LAST_STATUS=DONE|…|none`
- `span-open.sh` stdout `OPENED=N` or stderr + exit 1

- [ ] **Step 1: Write failing tests** for: no `.devlog` → `NOT_STARTED`; after touch `.enabled` + a DONE Round 1 → `ENABLED=yes` `LAST_STATUS=DONE` `SPAN` closed; `span-open.sh` writes JSON round 1 ticks 0 max 5; second open exit 1; `span-close.sh` removes file.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement scripts.** Prefer `json-field.sh` if present.

`status-devlog.sh` last status: fence-aware last Round, last non-empty line after `### Status`.

- [ ] **Step 4: Tests pass + commit** `feat: add status and span helper scripts`

---

### Task 2: Commands, skill, README

**Files:** `commands/status.md`, `commands/span.md`, SKILL span section, README command table, plugin descriptions (mention `/status` `/span`)

- [ ] **Step 1: `commands/status.md`**

```markdown
---
description: 查看這個專案 devlog 強制記錄是否開著、span / checkpoint / 最後一輪 Status。
---

跑：
```bash
CLAUDE_PROJECT_DIR="$(pwd)" bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/status-devlog.sh"
```
把 stdout 翻譯成給人看的幾行。不要改任何檔。`NOT_STARTED` 就說還沒 `/devlog-tracker:start`。
```

- [ ] **Step 2: `commands/span.md`**

If user wants to close, or `.span-open` exists and they did not ask to open: run `span-close.sh`, then Claude writes a **new** Round summarising the span (SKILL close rules). If opening: Claude writes the current Round as `IN_PROGRESS` first, then `span-open.sh`. Never hand-write `.span-open` JSON.

- [ ] **Step 3: SKILL** — in Span Mode「怎麼開一個 span」, say 用 `/devlog-tracker:span`（或跑 `span-open.sh`），不要手寫 JSON unless the script is unavailable.

- [ ] **Step 4: README** command table rows for status and span. Plugin `description` strings add the two commands.

- [ ] **Step 5: Commit** `feat: add /status and /span commands`

