-- Adapter for bufferline.nvim. Usage in the bufferline options:
--   show_tab_indicators = false,
--   custom_areas = { right = require("crew.bufferline").right },
local M = {}

--- Pills in the custom_areas format: a list of { text, link }.
---@return { text: string, link?: string }[]
function M.right()
	local items = {}
	for i, pill in ipairs(require("crew.status").pills()) do
		if i > 1 then
			items[#items + 1] = { text = " " } -- gap, bufferline paints it with the fill color
		end
		items[#items + 1] = { text = pill.text, link = pill.hl }
	end
	return items
end

return M
