# Contract checklist（審核／改版用）

本檔展開 `SKILL.md` 頂部的 **Contract** 七維。runtime 以 `SKILL.md` 為準；
這裡只做「條目 ↔ 權威段落／腳本」對照，方便審核與改版，避免在多處重抄規則。

改行為時：先改權威段落或腳本，再確認本表 pointer 仍對；不要只改本檔。

## Requirements

| 條件 | 權威位置 |
|---|---|
| 強制記錄開關 `.enabled`；未 start 不動作 | `SKILL.md`「用 `/devlog-tracker:start`…」；`commands/start.md`／`pause.md` |
| `/clear` 不注入、不自動接續 | `SKILL.md`「自動接續與 `/clear`」；`commands/continue.md` |
| continue／明確接續才開工；start 只對進度 | `commands/continue.md`；`SKILL.md`「接續：…」 |
| Cursor／Codex 無 slash → `commands/*.md` | `SKILL.md`「檔案位置」 |

## Output contracts

| 產出 | 權威位置 |
|---|---|
| Round 骨架：User Input + Summary + Reply + Handoff + Status | `SKILL.md`「每一輪的紀錄格式」 |
| Handoff／Session Handoff 用 XML 標籤（`<decisions>`／`<files>`／…；舊格式 `#### 決策`／`#### 檔案`／…） | `SKILL.md`「每一輪的紀錄格式」；`core/scripts/handoff-fields.sh`；`docs/design/handoff-xml.md` |
| Handoff 標籤順序與可省略規則 | 同上（寫入原則） |
| 工作區（`<workspace>`；舊格式 `#### 工作區`）七種格式 | 同上；生產者 `core/scripts/workspace-snapshot.sh` |
| 檔案（`<files>`；舊格式 `#### 檔案`）machine-verify 區塊 | 同上；`docs/design/files-verify.md`；`core/scripts/files-snapshot.sh` |
| Checkpoint 三段 | `references/checkpoint-mode.md` |
| Session Handoff 三段（揮發快照） | `docs/design/session-handoff-file.md`；`SKILL.md` 格式節 |
| `### 段落` 格式 | `references/round-segments.md`；Reply Fold 見 `references/reply-fold.md` |

## Invariants

| 不變式 | 權威位置 |
|---|---|
| L1：接手必須同輪寫回 | `SKILL.md`「L1 寫回義務」；`commands/continue.md` 步驟 6 |
| 聊天不旁白記錄動作／不提 Round 欄位名 | `SKILL.md`「寫進 devlog 不等於講給使用者聽」 |
| 不改 User Input（除 hook 占位） | `SKILL.md` 寫入原則 |
| 同一則使用者訊息不另開 `## Round` | `SKILL.md` 強制流程步驟 2 |
| 編輯對象是 `.round-current.md`（開著時） | `SKILL.md`「檔案位置」；`docs/design/round-current-split.md` |
| Lessons ≠ 架構知識庫；設計在 `docs/design/` | `SKILL.md`「Lessons Mode」；`references/lessons-mode.md` |
| `INTERRUPTED` 只由 hook 寫 | `SKILL.md` Status 規則 |

## Validation

| 層級 | 誰執行 | 權威位置 |
|---|---|---|
| Soft（agent 自檢） | 收尾前對照格式／完成條件／下一步 | `SKILL.md` 寫入原則與瑣碎度表 |
| Hard：缺 Summary／Reply／Handoff／非法 Status | Stop `enforce-devlog.sh` | `SKILL.md` 格式節末段 |
| Hard：工作區快照不符 | Stop + `workspace-snapshot.sh` | 同上；ssot Phase 1 |
| Hard：檔案區塊不符 | Stop + `files-snapshot.sh` | `docs/design/files-verify.md` |
| Hard：Session Handoff（IN_PROGRESS／BLOCKED） | Stop + `handoff-file.sh` | `docs/design/session-handoff-file.md`；`SKILL.md` 格式節 |
| Hard：上一輪工作區漂移擋工具 | PreToolUse（continue 同 session） | `SKILL.md`「接續」；`commands/continue.md` |
| Hard：Segment Watch 逾時先補段落 | PreToolUse | `references/round-segments.md` |
| Soft：Checkpoint／Lessons 建議 | hook 提示，不強制寫入本身 | `references/checkpoint-mode.md`／`lessons-mode.md` |
| fail-open／loop guard | hook 穩健性 | `core/scripts/enforce-devlog.sh` 開頭註解 |

## Transformation

| 意圖 | 步驟檔 |
|---|---|
| 開強制記錄 | `commands/start.md` |
| 接續上一題 | `commands/continue.md` |
| 暫停／狀態／壓縮／清空 | `commands/pause.md`／`status.md`／`compact.md`／`clean.md` |
| 具名保存／接續／總覽 | `commands/keep.md`／`resume.md`／`overview.md` |
| 整理所有 devlog（跨分支檔、archive、既有 keep 檔） | `commands/keep-all.md` |
| Span／Checkpoint／Segment／Lessons | `commands/span.md`／`checkpoint.md`／`segment-watch.md`／`lessons*.md` |
| 協定與跨指令行為 | `SKILL.md`（本層不重抄步驟） |

## Knowledge

| 主題 | 權威位置 |
|---|---|
| 主檔／分支檔／歸檔／keep／round-current／handoff | `SKILL.md`「檔案位置」；`docs/design/branch-scoped-devlog.md`；`docs/design/session-handoff-file.md` |
| 錄製時機與截斷 | `docs/design/recording-moments.md` |
| Span／Checkpoint／Lessons／Reply Fold／Segments | 各 `references/*.md` + 對應 `docs/design/*` |
| 下一步黑名單 | `docs/design/next-step-blacklist.md` |

## Observation

| 時機 | 該看什麼 | 權威位置 |
|---|---|---|
| 收尾前 | live git → 寫／核對「工作區」；完成條件能否 DONE | `SKILL.md` 工作區／完成條件；`workspace-snapshot.sh` |
| 接手（continue／resume／注入後開工） | 歷史 Round Status、「工作區」vs 實際樹、「下一步」 | `commands/continue.md` 步驟 5；`resume.md` |
| 長輪中途 | 是否有意義階段結果 → `### 段落` | `references/round-segments.md`；瑣碎度表 |
| BLOCKED | 缺件是否已出現（可觀察條件，不是 git 相符） | `SKILL.md`／`commands/continue.md` |
| 使用者只問進度 | 讀檔回答；仍可寫回但不旁白 | `SKILL.md` 旁白例外 |
