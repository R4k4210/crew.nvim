-- Keymaps. Every global key is a single key or a <leader> mapping, never a
-- custom chord: a chord like <C-,>n waits only timeoutlen for its second
-- key, and when it expires the second key runs on its own (n = search next).
local config = require("crew.config")

local M = {}

---@param modes string|string[]
---@param lhs string|false|nil
---@param rhs function
---@param desc string
local function set(modes, lhs, rhs, desc)
	if lhs then
		vim.keymap.set(modes, lhs, rhs, { desc = desc })
	end
end

function M.setup()
	local keys = config.options.keys
	local ws = function()
		return require("crew.workspace")
	end

	-- Normal and terminal mode, so it also gets you out of a running agent.
	set({ "n", "t" }, keys.toggle, function()
		ws().toggle()
	end, "crew: editor <-> last agent")

	-- Normal mode only: in terminal mode <leader> (Space) must reach the agent.
	local picker = function()
		return require("crew.picker")
	end
	set("n", keys.new, function()
		picker().new()
	end, "crew-new")
	set("n", keys.close, function()
		ws().close()
	end, "crew-exit")
	set("n", keys.pick, function()
		picker().pick()
	end, "crew-pick")
	set("n", keys.rename, function()
		picker().rename()
	end, "crew-rename")
	-- Lowercase asks which instance, uppercase sends to the last one.
	for how, suffix in pairs({ pick = "", last = "_last" }) do
		local label = how == "last" and "-last" or ""
		set("n", keys["send_file" .. suffix], function()
			require("crew.send").file(how)
		end, "crew-send-file" .. label)
		set("x", keys["send_selection" .. suffix], function()
			local first, last = vim.fn.line("v"), vim.fn.line(".")
			vim.cmd("normal! \27") -- leave visual mode before switching tabs
			require("crew.send").selection(first, last, how)
		end, "crew-send-selection" .. label)
	end

	-- Ctrl plus a digit has no legacy terminal encoding, so these only fire
	-- where the kitty keyboard protocol is on.
	if keys.jump then
		for slot = 1, 9 do
			set({ "n", "t" }, keys.jump:format(slot), function()
				ws().jump(slot)
			end, slot == 1 and "crew: go to editor" or ("crew: go to workspace " .. slot))
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
