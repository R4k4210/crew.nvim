-- Adapters: how crew picks one per profile and what each one changes.
local H = dofile("tests/helpers.lua")
local eq, match = H.eq, H.match
local child, T = H.new()

-- Record the command and env of every started job, running a shell instead.
local function capture()
	child.lua([[
		started, envs = {}, {}
		local jobstart = vim.fn.jobstart
		vim.fn.jobstart = function(cmd, o)
			started[#started + 1] = cmd
			envs[#envs + 1] = o.env
			return jobstart({ "sh" }, o)
		end
	]])
end

T["get"] = MiniTest.new_set()

T["get"]["uses the explicit adapter name"] = function()
	eq(child.lua_get([[require("crew.adapters").get({ cmd = { "my-wrapper" }, adapter = "claude" }).name]]), "claude")
end

T["get"]["detects the adapter from the basename of cmd[1]"] = function()
	eq(child.lua_get([[require("crew.adapters").get({ cmd = { "/usr/local/bin/claude" } }).name]]), "claude")
	eq(child.lua_get([[require("crew.adapters").get({ cmd = { "agy" } }).name]]), "agy")
end

T["get"]["falls back to plain for an unknown CLI"] = function()
	eq(child.lua_get([[require("crew.adapters").get({ cmd = { "codex" } }).name]]), "plain")
	eq(child.lua_get([[require("crew.adapters").get({ cmd = {} }).name]]), "plain")
end

T["get"]["does not load modules that are not adapters"] = function()
	eq(child.lua_get([[require("crew.adapters").get({ cmd = { "init" } }).name]]), "plain")
end

T["get"]["warns once about an unknown explicit adapter and uses plain"] = function()
	child.lua([[
		warned = {}
		vim.notify = function(msg, level) warned[#warned + 1] = { msg, level } end
		adapters = require("crew.adapters")
		first = adapters.get({ cmd = { "x" }, adapter = "nope" }).name
		adapters.get({ cmd = { "x" }, adapter = "nope" })
	]])
	eq(child.lua_get("first"), "plain")
	eq(child.lua_get("#warned"), 1)
	eq(child.lua_get("warned[1][2]"), child.lua_get("vim.log.levels.WARN"))
	match(child.lua_get("warned[1][1]"), 'unknown adapter "nope"', true)
end

T["open"] = MiniTest.new_set()

T["open"]["a plain profile starts the bare cmd with no CREW_STATUSLINE"] = function()
	child.lua([[require("crew").setup({ agents = { codex = { cmd = { "codex", "--fast" }, env = { A = "1" } } } })]])
	capture()
	child.lua([[require("crew.workspace").open()]])
	eq(child.lua_get("started[1]"), { "codex", "--fast" })
	eq(child.lua_get("envs[1].CREW_STATUSLINE"), vim.NIL)
	eq(child.lua_get("envs[1].CREW_ID"), "1")
	eq(child.lua_get("envs[1].A"), "1")
end

T["open"]["adapter = claude injects the hooks into a wrapper command"] = function()
	child.lua([[require("crew").setup({ agents = { work = { cmd = { "/opt/bin/my-claude-wrapper" }, adapter = "claude" } } })]])
	capture()
	child.lua([[require("crew.workspace").open()]])
	eq(child.lua_get("started[1][1]"), "/opt/bin/my-claude-wrapper")
	eq(child.lua_get("started[1][2]"), "--settings")
	match(child.lua_get("started[1][3]"), "UserPromptSubmit", true)
	eq(child.lua_get("envs[1].CREW_ID"), "1")
end

T["open"]["adapter = claude with hooks = false starts the bare cmd"] = function()
	child.lua([[require("crew").setup({ agents = { work = { cmd = { "wrap" }, adapter = "claude", hooks = false } } })]])
	capture()
	child.lua([[require("crew.workspace").open()]])
	eq(child.lua_get("started[1]"), { "wrap" })
	eq(child.lua_get("envs[1].CREW_STATUSLINE"), vim.NIL)
end

T["claude"] = MiniTest.new_set()

T["claude"]["resume_args resumes one session or opens claude's picker"] = function()
	child.lua([[claude = require("crew.adapters.claude")]])
	eq(child.lua_get([[claude.resume_args("abc")]]), { "--resume", "abc" })
	eq(child.lua_get([[claude.resume_args()]]), { "--resume" })
end

T["resume"] = MiniTest.new_set()

T["resume"]["a wrapper with adapter = claude opens the sessions picker"] = function()
	child.lua([[require("crew").setup({ agents = { work = { cmd = { "wrap" }, adapter = "claude", hooks = false } } })]])
	child.lua([[
		picked = nil
		require("crew.picker").sessions = function(name) picked = name end
		require("crew.workspace").resume()
	]])
	eq(child.lua_get("picked"), "work")
end

T["resume"]["an adapter without sessions opens its resume_args(nil)"] = function()
	child.lua([[
		package.loaded["crew.adapters.fake"] = { name = "fake", resume_args = function() return { "--pick" } end }
		require("crew").setup({ agents = { f = { cmd = { "sh" }, adapter = "fake" } } })
	]])
	capture()
	child.lua([[require("crew.workspace").resume()]])
	eq(child.lua_get("started[1]"), { "sh", "--pick" })
end

T["restore"] = MiniTest.new_set()

T["restore"]["a wrapper with adapter = claude resumes its saved session"] = function()
	child.lua([[
		require("crew").setup({ agents = { work = { cmd = { "wrap" }, adapter = "claude", hooks = false } } })
		persist = require("crew.persist")
		persist.dir = vim.fn.tempname()
		vim.fn.mkdir(persist.dir, "p")
		vim.fn.writefile({ vim.json.encode({ version = 1, agents = { { agent = "work", session_id = "s1" } } }) }, persist.path())
	]])
	capture()
	eq(child.lua_get("persist.restore()"), 1)
	eq(child.lua_get("started[1]"), { "wrap", "--resume", "s1" })
end

T["restore"]["a plain profile ignores its saved session id"] = function()
	child.lua([[
		require("crew").setup({ agents = { sh = { cmd = { "sh" } } } })
		persist = require("crew.persist")
		persist.dir = vim.fn.tempname()
		vim.fn.mkdir(persist.dir, "p")
		vim.fn.writefile({ vim.json.encode({ version = 1, agents = { { agent = "sh", session_id = "s1" } } }) }, persist.path())
	]])
	capture()
	eq(child.lua_get("persist.restore()"), 1)
	eq(child.lua_get("started[1]"), { "sh" })
end

return T
