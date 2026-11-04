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
---@field slot? integer Agent number, nil for the editor
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

--- One pill per entry: the slot number plus the state icon. Names stay out
--- of the pills on purpose, they take too much room; the picker shows them.
---@return crew.Pill[]
function M.pills()
	local icons = config.options.icons
	local pills = {}
	for _, entry in ipairs(M.list()) do
		local icon = entry.state and icons[entry.state]
		local hl = "CrewPill"
		if entry.editor then
			hl = entry.current and "CrewPillEditorCurrent" or "CrewPillEditor"
		elseif entry.current then
			hl = "CrewPillCurrent"
		elseif entry.state == "ask" and require("crew.state").blink then
			hl = "CrewPillAskBlink" -- second phase of the blink, flipped by a timer
		elseif entry.state then
			hl = STATE_HL[entry.state]
		end
		local text
		if entry.editor then
			text = (" %s "):format(config.options.editor.label)
		else
			text = icon and (" %d %s "):format(entry.slot, icon) or (" %d "):format(entry.slot)
		end
		pills[#pills + 1] = { slot = entry.slot, text = text, hl = hl }
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
