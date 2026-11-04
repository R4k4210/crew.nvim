-- Public entry point: require("crew")
local M = {}

---@param opts? crew.Config
function M.setup(opts)
  require("crew.config").setup(opts)
  require("crew.keymaps").setup()
end

return M
