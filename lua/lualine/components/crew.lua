-- Native lualine component, so the user config only needs "crew":
--   lualine_c = { "crew" }  or  { "crew", icon = "󰚩" }
-- lualine finds it because lua/lualine/components/ is on the runtimepath.
local Component = require("lualine.component"):extend()

function Component:update_status()
	local section = self:get_default_hl() -- back to the section color after each pill
	local parts = {}
	for i, pill in ipairs(require("crew.status").pills()) do
		if i > 1 then
			parts[#parts + 1] = section .. " "
		end
		parts[#parts + 1] = ("%%#%s#%s"):format(pill.hl, pill.text)
	end
	if #parts == 0 then
		return ""
	end
	return table.concat(parts) .. section
end

return Component
