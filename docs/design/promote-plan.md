# promote（規範回流）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `/devlog-tracker:promote`：從已 keep 的檔、lessons 檔與 Checkpoint 的 `### 決策` 挑出「之後應該一直遵守」的規範候選，使用者選定後寫進 CLAUDE.md 或 AGENTS.md 的 `<!-- devlog-tracker:rules:begin/end -->` 受管區塊。

**Architecture:** 三支小腳本各管一件事：`promote-sources.sh`（列來源，純讀取）、`promote-target.sh`（決定目標檔，純讀取）、`promote-write.sh`（在受管區塊內追加、逐字去重）。挑候選、等使用者選擇由 `commands/promote.md` 指揮模型完成。

**Tech Stack:** bash（macOS 3.2 相容）、POSIX awk、Node `node:test`（`cli/agents-md.test.js` 回歸測試）。

**Spec:** [`read-side-and-promote.md`](read-side-and-promote.md) §D

## Global Constraints

- 一般 PR 不改版號。
- 沒有使用者明確選擇就不寫入任何檔案。
- 只在 rules 區塊內追加；不刪除、不改寫區塊內既有規則，也不動區塊外的內容。
- rules 區塊必須獨立於 `init` 管理的 `<!-- devlog-tracker:begin/end -->` 區塊（`init` 會整塊覆寫自己的區塊）。
- `promote` **不**列入 `round-start.sh` 的 admin 清單（會改專案檔案，照常記 Round）。
- `overview` 維持純讀取，只加一句指向 `promote` 的說明。
- awk 只用 POSIX 功能；雙檔 awk 不用 `NR==FNR`（第一個檔為空時會誤判），改用 `FILENAME`。
- 驗證三步：shellcheck（同 AGENTS.md）、`bash core/scripts/run-tests.sh`、`npm test`。
- Commit 訊息結尾加 `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `core/scripts/promote-sources.sh` | Create | 列出 kept／lessons 檔與 Checkpoint 位置 |
| `core/scripts/promote-target.sh` | Create | 決定寫 CLAUDE.md 或 AGENTS.md，回報既有規則數 |
| `core/scripts/promote-write.sh` | Create | 建立或追加 rules 區塊、逐字去重 |
| `core/scripts/tests/test-promote.sh` | Create | 三支腳本的測試 |
| `cli/agents-md.test.js` | Modify | 鎖住「`init` 不動 rules 區塊」 |
| `commands/promote.md` | Create | 指令文件 |
| `commands/overview.md` | Modify | 結尾指向 `promote` |
| `core/scripts/tests/test-round-start.sh` | Modify | `promote` 不被豁免 |
| `cli/agents-md.js`、`cli/platforms/claude.js`、`README.md`、`README.zh-TW.md` | Modify | 對照表與指令表 |

## 受管區塊格式

```
<!-- devlog-tracker:rules:begin -->
## devlog-tracker 沉澱的規範

- <規則>（來源：<檔名>「<標題>」）
<!-- devlog-tracker:rules:end -->
```

標記行必須整行完全相同才算數（`$0 == mark`）。

---

### Task 1: `promote-sources.sh` 與 `promote-target.sh`

**Files:**
- Create: `core/scripts/promote-sources.sh`
- Create: `core/scripts/promote-target.sh`
- Test: `core/scripts/tests/test-promote.sh`

**Interfaces:**
- Consumes: `devlog_resolve_paths`、`devlog_kept_index_lines`、`devlog_lessons_index_lines`。
- Produces:
  - `promote-sources.sh` → 每行一筆：`FILE=<abs> KIND=kept EXISTS=0|1`、`FILE=<abs> KIND=lessons EXISTS=0|1`、`CHECKPOINT=<abs devlog file>:<line>`；全無時一行 `NO_SOURCES`。
  - `promote-target.sh` → `TARGET=<abs path>`；目標檔已有 rules 區塊時多一行 `EXISTING=<區塊內 "- " 開頭的行數>`。

- [ ] **Step 1: 寫失敗測試**

Create `core/scripts/tests/test-promote.sh`：

```bash
#!/usr/bin/env bash
# Self-check for promote-{sources,target,write}.sh
# (docs/design/read-side-and-promote.md D).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
FAIL=0
assert_line() {
  local desc="$1" expected="$2" out="$3"
  if printf '%s\n' "$out" | grep -qxF "$expected"; then echo "PASS: $desc"
  else echo "FAIL: $desc (missing [$expected] in: $out)"; FAIL=1; fi
}
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then echo "PASS: $desc"
  else echo "FAIL: $desc (expected [$expected] got [$actual])"; FAIL=1; fi
}
new_project() { local d; d="$(mktemp -d "$TMP_ROOT/p.XXXXXX")"; (cd "$d" && pwd); }

