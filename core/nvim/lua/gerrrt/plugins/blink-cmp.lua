-- ================================================================================================
-- TITLE : blink.cmp | completion (replaces nvim-cmp)
-- LINKS : https://github.com/saghen/blink.cmp
-- ABOUT : Performant, batteries-included completion. ~0.5–4ms/keystroke vs nvim-cmp's 60ms default
--         debounce, with a built-in Rust fuzzy matcher (typo-resistant, frecency + proximity).
--         Core sources (lsp/path/snippets/buffer) are built in — no cmp-* companion plugins.
-- MIGRATION NOTES (delete plugins/nvim-cmp.lua when adopting this):
--   • capabilities now come from blink — see servers/init.lua (get_lsp_capabilities) and the
--     dropped cmp-nvim-lsp dependency in plugins/nvim-lspconfig.lua.
--   • snippets: LuaSnip preset (your friendly-snippets carry over).
--   • lazydev: wired as a source with a high score_offset, same role as the old cmp group_index 0.
-- VERSION: pinned to v1 — blink V2 is in active development with breaking changes.
-- KEYMAPS: kept identical to your nvim-cmp setup (C-j/C-k move, C-b/C-f docs, C-Space, C-e, CR).
-- ================================================================================================
return {
	"saghen/blink.cmp",
	version = "1.*", -- prebuilt Rust fuzzy binary ships with tagged releases
	event = "InsertEnter",
	dependencies = {
		"rafamadriz/friendly-snippets",
		-- install_jsregexp needs make + a C toolchain, absent on stock Windows; skip the build there.
		-- LuaSnip degrades gracefully without jsregexp (only regex-transform snippets are affected).
		{ "L3MON4D3/LuaSnip", version = "v2.*", build = vim.fn.has("win32") == 0 and "make install_jsregexp" or nil },
	},
	---@module 'blink.cmp'
	---@type blink.cmp.Config
	opts = {
		snippets = { preset = "luasnip" },

		keymap = {
			preset = "none", -- define everything explicitly to match the old cmp maps
			["<C-k>"] = { "select_prev", "fallback" },
			["<C-j>"] = { "select_next", "fallback" },
			["<C-b>"] = { "scroll_documentation_up", "fallback" },
			["<C-f>"] = { "scroll_documentation_down", "fallback" },
			["<C-Space>"] = { "show", "show_documentation", "hide_documentation" },
			["<C-e>"] = { "hide", "fallback" },
			["<CR>"] = { "accept", "fallback" },
			-- snippet jumps (blink uses the native vim.snippet engine under luasnip preset)
			["<Tab>"] = { "snippet_forward", "fallback" },
			["<S-Tab>"] = { "snippet_backward", "fallback" },
		},

		appearance = {
			-- "mono" = use the Nerd Font Mono kind icons (crisp alignment). blink ships its own
			-- lspkind-style glyphs, so onsails/lspkind is no longer a dependency.
			nerd_font_variant = "mono",
		},

		completion = {
			list = {
				-- Match your old `confirm({ select = false })` feel: nothing is preselected, so a
				-- bare <CR> inserts a newline unless you explicitly selected an item.
				selection = { preselect = false, auto_insert = true },
			},
			menu = {
				border = "rounded",
				-- NvChad-style menu draw: a colored kind ICON on the left (colors via BlinkCmpKind*
				-- in utils/ui-highlights.lua), the label in the middle, and the kind TEXT trailing on
				-- the right — the same three-column rhythm as NvChad's cmp. treesitter still syntax-
				-- highlights the LSP label text so identifiers read like code.
				draw = {
					treesitter = { "lsp" },
					columns = {
						{ "kind_icon" },
						{ "label", "label_description", gap = 1 },
						{ "kind", gap = 1 },
					},
				},
			},
			documentation = { auto_show = true, auto_show_delay_ms = 200, window = { border = "rounded" } },
			ghost_text = { enabled = true },
		},

		signature = { enabled = true, window = { border = "rounded" } }, -- replaces cmp-nvim-lsp-signature-help

		sources = {
			default = { "lsp", "path", "snippets", "buffer", "lazydev" },
			providers = {
				-- lazydev: Neovim lua API + require-path completion when editing your config.
				-- High score_offset so it supersedes the LuaLS source for those (the v1 analog of
				-- the old nvim-cmp group_index = 0).
				lazydev = { name = "LazyDev", module = "lazydev.integrations.blink", score_offset = 100 },
			},
		},

		fuzzy = { implementation = "prefer_rust_with_warning" },
	},
	opts_extend = { "sources.default" },
}
