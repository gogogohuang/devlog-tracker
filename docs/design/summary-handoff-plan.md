# Summary + Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split each Round into a human `### Summary` and an AI `### Handoff`, and have the Stop hook block a turn whose last Round is missing either heading.

**Architecture:** Authoring rules live in `skills/devlog-tracker/SKILL.md`. Enforcement is a presence-only heading check in `enforce-devlog.sh`, inserted after the existing content-hash pass and before span-tick reset / checkpoint logic. Tests stay in the existing assert-and-exit script; no new files, no new languages.

**Tech Stack:** bash (`enforce-devlog.sh`, `test-enforce-devlog.sh`), awk for last-Round extraction, markdown for skill/README/commands.

## Global Constraints

- Spec: `docs/design/summary-handoff.md`. Do not invent extra hook checks (no subsection headings, no non-empty bodies, no Status/`下一步` consistency).
- Last Round block = from the last line matching `^## Round ` through the line before the next `^## ` heading, or EOF. A trailing `## Checkpoint` is not part of the Round.
- Required headings on that block: a line starting with `### Summary` and a line starting with `### Handoff`. Presence only.
- No `## Round ` found after a hash-changing write: fail-open (do not block).
- Check order: loop guard → enabled → span under-budget pass → hash comparison → **heading check** → span tick reset → checkpoint check. A heading-check failure must not reset `ticks_since_checkin`.
- Status remains `DONE | IN_PROGRESS | BLOCKED` only. Next-step sentence lives in Handoff `#### 下一步`, not under Status.
- Handoff subsection order and labels: `決策` → `檔案` → `現況` → `下一步`. Omit a subsection that did not occur; do not write 「無」.
- Do not migrate historical `### Response` rounds. Do not change `session-start-devlog.sh`, `round-start.sh`, or compact retain/move rules.
- `commands/compact.md` currently has no three-field Round phrase — leave it unchanged.
- This repo gitignores `docs/superpowers/`. Plans and specs live under `docs/design/`.

## File Structure

| File | Responsibility |
|---|---|
| `hooks/scripts/enforce-devlog.sh` | Hash check, then last-Round heading check, then span reset, then checkpoint |
| `hooks/scripts/test-enforce-devlog.sh` | Self-check for the above, including new heading scenarios and existing fixtures that must now carry both headings to pass |
| `skills/devlog-tracker/SKILL.md` | What Claude writes each round |
| `README.md` | User-facing format blurb + directory tree |
| `commands/start.md` | Round-shape phrase in the start instructions |
| `docs/design/span-mode.md` | One-line closeout wording (`Response` → Handoff) |
| `docs/design/checkpoint-mode.md` | Segment example closing on Summary/Handoff instead of Response |

Do not create new scripts. Do not bump plugin version.

---

### Task 1: Stop-hook heading check

**Files:**
- Modify: `hooks/scripts/test-enforce-devlog.sh`
- Modify: `hooks/scripts/enforce-devlog.sh` (hash-miss message around line 88; insert heading check between the hash-pass / span-reset block at lines 87–97 and the checkpoint block at line 99)
- Test: `bash hooks/scripts/test-enforce-devlog.sh`

**Interfaces:**
- Consumes: existing `CLAUDE_PROJECT_DIR`, `.enabled`, `.turn-start` hash marker, `devlog.md`, `.span-open`, `.checkpoint-state`.
- Produces: hash-miss stderr phrase `User Input / Summary / Handoff / Status`; heading-miss stderr phrase `最後一個 Round 缺少 \`### Summary\` 或 \`### Handoff\``; exit 2 when the last Round block lacks either heading; exit 0 when both are present, when no `## Round ` exists after a write, or when a Checkpoint after a complete last Round is the only new content.

- [ ] **Step 1: Add a fixture helper and the new heading-check tests**

In `hooks/scripts/test-enforce-devlog.sh`, immediately after the `assert_exit` function (after its closing `}`), add:

