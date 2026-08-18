-- ================================================================================================
-- TITLE : svelte (svelte-language-server) LSP Setup
-- LINKS : https://github.com/sveltejs/language-tools
-- ABOUT : Diagnostics, hover, completion and go-to for .svelte components. You already declared
--         svelte across the toolchain — conform (prettierd), nvim-lint (eslint_d), treesitter,
--         tailwindcss and emmet all target it — but there was no language server actually attaching,
--         so component-level intelligence was missing. This closes that gap. ts_ls still owns the
--         <script> TS/JS; tailwindcss/emmet handle classes/abbreviations — no overlap.
-- INSTALL: mason — package name "svelte-language-server" (added to ensure_installed in conform.lua).
-- ================================================================================================
return {
	cmd = { "svelteserver", "--stdio" },
	filetypes = { "svelte" },
	root_markers = { "svelte.config.js", "svelte.config.mjs", "package.json", ".git" },
}
