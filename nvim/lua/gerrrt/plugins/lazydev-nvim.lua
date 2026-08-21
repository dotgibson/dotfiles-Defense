-- ================================================================================================
-- TITLE : lazydev.nvim | correct LuaLS types for editing your Neovim config
-- LINKS : https://github.com/folke/lazydev.nvim
-- ABOUT : This is what kills the "undefined field" / "undefined global vim" squiggles in your
--         own config files. Setting `diagnostics.globals = { "vim" }` (servers/lua_ls.lua) only
--         silenced the *global* warning — lua_ls still had no TYPES for vim.api / vim.fn / vim.uv
--         / vim.hl, so every field access lit up anyway. lazydev feeds lua_ls the Neovim runtime
--         types, your installed plugins, and (via luvit-meta) vim.uv, dynamically as you edit.
--         It is folke's successor to neodev.nvim, which he deprecated for Neovim >= 0.10.
-- NOTE  : Because lazydev now manages the workspace library, servers/lua_ls.lua no longer hand-
--         lists $VIMRUNTIME/lua. The `---@diagnostic disable-next-line: undefined-field` in
--         config/lazy.lua is kept on purpose: lazydev resolves vim.uv, but the call site is
--         `(vim.uv or vim.loop).fs_stat` and the vim.loop side of that union can still flag
--         undefined-field — the pragma is a harmless belt-and-suspenders. Loads only on lua
--         files, so there's no startup cost elsewhere.
-- ================================================================================================
return {
	{
		"folke/lazydev.nvim",
		ft = "lua",
		opts = {
			library = {
				-- pull in vim.uv (libuv) types, but only when a file actually references vim.uv
				{ path = "luvit-meta/library", words = { "vim%.uv" } },
			},
		},
	},
	-- vim.uv (libuv) type annotations, loaded on demand by the lazydev library entry above
	{ "Bilal2453/luvit-meta", lazy = true },
}
