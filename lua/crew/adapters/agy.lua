-- Antigravity CLI (agy): resume by conversation id and crew's sessions
-- picker, read from agy's own conversation_summaries.db through sqlite3.
-- The db is undocumented, so any failure yields no sessions, never an error.
-- State pills, usage and the conversation id need :Crew setup agy, which
-- installs crew's hooks plugin and statusLine bridge (crew.agy_bridge).

---@type crew.Adapter
local M = { name = "agy" }

--- agy's data dir. Tests point it to a temp dir.
M.data_dir = vim.fn.expand("~/.gemini/antigravity-cli")

local QUERY = "SELECT conversation_id, title, preview, workspace_uris, last_modified_time FROM conversation_summaries"

--- Epoch seconds of a UTC timestamp like "2026-10-01 22:32:37.837267+00:00".
---@param s any
---@return integer?
local function epoch(s)
	if type(s) ~= "string" then
		return nil
	end
	local y, m, d, hh, mm, ss = s:match("^(%d+)%-(%d+)%-(%d+)[ T](%d+):(%d+):(%d+)")
	if not y then
		return nil
	end
	y, m, d = tonumber(y), tonumber(m), tonumber(d)
	-- Days from the civil date, independent of the local time zone.
	y = m <= 2 and y - 1 or y
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	local days = era * 146097 + doe - 719468
	return days * 86400 + tonumber(hh) * 3600 + tonumber(mm) * 60 + tonumber(ss)
end

---@param v any
---@return string?
local function str(v)
	return type(v) == "string" and v ~= "" and v or nil
end

--- True when the JSON list of file:// URIs holds cwd.
---@param uris any
---@param cwd string
---@return boolean
local function in_workspace(uris, cwd)
	local ok, list = pcall(vim.json.decode, type(uris) == "string" and uris or "")
	if not ok or type(list) ~= "table" then
		return false
	end
	for _, uri in ipairs(list) do
		if type(uri) == "string" and vim.startswith(uri, "file://") then
			local path_ok, path = pcall(vim.uri_to_fname, uri)
			if path_ok and path:gsub("/$", "") == cwd then
				return true
			end
		end
	end
	return false
end

--- statusline = false hides the user's status line inside crew; the
--- bridge reads this flag and still forwards state and usage.
function M.prepare(cmd, agent)
	if agent.statusline == false then
		return cmd, { CREW_STATUSLINE_OFF = "1" }
	end
	return cmd
end

--- The latest conversation agy recorded for cwd, from its
--- cache/last_conversations.json (workspace path -> conversation id).
---@param cwd string
---@return string?
function M.last_session(_, cwd)
	local ok, lines = pcall(vim.fn.readfile, M.data_dir .. "/cache/last_conversations.json")
	if not ok then
		return nil
	end
	local decoded_ok, map = pcall(vim.json.decode, table.concat(lines, "\n"))
	if not decoded_ok or type(map) ~= "table" then
		return nil
	end
	return str(map[cwd:gsub("/$", "")])
end

function M.health(_, report)
	local bridge = require("crew.agy_bridge")
	if bridge.installed() then
		report.ok("agy bridge installed: state pills, context and resume")
	else
		report.warn("agy bridge not installed, run :Crew setup agy for state pills, context and resume", {
			"restart agy after :Crew setup agy",
		})
	end
end

function M.resume_args(id)
	return id and { "--conversation", id } or nil
end

function M.sessions(_, cwd)
	local db = M.data_dir .. "/conversation_summaries.db"
	if vim.fn.executable("sqlite3") == 0 or not vim.uv.fs_stat(db) then
		return {}
	end
	local ok, res = pcall(function()
		return vim.system({ "sqlite3", "-readonly", "-json", db, QUERY }, { text = true }):wait(2000)
	end)
	if not ok or res.code ~= 0 then
		return {}
	end
	local decoded_ok, rows = pcall(vim.json.decode, res.stdout ~= "" and res.stdout or "[]")
	if not decoded_ok or type(rows) ~= "table" then
		return {}
	end
	cwd = cwd:gsub("/$", "")
	local list = {}
	for _, row in ipairs(rows) do
		local id = type(row) == "table" and str(row.conversation_id)
		if id and in_workspace(row.workspace_uris, cwd) then
			list[#list + 1] = {
				id = id,
				mtime = epoch(row.last_modified_time) or 0,
				title = str(row.title),
				prompt = str(row.preview),
			}
		end
	end
	table.sort(list, function(a, b)
		return a.mtime > b.mtime
	end)
	return list
end

return M
