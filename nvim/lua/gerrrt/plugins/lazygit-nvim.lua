-- ================================================================================================
-- TITLE : lazygit.nvim | lazygit in a floating window, in-editor
-- LINKS : https://github.com/kdheepak/lazygit.nvim
-- ABOUT : You already ship a lazygit config in Core (../lazygit) — this surfaces it on `<leader>gl`
--         in a float, so the full TUI is one keystroke away without leaving Neovim. Complements,
--         doesn't duplicate: gitsigns = gutter, fugitive = `:Git` commands, diffview = review,
--         lazygit = the fast interactive staging/branching TUI.
-- LAZY  : cmd + keys. Requires the `lazygit` binary on PATH (it's part of your Core toolchain).
-- NOTE  : floating-window border inherits your global `winborder = "rounded"` (options.lua).
-- ================================================================================================
return {
	"kdheepak/lazygit.nvim",
	dependencies = { "nvim-lua/plenary.nvim" },
	cmd = { "LazyGit", "LazyGitConfig", "LazyGitCurrentFile", "LazyGitFilter", "LazyGitFilterCurrentFile" },
	keys = {
		{ "<leader>gl", "<cmd>LazyGit<cr>", desc = "LazyGit (float)" },
	},
	init = function()
		vim.g.lazygit_floating_window_scaling_factor = 0.9
		vim.g.lazygit_use_neovim_remote = 0
	end,
}
