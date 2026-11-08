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

--- Milliseconds between spinner frames of a working agent.
M.spin_interval = 120

local spin_timer ---@type uv.uv_timer_t?
local frame = 1

---@return string[]? frames Nil when icons.work is a single still icon
local function work_frames()
	local work = require("crew.config").options.icons.work
	return type(work) == "table" and #work > 1 and work or nil
end

---@return boolean
local function someone_works()
	for _, ws in pairs(require("crew.workspace").workspaces) do
		if ws.state == "work" then
			return true
		end
	end
	return false
end

--- Pill icon of a state: the current spinner frame for work.
---@param state? crew.State
---@return string?
function M.icon(state)
	local icon = state and require("crew.config").options.icons[state]
	if type(icon) == "table" then
		return icon[(frame - 1) % #icon + 1]
	end
	return icon
end

--- Next spinner frame, then redraw the pills.
function M.spin_step()
	frame = frame + 1
	vim.cmd.redrawtabline()
	vim.cmd.redrawstatus({ bang = true })
end

---@return boolean
function M.spinning()
	return spin_timer ~= nil
end

--- Start or stop the spinner depending on whether an agent works.
function M.update_spin()
	if work_frames() and someone_works() then
		if not spin_timer then
			frame = 1
			spin_timer = assert(vim.uv.new_timer())
			spin_timer:start(M.spin_interval, M.spin_interval, vim.schedule_wrap(M.spin_step))
		end
	elseif spin_timer then
		spin_timer:stop()
		spin_timer:close()
		spin_timer = nil
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
---@param ws crew.Workspace
---@return crew.State?
local function next_state(event, payload, ws)
	-- Claude: UserPromptSubmit. agy: PreInvocation, before every model call.
	if event == "UserPromptSubmit" or event == "PreInvocation" or event == "PostToolUse" then
		return "work"
	elseif event == "StatusLine" then
		-- agy's status line runs on every refresh, so only a change counts:
		-- a pending tool confirmation asks, and answering it goes back to work.
		if payload.pending then
			return "ask"
		elseif ws.state == "ask" and payload.busy and not ws.waiting then
			return "work"
		end
	elseif event == "Screen" then
		-- agy has no "waiting on you" event, so crew watches its terminal for
		-- the selector it draws (see crew.screen). Only a change counts.
		if payload.waiting and not ws.waiting then
			ws.waiting = true
			return "ask"
		elseif not payload.waiting and ws.waiting then
			ws.waiting = false
			return ws.state == "ask" and "work" or nil
		end
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
	M.update_spin()
	vim.cmd.redrawtabline()
	vim.cmd.redrawstatus({ bang = true })
end

--- Entry point for scripts/hook.lua and scripts/agy_statusline.lua.
---@param id integer
---@param event string
---@param payload? table
function M.report(id, event, payload)
	local ws = find(id)
	if not ws then
		return
	end
	payload = payload or {}
	-- Every event carries the current session, so /clear moves it forward.
	if type(payload.session_id) == "string" and payload.session_id ~= "" and payload.session_id ~= ws.session_id then
		ws.session_id = payload.session_id
		require("crew.persist").save()
	end
	local new = next_state(event, payload, ws)
	if new then
		set(ws, new)
	end
end

--- Rate limits per profile. They belong to the account behind the profile,
--- so every instance of that profile shows the same numbers.
---@type table<string, { five_hour?: crew.Limit, seven_day?: crew.Limit }>
M.limits = {}

--- Epoch seconds from a number or an ISO 8601 UTC string.
---@param value number|string|nil
---@return integer?
function M.epoch(value)
	if type(value) == "number" then
		return math.floor(value)
	end
	if type(value) ~= "string" then
		return nil
	end
	local y, mo, d, h, mi, s = value:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
	if not y then
		return nil
	end
	local local_time = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s, isdst = false })
	return local_time + (os.time() - os.time(os.date("!*t") --[[@as osdateparam]]))
end

---@param limit? { pct?: number, resets_at?: number|string }
---@return crew.Limit?
local function normalize(limit)
	if not (limit and limit.pct) then
		return nil
	end
	return { pct = limit.pct, resets_at = M.epoch(limit.resets_at) }
end

--- Entry point for scripts/statusline.lua and scripts/agy_statusline.lua.
---@param id integer
---@param data { ctx?: number, cwd?: string, five_hour?: table, seven_day?: table }
function M.usage(id, data)
	local ws = find(id)
	if not ws then
		return
	end
	if data.cwd and data.cwd ~= ws.cwd then
		ws.cwd = data.cwd
		require("crew.workspace").refresh_branch(ws)
	end
	ws.usage = ws.usage or {}
	ws.usage.ctx = data.ctx or ws.usage.ctx
	local limits = M.limits[ws.agent] or {}
	limits.five_hour = normalize(data.five_hour) or limits.five_hour
	limits.seven_day = normalize(data.seven_day) or limits.seven_day
	M.limits[ws.agent] = limits
	vim.cmd.redrawtabline() -- the agent header shows these meters
end

--- The user entered a workspace tab: done means "not seen yet", so clear it.
function M.seen()
	local ws = require("crew.workspace").current()
	if ws and ws.state == "done" then
		set(ws, nil)
	end
	M.update_blink()
	M.update_spin()
end

return M
