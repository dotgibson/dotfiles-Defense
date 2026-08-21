-- ================================================================================================
-- TITLE : oil.nvim | edit the filesystem like a normal buffer
-- LINKS : https://github.com/stevearc/oil.nvim
-- ABOUT : A different tool than nvim-tree, not a replacement. nvim-tree is the persistent project
--         sidebar (<leader>e); oil opens the CURRENT directory AS A BUFFER on `-`, so you create/
--         rename/move/delete files by editing lines and `:w`. Renaming five files is `:%s/.../`,
--         and parent navigation is just `-` again. Many people keep both for exactly this split.
-- LAZY  : `-` keymap loads it on demand. `lazy = false` is the upstream recommendation only if you
--         want oil to hijack directory buffers; we DON'T — nvim-tree already owns `nvim <dir>` via
--         hijack_netrw (nvim-tree.lua) — so oil is purely on-demand and leaves that path alone.
-- ================================================================================================
return {
	"stevearc/oil.nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	cmd = "Oil",
	keys = {
		{ "-", "<cmd>Oil<cr>", desc = "Open parent dir (oil)" },
	},
	opts = {
		default_file_explorer = false, -- nvim-tree keeps the netrw-hijack role
		delete_to_trash = true,
		view_options = { show_hidden = true },
		float = { padding = 4 }, -- (only used if you call require('oil').open_float())
		keymaps = {
			["q"] = "actions.close",
			["<C-h>"] = false, -- leave <C-h> to vim-tmux-navigator
			["<C-l>"] = false, -- leave <C-l> to vim-tmux-navigator
		},
	},
}