```bash
append_minimal_round() {
  local n="$1" ts="$2"
  cat >> "$DEVLOG_DIR/devlog.md" <<EOF
## Round ${n} — ${ts}

### Summary
fixture

### Handoff
#### 現況
fixture

### Status
DONE
EOF
}
```

Do not yet replace the existing `echo "## Round ..."` writes. Then, immediately before the final `if [ "$FAIL" -eq 0 ]; then` block (currently around line 250), append the following scenarios. They must run after Checkpoint Scenario 6, and they start by wiping span/checkpoint state so leftover counters cannot mask heading results.

```bash
# --- Heading check: reset span/checkpoint so only hash + headings matter --
rm -f "$DEVLOG_DIR/.span-open" "$DEVLOG_DIR/.checkpoint-state"

# --- Heading Scenario 1: hash miss message names Summary / Handoff --------
cat > "$DEVLOG_DIR/devlog.md" <<'DEVEOF'
## Round 1 — 2026-09-09T10:00:00+08:00

### Summary
prior

### Handoff
#### 現況
prior

### Status
DONE
DEVEOF
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
HASH_MISS_MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "no write this round -> blocked (heading tests setup)" 2 $?
case "$HASH_MISS_MSG" in
  *"User Input / Summary / Handoff / Status"*) echo "PASS: hash-miss message names Summary / Handoff" ;;
  *) echo "FAIL: hash-miss message should name User Input / Summary / Handoff / Status, got: $HASH_MISS_MSG"; FAIL=1 ;;
esac
case "$HASH_MISS_MSG" in
  *"User Input / Response / Status"*) echo "FAIL: hash-miss message still names Response"; FAIL=1 ;;
  *) echo "PASS: hash-miss message no longer names Response" ;;
esac

# --- Heading Scenario 2: Round written without ### Summary -> blocked -----
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat >> "$DEVLOG_DIR/devlog.md" <<'DEVEOF'
## Round 2 — 2026-09-09T10:05:00+08:00

### Handoff
#### 現況
missing summary

### Status
DONE
DEVEOF
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "last Round missing ### Summary -> blocked" 2 $?

# --- Heading Scenario 3: Round written without ### Handoff -> blocked -----
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat >> "$DEVLOG_DIR/devlog.md" <<'DEVEOF'
## Round 3 — 2026-09-09T10:10:00+08:00

### Summary
missing handoff

### Status
DONE
DEVEOF
HEADING_MISS_MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "last Round missing ### Handoff -> blocked" 2 $?
case "$HEADING_MISS_MSG" in
  *'### Summary'*'### Handoff'*) echo "PASS: heading-miss message names both required headings" ;;
  *) echo "FAIL: heading-miss message should mention ### Summary and ### Handoff, got: $HEADING_MISS_MSG"; FAIL=1 ;;
esac

# --- Heading Scenario 4: both headings present, empty bodies -> allowed ---
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat >> "$DEVLOG_DIR/devlog.md" <<'DEVEOF'
## Round 4 — 2026-09-09T10:15:00+08:00

### Summary
### Handoff
### Status
DONE
DEVEOF
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "both headings present with empty bodies -> allowed" 0 $?

# --- Heading Scenario 5: hash changed, no ## Round heading -> fail-open ---
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
printf '%s\n' "just a note, not a round" > "$DEVLOG_DIR/devlog.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "write with no ## Round heading -> fail-open (allowed)" 0 $?

# --- Heading Scenario 6: Checkpoint text must not satisfy headings --------
# Last Round lacks both headings; a following Checkpoint quotes them.
# Extraction stops at the next ^##  line, so this must still block.
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat > "$DEVLOG_DIR/devlog.md" <<'DEVEOF'
## Round 5 — 2026-09-09T10:20:00+08:00
old response blob

## Checkpoint（Round 5 摘要）
### Summary
quoted
### Handoff
quoted
DEVEOF
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "headings only inside Checkpoint, last Round missing them -> blocked" 2 $?

# --- Heading Scenario 7: Checkpoint-only append on a complete last Round --
cat > "$DEVLOG_DIR/devlog.md" <<'DEVEOF'
## Round 6 — 2026-09-09T10:25:00+08:00

### Summary
complete

### Handoff
#### 現況
complete

### Status
DONE
DEVEOF
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
echo "## Checkpoint（Round 6 摘要）" >> "$DEVLOG_DIR/devlog.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "Checkpoint-only append after a complete last Round -> allowed" 0 $?

# --- Heading Scenario 8: span one-liner on a complete last Round ----------
# ticks at max so we do not silent-pass; a one-line append must still pass
# heading check because it lands inside the last Round, which already has
# both headings.
cat > "$DEVLOG_DIR/devlog.md" <<'DEVEOF'
## Round 6 — 2026-09-09T10:25:00+08:00

### Summary
complete

### Handoff
#### 現況
complete

### Status
DONE
DEVEOF
cat > "$DEVLOG_DIR/.span-open" <<'SPANEOF'
{
  "round": 6,
  "opened_at": "2026-09-09T10:25:00+08:00",
  "ticks_since_checkin": 5,
  "max_silent_ticks": 5
}
SPANEOF
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
echo "span check-in: still looping" >> "$DEVLOG_DIR/devlog.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "span budget expired, one-line append on complete last Round -> allowed" 0 $?
SPAN_TICKS_ONELINE="$(grep -o '"ticks_since_checkin"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.span-open" | grep -o '[0-9]\+$')"
if [ "$SPAN_TICKS_ONELINE" = "0" ]; then
  echo "PASS: span ticks reset after one-line append that passed heading check"
else
  echo "FAIL: ticks_since_checkin should reset to 0 after passing write, got '$SPAN_TICKS_ONELINE'"
  FAIL=1
fi

# --- Heading Scenario 9: heading miss must not reset span ticks -----------
cat > "$DEVLOG_DIR/.span-open" <<'SPANEOF'
{
  "round": 6,
  "opened_at": "2026-09-09T10:25:00+08:00",
  "ticks_since_checkin": 5,
  "max_silent_ticks": 5
}
SPANEOF
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat >> "$DEVLOG_DIR/devlog.md" <<'DEVEOF'
## Round 7 — 2026-09-09T10:30:00+08:00
incomplete new round
DEVEOF
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "span at max, new Round missing headings -> blocked" 2 $?
SPAN_TICKS_HELD="$(grep -o '"ticks_since_checkin"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.span-open" | grep -o '[0-9]\+$')"
if [ "$SPAN_TICKS_HELD" = "6" ]; then
  echo "PASS: heading-check failure did not reset ticks_since_checkin (stayed at 6 after round-start increment)"
else
  echo "FAIL: ticks_since_checkin should stay 6 (5 + round-start increment, not reset), got '$SPAN_TICKS_HELD'"
  FAIL=1
fi
rm -f "$DEVLOG_DIR/.span-open"
```

