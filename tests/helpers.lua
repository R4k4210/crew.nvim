-- Shared helpers: a child Neovim restarted for every case, plus expectations.
local H = {}

H.eq = MiniTest.expect.equality
H.neq = MiniTest.expect.no_equality

--- Expect `str` to contain the Lua pattern `pattern` (plain when `plain` is true).
H.match = MiniTest.new_expectation("string matching", function(str, pattern, plain)
	return type(str) == "string" and str:find(pattern, 1, plain) ~= nil
end, function(str, pattern)
	return ("Pattern: %s\nObserved: %s"):format(vim.inspect(pattern), vim.inspect(str))
end)

H.no_match = MiniTest.new_expectation("string not matching", function(str, pattern, plain)
	return type(str) == "string" and str:find(pattern, 1, plain) == nil
end, function(str, pattern)
	return ("Pattern: %s\nObserved: %s"):format(vim.inspect(pattern), vim.inspect(str))
end)

--- A child Neovim and a test set that restarts it before every case.
---@return table child, table set
function H.new()
	local child = MiniTest.new_child_neovim()
	local set = MiniTest.new_set({
		hooks = {
			pre_case = function()
				child.restart({ "-u", "tests/minimal_init.lua" })
			end,
			post_once = child.stop,
		},
	})
	return child, set
end

return H
