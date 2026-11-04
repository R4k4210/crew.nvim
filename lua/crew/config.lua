---@class crew.Agent
---@field cmd string[] Command that starts the agent CLI
---@field env? table<string, string> Extra environment variables for the agent

---@class crew.Config
---@field agents table<string, crew.Agent> Agent profiles, keyed by name
---@field default_agent string Agent opened when no name is given
---@field keys crew.Keys
---@field icons crew.Icons

---@class crew.Icons
---@field work string Agent is running a task
---@field ask string Agent waits on the user (permission prompt, question)
---@field done string Agent finished and the user has not looked yet

---@class crew.Keys
---@field toggle? string|false Editor <-> last agent, in normal and terminal mode. A single key, never a chord, so it does not depend on timeoutlen
---@field new? string|false Open a new agent (normal mode), asks which one when there are several profiles
---@field close? string|false Close the current agent (normal mode)
---@field pick? string|false Pick an open instance from a list with names and usage (normal mode)
---@field rename? string|false Name the current instance (normal mode)
---@field send_file? string|false Send @path of the current file to the agent (normal mode)
---@field send_selection? string|false Send the selected lines with their location to the agent (visual mode)
---@field send_file_last? string|false Like send_file, straight to the last agent with no picker
---@field send_selection_last? string|false Like send_selection, straight to the last agent with no picker
---@field jump? string|false Direct jump to slot N, a format string with %d (e.g. "<C-%d>"), false to disable. Needs a terminal with the kitty keyboard protocol
---@field stopinsert? string|false Key that leaves terminal mode inside agent buffers, e.g. "jk"

local M = {}

---@type crew.Config
M.defaults = {
	agents = {
		claude = { cmd = { "claude" } },
	},
	default_agent = "claude",
	keys = {
		-- Not <C-Space>: macOS binds it to "select previous input source".
		toggle = "<C-,>",
		new = "<leader>an",
		close = "<leader>ax",
		pick = "<leader>ap",
		rename = "<leader>ai",
		send_file = "<leader>af",
		send_selection = "<leader>av",
		send_file_last = "<leader>aF",
		send_selection_last = "<leader>aV",
		jump = "<C-%d>",
		stopinsert = false,
	},
	icons = {
		work = "●",
		ask = "?",
		done = "✓",
	},
}

-- Merged config. Starts as a copy of the defaults so the plugin works
-- even when the user never calls setup().
---@type crew.Config
M.options = vim.deepcopy(M.defaults)

---@param opts? crew.Config
function M.setup(opts)
	opts = opts or {}
	local options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
	-- Agents are a set the user owns: their list replaces the defaults
	-- instead of merging, so defining only codex does not leave claude around.
	if opts.agents then
		options.agents = vim.deepcopy(opts.agents)
		if not opts.default_agent then
			local names = vim.tbl_keys(options.agents)
			table.sort(names)
			options.default_agent = names[1]
		end
	end
	M.options = options
end

return M
