-- ================================================================================================
-- TITLE : persistence.nvim | automatic per-directory session save/restore
-- LINKS : https://github.com/folke/persistence.nvim
-- ABOUT : Saves a session (open buffers, window layout, tabpages, cwd) per project directory on
--         exit and lets you restore it. Pairs with harpoon: harpoon pins your hot files, this
--         brings the whole workspace back exactly as you left it. Lightweight — one autocmd,
--         native `:mksession` under the hood.
-- LAZY  : event = BufReadPre so a session is only tracked once you actually open a file (it won't
--         engage on the dashboard / `nvim` with no args). Restore keys live under a new `<leader>q`
--         (session) group.
-- KEYS  : qs restore (this dir) · ql restore last · qd stop saving for this session
-- ================================================================================================
return {
	"folke/persistence.nvim",
	event = "BufReadPre",
	keys = {
		{
			"<leader>qs",
			function()
				require("persistence").load()
			end,
			desc = "Restore session (this dir)",
		},
		{
			"<leader>ql",
			function()
				require("persistence").load({ last = true })
			end,
			desc = "Restore last session",
		},
		{
			"<leader>qd",
			function()
				require("persistence").stop()
			end,
			desc = "Don't save current session",
		},
	},
	opts = {},
}
