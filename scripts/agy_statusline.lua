-- agy statusLine bridge, run as: nvim --clean --headless -l agy_statusline.lua <original>
-- agy only reads its statusLine from its global settings.json, so
-- :Crew setup agy puts this script there and saves the user's own one in
-- <original> (JSON with the old statusLine object). agy pipes its status
-- JSON on stdin on every refresh. Inside a crew agent ($NVIM and CREW_ID)
-- this forwards the ask state, context and conversation id to crew. In
-- every case it then runs the original command with the same JSON and
-- prints its output, so agy looks exactly as before, unless the profile
-- set statusline = false (CREW_STATUSLINE_OFF).
local input = io.read("*a") or ""

local function forward()
	local server, id = os.getenv("NVIM"), tonumber(os.getenv("CREW_ID") or "")
	if not (server and id) then
		return
	end
	local ok, data = pcall(vim.json.decode, input, { luanil = { object = true, array = true } })
	if not ok or type(data) ~= "table" then
		return
	end
	local workspace = type(data.workspace) == "table" and data.workspace or {}
	-- Quota buckets have no documented unit or window, so only context is used.
	local usage = {
		ctx = type(data.context_window) == "table" and data.context_window.used_percentage or nil,
		cwd = workspace.current_dir or data.cwd,
	}
	local status = {
		pending = data.tool_confirmation_pending == true,
		busy = data.agent_state == "working" or data.agent_state == "tool_use",
		session_id = data.conversation_id,
	}
	local mode = server:match(":%d+$") and "tcp" or "pipe"
	local chan_ok, chan = pcall(vim.fn.sockconnect, mode, server, { rpc = true })
	if not chan_ok or chan == 0 then
		return
	end
	pcall(vim.rpcrequest, chan, "nvim_exec_lua", [[
		local ok, state = pcall(require, "crew.state")
		if ok then
			local id, usage, status = ...
			state.usage(id, usage)
			state.report(id, "StatusLine", status)
		end
	]], { id, usage, status })
	vim.fn.chanclose(chan)
end

pcall(forward) -- never let crew break the status bar

---@return string?
local function original()
	local file = arg[1]
	local f = file and io.open(file, "r")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	local ok, data = pcall(vim.json.decode, text)
	local line = ok and type(data) == "table" and data.statusLine
	return type(line) == "table" and type(line.command) == "string" and line.command or nil
end

local command = original()
if command and command ~= "" and os.getenv("CREW_STATUSLINE_OFF") ~= "1" then
	local result = vim.system({ "sh", "-c", command }, { stdin = input, text = true }):wait()
	io.write(result.stdout or "")
end
