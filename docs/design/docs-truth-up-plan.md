# Docs truth-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make living specs and comments match 0.8.x behavior so agents stop re-implementing compact / span / excerpt, and mark the 0.4→0.5 plan batch historical.

**Architecture:** Documentation-only edits. Specs under `docs/design/` that describe current product behavior are authoritative; finished `*-plan.md` files from `optimization-plans.md` get a HISTORICAL banner and stay as archives.

**Tech Stack:** Markdown.

## Global Constraints

- Spec: [`polish-0.9.0-design.md`](polish-0.9.0-design.md) §1.
- Do **not** change hook/script behavior, tests, or version numbers.
- Do **not** delete historical plan bodies or rewrite git history of checkboxes into fake `[x]` mass-edits unless a one-line HISTORICAL banner is clearer — prefer banner over rewriting hundreds of `- [ ]`.
- This repo gitignores `docs/superpowers/`. This plan lives under `docs/design/`.
- Do not bump version (batch ends at `version-0.9.0-plan.md`).

## File Structure

| File | Responsibility |
|---|---|
| `docs/design/recording-moments.md` | Fix last-8 / no-compact / compact-excerpt wording |
| `docs/design/span-mode.md` | Point Span open/close at `/devlog-tracker:span` |
| `docs/design/checkpoint-mode.md` | Note threshold now also via slash (plan 7); for this plan only remove “no dedicated slash” lie if span already has one — leave checkpoint slash wording soft until plan 7, or say “segment-watch has a command; checkpoint still file-edit until plan 7” |
| `docs/design/keep.md` | Testing section reflects `keep-move.sh` |
| `hooks/scripts/session-start-devlog.sh` | Comment: excerpt is Checkpoint + last 2 rounds, not 8 |
| `skills/devlog-tracker/SKILL.md` | SessionStart heal list includes `fork` where body says only startup/resume/clear |
| `docs/design/optimization-plans.md` | HISTORICAL banner + pointer to polish-0.9.0-design |
| Listed `*-plan.md` from optimization-plans index | One-line HISTORICAL banner each |

---

### Task 1: Fix living specs and comments

**Files:**
- Modify: `docs/design/recording-moments.md`
- Modify: `docs/design/span-mode.md`
- Modify: `docs/design/keep.md`
- Modify: `hooks/scripts/session-start-devlog.sh` (comment only)
- Modify: `skills/devlog-tracker/SKILL.md`

- [ ] **Step 1: `recording-moments.md` SessionStart**

Replace the paragraph that starts `Before injecting the last 8 rounds:` with:

```markdown
Before injecting the SessionStart excerpt (last Checkpoint if any, plus
the last two Rounds' Summary / Handoff / Status — see
`session-start-devlog.sh`): if `.round-open` exists **and**
stdin `source` is `startup` / `resume` / `clear` / `fork`, shared
interrupt close `dangling:session_start`. Skip heal when `source` is
`compact` or missing/unreadable (mid-turn auto-compact must not cancel
Stop). Then, for every source **except `clear`**, the existing span
warning + excerpt. `source=clear` exits 0 after heal with empty
stdout — `/clear` must leave context empty; resume is
`/devlog-tracker:continue` (see `docs/design/continue.md`). Crash
recovery for Status still happens on disk; User Input was already on
disk at submit.
```

In Known limitations, replace `Compact still injects the last-8 excerpt only.` with:

```markdown
Compact still injects the SessionStart excerpt (last Checkpoint + last
two Rounds' close) only — it does not heal.
```

Replace the Testing bullet:

```markdown
`compact.md` instruction coverage is documentation: retain
`INTERRUPTED`. No compact script exists today; do not add one.
```

with:

```markdown
`compact-devlog.sh` + `commands/compact.md` move older DONE rounds to
`devlog.archive.md`. Retain `INTERRUPTED` rounds in the main file per
compact rules. Do not invent a second compact mechanism.
```

- [ ] **Step 2: `span-mode.md`**

Replace:

