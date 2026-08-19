return {
	settings = {
		Lua = {
			-- lazydev.nvim (plugins/lazydev.lua) now feeds lua_ls the Neovim runtime types,
			-- vim.uv (via luvit-meta), and your installed plugins — so the old hand-listed
			-- workspace.library ($VIMRUNTIME/lua + the config dir) is gone. Those gaps were
			-- exactly what lua_ls was flagging as "undefined field" squiggles. The require
			-- path and your own gerrrt.* modules are handled by lazydev + the workspace root.
			diagnostics = { globals = { "vim" } }, -- harmless fallback; lazydev provides this too
			workspace = { checkThirdParty = false }, -- stop the "configure this as a library?" prompts
		},
	},
}
