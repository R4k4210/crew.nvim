-- Global keymaps and the silent jump to a missing slot.
local H = dofile("tests/helpers.lua")
local eq = H.eq
local child, T = H.new()

local function setup(opts)
	child.lua('vim.g.mapleader = " "')
	child.lua('require("crew").setup(...)', { opts or { agents = { sh = { cmd = { "sh" } } }, default_agent = "sh" } })
end

local function desc(mode, lhs)
	return child.lua("local lhs, mode = ...; return vim.fn.maparg(lhs, mode, false, true).desc", { lhs, mode })
end

local function mapped(mode, lhs)
	return child.lua("local lhs, mode = ...; return not vim.tbl_isempty(vim.fn.maparg(lhs, mode, false, true))", { lhs, mode })
end

T["<C-,> toggles in normal mode"] = function()
	setup()
	eq(desc("n", "<C-,>"), "crew: editor <-> last agent")
end

T["<C-,> toggles in terminal mode"] = function()
	setup()
	H.neq(desc("t", "<C-,>"), vim.NIL)
	eq(mapped("t", "<C-,>"), true)
end

T["<leader>an is crew-new"] = function()
	setup()
	eq(desc("n", "<leader>an"), "crew-new")
end

T["<leader>ax is crew-exit"] = function()
	setup()
	eq(desc("n", "<leader>ax"), "crew-exit")
end

T["<leader> maps stay out of terminal mode"] = function()
	setup()
	eq(mapped("t", "<leader>an"), false)
end

T["no chord <C-,>n is left"] = function()
	setup()
	eq(mapped("n", "<C-,>n"), false)
end

T["<C-3> jump exists in normal and terminal mode"] = function()
	setup()
	eq(mapped("n", "<C-3>"), true)
	eq(mapped("t", "<C-3>"), true)
	eq(type(desc("n", "<C-3>")), "string")
	eq(type(desc("t", "<C-3>")), "string")
end

T["<C-1> jumps to the first agent"] = function()
	setup()
	eq(desc("n", "<C-1>"), "crew: go to agent 1")
	eq(desc("t", "<C-9>"), "crew: go to agent 9")
end

T["keys.editor"] = MiniTest.new_set()

T["keys.editor"]["is disabled by default"] = function()
	setup()
	eq(child.lua_get('require("crew.config").options.keys.editor'), false)
	eq(child.lua_get([[#vim.tbl_filter(function(m) return m.desc == "crew: go to editor" end, vim.api.nvim_get_keymap("n"))]]), 0)
end

T["keys.editor"]["is mapped in normal and terminal mode when set"] = function()
	setup({ agents = { sh = { cmd = { "sh" } } }, keys = { editor = "<C-0>" } })
	eq(desc("n", "<C-0>"), "crew: go to editor")
	eq(desc("t", "<C-0>"), "crew: go to editor")
end

T["keys.editor"]["goes to the editor"] = function()
	setup({ agents = { sh = { cmd = { "sh" } } }, keys = { editor = "<C-0>" } })
	child.lua([[
		ws = require("crew.workspace")
		home = vim.api.nvim_get_current_tabpage()
		ws.open("sh")
		vim.fn.maparg("<C-0>", "n", false, true).callback()
	]])
	eq(child.lua_get("vim.api.nvim_get_current_tabpage() == home"), true)
end

T["jump to a missing slot"] = MiniTest.new_set()

T["jump to a missing slot"]["is silent"] = function()
	setup()
	child.lua([[
		notified = false
		vim.notify = function() notified = true end
		require("crew.workspace").jump(5)
	]])
	eq(child.lua_get("notified"), false)
end

T["jump to a missing slot"]["stays put"] = function()
	setup()
	child.lua([[
		tab = vim.api.nvim_get_current_tabpage()
		require("crew.workspace").jump(5)
	]])
	eq(child.lua_get("vim.api.nvim_get_current_tabpage() == tab"), true)
end

T["keys can be disabled with false"] = MiniTest.new_set()

local disabled = { keys = { toggle = false, new = false, close = false, jump = false } }

T["keys can be disabled with false"]["setup again does not crash"] = function()
	setup()
	eq(child.lua_get('(pcall(require("crew").setup, ...))', { disabled }), true)
end

T["keys can be disabled with false"]["a fresh setup does not map them"] = function()
	setup(disabled)
	eq(mapped("n", "<C-,>"), false)
	eq(mapped("n", "<leader>an"), false)
	eq(mapped("n", "<leader>ax"), false)
	eq(mapped("n", "<C-3>"), false)
end

return T
