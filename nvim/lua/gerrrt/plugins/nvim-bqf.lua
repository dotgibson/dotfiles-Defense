-- ================================================================================================
-- TITLE : nvim-bqf | better quickfix window (preview + fuzzy filter)
-- LINKS : https://github.com/kevinhwang91/nvim-bqf
-- ABOUT : Upgrades the native quickfix list with a live preview pane and in-list fuzzy filtering.
--         Trouble is still your pretty diagnostics/refs viewer; bqf improves the *native* qf that
--         `:grep` (rg, per options.lua), `:make`, fzf-lua's send-to-qf, and `:cdo` all feed into.
--         The two are complementary, not redundant.
-- LAZY  : ft = qf — it only ever needs to exist when a quickfix window is open, so it loads then
--         and never at startup.
-- ================================================================================================
return {
	"kevinhwang91/nvim-bqf",
	ft = "qf",
	opts = {
		auto_resize_height = true,
		preview = {
			winblend = 0, -- match transparent floats
			border = "rounded", -- match global winborder
		},
	},
}
