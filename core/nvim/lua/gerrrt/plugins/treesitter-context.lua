-- ================================================================================================
-- TITLE : nvim-treesitter-context | sticky context header (function/class you're inside)
-- LINKS : https://github.com/nvim-treesitter/nvim-treesitter-context
-- ABOUT : Pins the enclosing scope (the def/if/for you're currently inside) to the top of the
--         window as you scroll past it — the lightweight, in-window cousin of breadcrumbs. Reads
--         from the treesitter trees you already parse (nvim-treesitter.lua), so it "just works"
--         for every language with a parser and adds no parsing cost of its own.
-- LAZY  : event = BufReadPost/BufNewFile (matches treesitter's own trigger). `[c` jumps UP to the
--         context line — chosen because hlsearch is off and you navigate diffs via ]h/[h, so the
--         native ]c/[c change-motions are free outside diff buffers.
-- ================================================================================================
return {
	"nvim-treesitter/nvim-treesitter-context",
	event = { "BufReadPost", "BufNewFile" },
	keys = {
		{
			"[c",
			function()
				require("treesitter-context").go_to_context(vim.v.count1)
			end,
			desc = "Jump to context (upwards)",
		},
	},
	opts = {
		max_lines = 3, -- cap the header so it never eats the viewport
		multiline_threshold = 1, -- collapse multiline signatures to a single line
		trim_scope = "outer",
		mode = "cursor",
		-- No `separator = nil` line: assigning nil in a table literal simply omits the key, and
		-- nil is already the default (nvim-treesitter-context/lua/treesitter-context/config.lua:44)
		-- — it read as a deliberate setting but did nothing. Set it to a string to draw a rule
		-- under the context (which also makes it require 2+ lines above the cursorline).
	},
}
