-- ================================================================================================
-- TITLE : fzf-lua | fuzzy finder (NvChad-styled layout)
-- LINKS : https://github.com/ibhagwan/fzf-lua
-- NOTE  : LSP-specific pickers (definitions/refs/symbols) live in utils/lsp.lua on_attach,
--         so they're buffer-local and only active when a server is attached. This file
--         keeps the general finders.
-- NVCHAD: NvChad ships its finder look via TELESCOPE, but you run fzf-lua — so the `opts` below
--         TRANSLATE NvChad's telescope config into fzf-lua's own terms rather than adopting
--         telescope. Mirrored 1:1 from nvchad/configs/telescope.lua:
--           width 0.87 · height 0.80 · preview on the RIGHT at 55% · prompt on TOP
--           prompt-prefix "   " (f002 magnifier) · selection caret " " (f0da)
--         Rounded borders + the FzfLua* highlight groups (see utils/ui-highlights.lua) finish
--         the minimal, border-tinted NvChad look. Border chars come from `border = "rounded"`.
-- ================================================================================================
return {
	"ibhagwan/fzf-lua",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	cmd = "FzfLua",
	keys = {
		{
			"<leader>ff",
			function()
				require("fzf-lua").files()
			end,
			desc = "FZF Files",
		},
		{
			"<leader>fg",
			function()
				require("fzf-lua").live_grep()
			end,
			desc = "FZF Live Grep",
		},
		{
			"<leader>fb",
			function()
				require("fzf-lua").buffers()
			end,
			desc = "FZF Buffers",
		},
		{
			"<leader>fh",
			function()
				require("fzf-lua").help_tags()
			end,
			desc = "FZF Help Tags",
		},
		{
			"<leader>fr",
			function()
				require("fzf-lua").oldfiles()
			end,
			desc = "FZF Recent Files",
		},
		{
			"<leader>fk",
			function()
				require("fzf-lua").keymaps()
			end,
			desc = "FZF Keymaps",
		},
		{
			"<leader>fx",
			function()
				require("fzf-lua").diagnostics_document()
			end,
			desc = "FZF Diagnostics (doc)",
		},
		{
			"<leader>fX",
			function()
				require("fzf-lua").diagnostics_workspace()
			end,
			desc = "FZF Diagnostics (workspace)",
		},
	},
	opts = {
		-- Window geometry — NvChad's telescope layout, in fzf-lua terms.
		winopts = {
			height = 0.80, -- NvChad layout_config.height
			width = 0.87, -- NvChad layout_config.width
			row = 0.35, -- centered-ish, matching telescope's default vertical anchor
			col = 0.50,
			border = "rounded", -- the minimal rounded frame (border chars = ╭ ╮ ╰ ╯ ─ │)
			preview = {
				border = "rounded",
				layout = "horizontal",
				horizontal = "right:55%", -- NvChad preview_width = 0.55, on the right
				title = true,
				title_pos = "center",
				scrollbar = "float",
			},
		},
		-- fzf CLI flags that reproduce NvChad's prompt/caret placement.
		fzf_opts = {
			["--layout"] = "reverse", -- prompt on TOP (NvChad prompt_position = "top")
			["--info"] = "inline-right",
			["--prompt"] = "\u{f002}  ", -- f002 nf-fa-search — NvChad's prompt_prefix
			["--pointer"] = "\u{f0da}", -- f0da nf-fa-caret_right — NvChad's selection_caret
			["--marker"] = "\u{f0da}", -- multi-select marker, same caret for consistency
		},
		-- Inherit tokyonight's palette; the FzfLua* groups in utils/ui-highlights.lua then tint
		-- borders/titles for the minimal NvChad look.
		fzf_colors = true,
		-- Telescope-familiar preview scrolling without leaving the finder.
		keymap = {
			builtin = {
				["<C-d>"] = "preview-page-down",
				["<C-u>"] = "preview-page-up",
			},
		},
	},
}
