-- Antigravity (agy) bridge: :Crew setup agy, the hooks plugin, the status
-- line bridge and the restore fallback. Every agy path is a temp dir.
local H = dofile("tests/helpers.lua")
local eq, match = H.eq, H.match
local child, T = H.new()

-- Temp agy and crew state dirs, with a settings.json holding `settings`.
local function dirs(settings)
	child.lua(
		[[
		local settings = ...
		agy = require("crew.adapters.agy")
		bridge = require("crew.agy_bridge")
		persist = require("crew.persist")
		agy.data_dir = vim.fn.tempname()
		persist.dir = vim.fn.tempname()
		bridge.config_dir = vim.fn.tempname()
		vim.fn.mkdir(agy.data_dir, "p")
		settings_path = agy.data_dir .. "/settings.json"
		if settings then
			vim.fn.writefile({ vim.json.encode(settings) }, settings_path)
		end
		function read_json(path)
			return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
		end
		function backups()
			return #vim.fn.glob(agy.data_dir .. "/settings.json.crew-*.bak", false, true)
		end
	]],
		{ settings or false }
	)
end

T["setup"] = MiniTest.new_set()

T["setup"]["install writes the plugin, saves the original and swaps in the bridge"] = function()
	dirs({ colorScheme = "night", statusLine = { type = "command", command = "echo orig" } })
	child.lua("bridge.install()")
	eq(child.lua_get("vim.fn.filereadable(bridge.config_dir .. '/plugins/crew/plugin.json')"), 1)
	local hooks = child.lua_get("read_json(bridge.config_dir .. '/plugins/crew/hooks.json')")
	local spec = hooks.crew
	match(spec.PreInvocation[1].command, "hook.lua' PreInvocation", true)
	match(spec.PostToolUse[1].hooks[1].command, "hook.lua' PostToolUse", true)
	match(spec.Stop[1].command, "hook.lua' Stop", true)
	local settings = child.lua_get("read_json(settings_path)")
	eq(settings.colorScheme, "night")
	match(settings.statusLine.command, "agy_statusline.lua", true)
	eq(child.lua_get("read_json(bridge.original_file()).statusLine.command"), "echo orig")
	eq(child.lua_get("backups()"), 1)
	eq(child.lua_get("bridge.installed()"), true)
end

T["setup"]["a second install changes nothing and keeps the original"] = function()
	dirs({ statusLine = { type = "command", command = "echo orig" } })
	child.lua("bridge.install(); before = table.concat(vim.fn.readfile(settings_path), '\\n'); bridge.install()")
	eq(child.lua_get("table.concat(vim.fn.readfile(settings_path), '\\n') == before"), true)
	eq(child.lua_get("backups()"), 1)
	eq(child.lua_get("read_json(bridge.original_file()).statusLine.command"), "echo orig")
end

T["setup"]["remove restores the original status line and deletes the plugin"] = function()
	dirs({ colorScheme = "night", statusLine = { type = "command", command = "echo orig" } })
	child.lua("bridge.install(); bridge.remove()")
	eq(child.lua_get("vim.fn.isdirectory(bridge.config_dir .. '/plugins/crew')"), 0)
	local settings = child.lua_get("read_json(settings_path)")
	eq(settings.statusLine, { type = "command", command = "echo orig" })
	eq(settings.colorScheme, "night")
	eq(child.lua_get("bridge.installed()"), false)
end

T["setup"]["remove drops the status line when there was none"] = function()
	dirs({ colorScheme = "night" })
	child.lua("bridge.install(); bridge.remove()")
	local settings = child.lua_get("read_json(settings_path)")
	eq(settings.statusLine, nil)
	eq(settings.colorScheme, "night")
end

T["setup"][":Crew setup agy runs install and remove"] = function()
	dirs({})
	child.cmd("Crew setup agy")
	eq(child.lua_get("bridge.installed()"), true)
	child.cmd("Crew setup agy remove")
	eq(child.lua_get("bridge.installed()"), false)
end

-- Two plain workspaces, the editor current, as in test_hooks_state.
local function two_agents()
	child.lua([[
		require("crew").setup({ agents = { sh = { cmd = { "sh" } } } })
		ws, state = require("crew.workspace"), require("crew.state")
		vim.notify = function() end
		ws.open("sh"); ws.open("sh")
		a, b = ws.workspaces[1], ws.workspaces[2]
		ws.editor()
		function run(cmd, env, stdin)
			env = vim.deepcopy(env)
			local clear = env.clear == true
			env.clear = nil
			-- Async plus vim.wait, so this Neovim can answer the script's RPC.
			local res
			vim.system(cmd, { env = env, clear_env = clear, stdin = stdin, text = true }, function(r) res = r end)
			vim.wait(5000, function() return res ~= nil end)
			return res and { code = res.code, stdout = res.stdout } or { code = -1 }
		end
	]])
end

T["hook"] = MiniTest.new_set()

