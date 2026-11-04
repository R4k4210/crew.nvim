-- Status core: the data every UI adapter reads (bufferline, lualine, ...).
-- It knows nothing about any statusline plugin. Adapters only translate
-- pills() into the format their host expects.
local config = require("crew.config")
local workspace = require("crew.workspace")

---@alias crew.State "work"|"ask"|"done"

---@class crew.Entry
---@field editor? boolean True for the editor entry, which has no slot
---@field slot? integer Agent number 1..N, nil for the editor
---@field agent? string Agent profile, nil for the editor
---@field state? crew.State
---@field current boolean True for the tab the user is in

---@class crew.Pill
---@field kind "editor"|"agent"|"more" "more" stands for agents hidden outside the window
---@field slot? integer Agent number, nil for the editor and markers
---@field text string Ready to render, e.g. " 2 ? "
---@field hl string Highlight group name

local M = {}

--- Context from the instance, limits from its profile (shared by every
--- instance of that profile), falling back to what the instance holds.
---@param ws crew.Workspace
---@return crew.Usage?
local function usage_of(ws)
	local own = ws.usage or {}
	local shared = require("crew.state").limits[ws.agent] or {}
	local usage = {
		ctx = own.ctx,
		five_hour = shared.five_hour or own.five_hour,
		seven_day = shared.seven_day or own.seven_day,
	}
	return next(usage) and usage or nil
end

--- The editor first, then agents in slot order. Empty when no agent is
--- open, so adapters render nothing until there is something to switch to.
---@return crew.Entry[]
function M.list()
	if next(workspace.workspaces) == nil then
		return {}
	end
	local current = workspace.current()
	local entries = { { editor = true, current = current == nil } }
	for _, ws in ipairs(workspace.ordered()) do
		entries[#entries + 1] = {
			slot = ws.slot,
			agent = ws.agent,
			state = ws.state,
			name = ws.name,
			usage = usage_of(ws),
			current = ws == current,
		}
	end
	return entries
end

local STATE_HL = {
	work = "CrewPillWork",
	ask = "CrewPillAsk",
	done = "CrewPillDone",
}

---@param state? crew.State
---@return string
local function state_hl(state)
	if state == "ask" and require("crew.state").blink then
		return "CrewPillAskBlink" -- second phase of the blink, flipped by a timer
	end
	return state and STATE_HL[state] or "CrewPill"
end

-- Most urgent first: a marker shows the state that needs you soonest.
local URGENCY = { ask = 3, done = 2, work = 1 }

--- Marker for agents hidden on one side of the window, colored by the most
--- urgent state among them so a waiting agent is never out of sight.
---@param hidden crew.Entry[]
---@param fmt string
---@return crew.Pill
local function marker(hidden, fmt)
	local top
	for _, e in ipairs(hidden) do
		if e.state and URGENCY[e.state] > (top and URGENCY[top] or 0) then
			top = e.state
		end
	end
	return { kind = "more", text = fmt:format(#hidden), hl = top and state_hl(top) or "CrewPillMore" }
end

--- First agent of the window: max agents around the current one (in the
--- editor, around the last visited agent, else from agent 1), clamped so
--- the window never runs past either end.
---@param agents crew.Entry[]
---@param max integer
---@return integer
local function window_start(agents, max)
	-- Slots match list positions, so workspace.last indexes agents directly.
	local last = workspace.last
	local center = (last and agents[last]) and last or 1
	for i, e in ipairs(agents) do
		if e.current then
			center = i
		end
	end
	local start = center - math.floor((max - 1) / 2)
	return math.max(1, math.min(start, #agents - max + 1))
end

--- The editor pill, then a window of agent pills with a marker on each side
--- that hides agents. Each agent pill is its number plus the state icon.
--- Names stay out of the pills on purpose, they take too much room; the
--- picker shows them.
---@return crew.Pill[]
function M.pills()
	local entries = M.list()
	if #entries == 0 then
		return {}
	end
	local icons = config.options.icons
	local editor = table.remove(entries, 1)
	local pills = { {
		kind = "editor",
		text = (" %s "):format(config.options.editor.label),
		hl = editor.current and "CrewPillEditorCurrent" or "CrewPillEditor",
	} }

	local max = math.max(1, config.options.pills.max)
	local first, last = 1, #entries
	if #entries > max then
		first = window_start(entries, max)
		last = first + max - 1
	end
	if first > 1 then
		pills[#pills + 1] = marker(vim.list_slice(entries, 1, first - 1), " ‹%d ")
	end
	for i = first, last do
		local entry = entries[i]
		local icon = entry.state and icons[entry.state]
		pills[#pills + 1] = {
			kind = "agent",
			slot = entry.slot,
			text = icon and (" %d %s "):format(entry.slot, icon) or (" %d "):format(entry.slot),
			hl = entry.current and "CrewPillCurrent" or state_hl(entry.state),
		}
	end
	if last < #entries then
		pills[#pills + 1] = marker(vim.list_slice(entries, last + 1, #entries), " %d› ")
	end
	return pills
end

--- Header for an agent tab: slot, profile and name, then cwd and branch,
--- then the usage meters. Nil when the tab is not an agent (the editor).
---@param ws? crew.Workspace defaults to the agent in the current tab
---@return crew.Chunk[]?
function M.header(ws)
	ws = ws or workspace.current()
	if not ws then
		return nil
	end
	local percent = require("crew.picker").percent
	local usage = usage_of(ws) or {}
	local chunks = { { (" %d %s"):format(ws.slot, ws.agent), "CrewHeader" } }
	if ws.name then
		chunks[#chunks + 1] = { " " .. ws.name, "CrewHeaderName" }
	end
	if ws.cwd then
		chunks[#chunks + 1] = { "  " .. vim.fn.fnamemodify(ws.cwd, ":~"), "CrewHeaderDim" }
	end
	if ws.branch then
		chunks[#chunks + 1] = { "  " .. ws.branch, "CrewHeaderDim" }
	end
	for _, meter in ipairs({
		{ "   ctx ", usage.ctx },
		{ "  5h ", usage.five_hour and usage.five_hour.pct },
		{ "  wk ", usage.seven_day and usage.seven_day.pct },
	}) do
		chunks[#chunks + 1] = { meter[1], "CrewHeaderDim" }
		chunks[#chunks + 1] = percent(meter[2])
	end
	chunks[#chunks + 1] = { " ", "CrewHeaderDim" }
	return chunks
end

--- Winbar expression target: the header of the agent that owns the window
--- being drawn, as a statusline string.
---@return string
function M.winbar()
	local win = vim.g.statusline_winid or vim.api.nvim_get_current_win()
	local tab = vim.api.nvim_win_get_tabpage(win)
	for _, ws in pairs(workspace.workspaces) do
		if ws.tab == tab then
			local parts = {}
			for i, c in ipairs(M.header(ws) or {}) do
				parts[#parts + 1] = ("%%#%s#%s"):format(c[2] or "Normal", (c[1]:gsub("%%", "%%%%")))
				if i == (ws.name and 2 or 1) then
					-- Truncate after slot, profile and name: on a narrow window the
					-- cwd gets cut, never the part that says which agent this is.
					parts[#parts + 1] = "%<"
				end
			end
			return table.concat(parts)
		end
	end
	return ""
end

return M
