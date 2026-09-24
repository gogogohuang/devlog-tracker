# PR 描述產生器 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `/devlog-tracker:pr`：從目前 branch 的 devlog Rounds 與 `git log` 產生 PR body，寫到 `.devlog/pr-body.md`，使用者確認後才 `gh pr create`／`gh pr edit`。

**Architecture:** `pr-context.sh` 純讀取，輸出 `KEY=VALUE`（branch、base、devlog 檔、Round 行號、commit 數、`gh` 狀態、既有 PR 編號）；整理內容與對外動作由 `commands/pr.md` 指揮模型完成，照 `overview`／`search` 的「腳本抽資料、模型整理」分工。

**Tech Stack:** bash（macOS 3.2 相容）、git、選用 `gh`。

**Spec:** [`read-side-and-promote.md`](read-side-and-promote.md) §A

## Global Constraints

- 一般 PR 不改版號。
- `pr-context.sh` 只讀：對 `gh` 只呼叫 `gh auth status` 與 `gh pr view`，不建立、不修改任何東西。
- PR body 不貼 `User Input` 原文。
- 送出 `gh pr create`／`gh pr edit` 前一定停下來等使用者明確確認。
- `pr` **不**列入 `round-start.sh` 的 admin 清單（照常記 Round）。
- 驗證三步：shellcheck（同 AGENTS.md）、`bash core/scripts/run-tests.sh`、`npm test`。
- Commit 訊息結尾加 `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `core/scripts/pr-context.sh` | Create | 收集 PR 需要的 branch／base／devlog／gh 狀態 |
| `core/scripts/tests/test-pr-context.sh` | Create | 各種 repo 狀態的測試（`gh` 用假腳本） |
| `commands/pr.md` | Create | 指令文件：產生、確認、送出 |
| `core/scripts/tests/test-round-start.sh` | Modify | 確認 `pr` 不被豁免 |
| `cli/agents-md.js`、`cli/platforms/claude.js`、`README.md`、`README.zh-TW.md` | Modify | 對照表與指令表 |

## `pr-context.sh` 輸出契約

依序判斷，命中就印出該行並 exit 0：

| 條件 | 輸出 |
|---|---|
| 不是 git repo | `NOT_A_REPO` |
| detached HEAD | `DETACHED_HEAD` |
| 目前 branch 是 `main`／`master`（不分大小寫） | `ON_DEFAULT_BRANCH` |
| 找不到 base | `BRANCH=<b>` 後接 `NO_BASE` |

否則依序印：

```
BRANCH=<目前 branch>
BASE=<gh --base 用的 branch 名>
BASE_REF=<git log 用的 ref>
DEVLOG_FILE=<絕對路徑>
ROUNDS=<空白分隔的 Round 起始行號>   或   NO_BRANCH_DEVLOG
COMMITS=<git rev-list --count BASE_REF..HEAD>
GH=yes|no
PR=<number>|none
```

Base 決定：`refs/remotes/origin/HEAD` 存在 → `BASE` 為去掉 `origin/` 的名稱、`BASE_REF=origin/<name>`；否則依序試本地 `main`、`master` → `BASE=BASE_REF=<name>`。

---

### Task 1: `pr-context.sh`

**Files:**
- Create: `core/scripts/pr-context.sh`
- Test: `core/scripts/tests/test-pr-context.sh`

**Interfaces:**
- Consumes: `devlog_resolve_paths`、`devlog_list_round_starts`。
- Produces: 上面的輸出契約（Task 2 的 `commands/pr.md` 依賴每個鍵名）。

- [ ] **Step 1: 寫失敗測試**

Create `core/scripts/tests/test-pr-context.sh`：

```bash
#!/usr/bin/env bash
# Self-check for pr-context.sh (docs/design/read-side-and-promote.md A).
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

# gh stubs: one that is not logged in, one that is and has PR #42.
GH_OFF="$TMP_ROOT/gh-off"; GH_ON="$TMP_ROOT/gh-on"
mkdir -p "$GH_OFF" "$GH_ON"
printf '#!/usr/bin/env bash\nexit 1\n' > "$GH_OFF/gh"
cat > "$GH_ON/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "auth status") exit 0 ;;
  "pr view") echo 42 ;;
  *) echo "unexpected gh call: $*" >&2; exit 9 ;;
