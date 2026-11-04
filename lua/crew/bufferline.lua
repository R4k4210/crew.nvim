-- Adapter for bufferline.nvim. Usage in the bufferline options:
--   show_tab_indicators = false,
--   custom_filter = require("crew.bufferline").filter,
--   custom_areas = {
--     left = require("crew.bufferline").left,
--     right = require("crew.bufferline").right,
--   },
local M = {}

local made = {} ---@type table<string, string> group -> "fg:bg" it was last set with

--- A copy of `group` that keeps its foreground on bufferline's own fill
--- background. Linking straight to groups like Comment or Normal mixes
--- backgrounds: groups without one fall back to TabLineFill, others bring
--- their own. Kept up to date (bufferline's own generated groups are
--- `default = true` and never change, which would freeze colors that move,
--- like a percentage going from green to red).
---@param group string
---@return string
local function on_fill(group)
	local fill = vim.api.nvim_get_hl(0, { name = "BufferLineFill", link = false })
	if not fill.bg then
		fill = vim.api.nvim_get_hl(0, { name = "TabLineFill", link = false })
	end
	local src = vim.api.nvim_get_hl(0, { name = group, link = false })
	local name = "CrewBufferline" .. group
	local key = tostring(src.fg) .. ":" .. tostring(fill.bg) .. ":" .. tostring(src.bold)
	if made[name] ~= key then
		vim.api.nvim_set_hl(0, name, { fg = src.fg, bg = fill.bg, bold = src.bold })
		made[name] = key
	end
	return name
end

--- bufferline runs custom area text through the statusline evaluator, so a
--- literal % (as in "46%") must be doubled or it raises E539.
---@param chunks crew.Chunk[]
---@return { text: string, link?: string }[]
local function items(chunks)
	return vim.tbl_map(function(c)
		return { text = (c[1]:gsub("%%", "%%%%")), link = on_fill(c[2] or "Normal") }
	end, chunks)
end

vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("crew_bufferline", { clear = true }),
	callback = function()
		made = {} -- :hi clear dropped them, rebuild on the next draw
	end,
})

--- Pills in the custom_areas format: a list of { text, link }.
---@return { text: string, link?: string }[]
function M.right()
	local list = {}
	for i, pill in ipairs(require("crew.status").pills()) do
		if i > 1 then
			list[#list + 1] = { text = " " } -- gap, bufferline paints it with the fill color
		end
		-- Markers are bare arrows on the fill, pills keep their boxes.
		list[#list + 1] = { text = pill.text, link = pill.kind == "more" and on_fill(pill.hl) or pill.hl }
	end
	return list
end

--- Agent header on the left, only inside agent tabs.
---@return { text: string, link?: string }[]
function M.left()
	return items(require("crew.status").header() or {})
end

--- custom_filter: editor buffers mean nothing inside an agent tab, so hide
--- them there and let the header take the line.
---@return boolean
function M.filter()
	return require("crew.workspace").current() == nil
end

return M
