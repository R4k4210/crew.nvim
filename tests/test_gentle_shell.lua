-- Gentle Shell (a Pi coding agent): session ids, status extension and resume.
local H = dofile("tests/helpers.lua")
local eq, match = H.eq, H.match
local child, T = H.new()

local UUID = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

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

local function load()
	child.lua([[gs = require("crew.adapters.gentle_shell")]])
end

T["get"] = MiniTest.new_set()

T["get"]["detects gentle-shell and pi from the basename of cmd[1]"] = function()
	eq(child.lua_get([[require("crew.adapters").get({ cmd = { "gentle-shell", "--link" } }).name]]), "gentle_shell")
	eq(child.lua_get([[require("crew.adapters").get({ cmd = { "/opt/bin/gentle-shell" } }).name]]), "gentle_shell")
	eq(child.lua_get([[require("crew.adapters").get({ cmd = { "pi" } }).name]]), "gentle_shell")
end

T["get"]["takes the explicit adapter name"] = function()
	eq(child.lua_get([[require("crew.adapters").get({ cmd = { "my-pi" }, adapter = "gentle_shell" }).name]]), "gentle_shell")
end

T["prepare"] = MiniTest.new_set()

T["prepare"]["gives a fresh agent its own session id and the status extension"] = function()
	load()
	child.lua([[
		ws = {}
		cmd, env = gs.prepare({ "gentle-shell", "--link" }, { cmd = { "gentle-shell", "--link" } }, ws)
	]])
	local cmd = child.lua_get("cmd")
	eq({ cmd[1], cmd[2], cmd[3] }, { "gentle-shell", "--link", "--session-id" })
	match(cmd[4], UUID)
	eq(cmd[5], "-e")
	eq(cmd[6], child.lua_get("gs.extension"))
	match(cmd[6], "/scripts/pi_status%.js$")
	eq(child.lua_get("ws.session_id"), cmd[4])
	eq(child.lua_get("env.CREW_HOOK_SCRIPT"), child.lua_get([[require("crew.hooks").script]]))
	eq(child.lua_get("env.CREW_HOOK_NVIM"), child.lua_get("vim.v.progpath"))
end

T["prepare"]["generates a different id for every agent"] = function()
	load()
	child.lua([[
		a = gs.prepare({ "pi" }, { cmd = { "pi" } }, {})
		b = gs.prepare({ "pi" }, { cmd = { "pi" } }, {})
	]])
	H.neq(child.lua_get("a[3]"), child.lua_get("b[3]"))
end

T["prepare"]["keeps a resumed session and adds only the extension"] = function()
	load()
	child.lua([[
		ws = {}
		cmd = gs.prepare({ "gentle-shell", "--session", "s1" }, { cmd = { "gentle-shell" } }, ws)
	]])
	eq(child.lua_get("cmd"), { "gentle-shell", "--session", "s1", "-e", child.lua_get("gs.extension") })
	eq(child.lua_get("ws.session_id"), "s1")
end

T["prepare"]["adds no session id with any other session flag"] = function()
	load()
	for _, flag in ipairs({ "-r", "--resume", "-c", "--continue", "--no-session" }) do
		child.lua("cmd = gs.prepare({ 'pi', ... }, { cmd = { 'pi' } }, {})", { flag })
		eq(child.lua_get("cmd"), { "pi", flag, "-e", child.lua_get("gs.extension") })
	end
	child.lua([[cmd = gs.prepare({ "pi", "--session-id", "mine" }, { cmd = { "pi" } }, {})]])
	eq(child.lua_get("cmd"), { "pi", "--session-id", "mine", "-e", child.lua_get("gs.extension") })
end

T["resume_args"] = MiniTest.new_set()

T["resume_args"]["resumes by id or opens Pi's own picker"] = function()
	load()
	eq(child.lua_get([[gs.resume_args("abc")]]), { "--session", "abc" })
	eq(child.lua_get([[gs.resume_args()]]), { "-r" })
end

T["open"] = MiniTest.new_set()

T["open"]["starts gentle-shell with a session id, the extension and the hook env"] = function()
	child.lua([[require("crew").setup({ agents = { gs = { cmd = { "gentle-shell", "--link" } } } })]])
	capture()
	child.lua([[ws = require("crew.workspace").open()]])
	local cmd = child.lua_get("started[1]")
	eq({ cmd[1], cmd[2], cmd[3] }, { "gentle-shell", "--link", "--session-id" })
	eq(child.lua_get("ws.session_id"), cmd[4])
	eq(child.lua_get("envs[1].CREW_HOOK_SCRIPT"), child.lua_get([[require("crew.hooks").script]]))
	eq(child.lua_get("envs[1].CREW_ID"), tostring(child.lua_get("ws.id")))
end

T["restore"] = MiniTest.new_set()

T["restore"]["reopens a gentle-shell agent on its saved session"] = function()
	child.lua([[require("crew").setup({ agents = { gs = { cmd = { "gentle-shell", "--link" } } } })]])
	capture()
	child.lua([[
		persist = require("crew.persist")
		persist.dir = vim.fn.tempname()
		vim.fn.mkdir(persist.dir, "p")
		vim.fn.writefile({ vim.json.encode({ version = 1, agents = { { agent = "gs", session_id = "s1" } } }) }, persist.path())
	]])
	eq(child.lua_get("persist.restore()"), 1)
	eq(
		child.lua_get("started[1]"),
		{ "gentle-shell", "--link", "--session", "s1", "-e", child.lua_get([[require("crew.adapters.gentle_shell").extension]]) }
	)
end

return T
