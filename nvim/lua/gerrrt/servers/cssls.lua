-- ================================================================================================
-- TITLE : cssls (vscode-css-language-server) LSP Setup
-- LINKS : https://github.com/hrsh7th/vscode-langservers-extracted
-- ABOUT : Validation, hover and completion for CSS/SCSS/LESS. Complements your existing front-end
--         trio without overlap: tailwindcss = utility-class IntelliSense, emmet_ls = abbreviation
--         expansion, ccc.nvim = colour picker/preview — none of them validate raw stylesheets.
-- NOTE  : the built-in linter is set to "warning" for unknown at-rules so Tailwind's @tailwind /
--         @apply directives don't spam errors in projects that use them.
-- INSTALL: mason — package name "css-lsp" (added to ensure_installed in plugins/conform.lua).
-- ================================================================================================
return function(capabilities)
	-- css-lsp ships snippet completions; advertise the client capability so they come through.
	local caps = require("gerrrt.utils.lsp").with_snippets(capabilities)

	local lint = { validate = true, lint = { unknownAtRules = "warning" } }

	vim.lsp.config("cssls", {
		capabilities = caps,
		cmd = { "vscode-css-language-server", "--stdio" },
		filetypes = { "css", "scss", "less" },
		root_markers = { "package.json", ".git" },
		settings = { css = lint, scss = lint, less = lint },
	})
end
