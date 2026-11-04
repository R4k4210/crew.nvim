# crew.nvim

Run every AI agent from one Neovim, each one in its own full window workspace.

- Locator: `odd/tasks/crew.md` (Engram mirror: `odd/crew/tasks`, project `neovim-config`)
- Mockup: `docs/mockup.html` (live copy at https://claude.ai/artifact/RGdVZgcU7SQtokiyUgxVEp)
- Target: Neovim 0.12+, lazy.nvim, lualine, bufferline, neo-tree, snacks
- Delivery strategy: `ask-on-risk`. Commits only when the user asks for them.

## Objective

This section states what the plugin must achieve once it is finished. Moving between the code and any number of agents takes one key, every agent renders at full size, and the statusline tells you which agent is working, which one is waiting on you and which one is done. The user stops juggling separate terminals in AeroSpace.

## Problem and why

Current AI plugins treat the agent as a split, which forces the editor and the chat to share columns. Avante also centers the workflow on reviewing diffs one by one, a habit that matters less now that agents follow good skills and rules. Sidekick is the most comfortable option so far, yet the agent window is still either too small to read or large enough to hide the code. The result is many terminal instances managed by hand.

## Scope

The plugin covers agent workspaces, keymaps, a lualine component, agent state, a picker and usage meters. Anything about reviewing diffs, inline edits or chat UIs stays out, since the agent CLI already owns that experience.

## Constraints

- The plugin never imports the user config. It defines its own highlight groups with `default = true` and the user config paints them with OneDark Deep.
- Keys use a `<C-,>` prefix in normal and terminal mode, plus direct `<C-1..9>` jumps, so `jk` (terminal exit) and `<leader>` keep working. `Tab` is never mapped because Claude Code uses it.
- Lualine pills show only the number and a state icon. Names live in the picker.
- Neo-tree and the buffer list belong to workspace 1 only.
- Profiles (`claude` and `claude-work`) are first class, because rate limits belong to the account.

## Lessons and tasks

Each lesson leaves a working plugin and teaches one concept. Work happens together with the user, one lesson at a time.

- [x] **L1 Skeleton.** Repo layout (`lua/crew/init.lua`, `plugin/crew.lua`), `setup(opts)` merging defaults with `vim.tbl_deep_extend`, a `:Crew` command and loading it with lazy `dir =`. Concept: how Neovim finds plugins through `runtimepath` and why `plugin/` runs on startup while `lua/` runs on `require`.
  - Accept: `:Crew` prints the merged config, and editing a file plus `:Lazy reload crew.nvim` picks up the change.
- [x] **L2 Workspaces.** One tabpage per agent with a single terminal window started through `jobstart(cmd, { term = true })`. A state module tracks workspaces and exposes `open`, `goto`, `toggle` and `close`. Concept: tabpages, windows and buffers as three different things.
  - Accept: two agents open in tabs 2 and 3, closing one keeps the numbering stable and neo-tree never appears in an agent tab.
- [x] **L3 Keymaps.** The `<C-,>` prefix and direct `<C-1..9>` jumps in `n` and `t` modes, overridable from `opts.keys`. Concept: keymap modes and why terminal mode needs its own mappings.
  - Accept: every action works from inside a running agent without leaving insert mode first.
- [ ] **L4 Pills API and adapters.** `crew.status` owns the data (`list()`) and the pill format (`pills()`), shown as number plus state icon (`?` for ask, `●` work, `✓` done, from `opts.icons`). Two thin adapters render the same pills: `require("crew.bufferline").right` for `custom_areas` (with `show_tab_indicators = false`) and a native lualine component used as `"crew"`. Route: inline, teaching session continuing L1 to L3 with the code already loaded. Concept: a data core with ports per consumer, statusline expressions, highlight groups and `default = true` links.
  - Accept: pills render in the user lualine with OneDark Deep colors set from the user config only.
- [ ] **L5 Agent state.** Each agent gets `CREW_WS` in its environment. Claude Code hooks (`UserPromptSubmit`, `Notification`, `Stop`) call `nvim --server "$NVIM" --remote-expr` to report `work`, `ask` or `done`. A toast appears when an agent waits on input. Concept: RPC between a child process and Neovim.
  - Accept: a permission prompt in workspace 3 turns its pill orange and pulses it while the user is in the editor.
- [ ] **L6 Picker.** A snacks picker listing workspaces with a live preview of the terminal tail, plus a `vim.ui.select` fallback. Concept: optional dependencies.
  - Accept: `<C-,>p` lists every workspace, `enter` jumps and `x` closes.
- [ ] **L7 Usage meters.** A statusLine script forwards `context_window.used_percentage` and `rate_limits.five_hour` / `seven_day` to Neovim. Agent tabs show ctx, 5h and week bars with reset times. Concept: designing for missing data, since `rate_limits` arrives after the first response.
  - Accept: bars update per session for ctx and per profile for limits, and render empty without errors before data exists.
- [ ] **L8 Header in agent tabs.** Bufferline (or a winbar fallback) shows agent name, cwd, branch and the meters inside agent tabs.
  - Accept: matches the mockup header and returns to the buffer list in workspace 1.
- [ ] **L9 Quality and publish.** Tests with `mini.test`, `:checkhealth crew`, `doc/crew.txt`, README, GitHub repo `R4k4210/crew.nvim` with topics.
  - Accept: tests pass in CI and the plugin installs from `"R4k4210/crew.nvim"`.
- [ ] **L10 Replace Sidekick.** Swap Sidekick for crew.nvim in the user config.
  - Accept: daily work runs from one terminal for a full day.

## Progress

- 2026-11-03: name chosen (`crew.nvim`), repo folder created, mockup saved, plan written. Git initialized with no commits yet.
- 2026-11-03: L1 files written (`lua/crew/config.lua`, `lua/crew/init.lua`, `plugin/crew.lua`) plus the lazy spec at `~/.config/nvim/lua/r4k4210/plugins/crew.lua` (route: inline, 4 small files). Verified in `nvim --clean` with `rtp^=.` that setup merges `claude-work` with the default `claude` and that `:Crew` exists. Pending: running `:Crew` and `:Lazy reload crew.nvim` inside the real config, because the full config hangs when run headless.

- 2026-11-03: L2 written (`lua/crew/workspace.lua`, `lua/crew/commands.lua`, `plugin/crew.lua` with `:Crew` subcommands and a `TabClosed` prune, `default_agent` in config). Route: inline, teaching session with context already loaded. `:Crew` alone now lists workspaces and `:Crew config` prints the config. Verified with a 15 check headless script using fake `sh` agents (slots, toggle, close, slot reuse, manual `:tabclose`, agent exit, completion), all PASS. Pending: trying it with real `claude` inside the user config. The function is `jump`, since `goto` is a reserved word in LuaJIT.

- 2026-11-03: L3 written (`lua/crew/keymaps.lua`, `keys.stopinsert` in config, `attach(buf)` on open, setup wires keymaps). Prefix actions are `<Space>` toggle, `n` new agent (asks with `vim.ui.select` when there are several profiles), `x` close, `1..9` jump, mapped in `n` and `t` for both `<C-Space>` and `<C-@>`. The user config sets `stopinsert = "jk"`. Verified by driving a real headless Neovim over RPC with `--remote-send` (13 checks pass; `mode()` returns `n` for `nt`) and L2 still passes 15 of 15. Lesson learned: `feedkeys` with the `x` flag hangs once it reaches terminal mode, so terminal tests go through RPC.
- Known bugs for L8: the bufferline close icon (`%999X`) closes the current tab, so clicking it in the editor tab leaves `home` invalid. Fix with `show_close_icon = false` and by adopting another tab as home. Also, `agents` merges with the default `claude`, so a user cannot remove it yet.

- 2026-11-03: The user verified L1 to L3 by hand in their real config with real `claude` (open, `jk` to normal mode, toggle, jump, close all work). The `<C-Space>` prefix never reaches Neovim because macOS binds Ctrl+Space to "select previous input source", so the prefix must change. Proposed: `<C-,>` as prefix (free once Sidekick goes; Codeium was removed from the user config) plus direct `<C-1..9>` jumps, which need the kitty keyboard protocol (Ghostty yes, tmux/Zellij only with extended keys).
- 2026-11-03: Prefix moved to `<C-,>` and `keys.jump = "<C-%d>"` added (direct jumps in `n` and `t`, `false` disables). The `<C-1>` test with `<C-v>` passed in the user Ghostty. Sidekick lost its `<C-,>` toggle (kept `<leader>aa`) to avoid a prefix clash. Verified headlessly that `<C-1..9>` and the `<C-,>` actions register in `n` and `t`.
- 2026-11-03: Bug found by the user: `<C-2>` landed on the third tab. Cause: `:tabnew` opens next to the current tab, so opening a second agent from the editor put slot 3 before slot 2. Fix in `workspace.lua` (`tab_before`): open with `:Ntabnew` after the nearest lower slot or the home tab. RED then GREEN with a 10 check headless test (open from editor, open from agent, reuse a freed slot).
- 2026-11-03: Decision by the user: slots compact when a workspace closes (closing 2 turns 3 into 2 and 4 into 3), so `<C-N>` always matches tab N. Tradeoff accepted: an agent no longer keeps a fixed number. `compact()` runs at the end of `remove()`, covering `:Crew close`, agent exit and manual `:tabclose`, and `last` follows the moved agent. RED then GREEN, 20 of 20 checks.

- 2026-11-03: L1 to L3 committed on `feat/workspaces` (signed): `d57247e` chore, `8453db1` docs, `252110c` feat.

- 2026-11-03: L4 committed as `3d6d31b` (signed). Headless check 17 of 17 (pills, icons, highlights surviving `:colorscheme`, bufferline items, lualine output, compaction). User config wired: bufferline gets `show_tab_indicators = false` plus `custom_areas.right`, its `config` now passes `opts` (they were dropped before, so `slant` never applied), lualine gets `ins_left({ "crew" })` and depends on `crew.nvim` for load order. Pending: the user checks it visually.

- 2026-11-03: Bug found by the user: `<C-,>n` gave `E486: Pattern not found`. Cause: a chord only waits `timeoutlen` (300 ms in the user config) for its second key, then `n` runs alone as search next. Reproduced over RPC with a 600 ms gap. Decision by the user: no chords. `<C-,>` alone toggles (n, t), `<leader>cn` is crew-new and `<leader>ce` is crew-exit (n only, so Space still reaches the agent), `<C-1..9>` stay. Jumping to an empty slot is now silent. Headless check 10 of 10 plus L4 17 of 17. Note: the user config maps `<leader>c` alone to Delete Buffer, so a slow `<leader>c…` relies on which-key holding the key; which-key does not run headless, so that path needs a manual check.

- 2026-11-03: Defaults moved to `<leader>an` (crew-new) and `<leader>ax` (crew-exit), since `<leader>c` collided with the user Delete Buffer. Sidekick removed from the user config early (L10 partly done; backup of its uncommitted spec kept in the session scratchpad). The user crew spec now passes `--settings {"tui":"default"}` to both claude profiles (fullscreen TUI keeps no scrollback in a terminal buffer) and maps `<leader>aa` to `:Crew toggle` through lazy `keys`. Lost with Sidekick: send this, file, selection and prompt. Pending: the user `<leader>c` reorganization (Delete Buffer to `<leader>x`, Rename File to `<leader>fR`) awaits confirmation.

## Next step

User checks the L4 pills in bufferline and lualine, then OneDark Deep colors for `CrewPill*` and L5 agent state.
