-- Hook settings injection, the agent state machine, agent env and blink.
local H = dofile("tests/helpers.lua")
local eq, match = H.eq, H.match
local child, T = H.new()

T["hooks.command"] = MiniTest.new_set({
	hooks = {
		pre_case = function()
			child.lua([[
				hooks = require("crew.hooks")
				settings_of = function(cmd) return vim.json.decode(cmd[vim.fn.index(cmd, "--settings") + 2]) end
			]])
		end,
	},
})

T["hooks.command"]["adds --settings when missing"] = function()
	eq(child.lua_get('vim.fn.index(hooks.command({ "claude" }), "--settings") >= 0'), true)
end

T["hooks.command"]["settings has the four hook events"] = function()
	local events = child.lua_get('vim.tbl_keys(settings_of(hooks.command({ "claude" })).hooks)')
	table.sort(events)
	eq(events, { "Notification", "PostToolUse", "Stop", "UserPromptSubmit" })
end

T["hooks.command"]["hook command calls scripts/hook.lua with the event"] = function()
	local cmd = child.lua_get('settings_of(hooks.command({ "claude" })).hooks.Stop[1].hooks[1].command')
	match(cmd, "scripts/hook.lua", true)
	match(cmd, "Stop", true)
end

T["hooks.command"]["hook command is guarded by $NVIM and never fails"] = function()
	local cmd = child.lua_get('settings_of(hooks.command({ "claude" })).hooks.Stop[1].hooks[1].command')
	match(cmd, '"$NVIM"', true)
	match(cmd, "|| true", true)
end

T["hooks.command"]["merges with the user's own --settings"] = function()
	child.lua([[merged = hooks.command({ "claude", "--settings",
		'{"tui":"default","hooks":{"Stop":[{"hooks":[{"type":"command","command":"mine"}]}]}}' })]])
	eq(child.lua_get('#vim.tbl_filter(function(a) return a == "--settings" end, merged)'), 1)
	child.lua("m = vim.json.decode(merged[3])")
	eq(child.lua_get("m.tui"), "default")
	eq(child.lua_get("#m.hooks.Stop"), 2)
	eq(child.lua_get("m.hooks.Stop[1].hooks[1].command"), "mine")
end

T["hooks.command"]["leaves other commands untouched"] = function()
	eq(child.lua_get('hooks.command({ "codex" })'), { "codex" })
end

T["hooks.command"]["hooks = false opts out"] = function()
	eq(child.lua_get('hooks.command({ "claude" }, false)'), { "claude" })
end

T["hooks.command"]["does not mutate the config table"] = function()
	eq(child.lua_get('(function() local c = { "claude" }; hooks.command(c); return #c end)()'), 1)
end

T["state"] = MiniTest.new_set()

-- Slots 2 (a) and 3 (b), back in the editor; toasts are recorded in `notes`.
local function two_agents()
	child.lua([[
		require("crew").setup({ agents = { sh = { cmd = { "sh" } } } })
		ws, state = require("crew.workspace"), require("crew.state")
		notes = {}
		vim.notify = function(msg, level) notes[#notes + 1] = { msg, level } end
		ws.open("sh"); ws.open("sh")
		a, b = ws.workspaces[2], ws.workspaces[3]
		ws.jump(1)
	]])
end

T["state"]["each workspace gets a stable id"] = function()
	two_agents()
	eq(child.lua_get("a.id ~= nil and b.id ~= nil"), true)
	H.neq(child.lua_get("a.id"), child.lua_get("b.id"))
end

T["state"]["follows the hook events"] = function()
	two_agents()
	child.lua('state.report(a.id, "UserPromptSubmit", {})')
	eq(child.lua_get("a.state"), "work")
	child.lua('state.report(a.id, "Notification", { notification_type = "permission_prompt" })')
	eq(child.lua_get("a.state"), "ask")
	child.lua('state.report(a.id, "PostToolUse", {})')
	eq(child.lua_get("a.state"), "work")
	child.lua('state.report(a.id, "Stop", {})')
	eq(child.lua_get("a.state"), "done")
	child.lua('state.report(a.id, "Notification", { notification_type = "idle_prompt" })')
	eq(child.lua_get("a.state"), "done")
end

T["state"]["ask while away shows a toast"] = function()
	two_agents()
	child.lua('state.report(a.id, "Notification", { notification_type = "permission_prompt" })')
	eq(child.lua_get("#notes"), 1)
	match(child.lua_get("notes[1][1]"), "2", true)
end

T["state"]["unknown id is ignored"] = function()
	two_agents()
	eq(child.lua_get('(pcall(state.report, 999, "Stop", {}))'), true)
	eq(child.lua_get("a.state == nil and b.state == nil"), true)
end

T["state"]["no toast for the agent you are looking at"] = function()
	two_agents()
	child.lua([[
		ws.jump(3)
		state.report(b.id, "Notification", { notification_type = "permission_prompt" })
	]])
	eq(child.lua_get("#notes"), 0)
end

T["state"]["visiting a done agent clears done"] = function()
	two_agents()
	child.lua('state.report(a.id, "Stop", {}); ws.jump(2)')
	eq(child.lua_get("a.state"), vim.NIL)
end

T["state"]["id survives compaction"] = function()
	two_agents()
	child.lua("ws.close(2)")
	eq(child.lua_get("ws.workspaces[2] == b"), true)
	child.lua('state.report(b.id, "Stop", {})')
	eq(child.lua_get("b.state"), "done")
end

T["agent env has CREW_ID and NVIM"] = function()
	child.lua([[
		out = vim.fn.tempname()
		require("crew").setup({ agents = { env = { cmd = { "sh", "-c", "echo $CREW_ID:$NVIM > " .. out .. "; sleep 5" } } } })
		ws = require("crew.workspace")
		ws.open("env")
		e = ws.current()
		vim.wait(2000, function() return vim.fn.filereadable(out) == 1 and #vim.fn.readfile(out) > 0 end)
		line = vim.fn.readfile(out)[1] or ""
	]])
	eq(child.lua_get('line:match("^(%d+):")'), child.lua_get("tostring(e.id)"))
	H.neq(child.lua_get('line:match(":(.+)$")'), vim.NIL)
end

T["blink"] = MiniTest.new_set()

T["blink"]["ask pill alternates between two highlights"] = function()
	child.lua([[
		require("crew").setup({ agents = { sh = { cmd = { "sh" } } } })
		ws, state, status = require("crew.workspace"), require("crew.state"), require("crew.status")
		ws.open("sh")
		ws.workspaces[2].state = "ask"
		ws.jump(1)
	]])
	local hls = child.lua_get([[(function()
		local function ask_hl() for _, p in ipairs(status.pills()) do if p.slot == 2 then return p.hl end end end
		state.blink = false
		local h1 = ask_hl()
		state.blink = true
		return { h1, ask_hl() }
	end)()]])
	eq(hls, { "CrewPillAsk", "CrewPillAskBlink" })
end

T["blink"]["CrewPillAskBlink exists"] = function()
	eq(child.lua_get('vim.api.nvim_get_hl(0, { name = "CrewPillAskBlink" }).link ~= nil'), true)
end

return T