esac
EOF
chmod +x "$GH_OFF/gh" "$GH_ON/gh"
ctx() { PATH="$1:$PATH" CLAUDE_PROJECT_DIR="$2" bash "$SCRIPT_DIR/pr-context.sh"; }

# --- Not a git repo -------------------------------------------------------------
PLAIN="$TMP_ROOT/plain"; mkdir -p "$PLAIN"
assert_eq "not a repo" "NOT_A_REPO" "$(ctx "$GH_OFF" "$PLAIN")"

# --- Repo fixture ------------------------------------------------------------------
REPO="$TMP_ROOT/repo"; mkdir -p "$REPO"
gitc() { git -C "$REPO" -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false "$@"; }
gitc init -q -b main
echo a > "$REPO/a.txt"; gitc add a.txt; gitc commit -qm init

assert_eq "on main" "ON_DEFAULT_BRANCH" "$(ctx "$GH_OFF" "$REPO")"
gitc checkout -q -b MASTER
assert_eq "on MASTER (case-insensitive)" "ON_DEFAULT_BRANCH" "$(ctx "$GH_OFF" "$REPO")"
gitc checkout -q main
gitc checkout -q --detach
assert_eq "detached" "DETACHED_HEAD" "$(ctx "$GH_OFF" "$REPO")"
gitc checkout -q main

# --- Feature branch, no devlog, gh logged out --------------------------------------
gitc checkout -q -b feat/x
echo b > "$REPO/b.txt"; gitc add b.txt; gitc commit -qm "feat: b"
OUT="$(ctx "$GH_OFF" "$REPO")"
assert_line "branch" "BRANCH=feat/x" "$OUT"
assert_line "base from local main" "BASE=main" "$OUT"
assert_line "base ref" "BASE_REF=main" "$OUT"
assert_line "devlog file is branch-scoped + absolute" "DEVLOG_FILE=$(cd "$REPO" && pwd)/.devlog/devlog.feat-x.md" "$OUT"
assert_line "no branch devlog" "NO_BRANCH_DEVLOG" "$OUT"
assert_line "commit count" "COMMITS=1" "$OUT"
assert_line "gh logged out" "GH=no" "$OUT"
assert_line "no pr" "PR=none" "$OUT"

# --- Branch devlog with rounds + gh logged in -------------------------------------
mkdir -p "$REPO/.devlog"
cat > "$REPO/.devlog/devlog.feat-x.md" <<'EOF'
## Round 1 — 2026-09-01T10:00:00+0800

### Summary
one

### Status
DONE

## Round 2 — 2026-09-02T10:00:00+0800

### Summary
two

### Status
DONE
EOF
OUT="$(ctx "$GH_ON" "$REPO")"
assert_line "round start lines" "ROUNDS=1 9" "$OUT"
assert_line "gh logged in" "GH=yes" "$OUT"
assert_line "existing pr number" "PR=42" "$OUT"

# --- origin/HEAD wins over local main ---------------------------------------------
gitc update-ref refs/remotes/origin/main main
gitc symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
OUT="$(ctx "$GH_OFF" "$REPO")"
assert_line "base from origin/HEAD" "BASE=main" "$OUT"
assert_line "base ref is remote" "BASE_REF=origin/main" "$OUT"

# --- No main/master and no origin/HEAD -> NO_BASE ------------------------------
REPO2="$TMP_ROOT/repo2"; mkdir -p "$REPO2"
git -C "$REPO2" -c user.email=t@example.com -c user.name=t init -q -b trunk
echo a > "$REPO2/a.txt"; git -C "$REPO2" add a.txt
git -C "$REPO2" -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false commit -qm init
git -C "$REPO2" checkout -q -b dev
OUT="$(ctx "$GH_OFF" "$REPO2")"
assert_line "no base: branch still printed" "BRANCH=dev" "$OUT"
assert_line "no base" "NO_BASE" "$OUT"

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `bash core/scripts/tests/test-pr-context.sh`
Expected: `FAIL`（`pr-context.sh: No such file or directory`）

