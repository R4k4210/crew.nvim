-- Send context from the editor to an agent: an @path mention for a file, or
-- the selected lines with their location. Text goes in as a bracketed paste,
-- so the agent treats it as pasted input and never submits it on its own.
local M = {}

local PASTE_START, PASTE_END = "\27[200~", "\27[201~"

---@alias crew.SendTarget "pick"|"last"

---@param agent crew.Workspace
---@param text string
local function deliver(agent, text)
	vim.api.nvim_chan_send(agent.job, PASTE_START .. text .. PASTE_END)
	require("crew.workspace").jump(agent.slot) -- land in the agent to type the question
end

---@return crew.Workspace[]
local function open_agents()
	local ws, list = require("crew.workspace"), {}
	for slot = 2, 9 do
		list[#list + 1] = ws.workspaces[slot]
	end
	return list
end

--- "last": the current agent, else the last visited, else the first open.
--- "pick": ask which instance, unless only one is open.
---@param text string
---@param how? crew.SendTarget defaults to "pick"
local function paste(text, how)
	local ws = require("crew.workspace")
	local agents = open_agents()
	if #agents == 0 then
		vim.notify("crew: no agent open to send to", vim.log.levels.WARN)
		return
	end
	if how == "last" or #agents == 1 then
		return deliver(ws.current() or (ws.last and ws.workspaces[ws.last]) or agents[1], text)
	end
	require("crew.picker").instances("Crew send to", function(slot)
		local agent = ws.workspaces[slot]
		if agent then
			deliver(agent, text)
		end
	end)
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
---@param how? crew.SendTarget
function M.file(how)
	local p = path()
	if p then
		paste("@" .. p .. " ", how)
	end
end

--- Send lines first..last of the current buffer with their location.
---@param first integer
---@param last integer
---@param how? crew.SendTarget
function M.selection(first, last, how)
	if first > last then
		first, last = last, first
	end
	local lines = vim.api.nvim_buf_get_lines(0, first - 1, last, false)
	local ft = vim.bo.filetype ~= "" and vim.bo.filetype or (vim.filetype.match({ buf = 0 }) or "")
	local range = first == last and tostring(first) or ("%d-%d"):format(first, last)
	local p = path()
	local head = p and ("@%s:%s\n"):format(p, range) or ""
	paste(("%s```%s\n%s\n```\n"):format(head, ft, table.concat(lines, "\n")), how)
end

return M
