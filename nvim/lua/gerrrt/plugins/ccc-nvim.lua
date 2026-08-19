-- ================================================================================================
-- TITLE : ccc.nvim  | colour PICKER (:CccPick / :CccConvert)
-- LINKS : https://github.com/uga-rosa/ccc.nvim
-- NOTE  : ccc's always-on highlighter is intentionally OFF here (auto_enable = false). The inline
--         colour swatches / LSP document colours are now rendered by plugins/nvim-colorizer.lua
--         (colorify-style, visible-range) so the two don't double-render. ccc stays for the
--         interactive picker + format conversion, which nvim-colorizer doesn't provide.
-- ================================================================================================
return {
	"uga-rosa/ccc.nvim",
	cmd = { "CccPick", "CccConvert", "CccHighlighterToggle" },
	config = function()
		require("ccc").setup({
			highlighter = { auto_enable = false, lsp = true }, -- picker-only; highlighting → nvim-colorizer
			highlight_mode = "virtual",
		})
	end,
}
