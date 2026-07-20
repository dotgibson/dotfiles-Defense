return {
	filetypes = { "json", "jsonc" },
	settings = {
		json = {
			validate = { enable = true },
		},
	},
	-- SchemaStore (plugins/schemastore.lua) feeds the full schemastore.org catalogue so common
	-- config files (package.json, tsconfig, .eslintrc, GitHub Actions, ...) get validation +
	-- completion.
	--
	-- Resolved in before_init, NOT inline in `settings` above. schemastore.json.schemas() builds
	-- a 1,368-entry table (~5ms with the catalogue require); inline, that ran while this module
	-- was being CONFIGURED, and servers/init.lua configures all 19 servers in one pass.
	--
	-- To be precise about the cost, because the obvious phrasing overstates it: that pass runs
	-- ONCE PER SESSION (nvim-lspconfig loads from the one-shot `User FilePost` event, and Lua's
	-- require caches the module) — it was never per-buffer. The problem is that it was paid
	-- REGARDLESS OF FILETYPE: a session that only ever opens Lua files still built the entire
	-- JSON schema catalogue. before_init runs once per client INSTANCE, so the cost now lands
	-- only when a jsonls client actually starts. This is the idiom Neovim documents for exactly
	-- this (:h vim.lsp.ClientConfig — the tailwindcss configFile example).
	--
	-- pcall'd: on a box where schemastore isn't installed yet we keep validate=true and simply
	-- go without the catalogue, rather than erroring out of client startup.
	--
	-- MUTATE IN PLACE — do NOT rebind `config.settings`. Client.create() binds
	-- `self.settings = config.settings` (runtime lua/vim/lsp/client.lua:409) BEFORE before_init is
	-- invoked (:571). vim.tbl_deep_extend returns a NEW table, so `config.settings = ...` leaves
	-- client.settings pointing at the original and the catalogue is silently dropped — both the
	-- push path (workspace/didChangeConfiguration sends self.settings) and the pull path
	-- (handlers.lua lookup_section(client.settings, ...)) read the client's copy.
	-- Neovim's own docs demonstrate the rebinding form (client.lua:36-41); it does not work.
	before_init = function(_, config)
		local ok, store = pcall(require, "schemastore")
		if not ok then
			return
		end
		config.settings = config.settings or {}
		config.settings.json = config.settings.json or {}
		config.settings.json.schemas = store.json.schemas()
	end,
}
