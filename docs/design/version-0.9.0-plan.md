# Batch version 0.9.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After polish plans 1–7 are on `main`, bump the plugin from `0.8.0` to **`0.9.0` once**.

**Architecture:** Three files, same string. No other behavior. Do not run this plan until [`polish-0.9.0-design.md`](polish-0.9.0-design.md) plans 1–8 are merged.

**Tech Stack:** JSON manifests, README.

## Global Constraints

- Current release line is `0.8.0`. Target is **`0.9.0`**. Never use 0.8.1 or 0.10.0+ for this batch.
- Do not rewrite plugin `description` unless a feature plan already did — this task only changes `version` (and README `版本` clause).
- This repo gitignores `docs/superpowers/`. This plan lives under `docs/design/`.

## File Structure

| File | Responsibility |
|---|---|
| `.claude-plugin/plugin.json` | `"version": "0.9.0"` |
| `.claude-plugin/marketplace.json` | `plugins[0].version` |
| `README.md` | `版本 \`0.9.0\`` |

---

### Task 1: Bump to 0.9.0

**Files:**
- Modify: `.claude-plugin/plugin.json` `"version"`
- Modify: `.claude-plugin/marketplace.json` `plugins[0].version`
- Modify: `README.md` first-paragraph version clause

- [ ] **Step 1: Preconditions**

Confirm plans 1–8 from `polish-0.9.0-design.md` are on the branch (docs truth-up, cursor DX, segment-watch unblock, segment-watch perf, fence unify, redact expand, CI/shellcheck, checkpoint command). If any are missing, **stop**.

- [ ] **Step 2: Set version**

In both JSON files set `"version": "0.9.0"`.

In `README.md`, opening version clause:

```markdown
版本 `0.9.0`
```

(Match existing punctuation style next to that clause — keep the rest of the sentence.)

- [ ] **Step 3: Verify**

```bash
python3 - <<'PY'
import json
from pathlib import Path
v = "0.9.0"
p = json.loads(Path(".claude-plugin/plugin.json").read_text())
m = json.loads(Path(".claude-plugin/marketplace.json").read_text())
assert p["version"] == v, p["version"]
assert m["plugins"][0]["version"] == v, m["plugins"][0]["version"]
assert f"版本 `{v}`" in Path("README.md").read_text(), "README version line"
print("PASS:", v)
PY
```

Expected: `PASS: 0.9.0`

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json README.md
git commit -m "$(cat <<'EOF'
chore: bump to 0.9.0

EOF
)"
```
