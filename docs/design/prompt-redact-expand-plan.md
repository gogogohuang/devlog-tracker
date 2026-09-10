# Prompt redact expand Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mask additional common token shapes in User Input (`sk-` beyond Anthropic, Bearer tokens, JWT-shaped strings); strengthen start’s `.gitignore` nudge copy. Still not a general secret scanner.

**Architecture:** Extend `redact_prompt` sed/awk patterns; expand `test-redact-prompt.sh`. Tighten Traditional Chinese copy in `commands/start.md` when `GITIGNORE_DEVLOG=no`. Update recording-moments limitation text honestly (truncate-before-redact remains).

**Tech Stack:** bash, sed -E, awk.

## Global Constraints

- Spec: [`polish-0.9.0-design.md`](polish-0.9.0-design.md) §5.
- Replacement string remains exactly `（已遮罩）`.
- Truncation at 4000 stays **before** redact (token split by truncate may remain — document, do not “fix”).
- Do not redact bare URLs, emails, or UUIDs.
- Do not auto-edit `.gitignore` without user consent.
- Do not bump version.
- This plan lives under `docs/design/`.

## Patterns after this plan (complete set)

Keep existing:

- `sk-ant-api03-[A-Za-z0-9_-]+`
- `sk-ant-[A-Za-z0-9_-]{20,}`
- `ghp_[A-Za-z0-9]{20,}`
- `github_pat_[A-Za-z0-9_]{20,}`
- `xox[baprs]-[A-Za-z0-9-]{10,}`
- `AKIA[A-Z0-9]{16}`
- PEM private key blocks

**Add:**

- OpenAI-style: `sk-[A-Za-z0-9]{20,}` but apply **after** the more specific `sk-ant-…` rules (order matters so Anthropic tokens still match first; result is still `（已遮罩）`).
- `Bearer [A-Za-z0-9._\-+=/]{20,}`
- JWT: three base64url segments: `[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+` with each segment length ≥ 10 (avoid masking `a.b.c` short dotted words). Use sed -E carefully; if overly broad in practice, require first segment to start with `eyJ` (recommended default).

**Recommended JWT rule:** `eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+`

## File Structure

| File | Responsibility |
|---|---|
| `hooks/scripts/redact-prompt.sh` | patterns |
| `hooks/scripts/test-redact-prompt.sh` | new positives + URL/UUID negatives |
| `commands/start.md` | stronger gitignore nudge |
| `docs/design/recording-moments.md` | limitation list updated |

---

### Task 1: Redact unit tests + implementation

- [ ] **Step 1: Extend `test-redact-prompt.sh`**

Add checks (same `check` helper style as existing):

```bash
check openai "key sk-abcdefghijklmnopqrstuvwxyz123456 end" "（已遮罩）" "sk-abcdefghijklmnopqrstuvwxyz123456"
check bearer "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.aaaaabbbbbcccccdddddeeeee.fffffggggghhhhhiiiiijjjjj" "（已遮罩）" "Bearer eyJ"
# Prefer asserting the JWT blob is gone:
check jwt "token eyJhbGciOiJIUzI1NiJ9.aaaaabbbbbcccccdddddeeeee.fffffggggghhhhhiiiiijjjjj end" "（已遮罩）" "eyJhbGciOiJIUzI1NiJ9"
keep_uuid="$(printf '%s' 'id 550e8400-e29b-41d4-a716-446655440000' | redact_prompt)"
[ "$keep_uuid" = "id 550e8400-e29b-41d4-a716-446655440000" ] && echo "PASS: uuid kept" || { echo "FAIL: uuid $keep_uuid"; FAIL=1; }
```

Keep existing ant/ghp/akia/pem/url cases.

- [ ] **Step 2: Run — FAIL**

```bash
bash hooks/scripts/test-redact-prompt.sh
```

- [ ] **Step 3: Implement**

Append to the `sed -E` chain in `redact_prompt` (after `sk-ant-` rules):

```bash
    -e 's/sk-[A-Za-z0-9]{20,}/（已遮罩）/g' \
    -e 's/Bearer [A-Za-z0-9._\-+=\/]{20,}/（已遮罩）/g' \
    -e 's/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/（已遮罩）/g'
```

- [ ] **Step 4: Pass + commit**

```bash
bash hooks/scripts/test-redact-prompt.sh
git add hooks/scripts/redact-prompt.sh hooks/scripts/test-redact-prompt.sh
git commit -m "$(cat <<'EOF'
feat: expand prompt redact for sk-/Bearer/JWT shapes

EOF
)"
```

---

### Task 2: Stronger gitignore nudge + docs

- [ ] **Step 1: `commands/start.md` step 2**

Replace the soft suggest with firmer Traditional Chinese that:

1. States `.devlog/` **will contain raw prompts** (redact is partial only).
2. **Strongly recommends** adding `.devlog/` to `.gitignore`.
3. Still requires explicit user yes before appending.
4. If user declines, warn once that secrets may be committed accidentally.

Exact replacement for step 2:

```markdown
2. 若 stdout 有 `GITIGNORE_DEVLOG=no`：鄭重提醒——`.devlog/` 會寫入使用者原文（遮罩只覆蓋常見 token 前綴，不是通用掃密）。**強烈建議**把 `.devlog/` 加進專案 `.gitignore`。問要不要現在加。只有使用者明確說要，才在 `.gitignore` 末尾追加一行 `.devlog/`（檔案不存在就建立）。不要改其他行。若使用者拒絕，再警告一次「之後若不小心 commit，prompt／殘留密鑰可能進版控」，然後繼續步驟 3。
```

- [ ] **Step 2: `recording-moments.md` secrets limitation**

Update to list the expanded pattern families and keep: truncate-before-redact; not a general scanner; other secrets still copy into the project file.

- [ ] **Step 3: Commit**

```bash
git add commands/start.md docs/design/recording-moments.md
git commit -m "$(cat <<'EOF'
docs: strengthen .devlog gitignore nudge and redact limitations

EOF
)"
```
