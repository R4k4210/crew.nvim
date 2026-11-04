-- Native lualine component, so the user config only needs "crew":
--   lualine_c = { "crew" }  or  { "crew", icon = "󰚩" }
-- lualine finds it because lua/lualine/components/ is on the runtimepath.
local Component = require("lualine.component"):extend()

local made = {} ---@type table<string, string> group -> "fg:bg:bold" it was last set with

vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("crew_lualine", { clear = true }),
	callback = function()
		made = {} -- :hi clear dropped them, rebuild on the next draw
	end,
})

--- A copy of `group` that keeps its foreground on the section background,
--- so a marker is a bare arrow even when the group brings its own bg (or
--- none, which the statusline would fill with StatusLine instead).
---@param group string
---@param section? string lualine section group, e.g. lualine_c_normal
---@return string
local function on_section(group, section)
	local src = vim.api.nvim_get_hl(0, { name = group, link = false })
	local bg = section and vim.api.nvim_get_hl(0, { name = section, link = false }).bg
	local name = "CrewLualine" .. group
	-- Only set when it changes: setting a group redraws the screen. The bg
	-- follows the mode, so it is part of the key.
	local key = tostring(src.fg) .. ":" .. tostring(bg) .. ":" .. tostring(src.bold)
	if made[name] ~= key then
		vim.api.nvim_set_hl(0, name, { fg = src.fg, bg = bg, bold = src.bold })
		made[name] = key
	end
	return name
end

function Component:update_status()
	local section = self:get_default_hl() -- back to the section color after each pill
	local section_group = section:match("^%%#(.-)#")
	local parts = {}
	for i, pill in ipairs(require("crew.status").pills()) do
		if i > 1 then
			parts[#parts + 1] = section .. " "
		end
		local hl = pill.kind == "more" and on_section(pill.hl, section_group) or pill.hl
		parts[#parts + 1] = ("%%#%s#%s"):format(hl, pill.text)
	end
	if #parts == 0 then
		return ""
	end
	return table.concat(parts) .. section
end

return Component
