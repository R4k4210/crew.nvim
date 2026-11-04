-- Keymaps. Global ones use a prefix and work in normal and terminal mode,
-- so they fire from inside a running agent. Buffer-local ones only exist
-- in agent terminals.
local config = require("crew.config")

local M = {}

--- Open an agent, asking which one when there is more than one profile.
local function pick_and_open()
	local names = vim.tbl_keys(config.options.agents)
	table.sort(names)
	if #names == 1 then
		return require("crew.workspace").open(names[1])
	end
	vim.ui.select(names, { prompt = "Open agent" }, function(name)
		if name then
			require("crew.workspace").open(name)
		end
	end)
end

---@return { [1]: string, [2]: function, desc: string }[]
local function actions()
	local ws = require("crew.workspace")
	local list = {
		{ "<Space>", ws.toggle, desc = "editor <-> last agent" },
		{ "n", pick_and_open, desc = "new agent" },
		{ "x", function() ws.close() end, desc = "close agent" },
	}
	for slot = 1, 9 do
		list[#list + 1] = {
			tostring(slot),
			function() ws.jump(slot) end,
			desc = slot == 1 and "go to editor" or ("go to workspace " .. slot),
		}
	end
	return list
end

function M.setup()
	-- Direct jumps skip the prefix. Ctrl plus a digit has no legacy terminal
	-- encoding, so these only fire where the kitty keyboard protocol is on.
	local jump = config.options.keys.jump
	if jump then
		for slot = 1, 9 do
			vim.keymap.set({ "n", "t" }, jump:format(slot), function()
				require("crew.workspace").jump(slot)
			end, { desc = "crew: jump to slot " .. slot })
		end
	end

	local prefix = config.options.keys.prefix
	if not prefix then
		return -- user opted out with prefix = false
	end

	-- Most terminals send Ctrl-Space as NUL, which Neovim reads as <C-@>.
	-- Map both spellings so the prefix works everywhere.
	local prefixes = { prefix }
	if prefix:lower() == "<c-space>" then
		prefixes[#prefixes + 1] = "<C-@>"
	end

	for _, p in ipairs(prefixes) do
		for _, action in ipairs(actions()) do
			vim.keymap.set({ "n", "t" }, p .. action[1], action[2], { desc = "crew: " .. action.desc })
		end
	end
end

--- Keys that only exist inside one agent terminal.
---@param buf integer
function M.attach(buf)
	local stopinsert = config.options.keys.stopinsert
	if stopinsert then
		vim.keymap.set("t", stopinsert, [[<C-\><C-n>]], { buffer = buf, desc = "crew: normal mode" })
	end
end

return M
