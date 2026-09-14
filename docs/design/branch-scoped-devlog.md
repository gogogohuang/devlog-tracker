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

## One-time migration

The first time a non-default branch resolves to a `devlog.<name>.md` that
doesn't exist yet on disk, and `.devlog/devlog.md` already has content,
that existing `devlog.md` is **renamed** (not copied) to
`devlog.<name>.md` before use. Rationale: whatever is currently sitting in
`devlog.md` was written under *some* branch context — attributing it
wholesale to the branch currently checked out is a reasonable one-time,
best-effort call, and renaming (rather than copying) means the default
branch cleanly starts a fresh `devlog.md` next time it's checked out
instead of carrying a duplicate of another branch's history forward.

This is lossy if `devlog.md`'s existing content actually mixes multiple
branches' history from before this feature existed — that content can't
be retroactively split apart. Documented as a known limitation, not
solved.

The rename happens under the existing `devlog-lock.sh` mutual exclusion
(`devlog_with_lock`) to avoid a race between two concurrent hook
invocations both trying to migrate at once.

## `hooks/scripts/devlog-path.sh` (new file)

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
migration if applicable. Every script that currently hardcodes:

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
| `hooks/scripts/devlog-path.sh` | **New.** `devlog_resolve_paths`, branch detection, sanitizing, migration. |
| `hooks/scripts/tests/test-devlog-path.sh` | **New.** Unit tests: main/master passthrough, feature-branch mapping, slash sanitization, detached-HEAD fallback, non-git fallback, migration rename, migration is a no-op on second call. |
| `hooks/scripts/round-start.sh` | Replace hardcoded `DEVLOG_DIR`/`DEVLOG_FILE` with `devlog_resolve_paths`. |
| `hooks/scripts/enforce-devlog.sh` | Same. |
| `hooks/scripts/segment-watch.sh` | Same. |
| `hooks/scripts/session-start-devlog.sh` | Same. |
| `hooks/scripts/close-open-round.sh` | Same. |
| `hooks/scripts/pause-devlog.sh` | Same. |
| `hooks/scripts/checkpoint-set.sh` | Same. |
| `hooks/scripts/segment-watch-set.sh` | Same. |
| `hooks/scripts/lessons-on.sh` / `lessons-off.sh` / `lessons-append.sh` / `lessons-read.sh` | Same (each currently reads/writes `MAIN="$DEVLOG_DIR/devlog.md"` for the "## Lessons 索引" rebuild). |
| `hooks/scripts/keep-move.sh` | Same (`MAIN`). |
| `hooks/scripts/compact-devlog.sh` | Same (`MAIN`). |
| `hooks/scripts/clean-devlog.sh` | Same (`MAIN`). |
| `hooks/scripts/status-devlog.sh` | Same. |
| `hooks/scripts/span-open.sh` / `span-close.sh` | Same. |
| `hooks/scripts/on-tool-failure.sh` | Same. |
| `hooks/scripts/resume-devlog.sh` | Same (this script already computes a *different* `devlog.<name>.md` for an explicit `--name`; only its `DEVLOG_DIR` line is affected, not its own naming logic). |
| `hooks/scripts/await-open.sh` | Same. |
| `skills/devlog-tracker/SKILL.md` | Document branch-scoped file location under "檔案位置". |
| `README.md` | Mention branch-scoped devlog files where the four relaxation mechanisms / file layout are described. |

## Interaction with existing features

- **`.devlog/.enabled`, `.span-open`, `.checkpoint-state`,
  `.segment-watch-state`** stay single, project-wide files — enablement
  and mode state are not branch-scoped, only the devlog content file is.
  Switching branches mid-session does not turn recording off.
- **`devlog-lock.sh`**: the lock directory is `$DEVLOG_DIR/.lock`, one per
  project directory regardless of which branch file is being written —
  unchanged, still correct (it now also serializes the rare migration
  rename against concurrent writers).
- **`/devlog-tracker:keep` / `/devlog-tracker:resume` /
  `/devlog-tracker:lessons`**: unaffected, continue to operate on
  whichever file `DEVLOG_FILE` currently resolves to as their "source"
  (`MAIN`), same as today.

## Known Limitations

- Content written before this feature existed, if it mixes history from
  multiple branches, cannot be retroactively split — the one-time
  migration attributes all of a pre-existing `devlog.md` to whichever
  branch first triggers migration.
- Sanitized name collisions (two branches, or a branch and a manually
  `/keep`-saved name, mapping to the same `devlog.<name>.md`) share one
  file. Not detected or warned about.
- Branch rename (`git branch -m old new`) is not tracked — old content
  stays under `devlog.old.md`; there's no automatic move on rename, only
  on first-use-with-no-file-yet.