# === promote-sources.sh =========================================================
P="$(new_project)"
assert_eq "sources: no devlog -> NO_SOURCES" "NO_SOURCES" "$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-sources.sh")"

mkdir -p "$P/.devlog"
cat > "$P/.devlog/devlog.md" <<'EOF'
## Round 1 — 2026-09-01T10:00:00+0800

### Summary
x

### Status
DONE
EOF
assert_eq "sources: devlog without index/checkpoint -> NO_SOURCES" "NO_SOURCES" "$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-sources.sh")"

cat >> "$P/.devlog/devlog.md" <<'EOF'

```
## Checkpoint fake inside fence
```

## Checkpoint（Round 1-1）
### 決策
- always run shellcheck

## Kept 索引
- `devlog.topic-a.md`：Round 1-1，kept_at 2026-09-05T00:00:00+0800，topic a
- `devlog.ghost.md`：Round 2-2，kept_at 2026-09-05T00:00:00+0800，gone

## Lessons 索引
- `devlog.lessons.lock-files.md`：1 則，最新一則「x。」（updated_at 2026-09-01T00:00:00+0800）
EOF
printf 'kept\n' > "$P/.devlog/devlog.topic-a.md"
printf '# Lessons: lock-files\n' > "$P/.devlog/devlog.lessons.lock-files.md"
OUT="$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-sources.sh")"
assert_line "sources: kept file exists" "FILE=$P/.devlog/devlog.topic-a.md KIND=kept EXISTS=1" "$OUT"
assert_line "sources: kept ghost row" "FILE=$P/.devlog/devlog.ghost.md KIND=kept EXISTS=0" "$OUT"
assert_line "sources: lessons file" "FILE=$P/.devlog/devlog.lessons.lock-files.md KIND=lessons EXISTS=1" "$OUT"
CP_LINE="$(grep -n '^## Checkpoint（Round 1-1）' "$P/.devlog/devlog.md" | cut -d: -f1)"
assert_line "sources: real checkpoint line" "CHECKPOINT=$P/.devlog/devlog.md:$CP_LINE" "$OUT"
assert_eq "sources: fenced checkpoint ignored" "1" "$(printf '%s\n' "$OUT" | grep -c '^CHECKPOINT=')"

# === promote-target.sh ==========================================================
P="$(new_project)"
assert_eq "target: empty project -> CLAUDE.md" "TARGET=$P/CLAUDE.md" "$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-target.sh")"

printf '@AGENTS.md\n\n' > "$P/CLAUDE.md"
assert_eq "target: CLAUDE.md only imports AGENTS.md -> AGENTS.md" "TARGET=$P/AGENTS.md" "$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-target.sh")"

printf '# Rules\n\n@AGENTS.md\n' > "$P/CLAUDE.md"
assert_eq "target: CLAUDE.md with own content -> CLAUDE.md" "TARGET=$P/CLAUDE.md" "$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-target.sh")"

P="$(new_project)"
mkdir -p "$P/.codex"; printf '{}\n' > "$P/.codex/hooks.json"
assert_eq "target: codex-only (hooks.json) -> AGENTS.md" "TARGET=$P/AGENTS.md" "$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-target.sh")"

P="$(new_project)"
mkdir -p "$P/.agents/skills/devlog-start"
assert_eq "target: codex-only (skills) -> AGENTS.md" "TARGET=$P/AGENTS.md" "$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-target.sh")"