- [ ] **Step 2: Run tests and confirm the new heading scenarios fail**

Run: `bash hooks/scripts/test-enforce-devlog.sh`

Expected: existing scenarios still PASS (current hook only checks hash). New Heading Scenario 1 fails the message assertions (current stderr is `User Input / Response / Status`). Heading Scenarios 2, 3, 6, 9 fail their exit-code assertions (current hook exits 0 after any hash change). Heading Scenarios 4, 5, 7, 8 already exit 0 and may PASS. Script ends with `Some checks FAILED.` and exit 1.

If every new scenario already PASSes, stop — the tests are not actually covering the spec.

- [ ] **Step 3: Implement heading check and update the hash-miss message**

In `hooks/scripts/enforce-devlog.sh`, replace the hash-miss echo (the line that currently names `User Input / Response / Status`) with:

```bash
  echo "這一輪還沒有寫進 .devlog/devlog.md。請依 skills/devlog-tracker/SKILL.md 的格式，在檔案尾端補上這一輪的 \`## Round <N>\`（User Input / Summary / Handoff / Status），寫完再結束這一輪。" >&2
```

Then insert the heading check **after** that `if`/`fi` hash-miss block and **before** the existing span-tick reset (`if [ "$SPAN_VALID" -eq 1 ]; then`). Use this block verbatim:

