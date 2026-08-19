-- ================================================================================================
-- TITLE : vue_ls / Volar (Vue language server) LSP Setup
-- LINKS : https://github.com/vuejs/language-tools
-- ABOUT : Template/style intelligence for .vue single-file components. Runs in Volar 2.x "hybrid
--         mode": vue_ls owns the <template> (and styles), while ts_ls owns the <script> via Vue's
--         TypeScript plugin (wired in servers/ts_ls.lua). Both attach to .vue buffers. You already
--         declared vue across the toolchain (conform/prettierd, nvim-lint/eslint_d, treesitter,
--         tailwindcss, emmet) — this adds the missing component-level language server.
-- NAME  : we use the identifier `vue_ls` (lspconfig renamed `volar` → `vue_ls`). Because we supply
--         cmd/filetypes/root_markers ourselves, this does not depend on lspconfig shipping the
--         config under either name.
-- INSTALL: mason — package "vue-language-server" (added to ensure_installed in plugins/mason-tool-installer.lua).
-- ================================================================================================
return {
	cmd = { "vue-language-server", "--stdio" },
	filetypes = { "vue" },
	root_markers = {
		"vue.config.js",
		"vue.config.ts",
		"nuxt.config.js",
		"nuxt.config.ts",
		"package.json",
		".git",
	},
}
