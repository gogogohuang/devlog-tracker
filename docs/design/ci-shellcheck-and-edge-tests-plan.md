# CI shellcheck and edge tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run shellcheck on hook/adapter scripts in CI; add any remaining edge self-checks not already landed by plans 2–5.

**Architecture:** Extend `.github/workflows/hooks.yml` with a shellcheck step (apt install on ubuntu-latest). Edge tests live in existing `test-*.sh` / `test-adapters.sh` — only add cases still missing after earlier PRs.

**Tech Stack:** GitHub Actions, shellcheck, bash self-checks.

## Global Constraints

- Spec: [`polish-0.9.0-design.md`](polish-0.9.0-design.md) §6.
- Out of scope: flaky multi-process lock stress; macOS CI matrix.
- Do not bump version.
- If plans 2–5 already added their edge tests, this plan’s test task is a **gap audit** — add only what is still missing (document “already covered” in the commit body if empty).
- This plan lives under `docs/design/`.

## File Structure

| File | Responsibility |
|---|---|
| `.github/workflows/hooks.yml` | shellcheck + existing `run-tests.sh` |
| `cursor/hooks/test-adapters.sh` / `hooks/scripts/test-redact-prompt.sh` / etc. | only if gaps remain |

---

### Task 1: shellcheck in CI

**Files:**
- Modify: `.github/workflows/hooks.yml`

- [ ] **Step 1: Update workflow**

```yaml
name: hook-self-checks
on:
  push:
  pull_request:
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install shellcheck
        run: sudo apt-get update && sudo apt-get install -y shellcheck
      - name: Shellcheck hook scripts
        run: |
          shellcheck --severity=source --severity=source-path=SCRIPTDIR \
            hooks/scripts/*.sh cursor/hooks/*.sh
      - name: Run hook self-checks
        run: bash hooks/scripts/run-tests.sh
```

If shellcheck flags pre-existing style issues that are noisy:

1. Prefer fixing real bugs (unquoted expansions that break).
2. For sourced helpers, keep `# shellcheck source=…` directives already in tree.
3. Only as last resort: `shellcheck -e SC1091` etc. — list each disabled code in the commit message.

- [ ] **Step 2: Run locally if shellcheck is installed**

```bash
shellcheck --severity=source --severity=source-path=SCRIPTDIR hooks/scripts/*.sh cursor/hooks/*.sh
bash hooks/scripts/run-tests.sh
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/hooks.yml
# plus any SC fixes in scripts
git commit -m "$(cat <<'EOF'
ci: run shellcheck on hooks and cursor adapters

EOF
)"
```

---

### Task 2: Edge-test gap audit

- [ ] **Step 1: Checklist against design**

Confirm these exist after plans 2–5; if not, add them here with TDD:

| Case | Expected home |
|---|---|
| Cursor no-jq `session_id` | `cursor/hooks/test-adapters.sh` |
| Redact openai `sk-` / Bearer / JWT + UUID kept | `hooks/scripts/test-redact-prompt.sh` |
| Segment-watch cksum spy / identity skip | `hooks/scripts/test-segment-watch.sh` |
| Indented fence in `devlog_list_round_starts` | `hooks/scripts/test-devlog-md.sh` |

- [ ] **Step 2: Add only missing cases; run `bash hooks/scripts/run-tests.sh`**

- [ ] **Step 3: Commit only if files changed**

```bash
git add cursor/hooks/test-adapters.sh hooks/scripts/test-*.sh
git commit -m "$(cat <<'EOF'
test: fill polish-batch edge cases still missing after prior PRs

EOF
)"
```

If nothing missing: skip commit; note in PR description “gap audit clean.”