- [ ] **Step 3: 實作 `core/scripts/pr-context.sh`**

```bash
#!/usr/bin/env bash
# Context for /devlog-tracker:pr (docs/design/read-side-and-promote.md A).
# Plain read only: git is only queried, and gh is only asked `auth status`
# and `pr view` -- creating/editing the PR is the command doc's job, after
# the user confirms.
set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=devlog-md.sh
. "$SCRIPT_DIR/devlog-md.sh"
# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"

PROJECT_DIR="$(cd "${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}" 2>/dev/null && pwd)" || { echo "NOT_A_REPO"; exit 0; }
git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1 || { echo "NOT_A_REPO"; exit 0; }

BRANCH="$(git -C "$PROJECT_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || echo '')"
case "$BRANCH" in
  '') echo "DETACHED_HEAD"; exit 0 ;;
  [Mm][Aa][Ii][Nn]|[Mm][Aa][Ss][Tt][Ee][Rr]) echo "ON_DEFAULT_BRANCH"; exit 0 ;;
esac

BASE=""
BASE_REF=""
ORIGIN_HEAD="$(git -C "$PROJECT_DIR" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo '')"
if [ -n "$ORIGIN_HEAD" ]; then
  BASE="${ORIGIN_HEAD#origin/}"
  BASE_REF="$ORIGIN_HEAD"
else
  for candidate in main master; do
    if git -C "$PROJECT_DIR" rev-parse --verify --quiet "refs/heads/$candidate" >/dev/null; then
      BASE="$candidate"
      BASE_REF="$candidate"
      break
    fi
  done
fi

echo "BRANCH=$BRANCH"
[ -n "$BASE" ] || { echo "NO_BASE"; exit 0; }
echo "BASE=$BASE"
echo "BASE_REF=$BASE_REF"

devlog_resolve_paths "$PROJECT_DIR"
echo "DEVLOG_FILE=$DEVLOG_FILE"
ROUNDS=""
if [ -f "$DEVLOG_FILE" ]; then
  ROUNDS="$(devlog_list_round_starts "$DEVLOG_FILE" | awk '{ printf "%s%s", (n++ ? " " : ""), $1 }')"
fi
if [ -n "$ROUNDS" ]; then echo "ROUNDS=$ROUNDS"; else echo "NO_BRANCH_DEVLOG"; fi

COMMITS="$(git -C "$PROJECT_DIR" rev-list --count "$BASE_REF..HEAD" 2>/dev/null || echo 0)"
echo "COMMITS=$COMMITS"

GH=no
PR=none
if command -v gh >/dev/null 2>&1 && (cd "$PROJECT_DIR" && gh auth status >/dev/null 2>&1); then
  GH=yes
  n="$(cd "$PROJECT_DIR" && gh pr view --json number -q .number 2>/dev/null || echo '')"
  case "$n" in ''|*[!0-9]*) ;; *) PR="$n" ;; esac
fi
echo "GH=$GH"
echo "PR=$PR"
```

`chmod +x core/scripts/pr-context.sh`

- [ ] **Step 4: 跑測試確認通過**

Run: `bash core/scripts/tests/test-pr-context.sh && shellcheck --external-sources --source-path=SCRIPTDIR -S warning core/scripts/pr-context.sh core/scripts/tests/test-pr-context.sh`
Expected: `All checks passed.`，shellcheck 無輸出

- [ ] **Step 5: Commit**