T["hook"]["maps agy events to states and stores the conversation id"] = function()
	two_agents()
	child.lua([[
		function hook(event, stdin)
			local env = { NVIM = vim.v.servername, CREW_ID = tostring(a.id) }
			return run({ vim.v.progpath, "--clean", "--headless", "-l", "scripts/hook.lua", event }, env, stdin)
		end
	]])
	child.lua([[hook("PreInvocation", '{"conversationId":"c1"}')]])
	eq(child.lua_get("a.state"), "work")
	eq(child.lua_get("a.session_id"), "c1")
	child.lua([[a.state = nil; hook("PostToolUse", '{"conversationId":"c1"}')]])
	eq(child.lua_get("a.state"), "work")
	child.lua([[hook("Stop", '{"conversationId":"c2","terminationReason":"NO_TOOL_CALL"}')]])
	eq(child.lua_get("a.state"), "done")
	eq(child.lua_get("a.session_id"), "c2")
end

T["hook"]["the plugin command exits 0 with valid JSON and no $NVIM"] = function()
	dirs({})
	two_agents()
	child.lua("bridge.install()")
	local res = child.lua_get([[run(
		{ "sh", "-c", read_json(bridge.config_dir .. "/plugins/crew/hooks.json").crew.Stop[1].command },
		{ clear = true, PATH = vim.env.PATH, HOME = vim.env.HOME },
		"{}"
	)]])
	eq(res, { code = 0, stdout = "{}\n" })
end

T["statusline"] = MiniTest.new_set()

-- Run the bridge with `stdin`, chaining a fake original that prints ORIG.
local function statusline(env, stdin)
	return child.lua_get(
		[[(function(env, stdin)
			local original = vim.fn.tempname()
			vim.fn.writefile({ vim.json.encode({ statusLine = { command = "cat > /dev/null; echo ORIG" } }) }, original)
			env.PATH, env.HOME = vim.env.PATH, vim.env.HOME
			env.clear = true
			env.CREW_ID = env.CREW_ID and tostring(a.id) or nil
			env.NVIM = env.NVIM and vim.v.servername or nil
			return run({ vim.v.progpath, "--clean", "--headless", "-l", "scripts/agy_statusline.lua", original }, env, stdin)
		end)(...)]],
		{ env, stdin }
	)
end

T["statusline"]["forwards ask, context and the conversation id, then chains the original"] = function()
	two_agents()
	local res = statusline(
		{ NVIM = true, CREW_ID = true },
		'{"tool_confirmation_pending":true,"context_window":{"used_percentage":42},"conversation_id":"c3"}'
	)
	eq(res, { code = 0, stdout = "ORIG\n" })
	eq(child.lua_get("a.state"), "ask")
	eq(child.lua_get("a.usage.ctx"), 42)
	eq(child.lua_get("a.session_id"), "c3")
	statusline({ NVIM = true, CREW_ID = true }, '{"agent_state":"tool_use","conversation_id":"c3"}')
	eq(child.lua_get("a.state"), "work")
end

-- Shape of a real agy run: two weekly buckets, the model picks one.
local QUOTA = '"quota":{"gemini-weekly":{"remaining_fraction":0.9378,"reset_time":"2026-07-06T07:50:32Z"},'
	.. '"3p-weekly":{"remaining_fraction":0.5,"reset_time":"2026-07-07T00:00:00Z"}}'

T["screen"] = MiniTest.new_set()

