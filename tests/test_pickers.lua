-- Pickers through the vim.ui.select fallback, rename and aligned rows.
local H = dofile("tests/helpers.lua")
local eq, match = H.eq, H.match
local child, T = H.new()

local function setup()
	child.lua([[
		vim.g.mapleader = " "
		require("crew").setup({ agents = { sh = { adapter = "claude", cmd = { "sh" }, hooks = false }, zsh = { adapter = "claude", cmd = { "sh" }, hooks = false } }, default_agent = "sh" })
		ws = require("crew.workspace")
		picker = require("crew.picker")
	]])
end

-- zsh is agent 1 through picker.new, sh is agent 2 (current).
local function open_two()
	setup()
	child.lua([[
		vim.ui.select = function(items, opts, on_choice)
			shown = vim.tbl_map(opts.format_item, items)
			on_choice(items[2])
		end
		picker.new()
		ws.open("sh")
	]])
end

local function desc(lhs)
	return child.lua_get('vim.fn.maparg(..., "n", false, true).desc', { lhs })
end

T["keys"] = function()
	setup()
	eq(desc("<leader>ap"), "crew-pick")
	eq(desc("<leader>ai"), "crew-rename")
	eq(desc("<leader>an"), "crew-new")
end

T["new"] = MiniTest.new_set()

T["new"]["lists only the configured profiles, sorted"] = function()
	open_two()
	eq(child.lua_get("shown"), { "sh", "zsh" })
end

T["new"]["opens the chosen profile"] = function()
	open_two()
	eq(child.lua_get("ws.workspaces[1].agent"), "zsh")
end

T["rename"] = MiniTest.new_set()

T["rename"]["prompt names the slot and sets the name"] = function()
	open_two()
	child.lua([[
		vim.ui.input = function(opts, on_confirm) prompt = opts.prompt; on_confirm("cuca") end
		picker.rename()
	]])
	match(child.lua_get("prompt"), "2", true)
	eq(child.lua_get("ws.workspaces[2].name"), "cuca")
	eq(child.lua_get('require("crew.status").list()[3].name'), "cuca")
end

T["rename"]["empty name clears it"] = function()
	open_two()
	child.lua([[
		ws.workspaces[2].name = "cuca"
		vim.ui.input = function(_, on_confirm) on_confirm("") end
		picker.rename()
	]])
	eq(child.lua_get("ws.workspaces[2].name"), vim.NIL)
end

T["rename"]["cancel keeps the name"] = function()
	open_two()
	child.lua([[
		ws.workspaces[2].name = "keep"
		vim.ui.input = function(_, on_confirm) on_confirm(nil) end
		picker.rename()
	]])
	eq(child.lua_get("ws.workspaces[2].name"), "keep")
end

T["rename"][":Crew rename sets a name with spaces"] = function()
	open_two()
	child.lua('vim.cmd("Crew rename ops analysis")')
	eq(child.lua_get("ws.workspaces[2].name"), "ops analysis")
end

T["rename"]["does nothing in the editor"] = function()
	open_two()
	child.lua([[
		ws.editor()
		called = false
		vim.ui.input = function() called = true end
		picker.rename()
	]])
	eq(child.lua_get("called"), false)
end

T["pick"] = MiniTest.new_set()

-- Agent 1 asks and has usage, agent 2 is named and has none; pick chooses row 2.
local function pick_rows()
	open_two()
	child.lua([[
		vim.cmd("Crew rename ops analysis")
		ws.editor()
		ws.workspaces[1].state = "ask"
		ws.workspaces[1].usage = {
			ctx = 71,
			five_hour = { pct = 87, resets_at = os.time() + 47 * 60 + 30 },
			seven_day = { pct = 23, resets_at = os.time({ year = 2026, month = 11, day = 26, hour = 18, min = 0 }) },
		}
		vim.ui.select = function(items, opts, on_choice)
			shown = vim.tbl_map(opts.format_item, items)
			on_choice(items[2])
		end
		picker.pick()
	]])
	return child.lua_get("shown")
end