```bash
git add core/scripts/pr-context.sh core/scripts/tests/test-pr-context.sh
git commit -m "feat: add pr-context.sh for /devlog-tracker:pr

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `/devlog-tracker:pr` 指令與文件

**Files:**
- Create: `commands/pr.md`
- Modify: `core/scripts/tests/test-round-start.sh`（section 21 之後）
- Modify: `cli/agents-md.js`、`cli/platforms/claude.js`、`README.md`、`README.zh-TW.md`

**Interfaces:**
- Consumes: `pr-context.sh` 輸出契約（Task 1）。

- [ ] **Step 1: 寫測試（`pr` 不被豁免）**

在 `core/scripts/tests/test-round-start.sh` section 21 的最後一行 `rm -f …` 之後插入：

```bash
# --- 21b: /devlog-tracker:pr and :promote are NOT exempt (outward / file writes)
for WORK_CMD in pr; do
  rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open" "$DEVLOG_DIR/.turn-start" "$DEVLOG_DIR/.round-current.md"
  printf '{"prompt":"<command-name>/devlog-tracker:%s</command-name>"}' "$WORK_CMD" | bash "$SCRIPT_DIR/round-start.sh"
  CUR_BODY="$(cat "$DEVLOG_DIR/.round-current.md" 2>/dev/null || echo '')"
  assert_contains "$WORK_CMD command still opens a Round" "## Round 1 —" "$CUR_BODY"
done
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open" "$DEVLOG_DIR/.turn-start" "$DEVLOG_DIR/.round-current.md"
```

（`promote-plan.md` 會把 `for WORK_CMD in pr` 改成 `in pr promote`。）

Run: `bash core/scripts/tests/test-round-start.sh 2>&1 | grep 'pr command'`
Expected: `PASS: pr command still opens a Round`（這是守護測試：確保之後沒人誤把 `pr` 加進 admin 清單）

建立 `commands/pr.md` 後，`npm test` 的 `cli/agents-md.test.js`「block mentions every command doc」會失敗，Step 3 修正。

- [ ] **Step 2: 建立 `commands/pr.md`**

````markdown
---
description: 從這個 branch 的 devlog 與 git log 產生 PR 描述，寫到 .devlog/pr-body.md；使用者確認後才用 gh 建立或更新 PR。
---

這是使用者主動執行 `/devlog-tracker:pr` 時才做的事。產生草稿是純讀取；**建立或更新 PR 是對外動作，一定要等使用者明確確認才做。**

## 1. 取得 context

記下你目前已經確認的專案根目錄絕對路徑（後面步驟都要用這個值，不要用 `$(pwd)` 重新推——理由同 `commands/continue.md` 步驟 1）。先決定 plugin 根目錄（有 `DEVLOG_TRACKER_ROOT` 用它；否則用 `CLAUDE_PLUGIN_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄），再跑：

```bash
PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
DEVLOG_PROJECT_DIR="<剛才記下的專案根目錄絕對路徑>" bash "${PLUGIN_ROOT}/core/scripts/pr-context.sh"
```

- `NOT_A_REPO`：告知這不是 git repo，結束。
- `DETACHED_HEAD`：告知目前是 detached HEAD，先切到要開 PR 的 branch，結束。
- `ON_DEFAULT_BRANCH`：告知目前在 `main`／`master`，PR 要從 feature branch 開，結束。不要猜範圍。
- `NO_BASE`：告知找不到 base branch（沒有 `origin/HEAD`、也沒有本地 `main`／`master`），請使用者告訴你 base 名稱後再手動用 `git log <base>..HEAD` 繼續；結束這個流程。
- 其他：記下 `BRANCH`、`BASE`、`BASE_REF`、`DEVLOG_FILE`、`ROUNDS`（或 `NO_BRANCH_DEVLOG`）、`COMMITS`、`GH`、`PR`。

`COMMITS=0` 時告知這個 branch 相對 `BASE` 沒有 commit，問使用者是否仍要繼續。

## 2. 讀資料

- 跑 `git log --reverse --format='%h %s%n%b' <BASE_REF>..HEAD` 與 `git diff --stat <BASE_REF>...HEAD`。
- 有 `ROUNDS` 時，用 Read 讀 `DEVLOG_FILE` 全文，只看這些 Round（`ROUNDS` 是每個 `## Round` 標題的行號）。每個 Round 取 `### Summary`、`#### 決策`、`#### 檔案`、驗證紀錄（測試指令與結果，通常在 Summary、`#### 現況` 或 `### 段落`）。**不要讀或引用 `### User Input`。**
- `NO_BRANCH_DEVLOG` 時只依 git log 與 diff 產生，並在對話裡說明「這個 branch 沒有 devlog 紀錄，描述只根據 commit 產生」。

