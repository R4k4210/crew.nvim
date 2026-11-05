-- :Crew setup agy. agy has no per invocation settings flag, so crew plugs
-- into its global config once: a hooks plugin for the work and done
-- states plus the conversation id, and a statusLine bridge for the ask
-- state and context. Both stay inert outside crew: the hooks need $NVIM,
-- and the bridge then only runs the user's own statusLine.
local hooks = require("crew.hooks")

local M = {}

M.events = { "PreInvocation", "PostToolUse", "Stop" }

---@return string
local function data_dir()
	return require("crew.adapters.agy").data_dir
end

--- agy's global customization root, where it discovers plugins. Its
--- data dir (crew.adapters.agy) holds settings.json. Tests override both.
M.config_dir = vim.fn.expand("~/.gemini/config")

---@return string
function M.plugin_dir()
	return M.config_dir .. "/plugins/crew"
end

---@return string
local function settings_path()
	return data_dir() .. "/settings.json"
end

--- Where install keeps the user's own statusLine, as {"statusLine": {...}}
--- or {} when there was none.
---@return string
function M.original_file()
	return require("crew.persist").dir .. "/agy_statusline.json"
end

--- Neovim as found on PATH, since these commands outlive this Neovim and
--- v:progpath may be a versioned path that an upgrade removes.
---@return string
local function nvim()
	local path = vim.fn.exepath("nvim")
	return path ~= "" and path or vim.v.progpath
end

--- Shell command for one hook event. agy reads every hook's stdout as
--- JSON, so it always prints an empty object after the guarded call.
---@param event string
---@return string
function M.hook_command(event)
	return ('[ -n "$NVIM" ] && %s --clean --headless -l %s %s; printf \'{}\\n\''):format(
		vim.fn.shellescape(nvim()),
		vim.fn.shellescape(hooks.script),
		event
	)
end

---@return string
function M.bridge_command()
	return ("%s --clean --headless -l %s %s"):format(
		vim.fn.shellescape(nvim()),
		vim.fn.shellescape(hooks.agy_statusline_script),
		vim.fn.shellescape(M.original_file())
	)
end

---@param line any
---@return boolean
local function is_bridge(line)
	return type(line) == "table"
		and type(line.command) == "string"
		and line.command:find("agy_statusline.lua", 1, true) ~= nil
end

---@param path string
---@return string?
local function read(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

---@param path string
---@return table?
local function read_json(path)
	local text = read(path)
	if not text then
		return nil
	end
	local ok, data = pcall(vim.json.decode, text)
	return ok and type(data) == "table" and data or nil
end

--- Pretty JSON when this Neovim can indent, else compact.
---@param data table
---@return string
local function encode(data)
	if next(data) == nil then
		return "{}\n" -- an empty Lua table would encode as []
	end
	local ok, text = pcall(vim.json.encode, data, { indent = "  ", sort_keys = true })
	return (ok and text or vim.json.encode(data)) .. "\n"
end

--- Write through a temp file and a rename, so a crash never leaves half a file.
--- Returns false when the content is already there.
---@param path string
---@param text string
---@return boolean changed
local function write(path, text)
	if read(path) == text then
		return false
	end
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	local tmp = path .. ".tmp"
	local f = assert(io.open(tmp, "w"))
	f:write(text)
	f:close()
	assert(vim.uv.fs_rename(tmp, path))
	return true
end

--- Save settings.json with a timestamped backup of the old one next to it.
---@param settings table
local function write_settings(settings)
	local path = settings_path()
	local old = read(path)
	-- agy rewrites the file in its own format, so compare content, not text.
	local ok, current = pcall(vim.json.decode, old or "")
	if ok and vim.deep_equal(current, settings) then
		return
	end
	local text = encode(settings)
	if old then
		write(("%s.crew-%s.bak"):format(path, os.date("%Y%m%d%H%M%S")), old)
	end
	write(path, text)
end

---@return table
local function hooks_spec()
	local spec = {}
	for _, event in ipairs(M.events) do
		local handler = { type = "command", command = M.hook_command(event), timeout = 5 }
		-- Tool events group their handlers under a matcher, the others list them.
		spec[event] = event == "PostToolUse" and { { matcher = "*", hooks = { handler } } } or { handler }
	end
	return { crew = spec }
end

--- Install the plugin and the bridge. Safe to run again: an installed
--- bridge is refreshed in place and never saved as the original.
function M.install()
	local dir = M.plugin_dir()
	write(dir .. "/plugin.json", encode({ name = "crew", version = "1.0.0", description = "crew.nvim agent state for Neovim" }))
	write(dir .. "/hooks.json", encode(hooks_spec()))
	local path = settings_path()
	if read(path) and not read_json(path) then
		error(("crew: %s is not valid JSON, left untouched"):format(path), 0)
	end
	local settings = read_json(path) or {}
	local line = settings.statusLine
	if not is_bridge(line) then
		write(M.original_file(), encode(type(line) == "table" and { statusLine = line } or {}))
	end
	local bridge = type(line) == "table" and vim.deepcopy(line) or {}
	bridge.type, bridge.command = "command", M.bridge_command()
	settings.statusLine = bridge
	write_settings(settings)
end

--- Undo install: delete the plugin and put the original statusLine back,
--- or drop the key when there was none.
function M.remove()
	vim.fn.delete(M.plugin_dir(), "rf")
	local settings = read_json(settings_path())
	if settings and is_bridge(settings.statusLine) then
		local saved = read_json(M.original_file()) or {}
		settings.statusLine = saved.statusLine
		write_settings(settings)
	end
	os.remove(M.original_file())
end

--- True when both the plugin and the bridge are in place.
---@return boolean
function M.installed()
	local settings = read_json(settings_path()) or {}
	return vim.fn.filereadable(M.plugin_dir() .. "/hooks.json") == 1 and is_bridge(settings.statusLine)
end

--- Entry point for :Crew setup agy [remove].
---@param args string[]
function M.run(args)
	local ok, err = pcall(args[1] == "remove" and M.remove or M.install)
	if not ok then
		vim.notify(tostring(err), vim.log.levels.ERROR)
	elseif args[1] == "remove" then
		vim.notify("crew: agy bridge removed, restart agy to apply")
	else
		vim.notify("crew: agy bridge installed, restart agy to apply")
	end
end

return M
