-- Gentle Shell, a launcher for the Pi coding agent that forwards every extra
-- argument to pi (and pi itself). crew starts each fresh agent with its own
-- --session-id, so the tab owns its session from the first moment, and loads
-- scripts/pi_status.js with -e, which reports Pi's events through
-- scripts/hook.lua like Claude's hooks do. Nothing global is touched.
local hooks = require("crew.hooks")

---@type crew.Adapter
local M = { name = "gentle_shell" }

-- lua/crew/adapters/gentle_shell.lua -> plugin root
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h")

--- Pi extension that forwards state to crew.
M.extension = root .. "/scripts/pi_status.js"

-- Flags that pick a session already, which --session-id cannot join.
local SESSION_FLAGS = {
	["--session"] = true,
	["--session-id"] = true,
	["-r"] = true,
	["--resume"] = true,
	["-c"] = true,
	["--continue"] = true,
	["--no-session"] = true,
}

--- A random UUID v4, a valid Pi session id.
---@return string
local function uuid()
	local ok, bytes = pcall(vim.uv.random, 16)
	if not ok or type(bytes) ~= "string" or #bytes ~= 16 then
		bytes = ""
		for _ = 1, 16 do
			bytes = bytes .. string.char(math.random(0, 255))
		end
	end
	local b = { bytes:byte(1, 16) }
	b[7] = bit.bor(bit.band(b[7], 0x0f), 0x40)
	b[9] = bit.bor(bit.band(b[9], 0x3f), 0x80)
	local hex = ""
	for i, byte in ipairs(b) do
		hex = hex .. ("%02x"):format(byte) .. ((i == 4 or i == 6 or i == 8 or i == 10) and "-" or "")
	end
	return hex
end

--- Value following flag in cmd, nil when the flag is missing.
---@param cmd string[]
---@param flag string
---@return string?
local function value(cmd, flag)
	for i, arg in ipairs(cmd) do
		if arg == flag then
			return cmd[i + 1]
		end
	end
end

--- Add a session id unless cmd already picks a session, then the status
--- extension. The env tells the extension how to reach Neovim.
function M.prepare(cmd, _, ws)
	cmd = vim.deepcopy(cmd)
	local picked = false
	for _, arg in ipairs(cmd) do
		picked = picked or SESSION_FLAGS[arg] or false
	end
	local id = value(cmd, "--session-id") or value(cmd, "--session")
	if not picked then
		id = uuid()
		vim.list_extend(cmd, { "--session-id", id })
	end
	if ws and id then
		ws.session_id = id
	end
	vim.list_extend(cmd, { "-e", M.extension })
	return cmd, { CREW_HOOK_NVIM = vim.v.progpath, CREW_HOOK_SCRIPT = hooks.script }
end

function M.resume_args(id)
	return id and { "--session", id } or { "-r" }
end

return M