## 3. 產生 PR body

語言跟使用者一致。四節固定，順序不變：

1. **Summary**：這個 branch 做了什麼，2–4 條，寫結果不寫過程。
2. **Decisions**：取自 Rounds 的 `#### 決策`，只留最終版本；被後面 Round 推翻或改掉的不列。沒有就寫「無」。
3. **Changes**：依 commit 或檔案分組，每組一行說明。用 `#### 檔案` 與 git log 交叉比對；兩邊對不上時以 git 為準。
4. **Test plan**：取自 Rounds 的驗證紀錄，列出實際跑過的指令與結果。沒有紀錄就寫「未記錄」——**不要捏造沒跑過的測試。**

專案的 CLAUDE.md／AGENTS.md 若規定 PR 描述結尾格式（例如署名行），照做；此外不要自己加簽名。

用 Write 寫到 `<專案根目錄>/.devlog/pr-body.md`（`.devlog/` 已被 gitignore），並在對話裡完整顯示內容。

## 4. 等確認，再送出

**停下來。** 問使用者要不要送出，並說明接下來會做什麼：

- `GH=no`：告知 `gh` 未安裝或未登入，草稿在 `.devlog/pr-body.md`，可以自己貼上；結束。
- `PR=none`：提議一個 PR 標題（conventional commit 風格，跟這個 repo 既有 commit 一致），等使用者確認標題與內容後才跑：

  ```bash
  gh pr create --base "<BASE>" --title "<確認過的標題>" --body-file "<專案根目錄>/.devlog/pr-body.md"
  ```

  branch 還沒 push 時，`gh` 會提示；先問使用者要不要 `git push -u origin <BRANCH>`，不要自己推。
- `PR=<n>`：提醒「會覆寫 PR #<n> 目前的描述（包含別人手改的內容）」，確認後才跑：

  ```bash
  gh pr edit <n> --body-file "<專案根目錄>/.devlog/pr-body.md"
  ```

使用者要求修改時，改 `.devlog/pr-body.md` 後再顯示一次、再等確認。送出後回報 PR 網址。
````

- [ ] **Step 3: 對照表與 README**

`cli/agents-md.js` 的 `codexBlock()` 與 `cli/platforms/claude.js` 的 `claudeBlock()`，在 report／timeline 那列之後加：

```
| 產生 PR 描述 / pr | \`commands/pr.md\` |
```

`README.md` 指令表在 `/devlog-tracker:timeline` 那列之後加：

```
| `/devlog-tracker:pr` | Drafts a PR description from this branch's devlog Rounds plus `git log` (Summary / Decisions / Changes / Test plan; no User Input text), writes it to `.devlog/pr-body.md`, and — only after you confirm — runs `gh pr create` or `gh pr edit`. Refuses on `main`/`master`. |
```

`README.zh-TW.md` 同位置：

```
| `/devlog-tracker:pr` | 從這個 branch 的 devlog Rounds 與 `git log` 產生 PR 描述（Summary／Decisions／Changes／Test plan，不含 User Input 原文），寫到 `.devlog/pr-body.md`；你確認後才跑 `gh pr create` 或 `gh pr edit`。在 `main`／`master` 上不執行。 |
```

- [ ] **Step 4: 全部驗證**

Run:
```bash
shellcheck --external-sources --source-path=SCRIPTDIR -S warning \
  core/scripts/*.sh core/scripts/tests/*.sh cursor/hooks/*.sh codex/hooks/*.sh
bash core/scripts/run-tests.sh
npm test
```
Expected: 全過

- [ ] **Step 5: Commit**

```bash
git add commands/pr.md core/scripts/tests/test-round-start.sh cli/agents-md.js cli/platforms/claude.js README.md README.zh-TW.md
git commit -m "feat: /devlog-tracker:pr drafts PR descriptions from the devlog

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```
