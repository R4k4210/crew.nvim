-- Minimal init for the test runner and its child Neovim instances.
-- Only crew, mini.nvim (mini.test) and lualine.nvim are on the runtimepath.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

-- Opening an agent saves crew's restore file under stdpath("state"). Keep
-- every test run away from the user's real state directory.
vim.env.XDG_STATE_HOME = vim.fn.tempname()

vim.opt.rtp:prepend(root)

local function dep(name, url)
	local path = root .. "/deps/" .. name
	if vim.fn.isdirectory(path) == 0 then
		vim.fn.system({ "git", "clone", "--depth", "1", url, path })
	end
	vim.opt.rtp:append(path)
end

dep("mini.nvim", "https://github.com/echasnovski/mini.nvim")
dep("lualine.nvim", "https://github.com/nvim-lualine/lualine.nvim")

vim.cmd.source(root .. "/plugin/crew.lua")

require("mini.test").setup()
