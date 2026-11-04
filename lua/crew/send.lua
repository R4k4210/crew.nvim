-- Send context from the editor to an agent: an @path mention for a file, or
-- the selected lines with their location. Text goes in as a bracketed paste,
-- so the agent treats it as pasted input and never submits it on its own.
local M = {}

local PASTE_START, PASTE_END = "\27[200~", "\27[201~"

--- Agent in the current tab, else the last visited one, else the first open.
---@return crew.Workspace?
local function target()
	local ws = require("crew.workspace")
	local found = ws.current() or (ws.last and ws.workspaces[ws.last])
	if found then
		return found
	end
	for slot = 2, 9 do
		if ws.workspaces[slot] then
			return ws.workspaces[slot]
		end
	end
end

---@param text string
local function paste(text)
	local agent = target()
	if not agent then
		vim.notify("crew: no agent open to send to", vim.log.levels.WARN)
		return
	end
	vim.api.nvim_chan_send(agent.job, PASTE_START .. text .. PASTE_END)
	require("crew.workspace").jump(agent.slot) -- land in the agent to type the question
end

--- Path of the current buffer relative to the cwd, nil for unnamed buffers.
---@return string?
local function path()
	local name = vim.api.nvim_buf_get_name(0)
	if name == "" then
		return nil
	end
	return vim.fn.fnamemodify(name, ":~:.")
end

--- Mention the current file, e.g. "@lua/crew/send.lua ".
function M.file()
	local p = path()
	if p then
		paste("@" .. p .. " ")
	end
end

--- Send lines first..last of the current buffer with their location.
---@param first integer
---@param last integer
function M.selection(first, last)
	if first > last then
		first, last = last, first
	end
	local lines = vim.api.nvim_buf_get_lines(0, first - 1, last, false)
	local ft = vim.bo.filetype ~= "" and vim.bo.filetype or (vim.filetype.match({ buf = 0 }) or "")
	local range = first == last and tostring(first) or ("%d-%d"):format(first, last)
	local p = path()
	local head = p and ("@%s:%s\n"):format(p, range) or ""
	paste(("%s```%s\n%s\n```\n"):format(head, ft, table.concat(lines, "\n")))
end

return M
