# CI hook tests Implementation Plan

> **HISTORICAL.** Part of the 0.4→0.5 batch (`optimization-plans.md`). Do not re-execute.


> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One local command and one GitHub Actions workflow that run every `hooks/scripts/test-*.sh`.

**Architecture:** `run-tests.sh` loops `test-*.sh` in the same directory, fails on first non-zero. Workflow checks out and runs that script on `ubuntu-latest`.

**Tech Stack:** bash, GitHub Actions.

## Global Constraints

- Do not add Node/pytest. Do not install extra apt packages (`bash`, `coreutils`, `gawk` are enough; `jq` is optional — existing tests already cover no-jq paths).
- Do not bump version. Batch release is **0.5.0** after all optimization plans (`docs/design/version-0.5.0-plan.md`).
- This repo gitignores `docs/superpowers/`. This plan lives under `docs/design/`.
- README directory tree should list `run-tests.sh` and `.github/workflows/hooks.yml`.

## File Structure

| File | Responsibility |
|---|---|
| `hooks/scripts/run-tests.sh` | run all `test-*.sh` |
| `.github/workflows/hooks.yml` | CI |
| `README.md` | how to run tests |

---

### Task 1: Runner + workflow

**Files:**
- Create: `hooks/scripts/run-tests.sh`
- Create: `.github/workflows/hooks.yml`
- Modify: `README.md` (使用 or 目錄結構)

- [ ] **Step 1: Write `hooks/scripts/run-tests.sh`**

```bash
#!/usr/bin/env bash
# Run every hook self-check. Usage: bash hooks/scripts/run-tests.sh
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAIL=0
shopt -s nullglob
for t in "$DIR"/test-*.sh; do
  echo "=== $(basename "$t") ==="
  if ! bash "$t"; then
    FAIL=1
  fi
done
if [ "$FAIL" -ne 0 ]; then
  echo "Some hook self-checks FAILED."
  exit 1
fi
echo "All hook self-checks passed."
exit 0
```

- [ ] **Step 2: Write `.github/workflows/hooks.yml`**

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
      - name: Run hook self-checks
        run: bash hooks/scripts/run-tests.sh
```

- [ ] **Step 3: Run locally**

```bash
bash hooks/scripts/run-tests.sh
```

Expected: `All hook self-checks passed.` (whatever `test-*.sh` exist on this branch).

- [ ] **Step 4: README** add under 目錄結構 `hooks/scripts/run-tests.sh` and a short 測試 line:

```markdown
測試：`bash hooks/scripts/run-tests.sh`
```

- [ ] **Step 5: Commit**

```bash
git add hooks/scripts/run-tests.sh .github/workflows/hooks.yml README.md
git commit -m "$(cat <<'EOF'
ci: run hook self-checks on every push

EOF
)"
```

