-- Antigravity (agy): sessions from its conversation_summaries.db, resume by id.
local H = dofile("tests/helpers.lua")
local eq = H.eq
local child, T = H.new()

local function need_sqlite()
	if vim.fn.executable("sqlite3") == 0 then
		MiniTest.skip("sqlite3 is not installed")
	end
end

-- A fake agy data dir whose db holds conversations of three workspaces.
local function setup()
	need_sqlite()
	child.lua([[
		agy = require("crew.adapters.agy")
		agy.data_dir = vim.fn.tempname()
		vim.fn.mkdir(agy.data_dir, "p")
		local sql = [=[
			CREATE TABLE conversation_summaries (conversation_id text, title text NOT NULL DEFAULT '',
				preview text NOT NULL DEFAULT '', last_modified_time datetime NOT NULL,
				workspace_uris text NOT NULL, killed numeric NOT NULL DEFAULT false);
			INSERT INTO conversation_summaries VALUES
				('old', 'Old work', 'first prompt', '2026-09-30 12:00:00.000000+00:00', '["file:///work/My%20Dir"]', 0),
				('new', '', 'latest prompt', '2026-10-02 08:00:00.5+00:00', '["file:///other","file:///work/My%20Dir"]', 1),
				('mid', 'Mid', '', '2026-10-01 22:32:37.837267+00:00', '["file:///work/My%20Dir"]', 0),
				('elsewhere', 'Else', 'x', '2026-10-03 00:00:00+00:00', '["file:///work/My%20Dir/sub"]', 0),
				('broken', 'Bad', 'x', '2026-10-03 00:00:00+00:00', 'not json', 0);
		]=]
		local res = vim.system({ "sqlite3", agy.data_dir .. "/conversation_summaries.db", sql }):wait()
		assert(res.code == 0, res.stderr)
		agent = { cmd = { "agy" } }
	]])
end

T["sessions"] = MiniTest.new_set()

T["sessions"]["lists the conversations of cwd newest first"] = function()
	setup()
	local list = child.lua_get([[agy.sessions(agent, "/work/My Dir")]])
	eq(vim.tbl_map(function(s)
		return s.id
	end, list), { "new", "mid", "old" })
	eq(list[1].mtime, 1790928000)
	eq(list[2].mtime, 1790893957)
	eq(list[3].mtime, 1790769600)
end

T["sessions"]["maps empty title and preview to nil"] = function()
	setup()
	local list = child.lua_get([[agy.sessions(agent, "/work/My Dir")]])
	eq(list[1].title, nil)
	eq(list[1].prompt, "latest prompt")
	eq(list[2].title, "Mid")
	eq(list[2].prompt, nil)
	eq(list[3].branch, nil)
end

T["sessions"]["returns {} when the db is missing"] = function()
	child.lua([[
		agy = require("crew.adapters.agy")
		agy.data_dir = vim.fn.tempname()
	]])
	eq(child.lua_get([[agy.sessions({ cmd = { "agy" } }, "/work")]]), {})
end

T["sessions"]["returns {} for a cwd with no conversations"] = function()
	setup()
	eq(child.lua_get([[agy.sessions(agent, "/nowhere")]]), {})
end

T["resume_args"] = MiniTest.new_set()

T["resume_args"]["resumes a conversation by id and has no picker args"] = function()
	child.lua([[agy = require("crew.adapters.agy")]])
	eq(child.lua_get([[agy.resume_args("abc")]]), { "--conversation", "abc" })
	eq(child.lua_get([[agy.resume_args()]]), vim.NIL)
end

-- An agy profile that starts a shell instead, recording the command.
local function profile()
	child.lua([[
		require("crew").setup({ agents = { agy = { cmd = { "agy" } } } })
		started = {}
		local jobstart = vim.fn.jobstart
		vim.fn.jobstart = function(cmd, o)
			started[#started + 1] = cmd
			return jobstart({ "sh" }, o)
		end
	]])
end

T["restore"] = MiniTest.new_set()

T["restore"]["reopens an agy profile on its saved conversation"] = function()
	profile()
	child.lua([[
		persist = require("crew.persist")
		persist.dir = vim.fn.tempname()
		vim.fn.mkdir(persist.dir, "p")
		vim.fn.writefile({ vim.json.encode({ version = 1, agents = { { agent = "agy", session_id = "c1" } } }) }, persist.path())
	]])
	eq(child.lua_get("persist.restore()"), 1)
	eq(child.lua_get("started[1]"), { "agy", "--conversation", "c1" })
end

T["open"] = MiniTest.new_set()

T["open"]["starts the bare agy cmd with no CREW_STATUSLINE"] = function()
	profile()
	child.lua([[
		envs = {}
		local start = vim.fn.jobstart
		vim.fn.jobstart = function(cmd, o)
			envs[#envs + 1] = o.env
			return start(cmd, o)
		end
		require("crew.workspace").open()
	]])
	eq(child.lua_get("started[1]"), { "agy" })
	eq(child.lua_get("envs[1].CREW_STATUSLINE"), vim.NIL)
end

T["resume"] = MiniTest.new_set()

T["resume"]["opens crew's sessions picker and resumes the picked conversation"] = function()
	setup()
	profile()
	child.lua([[
		vim.fn.getcwd = function() return "/work/My Dir" end
		vim.ui.select = function(items, opts, on_choice) on_choice(items[2]) end
		require("crew.workspace").resume()
	]])
	eq(child.lua_get("started[1]"), { "agy", "--conversation", "mid" })
end

return T
