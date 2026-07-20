-- Vue hybrid mode: ts_ls owns the <script> in .vue files via Vue's TypeScript plugin, while
-- vue_ls (servers/vue_ls.lua) owns the <template>/styles. For that, ts_ls must (a) load
-- @vue/typescript-plugin and (b) also attach to the `vue` filetype. The plugin ships INSIDE the
-- mason `vue-language-server` package; we wire it ONLY when that package is installed, so a box
-- without Vue tooling keeps a clean plain-TypeScript ts_ls (no broken init_options / dead ft).
local vue_plugin = vim.fn.stdpath("data") .. "/mason/packages/vue-language-server/node_modules/@vue/language-server"
local filetypes = { "typescript", "javascript", "typescriptreact", "javascriptreact" }
local init_options

if vim.fn.isdirectory(vue_plugin) == 1 then
	init_options = {
		plugins = {
			{
				name = "@vue/typescript-plugin",
				location = vue_plugin,
				languages = { "vue" },
			},
		},
	}
	filetypes[#filetypes + 1] = "vue"
end

return {
	filetypes = filetypes,
	init_options = init_options,
	settings = { typescript = { indentStyle = "space", indentSize = 2 } },
	-- Native vim.lsp.config uses `root_markers` (a list), NOT the old lspconfig
	-- `root_dir = function(fname)` form. Under native LSP a root_dir FUNCTION has the
	-- signature fun(bufnr, on_dir) and must CALL on_dir() to start the client — a
	-- function that merely returns a path (the lspconfig idiom) is silently ignored,
	-- so the server never attaches. root_markers is the correct native equivalent.
	root_markers = { "tsconfig.json", "jsconfig.json", "package.json" },
}
