-- doc/crew.txt builds valid help tags and every section is reachable.
local H = dofile("tests/helpers.lua")
local child, T = H.new()

local TAGS = {
	"crew.txt",
	"crew-introduction",
	"crew-setup",
	"crew-options",
	"crew-keys",
	"crew-commands",
	":Crew",
	"crew-pickers",
	"crew-state",
	"crew-pills",
	"crew-highlights",
	"crew-health",
}

T["helptags build without errors and every tag opens"] = function()
	-- Build tags on a copy so tests never write doc/tags into the repo. :help
	-- needs a runtimepath entry whose doc/ holds the file and its tags.
	local root = vim.fn.tempname()
	vim.fn.mkdir(root .. "/doc", "p")
	vim.fn.writefile(vim.fn.readfile("doc/crew.txt"), root .. "/doc/crew.txt")
	child.cmd("helptags " .. root .. "/doc")
	child.lua("vim.opt.rtp:prepend(...)", { root })
	for _, tag in ipairs(TAGS) do
		local ok = child.lua("local tag = ...; return pcall(vim.cmd.help, tag)", { tag })
		H.eq({ tag, ok }, { tag, true })
	end
end

T["doc lines stay within 78 columns"] = function()
	for i, line in ipairs(vim.fn.readfile("doc/crew.txt")) do
		if vim.fn.strdisplaywidth(line) > 78 then
			error(("doc/crew.txt:%d is %d columns"):format(i, vim.fn.strdisplaywidth(line)))
		end
	end
end

return T