P="$(new_project)"
printf '# Mine\n\n<!-- devlog-tracker:rules:begin -->\n## devlog-tracker 沉澱的規範\n\n- a\n- b\n<!-- devlog-tracker:rules:end -->\n' > "$P/CLAUDE.md"
OUT="$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-target.sh")"
assert_line "target: existing block counted" "EXISTING=2" "$OUT"

# @@WRITE_TESTS@@

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `bash core/scripts/tests/test-promote.sh`
Expected: `FAIL`（腳本不存在）

- [ ] **Step 3: 實作 `core/scripts/promote-sources.sh`**

```bash
#!/usr/bin/env bash
# Sources for /devlog-tracker:promote (docs/design/read-side-and-promote.md D):
# kept files, lessons files, and Checkpoint headings in the current branch's
# devlog. Plain read only. compact never moves Checkpoints, so the archive has
# none to list.
set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=devlog-md.sh
. "$SCRIPT_DIR/devlog-md.sh"
# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"

PROJECT_DIR="$(cd "${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}" 2>/dev/null && pwd)" || { echo "NO_SOURCES"; exit 0; }
devlog_resolve_paths "$PROJECT_DIR"
MAIN="$DEVLOG_FILE"
[ -f "$MAIN" ] || { echo "NO_SOURCES"; exit 0; }

OUT=""
add() { OUT="$OUT$1"$'\n'; }
exists_flag() { if [ -f "$1" ]; then printf '1'; else printf '0'; fi; }

while IFS= read -r name; do
  [ -n "$name" ] || continue
  f="$DEVLOG_DIR/devlog.$name.md"
  add "FILE=$f KIND=kept EXISTS=$(exists_flag "$f")"
done < <(devlog_kept_index_lines "$MAIN" | sed -nE 's/.*`devlog\.([^`]+)\.md`.*/\1/p')

while IFS= read -r topic; do
  [ -n "$topic" ] || continue
  f="$DEVLOG_DIR/devlog.lessons.$topic.md"
  add "FILE=$f KIND=lessons EXISTS=$(exists_flag "$f")"
done < <(devlog_lessons_index_lines "$MAIN" | sed -nE 's/.*`devlog\.lessons\.([^`]+)\.md`.*/\1/p')

while IFS= read -r ln; do
  [ -n "$ln" ] && add "CHECKPOINT=$MAIN:$ln"
done < <(awk '/^[ \t]*```/ { fence = !fence; next } !fence && /^## Checkpoint/ { print NR }' "$MAIN")

if [ -z "$OUT" ]; then echo "NO_SOURCES"; else printf '%s' "$OUT"; fi
```

- [ ] **Step 4: 實作 `core/scripts/promote-target.sh`**

```bash
#!/usr/bin/env bash
# Picks the file /devlog-tracker:promote writes rules into
# (docs/design/read-side-and-promote.md D). Plain read only.
#   1. Codex-only project (no CLAUDE.md, Codex hooks or devlog skills present) -> AGENTS.md
#   2. CLAUDE.md that is nothing but "@AGENTS.md"                              -> AGENTS.md
#   3. otherwise                                                               -> CLAUDE.md
set -uo pipefail

PROJECT_DIR="$(cd "${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}" 2>/dev/null && pwd)" || exit 1
CLAUDE_MD="$PROJECT_DIR/CLAUDE.md"
AGENTS_MD="$PROJECT_DIR/AGENTS.md"
BEGIN_MARK='<!-- devlog-tracker:rules:begin -->'
END_MARK='<!-- devlog-tracker:rules:end -->'

HAS_CODEX=0
[ -f "$PROJECT_DIR/.codex/hooks.json" ] && HAS_CODEX=1
for d in "$PROJECT_DIR"/.agents/skills/devlog-*; do
  [ -d "$d" ] && HAS_CODEX=1
done

TARGET="$CLAUDE_MD"
if [ ! -f "$CLAUDE_MD" ] && [ "$HAS_CODEX" -eq 1 ]; then
  TARGET="$AGENTS_MD"
elif [ -f "$CLAUDE_MD" ] && [ "$(tr -d '[:space:]' < "$CLAUDE_MD")" = "@AGENTS.md" ]; then
  TARGET="$AGENTS_MD"
fi
echo "TARGET=$TARGET"

if [ -f "$TARGET" ] && grep -qxF "$BEGIN_MARK" "$TARGET"; then
  n="$(awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    $0 == b { g = 1; next }
    $0 == e { g = 0 }
    g && /^- / { c++ }
    END { print c + 0 }
  ' "$TARGET")"
  echo "EXISTING=$n"
fi
```

`chmod +x core/scripts/promote-sources.sh core/scripts/promote-target.sh`

- [ ] **Step 5: 跑測試確認通過**

Run: `bash core/scripts/tests/test-promote.sh && shellcheck --external-sources --source-path=SCRIPTDIR -S warning core/scripts/promote-sources.sh core/scripts/promote-target.sh core/scripts/tests/test-promote.sh`
Expected: `All checks passed.`，shellcheck 無輸出

- [ ] **Step 6: Commit**

```bash
git add core/scripts/promote-sources.sh core/scripts/promote-target.sh core/scripts/tests/test-promote.sh
git commit -m "feat: add promote-sources.sh and promote-target.sh

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `promote-write.sh`

**Files:**
- Create: `core/scripts/promote-write.sh`
- Test: `core/scripts/tests/test-promote.sh`（`# @@WRITE_TESTS@@` 處）

**Interfaces:**
- Consumes: `promote-target.sh` 的 `TARGET`（由指令文件傳入）；`devlog_lock_acquire`／`devlog_lock_release`。
- Produces: `promote-write.sh <target> <rules-file>` → stdout `ADDED=<n> SKIPPED_DUP=<m> TARGET=<path>`；參數錯誤 stderr `USAGE: …`、exit 2。

- [ ] **Step 1: 寫失敗測試**

把 `test-promote.sh` 的 `# @@WRITE_TESTS@@` 換成：

```bash
# === promote-write.sh ==========================================================
BEGIN_MARK='<!-- devlog-tracker:rules:begin -->'
END_MARK='<!-- devlog-tracker:rules:end -->'
P="$(new_project)"
RULES="$TMP_ROOT/rules.txt"

# --- target missing -> created with header ---------------------------------------
printf '  改核心腳本後跑 run-tests.sh  \n\n- 一般 PR 不改版號\n' > "$RULES"
OUT="$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-write.sh" "$P/CLAUDE.md" "$RULES")"
assert_eq "write: new file result" "ADDED=2 SKIPPED_DUP=0 TARGET=$P/CLAUDE.md" "$OUT"
EXPECTED="$(printf '%s\n## devlog-tracker 沉澱的規範\n\n- 改核心腳本後跑 run-tests.sh\n- 一般 PR 不改版號\n%s' "$BEGIN_MARK" "$END_MARK")"
assert_eq "write: new file content (trimmed, '- ' prefixed, blank skipped)" "$EXPECTED" "$(cat "$P/CLAUDE.md")"

# --- existing content without block -> appended after a blank line -------------------
P="$(new_project)"
printf '# Mine\nkeep me' > "$P/CLAUDE.md"
printf 'rule one\n' > "$RULES"
CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-write.sh" "$P/CLAUDE.md" "$RULES" >/dev/null
EXPECTED="$(printf '# Mine\nkeep me\n\n%s\n## devlog-tracker 沉澱的規範\n\n- rule one\n%s' "$BEGIN_MARK" "$END_MARK")"
assert_eq "write: appended after existing content (missing trailing newline handled)" "$EXPECTED" "$(cat "$P/CLAUDE.md")"

# --- existing block -> inserted before end mark; content after block kept -----------
printf '\n## After\ntail\n' >> "$P/CLAUDE.md"
printf 'rule two\n' > "$RULES"
CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-write.sh" "$P/CLAUDE.md" "$RULES" >/dev/null
EXPECTED="$(printf '# Mine\nkeep me\n\n%s\n## devlog-tracker 沉澱的規範\n\n- rule one\n- rule two\n%s\n\n## After\ntail' "$BEGIN_MARK" "$END_MARK")"
assert_eq "write: appended inside existing block" "$EXPECTED" "$(cat "$P/CLAUDE.md")"

# --- exact duplicates (existing + within input) skipped; file unchanged -------------
BEFORE="$(cat "$P/CLAUDE.md")"
printf -- '- rule one\nrule two\n' > "$RULES"
OUT="$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-write.sh" "$P/CLAUDE.md" "$RULES")"
assert_eq "write: all duplicates" "ADDED=0 SKIPPED_DUP=2 TARGET=$P/CLAUDE.md" "$OUT"
assert_eq "write: file unchanged on all-dup" "$BEFORE" "$(cat "$P/CLAUDE.md")"
printf 'rule three\nrule three\n' > "$RULES"
OUT="$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-write.sh" "$P/CLAUDE.md" "$RULES")"
assert_eq "write: duplicate within input counted once" "ADDED=1 SKIPPED_DUP=1 TARGET=$P/CLAUDE.md" "$OUT"

# --- lock released ------------------------------------------------------------------
mkdir -p "$P/.devlog"
CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-write.sh" "$P/CLAUDE.md" "$RULES" >/dev/null
[ ! -e "$P/.devlog/.lock" ] && echo "PASS: write: lock released" || { echo "FAIL: write: .lock left behind"; FAIL=1; }

# --- usage errors ---------------------------------------------------------------------
bash "$SCRIPT_DIR/promote-write.sh" >/dev/null 2>&1
RC=$?
assert_eq "write: no args exits 2" "2" "$RC"
bash "$SCRIPT_DIR/promote-write.sh" "$P/CLAUDE.md" "$TMP_ROOT/missing.txt" >/dev/null 2>&1
RC=$?
assert_eq "write: missing rules file exits 2" "2" "$RC"
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `bash core/scripts/tests/test-promote.sh`
Expected: `write:` 相關 `FAIL`

- [ ] **Step 3: 實作 `core/scripts/promote-write.sh`**

```bash
#!/usr/bin/env bash
# Writes rules chosen in /devlog-tracker:promote into the managed block
# <!-- devlog-tracker:rules:begin/end --> of <target>
# (docs/design/read-side-and-promote.md D). Append-only: never edits or
# removes a rule already in the block, never touches anything outside it.
# Exact-line duplicates (against the block, and within the input) are skipped.
# Usage: promote-write.sh <target> <rules-file>
set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"

TARGET="${1:-}"
RULES="${2:-}"
if [ -z "$TARGET" ] || [ ! -f "$RULES" ]; then
  echo "USAGE: promote-write.sh <target> <rules-file>" >&2
  exit 2
fi
BEGIN_MARK='<!-- devlog-tracker:rules:begin -->'
END_MARK='<!-- devlog-tracker:rules:end -->'

devlog_resolve_paths "${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
NEW="$(mktemp "${TMPDIR:-/tmp}/devlog-promote.XXXXXX")" || exit 1
EXISTING="$(mktemp "${TMPDIR:-/tmp}/devlog-promote.XXXXXX")" || exit 1
TO_ADD="$(mktemp "${TMPDIR:-/tmp}/devlog-promote.XXXXXX")" || exit 1
trap 'rm -f "$NEW" "$EXISTING" "$TO_ADD" "$TARGET.tmp"; devlog_lock_release' EXIT
[ -d "$DEVLOG_DIR" ] && devlog_lock_acquire

# Normalise: trim, drop blank lines, ensure a "- " list prefix.
awk '
  { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }
  $0 != "" { if ($0 !~ /^- /) $0 = "- " $0; print }
' "$RULES" > "$NEW"

if [ -f "$TARGET" ]; then
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '$0 == b { g = 1; next } $0 == e { g = 0 } g' "$TARGET" > "$EXISTING"
fi

# FILENAME, not NR==FNR: an empty $EXISTING would make NR==FNR true for $NEW too.
awk -v ex="$EXISTING" 'FILENAME == ex { seen[$0] = 1; next } !seen[$0]++' "$EXISTING" "$NEW" > "$TO_ADD"

TOTAL="$(awk 'END { print NR }' "$NEW")"
ADDED="$(awk 'END { print NR }' "$TO_ADD")"
SKIPPED=$((TOTAL - ADDED))

if [ "$ADDED" -gt 0 ]; then
  if [ -f "$TARGET" ] && grep -qxF "$BEGIN_MARK" "$TARGET" && grep -qxF "$END_MARK" "$TARGET"; then
    awk -v e="$END_MARK" -v add="$TO_ADD" '
      $0 == e && !done { while ((getline l < add) > 0) print l; done = 1 }
      { print }
    ' "$TARGET" > "$TARGET.tmp" || exit 1
  else
    {
      if [ -s "$TARGET" ]; then
        cat "$TARGET"
        [ -n "$(tail -c 1 "$TARGET")" ] && printf '\n'
        printf '\n'
      fi
      printf '%s\n## devlog-tracker 沉澱的規範\n\n' "$BEGIN_MARK"
      cat "$TO_ADD"
      printf '%s\n' "$END_MARK"
    } > "$TARGET.tmp" || exit 1
  fi
  mv "$TARGET.tmp" "$TARGET" || exit 1
fi

echo "ADDED=$ADDED SKIPPED_DUP=$SKIPPED TARGET=$TARGET"
```

`chmod +x core/scripts/promote-write.sh`

- [ ] **Step 4: 跑測試確認通過**

Run: `bash core/scripts/tests/test-promote.sh && shellcheck --external-sources --source-path=SCRIPTDIR -S warning core/scripts/promote-write.sh core/scripts/tests/test-promote.sh`
Expected: `All checks passed.`，shellcheck 無輸出

- [ ] **Step 5: Commit**

```bash
git add core/scripts/promote-write.sh core/scripts/tests/test-promote.sh
git commit -m "feat: add promote-write.sh for the managed rules block

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: 鎖住「`init` 不動 rules 區塊」

**Files:**
- Test: `cli/agents-md.test.js`

**Interfaces:**
- Consumes: `upsertAgentsMd`、`upsertMarkdown`、`BEGIN`（既有）。

這是回歸測試：現有的 `indexOf(BEGIN)` 不會誤中 `rules:begin`，所以測試寫好就會通過。目的是防止之後有人改動 marker 比對方式時把規則洗掉。

- [ ] **Step 1: 寫測試**

在 `cli/agents-md.test.js` 的 `test('block mentions every command doc …')` 之前加：

```js
const RULES_BLOCK = '<!-- devlog-tracker:rules:begin -->\n## devlog-tracker 沉澱的規範\n\n- rule one\n<!-- devlog-tracker:rules:end -->\n';

test('upsert never touches the promote rules block (rules before the init block)', () => {
  const dir = tmp();
  fs.writeFileSync(path.join(dir, 'AGENTS.md'), `# Mine\n\n${RULES_BLOCK}`);
  upsertAgentsMd(dir);
  upsertAgentsMd(dir);
  const text = fs.readFileSync(path.join(dir, 'AGENTS.md'), 'utf8');
  assert.ok(text.includes(RULES_BLOCK));
  assert.equal(text.split(BEGIN).length, 2);
});

