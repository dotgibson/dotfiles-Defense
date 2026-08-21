-- ================================================================================================
-- TITLE : diffview.nvim | full-window git diff, merge-resolution & file history
-- LINKS : https://github.com/sindrets/diffview.nvim
-- ABOUT : The piece your git stack was missing. gitsigns owns the gutter/hunks and fugitive owns
--         arbitrary `:Git` commands — diffview is the review surface: a side-by-side diff of the
--         whole change set, a 3-way merge-conflict resolver, and a browsable file/branch history.
--         Sits cleanly under your existing `<leader>g` (git) group.
-- LAZY  : cmd + keys only, so it loads the first time you open a review. Closes via its own
--         keymap so it can lazy-load without a startup cost.
-- KEYS  : gv open · gV close · gH file history (current file) · gL branch/repo log
-- ================================================================================================
return {
	"sindrets/diffview.nvim",
	cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewToggleFiles", "DiffviewFocusFiles" },
	keys = {
		{ "<leader>gv", "<cmd>DiffviewOpen<cr>", desc = "Diffview: open" },
		{ "<leader>gV", "<cmd>DiffviewClose<cr>", desc = "Diffview: close" },
		{ "<leader>gH", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview: file history (this file)" },
		{ "<leader>gL", "<cmd>DiffviewFileHistory<cr>", desc = "Diffview: repo history" },
	},
	opts = {
		enhanced_diff_hl = true,
		view = {
			-- histogram alg + linematch already set globally in options.lua; diffview inherits it.
			merge_tool = { layout = "diff3_mixed" },
		},
	},
}
