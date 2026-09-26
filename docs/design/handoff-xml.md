# Handoff XML (`<handoff>` / `<session-handoff>`)

`### Handoff` and `### Session Handoff` are the only Round sections whose
reader is the next Claude (and the Stop hook), never a human. Today both
are `####`-headed Markdown, so every consumer — `enforce-devlog.sh`,
`handoff-file.sh`, `devlog-md.sh`, `round-start.sh`, `segment-watch.sh` —
walks lines with awk, tracks ``` fences, and needs the odd-fence
fail-open (`_devlog_fence_nofence`, `_handoff_nofence_flag`) so a pasted
unclosed fence doesn't silently hide `#### 工作區`. Misspelled headings
(`#### 下一步驟`) are ignored rather than rejected.

This design moves those two sections — and only those two — to
line-based XML-style tags. `### User Input`／`### Summary`／`### Reply`／
`### 段落`／`### Status`／`## Checkpoint` stay Markdown: humans read them.

## Decisions (brainstorming session, 2026-09-26)

1. **Scope:** `### Handoff` and `### Session Handoff` both change.
   Nothing else in the Round does.
2. **Compatibility, not forced migration:** every reader accepts both the
   legacy `####` form and the XML form. Archive／keep／lessons files are
   never rewritten by the plugin.
3. **Writer is strict:** Stop accepts only XML for the round it
   validates. Legacy rounds exist only as history.
4. **English tag names** (table below). The Chinese subsection names stay
   as the legacy form and as documentation labels.
5. **Shared access layer** (approach A): one sourced helper,
   `core/scripts/handoff-fields.sh`, owns format detection, field
   extraction for both forms, and the name ↔ tag table. Rejected: B
   (normalize XML back to Markdown and keep the old awk — keeps `####` as
   the internal truth and keeps the fence problem) and C (dual branches
   in every consumer — the same compat code six times over).
6. **`/devlog-tracker:migrate`** converts legacy Handoffs in place. When
   Stop blocks on a legacy Handoff, the message tells the agent to run the
   migrate script itself; the user only needs to act when the agent keeps
   writing the legacy form (stale vendored skill → rerun `init` + `start`).
7. **Blocked messages carry the correct template**, printed from the same
   function SKILL.md's template is tested against.

## Format

```markdown
### Handoff
<handoff>
<decisions>
採用共用存取層，理由見 `docs/design/handoff-xml.md`
</decisions>
<files>
尚未 commit：
修改：core/scripts/enforce-devlog.sh
</files>
<workspace>
feat/handoff-xml @ b457121
未提交：core/scripts/enforce-devlog.sh
</workspace>
<state>…</state>
<done-when>…</done-when>
<next>…</next>
</handoff>

### Session Handoff
<session-handoff>
<decisions>
- （無）
</decisions>
<open-questions>
- …
</open-questions>
<failed-attempts>
- …
</failed-attempts>
</session-handoff>
```

| key | legacy heading | tag | block |
|---|---|---|---|
| decisions | `#### 決策` | `<decisions>` | handoff, session-handoff |
| files | `#### 檔案` | `<files>` | handoff |
| workspace | `#### 工作區` | `<workspace>` | handoff |
| state | `#### 現況` | `<state>` | handoff |
| done-when | `#### 完成條件` | `<done-when>` | handoff |
| next | `#### 下一步` | `<next>` | handoff |
| open-questions | `#### 待解問題` | `<open-questions>` | session-handoff |
| failed-attempts | `#### 失敗嘗試` | `<failed-attempts>` | session-handoff |

Rules:

1. **Markdown headings stay.** `### Handoff`／`### Session Handoff` still
   open the section; the tag block sits under them. Round boundaries,
   Summary／Reply checks and timeline section splitting are untouched.