test('upsert never touches the promote rules block (rules after the init block)', () => {
  const dir = tmp();
  upsertAgentsMd(dir);
  fs.appendFileSync(path.join(dir, 'AGENTS.md'), `\n${RULES_BLOCK}`);
  upsertAgentsMd(dir);
  const text = fs.readFileSync(path.join(dir, 'AGENTS.md'), 'utf8');
  assert.ok(text.includes(RULES_BLOCK));
  assert.ok(text.indexOf(END) < text.indexOf(RULES_BLOCK));
});

test('claude CLAUDE.md upsert never touches the promote rules block', () => {
  const dir = tmp();
  fs.writeFileSync(path.join(dir, 'CLAUDE.md'), `# Mine\n\n${RULES_BLOCK}`);
  upsertMarkdown(dir, { fileName: 'CLAUDE.md', block: `${BEGIN}\nx\n${END}\n` });
  upsertMarkdown(dir, { fileName: 'CLAUDE.md', block: `${BEGIN}\ny\n${END}\n` });
  const text = fs.readFileSync(path.join(dir, 'CLAUDE.md'), 'utf8');
  assert.ok(text.includes(RULES_BLOCK));
  assert.ok(text.includes('\ny\n') && !text.includes('\nx\n'));
});
```

- [ ] **Step 2: 跑測試**

Run: `node --test cli/agents-md.test.js`
Expected: PASS。若 FAIL，代表 `upsertMarkdown` 會誤動 rules 區塊——停下來修 `cli/agents-md.js` 的 marker 比對（改成整行比對），不要改測試。

- [ ] **Step 3: Commit**

```bash
git add cli/agents-md.test.js
git commit -m "test: lock that init never rewrites the promote rules block

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `/devlog-tracker:promote` 指令與文件

