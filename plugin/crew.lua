-- Runs once when Neovim loads the plugin. Keep it tiny: register
-- commands and autocmds here and defer the real work to lua/crew/.
if vim.g.loaded_crew then
	return
end
vim.g.loaded_crew = true

vim.api.nvim_create_user_command("Crew", function(opts)
	require("crew.commands").run(opts)
end, {
	nargs = "*",
	desc = "crew.nvim: list | open [agent] | jump N | editor | toggle | close [N] | config",
	complete = function(arglead, cmdline)
		return require("crew.commands").complete(arglead, cmdline)
	end,
})

local group = vim.api.nvim_create_augroup("crew", { clear = true })

-- :colorscheme runs :hi clear, which drops our links, so set them again.
require("crew.highlights").setup()
vim.api.nvim_create_autocmd("ColorScheme", {
	group = group,
	desc = "Restore crew pill highlight links",
	callback = function()
		require("crew.highlights").setup()
	end,
})

vim.api.nvim_create_autocmd("TabClosed", {
	group = group,
	desc = "Forget crew workspaces whose tab was closed by hand",
	callback = function()
		require("crew.workspace").prune()
	end,
})

vim.api.nvim_create_autocmd("TabEnter", {
	group = group,
	desc = "Mark a done agent as seen and stop the blink for the one you look at",
	callback = function()
		require("crew.state").seen()
	end,
})
