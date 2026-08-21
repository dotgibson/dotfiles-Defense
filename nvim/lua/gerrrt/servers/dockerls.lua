return {
	filetypes = { "dockerfile" },
	cmd = { "docker-langserver", "--stdio" },
	-- Native `root_markers` instead of the legacy `require("lspconfig").util.root_pattern`.
	-- root_pattern returns an fname-style function that native vim.lsp.config does not
	-- understand (it expects fun(bufnr, on_dir)), so the server never attached. This also
	-- drops the hard dependency on lspconfig's internal `util` module.
	root_markers = { "Dockerfile", ".git" },
}
