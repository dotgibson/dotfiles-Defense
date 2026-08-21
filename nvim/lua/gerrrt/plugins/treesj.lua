-- ================================================================================================
-- TITLE : treesj | split & join code blocks along treesitter nodes
-- LINKS : https://github.com/Wansmer/treesj
-- ABOUT : Toggle a node between one-line and multi-line form — collapse/expand a function's args,
--         a table/object/array, a JSX tag, a Rust struct, an import list — and it reflows correctly
--         per language because it walks the treesitter tree, not characters. A daily ergonomic win
--         across every language you touch. Complements mini.move (move lines) and mini.ai/textobjects
--         (select nodes); treesj reshapes them.
-- LAZY  : cmd + a single `<leader>j` toggle. `use_default_keymaps = false` so it claims no keys
--         beyond the one you see here (its default `<leader>m`/`gJ`/`gS` would collide with native
--         gJ and flash's `S`).
-- ================================================================================================
return {
	"Wansmer/treesj",
	dependencies = { "nvim-treesitter/nvim-treesitter" },
	cmd = { "TSJToggle", "TSJSplit", "TSJJoin" },
	keys = {
		{ "<leader>j", "<cmd>TSJToggle<cr>", desc = "Toggle split/join block" },
	},
	opts = {
		use_default_keymaps = false,
		max_join_length = 150,
	},
}