T["pick"]["lists only open instances"] = function()
	eq(#pick_rows(), 2)
end

T["pick"]["row has slot, profile and usage"] = function()
	local row = pick_rows()[1]
	match(row, "^1  zsh")
	match(row, "ctx  71%%")
	match(row, "5h  87%% ↻ 47m")
	match(row, "wk  23%% ↻ nov 26 18:00")
end

T["pick"]["row ends with the ask icon"] = function()
	match(pick_rows()[1], "%?$")
end

T["pick"]["the state icon is apart from the reset date"] = function()
	match(pick_rows()[1], "18:00 %?$")
end

T["pick"]["row has its name and dashes for missing usage"] = function()
	local row = pick_rows()[2]
	match(row, "ops analysis", true)
	match(row, "ctx    –", true)
end

T["pick"]["an agy row leaves the 5h cell blank and stays aligned"] = function()
	child.lua([[
		require("crew").setup({ agents = {
			c = { adapter = "claude", cmd = { "sh" }, hooks = false },
			g = { adapter = "agy", cmd = { "sh" } },
		}, default_agent = "c" })
		ws, picker = require("crew.workspace"), require("crew.picker")
		ws.open("c"); ws.open("g"); ws.editor()
		vim.ui.select = function(items, opts) shown = vim.tbl_map(opts.format_item, items) end
		picker.pick()
	]])
	local rows = child.lua_get("shown")
	match(rows[1], "5h", true)
	eq(rows[2]:find("5h", 1, true), nil)
	local function col(s, pat)
		return vim.fn.strdisplaywidth(s:sub(1, s:find(pat, 1, true) - 1))
	end
	eq(col(rows[1], " wk"), col(rows[2], " wk"))
end

T["pick"]["only agy rows drop the 5h column"] = function()
	child.lua([[
		require("crew").setup({ agents = { g = { adapter = "agy", cmd = { "sh" } } } })
		ws, picker = require("crew.workspace"), require("crew.picker")
		ws.open("g"); ws.open("g"); ws.editor()
		vim.ui.select = function(items, opts) shown = vim.tbl_map(opts.format_item, items) end
		picker.pick()
	]])
	local rows = child.lua_get("shown")
	match(rows[1], "^1  g +· │ ctx +– │ wk +–$")
end

T["pick"]["rows align"] = function()
	local rows = pick_rows()
	local function col(s, pat)
		return vim.fn.strdisplaywidth(s:sub(1, s:find(pat, 1, true) - 1))
	end
	eq(col(rows[1], "│"), col(rows[2], "│"))
	eq(col(rows[1], "5h"), col(rows[2], "5h"))
	eq(col(rows[1], " wk"), col(rows[2], " wk"))
end

T["pick"]["jumps to the chosen instance"] = function()
	pick_rows()
	eq(child.lua_get("ws.current() == ws.workspaces[2]"), true)
end

T["pick"]["does nothing with no instances"] = function()
	open_two()
	child.lua([[
		ws.close(1); ws.close(1)
		called = false
		vim.ui.select = function() called = true end
		picker.pick()
	]])
	eq(child.lua_get("called"), false)
end

T["sessions"] = MiniTest.new_set()

-- A claude profile whose config dir holds two sessions for the cwd, started
-- through a plain shell. The picker chooses row `pick`.
local function sessions_rows(pick)
	child.lua([[
		config_dir = vim.fn.tempname()
		require("crew").setup({
			agents = { claude = { cmd = { "claude" }, env = { CLAUDE_CONFIG_DIR = config_dir }, hooks = false } },
		})
		ws = require("crew.workspace")
		picker = require("crew.picker")
		started = {}
		local jobstart = vim.fn.jobstart
		vim.fn.jobstart = function(cmd, o)
			started[#started + 1] = cmd
			return jobstart({ "sh" }, o)
		end
		project = require("crew.sessions").dir(require("crew.config").options.agents.claude, vim.fn.getcwd())
		vim.fn.mkdir(project, "p")
		local function write(id, lines, mtime)
			local path = project .. "/" .. id .. ".jsonl"
			vim.fn.writefile(vim.tbl_map(vim.json.encode, lines), path)
			vim.uv.fs_utime(path, mtime, mtime)
		end
		local now = os.time()
		write("aaa", {
			{ type = "user", gitBranch = "feat/workspaces" },
			{ type = "ai-title", aiTitle = "Plan the sessions picker" },
			{ type = "last-prompt", lastPrompt = "list the sessions\nsecond line" },
		}, now)
		write("bbb", { { type = "user" } }, now - 86400 * 10)
	]])
	child.lua(
		[[
		local pick = ...
		vim.ui.select = function(items, opts, on_choice)
			shown = vim.tbl_map(opts.format_item, items)
			title = opts.prompt
			if pick then on_choice(items[pick]) end
		end
		picker.sessions("claude")
	]],
		{ pick or false }
	)
	return child.lua_get("shown")
end

T["sessions"]["lists sessions newest first with date, branch, title and prompt"] = function()
	local rows = sessions_rows()
	eq(#rows, 2)
	match(rows[1], "^today %d%d:%d%d feat/workspaces │ Plan the sessions picker │ list the sessions$")
	match(rows[2], "^%d%d %a%a%a +· +│ +│$")
	eq(child.lua_get("title"), "Crew sessions")
end

T["sessions"]["rows align"] = function()
	local rows = sessions_rows()
	local function col(s)
		return vim.fn.strdisplaywidth(s:sub(1, s:find("│", 1, true) - 1))
	end
	eq(col(rows[1]), col(rows[2]))
end

T["sessions"]["enter opens claude --resume with the session id"] = function()
	sessions_rows(2)
	eq(child.lua_get("vim.tbl_count(ws.workspaces)"), 1)
	eq(child.lua_get("started[1]"), { "claude", "--resume", "bbb" })
end

T["sessions"]["warns and opens nothing when there are no sessions"] = function()
	child.lua([[
		require("crew").setup({
			agents = { claude = { cmd = { "claude" }, env = { CLAUDE_CONFIG_DIR = vim.fn.tempname() } } },
		})
		warned = nil
		vim.notify = function(msg) warned = msg end
		called = false
		vim.ui.select = function() called = true end
		require("crew.picker").sessions("claude")
	]])
	eq(child.lua_get("called"), false)
	eq(child.lua_get("vim.tbl_count(require('crew.workspace').workspaces)"), 0)
	eq(child.lua_get("warned"), "crew: no sessions to resume in " .. child.lua_get("vim.fn.getcwd()"))
end

-- Profiles a and b each with one session; c shares a's config dir.
local function merged_rows(pick, with_shared)
	child.lua(
		[[
		local with_shared = ...
		dir_a, dir_b = vim.fn.tempname(), vim.fn.tempname()
		local agents = {
			a = { cmd = { "claude" }, env = { CLAUDE_CONFIG_DIR = dir_a }, hooks = false },
			b = { cmd = { "claude" }, env = { CLAUDE_CONFIG_DIR = dir_b }, hooks = false },
		}
		if with_shared then
			agents.c = { cmd = { "claude" }, env = { CLAUDE_CONFIG_DIR = dir_a }, hooks = false }
		end
		require("crew").setup({ agents = agents, default_agent = "a" })
		ws, picker, sessions = require("crew.workspace"), require("crew.picker"), require("crew.sessions")
		started = {}
		local jobstart = vim.fn.jobstart
		vim.fn.jobstart = function(cmd, o)
			started[#started + 1] = cmd
			return jobstart({ "sh" }, o)
		end
		local function write(name, id, title, mtime)
			local project = sessions.dir(require("crew.config").options.agents[name], vim.fn.getcwd())
			vim.fn.mkdir(project, "p")
			local path = project .. "/" .. id .. ".jsonl"
			vim.fn.writefile({ vim.json.encode({ type = "ai-title", aiTitle = title }) }, path)
			vim.uv.fs_utime(path, mtime, mtime)
		end
		local now = os.time()
		write("a", "old", "From a", now - 60)
		write("b", "new", "From b", now)
	]],
		{ with_shared or false }
	)
	child.lua(
		[[
		local pick = ...
		vim.ui.select = function(items, opts, on_choice)
			shown = vim.tbl_map(opts.format_item, items)
			if pick then on_choice(items[pick]) end
		end
		picker.sessions()
	]],
		{ pick or false }
	)
	return child.lua_get("shown")
end

T["sessions"]["with no profile lists every profile, newest first, with a profile column"] = function()
	local rows = merged_rows()
	eq(#rows, 2)
	match(rows[1], "^today %d%d:%d%d b +· +│ From b")
	match(rows[2], "^today %d%d:%d%d a +· +│ From a")
end

T["sessions"]["enter resumes with the profile that owns the session"] = function()
	merged_rows(1)
	eq(child.lua_get("ws.current().agent"), "b")
	eq(child.lua_get("started[1]"), { "claude", "--resume", "new" })
end

T["sessions"]["profiles sharing a config dir show a session once"] = function()
	local rows = merged_rows(nil, true)
	eq(#rows, 2)
	match(rows[2], "^today %d%d:%d%d a +· +│ From a") -- the default profile wins
end

return T
