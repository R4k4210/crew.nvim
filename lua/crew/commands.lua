-- :Crew <subcommand> [args]
local M = {}

---@type table<string, fun(args: string[])>
local subcommands = {
	list = function()
		local lines = { "editor" }
		for _, w in ipairs(require("crew.workspace").ordered()) do
			lines[#lines + 1] = ("%d %s"):format(w.slot, w.agent)
		end
		print(table.concat(lines, "\n"))
	end,
	config = function()
		print(vim.inspect(require("crew.config").options))
	end,
	open = function(args)
		require("crew.workspace").open(args[1])
	end,
	resume = function(args)
		require("crew.workspace").resume(args[1])
	end,
	jump = function(args)
		require("crew.workspace").jump(tonumber(args[1]))
	end,
	editor = function()
		require("crew.workspace").editor()
	end,
	toggle = function()
		require("crew.workspace").toggle()
	end,
	restore = function()
		require("crew.persist").restore()
	end,
	new = function()
		require("crew.picker").new()
	end,
	pick = function()
		require("crew.picker").pick()
	end,
	rename = function(args)
		if #args == 0 then
			return require("crew.picker").rename()
		end
		require("crew.workspace").rename(table.concat(args, " "))
	end,
	close = function(args)
		if args[1] == "all" then
			return require("crew.workspace").close_all()
		end
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
	if words[2] == "open" or words[2] == "resume" then
		local agents = vim.tbl_keys(require("crew.config").options.agents)
		table.sort(agents)
		return starting_with(agents, arglead)
	end
	if words[2] == "close" and position == 3 then
		return starting_with({ "all" }, arglead)
	end
	return {}
end

return M
