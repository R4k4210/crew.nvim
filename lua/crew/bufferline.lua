-- Adapter for bufferline.nvim. Usage in the bufferline options:
--   show_tab_indicators = false,
--   custom_filter = require("crew.bufferline").filter,
--   custom_areas = {
--     left = require("crew.bufferline").left,
--     right = require("crew.bufferline").right,
--   },
local M = {}

--- bufferline runs custom area text through the statusline evaluator, so a
--- literal % (as in "46%") must be doubled or it raises E539.
---@param chunks crew.Chunk[]
---@return { text: string, link?: string }[]
local function items(chunks)
	return vim.tbl_map(function(c)
		return { text = (c[1]:gsub("%%", "%%%%")), link = c[2] }
	end, chunks)
end

--- Pills in the custom_areas format: a list of { text, link }.
---@return { text: string, link?: string }[]
function M.right()
	local list = {}
	for i, pill in ipairs(require("crew.status").pills()) do
		if i > 1 then
			list[#list + 1] = { text = " " } -- gap, bufferline paints it with the fill color
		end
		list[#list + 1] = { text = pill.text, link = pill.hl }
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
