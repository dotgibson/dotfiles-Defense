-- ================================================================================================
-- TITLE : nvim-lspconfig | server config definitions for native LSP
-- LINKS : https://github.com/neovim/nvim-lspconfig
-- NOTE  : On Neovim 0.11+/0.12 lspconfig mainly SHIPS the server config files; the actual
--         enabling happens via vim.lsp.enable() in gerrrt/servers/init.lua. Mason installs
--         the server binaries (run :Mason to add/remove). Formatting/linting is handled by
--         conform.nvim + nvim-lint, not an LSP, so efmls-configs is no longer a dependency.
--         2026: cmp-nvim-lsp dropped — capabilities now come from blink.cmp (servers/init.lua).
-- ================================================================================================
return {
	"neovim/nvim-lspconfig",
	-- Loads on the custom `User FilePost` event (config/autocmds.lua) rather than BufReadPre, so the
	-- ~103ms of server configuration lands AFTER the first UI paint instead of in front of it.
	-- vim.lsp.enable() re-runs `doautoall nvim.lsp.enable FileType` when called post-startup, so the
	-- buffer that triggered the load still gets its client attached — no manual replay needed.
	event = "User FilePost",
	dependencies = {
		{ "mason-org/mason.nvim", opts = {} },
		-- blink.cmp is declared here because servers/init.lua calls
		-- `require("blink.cmp").get_lsp_capabilities()` to build the "*" capabilities. That require
		-- already pulled blink (+ friendly-snippets) in at THIS event via lazy's require-hook, so
		-- blink's own `event = "InsertEnter"` was never the trigger that actually loaded it —
		-- measured: opening a file and never entering insert mode loaded blink.cmp.
		--
		-- This is a HONESTY fix, not a speed-up: the load already happened, it just wasn't declared.
		-- Deferring blink any later is NOT an option — capabilities must be advertised in the
		-- `initialize` request, so a client started before blink loads would permanently advertise
		-- base capabilities and silently lose snippet/resolve support. Declaring it makes lazy load
		-- blink BEFORE this config body runs, so the pcall fallback in servers/init.lua now guards
		-- only genuine failure instead of masking a load-order dependency.
		"saghen/blink.cmp",
	},
	config = function()
		require("gerrrt.utils.diagnostics").setup()
		require("gerrrt.servers")
	end,
}
