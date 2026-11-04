# crew.nvim

Run several AI coding agents inside Neovim with each one in its own tab while always knowing which one needs you. crew treats agents the way a tiling window manager treats desktops, so Claude Code gets the full screen while small pills in your tabline and statusline tell you who is working, who is waiting on an answer and who is done.

crew is opinionated. The defaults reflect one specific workflow (Claude Code, snacks, bufferline and lualine on macOS), but every key, icon and color can be changed or turned off.

![Editor tab with workspace pills in bufferline and lualine](docs/images/editor.png)

## The idea

This section explains why agents live in tabs instead of splits. A split shares its columns with your code, so the agent renders cramped and every resize redraws its interface. A tab gives the agent the whole screen while your editor layout stays untouched in tab 1 where one key brings you back.

Slot 1 is always your editor and slots 2 to 9 are agent instances. When an instance closes, the ones after it move down, so `<C-3>` always means the third tab you see.

![An agent tab asking for permission](docs/images/agent.png)

## Requirements

This section lists what crew needs and what it uses when available.

- Neovim 0.11 or newer
- A terminal with the kitty keyboard protocol (Ghostty, kitty, WezTerm) for `<C-,>` and `<C-1>` to `<C-9>`, since legacy terminals cannot tell those keys apart
- Optional plugins that crew plugs into when present, namely [snacks.nvim](https://github.com/folke/snacks.nvim) for the pickers, [bufferline.nvim](https://github.com/akinsho/bufferline.nvim) and [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) for the pills

Without snacks the pickers fall back to `vim.ui.select`, which keeps everything usable on a plain setup.

## Installation

The snippet below installs crew with [lazy.nvim](https://github.com/folke/lazy.nvim) and two Claude profiles. Load it eagerly so the lualine component and the hooks are ready when Neovim starts.

```lua
{
  "R4k4210/crew.nvim",
  lazy = false,
  opts = {
    agents = {
      claude = { cmd = { "claude" } },
      ["claude-work"] = {
        cmd = { "claude" },
        env = { CLAUDE_CONFIG_DIR = vim.fn.expand("~/.claude-work") },
      },
    },
  },
}
```

Your `agents` table replaces the default one, so list every profile you want to pick from. Any CLI works as an agent while Claude Code agents also report their state back to Neovim.

## Keys

All keys live under `<leader>a` except the tab switching ones, which need to work from inside a running agent.

| Key | Mode | Action |
|---|---|---|
| `<C-,>` | normal, terminal | Toggle between the editor and the last agent |
| `<C-1>` to `<C-9>` | normal, terminal | Jump to a slot, silently ignored when it is empty |
| `<leader>an` | normal | New instance, picking a profile when there are several |
| `<leader>ap` | normal | Pick an open instance |
| `<leader>ai` | normal | Name the current instance |
| `<leader>ax` | normal | Close the current instance |
| `<leader>af` | normal | Send `@path` of the current file, picking the instance |
| `<leader>aF` | normal | Send the current file to the last instance |
| `<leader>av` | visual | Send the selected lines with their location, picking the instance |
| `<leader>aV` | visual | Send the selection to the last instance |

Leader keys only exist in normal and visual mode because inside an agent your space bar has to reach the agent. Leave terminal mode with `<C-\><C-n>` or with the key you set in `stopinsert`.

### Changing keys

Every entry in `opts.keys` takes a key string or `false` to turn it off. The example below moves the group to `<leader>c` and disables the direct jumps.

```lua
opts = {
  keys = {
    toggle = "<C-,>",
    new = "<leader>cn",
    close = "<leader>cx",
    pick = "<leader>cp",
    rename = "<leader>ci",
    send_file = "<leader>cf",
    send_file_last = "<leader>cF",
    send_selection = "<leader>cv",
    send_selection_last = "<leader>cV",
    jump = false, -- or any format with %d, e.g. "<A-%d>"
    stopinsert = "jk", -- leave terminal mode inside agents
  },
}
```

To map things yourself, set the keys to `false` and call the commands listed below.

## Pickers

crew opens its own snacks pickers with no preview window, so your global picker layout keeps its file preview everywhere else. The instance picker shows the slot, profile and name of each instance next to its usage.

![The instance picker](docs/images/picker.png)

Names are optional labels you set with `<leader>ai`. They appear in the picker and never in the pills, which keeps the pills one or two cells wide however long the name is.

## Agent state

Claude Code instances report their state through hooks that crew injects through the `--settings` flag of each Claude agent, so your own `settings.json` is never touched. If your command already passes `--settings`, crew merges its hooks into it and keeps yours.

| Pill | Meaning | Clears when |
|---|---|---|
| `●` | The agent is working | It stops or asks |
| `?` | The agent waits on you, for example a permission prompt | You answer |
| `✓` | The agent finished | You visit its tab |

A waiting agent also blinks its pill and shows a notification when you are in another tab. Each hook runs a small Lua script that talks to Neovim through `$NVIM` and always exits cleanly, so a broken hook can never block Claude. Set `hooks = false` on an agent to opt out.

## Pills in bufferline and lualine

crew ships one adapter per plugin and leaves the wiring to you, so it never changes another plugin behind your back. Use either one or both.

```lua
-- bufferline: pills replace the tab numbers on the right
options = {
  show_tab_indicators = false,
  custom_areas = {
    right = function()
      return require("crew.bufferline").right()
    end,
  },
}

-- lualine: a native component
sections = { lualine_c = { "crew" } }
```

Pills use the highlight groups `CrewPill`, `CrewPillCurrent`, `CrewPillWork`, `CrewPillAsk`, `CrewPillAskBlink` and `CrewPillDone`. They are linked to standard groups with `default = true`, so they follow your colorscheme and any `nvim_set_hl` call of yours wins.

## Commands

Everything the keys do is also available as a subcommand of `:Crew`, which helps when you prefer your own mappings.

```
:Crew open [profile]   :Crew new        :Crew pick
:Crew jump N           :Crew toggle     :Crew close [N]
:Crew rename [name]    :Crew list
```

## Status

crew is young and changes often. The usage columns in the instance picker show a dash until the usage feed from the Claude Code status line lands. Health checks, help docs and tests are on the way.

## Mockup

[docs/mockup.html](docs/mockup.html) is an interactive mockup of the whole workflow drawn within what a terminal grid can show. Open it in a browser and use the keys listed on the page.
