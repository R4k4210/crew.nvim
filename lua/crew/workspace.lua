-- Workspaces: slot 1 is the editor (the "home" tab), slots 2..9 are agents.
-- Each agent lives in its own tabpage with a single terminal window.
local config = require("crew.config")

---@class crew.Workspace
---@field slot integer Number shown to the user (2..9)
---@field agent string Agent profile name
---@field tab integer Tabpage handle
---@field buf integer Terminal buffer
---@field job integer Job id of the agent process
---@field state? crew.State Reported by the agent hooks (L5), nil until then

local M = {}

--- Tell tabline and statusline adapters that the workspace list changed.
--- Tab switches redraw on their own; opening and closing do not always.
local function changed()
	vim.cmd.redrawtabline()
	vim.cmd.redrawstatus({ bang = true })
end

local MAX_SLOT = 9

---@type table<integer, crew.Workspace>
M.workspaces = {}
---@type integer? Tabpage of the editor
M.home = nil
---@type integer? Slot of the last visited agent, used by toggle()
M.last = nil

---@return integer?
local function free_slot()
	for slot = 2, MAX_SLOT do
		if not M.workspaces[slot] then
			return slot
		end
	end
end

--- Tab number a new workspace must follow, so tab order matches slot order.
--- Plain :tabnew opens next to the current tab, which scrambles the order.
---@param slot integer
---@return integer
local function tab_before(slot)
	for s = slot - 1, 2, -1 do
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

--- Renumber workspaces to 2..n with no holes, keeping their order, so
--- jump(N) always matches tab N. M.last follows the agent it pointed to.
local function compact()
	local last = M.last and M.workspaces[M.last]
	local ordered = {}
	for slot = 2, MAX_SLOT do
		if M.workspaces[slot] then
			ordered[#ordered + 1] = M.workspaces[slot]
		end
	end
	M.workspaces = {}
	for i, ws in ipairs(ordered) do
		ws.slot = i + 1
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
			M.jump(1)
		end
		vim.cmd.tabclose(vim.api.nvim_tabpage_get_number(ws.tab))
	end
	if vim.api.nvim_buf_is_valid(ws.buf) then
		vim.api.nvim_buf_delete(ws.buf, { force = true })
	end
	compact()
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
	if not slot then
		vim.notify("crew: all workspaces are taken", vim.log.levels.WARN)
		return
	end

	if not M.current() then
		M.home = vim.api.nvim_get_current_tabpage()
	end

	vim.cmd(("%dtabnew"):format(tab_before(slot)))
	---@type crew.Workspace
	local ws = {
		slot = slot,
		agent = name,
		tab = vim.api.nvim_get_current_tabpage(),
		buf = vim.api.nvim_get_current_buf(),
		job = 0,
	}
	ws.job = vim.fn.jobstart(agent.cmd, {
		term = true,
		env = agent.env,
		on_exit = function()
			-- Job callbacks run in a restricted context, so defer the cleanup.
			vim.schedule(function()
				remove(ws)
			end)
		end,
	})
	vim.bo[ws.buf].buflisted = false -- keep it out of bufferline
	require("crew.keymaps").attach(ws.buf)
	M.workspaces[slot] = ws
	focus(ws)
	changed()
	return ws
end

--- Jump to a workspace. Slot 1 is the editor.
---@param slot? integer
function M.jump(slot)
	if slot == 1 then
		if M.home and vim.api.nvim_tabpage_is_valid(M.home) then
			vim.api.nvim_set_current_tabpage(M.home)
		end
		vim.cmd.stopinsert()
		return
	end
	local ws = slot and M.workspaces[slot]
	if not ws then
		vim.notify(("crew: no workspace %s"):format(slot or "?"), vim.log.levels.WARN)
		return
	end
	focus(ws)
end

--- Editor <-> last agent. Opens the default agent when none exists.
function M.toggle()
	if M.current() then
		return M.jump(1)
	end
	local ws = (M.last and M.workspaces[M.last]) or select(2, next(M.workspaces))
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

--- Drop workspaces whose tab was closed by hand (:tabclose).
function M.prune()
	for _, ws in pairs(M.workspaces) do
		if not vim.api.nvim_tabpage_is_valid(ws.tab) then
			remove(ws)
		end
	end
end

return M
