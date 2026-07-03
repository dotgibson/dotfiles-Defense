-- ================================================================================================
-- TITLE : which-key | shows your keybindings as you type the leader
-- LINKS : https://github.com/folke/which-key.nvim
-- ================================================================================================
return {
	"folke/which-key.nvim",
	event = "VeryLazy",
	opts = {
		spec = {
			{ "<leader>b", group = "buffer" },
			{ "<leader>c", group = "code / LSP" },
			{ "<leader>d", group = "debug (DAP)" },
			{ "<leader>f", group = "find (fzf)" },
			{ "<leader>g", group = "git" },
			{ "<leader>gx", group = "git conflict" },
			{ "<leader>h", group = "harpoon" },
			{ "<leader>n", group = "npm (package.json)" },
			{ "<leader>q", group = "session" },
			{ "<leader>s", group = "split / window" },
			{ "<leader>S", group = "search & replace" },
			{ "<leader>t", group = "test (neotest)" },
			{ "<leader>u", group = "ui / toggles" },
			{ "<leader>w", group = "which-key" },
			{ "<leader>x", group = "trouble / lists" },
			{ "<leader><tab>", group = "tabs" },
			-- non-leader: mini.surround moved here off `s` so flash owns `s` (see mini-nvim.lua)
			{ "gs", group = "surround", mode = { "n", "x" } },
		},
	},
	keys = {
		-- `<leader>?` now opens the full cheatsheet (config/keymaps.lua) — the whole map, not the
		-- live prompt. which-key's buffer-local-keys popup moves to `<leader>wk` so both survive.
		{
			"<leader>wk",
			function()
				require("which-key").show({ global = false })
			end,
			desc = "Buffer Local Keymaps (which-key)",
		},
	},
}
