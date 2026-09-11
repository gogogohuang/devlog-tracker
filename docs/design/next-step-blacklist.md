# `#### 下一步` Filler Blacklist

Add one more Stop-hook check on top of the existing non-empty check for
`#### 下一步`: reject a body that is *nothing but* a known filler phrase
("繼續完成", "持續優化", ...). This is a **rule-based, non-semantic**
string match — not a step toward scoring Summary/決策/現況 prose, which
stays out of scope (see Relationship to "no scoring prose" below).

## Motivation

`skills/devlog-tracker/SKILL.md` already tells Claude in prose: 「下一步」
要具體到下一輪打開就能做，寫「繼續完成」不算完成. The existing hook check
(`heading-substance-plan.md`) only verifies the section is **non-empty** —
writing literally `繼續完成` satisfies it. The rule has been documented
since 0.5.0 and is routinely not enforced because nothing checks it.

This closes that one specific, narrow gap without opening the door to
judging whether a `下一步` is *good* — only whether it is *empty of content
in a way the writing rule already calls out by name*.

## Relationship to "no scoring prose"

`docs/design/optimization-plans.md` and `docs/design/polish-0.9.0-design.md`
both forbid "scoring Summary prose", reaffirmed twice. That principle is
about **semantic judgment of narrative quality** — requiring an LLM (or an
LLM-gradable heuristic) to decide whether a decision was reasoned well, or
a status accurately reflects reality. It stays intact here:

- The check is a literal string/pattern match, computed by the same
  `awk`/`grep` machinery already used for `#### 工作區` and `#### 檔案`.
- It only ever fires when the **entire** trimmed body is one of a small,
  fixed set of known-empty phrases — never on content that merely mentions
  one of them inside a longer, concrete sentence.
- It does **not** extend to `### Summary`, `#### 決策`, or `#### 現況`.
  Those stay exactly as they are today: presence + non-empty only, no
  further check (see Q7 in the grilling session that produced this doc —
  scope was deliberately kept to `下一步` alone to avoid false-positives on
  legitimately short free prose elsewhere).

## Scope

Applies only to `#### 下一步`, only when `### Status` is `IN_PROGRESS` or
`BLOCKED` (the only cases where `#### 下一步` is required at all).

## Match rule

1. Extract the `#### 下一步` body the same way `heading-substance-plan.md`'s
   `section_body` already does (stop at the next `#### `/`### `/`## `).
2. Join all non-empty lines, trim leading/trailing whitespace per line,
   strip trailing full-width/half-width punctuation (`。`, `.`, `！`, `!`).
3. If the result is a **single line** and that line, after the strip in
   step 2, **exactly equals** (not merely contains) one of the blacklist
   entries below, block with `exit 2`.
4. Multi-line bodies, or any single line that has extra content beyond a
   blacklist entry, always pass. False negatives are acceptable; false
   positives on legitimate content are not (same fail-open-toward-content
   posture as the rest of this hook's design).

### Default blacklist

A small, fixed list to start (tune later if it proves too narrow or too
broad — this is not user-configurable in v1):

```
繼續完成
持續完成
持續優化
持續改進
之後再看
視情況調整
待確認
繼續
持續推進
繼續處理
```

### Error message

```
「#### 下一步」目前只寫了「<原文>」，這是空話，不算具體下一步。
請寫清楚下一輪打開就能做的具體動作（路徑／指令／要載入的 skill）。
```

## Implementation sketch

Lives in `hooks/scripts/enforce-devlog.sh`, immediately after the existing
`IN_PROGRESS`/`BLOCKED` → `#### 下一步` non-empty check (see
`heading-substance-plan.md` Task 2). Reuses the same `section_body` /
`awk` helper already defined there — no new file.

```bash
NEXT_BODY="$(section_body '^#### 下一步' <<<"$LAST_ROUND" \
  | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
  | grep -v '^$')"
NEXT_LINES="$(printf '%s\n' "$NEXT_BODY" | grep -c '.')"
if [ "$NEXT_LINES" -eq 1 ]; then
  STRIPPED="$(printf '%s' "$NEXT_BODY" | sed -e 's/[。.！!]*$//')"
  case "$STRIPPED" in
    繼續完成|持續完成|持續優化|持續改進|之後再看|視情況調整|待確認|繼續|持續推進|繼續處理)
      echo "「#### 下一步」目前只寫了「$STRIPPED」，這是空話，不算具體下一步。請寫清楚下一輪打開就能做的具體動作（路徑／指令／要載入的 skill）。" >&2
      exit 2
      ;;
  esac
fi
```

## Known limitations

- **Blacklist is fixed, not learned.** A filler phrase not on the list
  (e.g. "看情況" alone) still passes. This is deliberately conservative —
  see Match rule point 4.
- **Can still be gamed.** Appending any token to a blacklisted phrase
  ("繼續完成剩下的" 之類) passes, same as the existing "heading written for
  other reasons still counts" limitation on Summary/Handoff elsewhere.
  That is accepted, not fixed, here.
- **Not extended to other sections.** `### Summary`, `#### 決策`,
  `#### 現況` remain presence/non-empty-only. Extending this pattern to
  them is a separate future decision, not bundled into this one.

## Non-goals

- Scoring or judging `下一步` quality beyond "is it just a filler phrase".
- Any semantic/LLM-based check anywhere in `enforce-devlog.sh`.
- A user-tunable blacklist file/command in v1.

## Files

| File | Role |
|---|---|
| `hooks/scripts/enforce-devlog.sh` | New check, placed after existing `下一步` non-empty check |
| `hooks/scripts/test-enforce-devlog.sh` | New scenarios: pure blacklist phrase → blocked; blacklist phrase inside a longer sentence → allowed; multi-line body → allowed |
| `docs/design/summary-handoff.md` | Add one line under Known limitations noting the filler-phrase check |
| `skills/devlog-tracker/SKILL.md` | One sentence next to the existing "不算完成" writing rule, noting it is now also hook-enforced |
| `docs/design/next-step-blacklist.md` | This spec |
