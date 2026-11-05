-- Adapters hold everything specific to one agent CLI, so the rest of crew
-- never checks which CLI it runs. Every field is optional: a missing one
-- means the CLI lacks that capability and crew skips it.
local M = {}

---@class crew.Adapter
---@field name? string
---@field prepare? fun(cmd: string[], agent: crew.Agent, ws: crew.Workspace): string[], table<string, string>? Final command and extra env
---@field resume_args? fun(id?: string): string[]? Args that resume session id, or with nil open the CLI's own picker. Nil when it cannot
---@field sessions? fun(agent: crew.Agent, cwd: string): crew.Session[] Sessions of cwd for crew's picker, newest first
---@field last_session? fun(agent: crew.Agent, cwd: string): string? Latest session of cwd, for restoring an agent saved with no session id
---@field health? fun(agent: crew.Agent, report: crew.HealthReport) Extra :checkhealth lines for a profile

---@class crew.HealthReport
---@field ok fun(msg: string)
---@field info fun(msg: string)
---@field warn fun(msg: string, advice?: string[])
---@field error fun(msg: string, advice?: string[])

--- Adapters detected from the basename of cmd[1].
M.known = { claude = true, agy = true }

local warned = {}

---@param name string
---@return crew.Adapter?
local function load(name)
	if name == "init" then
		return nil
	end
	local ok, adapter = pcall(require, "crew.adapters." .. name)
	return ok and type(adapter) == "table" and adapter or nil
end

--- The adapter of a profile: its explicit adapter, else the one named like
--- the basename of cmd[1], else plain. An unknown explicit name warns once.
---@param agent crew.Agent
---@return crew.Adapter
function M.get(agent)
	local name = agent.adapter
	if name then
		local adapter = load(name)
		if adapter then
			return adapter
		end
		if not warned[name] then
			warned[name] = true
			vim.notify(("crew: unknown adapter %q, using plain"):format(name), vim.log.levels.WARN)
		end
	else
		local base = vim.fs.basename((agent.cmd or {})[1] or "")
		local adapter = M.known[base] and load(base)
		if adapter then
			return adapter
		end
	end
	return require("crew.adapters.plain")
end

return M
