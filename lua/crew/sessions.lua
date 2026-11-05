-- Claude Code sessions of a directory, read from Claude's own session files
-- (<config>/projects/<encoded cwd>/<id>.jsonl). The format is undocumented,
-- so every field is optional: a missing or odd field is nil, never an error.
local M = {}

local TAIL = 64 * 1024 -- session files reach megabytes; the tail has what we need

---@class crew.Session
---@field id string Session id, the file name without .jsonl
---@field mtime integer Last activity, epoch seconds
---@field branch? string
---@field title? string
---@field prompt? string

--- Claude's config dir: CLAUDE_CONFIG_DIR of the profile env, else of the
--- environment, else ~/.claude. Shared with crew.hooks.
---@param env? table<string, string> The profile's extra environment
---@return string
function M.config_dir(env)
	env = env or {}
	return env.CLAUDE_CONFIG_DIR or vim.env.CLAUDE_CONFIG_DIR or vim.fn.expand("~/.claude")
end

--- Claude's project dir for cwd: the profile's CLAUDE_CONFIG_DIR, else the
--- environment's, else ~/.claude, then every non alphanumeric char as "-".
---@param agent crew.Agent
---@param cwd string
---@return string
function M.dir(agent, cwd)
	return M.config_dir(agent.env) .. "/projects/" .. cwd:gsub("[^%w]", "-")
end

--- Ids of the sessions open in a running Claude process, from
--- <config>/sessions/<pid>.json. A file whose process is gone is skipped,
--- since a crash can leave it behind.
---@param agent crew.Agent
---@return table<string, true>
local function live(agent)
	local dir = M.config_dir(agent.env) .. "/sessions"
	local ids = {}
	for file, kind in vim.fs.dir(dir) do
		if kind == "file" and file:match("%.json$") then
			local ok, rec = pcall(vim.json.decode, table.concat(vim.fn.readfile(dir .. "/" .. file), "\n"))
			local pid = ok and type(rec) == "table" and tonumber(rec.pid)
			if pid and type(rec.sessionId) == "string" and vim.uv.kill(pid, 0) == 0 then
				ids[rec.sessionId] = true
			end
		end
	end
	return ids
end

--- The last TAIL bytes of a file, starting at a whole line.
---@param path string
---@return string?
local function tail(path)
	local fd = vim.uv.fs_open(path, "r", 438)
	if not fd then
		return
	end
	local stat = vim.uv.fs_fstat(fd)
	local offset = stat and math.max(0, stat.size - TAIL) or 0
	local data = vim.uv.fs_read(fd, TAIL, offset)
	vim.uv.fs_close(fd)
	if data and offset > 0 then
		data = data:match("\n(.*)$")
	end
	return data
end

---@param v any
---@return string?
local function str(v)
	return type(v) == "string" and v ~= "" and v or nil
end

--- Title, prompt and branch from the last records that carry them.
---@param path string
---@param session crew.Session
local function read(path, session)
	local ai, custom
	for line in (tail(path) or ""):gmatch("[^\n]+") do
		local ok, rec = pcall(vim.json.decode, line)
		if ok and type(rec) == "table" then
			session.branch = str(rec.gitBranch) or session.branch
			if rec.type == "ai-title" then
				ai = str(rec.aiTitle) or ai
			elseif rec.type == "custom-title" then
				custom = str(rec.customTitle) or custom
			elseif rec.type == "last-prompt" then
				session.prompt = str(rec.lastPrompt) or session.prompt
			end
		end
	end
	session.title = custom or ai
end

--- Sessions of cwd for a profile, newest first. {} when there are none.
--- Sessions open elsewhere are left out: resuming one starts a second
--- process on the same conversation, and closing it ends the session for
--- the first one too (its SessionEnd hooks fire with the same id).
---@param agent crew.Agent
---@param cwd string
---@return crew.Session[]
function M.list(agent, cwd)
	local dir = M.dir(agent, cwd)
	local open = live(agent)
	local list = {}
	for file, kind in vim.fs.dir(dir) do
		local id = file:match("^(.+)%.jsonl$")
		id = id and not open[id] and id or nil
		local path = dir .. "/" .. file
		local stat = id and kind == "file" and vim.uv.fs_stat(path)
		if stat then
			local session = { id = id, mtime = stat.mtime.sec }
			read(path, session)
			list[#list + 1] = session
		end
	end
	table.sort(list, function(a, b)
		return a.mtime > b.mtime
	end)
	return list
end

return M
