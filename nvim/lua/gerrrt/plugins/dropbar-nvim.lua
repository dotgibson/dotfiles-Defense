-- ================================================================================================
-- TITLE : dropbar.nvim | IDE-style breadcrumbs in the winbar
-- LINKS : https://github.com/Bekaboo/dropbar.nvim
-- ABOUT : The breadcrumb trail you asked for — a winbar at the top of each window showing
--         path › symbol › symbol for where the cursor sits. Pure Neovim 0.10+ (no extra UI libs);
--         it sources from the LSP document-symbols you already get on attach, falling back to
--         treesitter, so it needs nothing new. `<leader>;` opens an interactive, fuzzy-pickable
--         dropdown of the trail (jump straight to a sibling symbol).
-- LAZY  : event = BufReadPost/BufNewFile. Plays nicely with bufferline (top tabline) +
--         treesitter-context (sticky scope) — winbar is a distinct line below the tabline.
-- NOTE  : Honors your global transparency/theme automatically. No tofu glyphs are introduced
--         here; dropbar uses its own kind icons which require the Nerd Font you already run.
-- ================================================================================================
return {
	"Bekaboo/dropbar.nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	event = { "BufReadPost", "BufNewFile" },
	keys = {
		{
			"<leader>;",
			function()
				require("dropbar.api").pick()
			end,
			desc = "Breadcrumb pick (dropbar)",
		},
	},
	opts = {
		bar = {
			-- don't draw the winbar in special/utility buffers (tree, trouble, dap, help, etc.)
			enable = function(buf, win, _)
				if vim.bo[buf].buftype ~= "" or vim.fn.win_gettype(win) ~= "" then
					return false
				end
				local ft = vim.bo[buf].filetype
				local skip = { NvimTree = true, help = true }
				return not skip[ft]
			end,
		},
	},
}
