-- ================================================================================================
-- TITLE : html (vscode-html-language-server) LSP Setup
-- LINKS : https://github.com/hrsh7th/vscode-langservers-extracted
-- ABOUT : Real HTML validation, hover, and tag/attribute completion. This is distinct from
--         emmet_ls (servers/emmet_ls.lua), which only EXPANDS abbreviations (div.foo<Tab>) — it
--         has no diagnostics or document model. Both attach to HTML happily; emmet does shorthand,
--         html-lsp does correctness. snippetSupport is advertised so blink.cmp gets snippet items.
-- INSTALL: mason — package name "html-lsp" (added to ensure_installed in plugins/conform.lua).
-- ================================================================================================
return function(capabilities)
	-- html-lsp ships snippet completions; advertise the client capability so they come through.
	local caps = require("gerrrt.utils.lsp").with_snippets(capabilities)

	vim.lsp.config("html", {
		capabilities = caps,
		cmd = { "vscode-html-language-server", "--stdio" },
		filetypes = { "html" },
		root_markers = { "package.json", ".git" },
	})
end
