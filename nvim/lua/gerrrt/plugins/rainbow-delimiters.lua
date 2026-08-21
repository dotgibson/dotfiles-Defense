-- ================================================================================================
-- TITLE : rainbow-delimiters.nvim | colour-paired brackets/parens via treesitter
-- LINKS : https://github.com/HiPhish/rainbow-delimiters.nvim
-- ABOUT : Colours matching (), [], {} (and language-specific pairs) by nesting depth so deeply
--         nested code — Lisp-y Lua tables, JSX, Solidity, nested generics — is readable at a
--         glance. Treesitter-driven (so it tracks real syntax, not naive char matching) using the
--         parsers you already install. Complements mini.pairs (which inserts) and the native
--         showmatch/matchparen you have on.
-- LAZY  : event = BufReadPost/BufNewFile, same trigger as treesitter itself.
-- NOTE  : Uses `config` rather than `opts` because the setup function lives in the
--         `rainbow-delimiters.setup` SUBMODULE. lazy.nvim's `opts` would call
--         `require("rainbow-delimiters").setup(opts)` (the top-level module), which has no such
--         function — so the config table has to be passed explicitly via `config`.
-- ================================================================================================
return {
	"HiPhish/rainbow-delimiters.nvim",
	event = { "BufReadPost", "BufNewFile" },
	config = function()
		require("rainbow-delimiters.setup").setup({
			strategy = {
				[""] = require("rainbow-delimiters").strategy["global"],
			},
			query = {
				[""] = "rainbow-delimiters",
				lua = "rainbow-blocks", -- also colour do/end, if/end blocks in Lua
			},
		})
	end,
}
