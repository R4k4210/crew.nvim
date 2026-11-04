-- Pickers: new instance from a profile, jump to an open instance, and the
-- rename input. With snacks installed crew opens its own snacks picker with
-- no preview window, so the user's global picker layout stays untouched for
-- files and grep. Without snacks it falls back to vim.ui.select.
local config = require("crew.config")

local M = {}

---@alias crew.Chunk { [1]: string, [2]?: string } text and highlight group

---@param s string
---@param width integer
---@return string
local function pad(s, width)
	return s .. string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(s)))
end

---@param pct? number
---@return crew.Chunk
local function percent(pct)
	if not pct then
		return { "   –", "Comment" }
	end
	local hl = pct >= 85 and "DiagnosticError" or pct >= 60 and "DiagnosticWarn" or "DiagnosticOk"
	return { ("%3d%%"):format(pct), hl }
end

--- "2h14m" or "47m" until an epoch time.
---@param at integer
---@return string
local function time_left(at)
	local mins = math.max(0, math.floor((at - os.time()) / 60))
	local h, m = math.floor(mins / 60), mins % 60
	return h > 0 and ("%dh%dm"):format(h, m) or ("%dm"):format(m)
end

--- "nov 26 18:00" for an epoch time.
---@param at integer
---@return string
local function date(at)
	return os.date("%b %d %H:%M", at):lower()
end

---@param limit? crew.Limit
---@param fmt fun(at: integer): string
---@param width integer
---@return crew.Chunk[]
local function limit_cells(limit, fmt, width)
	local reset = limit and limit.resets_at and ("↻ " .. fmt(limit.resets_at)) or ""
	return { percent(limit and limit.pct), { " " .. pad(reset, width), "Comment" } }
end

local STATE_HL = { work = "CrewPillWork", ask = "CrewPillAsk", done = "CrewPillDone" }

--- One aligned row per instance. Widths come from the whole list so the
--- columns line up whatever the profile and instance names are.
---@param entry crew.Entry
---@param widths { agent: integer, name: integer }
---@return crew.Chunk[]
function M.instance_row(entry, widths)
	local usage = entry.usage or {}
	local chunks = {
		{ ("%d  "):format(entry.slot), "Number" },
		{ pad(entry.agent, widths.agent) .. " ", "Function" },
		entry.name and { pad(entry.name, widths.name), "Normal" } or { pad("·", widths.name), "Comment" },
		{ " │ ctx ", "Comment" },
		percent(usage.ctx),
		{ " │ 5h ", "Comment" },
	}
	vim.list_extend(chunks, limit_cells(usage.five_hour, time_left, 8))
	chunks[#chunks + 1] = { " wk ", "Comment" }
	vim.list_extend(chunks, limit_cells(usage.seven_day, date, 14))
	local icon = entry.state and config.options.icons[entry.state]
	if icon then
		chunks[#chunks + 1] = { icon, STATE_HL[entry.state] }
	end
	return chunks
end

---@param chunks crew.Chunk[]
---@return string
local function plain(chunks)
	local text = table.concat(vim.tbl_map(function(c)
		return c[1]
	end, chunks))
	return (text:gsub("%s+$", ""))
end

---@class crew.PickItem
---@field text string Plain row, used for filtering and by vim.ui.select
---@field chunks crew.Chunk[]
---@field value any

--- Show a list and call on_choice with the chosen value (never with nil).
---@param title string
---@param items crew.PickItem[]
---@param on_choice fun(value: any)
---@param selected? integer Row the cursor starts on (snacks only)
local function select(title, items, on_choice, selected)
	local ok, snacks = pcall(require, "snacks")
	if ok and snacks.picker then
		snacks.picker.pick({
			title = title,
			items = items,
			on_show = selected and function(picker)
				picker.list:set_target(selected)
			end or nil,
			format = function(item)
				return item.chunks
			end,
			layout = {
				preset = "select",
				preview = false,
				-- Fit the list to the rows instead of the preset 40% of the screen.
				config = function(layout)
					local rows = math.max(1, math.min(#items, math.floor(vim.o.lines * 0.6)))
					for _, box in ipairs(layout.layout) do
						if box.win == "list" then
							box.height = rows
						end
					end
					-- input line + its bottom border + the rows + the outer border
					layout.layout.height = rows + 4
					layout.layout.min_height = nil
				end,
			},
			confirm = function(picker, item)
				picker:close()
				if item then
					vim.schedule(function()
						on_choice(item.value)
					end)
				end
			end,
		})
		return
	end
	vim.ui.select(items, {
		prompt = title,
		format_item = function(item)
			return item.text
		end,
	}, function(item)
		if item then
			on_choice(item.value)
		end
	end)
end

--- New instance: pick a profile from opts.agents, skipped when there is one.
function M.new()
	local names = vim.tbl_keys(config.options.agents)
	table.sort(names)
	local open = require("crew.workspace").open
	if #names == 1 then
		return open(names[1])
	end
	local items = vim.tbl_map(function(name)
		return { text = name, chunks = { { name, "Function" } }, value = name }
	end, names)
	select("Crew new", items, open)
end

--- Choose an open instance and call on_choice with its slot. The cursor
--- starts on the last visited instance, so Enter means "the usual one".
--- Does nothing when no agent is open.
---@param title string
---@param on_choice fun(slot: integer)
function M.instances(title, on_choice)
	local entries = vim.tbl_filter(function(e)
		return e.slot > 1
	end, require("crew.status").list())
	if #entries == 0 then
		return
	end
	local last, selected = require("crew.workspace").last, nil
	for i, e in ipairs(entries) do
		if e.slot == last then
			selected = i
		end
	end
	local widths = { agent = 1, name = 1 }
	for _, e in ipairs(entries) do
		widths.agent = math.max(widths.agent, vim.fn.strdisplaywidth(e.agent))
		widths.name = math.max(widths.name, vim.fn.strdisplaywidth(e.name or "·"))
	end
	local items = vim.tbl_map(function(e)
		local chunks = M.instance_row(e, widths)
		return { text = plain(chunks), chunks = chunks, value = e.slot }
	end, entries)
	select(title, items, on_choice, selected)
end

--- Jump to an open instance.
function M.pick()
	M.instances("Crew instances", require("crew.workspace").jump)
end

--- Name the current instance. Empty clears it, cancel keeps it.
function M.rename()
	local ws = require("crew.workspace")
	local current = ws.current()
	if not current then
		return
	end
	vim.ui.input({ prompt = ("Name instance %d: "):format(current.slot), default = current.name or "" }, function(name)
		if name ~= nil then
			ws.rename(name, current.slot)
		end
	end)
end

return M