```bash
# --- 標題檢查（Summary + Handoff）-----------------------------------------
# 雜湊已經證明這輪有寫入。接著取出最後一個 Round 區塊：從最後一個
# 「## Round 」行起到下一條「## 」標題之前（或 EOF）。這個區塊必須同時有
# 以 ### Summary、### Handoff 開頭的行。只驗標題存在，不驗內容。
# 解析不到任何 ## Round：fail-open（不擋），避免把「寫了但不是 Round」
# 變成新的卡死理由。
LAST_ROUND="$(awk '
  /^## Round / { start = NR }
  { lines[NR] = $0 }
  END {
    if (start == 0) exit 0
    end = NR
    for (i = start + 1; i <= NR; i++) {
      if (lines[i] ~ /^## /) { end = i - 1; break }
    }
    for (i = start; i <= end; i++) print lines[i]
  }
' "$DEVLOG_FILE" 2>/dev/null || true)"
if [ -n "$LAST_ROUND" ]; then
  HAS_SUMMARY=0
  HAS_HANDOFF=0
  printf '%s\n' "$LAST_ROUND" | grep -q '^### Summary' && HAS_SUMMARY=1
  printf '%s\n' "$LAST_ROUND" | grep -q '^### Handoff' && HAS_HANDOFF=1
  if [ "$HAS_SUMMARY" -eq 0 ] || [ "$HAS_HANDOFF" -eq 0 ]; then
    echo "最後一個 Round 缺少 \`### Summary\` 或 \`### Handoff\`。請依 skills/devlog-tracker/SKILL.md 補上這兩個標題（Summary 給人掃、Handoff 給下一輪接續），寫完再結束這一輪。" >&2
    exit 2
  fi
fi
```

Leave the span-tick reset and checkpoint block that follow unchanged.

- [ ] **Step 4: Point existing passing writes at `append_minimal_round`**

The heading check will now fail every existing scenario that appends only `## Round N — …` and then expects exit 0. Replace those writes; do not change their expected exit codes.

Replace Scenario 2:

```bash
echo "## Round 1 — 2026-09-08T00:00:00+08:00" >> "$DEVLOG_DIR/devlog.md"
```

with:

```bash
append_minimal_round 1 "2026-09-08T00:00:00+08:00"
```

Replace Span Mode Scenario 3:

```bash
echo "## Round 2 — 2026-09-08T00:10:00+08:00" >> "$DEVLOG_DIR/devlog.md"
```

with:

```bash
append_minimal_round 2 "2026-09-08T00:10:00+08:00"
```

Replace Checkpoint Mode Scenario 1:

```bash
echo "## Round 3 — 2026-09-08T00:20:00+08:00" >> "$DEVLOG_DIR/devlog.md"
```

with:

```bash
append_minimal_round 3 "2026-09-08T00:20:00+08:00"
```

Replace Checkpoint Mode Scenario 2:

```bash
echo "## Round 4 — 2026-09-08T00:25:00+08:00" >> "$DEVLOG_DIR/devlog.md"
```

with:

```bash
append_minimal_round 4 "2026-09-08T00:25:00+08:00"
```

Checkpoint Mode Scenario 3 only appends `## Checkpoint（Round 3-4 摘要）`. After the Scenario 2 replacement, last Round is Round 4 with both headings, so this stays a one-line append — do not add headings to the Checkpoint itself.

Replace Checkpoint Mode Scenario 5 (the write that currently expects allowed after a malformed checkpoint-state):

```bash
echo "## Round 5 — 2026-09-08T00:35:00+08:00" >> "$DEVLOG_DIR/devlog.md"
```

with:

```bash
append_minimal_round 5 "2026-09-08T00:35:00+08:00"
```

Replace Checkpoint Mode Scenario 6's initial file and the Round 2 append. Current initial file is:

