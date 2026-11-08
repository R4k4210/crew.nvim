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

T["window"] = MiniTest.new_set()

-- 15 agents, current is agent n. texts() and hls() read the pills.
local function fifteen(n, opts)
	setup(opts)
	child.lua([[
		for _ = 1, 15 do ws.open() end
		ws.jump(...)
		state = require("crew.state")
		texts = function() return vim.tbl_map(function(p) return p.text end, status.pills()) end
		last_hl = function() local p = status.pills(); return p[#p].hl end
	]], { n })
end

T["window"]["shows max agents around the current one"] = function()
	fifteen(10)
	eq(child.lua_get("texts()"), { " E ", " ‹ ", " 8 ", " 9 ", " 10 ", " 11 ", " 12 ", " › " })
end

T["window"]["pills have a kind"] = function()
	fifteen(10)
	eq(child.lua_get("vim.tbl_map(function(p) return p.kind end, status.pills())"), {
		"editor", "more", "agent", "agent", "agent", "agent", "agent", "more",
	})
end

T["window"]["no left marker at the start"] = function()
	fifteen(1)
	eq(child.lua_get("texts()"), { " E ", " 1 ", " 2 ", " 3 ", " 4 ", " 5 ", " › " })
end

T["window"]["no right marker at the end"] = function()
	fifteen(15)
	eq(child.lua_get("texts()"), { " E ", " ‹ ", " 11 ", " 12 ", " 13 ", " 14 ", " 15 " })
end

T["window"]["no markers when every agent fits"] = function()
	setup()
	child.lua("for _ = 1, 5 do ws.open() end")
	eq(child.lua_get("#status.pills()"), 6)
end

T["window"]["respects pills.max"] = function()
	fifteen(10, { pills = { max = 3 } })
	eq(child.lua_get("texts()"), { " E ", " ‹ ", " 9 ", " 10 ", " 11 ", " › " })
end

T["window"]["in the editor it centers on the last visited agent"] = function()
	fifteen(10)
	child.lua("ws.editor()")
	eq(child.lua_get("texts()"), { " E ", " ‹ ", " 8 ", " 9 ", " 10 ", " 11 ", " 12 ", " › " })
end

T["window"]["in the editor with no last agent it starts from agent 1"] = function()
	fifteen(10)
	child.lua("ws.editor(); ws.last = nil")
	eq(child.lua_get("texts()"), { " E ", " 1 ", " 2 ", " 3 ", " 4 ", " 5 ", " › " })
end

T["window"]["a marker with nothing to report uses CrewPillMore"] = function()
	fifteen(10)
	eq(child.lua_get("last_hl()"), "CrewPillMore")
	eq(child.lua_get('vim.api.nvim_get_hl(0, { name = "CrewPillMore" }).link'), "Comment")
end

T["window"]["a hidden ask colors its marker and blinks between orange and dim"] = function()
	fifteen(10)
	child.lua('ws.workspaces[14].state = "done"; ws.workspaces[15].state = "ask"')
	eq(child.lua_get("(function() state.blink = false; return last_hl() end)()"), "CrewPillAsk")
	-- CrewPillAskBlink has a background, a marker is only an arrow.
	eq(child.lua_get("(function() state.blink = true; return last_hl() end)()"), "CrewPillMore")
end

T["window"]["a hidden ask keeps the blink timer running"] = function()
	fifteen(10)
	child.lua([[
		state.report(ws.workspaces[15].id, "Notification", { notification_type = "permission_prompt" })
		state.blink = false
		flipped = vim.wait(2000, function() return state.blink end)
	]])
	eq(child.lua_get("flipped"), true)
end

T["window"]["done wins over work in a marker"] = function()
	fifteen(10)
	child.lua('ws.workspaces[2].state = "work"; ws.workspaces[3].state = "done"')
	eq(child.lua_get("status.pills()[2].hl"), "CrewPillDone")
	child.lua("ws.workspaces[3].state = nil")
	eq(child.lua_get("status.pills()[2].hl"), "CrewPillWork")
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

T["bufferline right"]["markers sit on the bufferline fill background"] = function()
	fifteen(10)
	child.lua([[
		vim.api.nvim_set_hl(0, "BufferLineFill", { bg = 0x070707 })
		vim.api.nvim_set_hl(0, "CrewPillMore", { fg = 0x555555, bg = 0x333333 })
		ws.workspaces[15].state = "ask"
		state.blink = false
	]])
	local bgs = child.lua_get([[(function()
		local bgs = {}
		for _, it in ipairs(require("crew.bufferline").right()) do
			if it.text == " ‹ " or it.text == " › " then
				bgs[#bgs + 1] = vim.api.nvim_get_hl(0, { name = it.link, link = false }).bg or -1
			end
		end
		return bgs
	end)()]])
	eq(bgs, { 0x070707, 0x070707 })
end

T["bufferline right"]["agent pills keep their linked groups"] = function()
	open_two()
	eq(child.lua_get('require("crew.bufferline").right()[5].link'), "CrewPillCurrent")
end

T["lualine marker sits on the section background"] = function()
	fifteen(10)
	child.lua([[
		require("lualine").setup({})
		vim.api.nvim_set_hl(0, "CrewPillMore", { fg = 0x555555, bg = 0x333333 })
	]])
	local out = child.lua_get([[(function()
		local Comp = require("lualine.components.crew")
		local comp = Comp({ self = { section = "c" }, component_separators = "", section_separators = "" })
		section = comp:get_default_hl():match("#(.-)#")
		return comp:update_status()
	end)()]])
	local group = out:match("%%#([%w_]+)# › ")
	H.neq(group, nil)
	eq(child.lua_get("vim.api.nvim_get_hl(0, { name = ..., link = false }).bg", { group }), child.lua_get("vim.api.nvim_get_hl(0, { name = section, link = false }).bg"))
	eq(child.lua_get("vim.api.nvim_get_hl(0, { name = ..., link = false }).fg", { group }), 0x555555)
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

T["spinner"] = MiniTest.new_set()

local FRAMES = { "⠴", "⠦", "⠖", "⠲" }

-- Agent 1 works, agent 2 is current; returns the text of pill 1.
local function working(opts)
	setup(opts)
	child.lua([[
		ws.open(); ws.open()
		state = require("crew.state")
		state.spin_interval = 60000 -- frames advance only through spin_step here
		state.report(ws.workspaces[1].id, "UserPromptSubmit", {})
		pill = function() return status.pills()[2].text end -- [1] is the editor
	]])
end

T["spinner"]["a working agent shows the first frame and steps through them"] = function()
	working()
	eq(child.lua_get("pill()"), " 1 " .. FRAMES[1] .. " ")
	child.lua("state.spin_step()")
	eq(child.lua_get("pill()"), " 1 " .. FRAMES[2] .. " ")
	eq(child.lua_get("state.spinning()"), true)
end

T["spinner"]["stops when no agent works"] = function()
	working()
	child.lua('state.report(ws.workspaces[1].id, "Stop", {})')
	eq(child.lua_get("state.spinning()"), false)
end

T["spinner"]["a string icon stays still and starts no timer"] = function()
	working({ icons = { work = "●" } })
	eq(child.lua_get("pill()"), " 1 ● ")
	eq(child.lua_get("state.spinning()"), false)
end

return T
