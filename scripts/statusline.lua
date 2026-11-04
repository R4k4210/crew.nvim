-- Claude Code statusLine bridge, run as: nvim --clean --headless -l statusline.lua
-- Claude pipes its status JSON on stdin every time the status refreshes.
-- This forwards context and rate limits to crew through $NVIM, then runs
-- the user's own statusLine ($CREW_STATUSLINE) with the same JSON and prints
-- its output, so the status bar inside Claude looks exactly as before.
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
	local function limit(name)
		local l = data.rate_limits and data.rate_limits[name]
		return l and { pct = l.used_percentage, resets_at = l.resets_at } or nil
	end
	local usage = {
		ctx = data.context_window and data.context_window.used_percentage,
		five_hour = limit("five_hour"),
		seven_day = limit("seven_day"),
	}
	local mode = server:match(":%d+$") and "tcp" or "pipe"
	local chan_ok, chan = pcall(vim.fn.sockconnect, mode, server, { rpc = true })
	if not chan_ok or chan == 0 then
		return
	end
	pcall(vim.rpcrequest, chan, "nvim_exec_lua", [[
		local ok, state = pcall(require, "crew.state")
		if ok then state.usage(...) end
	]], { id, usage })
	vim.fn.chanclose(chan)
end

pcall(forward) -- never let crew break the status bar

local original = os.getenv("CREW_STATUSLINE")
if original and original ~= "" then
	local result = vim.system({ "sh", "-c", original }, { stdin = input, text = true }):wait()
	io.write(result.stdout or "")
end
