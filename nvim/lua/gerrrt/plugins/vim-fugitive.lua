-- ================================================================================================
-- TITLE : vim-fugitive | the premier Git command wrapper
-- LINKS : https://github.com/tpope/vim-fugitive
-- ================================================================================================
return {
	"tpope/vim-fugitive",
	cmd = { "Git", "G", "Gdiffsplit", "Gread", "Gwrite", "Gblame" },
	keys = {
		{ "<leader>gg", "<cmd>Git<cr>", desc = "Git status (fugitive)" },
		{ "<leader>gc", "<cmd>Git commit<cr>", desc = "Git commit" },
		{ "<leader>gP", "<cmd>Git push<cr>", desc = "Git push" },
	},
}
