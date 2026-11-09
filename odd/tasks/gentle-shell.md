# Gentle Shell adapter

## Objective

Run Gentle Shell (`gentle-shell --link`, a Pi coding agent) as a crew agent with live status pills, session resume and restore after a restart.

## Problem and why

crew only knows Claude Code and agy, so a Gentle Shell profile falls back to plain and its pill never changes state. Gentle Shell forwards every extra argument to `pi`, which lets crew inject its own session id and a status extension per invocation without touching global config.

## Design

The adapter launches Pi with `--session-id <id>` so each tab owns its session from the start. A small Pi extension loaded with `-e` maps Pi events onto the existing hook transport (`scripts/hook.lua`), so state arrives by push like Claude's hooks.

- `agent_start` reports `UserPromptSubmit` (work)
- `ui_prompt_start` reports `Notification` (ask)
- `ui_prompt_end` reports `PostToolUse` (work)
- `agent_settled` reports `Stop` (done)
- every report carries `session_id`

Resume uses `--session <id>`, and `-r` opens Pi's own picker. Sessions are read from `~/.pi/agent/sessions/`, degrading to `{}` on any unknown format. No usage meters, since claude-bridge usage lives in response headers crew cannot see.

## Scope and constraints

- Allowed: new adapter module, extension script, `M.known` registration, config comment, README, `doc/crew.txt`, new tests
- Existing tests stay green without editing their assertions
- Undocumented formats degrade quietly, never raise
- Pre-existing uncommitted change in `odd/tasks/crew.md` is not ours and is left untouched

## Tasks

- [x] G1 Adapter skeleton: registration, `prepare` (session id plus `-e` extension plus env), `resume_args` (route: delegated writer, commit recorded under progress)
- [x] G2 Status extension script and wiring to `scripts/hook.lua` (route: delegated writer, commit recorded under progress)
- [x] G3 Sessions listing and `last_session` from the linked `~/.pi/agent` or isolated `~/.gentle-shell/agent` home (route: delegated writer, commit recorded under progress)
- [ ] G4 Health check, docs (README, `doc/crew.txt`, config comment) (route: delegated writer)

## Acceptance criteria

- `make test` green after each task
- A `gentle-shell` profile resolves to the new adapter by `cmd[1]` basename
- Resume by id and restore after restart work
- Pills move through work, ask and done from real Pi events

## Checks

- `make test`, single file with `make test_file FILE=tests/<file>.lua`

## Progress

- Branch `feat/gentle-shell-adapter` created from `main`
- G1 done in `407c849`: adapter registration, `prepare`, `resume_args`; `make test` 260 cases green
- G2 done: `scripts/pi_status.js` maps Pi events to hook events, tested with a fake Pi and a fake nvim through node; `make test` 264 cases green
- G2 committed in `7572391`
- G3 done: sessions resolve the agent home from the profile (`--link` or `pi` use `~/.pi/agent`, else `~/.gentle-shell/agent`), honoring `PI_CODING_AGENT_SESSION_DIR`, `PI_CODING_AGENT_DIR` and `GENTLE_SHELL_HOME`; smoke read of real sessions listed 2; `make test` 271 cases green
