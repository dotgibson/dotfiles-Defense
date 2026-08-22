-- ================================================================================================
-- TITLE : vim-tmux-navigator | seamless nvim split <-> tmux pane navigation
-- LINKS : https://github.com/christoomey/vim-tmux-navigator
-- NOTE  : Provides <C-h/j/k/l> out of the box (it crosses into tmux panes too). These were
--         previously also mapped manually in keymaps.lua — that duplicate is now removed.
-- ================================================================================================
return {
	"christoomey/vim-tmux-navigator",
	cmd = {
		"TmuxNavigateLeft",
		"TmuxNavigateDown",
		"TmuxNavigateUp",
		"TmuxNavigateRight",
		"TmuxNavigatePrevious",
	},
	keys = {
		{ "<C-h>", "<cmd>TmuxNavigateLeft<cr>", desc = "Window/pane left" },
		{ "<C-j>", "<cmd>TmuxNavigateDown<cr>", desc = "Window/pane down" },
		{ "<C-k>", "<cmd>TmuxNavigateUp<cr>", desc = "Window/pane up" },
		{ "<C-l>", "<cmd>TmuxNavigateRight<cr>", desc = "Window/pane right" },
	},
}
