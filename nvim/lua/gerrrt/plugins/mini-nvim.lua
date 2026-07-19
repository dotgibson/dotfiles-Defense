-- ================================================================================================
-- TITLE : mini.nvim modules | small, focused editing upgrades
-- LINKS : https://github.com/echasnovski/mini.nvim
-- NOTE  : Removed mini.comment (Neovim ships native gc/gcc since 0.10).
--         Consolidated from separate per-module specs into a single spec so lazy.nvim only
--         tracks one plugin entry and runtime/lockfile overhead is minimized.
--         mini.move owns <A-h/j/k/l> line moving; mini.bufremove backs <leader>bd.
-- ================================================================================================
return {
	"echasnovski/mini.nvim",
	version = "*",
	-- nvim-treesitter-textobjects ships the `textobjects` queries that mini.ai.gen_spec.treesitter
	-- reads (see the mini.ai setup below). Declared here so those queries are guaranteed on the
	-- runtimepath before mini.ai resolves them. The plugin's own spec (motions) is unchanged; lazy
	-- merges the two entries by name.
	dependencies = { "nvim-treesitter/nvim-treesitter-textobjects" },
	-- Deferred off the startup critical path: none of these modules are needed before the
	-- first UI paint. mini.notify only has to replace vim.notify before the first toast, and
	-- mini.trailspace.trim() only runs in the BufWritePre autocmd (config/autocmds.lua) — both
	-- fire well after VeryLazy. ai/move/surround/pairs are ready before you can edit a buffer.
	event = "VeryLazy",
	config = function()
		local ai = require("mini.ai")

		-- Treesitter selection routed THROUGH mini.ai's single a/i dispatcher, so it adds ZERO
		-- latency (a/i already wait for an object char — adding object keys can't make `a` ambiguous
		-- the way a standalone `ac` map would; that's why the textobjects plugin stays motions-only).
		-- PURELY ADDITIVE: mini.ai's built-in `f` (function *call*) and `a` (argument) are left as-is.
		-- We add the objects mini.ai lacks: `c` = class, `o` = block / conditional / loop.
		-- Prefer `f` to mean the function *definition*? add an `f = ai.gen_spec.treesitter(...)` entry.
		-- Guarded only against `ai.gen_spec.treesitter` itself being ABSENT (e.g. an older mini.ai):
		-- the pcall wraps spec *construction*, which just validates the capture format and returns a
		-- closure — it does NOT resolve queries. A missing/uninstalled parser or `textobjects` query
		-- is handled lazily by mini.ai at textobject-use time (`ac`/`ao`), not here. On the absent
		-- case we fall back to mini.ai defaults rather than breaking setup.
		local custom_textobjects
		local ok, ts = pcall(function()
			return {
				c = ai.gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }),
				o = ai.gen_spec.treesitter({
					a = { "@block.outer", "@conditional.outer", "@loop.outer" },
					i = { "@block.inner", "@conditional.inner", "@loop.inner" },
				}),
			}
		end)
		if ok then
			custom_textobjects = ts
		end

		ai.setup({ custom_textobjects = custom_textobjects })
		require("mini.move").setup({})
		-- mini.surround on the `gs` prefix (gsa/gsd/gsr/gsf/gsF/gsh/gsn) instead of the default
		-- `s*`. flash.nvim owns `s` (jump); with surround also living on `s*`, every `s` press had
		-- to wait out `timeoutlen` (500ms) to disambiguate `s` from `sa`/`sd`/`sr`/... Moving
		-- surround to `gs` frees `s` to fire flash instantly. (`gs` only shadows the near-useless
		-- `:sleep` default — swap to a `gz` prefix if you ever want plain `gs` back.)
		require("mini.surround").setup({
			mappings = {
				add = "gsa", -- add surround (normal: gsaiw" ; visual: select then gsa")
				delete = "gsd", -- delete surround (gsd")
				replace = "gsr", -- replace surround (gsr"' )
				find = "gsf", -- find surround to the right
				find_left = "gsF", -- find surround to the left
				highlight = "gsh", -- highlight surround
				update_n_lines = "gsn", -- update n_lines used for search
			},
		})
		require("mini.cursorword").setup({})
		require("mini.indentscope").setup({})
		require("mini.pairs").setup({})
		require("mini.trailspace").setup({})
		require("mini.bufremove").setup({})
		require("mini.notify").setup({})
		-- setup() alone does NOT replace vim.notify — without this line mini.notify is configured
		-- but unused, and vim.notify(...) calls (e.g. harpoon's "added" toast) still hit Neovim's
		-- built-in notifier. make_notify() returns a drop-in replacement. fidget.nvim is also
		-- installed (plugins/fidget-nvim.lua) but only renders LSP *progress* — it is not a
		-- vim.notify backend, so the two don't clash; this owns vim.notify, fidget owns $/progress.
		vim.notify = require("mini.notify").make_notify()
	end,
}
