-- Open agents saved per directory and restored after a restart.
local H = dofile("tests/helpers.lua")
local eq, match = H.eq, H.match
local child, T = H.new()

-- Profiles: sh runs a shell, claude has a claude cmd but the stub below
-- runs a shell too, so nothing real starts.
local function setup()
	child.lua([[
		require("crew").setup({ agents = {
			sh = { cmd = { "sh" } },
			claude = { cmd = { "claude" }, hooks = false },
		} })
		ws = require("crew.workspace")
		persist = require("crew.persist")
		persist.dir = vim.fn.tempname()
		home = vim.api.nvim_get_current_tabpage()
		started = {}
		local jobstart = vim.fn.jobstart
		vim.fn.jobstart = function(cmd, o)
			started[#started + 1] = cmd
			return jobstart({ "sh" }, o)
		end
		saved = function()
			local f = io.open(persist.path(), "r")
			if not f then return nil end
			local data = vim.json.decode(f:read("*a"))
			f:close()
			return data
		end
		write = function(data)
			vim.fn.mkdir(persist.dir, "p")
			local f = io.open(persist.path(), "w")
			f:write(type(data) == "string" and data or vim.json.encode(data))
			f:close()
		end
	]])
end

T["save"] = MiniTest.new_set()

T["save"]["writes agents in slot order with name and session id"] = function()
	setup()
	child.lua([[
		ws.open("sh"); ws.open("claude")
		ws.workspaces[2].session_id = "abc"
		ws.rename("first", 1)
		persist.save()
	]])
	eq(child.lua_get("saved().version"), 1)
	eq(child.lua_get("saved().agents"), {
		{ agent = "sh", name = "first", cwd = child.lua_get("vim.fn.getcwd()") },
		{ agent = "claude", cwd = child.lua_get("vim.fn.getcwd()"), session_id = "abc" },
	})
end

T["save"]["the file name encodes the cwd"] = function()
	setup()
	match(child.lua_get("persist.path()"), "/[%w-]+%.json$")
	eq(child.lua_get("vim.fs.basename(persist.path())"), child.lua_get("vim.fn.getcwd():gsub('[^%w]', '-') .. '.json'"))
end

T["save"]["runs on open, rename, close and a new session id"] = function()
	setup()
	child.lua('ws.open("claude"); ws.open("sh")')
	eq(child.lua_get("#saved().agents"), 2)
	child.lua('ws.rename("named", 2)')
	eq(child.lua_get("saved().agents[2].name"), "named")
	child.lua([[require("crew.state").report(ws.workspaces[1].id, "UserPromptSubmit", { session_id = "s1" })]])
	eq(child.lua_get("saved().agents[1].session_id"), "s1")
	child.lua("ws.close(1)")
	eq(child.lua_get("saved().agents"), { { agent = "sh", name = "named", cwd = child.lua_get("vim.fn.getcwd()") } })
end

T["save"]["deletes the file when no agent is left"] = function()
	setup()
	child.lua('ws.open("sh")')
	eq(child.lua_get("vim.uv.fs_stat(persist.path()) ~= nil"), true)
	child.lua("ws.close(1)")
	eq(child.lua_get("vim.uv.fs_stat(persist.path()) == nil"), true)
end

T["save"]["does nothing while Neovim is quitting"] = function()
	setup()
	child.lua('ws.open("sh"); ws.open("sh")')
	child.lua("persist.exiting = function() return true end; ws.close(1)")
	eq(child.lua_get("#saved().agents"), 2)
end

T["save"]["a write failure warns once and never errors"] = function()
	setup()
	child.lua([[
		warnings = 0
		vim.notify = function(_, level) if level == vim.log.levels.WARN then warnings = warnings + 1 end end
		persist.dir = "/dev/null/crew"
		ws.open("sh"); ws.open("sh")
	]])
	eq(child.lua_get("vim.tbl_count(ws.workspaces)"), 2)
	eq(child.lua_get("warnings"), 1)
end

T["close"] = MiniTest.new_set()

T["close"]["close_all from the user forgets the agents"] = function()
	setup()
	child.lua('ws.open("sh"); ws.open("sh"); ws.close_all()')
	eq(child.lua_get("vim.uv.fs_stat(persist.path()) == nil"), true)
end

T["close"]["closing agents on exit keeps the file"] = function()
	setup()
	child.lua('ws.open("sh"); ws.open("sh"); ws.before_session_save(0)')
	eq(child.lua_get("vim.tbl_count(ws.workspaces)"), 0)
	eq(child.lua_get("#saved().agents"), 2)
end

T["load"] = MiniTest.new_set()

T["load"]["returns nil for a missing or malformed file"] = function()
	setup()
	eq(child.lua_get("persist.load()"), vim.NIL)
	child.lua('write("{ not json")')
	eq(child.lua_get("persist.load()"), vim.NIL)
	child.lua('write({ version = 1, agents = "nope" })')
	eq(child.lua_get("persist.load()"), vim.NIL)
end

T["restore"] = MiniTest.new_set()

T["restore"]["reopens agents in order with names and resume args"] = function()
	setup()
	child.lua([[write({ version = 1, agents = {
		{ agent = "claude", name = "api", session_id = "id-1" },
		{ agent = "sh", session_id = "id-2" },
		{ agent = "claude" },
	} })]])
	eq(child.lua_get("persist.restore()"), 3)
	eq(child.lua_get("started"), { { "claude", "--resume", "id-1" }, { "sh" }, { "claude" } })
	eq(child.lua_get("{ ws.workspaces[1].agent, ws.workspaces[2].agent, ws.workspaces[3].agent }"), { "claude", "sh", "claude" })
	eq(child.lua_get("ws.workspaces[1].name"), "api")
	eq(child.lua_get("ws.workspaces[2].name"), vim.NIL)
	eq(child.lua_get("vim.api.nvim_get_current_tabpage() == home"), true)
	eq(child.lua_get("#saved().agents"), 3)
end

T["restore"]["skips unknown profiles with one warning"] = function()
	setup()
	child.lua([[
		warned = {}
		vim.notify = function(msg, level) warned[#warned + 1] = { msg, level } end
		write({ version = 1, agents = { { agent = "gone" }, { agent = "sh" }, { agent = "old" } } })
	]])
	eq(child.lua_get("persist.restore()"), 1)
	eq(child.lua_get("#warned"), 1)
	eq(child.lua_get("warned[1][2]"), child.lua_get("vim.log.levels.WARN"))
	match(child.lua_get("warned[1][1]"), "gone, old", true)
end

T["restore"]["does nothing while agents are open"] = function()
	setup()
	child.lua([[
		ws.open("sh")
		write({ version = 1, agents = { { agent = "sh" }, { agent = "sh" } } })
		notified = false
		vim.notify = function() notified = true end
	]])
	eq(child.lua_get("persist.restore()"), 0)
	eq(child.lua_get("vim.tbl_count(ws.workspaces)"), 1)
	eq(child.lua_get("notified"), false)
end

T["restore"]["runs after a session loads"] = function()
	setup()
	child.lua([[write({ version = 1, agents = { { agent = "sh" } } })]])
	child.lua([[vim.api.nvim_exec_autocmds("SessionLoadPost", {})]])
	child.lua("vim.wait(1000, function() return vim.tbl_count(ws.workspaces) == 1 end)")
	eq(child.lua_get("vim.tbl_count(ws.workspaces)"), 1)
end

T["restore"][":Crew restore reopens the saved agents"] = function()
	setup()
	child.lua([[write({ version = 1, agents = { { agent = "sh" } } })]])
	child.lua('vim.cmd("Crew restore")')
	eq(child.lua_get("vim.tbl_count(ws.workspaces)"), 1)
	eq(child.lua_get('vim.fn.getcompletion("Crew rest", "cmdline")'), { "restore" })
end

return T