**Files:**
- Create: `commands/promote.md`
- Modify: `commands/overview.md`（步驟 2 第 2 點結尾）
- Modify: `core/scripts/tests/test-round-start.sh`（`21b` 區塊）
- Modify: `cli/agents-md.js`、`cli/platforms/claude.js`、`README.md`、`README.zh-TW.md`

**Interfaces:**
- Consumes: Task 1–2 三支腳本的輸出契約。

- [ ] **Step 1: 寫測試（`promote` 不被豁免）**

`core/scripts/tests/test-round-start.sh` 的 `21b` 區塊，把 `for WORK_CMD in pr; do` 改成：

```bash
for WORK_CMD in pr promote; do
```

Run: `bash core/scripts/tests/test-round-start.sh 2>&1 | grep 'promote command'`
Expected: `PASS: promote command still opens a Round`（守護測試）

- [ ] **Step 2: 建立 `commands/promote.md`**

````markdown
---
description: 從已 keep 的檔、lessons 檔與 Checkpoint 決策挑出該長期遵守的規範，你選定後寫進 CLAUDE.md 或 AGENTS.md 的 devlog-tracker 規範區塊。
---

這是使用者主動執行 `/devlog-tracker:promote` 時才做的事。**沒有使用者明確選擇就不寫入任何檔案。**

