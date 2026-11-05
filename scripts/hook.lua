-- Agent hook bridge, run as: nvim --clean --headless -l hook.lua <Event>
-- The CLI (Claude Code, or agy through crew's plugin) pipes the hook JSON
-- on stdin. This connects to the Neovim that owns
-- the agent ($NVIM, set in every :terminal job) and hands the event to
-- crew.state. Any failure exits quietly: a hook must never get in the way.
local event = arg[1]
local server, id = os.getenv("NVIM"), tonumber(os.getenv("CREW_ID") or "")
if not (event and server and id) then
	return
end

local ok, payload = pcall(vim.json.decode, io.read("*a") or "")
payload = ok and type(payload) == "table" and payload or {}

local mode = server:match(":%d+$") and "tcp" or "pipe" -- host:port or a socket path
local chan_ok, chan = pcall(vim.fn.sockconnect, mode, server, { rpc = true })
if not chan_ok or chan == 0 then
	return
end
pcall(vim.rpcrequest, chan, "nvim_exec_lua", [[
	local ok, state = pcall(require, "crew.state")
	if ok then state.report(...) end
]], { id, event, {
	notification_type = payload.notification_type,
	-- Claude names it session_id, agy conversationId.
	session_id = payload.session_id or payload.conversationId,
} })
vim.fn.chanclose(chan)
