return {
	filetypes = {
		"html",
		"typescript",
		"javascript",
		"javascriptreact",
		"typescriptreact",
		"css",
		"sass",
		"scss",
		"svelte",
		"vue",
	},
	-- Native vim.lsp.config uses `root_markers` (a list), not the old lspconfig
	-- `root_dir = function(fname)` form, which native LSP ignores (it expects
	-- fun(bufnr, on_dir) and would never start the server otherwise).
	root_markers = { "package.json", ".git" },
}