## 1. 取得來源與目標

記下你目前已經確認的專案根目錄絕對路徑（後面步驟都要用這個值，不要用 `$(pwd)` 重新推——理由同 `commands/continue.md` 步驟 1）。先決定 plugin 根目錄（有 `DEVLOG_TRACKER_ROOT` 用它；否則用 `CLAUDE_PLUGIN_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄），再跑：

```bash
PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
DEVLOG_PROJECT_DIR="<專案根目錄絕對路徑>" bash "${PLUGIN_ROOT}/core/scripts/promote-sources.sh"
DEVLOG_PROJECT_DIR="<專案根目錄絕對路徑>" bash "${PLUGIN_ROOT}/core/scripts/promote-target.sh"
```

- `NO_SOURCES`：告知目前沒有可以沉澱的來源（還沒 keep 過、沒有 lessons、也沒有 Checkpoint），可以先用 `/devlog-tracker:keep` 或開 Lessons Mode；結束。
- `FILE=<路徑> KIND=kept|lessons EXISTS=1`：要讀的檔。`EXISTS=0` 是索引還在但檔案已被刪掉，跳過，最後提一句。
- `CHECKPOINT=<檔案>:<行號>`：從該行的 `## Checkpoint` 標題往下讀到下一個 `## ` 標題為止，只看其中 `### 決策` 小節。
- `TARGET=<路徑>`：規則要寫進的檔。`EXISTING=<n>` 表示這個檔已經有 n 條沉澱過的規則。

