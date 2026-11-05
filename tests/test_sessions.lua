-- Claude session files: where they live and what the tail of each one says.
local H = dofile("tests/helpers.lua")
local eq = H.eq
local child, T = H.new()

-- A fake Claude config dir holding sessions for the cwd /work/repo.
local function setup()
	child.lua([[
		sessions = require("crew.sessions")
		config_dir = vim.fn.tempname()
		agent = { cmd = { "claude" }, env = { CLAUDE_CONFIG_DIR = config_dir } }
		cwd = "/work/repo"
		project = config_dir .. "/projects/-work-repo"
		vim.fn.mkdir(project, "p")
		write = function(id, lines, mtime)
			local path = project .. "/" .. id .. ".jsonl"
			vim.fn.writefile(lines, path)
			if mtime then
				vim.uv.fs_utime(path, mtime, mtime)
			end
		end
		rec = function(t) return vim.json.encode(t) end
	]])
end

T["dir"] = MiniTest.new_set()

T["dir"]["encodes every non alphanumeric character as a dash"] = function()
	child.lua([[sessions = require("crew.sessions")]])
	eq(
		child.lua_get([[sessions.dir({ cmd = { "claude" }, env = { CLAUDE_CONFIG_DIR = "/cfg" } }, "/Users/r4k4210/_dev/_personal/crew.nvim")]]),
		"/cfg/projects/-Users-r4k4210--dev--personal-crew-nvim"
	)
end

T["dir"]["falls back to $CLAUDE_CONFIG_DIR, then ~/.claude"] = function()
	child.lua([[sessions = require("crew.sessions")]])
	child.lua([[vim.env.CLAUDE_CONFIG_DIR = "/envcfg"]])
	eq(child.lua_get([[sessions.dir({ cmd = { "claude" } }, "/a")]]), "/envcfg/projects/-a")
	child.lua([[vim.env.CLAUDE_CONFIG_DIR = nil]])
	eq(child.lua_get([[sessions.dir({ cmd = { "claude" } }, "/a")]]), vim.fn.expand("~/.claude") .. "/projects/-a")
end

T["list"] = MiniTest.new_set()

T["list"]["returns {} when the project dir is missing"] = function()
	setup()
	eq(child.lua_get([[sessions.list(agent, "/nowhere")]]), {})
end

T["list"]["sorts newest first with id and mtime"] = function()
	setup()
	child.lua([[
		write("old", { rec({ type = "user" }) }, 1000)
		write("new", { rec({ type = "user" }) }, 3000)
		write("mid", { rec({ type = "user" }) }, 2000)
	]])
	eq(child.lua_get([[vim.tbl_map(function(s) return s.id end, sessions.list(agent, cwd))]]), { "new", "mid", "old" })
	eq(child.lua_get([[sessions.list(agent, cwd)[1].mtime]]), 3000)
end

T["list"]["takes the last occurrence of title, prompt and branch"] = function()
	setup()
	child.lua([[
		write("s", {
			rec({ type = "user", gitBranch = "main" }),
			rec({ type = "ai-title", aiTitle = "first" }),
			rec({ type = "last-prompt", lastPrompt = "one" }),
			rec({ type = "assistant", gitBranch = "feat/x" }),
			rec({ type = "ai-title", aiTitle = "second" }),
			rec({ type = "last-prompt", lastPrompt = "two" }),
		})
	]])
	local s = child.lua_get([[sessions.list(agent, cwd)[1] ]])
	eq({ s.title, s.prompt, s.branch }, { "second", "two", "feat/x" })
end

T["list"]["custom-title beats ai-title"] = function()
	setup()
	child.lua([[
		write("s", {
			rec({ type = "custom-title", customTitle = "mine" }),
			rec({ type = "ai-title", aiTitle = "generated" }),
		})
	]])
	eq(child.lua_get([[sessions.list(agent, cwd)[1].title]]), "mine")
end

T["list"]["malformed lines and missing fields degrade to nil"] = function()
	setup()
	child.lua([[
		write("s", { "{not json", rec({ type = "ai-title" }), "[1,2]", "42", rec({ type = "last-prompt", lastPrompt = 7 }) })
		write("empty", {}, 1)
	]])
	local list = child.lua_get([[sessions.list(agent, cwd)]])
	eq(#list, 2)
	eq({ list[1].id, list[1].title, list[1].prompt, list[1].branch }, { "s", nil, nil, nil })
	eq(list[2].id, "empty")
end

T["list"]["reads only the last 64 KB"] = function()
	setup()
	child.lua([[
		local filler = {}
		for i = 1, 1000 do filler[i] = rec({ type = "user", text = string.rep("x", 100) }) end
		local head = vim.list_extend({ rec({ type = "ai-title", aiTitle = "lost" }) }, filler)
		write("head", head, 1)
		local tail = vim.list_extend(vim.deepcopy(filler), { rec({ type = "ai-title", aiTitle = "found" }) })
		write("tail", tail, 2)
	]])
	local list = child.lua_get([[sessions.list(agent, cwd)]])
	eq({ list[1].id, list[1].title }, { "tail", "found" })
	eq({ list[2].id, list[2].title }, { "head", nil })
end

return T
