-- Agent state. Hook reports arrive over RPC from scripts/hook.lua and move a
-- workspace between work, ask and done. Reports carry the workspace id, not
-- its slot, because slots get renumbered when a workspace closes.
local M = {}

--- Phase of the ask blink, flipped by a timer while some agent waits.
M.blink = false

---@type uv.uv_timer_t?
local timer

---@return boolean
local function someone_waits()
	local current = require("crew.workspace").current()
	for _, ws in pairs(require("crew.workspace").workspaces) do
		if ws.state == "ask" and ws ~= current then
			return true
		end
	end
	return false
end

--- Start or stop the blink timer depending on whether an agent waits.
function M.update_blink()
	if someone_waits() then
		if not timer then
			timer = assert(vim.uv.new_timer())
			timer:start(0, 600, vim.schedule_wrap(function()
				M.blink = not M.blink
				vim.cmd.redrawtabline()
				vim.cmd.redrawstatus({ bang = true })
			end))
		end
	elseif timer then
		timer:stop()
		timer:close()
		timer = nil
		M.blink = false
	end
end

---@param id integer
---@return crew.Workspace?
local function find(id)
	for _, ws in pairs(require("crew.workspace").workspaces) do
		if ws.id == id then
			return ws
		end
	end
end

--- New state for a hook event, or nil to leave the current one.
---@param event string
---@param payload table
---@return crew.State?
local function next_state(event, payload)
	if event == "UserPromptSubmit" or event == "PostToolUse" then
		return "work"
	elseif event == "Stop" then
		return "done"
	elseif event == "Notification" then
		-- idle_prompt fires after a quiet minute; the agent is not asking anything
		if payload.notification_type ~= "idle_prompt" then
			return "ask"
		end
	end
end

---@param ws crew.Workspace
---@param new crew.State?
local function set(ws, new)
	local workspace = require("crew.workspace")
	if new == "done" and ws == workspace.current() then
		new = nil -- you are already looking at it
	end
	if ws.state == new then
		return
	end
	ws.state = new
	if new == "ask" and ws ~= workspace.current() then
		local who = ws.name and ("%d %s"):format(ws.slot, ws.name) or ("%d %s"):format(ws.slot, ws.agent)
		vim.notify(("%s needs input"):format(who), vim.log.levels.WARN, { title = "crew" })
	end
	M.update_blink()
	vim.cmd.redrawtabline()
	vim.cmd.redrawstatus({ bang = true })
end

--- Entry point for scripts/hook.lua.
---@param id integer
---@param event string
---@param payload? table
function M.report(id, event, payload)
	local ws = find(id)
	if not ws then
		return
	end
	local new = next_state(event, payload or {})
	if new then
		set(ws, new)
	end
end

--- The user entered a workspace tab: done means "not seen yet", so clear it.
function M.seen()
	local ws = require("crew.workspace").current()
	if ws and ws.state == "done" then
		set(ws, nil)
	end
	M.update_blink()
end

return M
