# Agent adapters

## Objective

Let crew support agent CLIs other than Claude Code through one adapter per agent, so adding a CLI means writing one file instead of spreading `if claude` checks.

## Problem

Claude specifics live in six places: `workspace.open` (hook injection), `workspace.resume` (sessions picker or args), `persist.restore` (resume by id), `health` (status line check), `picker.sessions` (session list) and `hooks.command` (basename detection). The Claude config dir is computed twice (`sessions.lua`, `hooks.lua`). Every new CLI would add another branch to each of them.

## Why

The user wants Antigravity (`agy`), Codex and Gemini next to Claude. Research of 2026-11-05 (feature doc `odd/tasks/crew.md`, item F3) showed each CLI injects hooks, stores sessions and resumes differently, so they share a contract, not behaviour.

## Scope

- One contract per agent with optional capabilities. A `plain` adapter implements none and is the fallback for any CLI.
- A profile picks its adapter with `adapter = "<name>"`, else crew detects it from the basename of `cmd[1]`.
- Claude moves behind the contract with no behaviour change.
- Antigravity (`agy`) is the second adapter, since it is installed and testable.

Out of scope: Codex and Gemini adapters (not installed, cannot be tested), state pills for agy (its hooks and status line only exist in global config).

## Constraints

- Composition, not inheritance, as in sidekick.nvim (`sk/cli/{tool}.lua`) and CodeCompanion (`adapters.extend`).
- The existing suite is the safety net for the Claude move: it must stay green without editing assertions.
- Undocumented formats degrade to empty fields, never errors.

## Tasks

- [x] **A1 Contract and resolution.** `lua/crew/adapters/init.lua` resolves the adapter of a profile (explicit `adapter`, else basename, else `plain`). Contract fields, all optional: `prepare(cmd, agent, ws)` returns the final cmd and extra env (hooks, status line), `resume_args(id)` returns args for one session or, with nil, for the CLI's own picker, `sessions(agent, cwd)` lists sessions for crew's picker, `health(agent)` reports checks. Test first.
- [x] **A2 Claude adapter.** `lua/crew/adapters/claude.lua` wraps `crew.hooks` and `crew.sessions`. `workspace`, `persist`, `picker` and `health` call the adapter; every `basename == "claude"` check goes away; the config dir is computed once. No behaviour change: the current suite stays green as is, plus adapter tests.
- [x] **A3 Antigravity adapter.** `resume_args` uses `--conversation <id>` (verified in `agy --help`). `sessions` reads `conversation_summaries.db` (title, preview, workspace) if its schema checks out and `sqlite3` is available, else the adapter offers no picker and `<leader>aN` opens agy's own `/resume`. Verify the schema and paths locally before writing.
- [ ] **A5 agy state and usage bridge.** Deferred by the user on 2026-11-05, next step after this PR. agy only reads its statusLine from global config; a crew bridge script set there once would forward `agent_state`, `tool_confirmation_pending`, `context_window.used_percentage` and `quota` to Neovim inside crew and chain the user script outside. Capture a real stdin sample first, the format is not fully documented. Also covers two gaps found on 2026-11-05: (1) agy agents never get a `session_id` (crew only learns it from Claude hooks), so restore reopens agy fresh instead of resuming; the statusLine `conversation_id` fixes it, with `cache/last_conversations.json` (latest conversation per workspace) as a fallback for one agy per directory. (2) The sessions picker cannot hide agy conversations open in another tab.
- [x] **A6 One picker for every profile.** Found by the user on 2026-11-05: with `agy` added and no `default_agent`, alphabetical order made agy the default, so `<leader>aN` hid Claude. Now several profiles with sessions share one picker with a profile column; shared config dirs dedupe by adapter and id. Route inline, test first (4 RED, then green), commit 76076d4. Checked against real data from `~/.config/nvim`: Claude and agy sessions side by side.
- [x] **A4 Docs.** README section "Claude Code only, for now" becomes a table of adapters and capabilities; `:help crew` documents the `adapter` option.

## Acceptance criteria

- `make test` green after each task, with the A2 move leaving existing assertions untouched.
- A profile `agy = { cmd = { "agy" } }` resumes with `--conversation <id>` and restores after a restart.
- A profile with an unknown CLI behaves as today (tab, pills, send, no state).

## Checks

`make test` per task (mini.test). No linter or formatter is configured in the repo.

## Delivery

Forecast about 500 authored changed lines (A1 plus A2 about 250, A3 about 200, A4 about 60), over the 400 line budget. Strategy `single-pr`, chosen by the user on 2026-11-05 (personal project, no review split needed).

## Progress

- 2026-11-05: branch `refactor/adapters` created from `feat/workspaces` after pushing it. Feature doc created. Engram mirror pending: Engram rejects writes for this session ("host session already ended").
- 2026-11-05: A1 to A4 built by one delegated writer, test first (A1 and A2: 11 of 12 RED; A3: 7 RED; A4 passive docs). One existing test pinned to `adapter = "claude"` because it used `sh` as a stand in and plain profiles no longer get `CREW_STATUSLINE`; the assertion is unchanged. Full suite green. agy sessions checked read only against the real db (schema matches, percent encoded path resolves). Commits: cf03032 refactor, 990289e feat, c72d9f1 docs.

## Next step

Choose the PR base (one PR against main with all of feat/workspaces, or stacked), then open it. Also done on this branch: `statusline = false` profile option (9e28cd9).
