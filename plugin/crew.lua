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
	desc = "crew.nvim: list | open [agent] | jump N | toggle | close [N] | config",
	complete = function(arglead, cmdline)
		return require("crew.commands").complete(arglead, cmdline)
	end,
})

vim.api.nvim_create_autocmd("TabClosed", {
	group = vim.api.nvim_create_augroup("crew", { clear = true }),
	desc = "Forget crew workspaces whose tab was closed by hand",
	callback = function()
		require("crew.workspace").prune()
	end,
})
