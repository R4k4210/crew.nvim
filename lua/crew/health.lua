-- :checkhealth crew
local M = {}

local health = vim.health

--- Report an optional plugin crew can plug into.
---@param module string
---@param what string
local function optional(module, what)
	if pcall(require, module) then
		health.ok(("%s found: %s"):format(module, what))
	else
		health.info(("%s not found: %s is off, nothing else changes"):format(module, what))
	end
end

function M.check()
	local config = require("crew.config").options

	health.start("crew: Neovim")
	if vim.fn.has("nvim-0.11") == 1 then
		health.ok("Neovim " .. tostring(vim.version()))
	else
		health.error("Neovim 0.11 or newer is required", { "crew starts agents with jobstart(..., { term = true })" })
	end

	health.start("crew: agents")
	local names = vim.tbl_keys(config.agents)
	table.sort(names)
	if #names == 0 then
		health.warn("no agents configured", { "add at least one entry to opts.agents" })
	end
	for _, name in ipairs(names) do
		local cmd = config.agents[name].cmd or {}
		local exe = cmd[1]
		if exe and vim.fn.executable(exe) == 1 then
			health.ok(("%s: %s"):format(name, vim.fn.exepath(exe)))
		else
			health.warn(("%s: %s is not installed or not in PATH"):format(name, tostring(exe)))
		end
	end
	if not config.agents[config.default_agent] then
		health.warn(("default_agent %q is not in opts.agents"):format(tostring(config.default_agent)))
	end

	health.start("crew: Claude Code bridge")
	local hooks = require("crew.hooks")
	for _, script in ipairs({ hooks.script, hooks.statusline_script }) do
		if vim.fn.filereadable(script) == 1 then
			health.ok(vim.fn.fnamemodify(script, ":t") .. " found")
		else
			health.error(script .. " is missing", { "reinstall crew.nvim" })
		end
	end
	-- Each adapter reports on its own profiles, prefixed with the profile name.
	local adapters = require("crew.adapters")
	for _, name in ipairs(names) do
		local agent = config.agents[name]
		local adapter = adapters.get(agent)
		if adapter.health then
			local function prefixed(fn)
				return function(msg, advice)
					fn(("%s: %s"):format(name, msg), advice)
				end
			end
			adapter.health(agent, {
				ok = prefixed(health.ok),
				info = prefixed(health.info),
				warn = prefixed(health.warn),
				error = prefixed(health.error),
			})
		end
	end

	health.start("crew: integrations")
	optional("snacks", "pickers without preview (vim.ui.select is used otherwise)")
	optional("bufferline", "pills and agent header in the tabline, if wired in its options")
	optional("lualine", "pills through the `crew` component, if added to a section")

	health.start("crew: keys")
	health.info(
		"<C-,> and <C-1> to <C-9> need a terminal with the kitty keyboard protocol (Ghostty, kitty, WezTerm); legacy terminals cannot tell them apart"
	)
	local term = vim.env.TERM_PROGRAM or vim.env.TERM or "unknown"
	health.info("terminal: " .. term)
end

return M
