# Optimization plans (0.4.0 follow-ups)

Index for the plans that implement the 2026-09-09 review of `main` @ `29e16b5`.
This repo gitignores `docs/superpowers/`; plans live under `docs/design/`.

Do **not** implement the "don't do" list (re-inject on `/clear`, empty startup, scoring Summary prose, agentflow SDD, auto compact, transcript parse, instant Esc).

## Version numbers

Ship **all thirteen plans in one batch**. Do **not** bump version inside any feature plan.

After every feature plan is done, run [`version-0.5.0-plan.md`](version-0.5.0-plan.md) once: `0.4.0` → **`0.5.0`** in all three files:

- `.claude-plugin/plugin.json` → `"version"`
- `.claude-plugin/marketplace.json` → `plugins[0].version`
- `README.md` → first paragraph `版本 \`0.5.0\``

Do not bump to 0.4.1, 0.6.0, or any other intermediate number.

## Execution order

| # | Plan |
|---|---|
| 1 | [`skill-and-docs-plan.md`](skill-and-docs-plan.md) |
| 2 | [`start-pause-scripts-plan.md`](start-pause-scripts-plan.md) |
| 3 | [`hook-json-helper-plan.md`](hook-json-helper-plan.md) |
| 4 | [`session-start-excerpt-plan.md`](session-start-excerpt-plan.md) |
| 5 | [`heading-substance-plan.md`](heading-substance-plan.md) |
| 6 | [`compact-keep-scripts-plan.md`](compact-keep-scripts-plan.md) |
| 7 | [`ci-hook-tests-plan.md`](ci-hook-tests-plan.md) |
| 8 | [`status-and-span-commands-plan.md`](status-and-span-commands-plan.md) |
| 9 | [`keep-resume-plan.md`](keep-resume-plan.md) |
| 10 | [`segment-watch-subagent-plan.md`](segment-watch-subagent-plan.md) |
| 11 | [`prompt-redact-plan.md`](prompt-redact-plan.md) |
| 12 | [`devlog-file-lock-plan.md`](devlog-file-lock-plan.md) |
| 13 | [`cursor-hooks-plan.md`](cursor-hooks-plan.md) |
| 14 | [`version-0.5.0-plan.md`](version-0.5.0-plan.md) — **only version bump** |

Each feature plan is self-contained (TDD, exact files, exact commands). Prefer subagent-driven-development or executing-plans. One PR, one version.
