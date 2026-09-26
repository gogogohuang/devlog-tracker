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
- 有 `ROUNDS` 時，用 Read 讀 `DEVLOG_FILE` 全文，只看這些 Round（`ROUNDS` 是每個 `## Round` 標題的行號）。每個 Round 取 `### Summary`、`<decisions>`（舊格式 `#### 決策`）、`<files>`（舊格式 `#### 檔案`）、驗證紀錄（測試指令與結果，通常在 Summary、`<state>`（舊格式 `#### 現況`）或 `### 段落`）。**不要讀或引用 `### User Input`。**
- `NO_BRANCH_DEVLOG` 時只依 git log 與 diff 產生，並在對話裡說明「這個 branch 沒有 devlog 紀錄，描述只根據 commit 產生」。

## 3. 產生 PR body

語言跟使用者一致。四節固定，順序不變：

1. **Summary**：這個 branch 做了什麼，2–4 條，寫結果不寫過程。
2. **Decisions**：取自 Rounds 的 `<decisions>`（舊格式 `#### 決策`），只留最終版本；被後面 Round 推翻或改掉的不列。沒有就寫「無」。
3. **Changes**：依 commit 或檔案分組，每組一行說明。用 `<files>`（舊格式 `#### 檔案`）與 git log 交叉比對；兩邊對不上時以 git 為準。
4. **Test plan**：取自 Rounds 的驗證紀錄，列出實際跑過的指令與結果。沒有紀錄就寫「未記錄」——**不要捏造沒跑過的測試。**

專案的 CLAUDE.md／AGENTS.md 若規定 PR 描述結尾格式（例如署名行），照做；此外不要自己加簽名。

用 Write 寫到 `<專案根目錄>/.devlog/pr-body.md`（`.devlog/` 通常已被 gitignore，沒有的話別把它 commit），並在對話裡完整顯示內容。

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
