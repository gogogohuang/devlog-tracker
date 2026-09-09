# Skill frontmatter and docs-drift Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the skill YAML path and over-broad triggers, and catch two docs lines that 0.4.0 `/continue` left stale.

**Architecture:** Copy-only. No hooks, no scripts, no version bump. Grep checklists replace hook self-checks (same as `keep-plan.md` command-file tasks).

**Tech Stack:** Markdown skill, design docs.

## Global Constraints

- Do not edit `hooks/`, `commands/`, or plugin JSON.
- Do not bump version. Batch release is **0.5.0** after all optimization plans (`docs/design/version-0.5.0-plan.md`).
- Command copy stays Traditional Chinese; these files are mixed already — keep each file's current language.
- This repo gitignores `docs/superpowers/`. This plan lives under `docs/design/`.
- Do not rewrite SKILL.md body structure. Only YAML `description` plus the one "最近 8 輪" sentence if it still says 8 after this plan (leave inject behavior to `session-start-excerpt-plan.md` — **do not** change the 8-round behavior here).
- Do not add "start" or "keep" as bare trigger words.

## File Structure

| File | Responsibility |
|---|---|
| `skills/devlog-tracker/SKILL.md` | YAML `description` only in Task 1 |
| `docs/design/recording-moments.md` | Test-table line about SessionStart printing |
| `docs/design/keep.md` | Boundary note: continue reads `devlog.md` only |

---

### Task 1: Skill YAML description

**Files:**
- Modify: `skills/devlog-tracker/SKILL.md` lines 1–4
- Test: grep checklist in Step 2

**Interfaces:**
- Consumes: current frontmatter
- Produces: a `description` that names `.devlog/devlog.md`, `/devlog-tracker:continue`, and does not use bare `start` / `keep` as trigger words

- [ ] **Step 1: Replace the YAML `description` value**

In `skills/devlog-tracker/SKILL.md`, replace the entire `description:` line with this single line (YAML still one scalar):

```yaml
description: 在專案的 .devlog/devlog.md 維護逐輪對話紀錄。使用者下 /devlog-tracker:start 後 Stop hook 強制每輪寫入；SessionStart 在 startup / resume / compact / fork 注入進度，/clear 不注入；要接續用 /devlog-tracker:continue。當使用者提到「devlog-tracker」「.devlog/devlog.md」「/devlog-tracker:continue」或明確要寫／接續這份紀錄時使用。
```

Keep `name: devlog-tracker` unchanged.

- [ ] **Step 2: Grep checklist**

Run from repo root:

```bash
python3 - <<'PY'
from pathlib import Path
text = Path("skills/devlog-tracker/SKILL.md").read_text()
fm = text.split("---", 2)[1]
assert ".devlog/devlog.md" in fm, "frontmatter must name .devlog/devlog.md"
assert "專案根目錄維護一份 devlog.md" not in fm, "old root-path wording must go"
assert "/devlog-tracker:continue" in fm
assert "當使用者提到「devlog」「start」" not in fm, "bare start/devlog trigger list must go"
assert "「keep」" not in fm, "bare keep trigger must go"
print("PASS: skill frontmatter")
PY
```

Expected: `PASS: skill frontmatter`

- [ ] **Step 3: Commit**

```bash
git add skills/devlog-tracker/SKILL.md
git commit -m "$(cat <<'EOF'
docs: point the skill at .devlog/devlog.md and narrow its triggers

EOF
)"
```

---

### Task 2: recording-moments SessionStart print line

**Files:**
- Modify: `docs/design/recording-moments.md` around the testing bullet `SessionStart with marker → stamp then still print last rounds.`

**Interfaces:**
- Consumes: 0.4.0 continue spec (`source=clear` silent)
- Produces: test-table text that matches `session-start-devlog.sh`

- [ ] **Step 1: Replace the stale bullet**

Find:

```markdown
- SessionStart with marker → stamp then still print last rounds.
```

Replace with:

```markdown
- SessionStart with marker → stamp; `startup` / `resume` / `fork` (and
  `compact`, which does not heal) still print the log excerpt; `clear`
  stamps on disk then prints nothing.
```

- [ ] **Step 2: Grep checklist**

```bash
grep -n "then still print last rounds" docs/design/recording-moments.md && echo FAIL || echo PASS
grep -n "clear" docs/design/recording-moments.md | head
```

Expected: first command prints `PASS` (no match). The heal section at line ~241 already describes silent clear; leave it.

- [ ] **Step 3: Commit**

```bash
git add docs/design/recording-moments.md
git commit -m "$(cat <<'EOF'
docs: SessionStart heal on /clear stays silent

EOF
)"
```

---

### Task 3: keep.md continue boundary

**Files:**
- Modify: `docs/design/keep.md` section "Boundary with compact and session start"

**Interfaces:**
- Consumes: `commands/continue.md` rule "不要讀 keep 檔，除非 Handoff 下一步指向"
- Produces: one sentence so keep spec matches continue

- [ ] **Step 1: Insert after "SessionStart still reads only `devlog.md`."**

The paragraph today:

```markdown
Neither command touches the other's target files. SessionStart still
reads only `devlog.md`. Kept files live under `.devlog/`, so they follow
the same gitignore (or not) as the working log; this plugin does not
add a separate tracking path.
```

Replace with:

```markdown
Neither command touches the other's target files. SessionStart still
reads only `devlog.md`. `/devlog-tracker:continue` also reads only
`devlog.md` unless that last Handoff's 下一步 names a keep file.
Kept files live under `.devlog/`, so they follow the same gitignore
(or not) as the working log; this plugin does not add a separate
tracking path.
```

- [ ] **Step 2: Grep checklist**

```bash
grep -F "/devlog-tracker:continue" docs/design/keep.md
```

Expected: at least one line containing that string.

- [ ] **Step 3: Commit**

```bash
git add docs/design/keep.md
git commit -m "$(cat <<'EOF'
docs: continue does not read keep files by default

EOF
)"
```
