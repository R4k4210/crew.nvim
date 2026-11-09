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

---@param v any
---@return string?
local function str(v)
	return type(v) == "string" and v ~= "" and v or nil
end

--- An env var of the profile, else of Neovim.
---@param agent crew.Agent
---@param key string
---@return string?
local function getenv(agent, key)
	return str((agent.env or {})[key]) or str(vim.env[key])
end

--- True when the profile runs on the user's own Pi home: pi itself, or
--- gentle-shell with --link. Plain gentle-shell uses its isolated home.
---@param agent crew.Agent
---@return boolean
local function linked(agent)
	local cmd = agent.cmd or {}
	return vim.fs.basename(cmd[1] or "") == "pi" or vim.tbl_contains(cmd, "--link")
end

--- Where Pi keeps the sessions of cwd for a profile. A custom session dir
--- (PI_CODING_AGENT_SESSION_DIR) is flat, holding every cwd. Otherwise it is
--- <agent dir>/sessions/--<cwd with / \\ : as ->--, where the agent dir is
--- PI_CODING_AGENT_DIR or ~/.pi/agent when linked, else GENTLE_SHELL_HOME or
--- ~/.gentle-shell/agent.
---@param agent crew.Agent
---@param cwd string
---@return string
function M.sessions_dir(agent, cwd)
	local custom = getenv(agent, "PI_CODING_AGENT_SESSION_DIR")
	if custom then
		return vim.fn.expand(custom)
	end
	local home
	if linked(agent) then
		home = getenv(agent, "PI_CODING_AGENT_DIR") or "~/.pi/agent"
	else
		home = getenv(agent, "GENTLE_SHELL_HOME") or "~/.gentle-shell/agent"
	end
	local safe = cwd:gsub("^[/\\]", ""):gsub("[/\\:]", "-")
	return vim.fn.expand(home) .. "/sessions/--" .. safe .. "--"
end

local CHUNK = 64 * 1024 -- session files reach megabytes; head and tail are enough

--- The first and the last CHUNK bytes of a file, the tail from a whole line.
---@param path string
---@return string?, string?
local function ends(path)
	local fd = vim.uv.fs_open(path, "r", 438)
	if not fd then
		return
	end
	local stat = vim.uv.fs_fstat(fd)
	local size = stat and stat.size or 0
	local head = vim.uv.fs_read(fd, CHUNK, 0)
	local offset = math.max(0, size - CHUNK)
	local tail = offset > 0 and vim.uv.fs_read(fd, CHUNK, offset) or head
	vim.uv.fs_close(fd)
	if tail and offset > 0 then
		tail = tail:match("\n(.*)$")
	end
	return head, tail
end

---@param line string?
---@return table?
local function decode(line)
	local ok, rec = pcall(vim.json.decode, line or "")
	return ok and type(rec) == "table" and rec or nil
end

--- Text of a user message, whose content is a string or a list of blocks.
---@param content any
---@return string?
local function text(content)
	if type(content) == "string" then
		return str(content)
	end
	if type(content) == "table" then
		for _, block in ipairs(content) do
			if type(block) == "table" and block.type == "text" and str(block.text) then
				return block.text
			end
		end
	end
end

--- Sessions of cwd for a profile, newest first. {} when there are none.
--- The format is Pi's own, so a missing or odd field is nil, never an error.
function M.sessions(agent, cwd)
	cwd = cwd:gsub("/$", "")
	local dir = M.sessions_dir(agent, cwd)
	local list = {}
	local ok = pcall(function()
		for file, kind in vim.fs.dir(dir) do
			local name = kind == "file" and file:match("^(.+)%.jsonl$")
			local path = dir .. "/" .. file
			local stat = name and vim.uv.fs_stat(path)
			if stat then
				local head, tail = ends(path)
				local first = decode((head or ""):match("^[^\n]*"))
				local hdr = first and first.type == "session" and first or {}
				if not str(hdr.cwd) or hdr.cwd:gsub("/$", "") == cwd then
					local s = { id = str(hdr.id) or name:match("^[^_]*_(.+)$") or name, mtime = stat.mtime.sec }
					for line in (tail or ""):gmatch("[^\n]+") do
						local rec = decode(line)
						if rec and rec.type == "session_info" then
							s.title = str(rec.name) or s.title
						elseif rec and rec.type == "message" and type(rec.message) == "table" and rec.message.role == "user" then
							s.prompt = text(rec.message.content) or s.prompt
						end
					end
					list[#list + 1] = s
				end
			end
		end
	end)
	if not ok then
		return {}
	end
	table.sort(list, function(a, b)
		return a.mtime > b.mtime
	end)
	return list
end

--- The latest session of cwd, for an agent saved before its id was known.
function M.last_session(agent, cwd)
	local s = M.sessions(agent, cwd)[1]
	return s and s.id or nil
end

return M
