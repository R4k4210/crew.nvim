-- Workspaces: agents numbered 1..N with no upper limit. The editor (the
-- "home" tab) stands apart and has no number.
-- Each agent lives in its own tabpage with a single terminal window.
local config = require("crew.config")

---@class crew.Workspace
---@field id integer Stable for the whole life of the workspace, unlike slot. Hooks report with it
---@field slot integer Number shown to the user (1..N), renumbered when a workspace closes
---@field agent string Agent profile name
---@field tab integer Tabpage handle
---@field buf integer Terminal buffer
---@field job integer Job id of the agent process
---@field state? crew.State Reported by the agent hooks (L5), nil until then
---@field name? string Label set by the user, shown in the picker and never in the pills
---@field usage? crew.Usage Reported by the statusLine script (L7), nil until then
---@field cwd? string Where the agent works, updated from its statusLine
---@field branch? string|false Git branch of cwd, false when there is none, nil while unknown

---@class crew.Limit
---@field pct number Percent used
---@field resets_at integer Epoch seconds

---@class crew.Usage
---@field ctx? number Context window percent used
---@field five_hour? crew.Limit
---@field seven_day? crew.Limit

local M = {}

--- Tell tabline and statusline adapters that the workspace list changed.
--- Tab switches redraw on their own; opening and closing do not always.
local function changed()
	vim.cmd.redrawtabline()
	vim.cmd.redrawstatus({ bang = true })
end

---@type table<integer, crew.Workspace>
M.workspaces = {}
---@type integer? Tabpage of the editor
M.home = nil
---@type integer? Slot of the last visited agent, used by toggle()
M.last = nil

local next_id = 0

--- Workspaces in slot order. Slots have no holes once compacted, but a
--- workspace may be gone for a moment while it is being removed.
---@return crew.Workspace[]
function M.ordered()
	local list = vim.tbl_values(M.workspaces)
	table.sort(list, function(a, b)
		return a.slot < b.slot
	end)
	return list
end

---@return integer
local function free_slot()
	local slot = 1
	while M.workspaces[slot] do
		slot = slot + 1
	end
	return slot
end

--- Tab number a new workspace must follow, so tab order matches slot order.
--- Plain :tabnew opens next to the current tab, which scrambles the order.
---@param slot integer
---@return integer
local function tab_before(slot)
	for s = slot - 1, 1, -1 do
		local ws = M.workspaces[s]
		if ws and vim.api.nvim_tabpage_is_valid(ws.tab) then
			return vim.api.nvim_tabpage_get_number(ws.tab)
		end
	end
	if M.home and vim.api.nvim_tabpage_is_valid(M.home) then
		return vim.api.nvim_tabpage_get_number(M.home)
	end
	return vim.fn.tabpagenr()
end

--- Workspace shown in the current tab, if any.
---@return crew.Workspace?
function M.current()
	local tab = vim.api.nvim_get_current_tabpage()
	for _, ws in pairs(M.workspaces) do
		if ws.tab == tab then
			return ws
		end
	end
end

---@param ws crew.Workspace
local function focus(ws)
	vim.api.nvim_set_current_tabpage(ws.tab)
	M.last = ws.slot
	vim.cmd.startinsert()
end

--- Renumber workspaces to 1..n with no holes, keeping their order, so
--- jump(N) always matches agent tab N. M.last follows the agent it pointed to.
local function compact()
	local last = M.last and M.workspaces[M.last]
	local ordered = M.ordered()
	M.workspaces = {}
	for i, ws in ipairs(ordered) do
		ws.slot = i
		M.workspaces[ws.slot] = ws
	end
	M.last = last and last.slot or nil
end

--- Forget a workspace and free everything it owns.
---@param ws crew.Workspace
local function remove(ws)
	if M.workspaces[ws.slot] ~= ws then
		return -- already removed
	end
	M.workspaces[ws.slot] = nil
	if M.last == ws.slot then
		M.last = nil
	end
	pcall(vim.fn.jobstop, ws.job)

	if vim.api.nvim_tabpage_is_valid(ws.tab) and #vim.api.nvim_list_tabpages() > 1 then
		if vim.api.nvim_get_current_tabpage() == ws.tab then
			M.editor()
		end
		vim.cmd.tabclose(vim.api.nvim_tabpage_get_number(ws.tab))
	end
	if vim.api.nvim_buf_is_valid(ws.buf) then
		vim.api.nvim_buf_delete(ws.buf, { force = true })
	end
	compact()
	require("crew.state").update_blink()
	changed()
end

