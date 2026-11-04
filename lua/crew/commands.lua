-- :Crew <subcommand> [args]
local M = {}

---@type table<string, fun(args: string[])>
local subcommands = {
	list = function()
		local ws = require("crew.workspace")
		local lines = { "1 editor" }
		for slot = 2, 9 do
			local w = ws.workspaces[slot]
			if w then
				lines[#lines + 1] = ("%d %s"):format(slot, w.agent)
			end
		end
		print(table.concat(lines, "\n"))
	end,
	config = function()
		print(vim.inspect(require("crew.config").options))
	end,
	open = function(args)
		require("crew.workspace").open(args[1])
	end,
	jump = function(args)
		require("crew.workspace").jump(tonumber(args[1]))
	end,
	toggle = function()
		require("crew.workspace").toggle()
	end,
	close = function(args)
		require("crew.workspace").close(tonumber(args[1]))
	end,
}

---@param opts { fargs: string[] }
function M.run(opts)
	local args = vim.deepcopy(opts.fargs)
	local name = table.remove(args, 1) or "list"
	local fn = subcommands[name]
	if not fn then
		vim.notify(("crew: unknown subcommand %q"):format(name), vim.log.levels.ERROR)
		return
	end
	fn(args)
end

---@param list string[]
---@param prefix string
local function starting_with(list, prefix)
	return vim.tbl_filter(function(item)
		return vim.startswith(item, prefix)
	end, list)
end

--- Tab completion for :Crew
---@param arglead string Word being typed
---@param cmdline string Whole command line
function M.complete(arglead, cmdline)
	local words = vim.split(cmdline, "%s+", { trimempty = true })
	local typing_new_word = cmdline:sub(-1) == " "
	local position = #words + (typing_new_word and 1 or 0)

	if position <= 2 then
		local names = vim.tbl_keys(subcommands)
		table.sort(names)
		return starting_with(names, arglead)
	end
	if words[2] == "open" then
		local agents = vim.tbl_keys(require("crew.config").options.agents)
		table.sort(agents)
		return starting_with(agents, arglead)
	end
	return {}
end

return M