```bash
cat > "$DEVLOG_DIR/devlog.md" <<'DEVEOF'
## Round 1 — 2026-09-09T00:00:00+08:00
DEVEOF
```

Replace with:

```bash
: > "$DEVLOG_DIR/devlog.md"
append_minimal_round 1 "2026-09-09T00:00:00+08:00"
```

Replace:

```bash
echo "## Round 2 — 2026-09-09T00:05:00+08:00" >> "$DEVLOG_DIR/devlog.md"
```

with:

```bash
append_minimal_round 2 "2026-09-09T00:05:00+08:00"
```

The follow-up `echo "## Checkpoint（Round 2 摘要）"` stays as-is.

- [ ] **Step 5: Run the full hook self-check**

Run: `bash hooks/scripts/test-enforce-devlog.sh`

Expected: every line is `PASS: …`, then `All checks passed.`, exit 0.

If Heading Scenario 9 reports ticks other than 6: `round-start.sh` increments `ticks_since_checkin` from 5 to 6 before `enforce-devlog.sh` runs. The failure mode to debug is a reset to 0 (heading check ran after span reset) or a stay at 5 (round-start did not increment).

Also run: `bash hooks/scripts/test-session-start-devlog.sh`

Expected: `All checks passed.` (no production changes to that script).

- [ ] **Step 6: Commit**

```bash
git add hooks/scripts/enforce-devlog.sh hooks/scripts/test-enforce-devlog.sh
git commit -m "$(cat <<'EOF'
feat: require Summary and Handoff headings on the last Round

EOF
)"
```

---

### Task 2: Authoring instructions and user-facing copy

**Files:**
- Modify: `skills/devlog-tracker/SKILL.md` (format, writing rules, trivial rounds, segments example, span close, checkpoint content)
- Modify: `README.md` (特色「格式固定」bullet; `docs/design/` tree)
- Modify: `commands/start.md` (the `User Input / Response / Status` phrase)
- Modify: `docs/design/span-mode.md` (closing Round sentence)
- Modify: `docs/design/checkpoint-mode.md` (segment example)
- Test: none automated — grep for leftover current-format `### Response` / `User Input / Response / Status` after the edits

**Interfaces:**
- Consumes: heading names and stderr phrases from Task 1 (`### Summary`, `### Handoff`, `User Input / Summary / Handoff / Status`).
- Produces: SKILL.md as the single source of authoring rules the Stop hook's messages point at.

- [ ] **Step 1: Replace the Round format block and writing rules in SKILL.md**

In `skills/devlog-tracker/SKILL.md`, replace the section starting at `## 每一輪的紀錄格式` through the end of `### 怎麼判斷這輪該寫多細（瑣碎程度）` (the table included) with:

````markdown
## 每一輪的紀錄格式

完成一輪工作後（或使用者要求先記錄時），在檔案尾端新增：

```markdown
## Round <N> — <ISO 8601 時間戳，含時區>

### User Input
<使用者這輪的輸入，貼近原話，保留關鍵細節，不用強制逐字照抄>

### Summary
<2–4 句，給人掃：這輪結論、有沒有卡住。不要寫檔案路徑、commit hash、skill 名稱、逐步指令>

### Handoff
#### 決策
<影響後續方向的選擇與理由。沒做選擇就整節省略>

#### 檔案
<新增／修改／刪除的路徑；有 commit 就寫 hash 或說明沒 commit。沒動檔就整節省略>

#### 現況
<工作區現在的實際狀態，讓下一輪不用重探。幾乎每輪都該有>

#### 下一步
<下一輪第一件具體要做的事（路徑、指令、要載入的 skill）。
IN_PROGRESS／BLOCKED 必寫；DONE 且沒有後續就整節省略>

### Status
DONE | IN_PROGRESS | BLOCKED
```

Round 編號：讀取檔案中最後一個 `## Round <N>`，本輪用 N+1；檔案不存在就從 Round 1 開始。