-- An agy agent whose terminal draws agy's selector footer, then, after
-- `clear_after` seconds when given, scrolls it out of view.
local function selector(clear_after)
	local script = [[printf 'Question 1/1: allow?\n> 1. Allow\n  ↑/↓ Navigate · enter Select · esc Skip\n']]
	if clear_after then
		script = script .. ("; sleep %d; i=0; while [ $i -lt 80 ]; do echo working; i=$((i+1)); done"):format(clear_after)
	end
	child.lua(
		[[
		require("crew").setup({ agents = { g = { adapter = "agy", cmd = { "sh", "-c", ... .. "; sleep 5" } } } })
		ws, state = require("crew.workspace"), require("crew.state")
		notes = {}
		vim.notify = function(msg) notes[#notes + 1] = msg end
		g = ws.open("g")
		g.state = "work"
		ws.editor()
	]],
		{ script }
	)
end

T["screen"]["agy's selector footer means it waits on you"] = function()
	selector()
	child.lua("vim.wait(3000, function() return g.state == 'ask' end)")
	eq(child.lua_get("g.state"), "ask")
	eq(child.lua_get("#notes > 0"), true)
end

T["screen"]["the footer leaving the screen goes back to work"] = function()
	selector(1)
	child.lua("vim.wait(3000, function() return g.state == 'ask' end)")
	child.lua("vim.wait(4000, function() return g.state == 'work' end)")
	eq(child.lua_get("g.state"), "work")
end

T["statusline"]["a Gemini model fills the week limit from gemini-weekly"] = function()
	two_agents()
	statusline({ NVIM = true, CREW_ID = true }, '{"model":{"id":"Gemini 3.8 Flash (High)"},' .. QUOTA .. "}")
	local week = child.lua_get("require('crew.state').limits[a.agent].seven_day")
	eq(math.floor(week.pct * 100 + 0.5), 622) -- 6.22% used
	eq(week.resets_at, child.lua_get("require('crew.state').epoch('2026-07-06T07:50:32Z')"))
	eq(child.lua_get("require('crew.state').limits[a.agent].five_hour"), vim.NIL)
end

T["statusline"]["a third party model fills the week limit from 3p-weekly"] = function()
	two_agents()
	statusline({ NVIM = true, CREW_ID = true }, '{"model":{"id":"Claude Sonnet"},' .. QUOTA .. "}")
	eq(child.lua_get("require('crew.state').limits[a.agent].seven_day.pct"), 50)
end

T["statusline"]["leaves a done agent alone while idle"] = function()
	two_agents()
	child.lua([[a.state = "done"]])
	statusline({ NVIM = true, CREW_ID = true }, '{"agent_state":"idle"}')
	eq(child.lua_get("a.state"), "done")
end

T["statusline"]["CREW_STATUSLINE_OFF hides the original but still forwards"] = function()
	two_agents()
	local res = statusline({ NVIM = true, CREW_ID = true, CREW_STATUSLINE_OFF = "1" }, '{"tool_confirmation_pending":true}')
	eq(res, { code = 0, stdout = "" })
	eq(child.lua_get("a.state"), "ask")
end

T["statusline"]["outside crew only chains the original"] = function()
	two_agents()
	local res = statusline({}, '{"tool_confirmation_pending":true}')
	eq(res, { code = 0, stdout = "ORIG\n" })
	eq(child.lua_get("a.state"), vim.NIL)
end

T["adapter"] = MiniTest.new_set()

T["adapter"]["prepare passes statusline = false as CREW_STATUSLINE_OFF"] = function()
	child.lua([[agy = require("crew.adapters.agy")]])
	local off = child.lua_get([[{ agy.prepare({ "agy" }, { cmd = { "agy" }, statusline = false }) }]])
	eq(off, { { "agy" }, { CREW_STATUSLINE_OFF = "1" } })
	eq(child.lua_get([[{ agy.prepare({ "agy" }, { cmd = { "agy" } }) }]]), { { "agy" } })
end

T["adapter"]["restore falls back to the last conversation of the cwd"] = function()
	dirs({})
	child.lua([[
		require("crew").setup({ agents = { agy = { cmd = { "agy" } } } })
		started = {}
		local jobstart = vim.fn.jobstart
		vim.fn.jobstart = function(cmd, o)
			started[#started + 1] = cmd
			return jobstart({ "sh" }, o)
		end
		vim.fn.mkdir(agy.data_dir .. "/cache", "p")
		vim.fn.writefile({ vim.json.encode({ ["/work/x"] = "c9" }) }, agy.data_dir .. "/cache/last_conversations.json")
		vim.fn.mkdir(persist.dir, "p")
		vim.fn.writefile({ vim.json.encode({ version = 1, agents = { { agent = "agy", cwd = "/work/x" } } }) }, persist.path())
	]])
	eq(child.lua_get("persist.restore()"), 1)
	eq(child.lua_get("started[1]"), { "agy", "--conversation", "c9" })
	eq(child.lua_get("require('crew.workspace').workspaces[1].session_id"), "c9")
end

T["adapter"]["health suggests :Crew setup agy until it is installed"] = function()
	dirs({})
	child.lua([[
		lines = {}
		local function add(kind) return function(msg) lines[#lines + 1] = kind .. ": " .. msg end end
		report = { ok = add("ok"), info = add("info"), warn = add("warn"), error = add("error") }
		agy.health({ cmd = { "agy" } }, report)
	]])
	match(table.concat(child.lua_get("lines"), "\n"), "warn: .*:Crew setup agy")
	child.lua("lines = {}; bridge.install(); agy.health({ cmd = { 'agy' } }, report)")
	match(table.concat(child.lua_get("lines"), "\n"), "ok: ")
end

T["picker"] = MiniTest.new_set()

T["picker"]["hides a session open in this Neovim"] = function()
	child.lua([[
		config_dir = vim.fn.tempname()
		require("crew").setup({
			agents = { claude = { cmd = { "claude" }, env = { CLAUDE_CONFIG_DIR = config_dir }, hooks = false } },
		})
		local jobstart = vim.fn.jobstart
		vim.fn.jobstart = function(_, o) return jobstart({ "sh" }, o) end
		local project = require("crew.sessions").dir(require("crew.config").options.agents.claude, vim.fn.getcwd())
		vim.fn.mkdir(project, "p")
		for _, id in ipairs({ "aaa", "bbb" }) do
			vim.fn.writefile({ vim.json.encode({ type = "ai-title", aiTitle = "Title " .. id }) }, project .. "/" .. id .. ".jsonl")
		end
		local ws = require("crew.workspace")
		ws.open("claude")
		ws.current().session_id = "aaa"
		vim.ui.select = function(items, opts) shown = vim.tbl_map(opts.format_item, items) end
		require("crew.picker").sessions("claude")
	]])
	local rows = child.lua_get("shown")
	eq(#rows, 1)
	match(rows[1], "Title bbb", true)
end

return T
