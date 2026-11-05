-- Claude Code: state hooks and the usage feed through --settings, resume
-- by session id and crew's own sessions picker.
local hooks = require("crew.hooks")
local sessions = require("crew.sessions")

---@type crew.Adapter
local M = { name = "claude" }

--- Merge crew's hooks into the command and chain the user's statusLine
--- through CREW_STATUSLINE. hooks = false leaves both untouched, while
--- statusline = false keeps the usage feed and shows no status line.
function M.prepare(cmd, agent)
	if agent.hooks == false then
		return cmd, nil
	end
	local env = nil
	if agent.statusline ~= false then
		env = { CREW_STATUSLINE = hooks.original_statusline(cmd, agent.env or {}) }
	end
	return hooks.merge(cmd), env
end

function M.resume_args(id)
	return id and { "--resume", id } or { "--resume" }
end

M.sessions = sessions.list

function M.health(agent, report)
	if agent.hooks ~= false then
		local original = hooks.original_statusline(agent.cmd or {}, agent.env or {})
		report.info(("chains statusLine %s"):format(original and ("`" .. original .. "`") or "(none)"))
	end
end

return M
