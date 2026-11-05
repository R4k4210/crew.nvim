-- statusLine injection, original statusLine discovery and usage state.
local H = dofile("tests/helpers.lua")
local eq, match = H.eq, H.match
local child, T = H.new()

local function hooks_setup()
	child.lua([[
		hooks = require("crew.hooks")
		settings_of = function(cmd) return vim.json.decode(cmd[vim.fn.index(cmd, "--settings") + 2]) end
	]])
end

T["statusLine"] = MiniTest.new_set({ hooks = { pre_case = hooks_setup } })

T["statusLine"]["is injected as a command"] = function()
	child.lua('s = settings_of(hooks.command({ "claude" }))')
	eq(child.lua_get("s.statusLine.type"), "command")
	match(child.lua_get("s.statusLine.command"), "scripts/statusline.lua", true)
end

T["statusLine"]["is guarded by $NVIM"] = function()
	match(child.lua_get('settings_of(hooks.command({ "claude" })).statusLine.command'), '"$NVIM"', true)
end

T["original statusLine"] = MiniTest.new_set({ hooks = { pre_case = hooks_setup } })

local own = { "claude", "--settings", '{"statusLine":{"type":"command","command":"echo mine"}}' }

T["original statusLine"]["comes from --settings"] = function()
	eq(child.lua_get("hooks.original_statusline(..., {})", { own }), "echo mine")
end

T["original statusLine"]["is replaced by crew's in the merged settings"] = function()
	match(child.lua_get("settings_of(hooks.command(...)).statusLine.command", { own }), "statusline.lua", true)
end

T["original statusLine"]["comes from CLAUDE_CONFIG_DIR/settings.json"] = function()
	child.lua([[
		dir = vim.fn.tempname()
		vim.fn.mkdir(dir, "p")
		vim.fn.writefile({ '{"statusLine":{"type":"command","command":"bash ~/x.sh"}}' }, dir .. "/settings.json")
	]])
	eq(child.lua_get('hooks.original_statusline({ "claude" }, { CLAUDE_CONFIG_DIR = dir })'), "bash ~/x.sh")
end

T["original statusLine"]["is nil when there is none"] = function()
	eq(child.lua_get('hooks.original_statusline({ "claude" }, { CLAUDE_CONFIG_DIR = vim.fn.tempname() })'), vim.NIL)
end

T["usage"] = MiniTest.new_set()

-- Agents 1, 2 (profile a) and 3 (profile b); agent 1 reported usage.
local function usage_setup()
	child.lua([[
		require("crew").setup({ agents = { a = { cmd = { "sh" } }, b = { cmd = { "sh" } } } })
		ws, state, status = require("crew.workspace"), require("crew.state"), require("crew.status")
		ws.open("a"); ws.open("a"); ws.open("b")
		a1, a2, b1 = ws.workspaces[1], ws.workspaces[2], ws.workspaces[3]
		reset = os.time() + 3600
		state.usage(a1.id, { ctx = 71, five_hour = { pct = 87, resets_at = reset }, seven_day = { pct = 23, resets_at = reset + 86400 } })
		usage = function(slot) for _, e in ipairs(status.list()) do if e.slot == slot then return e.usage or {} end end end
	]])
end

T["usage"]["ctx belongs to the reporting instance"] = function()
	usage_setup()
	eq(child.lua_get("usage(1).ctx"), 71)
	eq(child.lua_get("usage(2).ctx"), vim.NIL)
end

T["usage"]["limits are shared by the profile"] = function()
	usage_setup()
	eq(child.lua_get("usage(2).five_hour.pct"), 87)
	eq(child.lua_get("usage(2).seven_day.pct"), 23)
end

T["usage"]["limits do not leak to another profile"] = function()
	usage_setup()
	eq(child.lua_get("usage(3).five_hour"), vim.NIL)
end

T["usage"]["newer limits win for every instance of the profile"] = function()
	usage_setup()
	child.lua("state.usage(a2.id, { ctx = 12, five_hour = { pct = 90, resets_at = reset } })")
	eq(child.lua_get("usage(1).five_hour.pct"), 90)
	eq(child.lua_get("usage(1).ctx"), 71)
end

T["epoch"] = MiniTest.new_set()

T["epoch"]["ISO reset times become epoch seconds"] = function()
	eq(
		child.lua_get('require("crew.state").epoch("2026-11-26T18:00:00Z")'),
		child.lua_get(
			"os.time({ year = 2026, month = 11, day = 26, hour = 18, min = 0, sec = 0, isdst = false }) + (os.time() - os.time(os.date('!*t')))"
		)
	)
end

T["epoch"]["numeric reset times pass through"] = function()
	eq(child.lua_get('require("crew.state").epoch(1764180000)'), 1764180000)
end

T["agent env has CREW_STATUSLINE"] = function()
	child.lua([[
		out = vim.fn.tempname()
		-- sh stands in for claude, so pin the adapter the basename would not pick.
		require("crew").setup({ agents = { claude = { adapter = "claude", cmd = { "sh", "-c", "echo \"$CREW_STATUSLINE\" > " .. out .. "; sleep 5" } } } })
		require("crew.hooks").original_statusline = function() return "echo from-user" end
		require("crew.workspace").open("claude")
		vim.wait(2000, function() return vim.fn.filereadable(out) == 1 and #vim.fn.readfile(out) > 0 end)
	]])
	eq(child.lua_get('vim.fn.readfile(out)[1] or ""'), "echo from-user")
end

return T
