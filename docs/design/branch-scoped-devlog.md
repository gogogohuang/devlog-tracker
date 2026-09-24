# Branch-Scoped Devlog Files

## Motivation

`devlog.md` is currently one shared file per project directory, regardless
of which git branch is checked out. That's fine across separate `git
worktree`s — `.devlog/` is gitignored, so a second worktree is a different
directory on disk and already gets its own independent `.devlog/` for
free, no code change needed.

The real gap: **switching branches inside the same worktree**. Open a
branch to fix one issue, then `git checkout` to another branch for an
unrelated one, and both write into the same `devlog.md` — the two
problems' histories interleave, and `Handoff`/`#### 工作區` for one
branch's work can get confused with another's.

## Scope

- In scope: resolving which devlog file to read/write based on the
  currently checked-out branch, within a single working directory.
- Out of scope: any worktree-specific logic. Worktree isolation is already
  solved by `.devlog/` being per-directory and gitignored.
- Out of scope: `devlog.archive.md`, `/devlog-tracker:keep`-produced
  `devlog.<name>.md`, and `devlog.lessons.<topic>.md` — these are
  explicit, user-triggered operations and stay project-wide, not
  branch-scoped.
- No new on/off toggle. This is default behavior once
  `/devlog-tracker:start` has been run, same enablement scope as today
  (`.devlog/.enabled`) — not a separate mode like Span/Lessons.

## Branch → filename resolution

```
1. Not a git repo, or branch detection fails for any reason
   → .devlog/devlog.md   (unchanged, fail-open — matches every other
                            hook script's posture in this plugin)
2. Current branch is `main` or `master` (case-insensitive)
   → .devlog/devlog.md   (backward compatible: existing projects and
                            their history are untouched)
3. Current branch resolves to a real name (git rev-parse --abbrev-ref HEAD
   returns something other than "HEAD")
   → .devlog/devlog.{sanitized-branch}.md
4. Detached HEAD (rev-parse returns literal "HEAD", no branch checked out)
   → .devlog/devlog.{sanitized-worktree-dirname}.md
   (basename of the working directory, same fallback spirit as #1)
```

**Sanitizing a name for use as a filename segment:** replace every
character that isn't `[A-Za-z0-9._-]` with `-` (this turns `/` into `-`,
so `feature/foo` → `devlog.feature-foo.md`), collapse repeated `-`, trim
leading/trailing `-`. This reuses the same flat `devlog.<name>.md`
namespace `/devlog-tracker:keep` and `/devlog-tracker:resume` already use
— a branch name that happens to collide with a manually-kept name (or
another branch's sanitized form) shares that one file. This is treated as
an accepted rare edge case, not specially guarded against.

## Origin marker

The sanitized filename can't be mapped back to a branch (`feat/x` and
`feat-x` both give `devlog.feat-x.md`), and it shares the
`devlog.<name>.md` namespace with kept files. So a branch file records
its origin as its first line:

```
<!-- devlog-origin: branch=feat/x -->
<!-- devlog-origin: detached=<worktree dirname> -->
```

`devlog_resolve_paths` exports it as `DEVLOG_ORIGIN` (empty for
`devlog.md`). It is written only when a branch file is created: prepended
to a migrated tail, or by `devlog_merge_round_current` when the target is
missing or empty. `devlog.md` never gets one, existing branch files are
not backfilled, and `keep-move.sh`'s full keep leaves it in place instead
of moving it with the project summary. `/devlog-tracker:keep-all` is the
consumer (see `docs/design/keep-all.md`).

## Carrying over the unfinished tail

The first time a non-default branch resolves to a `devlog.<name>.md` that
doesn't exist yet on disk, only the **unfinished tail** of
`.devlog/devlog.md` is **cut** (moved, not copied) into it: every
`## Round` block after the last one whose `### Status` is `DONE` (all
rounds, if none is `DONE`). `handoff.md` moves to `handoff.<name>.md`
along with it, since it snapshots that same unfinished work.

Nothing moves, and the branch starts with an empty file, when:

