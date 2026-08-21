-- ================================================================================================
-- TITLE : html (vscode-html-language-server) LSP Setup
-- LINKS : https://github.com/hrsh7th/vscode-langservers-extracted
-- ABOUT : Real HTML validation, hover, and tag/attribute completion. This is distinct from
--         emmet_ls (servers/emmet_ls.lua), which only EXPANDS abbreviations (div.foo<Tab>) — it
--         has no diagnostics or document model. Both attach to HTML happily; emmet does shorthand,
--         html-lsp does correctness. snippetSupport is advertised so blink.cmp gets snippet items.
-- INSTALL: mason — package name "html-lsp" (added to ensure_installed in plugins/mason-tool-installer.lua).
-- ================================================================================================
return {
	-- html-lsp ships snippet completions; advertise the client capability so they come through.
	-- Only the LEAF is set here. vim.lsp.config resolves a server as
	--   tbl_deep_extend("force", config["*"], <lsp/*.lua on rtp>, config["html"])
	-- so this deep-merges ONTO the blink.cmp capabilities installed on the "*" wildcard in
	-- servers/init.lua — the rest of the capability table is inherited, not replaced. This is what
	-- retired utils/lsp.lua's with_snippets(), which had to hand-deepcopy the whole table to add
	-- one boolean without mutating the shared one.
	capabilities = {
		textDocument = { completion = { completionItem = { snippetSupport = true } } },
	},
	cmd = { "vscode-html-language-server", "--stdio" },
	filetypes = { "html" },
	root_markers = { "package.json", ".git" },
}