2. **A tag is structure only when it is the whole line** (`^<next>$`,
   `^</next>$`, surrounding whitespace allowed). Inline `<…>`, tags inside
   prose, and ``` fences inside a field are content. Fences are **not**
   tracked inside a tag block. Known cost: a content line consisting of
   exactly `</next>` is misread; accepted.
3. **This is not real XML.** No attributes, no self-closing tags, no
   nesting beyond block → field, no escaping — `&` and `<` in content are
   literal. Do not feed these blocks to an XML parser.
4. **Field content is unchanged Markdown.** `<workspace>` keeps the seven
   `workspace-snapshot.sh` formats; `<files>` keeps the `commit <hash>：`／
   `尚未 commit：` grammar. Both machine checks are reused verbatim.
5. **Order, presence and emptiness rules are the current ones**, keyed by
   tag: decisions → files → workspace → state → done-when → next;
   session-handoff: decisions → open-questions → failed-attempts. An
   empty field is an error, same as an empty subsection.
6. **Stricter than legacy:** unknown tag, unclosed tag, tag and content on
   one line (`<next>做 X</next>`), or non-blank text outside the block
   (between `### Handoff` and the next `###`) all block.
7. **One form per round:** a round Stop validates must use XML for both
   Handoff and Session Handoff.
8. **`handoff.md` holds the XML block verbatim** (`<session-handoff>` …
   `</session-handoff>`). Existing legacy `handoff.md` files are still
   injected as-is by SessionStart (it pastes the file whole).

## Access layer: `core/scripts/handoff-fields.sh`

Sourced helper, no side effects.

- `handoff_format <blob>` → `xml` | `md` | `none`. `<blob>` is a section
  body (text under `### Handoff` or `### Session Handoff`). `xml` when the
  first non-blank line is the block's opening tag; `md` when a `#### `
  heading appears (fence-aware, legacy rules); otherwise `none`.
- `handoff_field <blob> <key>` → field body for either form, empty when
  absent. Legacy path is the existing fence-aware `#### ` scan including
  the odd-fence fail-open; XML path is the whole-line tag scan.
- `handoff_xml_check <blob> <handoff|session-handoff>` → exit 0, or exit 1
  with one error line naming the offending tag／line (rule 6 cases, order,
  duplicates, empty fields).
- `handoff_xml_template <handoff|session-handoff>` → the canonical
  template, printed in blocked messages.
- The key／heading／tag table lives here only. `timeline-render.js` keeps
  a JS copy (display only); a test checks the two agree.

## Stop hook (`enforce-devlog.sh`)

For the last round, in order:

1. Heading check (`### Summary`／`### Reply`／`### Handoff` present and
   non-empty) — unchanged.
2. **Format gate** on the Handoff body:
   - `xml` → continue.
   - `md` → block. Message: Handoff must use XML; run
     `bash "<absolute plugin root>/core/scripts/migrate-handoff.sh"`
     (with `DEVLOG_PROJECT_DIR` set) and finish the turn again; if the
     round is reported under `SKIPPED`, rewrite it by hand using the
     template (printed). Then a line addressed to the user: if the agent
     keeps writing the legacy form, the vendored skill／commands are stale —
     rerun `npx devlog-tracker init` (plugin users: update the plugin),
     then `/devlog-tracker:start`.
   - `none` or `handoff_xml_check` fails → block with the specific error
     and the template.
3. Order／duplicate check — now from the tag sequence (part of
   `handoff_xml_check`); messages name tags.
4. Field checks read through `handoff_field`; their logic is unchanged:
   `done-when`／`next` required for `IN_PROGRESS`／`BLOCKED`, the next-step
   blacklist, the `IN_PROGRESS` actionability check, the `BLOCKED`
   missing-item phrasing, `workspace` verbatim compare, `files` verify.
5. Session Handoff: required for `IN_PROGRESS`／`BLOCKED`, same gate with
   `session-handoff`; on pass the block is written to `handoff.md`;
   `DONE` deletes it; `INTERRUPTED` leaves it — unchanged policy.
6. Fail-open, loop guard, `.enabled`, and the hook-written `INTERRUPTED`
   stub exemption are unchanged. `close-open-round.sh` now emits its stub
   as `<handoff>` + `<state>`.

The Stop hook grows during the transition (legacy reading stays); that is
accepted. It shrinks when legacy reading is removed (see end).

## Migrate (`/devlog-tracker:migrate`)

Files: `core/scripts/migrate-handoff.sh`, `commands/migrate.md`.

