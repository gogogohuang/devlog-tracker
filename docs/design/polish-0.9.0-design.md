# Polish batch → 0.9.0 (design)

Design for the 2026-09-10 review follow-ups on `main` @ ~0.8.0.
Plans live under `docs/design/` (this repo gitignores `docs/superpowers/`).

## Decisions (locked)

| Decision | Choice |
|---|---|
| Slice | Theme-based: one plan → one PR |
| Version | No bump inside feature plans; after all feature PRs merge, run `version-0.9.0-plan.md` once (`0.8.0` → `0.9.0`) in `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `README.md` |
| Cursor depth | Fix gaps + Claude `/devlog-tracker:checkpoint`. No Cursor-only slash packaging. No invented StopFailure or cloud `sessionStart` workaround |
| Don't do | Still forbidden: re-inject on `/clear`, empty startup, scoring Summary prose, agentflow SDD, auto compact, transcript parse, instant Esc stamp (see `optimization-plans.md`) |

## Execution order

| # | Plan | Goal |
|---|---|---|
| 1 | [`docs-truth-up-plan.md`](docs-truth-up-plan.md) | Align specs/comments with 0.8.0 reality; mark finished `*-plan.md` historical; refresh index |
| 2 | [`cursor-dx-plan.md`](cursor-dx-plan.md) | No-jq `session_id`; `DEVLOG_TRACKER_ROOT` / `CLAUDE_PLUGIN_ROOT` fallback; README Cursor manual commands |
| 3 | [`segment-watch-unblock-plan.md`](segment-watch-unblock-plan.md) | Skip valve on Claude Code `agent_id`; allow Read/Grep of `devlog.md` when expired; safe-append stderr/SKILL |
| 4 | [`segment-watch-perf-plan.md`](segment-watch-perf-plan.md) | PreToolUse: cheap mtime/size gate before full-file `cksum`; same silence semantics |
| 5 | [`fence-unify-plan.md`](fence-unify-plan.md) | Shared fence regex (indented fences allowed) for keep/compact/`devlog-md` and enforce/session-start |
| 6 | [`prompt-redact-expand-plan.md`](prompt-redact-expand-plan.md) | Broader common token patterns; stronger `.gitignore` nudge on start |
| 7 | [`ci-shellcheck-and-edge-tests-plan.md`](ci-shellcheck-and-edge-tests-plan.md) | shellcheck in CI; edge tests (Cursor no-jq, redact negatives) |
| 8 | [`checkpoint-command-plan.md`](checkpoint-command-plan.md) | `/devlog-tracker:checkpoint` mirrors `/segment-watch` for `max_silent_rounds` |
| 9 | [`version-0.9.0-plan.md`](version-0.9.0-plan.md) | Version bump only |

Each feature plan is self-contained (TDD where behavior changes, exact files, exact commands). Prefer subagent-driven-development or executing-plans. Do not bump version inside plans 1–8.

**Priority note:** Plan 3 (unblock) may be implemented before 1–2 if a live workflow is hitting the wipe/death-spiral; still one PR per plan.

## Per-plan scope

### 1. Docs truth-up

**In:** Fix stale claims in `recording-moments.md` (last-8 / no compact), `span-mode.md` (no slash), `session-start-devlog.sh` comments, `keep.md` Testing, SKILL fork list if incomplete. Mark `optimization-plans.md` and completed `*-plan.md` as historical (header note or checkbox closeout) without deleting history.

**Out:** Hook/script behavior changes.

### 2. Cursor DX

**In:** `cursor/hooks/on-submit-prompt.sh` always forward `session_id` when present (with or without jq). Commands and adapters resolve plugin root via `CLAUDE_PLUGIN_ROOT` then `DEVLOG_TRACKER_ROOT`. README documents how to run the commands that already exist at this point (start/pause/status/span/segment-watch/compact/keep/clean/continue) from Cursor. Plan 8 adds the checkpoint line when that command ships.

**Out:** Cursor slash command packaging; StopFailure adapter; cloud sessionStart invention; mapping Cursor `sessionStart` to clear/compact/fork (API cannot).

### 3. Segment Watch unblock

**In:** Non-empty PreToolUse `agent_id` → skip valve (Claude Code dynamic workflow / subagents share parent `session_id`). Expired allowlist adds `Read`/`Grep` on `.devlog/devlog.md`. Stderr + SKILL: Read then Edit/StrReplace append; forbid full-file Write overwrite.

**Out:** Auto-pause; Cursor-invented fields; Bash allowlist; removing Write from allowlist (messaging only).

### 4. Segment Watch perf

**In:** Persist and compare cheap file identity (e.g. `mtime` + size) so unchanged files skip `cksum`; on change or missing prior identity, `cksum` as today. Tests prove silence block still fires and allowlist still works.

**Out:** Changing default threshold; locking `.segment-state`; requiring `### 段落` heading text.

### 5. Fence unify

**In:** One shared helper (extend `devlog-md.sh` or small sourced helper) so fence open/close matching allows leading whitespace everywhere that strips or splits rounds. Tests for indented fence hiding a fake `## Round`.

**Out:** Full markdown AST; changing Summary/Handoff substance rules.

### 6. Prompt redact expand

**In:** Add patterns for common leaks beyond current set (at least OpenAI-style `sk-` that is not only `sk-ant-`, `Bearer` tokens, JWT-shaped strings) without claiming general secret scanning. Start/command copy nudges `.gitignore` for `.devlog/` more firmly when missing. Tests for new positives and a truncate-vs-redact note left honest in docs.

**Out:** Entropy scanners; blocking commit; rewriting entire User Input history.

### 7. CI shellcheck + edge tests

**In:** Add shellcheck step to `.github/workflows/hooks.yml` (scripts under `hooks/scripts/` and `cursor/hooks/`). Extend self-checks for Cursor no-jq `session_id`, selected redact negatives, and any new helpers from prior code plans if not already covered there.

**Out:** Flaky multi-process lock stress; macOS CI matrix (optional later).

### 8. Checkpoint command

**In:** Mirror `segment-watch-set.sh` / `commands/segment-watch.md`: user-facing `/devlog-tracker:checkpoint <N>` sets `max_silent_rounds` on `.checkpoint-state`; `NOT_STARTED` if no `.enabled`; do not reset counters when only changing max. Update SKILL, README, status output if useful.

**Out:** Changing Stop checkpoint enforcement formula; auto-writing Checkpoint bodies.

### 9. Version 0.9.0

**In:** Bump the three version surfaces only after 1–8 are on `main`.

**Out:** Feature work.

## Success criteria

- Specs describe current 0.8.x+ behavior; agents are not misled into re-implementing compact/span/excerpt.
- Cursor without jq still isolates Segment Watch by `session_id` when the payload includes it.
- Claude Code subagent / dynamic-workflow PreToolUse with `agent_id` is not blocked by Segment Watch; main thread can Read `devlog.md` when expired and is told to append, not overwrite.
- PreToolUse on a large unchanged `devlog.md` does not re-hash every tool call (measurable via test or documented identity short-circuit).
- Indented fences cannot diverge keep/compact vs enforce.
- Redact covers the expanded pattern set with tests; docs still say “not a general scanner.”
- CI runs shellcheck + existing `run-tests.sh`.
- `/devlog-tracker:checkpoint` adjusts `max_silent_rounds` like segment-watch adjusts seconds.
- Plugin version reads `0.9.0` only after the final plan.

## Relationship to older index

[`optimization-plans.md`](optimization-plans.md) remains the 0.4→0.5 batch index (historical). This file indexes the 0.8→0.9 polish batch. Do not reopen the don't-do list.