--- Open a new agent workspace.
---@param name? string Agent profile, defaults to config.default_agent
---@return crew.Workspace?
function M.open(name)
	name = name or config.options.default_agent
	local agent = config.options.agents[name]
	if not agent then
		vim.notify(("crew: unknown agent %q"):format(name), vim.log.levels.ERROR)
		return
	end
	local slot = free_slot()

	if not M.current() then
		M.home = vim.api.nvim_get_current_tabpage()
	end

	vim.cmd(("%dtabnew"):format(tab_before(slot)))
	next_id = next_id + 1
	---@type crew.Workspace
	local ws = {
		id = next_id,
		slot = slot,
		agent = name,
		tab = vim.api.nvim_get_current_tabpage(),
		buf = vim.api.nvim_get_current_buf(),
		job = 0,
	}
	-- CREW_ID tells the hooks who they are; Neovim adds $NVIM on its own.
	-- CREW_STATUSLINE is the user's own statusLine, chained by crew's.
	local hooks = require("crew.hooks")
	local env = vim.tbl_extend("force", agent.env or {}, { CREW_ID = tostring(ws.id) })
	if agent.hooks ~= false then
		env.CREW_STATUSLINE = hooks.original_statusline(agent.cmd, agent.env or {})
	end
	ws.job = vim.fn.jobstart(hooks.command(agent.cmd, agent.hooks), {
		term = true,
		env = env,
		on_exit = function()
			-- Job callbacks run in a restricted context, so defer the cleanup.
			vim.schedule(function()
				remove(ws)
			end)
		end,
	})
	vim.bo[ws.buf].buflisted = false -- keep it out of bufferline
	require("crew.keymaps").attach(ws.buf)
	ws.cwd = vim.fn.getcwd()
	M.refresh_branch(ws)
	if config.options.header == "winbar" then
		vim.wo[vim.api.nvim_get_current_win()].winbar = "%{%v:lua.require'crew.status'.winbar()%}"
	end
	M.workspaces[slot] = ws
	focus(ws)
	changed()
	return ws
end

--- Go to the editor (the home tab).
function M.editor()
	if M.home and vim.api.nvim_tabpage_is_valid(M.home) then
		vim.api.nvim_set_current_tabpage(M.home)
	end
	vim.cmd.stopinsert()
end

--- Jump to agent N.
---@param slot? integer
function M.jump(slot)
	local ws = slot and M.workspaces[slot]
	if not ws then
		return -- empty slot: stay put, a notification here is just noise
	end
	focus(ws)
end

--- Editor <-> last agent. Opens the default agent when none exists.
function M.toggle()
	if M.current() then
		return M.editor()
	end
	local ws = (M.last and M.workspaces[M.last]) or M.workspaces[1]
	if ws then
		focus(ws)
	else
		M.open()
	end
end

--- Close a workspace, or the current one when no slot is given.
---@param slot? integer
function M.close(slot)
	local ws = slot and M.workspaces[slot] or M.current()
	if not ws then
		vim.notify("crew: nothing to close", vim.log.levels.WARN)
		return
	end
	remove(ws)
end

--- Close every agent and land in the editor. Silent, even with none open.
function M.close_all()
	-- Leave first, so no agent tab is current while the tabs go away.
	M.editor()
	for _, ws in ipairs(M.ordered()) do
		remove(ws)
	end
end

--- Called before a session file is written. On exit, close every agent so
--- :mksession keeps editor files only; a restored session would otherwise
--- reopen a bare agent terminal outside crew. A save mid session keeps them.
---@param exiting any v:exiting, vim.NIL until Neovim starts to quit
function M.before_session_save(exiting)
	if exiting ~= nil and exiting ~= vim.NIL then
		M.close_all()
	end
end

--- Name a workspace, or the current one when no slot is given.
--- An empty or nil name clears it.
---@param name? string
---@param slot? integer
function M.rename(name, slot)
	local ws = slot and M.workspaces[slot] or M.current()
	if not ws then
		return
	end
	name = name and vim.trim(name) or ""
	ws.name = name ~= "" and name or nil
	changed()
end

--- Read the git branch of ws.cwd in the background. Sets ws.branch to the
--- name, or false outside a repo or on a detached HEAD.
---@param ws crew.Workspace
function M.refresh_branch(ws)
	local cwd = ws.cwd
	if not cwd then
		return
	end
	vim.system({ "git", "-C", cwd, "branch", "--show-current" }, { text = true }, vim.schedule_wrap(function(result)
		if ws.cwd ~= cwd then
			return -- the agent moved on while git was running
		end
		local name = result.code == 0 and vim.trim(result.stdout or "") or ""
		ws.branch = name ~= "" and name or false
		changed()
	end))
end

--- Drop workspaces whose tab was closed by hand (:tabclose).
function M.prune()
	for _, ws in pairs(M.workspaces) do
		if not vim.api.nvim_tabpage_is_valid(ws.tab) then
			remove(ws)
		end
	end
end

return M