- the last Round in `devlog.md` is already `DONE` (or there are no Rounds);
- HEAD doesn't contain the local `main`/`master` tip
  (`git merge-base --is-ancestor`) — an older branch being checked out
  (e.g. to review it) rather than one just forked from the work in
  progress; or
- `.devlog/.enabled` is absent.

Everything that isn't a Round — the project header, `## Checkpoint`
sections (even ones sitting between moved Rounds), `## Kept 索引`,
`## Lessons 索引` — stays in `devlog.md`. Moved Rounds keep their numbers.

Why not move the whole file (the original design): `main` keeps using
`devlog.md`, so with no "already migrated" marker the wholesale rename
fired on *every* new branch, not once. Each new branch took all of
`main`'s history with it — project summary and indexes included — leaving
`main` with an empty `devlog.md`, scattering `main`'s history across
branch files that are abandoned after merge, and making
`/devlog-tracker:pr` on the new branch list Rounds that had nothing to do
with it. The only thing that genuinely belongs to a freshly cut branch is
the work that was still in progress on `main` when it was cut (the usual
`git checkout -b` with uncommitted changes); cutting rather than copying
keeps a single Handoff for that work, so the next `continue` can't pick
up the wrong file.

The cut happens under the existing `devlog-lock.sh` lock. The branch file
is written before `devlog.md` is rewritten, so a failure in between
duplicates the tail rather than losing it. While the branch file doesn't
exist yet, every hook re-resolves; the last Round's Status is checked
first so the common `DONE` case costs one short scan.

## `core/scripts/devlog-path.sh` (new file)

A new sourced helper, parallel to `devlog-md.sh` (content parsing) and
`devlog-lock.sh` (write serialization) rather than folded into either —
path resolution is its own concern and is easiest to unit-test in
isolation.

Provides one function:

```
devlog_resolve_paths <project_dir>
```

