-- ================================================================================================
-- TITLE : gitlinker.nvim | yank / open a permanent link to the line(s) under the cursor
-- LINKS : https://github.com/linrongbin16/gitlinker.nvim
-- ABOUT : Completes your git stack (gitsigns gutter · fugitive `:Git` · diffview review · lazygit
--         TUI) with the one thing they don't do: turn the current line or visual selection into a
--         permalink on the remote host (GitHub/GitLab/Bitbucket/etc., commit-pinned so it never
--         rots) — copy it for a PR/review, or open it straight in the browser. Handy when sharing a
--         finding or a snippet of someone else's code.
-- LAZY  : cmd + keys under your existing `<leader>g` (git) group. `gy` is free under leader (the
--         non-leader `gy` = LSP type-definitions in utils/lsp.lua is untouched).
-- ================================================================================================
return {
	"linrongbin16/gitlinker.nvim",
	cmd = "GitLink",
	opts = {},
	keys = {
		{ "<leader>gy", "<cmd>GitLink<cr>", mode = { "n", "v" }, desc = "Yank git permalink" },
		{ "<leader>gY", "<cmd>GitLink!<cr>", mode = { "n", "v" }, desc = "Open git permalink (browser)" },
	},
}
