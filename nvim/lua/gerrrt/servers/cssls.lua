-- ================================================================================================
-- TITLE : cssls (vscode-css-language-server) LSP Setup
-- LINKS : https://github.com/hrsh7th/vscode-langservers-extracted
-- ABOUT : Validation, hover and completion for CSS/SCSS/LESS. Complements your existing front-end
--         trio without overlap: tailwindcss = utility-class IntelliSense, emmet_ls = abbreviation
--         expansion, ccc.nvim = colour picker/preview — none of them validate raw stylesheets.
-- NOTE  : the built-in linter is set to "warning" for unknown at-rules so Tailwind's @tailwind /
--         @apply directives don't spam errors in projects that use them.
-- INSTALL: mason — package name "css-lsp" (added to ensure_installed in plugins/mason-tool-installer.lua).
-- ================================================================================================
local lint = { validate = true, lint = { unknownAtRules = "warning" } }

return {
	-- css-lsp ships snippet completions; advertise the client capability so they come through.
	-- Only the LEAF is set — vim.lsp.config deep-merges this over the "*" wildcard capabilities
	-- installed in servers/init.lua, so everything else is inherited. See servers/html.lua.
	capabilities = {
		textDocument = { completion = { completionItem = { snippetSupport = true } } },
	},
	cmd = { "vscode-css-language-server", "--stdio" },
	filetypes = { "css", "scss", "less" },
	root_markers = { "package.json", ".git" },
	settings = { css = lint, scss = lint, less = lint },
}
