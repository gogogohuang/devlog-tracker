# Keep resume Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/devlog-tracker:resume <name>` reads `.devlog/devlog.<name>.md` and continues that episode. SessionStart still does not inject keep files.

**Architecture:** Slash command only (like continue). Optional `resume-devlog.sh --name` only lists/validates the file exists and prints the last Round Status + last Handoff; Claude does the work. No new hooks.

**Tech Stack:** bash validator + command markdown.

## Global Constraints

- Do not inject keep files on SessionStart.
- Name normalization matches keep: strip `devlog.` prefix and `.md` suffix; reject `archive`, `..`, slashes, empty.
- Missing file → tell the user, list other `devlog.*.md` except `devlog.md` / `devlog.archive.md` (via script stdout `CANDIDATES=`).
- Do not bump version. Batch release is **0.5.0** after all optimization plans (`docs/design/version-0.5.0-plan.md`).
- This repo gitignores `docs/superpowers/`. This plan lives under `docs/design/`.

## File Structure

| File | Responsibility |
|---|---|
| `hooks/scripts/resume-devlog.sh` | `--name` validate + print excerpt path |
| `hooks/scripts/test-resume-devlog.sh` | self-check |
| `commands/resume.md` | authoring |
| `skills/devlog-tracker/SKILL.md` | pointer next to keep |
| `docs/design/keep.md` | non-goal "reading keep on SessionStart" stays; add resume command |

---

### Task 1: Validator script

**Interfaces:** `resume-devlog.sh --name foo` exit 0 prints `PATH=.devlog/devlog.foo.md` then the file contents to stdout (Claude needs the text). Exit 1 `MISSING` plus `CANDIDATES=a,b`.

- [ ] **Step 1: Tests** — missing name; existing keep file prints PATH and a Round heading; `archive` rejected; `../x` rejected.

- [ ] **Step 2: Implement** using the same name normalization as `keep-move.sh` if that script exists; otherwise copy keep.md rules.

- [ ] **Step 3: Commit** `feat: validate keep-file resume paths`

---

### Task 2: Command + docs

`commands/resume.md`: run the script with the user-supplied name (or ask which candidate). Then act like continue on **that file's** last historical Round (IN_PROGRESS → 下一步). Write the new work into **`devlog.md`**, not back into the keep file. Do not auto-run.

SKILL: one short section. README command table. keep.md Files table add `commands/resume.md`. Non-goals: still no SessionStart inject.

- [ ] **Commit** `feat: add /devlog-tracker:resume`

