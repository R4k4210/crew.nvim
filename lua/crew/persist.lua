-- Open agents saved per directory, so they come back after a restart.
-- The state is written on every change, never only on exit, because a
-- killed terminal may skip the exit autocmds.
local M = {}

---@class crew.SavedAgent
---@field agent string Profile name
---@field name? string
---@field cwd? string
---@field session_id? string

--- Where state files live. Tests point it to a temp dir.
M.dir = vim.fn.stdpath("state") .. "/crew"

--- True while Neovim quits. Closing agents on quit (and their jobs exiting)
--- must not empty the file, so saving pauses. Overridable in tests.
---@return boolean
function M.exiting()
	return vim.v.exiting ~= vim.NIL
end

local paused = 0
local warned = false

--- State file for Neovim's cwd, every non alphanumeric char as "-".
---@return string
function M.path()
	return ("%s/%s.json"):format(M.dir, (vim.fn.getcwd():gsub("[^%w]", "-")))
end

--- Run fn with saving off, for restore and for closing agents on quit.
---@param fn fun()
function M.without_saving(fn)
	paused = paused + 1
	local ok, err = pcall(fn)
	paused = paused - 1
	if not ok then
		error(err, 0)
	end
end

---@param path string
---@param text string
local function write(path, text)
	vim.fn.mkdir(M.dir, "p")
	local tmp = path .. ".tmp"
	local f = assert(io.open(tmp, "w"))
	f:write(text)
	f:close()
	assert(vim.uv.fs_rename(tmp, path))
end

--- Write the open agents in slot order, or delete the file when none is open.
--- Never errors: a failure warns once and the plugin carries on.
function M.save()
	if paused > 0 or M.exiting() then
		return
	end
	local ok, err = pcall(function()
		local agents = {}
		for _, ws in ipairs(require("crew.workspace").ordered()) do
			agents[#agents + 1] = { agent = ws.agent, name = ws.name, cwd = ws.cwd, session_id = ws.session_id }
		end
		if #agents == 0 then
			return M.clear()
		end
		write(M.path(), vim.json.encode({ version = 1, agents = agents }))
	end)
	if not ok and not warned then
		warned = true
		vim.notify(("crew: cannot save open agents: %s"):format(err), vim.log.levels.WARN)
	end
end

--- Forget the saved agents of the current directory.
function M.clear()
	os.remove(M.path())
end

--- Saved agents of the current directory, nil when missing or malformed.
---@return crew.SavedAgent[]?
function M.load()
	local f = io.open(M.path(), "r")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	local ok, data = pcall(vim.json.decode, text)
	if not ok or type(data) ~= "table" or type(data.agents) ~= "table" then
		return nil
	end
	local agents = {}
	for _, a in ipairs(data.agents) do
		if type(a) ~= "table" or type(a.agent) ~= "string" then
			return nil
		end
		agents[#agents + 1] = a
	end
	return agents
end

--- Reopen the saved agents in order, each one resuming its own
--- conversation when its adapter can. Does nothing while agents are open, to avoid duplicates.
---@return integer count Agents reopened
function M.restore()
	local workspace = require("crew.workspace")
	local profiles = require("crew.config").options.agents
	if next(workspace.workspaces) then
		return 0
	end
	local saved = M.load() or {}
	local count, unknown = 0, {}
	M.without_saving(function()
		for _, a in ipairs(saved) do
			local profile = profiles[a.agent]
			if not profile then
				unknown[#unknown + 1] = a.agent
			else
				local adapter = require("crew.adapters").get(profile)
				local resume = type(a.session_id) == "string" and a.session_id ~= ""
				local args = resume and adapter.resume_args and adapter.resume_args(a.session_id) or nil
				local ws = workspace.open(a.agent, args)
				if ws then
					count = count + 1
					ws.session_id = resume and a.session_id or nil
					if type(a.name) == "string" then
						workspace.rename(a.name, ws.slot)
					end
				end
			end
		end
	end)
	if #unknown > 0 then
		vim.notify(("crew: skipped unknown agents: %s"):format(table.concat(unknown, ", ")), vim.log.levels.WARN)
	end
	if count > 0 then
		workspace.editor()
		M.save()
	end
	return count
end

return M
