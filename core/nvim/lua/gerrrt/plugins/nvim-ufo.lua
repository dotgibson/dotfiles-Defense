-- ================================================================================================
-- TITLE : nvim-ufo | modern folding with inline previews
-- LINKS : https://github.com/kevinhwang91/nvim-ufo
-- ABOUT : Turns Neovim's folds into something you actually use: a fold shows a preview of its
--         contents, `zR`/`zM` open/close all with proper restore, and `zK` peeks the folded lines
--         under the cursor in a popup (falling back to LSP hover when there's no fold). Uses the
--         treesitter parsers you already install, with an indent fallback for parserless filetypes.
-- INTERPLAY: UFO is the SOLE fold owner. options.lua sets only foldlevel=99 (folds open on open) and
--         NO LONGER sets foldmethod=expr / a global treesitter foldexpr — UFO computes folds through
--         its own providers below, so that global foldexpr was redundant per-buffer work (UFO never
--         reads 'foldexpr'). We re-assert foldlevel/foldlevelstart=99 here (UFO requirement). To fall
--         back to plain folding, remove this file AND restore foldmethod=expr +
--         foldexpr=v:lua.vim.treesitter.foldexpr() in options.lua.
-- ================================================================================================
return {
	"kevinhwang91/nvim-ufo",
	dependencies = { "kevinhwang91/promise-async" },
	event = { "BufReadPost", "BufNewFile" },
	init = function()
		-- UFO needs folds to start open; these mirror your options.lua intent.
		vim.o.foldlevel = 99
		vim.o.foldlevelstart = 99
		vim.o.foldenable = true
	end,
	opts = {
		-- treesitter first (real syntax folds), indent fallback for filetypes without a parser.
		provider_selector = function()
			return { "treesitter", "indent" }
		end,
	},
	keys = {
		{
			"zR",
			function()
				require("ufo").openAllFolds()
			end,
			desc = "Open all folds",
		},
		{
			"zM",
			function()
				require("ufo").closeAllFolds()
			end,
			desc = "Close all folds",
		},
		{
			"zK",
			function()
				local winid = require("ufo").peekFoldedLinesUnderCursor()
				if not winid then
					vim.lsp.buf.hover()
				end
			end,
			desc = "Peek fold / hover",
		},
	},
}