寫入原則：
- **User Input 預設貼近使用者原話，但保留彈性，不強制逐字照錄。** 目標是讓人「只讀這份
  檔案、不用翻對話紀錄」就能接續開發，所以要保留原始措辭裡的關鍵細節（用詞、並列條件、
  隨口補充的例外情況），但不用機械式地一字不漏照抄——內容太長、太雜（例如夾雜大段貼上的
  log 或程式碼）時，可以留原文最相關的部分、把明顯的雜訊留在原處摘要帶過，怎麼拿捏由
  Claude 自己判斷，不用每次都整段複製。
- **兩個讀者拆開：** `Summary` 只給人掃；`Handoff` 只給下一輪 Claude 接手。同一件事不要兩邊複述。
- Handoff 四個小節順序固定（決策 → 檔案 → 現況 → 下一步）。沒發生的整節省略，不要寫「無」。
  `現況` 幾乎每輪都該有。`下一步` 在 `IN_PROGRESS`／`BLOCKED` 必寫，且要具體到下一輪打開就能做，
  不要寫「繼續完成」。
- Handoff 只寫已發生的事；未來式只允許出現在「下一步」。
- `Status` 只寫 `DONE`、`IN_PROGRESS`、`BLOCKED` 其中一個，不要在下面再附「接下來要做什麼」
  （那句搬進 Handoff 的「下一步」）。`IN_PROGRESS` = 還能做；`BLOCKED` = 缺外部輸入；
  `DONE` = 這輪請求已結束。
- 每輪一個區塊，不要把多輪內容合併寫成一個 Round。
- 不要另外開欄位列「這輪用了哪些 skill」——那是稽核用途，跟接續開發沒有直接關係。只有
  當接續動作**必須**重新載入某個特定 skill 才能正確接手時，才把 skill 名稱寫進 Handoff
  「下一步」裡。

Stop hook 會檢查最後一個 Round 是否同時有 `### Summary` 與 `### Handoff` 這兩行標題
（只驗標題存在，不驗寫得好不好）。新開的 Round 兩個標題都要有，瑣碎輪也不例外。

### 怎麼判斷這輪該寫多細（瑣碎程度）

「每輪都要記錄」管的是**要不要留下這一輪的痕跡**，瑣碎程度管的是**該寫多細**，這是兩件
不同的事——瑣碎不代表可以跳過不記，只代表這輪該寫得短。

判斷測試：**如果把這一輪從 devlog 刪掉，之後光讀檔案接續工作，會不會漏掉重要資訊？**
會漏掉就不瑣碎，要完整寫；不會漏掉（純確認、閒聊、使用者只回「好」「謝謝」、沒有產生任何
實質變化或懸而未決的事）就是瑣碎，但**還是要有這個 Round 區塊**，只是 Summary 一句話、
Handoff 只留「現況」一句，Status 多半 `DONE`。兩個標題仍然都要有。

具體訊號：

| 訊號 | 不瑣碎（寫詳細） | 瑣碎（一句話帶過） |
|---|---|---|
| 檔案異動 | 有改到／新增／刪除檔案 | 完全沒動任何檔案 |
| 決策 | 做了會影響後續方向的選擇 | 沒有做任何選擇，純粹回應 |
| Status | `IN_PROGRESS` / `BLOCKED`（還有事沒完） | `DONE` 且沒有任何懸而未決 |
| 內容重複性 | 帶來新資訊 | 只是重複或確認前一輪已經記過的事 |
````

Keep the SKILL section in the same heading hierarchy as today (`## 每一輪的紀錄格式`). The format example inside it uses a normal three-backtick `markdown` fence.

- [ ] **Step 2: Update Round Segments, Span close, and Checkpoint content in SKILL.md**

Replace the Round Segments section body (from `## Round Segments：單輪內的階段性記錄` through the paragraph that currently says 「照舊只寫一個 `Response` 就好」) with:

