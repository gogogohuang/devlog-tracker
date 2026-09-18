# CLAUDE.md

## 版號與發版

**一般 PR 不需要改版號。** 版號只在發版時改，由 `pnpm version` 統一處理，不要手動改下面這些檔案的版本字串：

- `package.json` → `"version"`（唯一的版本來源）
- `.claude-plugin/plugin.json` → `"version"`
- `.claude-plugin/marketplace.json` → `plugins[0].version`
- `README.md` → 開頭的 `**版本** X.Y.Z` 那行

後三個由 `scripts/sync-version.js` 依 `package.json` 自動同步（掛在 `package.json` 的 `"version"` lifecycle script，`pnpm version` 會執行它並把結果併進同一個版本 commit）。

版號規則（semver 精神，實際上幾乎都是 minor bump）：
- 新功能／行為變更 → `pnpm version minor`（`0.14.0` → `0.15.0`）
- 只有 bug fix／不影響行為的小補丁 → `pnpm version patch`

### 發版步驟

在乾淨的 `main` 上（工作區不能有未 commit 的變更）：

```bash
pnpm version minor            # 改四個檔案、產生 `0.X.Y` commit、打 `v0.X.Y` tag
git push --follow-tags        # 推 commit 與 tag
gh release create v0.X.Y --generate-notes   # 建 Release；這一步會觸發自動發版
```

Release 一建立（published），`.github/workflows/npm-publish.yml` 就會：檢查 tag 與四個檔案版本一致、跑 `npm test`、用 npm Trusted Publishing（OIDC，不存 token）發布到 npmjs。該版本已經在 npm 上時會直接跳過，不會報錯。

版本一致性可隨時檢查：`node scripts/sync-version.js --check`（加 `--tag vX.Y.Z` 會一併檢查 tag）。

### 注意

- Claude Code plugin marketplace 以 `plugin.json` 的版本判斷有沒有更新，所以使用者只會在發版時收到更新，合併 PR 本身不會。
- 第一次發布（`0.21.0`）npm 上還沒有這個套件，Trusted Publisher 必須綁在已存在的套件上，所以要手動 `npm login && npm publish`，再到 npmjs.com 註冊 Trusted Publisher（repo `gogogohuang/devlog-tracker`、workflow 檔名 `npm-publish.yml`），然後補打 tag：`git tag v0.21.0 && git push origin v0.21.0`，並建立對應的 Release。從下一版起就走上面的發版步驟。