## 2. 挑候選

用 Read 讀 `EXISTS=1` 的檔案、每個 Checkpoint 的 `### 決策`，以及 `TARGET` 檔（存在的話，看它整份內容，含 `<!-- devlog-tracker:rules:begin -->` 區塊內既有規則）。

挑出讀起來像「規則、之後應該一直遵守」的內容：

- 要：跨任務都成立的約定、踩過坑後定下的做法、明確的「不要做 X」。
- 不要：單次任務細節、已經被後續內容推翻或取代的決定、`TARGET` 檔裡已經寫了（不論在不在規範區塊裡）意思相同的規則。

每條候選寫成一行、可以直接放進 CLAUDE.md 的條列句，必要時附一句原因，結尾標出處：`（來源：<檔名>「<標題>」）`。找不到夠格的就說沒有，不硬湊。

在對話裡列出編號清單，並說明會寫進哪個檔（`TARGET`）。

## 3. 等使用者選

**停下來。** 請使用者回覆要寫入的編號（例如 `1,3`），也可以要求改寫某條。使用者沒有明確選擇（例如只說「看起來不錯」）時，再問一次要哪幾條；不要自己決定全寫。

## 4. 寫入

1. 用 Write 把選定（改寫過就用改寫版）的規則寫到 `<專案根目錄>/.devlog/.promote-rules.tmp`，一行一條。
2. 跑：

   ```bash
   DEVLOG_PROJECT_DIR="<專案根目錄絕對路徑>" bash "${PLUGIN_ROOT}/core/scripts/promote-write.sh" "<TARGET>" "<專案根目錄>/.devlog/.promote-rules.tmp"
   rm -f "<專案根目錄>/.devlog/.promote-rules.tmp"
   ```

