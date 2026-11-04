-- Pills, highlights, bufferline right side and the lualine component.
local H = dofile("tests/helpers.lua")
local eq, match = H.eq, H.match
local child, T = H.new()

local function setup(opts)
	child.lua([[
		require("crew").setup(vim.tbl_extend("force", { agents = { sh = { cmd = { "sh" } } }, default_agent = "sh" }, ... or {}))
		ws = require("crew.workspace")
		status = require("crew.status")
	]], { opts })
end

-- Two agents: 1 and 2, agent 2 is current.
local function open_two()
	setup()
	child.lua("ws.open(); ws.open()")
end

T["crew.status loads"] = function()
	eq(child.lua_get('(pcall(require, "crew.status"))'), true)
end

T["no pills without agents"] = function()
	setup()
	eq(child.lua_get("#status.pills()"), 0)
end

T["pills"] = MiniTest.new_set()

T["pills"]["one per workspace, editor included"] = function()
	open_two()
	eq(child.lua_get("#status.pills()"), 3)
end

T["pills"]["agent text has the number only"] = function()
	open_two()
	eq(child.lua_get("status.pills()[2].text"), " 1 ")
	eq(child.lua_get("status.pills()[3].text"), " 2 ")
end

T["pills"]["current uses CrewPillCurrent, others CrewPill"] = function()
	open_two()
	eq(child.lua_get("status.pills()[3].hl"), "CrewPillCurrent")
	eq(child.lua_get("status.pills()[2].hl"), "CrewPill")
end

T["pills"]["ask shows ? with CrewPillAsk"] = function()
	open_two()
	child.lua('ws.workspaces[1].state = "ask"')
	eq(child.lua_get("status.pills()[2].text"), " 1 ? ")
	eq(child.lua_get("status.pills()[2].hl"), "CrewPillAsk")
end

T["pills"]["done shows a check"] = function()
	open_two()
	child.lua('ws.workspaces[1].state = "done"')
	eq(child.lua_get("status.pills()[2].text"), " 1 ✓ ")
end

T["pills"]["closing compacts them"] = function()
	open_two()
	child.lua("ws.close(1)")
	eq(child.lua_get("#status.pills()"), 2)
end

T["editor pill"] = MiniTest.new_set()

T["editor pill"]["shows the default label"] = function()
	open_two()
	eq(child.lua_get("status.pills()[1].text"), " E ")
end

T["editor pill"]["shows a custom label"] = function()
	setup({ editor = { label = "H" } })
	child.lua("ws.open()")
	eq(child.lua_get("status.pills()[1].text"), " H ")
end

T["editor pill"]["uses CrewPillEditor when you are elsewhere"] = function()
	open_two()
	eq(child.lua_get("status.pills()[1].hl"), "CrewPillEditor")
end

T["editor pill"]["uses CrewPillEditorCurrent in the editor"] = function()
	open_two()
	child.lua("ws.editor()")
	eq(child.lua_get("status.pills()[1].hl"), "CrewPillEditorCurrent")
	eq(child.lua_get("status.pills()[2].hl"), "CrewPill")
end

T["list exposes state and agent"] = function()
	open_two()
	child.lua('ws.workspaces[1].state = "done"')
	eq(child.lua_get("status.list()[2].state"), "done")
	eq(child.lua_get("status.list()[2].agent"), "sh")
	eq(child.lua_get("status.list()[2].slot"), 1)
end

T["list starts with the editor, with no slot"] = function()
	open_two()
	eq(child.lua_get("status.list()[1].editor"), true)
	eq(child.lua_get("status.list()[1].slot"), vim.NIL)
	eq(child.lua_get("status.list()[3].slot"), 2)
end

T["highlights"] = MiniTest.new_set()

T["highlights"]["CrewPillAsk is a default link"] = function()
	eq(child.lua_get('vim.api.nvim_get_hl(0, { name = "CrewPillAsk" }).link ~= nil'), true)
end

T["highlights"]["survive :colorscheme"] = function()
	child.lua('vim.cmd.colorscheme("default")')
	eq(child.lua_get('vim.api.nvim_get_hl(0, { name = "CrewPillAsk" }).link ~= nil'), true)
end

T["highlights"]["editor groups link to Visual and TabLineSel"] = function()
	eq(child.lua_get('vim.api.nvim_get_hl(0, { name = "CrewPillEditor" }).link'), "Visual")
	eq(child.lua_get('vim.api.nvim_get_hl(0, { name = "CrewPillEditorCurrent" }).link'), "TabLineSel")
end

T["highlights"]["editor groups survive :colorscheme"] = function()
	child.lua('vim.cmd.colorscheme("default")')
	eq(child.lua_get('vim.api.nvim_get_hl(0, { name = "CrewPillEditor" }).link'), "Visual")
	eq(child.lua_get('vim.api.nvim_get_hl(0, { name = "CrewPillEditorCurrent" }).link'), "TabLineSel")
end

T["bufferline right"] = MiniTest.new_set()

T["bufferline right"]["items have text and link"] = function()
	open_two()
	child.lua('right = require("crew.bufferline").right()')
	eq(child.lua_get("type(right[1].text)"), "string")
	eq(child.lua_get("right[1].link"), "CrewPillEditor")
end

T["bufferline right"]["puts gaps between pills"] = function()
	open_two()
	eq(child.lua_get('#require("crew.bufferline").right()'), 5)
end

T["lualine component"] = function()
	open_two()
	child.lua('ws.workspaces[1].state = "done"')
	local out = child.lua_get([[(function()
		local Comp = require("lualine.components.crew")
		local comp = Comp({ self = { section = "c" }, component_separators = "", section_separators = "" })
		return comp:update_status()
	end)()]])
	match(out, "%#CrewPillCurrent#", true)
	match(out, " 1 ", true)
end

return T
