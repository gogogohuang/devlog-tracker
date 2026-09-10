# Prompt redact Implementation Plan

> **HISTORICAL.** Part of the 0.4→0.5 batch (`optimization-plans.md`). Do not re-execute.


> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace a small set of token-shaped substrings in the User Input skeleton before writing `devlog.md`. Not a general secret scanner.

**Architecture:** `redact-prompt.sh` is sourced from `round-start.sh` after prompt extract/truncate/fence sanitize. Tests cover the function in isolation and one round-start integration case.

**Tech Stack:** bash `sed`.

## Global Constraints

- Truncation at 4000 characters stays **before** redact (so a token split by truncate may remain — acceptable).
- Replacement string is exactly `（已遮罩）` (fullwidth parens).
- Patterns (and only these):
  - `sk-ant-api03-[A-Za-z0-9_-]+`
  - `sk-ant-[A-Za-z0-9_-]{20,}`
  - `ghp_[A-Za-z0-9]{20,}`
  - `github_pat_[A-Za-z0-9_]{20,}`
  - `xox[baprs]-[A-Za-z0-9-]{10,}`
  - `AKIA[A-Z0-9]{16}`
  - `-----BEGIN [A-Z ]*PRIVATE KEY-----` through `-----END [A-Z ]*PRIVATE KEY-----` (inclusive, multiline)
- Do not redact URLs, emails, or UUID-looking strings.
- Do not bump version. Batch release is **0.5.0** after all optimization plans (`docs/design/version-0.5.0-plan.md`).
- Update `docs/design/recording-moments.md` known limitation "Secrets in the prompt".
- This repo gitignores `docs/superpowers/`. This plan lives under `docs/design/`.

## File Structure

| File | Responsibility |
|---|---|
| `hooks/scripts/redact-prompt.sh` | `redact_prompt` reads stdin, writes stdout |
| `hooks/scripts/test-redact-prompt.sh` | unit cases |
| `hooks/scripts/round-start.sh` | pipe prompt through redact |
| `hooks/scripts/test-round-start.sh` | one integration case |
| `docs/design/recording-moments.md` | limitation text |

---

### Task 1: Unit tests + function

- [ ] **Step 1: `test-redact-prompt.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/redact-prompt.sh"
FAIL=0
check() {
  local d="$1" in="$2" needle="$3" forbidden="$4"
  out="$(printf '%s' "$in" | redact_prompt)"
  case "$out" in *"$needle"*) echo "PASS: $d masked" ;; *) echo "FAIL: $d no mask [$out]"; FAIL=1 ;; esac
  if [ -n "$forbidden" ]; then
    case "$out" in *"$forbidden"*) echo "FAIL: $d leaked"; FAIL=1 ;; *) echo "PASS: $d no leak" ;; esac
  fi
}
check ant "token sk-ant-api03-ABCDEFG123456 end" "（已遮罩）" "sk-ant-api03-ABCDEFG123456"
check ghp "ghp_abcdefghijklmnopqrstuvwxyz0123456789" "（已遮罩）" "ghp_abcdefghijklmnopqrstuvwxyz0123456789"
check akia "AKIAIOSFODNN7EXAMPLE" "（已遮罩）" "AKIAIOSFODNN7EXAMPLE"
keep="$(printf '%s' 'see https://example.com/user/alpha' | redact_prompt)"
[ "$keep" = "see https://example.com/user/alpha" ] && echo "PASS: url kept" || { echo "FAIL: url $keep"; FAIL=1; }
pem="$(printf '%s\n' '-----BEGIN PRIVATE KEY-----' 'MIIB' '-----END PRIVATE KEY-----' | redact_prompt)"
case "$pem" in *PRIVATE KEY*) echo "FAIL: pem leaked"; FAIL=1 ;; *「已遮罩」*|*（已遮罩）*) echo "PASS: pem masked" ;; *) echo "FAIL: pem [$pem]"; FAIL=1 ;; esac
if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
```

Use only `（已遮罩）` in the pem assertion (the doubled needle above is a writing slip — implement the test with that one string).

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement `redact_prompt` with `sed -E`** (and `sed` for the PEM range). macOS BSD sed: do not use GNU `-z` unless you also handle BSD; PEM via awk is OK:

```bash
redact_prompt() {
  awk '
    /-----BEGIN [A-Z ]*PRIVATE KEY-----/ { skip=1; print "（已遮罩）"; next }
    skip && /-----END [A-Z ]*PRIVATE KEY-----/ { skip=0; next }
    skip { next }
    { print }
  ' | sed -E \
    -e 's/sk-ant-api03-[A-Za-z0-9_-]+/（已遮罩）/g' \
    -e 's/sk-ant-[A-Za-z0-9_-]{20,}/（已遮罩）/g' \
    -e 's/ghp_[A-Za-z0-9]{20,}/（已遮罩）/g' \
    -e 's/github_pat_[A-Za-z0-9_]{20,}/（已遮罩）/g' \
    -e 's/xox[baprs]-[A-Za-z0-9-]{10,}/（已遮罩）/g' \
    -e 's/AKIA[A-Z0-9]{16}/（已遮罩）/g'
}
```

- [ ] **Step 4: Unit tests pass. Commit** `feat: redact common token patterns in User Input`

---

### Task 2: Wire round-start

After fence sanitize, before append:

```bash
PROMPT="$(printf '%s' "$PROMPT" | redact_prompt)"
```

Source `redact-prompt.sh` from `HOOKS_DIR`.

Add `test-round-start.sh` case: prompt contains `ghp_` + 36 alnum, written User Input contains `（已遮罩）` and not the raw token.

Update recording-moments limitation to: common provider-prefix tokens are masked; other secrets still copy into the project file.

- [ ] **Commit** `feat: apply prompt redact in round-start skeletons`

