# Keep-all (reorganize every devlog into topic files)

`/devlog-tracker:keep-all` is `keep` widened from one file to every devlog
file in `.devlog/`: the current branch's working log, other branches'
working logs, `devlog.archive.md`, and every file an earlier `keep` (or
`keep-all`) already produced. Claude partitions all of their Rounds into
topics — across files, not just contiguous ranges inside one — proposes
the whole set of named files at once, and after confirmation a single
script run rewrites everything atomically.

It is a separate command, not a `keep` sub-mode (`keep:all`): `cli init`
turns each `commands/*.md` into a skill directory for Codex/Cursor, where
a `:` in the name is not safe, and the repo already uses hyphenated
siblings (`lessons-on`/`lessons-off`).

`keep` itself is unchanged. Its single-file, single-range primitive
(`keep-move.sh`) stays as it is; keep-all has its own script because its
unit of work is "a set of Rounds from several files", which a
`--from/--to` range in one file cannot express.

`core/scripts/keep-all.sh` resolves the current branch's file, reads the
open Round from `.round-open`, holds the devlog lock, and hands off to
`core/scripts/keep-all.js`, which does the scanning, validation and
rewriting. Multi-file, all-or-nothing rewriting is far easier to get
right in JS than in awk; like `timeline`, the command needs Node ≥18 and
the wrapper prints `NO_NODE` without it. keep-all is a management
command: `round-start.sh` doesn't open a Round for it, same as `keep`.

This also adds an **origin marker** to branch-scoped devlog files (see
Origin marker), which keep-all relies on to tell branch files from kept
files without guessing.

## Motivation

`keep` only ever reads the file `devlog_resolve_paths` picks for the
current branch. After some time a project has:

- `devlog.md` (main) plus several `devlog.<branch>.md`, one per branch
  that was ever worked on, each holding part of the history;
- `devlog.archive.md`, a chronological dump that `keep` never looks at;
- a pile of `devlog.<name>.md` kept files, split along whatever topic
  boundaries made sense *at the time*, often with the same topic spread
  over several of them.

A topic routinely spans these (design discussed on main, implemented on
a feature branch, the early part compacted into archive). Nothing today
can bring those pieces together. keep-all does.

## Origin marker (branch files)

Branch files and kept files share the `devlog.<name>.md` namespace, and
the filename is lossy (`feat/x` and `feat-x` both become
`devlog.feat-x.md`). A branch file therefore records where it came from,
as its first line:

```
<!-- devlog-origin: branch=feat/keep-all -->
<!-- devlog-origin: detached=my-worktree-dir -->
```

- An HTML comment: invisible in rendered Markdown, not a `## ` heading,
  so no Round/Checkpoint parser sees it.
- `branch=` holds the raw branch name from `git rev-parse --abbrev-ref
  HEAD`, before sanitizing. `detached=` holds the working directory
  basename used for the detached-HEAD fallback.
- `devlog.md` never gets a marker: its name already identifies it
  (main/master or no git).

**Where it is written.** `devlog_resolve_paths` exports the origin
(`DEVLOG_ORIGIN`, e.g. `branch=feat/keep-all`; empty for `devlog.md`).
The marker is written only at the two points that *create* a branch
file:

1. `_devlog_migrate_unfinished_tail` — the marker is prepended to the
   cut tail before it is moved into place.
2. `devlog_merge_round_current` — when the target file is missing or
   empty and `DEVLOG_ORIGIN` is set, the marker is written first, then
   the Round.

Resolving a path never creates a file by itself (keeps today's "branch
file appears with its first Round" behavior and doesn't change migration
timing).

**Existing files are not backfilled.** Only keep-all needs the marker,
and no other command should silently rewrite a file the user didn't
ask it to touch. keep-all falls back to inferring (see Source
classification).

**Preserving it.** Everything that rewrites a branch file must keep
line 1 when it is the marker:

- `keep-move.sh` full keep moves "text before the first Round" (the
  project summary) into the kept file — the marker is excluded from
  that and stays in the source.
- `clean-devlog.sh` keeps the marker line when it empties the file.
- `session-start-devlog.sh`'s "opening summary" excerpt skips it.
- `compact-devlog.sh`, `close-open-round.sh`, `round-start.sh` only
  append or move Round blocks — unaffected, covered by a regression
  test.

## Source classification

`keep-all.sh --scan` lists every `.devlog/devlog*.md` and classifies it.
Classification is done by the script, never by Claude reading filenames.