3. 依輸出 `ADDED=<n> SKIPPED_DUP=<m> TARGET=<路徑>` 回報：寫入了幾條、幾條因為一字不差已存在而跳過、寫到哪個檔。提醒使用者這個檔要不要 commit 由他決定。

規範區塊只會被追加；要修改或刪除已寫入的規則，請使用者直接編輯該檔。`npx devlog-tracker init` 不會動這個區塊。
````

- [ ] **Step 3: `overview.md` 指向 `promote`**

`commands/overview.md` 步驟 2 第 2 點（「**可能該進 CLAUDE.md 的規範**：…找不到夠格的候選就不要輸出這一節、也不要硬湊。」）結尾接一句：

```
有輸出這一節時，最後補一句：要把其中幾條正式寫進 CLAUDE.md／AGENTS.md，可以執行 `/devlog-tracker:promote`（它會另外把 lessons 與 Checkpoint 決策也納入，並在你選定後才寫入）。
```

- [ ] **Step 4: 對照表與 README**

`cli/agents-md.js` 的 `codexBlock()`：把 `| 保存主題 / keep、接續具名檔 / resume、跨主題總覽 / overview | … |` 那列之後加：

```
| 沉澱規範寫進 CLAUDE.md／AGENTS.md / promote | \`commands/promote.md\` |
```

`cli/platforms/claude.js` 的 `claudeBlock()` 同位置加同一列。

`README.md` 指令表在 `/devlog-tracker:overview` 那列之後加：

```
| `/devlog-tracker:promote` | Picks rule candidates from kept files, lessons files and Checkpoint `### 決策` sections, lists them numbered, and — only for the ones you choose — appends them to a managed `<!-- devlog-tracker:rules:begin/end -->` block in `CLAUDE.md` (or `AGENTS.md` when `CLAUDE.md` is just `@AGENTS.md`, or on Codex-only projects). Append-only, exact duplicates skipped; `init` never rewrites this block. |
```

`README.zh-TW.md` 同位置：

```
| `/devlog-tracker:promote` | 從已 keep 的檔、lessons 檔與 Checkpoint 的 `### 決策` 挑出規範候選並編號列出；只有你選定的才追加到 `CLAUDE.md`（`CLAUDE.md` 只有 `@AGENTS.md` 或只裝 Codex 時改寫 `AGENTS.md`）的 `<!-- devlog-tracker:rules:begin/end -->` 受管區塊。只追加、一字不差的重複會跳過；`init` 不會覆寫這個區塊。 |
```

- [ ] **Step 5: 全部驗證**

Run:
```bash
shellcheck --external-sources --source-path=SCRIPTDIR -S warning \
  core/scripts/*.sh core/scripts/tests/*.sh cursor/hooks/*.sh codex/hooks/*.sh
bash core/scripts/run-tests.sh
npm test
```
Expected: 全過

- [ ] **Step 6: Commit**

```bash
git add commands/promote.md commands/overview.md core/scripts/tests/test-round-start.sh \
  cli/agents-md.js cli/platforms/claude.js README.md README.zh-TW.md
git commit -m "feat: /devlog-tracker:promote writes chosen rules into CLAUDE.md/AGENTS.md

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```
