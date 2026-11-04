-- Status core: the data every UI adapter reads (bufferline, lualine, ...).
-- It knows nothing about any statusline plugin. Adapters only translate
-- pills() into the format their host expects.
local config = require("crew.config")
local workspace = require("crew.workspace")

---@alias crew.State "work"|"ask"|"done"

---@class crew.Entry
---@field slot integer 1 is the editor, 2..9 are agents
---@field agent? string Agent profile, nil for the editor
---@field state? crew.State
---@field current boolean True for the tab the user is in

---@class crew.Pill
---@field slot integer
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

--- Workspaces in slot order, editor first. Empty when no agent is open,
--- so adapters render nothing until there is something to switch to.
---@return crew.Entry[]
function M.list()
	if next(workspace.workspaces) == nil then
		return {}
	end
	local current = workspace.current()
	local entries = { { slot = 1, current = current == nil } }
	for slot = 2, 9 do
		local ws = workspace.workspaces[slot]
		if ws then
			entries[#entries + 1] = {
				slot = slot,
				agent = ws.agent,
				state = ws.state,
				name = ws.name,
				usage = usage_of(ws),
				current = ws == current,
			}
		end
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
		if entry.current then
			hl = "CrewPillCurrent"
		elseif entry.state == "ask" and require("crew.state").blink then
			hl = "CrewPillAskBlink" -- second phase of the blink, flipped by a timer
		elseif entry.state then
			hl = STATE_HL[entry.state]
		end
		pills[#pills + 1] = {
			slot = entry.slot,
			text = icon and (" %d %s "):format(entry.slot, icon) or (" %d "):format(entry.slot),
			hl = hl,
		}
	end
	return pills
end

return M
