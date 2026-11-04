-- Agent header: bufferline left side and filter, fill background, branch, winbar.
local H = dofile("tests/helpers.lua")
local eq, match, no_match = H.eq, H.match, H.no_match
local child, T = H.new()

-- The agent cwd is a git repo on branch "crew-test".
local function setup(opts)
	child.lua([[
		text = function(chunks) return table.concat(vim.tbl_map(function(c) return c[1] or c.text end, chunks or {})) end
		repo = vim.fn.tempname()
		vim.fn.mkdir(repo, "p")
		vim.fn.system({ "git", "-C", repo, "init", "-q", "-b", "crew-test" })
		vim.cmd.cd(repo)
		require("crew").setup(vim.tbl_extend("force", { agents = { claude = { cmd = { "sh" }, hooks = false } } }, ... or {}))
		ws, status, state = require("crew.workspace"), require("crew.status"), require("crew.state")
		bl = require("crew.bufferline")
	]], { opts })
end

-- One agent in slot 2, named "cuca", with usage, branch read.
local function agent()
	setup()
	child.lua([[
		ws.open("claude")
		a = ws.current()
		vim.wait(2000, function() return a.branch ~= nil end)
		a.name = "cuca"
		state.usage(a.id, { ctx = 71, five_hour = { pct = 87, resets_at = os.time() + 600 }, seven_day = { pct = 23, resets_at = os.time() + 9000 } })
		h = text(status.header())
	]])
end

T["in the editor"] = MiniTest.new_set()

T["in the editor"]["there is no header"] = function()
	setup()
	eq(child.lua_get("status.header()"), vim.NIL)
end

T["in the editor"]["bufferline left is empty"] = function()
	setup()
	eq(child.lua_get("#bl.left()"), 0)
end

T["in the editor"]["bufferline filter shows buffers"] = function()
	setup()
	eq(child.lua_get("bl.filter(vim.api.nvim_get_current_buf())"), true)
end

T["open"] = MiniTest.new_set()

T["open"]["records the cwd"] = function()
	agent()
	eq(child.lua_get("a.cwd == vim.fn.getcwd()"), true)
end

T["open"]["reads the branch in the background"] = function()
	agent()
	eq(child.lua_get("a.branch"), "crew-test")
end

T["header"] = MiniTest.new_set()

T["header"]["starts with slot, profile and name"] = function()
	agent()
	match(child.lua_get("h"), "^ 2 claude cuca")
end

T["header"]["shows the cwd shortened"] = function()
	agent()
	match(child.lua_get("h"), child.lua_get('vim.fn.fnamemodify(repo, ":~")'), true)
end

T["header"]["shows the branch"] = function()
	agent()
	match(child.lua_get("h"), "crew-test", true)
end

T["header"]["shows the meters"] = function()
	agent()
	local h = child.lua_get("h")
	match(h, "ctx  71%", true)
	match(h, "5h  87%", true)
	match(h, "wk  23%", true)
end

T["bufferline left"] = MiniTest.new_set()

T["bufferline left"]["escapes % for the statusline evaluator"] = function()
	agent()
	eq(child.lua_get("text(bl.left())"), (child.lua_get("h"):gsub("%%", "%%%%")))
end

T["bufferline left"]["evaluates without E539"] = function()
	agent()
	eq(child.lua_get("(pcall(vim.api.nvim_eval_statusline, text(bl.left()), { use_tabline = true }))"), true)
end

T["bufferline left"]["items use links"] = function()
	agent()
	eq(child.lua_get("type(bl.left()[1].link)"), "string")
end

T["bufferline left"]["filter hides editor buffers in agent tabs"] = function()
	agent()
	eq(child.lua_get("bl.filter(1)"), false)
end

T["cwd from the statusLine"] = MiniTest.new_set()

T["cwd from the statusLine"]["moves the header and refreshes the branch"] = function()
	agent()
	child.lua([[
		other = vim.fn.tempname()
		vim.fn.mkdir(other, "p")
		vim.fn.system({ "git", "-C", other, "init", "-q", "-b", "other-branch" })
		state.usage(a.id, { cwd = other })
		vim.wait(2000, function() return a.branch == "other-branch" end)
	]])
	eq(child.lua_get("a.cwd == other"), true)
	eq(child.lua_get("a.branch"), "other-branch")
end

T["cwd from the statusLine"]["outside git drops the branch"] = function()
	agent()
	child.lua([[
		nogit = vim.fn.tempname()
		vim.fn.mkdir(nogit, "p")
		state.usage(a.id, { cwd = nogit })
		vim.wait(2000, function() return a.branch == false end)
	]])
	eq(child.lua_get("a.branch"), false)
	no_match(child.lua_get("text(status.header())"), "crew-test", true)
end

T["winbar"] = MiniTest.new_set()

local function winbar_agent()
	setup({ header = "winbar" })
	child.lua([[
		ws.open("claude")
		b = ws.current()
		wb = vim.wo[vim.api.nvim_get_current_win()].winbar
	]])
end

T["winbar"]["is set on the agent window"] = function()
	winbar_agent()
	match(child.lua_get("wb"), "crew", true)
end

T["winbar"]["renders the header"] = function()
	winbar_agent()
	local rendered = child.lua_get(
		"vim.api.nvim_eval_statusline(wb, { winid = vim.api.nvim_get_current_win(), use_winbar = true }).str"
	)
	match(rendered, child.lua_get("b.slot") .. " claude", true)
end

T["winbar"]["is not set on the editor window"] = function()
	winbar_agent()
	child.lua("ws.jump(1)")
	no_match(child.lua_get('vim.wo.winbar or ""'), "crew", true)
end

T["fill background"] = MiniTest.new_set()

-- Header colors sit on bufferline's fill, whatever the source group brings.
local function fill_agent()
	agent()
	child.lua([[
		vim.api.nvim_set_hl(0, "BufferLineFill", { bg = 0x070707 })
		vim.api.nvim_set_hl(0, "Normal", { fg = 0xaaaaaa, bg = 0x111111 })
		ws.jump(1); ws.jump(2)
	]])
end

T["fill background"]["every header item uses the bufferline fill background"] = function()
	fill_agent()
	local bgs = child.lua_get([[(function()
		local bgs = {}
		for _, it in ipairs(bl.left()) do bgs[tostring(vim.api.nvim_get_hl(0, { name = it.link, link = false }).bg or -1)] = true end
		return vim.tbl_keys(bgs)
	end)()]])
	eq(bgs, { tostring(0x070707) })
end

T["fill background"]["a percentage changes color when its level changes"] = function()
	fill_agent()
	child.lua([[
		pct_fg = function()
			local items = bl.left()
			for i, it in ipairs(items) do
				if it.text:find("ctx", 1, true) then return vim.api.nvim_get_hl(0, { name = items[i + 1].link, link = false }).fg end
			end
		end
	]])
	local low = child.lua_get("(function() state.usage(ws.current().id, { ctx = 10 }); return pct_fg() end)()")
	local high = child.lua_get("(function() state.usage(ws.current().id, { ctx = 95 }); return pct_fg() end)()")
	H.neq(high, low)
end

return T