```markdown
## Round Segments：單輪內的階段性記錄

一輪如果包含好幾個明顯階段（先探索、再做決策、再實作、再驗證），不要全部
憋到最後才寫一次 Summary／Handoff——那樣中途 crash 會整輪的過程全部遺失，事後也
看不出中間走過的路。改成邊做邊在這輪底下追加階段性子區塊，插在 User Input 和
收尾的 Summary／Handoff 之間：

`````markdown
## Round 15 — 2026-09-09T09:00:00+08:00

### User Input
幫我重構 XXX 模組

### 段落 1 - 09:12
讀完現有程式碼，發現三個地方耦合...

### 段落 2 - 09:20
決定拆成 A/B 兩個檔案，理由...

### 段落 3 - 09:35
完成拆分，跑測試全過

### Summary
把 XXX 模組拆成 A/B 兩個檔案，測試全過。

### Handoff
#### 決策
拆成 A/B，理由是三處耦合都集中在同一個檔。
#### 檔案
新增 a.ts、b.ts；刪除 xxx.ts。尚未 commit。
#### 現況
拆分完成，測試全過。
#### 下一步
（省略：DONE）

### Status
DONE
`````

上面範例裡「下一步」整節應刪掉，不要真的寫「（省略：DONE）」。DONE 且沒有後續時直接沒有 `#### 下一步` 這個標題。

**什麼時候該寫一個段落**：跟判斷 `Status: IN_PROGRESS` 用的同一套標準——「有意義的
階段性結果」，不是照時間或工具呼叫次數機械觸發。短的、沒什麼階段可言的一輪，
照舊只寫 Summary／Handoff 就好，不用硬湊段落。不要把段落內容再抄進 Summary 或 Handoff。
```

Keep the following paragraph that starts with `機制上不需要任何 hook 改動` — it is still true for segments themselves. After it, add this sentence as its own paragraph:

```markdown
收尾時 Stop hook 仍會要求最後一個 Round 上看得到 `### Summary` 與 `### Handoff`。
```

In `### span 開著的時候會自動發生什麼事`, after `寫點輕量的進度（不用完整 Round，一行都可以）就能讓它繼續運作。`, append:

```markdown
前提是最後一個 Round 裡已經有 `### Summary` 與 `### Handoff`——一行是追加到那個 Round，不是新開一個缺標題的 Round。若這輪是新開的 Round，兩個標題都要有。
```

Replace the `### 怎麼關掉一個 span` paragraph with:

```markdown
整個 Ask 真的做完時：**開一個新的 Round**（不要回頭改寫當初開 span 那個
Round），User Input 可以寫「（自動續接收尾，接續 Round 12）」；Summary 用 2–4 句
給人看這段自動化的結論；Handoff 依四個小節總結整段期間做了什麼（決策／檔案／現況／
下一步）；Status 正常寫 `DONE`／`IN_PROGRESS`／`BLOCKED`；然後刪掉 `.devlog/.span-open`。
```

In `### 被要求補寫的時候該怎麼寫`, replace the sentence that currently says `內容抓重點就好，不用逐輪複述——細節本來就還留在下面的 Round 區塊裡，checkpoint 只是給翻閱時的路標。` with:

```markdown
`X`-`Y` 是這段還沒被摘要過的 Round 範圍，內容對齊各輪 Summary 抓重點就好，不用逐輪複述、
也不要變成各輪 Handoff 的合集——細節本來就還留在 Round 區塊裡，checkpoint 只是給翻閱時的路標，
不替代每輪 Summary。
```

- [ ] **Step 3: Update README, start command, and the two older design docs**

In `README.md`, replace the 格式固定 bullet:

```markdown
- **格式固定**：每輪都是 `User Input`（貼近原話，保留彈性）/ `Summary`（人讀結論）/ `Handoff`（下一輪接續：決策、檔案、現況、下一步）/ `Status`（只寫 `DONE` / `IN_PROGRESS` / `BLOCKED`），讀檔案就能還原對話重點，不用翻對話紀錄。細節見 [`docs/design/summary-handoff.md`](docs/design/summary-handoff.md) 和 SKILL.md。
```

