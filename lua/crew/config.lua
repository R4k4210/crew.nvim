---@class crew.Agent
---@field cmd string[] Command that starts the agent CLI
---@field env? table<string, string> Extra environment variables for the agent

---@class crew.Config
---@field agents table<string, crew.Agent> Agent profiles, keyed by name
---@field default_agent string Agent opened when no name is given
---@field keys crew.Keys

---@class crew.Keys
---@field prefix string|false Prefix for global keymaps (normal and terminal mode), false to disable
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
		prefix = "<C-,>",
		jump = "<C-%d>",
		stopinsert = false,
	},
}

-- Merged config. Starts as a copy of the defaults so the plugin works
-- even when the user never calls setup().
---@type crew.Config
M.options = vim.deepcopy(M.defaults)

---@param opts? crew.Config
function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
