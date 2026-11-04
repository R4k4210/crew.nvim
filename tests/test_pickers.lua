-- Pickers through the vim.ui.select fallback, rename and aligned rows.
local H = dofile("tests/helpers.lua")
local eq, match = H.eq, H.match
local child, T = H.new()

local function setup()
	child.lua([[
		vim.g.mapleader = " "
		require("crew").setup({ agents = { sh = { cmd = { "sh" } }, zsh = { cmd = { "sh" } } }, default_agent = "sh" })
		ws = require("crew.workspace")
		picker = require("crew.picker")
	]])
end

-- zsh in slot 2 through picker.new, sh in slot 3 (current).
local function open_two()
	setup()
	child.lua([[
		vim.ui.select = function(items, opts, on_choice)
			shown = vim.tbl_map(opts.format_item, items)
			on_choice(items[2])
		end
		picker.new()
		ws.open("sh")
	]])
end

local function desc(lhs)
	return child.lua_get('vim.fn.maparg(..., "n", false, true).desc', { lhs })
end

T["keys"] = function()
	setup()
	eq(desc("<leader>ap"), "crew-pick")
	eq(desc("<leader>ai"), "crew-rename")
	eq(desc("<leader>an"), "crew-new")
end

T["new"] = MiniTest.new_set()

T["new"]["lists only the configured profiles, sorted"] = function()
	open_two()
	eq(child.lua_get("shown"), { "sh", "zsh" })
end

T["new"]["opens the chosen profile"] = function()
	open_two()
	eq(child.lua_get("ws.workspaces[2].agent"), "zsh")
end

T["rename"] = MiniTest.new_set()

T["rename"]["prompt names the slot and sets the name"] = function()
	open_two()
	child.lua([[
		vim.ui.input = function(opts, on_confirm) prompt = opts.prompt; on_confirm("cuca") end
		picker.rename()
	]])
	match(child.lua_get("prompt"), "3", true)
	eq(child.lua_get("ws.workspaces[3].name"), "cuca")
	eq(child.lua_get('require("crew.status").list()[3].name'), "cuca")
end

T["rename"]["empty name clears it"] = function()
	open_two()
	child.lua([[
		ws.workspaces[3].name = "cuca"
		vim.ui.input = function(_, on_confirm) on_confirm("") end
		picker.rename()
	]])
	eq(child.lua_get("ws.workspaces[3].name"), vim.NIL)
end

T["rename"]["cancel keeps the name"] = function()
	open_two()
	child.lua([[
		ws.workspaces[3].name = "keep"
		vim.ui.input = function(_, on_confirm) on_confirm(nil) end
		picker.rename()
	]])
	eq(child.lua_get("ws.workspaces[3].name"), "keep")
end

T["rename"][":Crew rename sets a name with spaces"] = function()
	open_two()
	child.lua('vim.cmd("Crew rename ops analysis")')
	eq(child.lua_get("ws.workspaces[3].name"), "ops analysis")
end

T["rename"]["does nothing in the editor"] = function()
	open_two()
	child.lua([[
		ws.jump(1)
		called = false
		vim.ui.input = function() called = true end
		picker.rename()
	]])
	eq(child.lua_get("called"), false)
end

T["pick"] = MiniTest.new_set()

-- Slot 2 asks and has usage, slot 3 is named and has none; pick chooses row 2.
local function pick_rows()
	open_two()
	child.lua([[
		vim.cmd("Crew rename ops analysis")
		ws.jump(1)
		ws.workspaces[2].state = "ask"
		ws.workspaces[2].usage = {
			ctx = 71,
			five_hour = { pct = 87, resets_at = os.time() + 47 * 60 + 30 },
			seven_day = { pct = 23, resets_at = os.time({ year = 2026, month = 11, day = 26, hour = 18, min = 0 }) },
		}
		vim.ui.select = function(items, opts, on_choice)
			shown = vim.tbl_map(opts.format_item, items)
			on_choice(items[2])
		end
		picker.pick()
	]])
	return child.lua_get("shown")
end

T["pick"]["lists only open instances"] = function()
	eq(#pick_rows(), 2)
end

T["pick"]["row has slot, profile and usage"] = function()
	local row = pick_rows()[1]
	match(row, "^2  zsh")
	match(row, "ctx  71%%")
	match(row, "5h  87%% ↻ 47m")
	match(row, "wk  23%% ↻ nov 26 18:00")
end

T["pick"]["row ends with the ask icon"] = function()
	match(pick_rows()[1], "%?$")
end

T["pick"]["row has its name and dashes for missing usage"] = function()
	local row = pick_rows()[2]
	match(row, "ops analysis", true)
	match(row, "ctx    –", true)
end

T["pick"]["rows align"] = function()
	local rows = pick_rows()
	local function col(s, pat)
		return vim.fn.strdisplaywidth(s:sub(1, s:find(pat, 1, true) - 1))
	end
	eq(col(rows[1], "│"), col(rows[2], "│"))
	eq(col(rows[1], "5h"), col(rows[2], "5h"))
	eq(col(rows[1], " wk"), col(rows[2], " wk"))
end

T["pick"]["jumps to the chosen instance"] = function()
	pick_rows()
	eq(child.lua_get("ws.current() == ws.workspaces[3]"), true)
end

T["pick"]["does nothing with no instances"] = function()
	open_two()
	child.lua([[
		ws.close(2); ws.close(2)
		called = false
		vim.ui.select = function() called = true end
		picker.pick()
	]])
	eq(child.lua_get("called"), false)
end

return T