Side effect: sets (and leaves set in the caller's shell) `DEVLOG_DIR` and
`DEVLOG_FILE` following the algorithm above, performing the one-time
tail carry-over if applicable. Every script that currently hardcodes:

```sh
DEVLOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.devlog"
DEVLOG_FILE="$DEVLOG_DIR/devlog.md"     # or MAIN="$DEVLOG_DIR/devlog.md"
```

switches to:

```sh
. "$SCRIPT_DIR/devlog-path.sh"
devlog_resolve_paths "${CLAUDE_PROJECT_DIR:-.}"
```

and uses `$DEVLOG_FILE` (or assigns `MAIN="$DEVLOG_FILE"` where the
existing local variable is named `MAIN`) exactly as before. No caller
needs to know branch logic exists.

## Files touched

| File | Change |
|---|---|
| `core/scripts/devlog-path.sh` | **New.** `devlog_resolve_paths`, branch detection, sanitizing, unfinished-tail carry-over. |
| `core/scripts/tests/test-devlog-path.sh` | **New.** Unit tests: main/master passthrough, feature-branch mapping, slash sanitization, detached-HEAD fallback, non-git fallback, tail carry-over (DONE → nothing moves, unfinished tail + handoff cut, no-DONE, stale branch), no-op on second call. |
| `core/scripts/round-start.sh` | Replace hardcoded `DEVLOG_DIR`/`DEVLOG_FILE` with `devlog_resolve_paths`. |
| `core/scripts/enforce-devlog.sh` | Same. |
| `core/scripts/segment-watch.sh` | Same. |
| `core/scripts/session-start-devlog.sh` | Same. |
| `core/scripts/close-open-round.sh` | Same. |
| `core/scripts/pause-devlog.sh` | Same. |
| `core/scripts/checkpoint-set.sh` | Same. |
| `core/scripts/segment-watch-set.sh` | Same. |
| `core/scripts/lessons-on.sh` / `lessons-off.sh` / `lessons-append.sh` / `lessons-read.sh` | Same (each currently reads/writes `MAIN="$DEVLOG_DIR/devlog.md"` for the "## Lessons 索引" rebuild). |
| `core/scripts/keep-move.sh` | Same (`MAIN`). |
| `core/scripts/compact-devlog.sh` | Same (`MAIN`). |
| `core/scripts/clean-devlog.sh` | Same (`MAIN`). |
| `core/scripts/status-devlog.sh` | Same. |
| `core/scripts/span-open.sh` / `span-close.sh` | Same. |
| `core/scripts/on-tool-failure.sh` | Same. |
| `core/scripts/resume-devlog.sh` | Same (this script already computes a *different* `devlog.<name>.md` for an explicit `--name`; only its `DEVLOG_DIR` line is affected, not its own naming logic). |
| `core/scripts/await-open.sh` | Same. |
| `skills/devlog-tracker/SKILL.md` | Document branch-scoped file location under "檔案位置". |
| `README.md` | Mention branch-scoped devlog files where the four relaxation mechanisms / file layout are described. |

## Interaction with existing features

- **`.devlog/.enabled`, `.span-open`, `.checkpoint-state`,
  `.segment-watch-state`** stay single, project-wide files — enablement
  and mode state are not branch-scoped, only the devlog content file is.
  Switching branches mid-session does not turn recording off.
- **`devlog-lock.sh`**: the lock directory is `$DEVLOG_DIR/.lock`, one per
  project directory regardless of which branch file is being written —
  unchanged, still correct (it now also serializes the rare tail carry-over
  rename against concurrent writers).
- **`/devlog-tracker:keep` / `/devlog-tracker:resume` /
  `/devlog-tracker:lessons`**: unaffected, continue to operate on
  whichever file `DEVLOG_FILE` currently resolves to as their "source"
  (`MAIN`), same as today.
- **`.devlog/.round-open`**: now carries a `file` field naming the
  branch-scoped file it belongs to. `close-open-round.sh` ignores (leaves
  untouched) a `.round-open` whose `file` doesn't match the currently
  resolved `DEVLOG_FILE`, so switching branches between `round-start.sh`
  opening a round and the round closing can no longer stamp
  `INTERRUPTED` onto an already-finished Round in a different branch's
  file. A `.round-open` written before this guard existed (no `file`
  field) is treated leniently, same as before.
- **Tail carry-over** only fires while `.devlog/.enabled` is
  present, so read-only/informational commands (e.g.
  `/devlog-tracker:status`, `/devlog-tracker:lessons`) can't
  cut Rounds out of `devlog.md` on a project that
  was never `/devlog-tracker:start`-ed, or one that's currently
  `/devlog-tracker:pause`-d.

## Known Limitations

- Content written before this feature existed, if it mixes history from
  multiple branches, cannot be retroactively split — it stays in
  `devlog.md`, apart from any unfinished tail the first new branch cuts.
- Tail carry-over treats every non-`DONE` Round after the last `DONE` as
  belonging to the new branch. If `main` had unfinished work that the
  new branch isn't about, those Rounds still move; move them back by hand.
- Projects upgraded from the wholesale-rename version keep whatever was
  already renamed into branch files; nothing is moved back.
- Sanitized name collisions (two branches, or a branch and a manually
  `/keep`-saved name, mapping to the same `devlog.<name>.md`) share one
  file. Not detected or warned about — except for the two names this
  plugin already reserves for other purposes, `archive` and any name
  starting with `lessons.`, which fall back to the shared `devlog.md`
  instead of colliding with `devlog.archive.md` / `devlog.lessons.*.md`.
- Branch rename (`git branch -m old new`) is not tracked — old content
  stays under `devlog.old.md`; there's no automatic move on rename, only
  on first-use-with-no-file-yet.
- A branch name that sanitizes to an empty string (e.g. one made
  entirely of non-ASCII characters such as CJK) no longer silently
  shares `devlog.md`: it gets a stable, ASCII-safe `devlog.b-<hash>.md`
  derived from a checksum of the original name instead. The hash-derived
  filename isn't human-readable, so mapping it back to the branch it
  belongs to requires re-deriving the hash rather than reading it off
  the filename.
