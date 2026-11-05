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

M.statusline_script = root .. "/scripts/statusline.lua"
M.agy_statusline_script = root .. "/scripts/agy_statusline.lua"

--- The statusLine runs our script, which forwards usage to Neovim and then
--- prints whatever the user's own statusLine prints ($CREW_STATUSLINE).
---@return string
function M.statusline_command()
	return ('[ -n "$NVIM" ] && %s --clean --headless -l %s || true'):format(
		vim.fn.shellescape(vim.v.progpath),
		vim.fn.shellescape(M.statusline_script)
	)
end

---@return table settings with crew's hooks and statusLine only
local function crew_settings()
	local hooks = {}
	for _, event in ipairs(M.events) do
		hooks[event] = { { hooks = { { type = "command", command = M.hook_command(event) } } } }
	end
	return { hooks = hooks, statusLine = { type = "command", command = M.statusline_command() } }
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

--- Command with crew's hooks and statusLine merged into its --settings,
--- whatever the executable is called. The claude adapter calls it.
---@param cmd string[]
---@return string[]
function M.merge(cmd)
	cmd = vim.deepcopy(cmd)
	local at = vim.fn.index(cmd, "--settings") + 1 -- 0 when missing
	local settings = at > 0 and cmd[at + 1] and read_settings(cmd[at + 1]) or {}
	local ours = crew_settings()
	settings.hooks = settings.hooks or {}
	for event, list in pairs(ours.hooks) do
		settings.hooks[event] = vim.list_extend(settings.hooks[event] or {}, list)
	end
	-- Only one statusLine can run, so crew's takes the slot and chains the
	-- user's original one (see original_statusline and scripts/statusline.lua).
	settings.statusLine = ours.statusLine
	local json = vim.json.encode(settings)
	if at > 0 then
		cmd[at + 1] = json
	else
		vim.list_extend(cmd, { "--settings", json })
	end
	return cmd
end

--- Like merge, but only for commands named claude; enabled = false opts
--- out. Kept for direct callers: crew itself goes through its adapters.
---@param cmd string[]
---@param enabled? boolean
---@return string[]
function M.command(cmd, enabled)
	if enabled == false or vim.fs.basename(cmd[1] or "") ~= "claude" then
		return vim.deepcopy(cmd)
	end
	return M.merge(cmd)
end

--- The statusLine command the agent would run without crew: from its own
--- --settings first, else from settings.json in its config dir
--- ($CLAUDE_CONFIG_DIR, default ~/.claude). Nil when there is none.
---@param cmd string[]
---@param env table<string, string> The agent's extra environment
---@return string?
function M.original_statusline(cmd, env)
	local at = vim.fn.index(cmd, "--settings") + 1
	local inline = at > 0 and cmd[at + 1] and read_settings(cmd[at + 1]) or {}
	if inline.statusLine and inline.statusLine.command then
		return inline.statusLine.command
	end
	local dir = require("crew.sessions").config_dir(env)
	local file = read_settings(dir .. "/settings.json")
	return file.statusLine and file.statusLine.command or nil
end

return M
