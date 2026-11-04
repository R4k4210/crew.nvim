-- Agents config replacing the defaults, and sending files or selections.
local H = dofile("tests/helpers.lua")
local eq, match = H.eq, H.match
local child, T = H.new()

local function names()
	return child.lua_get([[(function()
		local n = vim.tbl_keys(require("crew.config").options.agents)
		table.sort(n)
		return table.concat(n, ",")
	end)()]])
end

local function setup(opts)
	child.lua('require("crew").setup(...)', { opts })
end

local function default_agent()
	return child.lua_get('require("crew.config").options.default_agent')
end

T["agents"] = MiniTest.new_set()

T["agents"]["no opts keeps the claude default"] = function()
	child.lua('require("crew").setup()')
	eq(names(), "claude")
	eq(default_agent(), "claude")
end

T["agents"]["own agents replace the default claude"] = function()
	setup({ agents = { codex = { cmd = { "codex" } } } })
	eq(names(), "codex")
end

T["agents"]["default_agent falls back to the first agent"] = function()
	setup({ agents = { codex = { cmd = { "codex" } } } })
	eq(default_agent(), "codex")
end

T["agents"]["fallback default is the first name sorted"] = function()
	setup({ agents = { b = { cmd = { "b" } }, a = { cmd = { "a" } } } })
	eq(default_agent(), "a")
end

T["agents"]["an explicit default_agent is kept"] = function()
	setup({ agents = { a = { cmd = { "a" } }, b = { cmd = { "b" } } }, default_agent = "b" })
	eq(default_agent(), "b")
end

T["agents"]["other opts still merge with defaults"] = function()
	setup({ keys = { stopinsert = "jk" } })
	eq(child.lua_get('require("crew.config").options.keys.toggle'), "<C-,>")
	eq(child.lua_get('require("crew.config").options.keys.stopinsert'), "jk")
end

-- Send: nvim_chan_send is recorded in `sent`, the picker in `asked`.
local function send_setup()
	child.lua([[
		vim.g.mapleader = " "
		require("crew").setup({ agents = { sh = { cmd = { "sh" } } } })
		send, ws = require("crew.send"), require("crew.workspace")
		sent, asked, choice = {}, 0, 1
		vim.api.nvim_chan_send = function(chan, data) sent[#sent + 1] = { chan, data } end
		vim.ui.select = function(items, _, on_choice) asked = asked + 1; on_choice(items[choice]) end
		vim.cmd.edit(vim.fn.tempname() .. ".lua")
		file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":~:.")
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = 1", "local b = 2", "local c = 3" })
	]])
end

local function desc(mode, lhs)
	return child.lua("local mode, lhs = ...; return vim.fn.maparg(lhs, mode, false, true).desc", { mode, lhs })
end

T["send"] = MiniTest.new_set()

T["send"]["keys"] = function()
	send_setup()
	eq(desc("n", "<leader>af"), "crew-send-file")
	eq(desc("x", "<leader>av"), "crew-send-selection")
	eq(desc("n", "<leader>aF"), "crew-send-file-last")
	eq(desc("x", "<leader>aV"), "crew-send-selection-last")
end

T["send"]["with no agent sends nothing"] = function()
	send_setup()
	child.lua("send.file()")
	eq(child.lua_get("#sent"), 0)
end

-- One agent open, back in the editor.
local function one_agent()
	send_setup()
	child.lua([[
		ws.open("sh")
		agent = ws.current()
		ws.editor()
	]])
end

T["send"]["file goes to the agent's job"] = function()
	one_agent()
	child.lua("send.file()")
	eq(child.lua_get("sent[1][1] == agent.job"), true)
end

T["send"]["file is a bracketed paste of @path"] = function()
	one_agent()
	child.lua("send.file()")
	local file = child.lua_get("file")
	eq(child.lua_get("sent[1][2]"), "\27[200~@" .. file .. " \27[201~")
end

T["send"]["jumps to the agent"] = function()
	one_agent()
	child.lua("send.file()")
	eq(child.lua_get("ws.current() == agent"), true)
end

T["send"]["selection names the line range"] = function()
	one_agent()
	child.lua("send.selection(2, 3)")
	match(child.lua_get("sent[1][2]"), "@" .. vim.pesc(child.lua_get("file")) .. ":2%-3")
end

T["send"]["selection carries the text in a lua fence"] = function()
	one_agent()
	child.lua("send.selection(2, 3)")
	match(child.lua_get("sent[1][2]"), "```lua\nlocal b = 2\nlocal c = 3\n```", true)
end

T["send"]["selection is a bracketed paste"] = function()
	one_agent()
	child.lua("send.selection(2, 3)")
	local s = child.lua_get("sent[1][2]")
	eq(s:sub(1, 6), "\27[200~")
	eq(s:sub(-6), "\27[201~")
end

T["send"]["one line selection uses a single line number"] = function()
	one_agent()
	child.lua("send.selection(1, 1)")
	match(child.lua_get("sent[1][2]"), ":1\n", true)
end

T["send targets"] = MiniTest.new_set()

-- Agents 1, 2, 3 open; last visited is 2; back in the editor.
local function three_agents()
	send_setup()
	child.lua([[
		ws.open("sh"); ws.open("sh"); ws.open("sh")
		a1, a2, a3 = ws.workspaces[1], ws.workspaces[2], ws.workspaces[3]
		ws.jump(2); ws.editor()
	]])
end

T["send targets"]["several agents: asks which one"] = function()
	three_agents()
	child.lua("choice = 1; send.file()")
	eq(child.lua_get("asked"), 1)
	eq(child.lua_get("sent[1][1] == a1.job"), true)
	eq(child.lua_get("ws.current() == a1"), true)
end

T["send targets"]["last does not ask"] = function()
	three_agents()
	child.lua('send.file("last")')
	eq(child.lua_get("asked"), 0)
	eq(child.lua_get("sent[1][1] == a2.job"), true)
end

T["send targets"]["cancelling the picker sends nothing"] = function()
	three_agents()
	child.lua([[
		vim.ui.select = function(_, _, on_choice) asked = asked + 1; on_choice(nil) end
		send.selection(1, 1)
	]])
	eq(child.lua_get("asked"), 1)
	eq(child.lua_get("#sent"), 0)
end

T["send targets"]["one agent: no picker, sent directly"] = function()
	three_agents()
	child.lua([[
		ws.close(2); ws.close(2)
		ws.editor()
		send.selection(1, 1)
	]])
	eq(child.lua_get("asked"), 0)
	eq(child.lua_get("sent[1][1] == a1.job"), true)
end

return T
