-- Claude Code hooks: crew injects them through the --settings flag of each
-- claude agent, so the user's global settings.json is never touched. Each hook
-- runs scripts/hook.lua, which reads the hook JSON from stdin and reports it
-- back to this Neovim through $NVIM (see crew.state).
local M = {}

M.events = { "UserPromptSubmit", "PostToolUse", "Notification", "Stop" }

-- lua/crew/hooks.lua -> plugin root
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
M.script = root .. "/scripts/hook.lua"

--- Shell command for one event. Guarded by $NVIM (only set inside a Neovim
--- terminal) and always exits 0, so a hook can never block or break Claude.
---@param event string
---@return string
function M.hook_command(event)
	return ('[ -n "$NVIM" ] && %s --clean --headless -l %s %s || true'):format(
		vim.fn.shellescape(vim.v.progpath),
		vim.fn.shellescape(M.script),
		event
	)
end

---@return table settings with crew's hooks only
local function crew_settings()
	local hooks = {}
	for _, event in ipairs(M.events) do
		hooks[event] = { { hooks = { { type = "command", command = M.hook_command(event) } } } }
	end
	return { hooks = hooks }
end

--- Settings given as inline JSON or as a file path.
---@param value string
---@return table
local function read_settings(value)
	local text = value
	if not vim.startswith(vim.trim(value), "{") then
		local ok, lines = pcall(vim.fn.readfile, vim.fn.expand(value))
		text = ok and table.concat(lines, "\n") or "{}"
	end
	local ok, decoded = pcall(vim.json.decode, text)
	return ok and type(decoded) == "table" and decoded or {}
end

--- Command for an agent with crew's hooks merged into its --settings.
--- Only claude commands are touched; enabled = false opts out.
---@param cmd string[]
---@param enabled? boolean
---@return string[]
function M.command(cmd, enabled)
	cmd = vim.deepcopy(cmd)
	if enabled == false or vim.fs.basename(cmd[1] or "") ~= "claude" then
		return cmd
	end
	local at = vim.fn.index(cmd, "--settings") + 1 -- 0 when missing
	local settings = at > 0 and cmd[at + 1] and read_settings(cmd[at + 1]) or {}
	settings.hooks = settings.hooks or {}
	for event, list in pairs(crew_settings().hooks) do
		settings.hooks[event] = vim.list_extend(settings.hooks[event] or {}, list)
	end
	local json = vim.json.encode(settings)
	if at > 0 then
		cmd[at + 1] = json
	else
		vim.list_extend(cmd, { "--settings", json })
	end
	return cmd
end

return M
