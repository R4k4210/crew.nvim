-- Agent numbering: agents are 1..N with no limit, the editor stands apart.
local H = dofile("tests/helpers.lua")
local eq = H.eq
local child, T = H.new()

local function setup()
	child.lua([[
		require("crew").setup({ agents = { sh = { cmd = { "sh" } } } })
		ws = require("crew.workspace")
		home = vim.api.nvim_get_current_tabpage()
		tabnr = function(w) return vim.api.nvim_tabpage_get_number(w.tab) end
	]])
end

local function open(n)
	child.lua("for _ = 1, ... do ws.open('sh') end", { n })
end

T["the first agent is 1"] = function()
	setup()
	open(1)
	eq(child.lua_get("ws.current().slot"), 1)
	eq(child.lua_get("ws.workspaces[1] == ws.current()"), true)
end

T["more than 9 agents can be opened"] = function()
	setup()
	open(12)
	eq(child.lua_get("vim.tbl_count(ws.workspaces)"), 12)
	eq(child.lua_get("ws.current().slot"), 12)
end

T["tab order follows agent order, after the editor"] = function()
	setup()
	open(3)
	child.lua("ws.jump(1); ws.open('sh')") -- opened from agent 1, still goes last
	eq(child.lua_get("vim.api.nvim_tabpage_get_number(home)"), 1)
	eq(child.lua_get("{ tabnr(ws.workspaces[1]), tabnr(ws.workspaces[2]), tabnr(ws.workspaces[4]) }"), { 2, 3, 5 })
end

T["jump to a missing agent stays put"] = function()
	setup()
	open(2)
	child.lua("ws.jump(1); ws.jump(7)")
	eq(child.lua_get("ws.current() == ws.workspaces[1]"), true)
end

T["editor() goes to the home tab"] = function()
	setup()
	open(2)
	child.lua("ws.editor()")
	eq(child.lua_get("vim.api.nvim_get_current_tabpage() == home"), true)
	eq(child.lua_get("ws.current()"), vim.NIL)
end

T["toggle goes to the editor and back to the last agent"] = function()
	setup()
	open(2)
	child.lua("ws.jump(1); ws.toggle()")
	eq(child.lua_get("vim.api.nvim_get_current_tabpage() == home"), true)
	child.lua("ws.toggle()")
	eq(child.lua_get("ws.current() == ws.workspaces[1]"), true)
end

T["closing the current agent goes to the editor"] = function()
	setup()
	open(3)
	child.lua("ws.jump(2); ws.close()")
	eq(child.lua_get("vim.api.nvim_get_current_tabpage() == home"), true)
	eq(child.lua_get("{ ws.workspaces[1].slot, ws.workspaces[2].slot, ws.workspaces[3] == nil }"), { 1, 2, true })
end

T["close_all"] = MiniTest.new_set()

T["close_all"]["closes every agent and lands in the editor"] = function()
	setup()
	open(3)
	child.lua("ws.jump(2); ws.close_all()")
	eq(child.lua_get("vim.tbl_count(ws.workspaces)"), 0)
	eq(child.lua_get("vim.api.nvim_get_current_tabpage() == home"), true)
	eq(child.lua_get("#vim.api.nvim_list_tabpages()"), 1)
	eq(child.lua_get([[#vim.tbl_filter(function(b) return vim.bo[b].buftype == "terminal" end, vim.api.nvim_list_bufs())]]), 0)
end

T["session save"] = MiniTest.new_set()

T["session save"]["on exit closes agents so the session holds editor files only"] = function()
	setup()
	open(2)
	child.lua("ws.before_session_save(0)")
	eq(child.lua_get("vim.tbl_count(ws.workspaces)"), 0)
	eq(child.lua_get("#vim.api.nvim_list_tabpages()"), 1)
end

T["session save"]["mid session keeps agents open"] = function()
	setup()
	open(2)
	child.lua("vim.api.nvim_exec_autocmds('User', { pattern = 'PersistenceSavePre' })")
	eq(child.lua_get("vim.tbl_count(ws.workspaces)"), 2)
	eq(child.lua_get("#vim.api.nvim_list_tabpages()"), 3)
end

T["close_all"]["is silent and safe with no agents"] = function()
	setup()
	child.lua([[
		notified = false
		vim.notify = function() notified = true end
		ws.close_all()
	]])
	eq(child.lua_get("notified"), false)
	eq(child.lua_get("vim.api.nvim_get_current_tabpage() == home"), true)
end

T[":Crew"] = MiniTest.new_set()

T[":Crew"]["close all closes every agent"] = function()
	setup()
	open(3)
	child.lua('vim.cmd("Crew close all")')
	eq(child.lua_get("vim.tbl_count(ws.workspaces)"), 0)
	eq(child.lua_get("vim.api.nvim_get_current_tabpage() == home"), true)
end

T[":Crew"]["close 2 closes only agent 2"] = function()
	setup()
	open(3)
	child.lua("ws.workspaces[3].name = 'third'")
	child.lua('vim.cmd("Crew close 2")')
	eq(child.lua_get("vim.tbl_count(ws.workspaces)"), 2)
	eq(child.lua_get("ws.workspaces[2].name"), "third")
end

T[":Crew"]["close completes all"] = function()
	setup()
	eq(child.lua_get('vim.fn.getcompletion("Crew close ", "cmdline")'), { "all" })
end

T[":Crew"]["jump 12 goes to agent 12"] = function()
	setup()
	open(12)
	child.lua('ws.editor(); vim.cmd("Crew jump 12")')
	eq(child.lua_get("ws.current().slot"), 12)
end

T[":Crew"]["editor goes to the home tab"] = function()
	setup()
	open(1)
	child.lua('vim.cmd("Crew editor")')
	eq(child.lua_get("vim.api.nvim_get_current_tabpage() == home"), true)
end

T[":Crew"]["list prints the editor first, then the agents"] = function()
	setup()
	open(2)
	eq(child.lua_get('vim.api.nvim_exec2("Crew list", { output = true }).output'), "editor\n1 sh\n2 sh")
end

return T
