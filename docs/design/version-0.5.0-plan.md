# Batch version 0.5.0 Implementation Plan

> **HISTORICAL.** Part of the 0.4→0.5 batch (`optimization-plans.md`). Do not re-execute.


> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After all thirteen optimization feature plans are on the branch, bump the plugin from `0.4.0` to **`0.5.0` once**.

**Architecture:** Three files, same string. No other behavior. Do not run this plan until plans 1–13 are done.

**Tech Stack:** JSON manifests, README.

## Global Constraints

- Current `main` is `0.4.0`. Target is **`0.5.0`**. Never use 0.4.1 or 0.6.0+ for this batch.
- Do not rewrite plugin `description` unless a feature plan already did in an earlier commit — this task only changes `version`.
- This repo gitignores `docs/superpowers/`. This plan lives under `docs/design/`.

## File Structure

| File | Responsibility |
|---|---|
| `.claude-plugin/plugin.json` | `"version": "0.5.0"` |
| `.claude-plugin/marketplace.json` | `plugins[0].version` |
| `README.md` | `版本 \`0.5.0\`` |

---

### Task 1: Bump to 0.5.0

**Files:**
- Modify: `.claude-plugin/plugin.json` `"version"`
- Modify: `.claude-plugin/marketplace.json` `plugins[0].version`
- Modify: `README.md` first paragraph `版本 \`0.4.0\`` (or whatever HEAD still says if a feature plan touched README without bumping)

- [ ] **Step 1: Set version**

In `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, set `"version": "0.5.0"`.

In `README.md`, the opening version clause must be:

```markdown
版本 `0.5.0`。
```

- [ ] **Step 2: Verify**

```bash
python3 - <<'PY'
import json
from pathlib import Path
v = "0.5.0"
p = json.loads(Path(".claude-plugin/plugin.json").read_text())
m = json.loads(Path(".claude-plugin/marketplace.json").read_text())
assert p["version"] == v, p["version"]
assert m["plugins"][0]["version"] == v, m["plugins"][0]["version"]
assert f"版本 `{v}`" in Path("README.md").read_text(), "README version line"
print("PASS:", v)
PY
```

Expected: `PASS: 0.5.0`

- [ ] **Step 3: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json README.md
git commit -m "$(cat <<'EOF'
chore: bump to 0.5.0

EOF
)"
```
