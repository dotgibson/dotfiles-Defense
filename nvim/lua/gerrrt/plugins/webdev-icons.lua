-- nvim-web-devicons | filetype glyphs shared by fzf-lua, bufferline, nvim-tree, lualine.
-- lazy = true so it isn't sourced at startup on its own — it loads when one of those
-- plugins pulls it in as a dependency (which is the only time it's actually needed).
return {
	"nvim-tree/nvim-web-devicons",
	lazy = true,
	opts = {},
}