- **Targets:** `.devlog/.round-current.md`, `devlog.md` and every branch
  devlog (resolved via `devlog-path.sh`), `handoff.md` and branch
  variants. Not archive, keep (`devlog.<name>.md`), or lessons files.
- **Conversion:** per Round, locate `### Handoff`／`### Session Handoff`
  with the existing fence-aware parsing; map each `#### ` subsection to
  its tag; copy content byte-for-byte.
- **Idempotent:** rounds already in XML are skipped.
- **Never guesses:** a round with an unknown `#### ` subsection, bad order,
  a duplicate, or an odd fence count inside the section is left untouched
  and reported. History is converted as-is — no validation, no filling
  missing fields, no removals.
- **Safety:** takes `devlog-lock.sh`; writes each file to a temp file and
  `mv`s it into place; before changing a file, copies it to
  `<file>.pre-migrate` (overwriting the previous backup) because
  `.devlog/` is gitignored.
- **Output:** `MIGRATED=<n>`, `SKIPPED=<n>` followed by one
  `SKIP <file> Round <N>: <reason>` line each, `BACKUP=<path>` per changed
  file. `commands/migrate.md` reports it in one sentence.

## Readers

| file | change |
|---|---|
| `devlog-md.sh` (`devlog_round_workspace_body`) | read via `handoff_field … workspace`; `round-start.sh`／`segment-watch.sh` inherit it — only their messages change (`工作區（<workspace>）`) |
| `session-start-devlog.sh` | excerpt copies the whole `### Handoff`; confirm fence counting does not swallow an XML block |
| `report-scan.awk` | unchanged (captures the whole Handoff) |
| `timeline-render.js` | before `renderMarkdown`, turn each field tag into a `#### <中文名>` heading |
| `close-open-round.sh` | XML stub |
| `handoff-file.sh` | validation／extraction via the access layer; writes the XML block |

## Docs

- `skills/devlog-tracker/SKILL.md`: XML template in 「每一輪的紀錄格式」,
  the key／heading／tag table, and a note that legacy `####` appears only
  in history and is read for compatibility.
- `commands/pr.md`, `keep.md`, `keep-all.md`, `continue.md`, `resume.md`,
  `search.md`, `status.md`: every hard-coded subsection name becomes
  「決策（`<decisions>`；舊格式 `#### 決策`）」. `keep.md`'s summary-mode
  do-not-touch list adds `<workspace>`／`<files>`／`<done-when>`／`<next>`.
- New `commands/migrate.md`; one row in `cli/agents-md.js`'s Codex table.
- `README.md`／`README.zh-TW.md`: Handoff XML in the format section,
  migrate in the command list, upgrade note (agent migrates on block;
  persistent legacy writes → rerun `init` + `start`).

## Tests

- New `tests/test-handoff-fields.sh`: format detection; field extraction
  in both forms; each rule-6 failure; order／duplicate／empty; SKILL.md's
  template equals `handoff_xml_template` output.
- New `tests/test-migrate-handoff.sh`: basic conversion; idempotence; XML
  rounds skipped; unknown subsection → whole round skipped; fake `####`
  inside a fence not converted; backup written; branch devlog converted;
  `handoff.md` converted.
- Enforce tests: fixtures for new behavior move to XML; a small set of
  legacy fixtures remains only for "legacy is blocked (message has migrate
  path + template)" and read-side compatibility. Not every old test is
  duplicated.
- `test-session-start-devlog.sh`, `test-close-open-round.sh`,
  `test-workspace-snapshot.sh`, round-start／segment-watch drift tests:
  add an XML case each.
- Node: `timeline-render.test.js` renders an XML Handoff and checks the
  JS table matches the bash one; `agents-md.test.js` for the new row.
- Adapters: `test-adapters.sh` for cursor／codex must still pass; no
  adapter change expected.

## Removing legacy support (later)

Not part of this work. Preconditions: migrate has shipped for at least
one release, and keep／archive files have a conversion path (extend
migrate or accept them as read-only history). Then delete the `md` path
in `handoff-fields.sh` and the odd-fence fail-open it needed.