In the same file's directory tree, replace the `docs/design/` entries with:

```
├── docs/design/
│   ├── span-mode.md           # Span Mode 設計文件
│   ├── checkpoint-mode.md     # Checkpoint Mode 設計文件
│   └── summary-handoff.md     # 每輪 Summary（人）+ Handoff（AI）設計文件
```

In `commands/start.md` step 5, replace `（User Input / Response / Status）` with `（User Input / Summary / Handoff / Status）`.

In `docs/design/span-mode.md`, replace:

```
(e.g. "（自動續接收尾，接續 Round 12）"); its Response summarizes the whole
spanned period.
```

with:

```
(e.g. "（自動續接收尾，接續 Round 12）"); its Summary (human) and Handoff
(next Claude) summarize the whole spanned period.
```

In `docs/design/checkpoint-mode.md`:

- In the opening paragraph, replace `one round's \`Response\` is a single` with `one round's closing summary is a single`.
- Replace `everything until the final \`Response\`` with `everything until the final Summary / Handoff`.
- Replace the format example's closing `Response: (最終總結)` / `Status: DONE` with:

```markdown
### Summary
完成拆分，測試全過。

### Handoff
#### 現況
拆分完成，測試全過。

### Status
DONE
```

- Replace `A short round with no real phases still gets a single \`Response\` as today` with `A short round with no real phases still gets Summary / Handoff as today, with no segment headings`.

Leave `docs/design/summary-handoff.md` as-is (it describes the old `### Response` as the problem being replaced).

- [ ] **Step 4: Grep for leftover current-format phrasing**

Run from the repo root:

```bash
rg -n 'User Input / Response / Status|### Response' --glob '!docs/design/summary-handoff.md' --glob '!docs/design/summary-handoff-plan.md'
```

Expected: no matches in `skills/`, `README.md`, `commands/`, `hooks/`. Mentions inside `docs/design/summary-handoff.md` (the spec talking about the old field) are allowed and excluded by the glob. If `rg` is missing, use `grep -R`.

Also run: `bash hooks/scripts/test-enforce-devlog.sh` and `bash hooks/scripts/test-session-start-devlog.sh`

Expected: both print `All checks passed.`

- [ ] **Step 5: Commit**

```bash
git add skills/devlog-tracker/SKILL.md README.md commands/start.md docs/design/span-mode.md docs/design/checkpoint-mode.md
git commit -m "$(cat <<'EOF'
docs: split each Round into Summary and Handoff

EOF
)"
```

---

## Self-review (spec coverage)

| Spec requirement | Task |
|---|---|
| Round template with Summary + structured Handoff + Status enum only | Task 2 Step 1 |
| Writing rules (two readers, omit empty subsections, trivial rounds, future tense only in 下一步) | Task 2 Step 1 |
| Skill name lives in Handoff 下一步, not Status | Task 2 Step 1 |
| Round Segments between User Input and Summary/Handoff | Task 2 Step 2 |
| Checkpoint content aligns with Summaries | Task 2 Step 2 |
| Span close uses new format; one-line check-in requires existing headings | Task 2 Step 2 + Task 1 Scenario 8 |
| Hash-miss message names Summary / Handoff | Task 1 Scenario 1 + Step 3 |
| Last-Round extraction stops before next `## ` | Task 1 Scenario 6 |
| Missing Summary or Handoff → exit 2 | Task 1 Scenarios 2–3 |
| Empty bodies still pass | Task 1 Scenario 4 |
| No `## Round` → fail-open | Task 1 Scenario 5 |
| Checkpoint-only append on complete last Round passes | Task 1 Scenario 7 |
| Heading miss does not reset span ticks | Task 1 Scenario 9 |
| Existing hash/span/checkpoint tests still pass | Task 1 Step 4 fixture updates |
| README + start.md copy | Task 2 Step 3 |
| compact.md / session-start / round-start / version bump | out of scope, no task |
| Historical `### Response` migration | out of scope, no task |
