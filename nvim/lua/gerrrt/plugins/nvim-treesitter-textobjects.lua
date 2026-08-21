-- ================================================================================================
-- TITLE : nvim-treesitter-textobjects (main branch) | syntax-aware MOTIONS
-- LINKS : https://github.com/nvim-treesitter/nvim-treesitter-textobjects
-- ABOUT : Jump to the next/previous function or argument across any language with a parser, reading
--         the same treesitter trees you already parse (nvim-treesitter.lua) — no extra parsing cost.
-- SCOPE : MOTIONS ONLY, on purpose. mini.ai (plugins/mini-nvim.lua) owns the `a`/`i` text-object
--         operators and already provides `af`/`if` (a function *call*) and `aa`/`ia` (an argument).
--         Binding standalone `af`/`ac`/`aa` here would (1) make every bare `a`/`i` wait out
--         `timeoutlen` to disambiguate — the exact latency the repo removed by moving surround off
--         `s` — and (2) shadow mini.ai's own objects. So selection stays with mini.ai; this module
--         contributes only the cursor MOTIONS mini.ai doesn't have. Treesitter *selection* for
--         classes (`ac`/`ic`) and blocks/conditionals/loops (`ao`/`io`) IS wired — but through
--         mini.ai's single `a`/`i` dispatcher (custom_textobjects in mini-nvim.lua), which adds no
--         latency, rather than as standalone maps here.
-- BRANCH: `main` to match your nvim-treesitter `main` spec (mixing main + master breaks queries).
-- KEYMAPS: `]f`/`[f` (function) and `]a`/`[a` (argument) — chosen to avoid `]c`/`[c`
--          (treesitter-context jump + diff change motions) and `]m`/`[m`.
-- ================================================================================================
return {
	"nvim-treesitter/nvim-treesitter-textobjects",
	branch = "main",
	dependencies = { "nvim-treesitter/nvim-treesitter" },
	event = { "BufReadPost", "BufNewFile" },
	config = function()
		require("nvim-treesitter-textobjects").setup({})

		local move = require("nvim-treesitter-textobjects.move")
		vim.keymap.set({ "n", "x", "o" }, "]f", function()
			move.goto_next_start("@function.outer", "textobjects")
		end, { desc = "Next function start" })
		vim.keymap.set({ "n", "x", "o" }, "[f", function()
			move.goto_previous_start("@function.outer", "textobjects")
		end, { desc = "Prev function start" })
		vim.keymap.set({ "n", "x", "o" }, "]a", function()
			move.goto_next_start("@parameter.inner", "textobjects")
		end, { desc = "Next argument" })
		vim.keymap.set({ "n", "x", "o" }, "[a", function()
			move.goto_previous_start("@parameter.inner", "textobjects")
		end, { desc = "Prev argument" })
	end,
}
