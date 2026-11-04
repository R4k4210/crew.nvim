-- Workspace picker. Goes through vim.ui.select, so it looks like whatever
-- UI the user has (snacks, telescope, fzf-lua, or the builtin list).
-- Unlike the pills, it shows agent names.
local config = require("crew.config")

local M = {}

---@param entry crew.Entry
---@return string
local function format(entry)
	local text = ("%d  %s"):format(entry.slot, entry.agent or "editor")
	local icon = entry.state and config.options.icons[entry.state]
	return icon and (text .. "  " .. icon) or text
end

function M.pick()
	local entries = require("crew.status").list()
	if #entries == 0 then
		entries = { { slot = 1, current = true } } -- no agents yet: only the editor
	end
	vim.ui.select(entries, { prompt = "Crew agents", format_item = format }, function(entry)
		if entry then
			require("crew.workspace").jump(entry.slot)
		end
	end)
end

return M
