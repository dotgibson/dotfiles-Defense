-- ================================================================================================
-- TITLE : todo-comments.nvim | highlight & navigate TODO / FIXME / HACK / NOTE / PERF
-- LINKS : https://github.com/folke/todo-comments.nvim
-- ABOUT : Highlights keyword comments across every language (uses ripgrep to search, so it
--         understands your whole tree) and gives you a searchable list. Wires into the tools you
--         already run: `<leader>xt` opens the matches in Trouble (same group as your other lists)
--         and `<leader>ft` searches them with fzf-lua (your find prefix). `]t` / `[t` jump.
-- LAZY  : event = "User FilePost" (same trigger as gitsigns/lint — see config/autocmds.lua) plus
--         cmd/keys, so it costs nothing at startup AND nothing before the first paint. ripgrep is
--         already your grepprg (options.lua), so no new dependency.
-- ICONS : keyword glyphs are written as \u{XXXX} escapes (Nerd Font codepoints) so they survive
--         transfer — raw private-use glyphs get silently stripped. Matches the house convention.
-- ================================================================================================
return {
	"folke/todo-comments.nvim",
	dependencies = { "nvim-lua/plenary.nvim" },
	-- `User FilePost` (config/autocmds.lua). Its highlighter attaches to every buffer in a visible
	-- window on setup, so the triggering buffer gets highlighted without a FileType replay.
	event = "User FilePost",
	cmd = { "TodoTrouble", "TodoFzfLua", "TodoQuickFix", "TodoLocList" },
	keys = {
		{
			"]t",
			function()
				require("todo-comments").jump_next()
			end,
			desc = "Next todo comment",
		},
		{
			"[t",
			function()
				require("todo-comments").jump_prev()
			end,
			desc = "Previous todo comment",
		},
		{ "<leader>xt", "<cmd>TodoTrouble<cr>", desc = "Todo (Trouble)" },
		{ "<leader>xT", "<cmd>TodoTrouble keywords=TODO,FIX,FIXME<cr>", desc = "Todo/Fix/Fixme (Trouble)" },
		{ "<leader>ft", "<cmd>TodoFzfLua<cr>", desc = "FZF Todo comments" },
	},
	opts = {
		signs = true,
		keywords = {
			FIX = { icon = "\u{f188} ", color = "error", alt = { "FIXME", "BUG", "ISSUE" } }, -- f188 bug
			TODO = { icon = "\u{f0ae} ", color = "info" }, -- f0ae tasks
			HACK = { icon = "\u{f06d} ", color = "warning" }, -- f06d fire
			WARN = { icon = "\u{f071} ", color = "warning", alt = { "WARNING", "XXX" } }, -- f071 triangle
			PERF = { icon = "\u{f0e4} ", alt = { "OPTIM", "PERFORMANCE", "OPTIMIZE" } }, -- f0e4 dashboard
			NOTE = { icon = "\u{f249} ", color = "hint", alt = { "INFO" } }, -- f249 sticky note
			TEST = { icon = "\u{f0c3} ", color = "test", alt = { "TESTING", "PASSED", "FAILED" } }, -- f0c3 flask
		},
		-- highlight only the keyword by default; keeps source comments readable in dense files.
		highlight = { keyword = "wide", after = "fg" },
	},
}
