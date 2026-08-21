return {
	filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "vue", "svelte" },
	-- Native vim.lsp.config uses `root_markers` (a list). A root_dir FUNCTION here
	-- would need the native fun(bufnr, on_dir) signature and would have to call
	-- on_dir(); the old lspconfig `function(fname) return ... end` form is ignored by
	-- native LSP, so the server silently never attaches.
	root_markers = {
		"tailwind.config.js",
		"tailwind.config.ts",
		"tailwind.config.mjs",
		"postcss.config.js",
		"postcss.config.ts",
	},
}
