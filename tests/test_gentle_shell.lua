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

-- Run scripts/pi_status.js against a fake Pi and a fake nvim that records
-- each hook call as "<event> <stdin json>" in a file of its own.
local function run_extension(env, calls)
	if vim.fn.executable("node") == 0 then
		MiniTest.skip("node is not installed")
	end
	local dir = vim.fn.tempname()
	local out = dir .. "/calls"
	vim.fn.mkdir(out, "p")
	vim.fn.writefile({ "#!/bin/sh", 'f="$OUT/$$"', 'printf "%s " "$5" > "$f.tmp"', 'cat >> "$f.tmp"', 'mv "$f.tmp" "$f"' }, dir .. "/nvim")
	vim.fn.setfperm(dir .. "/nvim", "rwxr-xr-x")
	vim.fn.writefile({
		"const mod = await import(process.argv[2]);",
		"const on = {};",
		"mod.default({ on: (name, fn) => { on[name] = fn; } });",
		'const ctx = { sessionManager: { getSessionId: () => "sid" } };',
		"for (const [name, event] of JSON.parse(process.argv[3])) await on[name](event, ctx);",
	}, dir .. "/harness.mjs")
	local res = vim.system({ "node", dir .. "/harness.mjs", vim.fn.fnamemodify("scripts/pi_status.js", ":p"), vim.json.encode(calls) }, {
		env = vim.tbl_extend("force", { OUT = out, CREW_HOOK_NVIM = dir .. "/nvim", CREW_HOOK_SCRIPT = "/x/hook.lua" }, env),
	}):wait(5000)
	eq(res.code, 0)
	local function read()
		local lines = {}
		for name in vim.fs.dir(out) do
			if not name:match("%.tmp$") then
				lines[#lines + 1] = table.concat(vim.fn.readfile(out .. "/" .. name), "\n")
			end
		end
		return lines
	end
	vim.wait(2000, function()
		return #read() >= #calls
	end, 20)
	vim.uv.sleep(100) -- a stray extra call would land by now
	return read()
end

local function parse(line)
	local event, json = line:match("^(%S+) (.*)$")
	return event, vim.json.decode(json)
end

T["extension"] = MiniTest.new_set()

T["extension"]["is a readable file next to the hook helper"] = function()
	load()
	eq(vim.fn.filereadable(child.lua_get("gs.extension")), 1)
end

T["extension"]["maps Pi events onto crew's hook events with the session id"] = function()
	local lines = run_extension({ NVIM = "/tmp/fake.sock", CREW_ID = "3" }, {
		{ "agent_start", vim.empty_dict() },
		{ "ui_prompt_start", { kind = "confirm", title = "Allow?" } },
		{ "ui_prompt_end", vim.empty_dict() },
		{ "agent_settled", { aborted = false } },
		{ "session_start", { reason = "new" } },
	})
	table.sort(lines) -- calls run detached, so their order is not fixed
	local got = {}
	for _, line in ipairs(lines) do
		local event, payload = parse(line)
		got[#got + 1] = { event, payload }
	end
	eq(got, {
		{ "Notification", { session_id = "sid", notification_type = "confirm" } },
		{ "PostToolUse", { session_id = "sid" } },
		{ "SessionStart", { session_id = "sid" } },
		{ "Stop", { session_id = "sid" } },
		{ "UserPromptSubmit", { session_id = "sid" } },
	})
end

T["extension"]["does nothing outside a crew agent"] = function()
	eq(run_extension({ NVIM = "", CREW_ID = "" }, { { "agent_start", vim.empty_dict() } }), {})
end

T["state"] = MiniTest.new_set()

T["state"]["SessionStart moves the session id and keeps the state"] = function()
	child.lua([[require("crew").setup({ agents = { gs = { cmd = { "gentle-shell" } } } })]])
	capture()
	child.lua([[
		ws = require("crew.workspace").open()
		state = require("crew.state")
		state.report(ws.id, "UserPromptSubmit", {})
		state.report(ws.id, "SessionStart", { session_id = "next" })
	]])
	eq(child.lua_get("ws.session_id"), "next")
	eq(child.lua_get("ws.state"), "work")
end

-- Write a Pi session file under dir, made `age` seconds ago.
local function session(dir, file, lines, age)
	child.lua(
		[[
		local dir, file, lines, age = ...
		vim.fn.mkdir(dir, "p")
		vim.fn.writefile(vim.tbl_map(vim.json.encode, lines), dir .. "/" .. file)
		local t = os.time() - age
		vim.uv.fs_utime(dir .. "/" .. file, t, t)
	]],
		{ dir, file, lines, age }
	)
end

local function header(id, cwd)
	return { type = "session", version = 3, id = id, timestamp = "2026-11-01T10:00:00.000Z", cwd = cwd }
end

local function user(text)
	return { type = "message", id = "u1", parentId = vim.NIL, timestamp = "2026-11-01T10:00:01.000Z", message = { role = "user", content = text } }
end

-- Clear Pi and Gentle Shell env overrides, so defaults show.
local function clean_env()
	child.lua([[
		for _, k in ipairs({ "PI_CODING_AGENT_DIR", "PI_CODING_AGENT_SESSION_DIR", "GENTLE_SHELL_HOME" }) do
			vim.env[k] = nil
		end
	]])
end

T["sessions_dir"] = MiniTest.new_set()

T["sessions_dir"]["uses ~/.pi/agent with --link or pi, else the isolated ~/.gentle-shell/agent"] = function()
	load()
	clean_env()
	local home = vim.fn.expand("~")
	eq(child.lua_get([[gs.sessions_dir({ cmd = { "gentle-shell", "--link" } }, "/work/My Dir")]]), home .. "/.pi/agent/sessions/--work-My Dir--")
	eq(child.lua_get([[gs.sessions_dir({ cmd = { "pi" } }, "/work")]]), home .. "/.pi/agent/sessions/--work--")
	eq(child.lua_get([[gs.sessions_dir({ cmd = { "gentle-shell" } }, "/work")]]), home .. "/.gentle-shell/agent/sessions/--work--")
end

T["sessions_dir"]["honors the profile env, then Neovim's env"] = function()
	load()
	clean_env()
	eq(child.lua_get([[gs.sessions_dir({ cmd = { "gentle-shell", "--link" }, env = { PI_CODING_AGENT_DIR = "/p" } }, "/w")]]), "/p/sessions/--w--")
	eq(child.lua_get([[gs.sessions_dir({ cmd = { "gentle-shell" }, env = { GENTLE_SHELL_HOME = "/g" } }, "/w")]]), "/g/sessions/--w--")
	child.lua([[vim.env.PI_CODING_AGENT_DIR = "/envp"]])
	eq(child.lua_get([[gs.sessions_dir({ cmd = { "pi" } }, "/w")]]), "/envp/sessions/--w--")
	-- A custom session dir holds the sessions of every cwd, flat.
	eq(child.lua_get([[gs.sessions_dir({ cmd = { "gentle-shell" }, env = { PI_CODING_AGENT_SESSION_DIR = "/s" } }, "/w")]]), "/s")
end

T["sessions"] = MiniTest.new_set()

-- A linked and an isolated profile, each with its own temp agent dir.
local function homes()
	load()
	clean_env()
	child.lua([[
		pihome, gshome = vim.fn.tempname(), vim.fn.tempname()
		linked = { cmd = { "gentle-shell", "--link" }, env = { PI_CODING_AGENT_DIR = pihome } }
		isolated = { cmd = { "gentle-shell" }, env = { GENTLE_SHELL_HOME = gshome } }
	]])
	return child.lua_get("pihome"), child.lua_get("gshome")
end

T["sessions"]["lists the sessions of cwd newest first with name and last prompt"] = function()
	local pihome = homes()
	local dir = pihome .. "/sessions/--work-My Dir--"
	session(dir, "2026-11-01T10-00-00-000Z_old.jsonl", { header("old", "/work/My Dir"), user("first prompt") }, 300)
	session(dir, "2026-11-02T10-00-00-000Z_new.jsonl", {
		header("new", "/work/My Dir"),
		user("hello"),
		{ type = "message", id = "u2", parentId = "u1", timestamp = "x", message = { role = "user", content = { { type = "text", text = "latest" } } } },
		{ type = "session_info", id = "i1", parentId = "u2", timestamp = "x", name = "Refactor auth" },
	}, 10)
	session(dir, "notes.txt", { "x" }, 0)
	local list = child.lua_get([[gs.sessions(linked, "/work/My Dir")]])
	eq(vim.tbl_map(function(s)
		return { s.id, s.title or false, s.prompt }
	end, list), { { "new", "Refactor auth", "latest" }, { "old", false, "first prompt" } })
	eq(list[1].mtime > list[2].mtime, true)
	eq(child.lua_get([[gs.last_session(linked, "/work/My Dir")]]), "new")
end

T["sessions"]["reads the isolated home of a profile without --link"] = function()
	local pihome, gshome = homes()
	session(gshome .. "/sessions/--work--", "t_iso.jsonl", { header("iso", "/work") }, 0)
	session(pihome .. "/sessions/--work--", "t_linked.jsonl", { header("linked", "/work") }, 0)
	eq(child.lua_get([[gs.last_session(isolated, "/work")]]), "iso")
	eq(child.lua_get([[gs.last_session(linked, "/work")]]), "linked")
end

T["sessions"]["filters a flat custom session dir by the header cwd"] = function()
	load()
	child.lua([[sdir = vim.fn.tempname(); flat = { cmd = { "pi" }, env = { PI_CODING_AGENT_SESSION_DIR = sdir } }]])
	local sdir = child.lua_get("sdir")
	session(sdir, "a_here.jsonl", { header("here", "/work") }, 10)
	session(sdir, "b_there.jsonl", { header("there", "/else") }, 0)
	eq(vim.tbl_map(function(s)
		return s.id
	end, child.lua_get([[gs.sessions(flat, "/work")]])), { "here" })
end

T["sessions"]["degrades to {} and nil on missing dirs and odd files"] = function()
	local pihome = homes()
	eq(child.lua_get([[gs.sessions(linked, "/nowhere")]]), {})
	eq(child.lua_get([[gs.last_session(linked, "/nowhere")]]), vim.NIL)
	local dir = pihome .. "/sessions/--work--"
	session(dir, "t_broken.jsonl", { "not json" }, 0)
	child.lua([[vim.fn.writefile({ "{oops", "[1,2]" }, ...)]], { dir .. "/t_garbage.jsonl" })
	child.lua([[vim.fn.writefile({}, ...)]], { dir .. "/t_empty.jsonl" })
	local ids = vim.tbl_map(function(s)
		return s.id
	end, child.lua_get([[gs.sessions(linked, "/work")]]))
	table.sort(ids)
	-- No header: the id comes from the file name, after the timestamp.
	eq(ids, { "broken", "empty", "garbage" })
end

T["resume"] = MiniTest.new_set()

T["resume"]["opens crew's sessions picker and resumes the picked session"] = function()
	local pihome = homes()
	session(pihome .. "/sessions/--work--", "t_s1.jsonl", { header("s1", "/work") }, 0)
	child.lua([[require("crew").setup({ agents = { gs = linked } })]])
	capture()
	child.lua([[
		vim.fn.getcwd = function() return "/work" end
		vim.ui.select = function(items, opts, on_choice) on_choice(items[1]) end
		require("crew.workspace").resume("gs")
	]])
	eq(child.lua_get("started[1]"), { "gentle-shell", "--link", "--session", "s1", "-e", child.lua_get("gs.extension") })
end

return T