| kind | how it is recognised | movable Rounds |
|---|---|---|
| `current` | the file `devlog_resolve_paths` returns now | all except the open Round (`.round-open`) |
| `branch` | `devlog.md` when not current; any file whose line 1 is an origin marker; any other `devlog.<x>.md` that is not one of the kinds below (legacy, origin inferred from the filename) | all except the **unfinished tail**: every Round after the last `DONE` stays |
| `archive` | `devlog.archive.md` | all |
| `kept` | line 1 is `# Kept log` | all, and **every one must be assigned** |
| skipped | `devlog.lessons.*.md` | — |

The unfinished-tail rule is the same one branch migration uses, so a
branch still being worked on keeps exactly what `continue`/`resume` on
that branch need. `current` doesn't need it: its open Round is known.

For `branch` sources the scan also reports the branch's state, for
Claude to show the user (display only, it never changes what is
movable):

- `active` — `refs/heads/<name>` exists and is not merged into
  main/master;
- `merged` — exists and `git merge-base --is-ancestor <name> <main>`;
- `gone` — no such local branch;
- `unknown` — origin was inferred from a legacy filename (the raw name
  can't be recovered), or not a git repo.

### Round identity

Round numbers are not unique across files (every branch file restarts
wherever main was; archive can hold two "Round 3" after a full keep
renumbered the open Round). The scan gives every Round a global id
`#1…#N`, ordered by the heading timestamp (`## Round N — <ts>`, format
`%Y-%m-%dT%H:%M:%S%z`, parsed to an instant so different UTC offsets
compare correctly; unparseable timestamps sort last, ties fall back to
file name order then line order). Plans refer to ids,
never to Round numbers.

### Scan output

```
FINGERPRINT=<cksum, see Apply step 1> COUNT=<N>
SOURCE file=devlog.md kind=branch origin=main origin_from=default state=n/a
SOURCE file=devlog.feat-x.md kind=current origin=feat/x origin_from=marker state=active
SOURCE file=devlog.span-mode.md kind=kept
SOURCE file=devlog.archive.md kind=archive
ROUND id=1 file=devlog.archive.md round=3 line=12 ts=2026-08-01T10:00:00+0800 status=DONE movable=1
...
```

Nothing movable at all → `NOTHING`, exit 0.

## Command flow (`commands/keep-all.md`)

1. Run `keep-all.sh --scan`. On `NOTHING`, say so and stop.
2. Read the listed files. Partition the movable Rounds into topic
   segments. A segment is any set of ids — it may take Rounds from
   several files and need not be contiguous. Same "worth keeping"
   signals as `keep`:
   - Rounds from `kept` sources must all land in some segment (they
     were already judged worth keeping).
   - Thin Rounds from other sources may be left out; they stay where
     they are.
3. Propose every segment in one message, then stop and wait:

   ```
   掃到 N 段主題：
     1. <一句描述>　→ devlog.<name>.md
        devlog.md #3–#8（Round 12–17）、devlog.feat-x.md #20–#24（Round 1–5，分支 feat/x 已合併）
     2. ...
   會被重整並刪除的舊 kept 檔：devlog.a.md、devlog.b.md
   其餘可搬但偏瑣碎、留在原檔：<id 範圍或「無」>
   分支未完成尾巴（不動）：devlog.feat-y.md Round 8–9

   回覆：
     採用
     改第 N 段檔名 <name> / 移除第 N 段 / 第 N 段併入第 M 段 / 摘要第 N 段
     取消
   ```

   `移除第 N 段` is rejected for a segment containing `kept`-source
   Rounds (they would have nowhere to go); use `併入` instead.
   Moving individual Rounds between segments is out of scope for the
   reply grammar — the user can say it in words and Claude re-proposes.
4. On confirmation, write the plan to `.devlog/.keep-all-plan.tsv`:
   one line per segment, `<name>\t<desc>\t<id list>` (e.g. `3-8,20-24`).
5. Run `keep-all.sh --apply .devlog/.keep-all-plan.tsv --fingerprint <fp> --count <N>`
   (both from the scan).
   On exit 1, show stderr verbatim and stop; nothing was written (see
   Apply).
6. Optional `摘要第 N 段`: same rules as `keep` step 5.5 on the resulting
   file.
7. Report per file (path, Rounds count and origin files), deleted kept
   files, backup directory. Close the open Round as usual.

## Apply (`keep-all.sh --apply`)

One run, all or nothing, under the devlog lock.

1. **Re-scan and compare fingerprint.** The scan and the apply run in
   different turns: between them, other work may merge a Round into
   `current` (keep-all itself opens none). So the fingerprint does not cover whole files. It
   covers the scanned Rounds and the source list: `cksum` over the
   ordered `(file, heading, block cksum)` of ids `#1…#N` plus every
   source's path and kind. Apply re-scans and recomputes it over the
   first `N` ids. A Round appended after the scan has the newest
   timestamp, so it sorts after `#N`, isn't in the plan, and stays where
   it is. Any other change (edited or removed Round, new or deleted
   source) → refuse.
2. **Validate the plan.**
   - every id exists and is movable; no id in two segments;
   - every `kept`-source id is covered;
   - names: same normalization and rejection rules as `keep` (strip
     `devlog.`/`.md`, no `/`, `\`, `..`, not empty, not `archive`, not
     `devlog.md`, ≤ 64 chars), plus not `lessons.*`;
   - collisions: a target may not be an existing file, **except** a
     `kept` source that this plan fully consumes (reusing its name is
     allowed); may not equal another segment's target.
   Any failure → stderr, exit 1, no write.
3. **Backup** every source that will change into
   `.devlog/.keep-all-backup/<timestamp>/` (plain copies). The directory
   is gitignored with the rest of `.devlog/`; keep-all never deletes old
   backups.
4. **Build in a temp dir.**
   - Each target: `# Kept log` header with `- source: keep-all`, one
     `- rounds:` line per origin file (`devlog.md 12-17, 20`), `-
     kept_at`; then the Round blocks in id order.
   - A `## Checkpoint` block travels with the Round immediately before
     it; if that Round doesn't move, the Checkpoint stays. A Checkpoint
     in a `kept` source with no preceding Round travels with the next
     one.
   - A `kept` source's project summary (text between its provenance
     header and first block, present after a full keep) goes to the
     target that receives that file's first Round.
   - Sources: moved blocks removed. `current`/`branch` files are
     rewritten but never deleted, even if no Round is left (deleting a
     branch file would re-trigger migration on next checkout); origin
     marker and project summary stay. `archive` is deleted if no Round is
     left. Consumed `kept` sources are deleted.
   - Verify every moved Round heading appears exactly once across the
     targets and not in any rewritten source.
5. **Kept index.**
   - Remove, from every non-deleted source, index lines that point at a
     deleted kept file.
   - Append one line per new target to the `current` file's `## Kept
     索引`: `` - `devlog.<name>.md`：keep-all，<n> 輪，kept_at <ts>，<desc> ``.
   - Lines for kept files keep-all didn't touch stay where they are.
6. **Commit.** Move targets into place, then rewritten sources, then
   delete consumed files. A failure here stops and prints the backup path
   (the backup is the recovery route; no automatic rollback).
7. **State files.** `.span-open` pointing at a Round that moved out of
   `current` is removed. No renumbering of the open Round and no
   checkpoint-counter reset — unlike `keep`'s full keep, "everything was
   moved" isn't a meaningful state across many files.
8. stdout: `KEPT=<path> ROUNDS=<n>` per target, `DELETED=<path>` per
   removed file, `BACKUP=<dir>`.

## Non-goals

- No automatic trigger; user runs the command.
- No backfilling origin markers into existing branch files.
- Not touching `devlog.lessons.*.md` or their index.
- No per-Round edit grammar in the confirmation reply.
- `keep`, `compact`, `resume`, `overview` behavior unchanged (they
  already work on any `# Kept log` file by name).

## Testing

`core/scripts/tests/test-keep-all.sh`:

- classification: current / branch (marker, legacy, `devlog.md` off
  main) / archive / kept / lessons skipped;
- branch unfinished tail and current open Round are not movable;
- cross-file segment lands in one file in timestamp order;
- kept sources consumed, deleted, name reuse allowed; uncovered kept id
  rejected;
- Kept index: ghost lines removed everywhere, new lines on current;
- Checkpoint follows its preceding Round;
- fingerprint mismatch, bad name, collision, overlapping ids → exit 1
  and every file byte-identical;
- backup contains every changed source;
- `.span-open` cleared only when its Round moved.

`test-devlog-path.sh` / `test-branch-scoped-integration.sh`: marker
written on migration and on first merge, not on `devlog.md`, not
rewritten on later merges; raw branch name preserved.
`test-keep-move.sh`, `test-clean-devlog.sh`, `test-session-start-devlog.sh`:
marker survives / is skipped.

## Docs to update

`README.md`, `README.zh-TW.md`, `skills/devlog-tracker/SKILL.md` (file
list: origin marker, keep-all), `cli/agents-md.js` command table,
`commands/keep.md` (one line pointing to keep-all),
`docs/design/branch-scoped-devlog.md` (origin marker section).