```markdown
A JSON file, written and maintained directly by Claude (via Write/Edit —
there is no dedicated slash command for this), never by a hook script:
```

with:

```markdown
A JSON file owned by `/devlog-tracker:span` via `span-open.sh` /
`span-close.sh` (see `commands/span.md`). Hooks never create or delete
this file themselves. Do not hand-edit `.span-open` when the slash
command is available:
```

- [ ] **Step 3: `keep.md` Testing**

Replace the Testing section body with:

```markdown
## Testing

`hooks/scripts/keep-move.sh` has `hooks/scripts/test-keep-move.sh`
(assert-and-exit). Topic-split *judgment* still lives in
`commands/keep.md` (LLM steps); the script only moves contiguous
ranges after confirm. The keep turn's own Round still has to satisfy
Stop (`### Summary` / `### Handoff` / Status rules).
```

Also fix the Files table line that claims “No hook or `hooks/hooks.json` changes” if it still implies no scripts — add `hooks/scripts/keep-move.sh` and `hooks/scripts/test-keep-move.sh` to the Files table; remove or soften “No hook or hooks/hooks.json changes” to “No `hooks/hooks.json` changes (user-invoked script only).”

- [ ] **Step 4: `session-start-devlog.sh` comment**

Find the comment containing `最近 8 輪` (or English “8 rounds”) and replace with wording equivalent to:

```bash
# mid-turn auto-compact 改雜湊讓 Stop 靜默放行；compact 仍注入 excerpt
#（最後一個 Checkpoint + 最近兩輪 Summary/Handoff/Status），不 heal。
```

- [ ] **Step 5: SKILL heal list**

In `skills/devlog-tracker/SKILL.md`, every user-facing list of SessionStart heal sources that says only `startup / resume / clear` must become `startup / resume / clear / fork` (YAML description already lists fork for inject — keep inject and heal consistent).

- [ ] **Step 6: Grep gate**

```bash
rg -n 'last 8 rounds|最近 8 輪|No compact script exists|no dedicated slash command for this' docs/design/recording-moments.md docs/design/span-mode.md hooks/scripts/session-start-devlog.sh || true
rg -n 'No new hook scripts, so no new hook self-checks' docs/design/keep.md || true
```

Expected: no matches in those stale phrases (span may still mention limitations elsewhere — only the “no dedicated slash” claim for `.span-open` must be gone).

- [ ] **Step 7: Commit**

```bash
git add docs/design/recording-moments.md docs/design/span-mode.md docs/design/keep.md \
  hooks/scripts/session-start-devlog.sh skills/devlog-tracker/SKILL.md
git commit -m "$(cat <<'EOF'
docs: align specs with 0.8.x compact, span, and excerpt behavior

EOF
)"
```

---

### Task 2: Mark 0.5 batch plans historical

**Files:**
- Modify: `docs/design/optimization-plans.md`
- Modify: each plan linked from its Execution order table (skill-and-docs through version-0.5.0, plus any sibling feature plans that table lists)

- [ ] **Step 1: Banner on `optimization-plans.md`**

Prepend after the title:

```markdown
> **HISTORICAL (0.4.0 → 0.5.0).** Shipped. Do not re-execute.
> Next polish batch: [`polish-0.9.0-design.md`](polish-0.9.0-design.md).
```

Optionally one sentence at the bottom: “Checkbox bodies left as written at planning time; treat the banner as the status of record.”

- [ ] **Step 2: Banner each indexed plan**

For every file in the Execution order table of `optimization-plans.md`, prepend as the first line after the H1 (or immediately under the agentic-workers quote):

```markdown
> **HISTORICAL.** Part of the 0.4→0.5 batch (`optimization-plans.md`). Do not re-execute.
```

- [ ] **Step 3: Commit**

```bash
git add docs/design/optimization-plans.md docs/design/*-plan.md
git commit -m "$(cat <<'EOF'
docs: mark 0.4→0.5 optimization plans historical

EOF
)"
```

Do not mark `polish-0.9.0-design.md` or this plan historical.
