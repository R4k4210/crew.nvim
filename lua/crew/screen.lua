-- Terminal watcher for CLIs that never say they wait on the user. The
-- adapter names a piece of text its CLI always draws while it waits (agy's
-- selector footer), and crew reports a Screen event whenever that text
-- shows up in, or leaves, the visible bottom of the agent terminal.
local M = {}

local DEBOUNCE = 150 -- ms, terminals redraw in bursts

--- True when the last `height` lines of buf contain text.
---@param buf integer
---@param text string
---@param height integer
---@return boolean
function M.visible(buf, text, height)
	local count = vim.api.nvim_buf_line_count(buf)
	for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, math.max(0, count - height), count, false)) do
		if line:find(text, 1, true) then
			return true
		end
	end
	return false
end

--- Watch the terminal of ws for text until the buffer goes away.
---@param ws crew.Workspace
---@param text string
function M.watch(ws, text)
	local timer = vim.uv.new_timer()
	local function check()
		if not vim.api.nvim_buf_is_valid(ws.buf) then
			return
		end
		local win = vim.fn.bufwinid(ws.buf)
		local height = win ~= -1 and vim.api.nvim_win_get_height(win) or vim.o.lines
		require("crew.state").report(ws.id, "Screen", { waiting = M.visible(ws.buf, text, height) })
	end
	vim.api.nvim_buf_attach(ws.buf, false, {
		on_lines = function()
			timer:start(DEBOUNCE, 0, vim.schedule_wrap(check))
		end,
		on_detach = function()
			timer:stop()
			timer:close()
		end,
	})
end

return M
