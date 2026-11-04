-- :checkhealth crew reports what crew needs and what it can plug into.
local H = dofile("tests/helpers.lua")
local child, T = H.new()

--- Run :checkhealth crew in the child and return the report text.
---@param opts? table crew.setup options
---@return string
local function health(opts)
	child.lua('require("crew").setup(...)', { opts or {} })
	child.cmd("checkhealth crew")
	return table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

T["reports the Neovim version as OK"] = function()
	H.match(health(), "OK.-Neovim")
end

T["warns about an agent command that is not installed"] = function()
	local report = health({ agents = { ghost = { cmd = { "crew-no-such-cli" } } } })
	H.match(report, "WARNING.-ghost.-crew%-no%-such%-cli")
end

T["accepts an agent command that exists"] = function()
	H.match(health({ agents = { shell = { cmd = { "sh" } } } }), "OK.-shell")
end

T["finds the bridge scripts"] = function()
	local report = health()
	H.match(report, "OK.-hook.lua")
	H.match(report, "OK.-statusline.lua")
end

T["lists optional integrations without failing"] = function()
	local report = health()
	H.match(report, "snacks")
	H.match(report, "bufferline")
	H.match(report, "lualine")
	H.no_match(report, "ERROR")
end

T["explains which keys need the kitty keyboard protocol"] = function()
	H.match(health(), "kitty keyboard protocol")
end

return T
