-- Highlight groups for the pills. They are links with default = true, so
-- they follow any colorscheme and a user :hi or nvim_set_hl always wins.
local M = {}

M.groups = {
	CrewPill = "TabLine",
	CrewPillCurrent = "TabLineSel",
	CrewPillWork = "DiagnosticInfo",
	CrewPillAsk = "DiagnosticWarn",
	CrewPillAskBlink = "IncSearch", -- second phase of the ask blink
	CrewPillDone = "DiagnosticOk",
	CrewHeader = "Title", -- slot and profile in the agent tab header
	CrewHeaderName = "Normal",
}

function M.setup()
	for name, link in pairs(M.groups) do
		vim.api.nvim_set_hl(0, name, { link = link, default = true })
	end
end

return M
