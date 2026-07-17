-- LSP client capabilities now come from blink.cmp (was: cmp_nvim_lsp). blink
-- advertises the completion capabilities its sources support; get_lsp_capabilities
-- merges them onto Neovim's defaults. (Migration: see plugins/blink-cmp.lua.)
-- Guard the blink require: if it fails to load (fresh box, plugin not built yet), fall back to
-- Neovim's default client capabilities rather than aborting the whole server stack.
local ok, capabilities = pcall(function()
	return require("blink.cmp").get_lsp_capabilities()
end)
if not ok then
	capabilities = vim.lsp.protocol.make_client_capabilities()
end

-- Language Server Protocol (LSP)
require("gerrrt.servers.lua_ls")(capabilities)
require("gerrrt.servers.ty")(capabilities) -- Astral: Python type checking + language features
require("gerrrt.servers.ruff")(capabilities) -- Astral: Python lint diagnostics + code actions
require("gerrrt.servers.gopls")(capabilities)
require("gerrrt.servers.jsonls")(capabilities)
require("gerrrt.servers.ts_ls")(capabilities)
require("gerrrt.servers.vue_ls")(capabilities) -- Vue/Volar template + styles (ts_ls owns <script>)
require("gerrrt.servers.bashls")(capabilities)
require("gerrrt.servers.clangd")(capabilities)
require("gerrrt.servers.dockerls")(capabilities)
require("gerrrt.servers.emmet_ls")(capabilities)
require("gerrrt.servers.yamlls")(capabilities)
require("gerrrt.servers.tailwindcss")(capabilities)
require("gerrrt.servers.solidity_ls_nomicfoundation")(capabilities)
require("gerrrt.servers.taplo")(capabilities) -- TOML (pyproject/Cargo/foundry/starship/mise)
require("gerrrt.servers.marksman")(capabilities) -- Markdown cross-file intelligence
require("gerrrt.servers.html")(capabilities) -- HTML validation (emmet only expands)
require("gerrrt.servers.cssls")(capabilities) -- CSS/SCSS/LESS validation
require("gerrrt.servers.svelte")(capabilities) -- Svelte component intelligence (ts_ls owns <script>)

-- Python: ty (types) + ruff (lint/codeactions) is the Astral stack — pyright intentionally
-- not enabled. To fall back to pyright, re-add servers/pyright.lua and list it here.

-- The servers we WANT on. Whether each actually gets enabled is gated below by whether its
-- binary is present, so a not-yet-installed server can't spam errors.
local wanted = {
	"lua_ls",
	"ty",
	"ruff",
	"gopls",
	"jsonls",
	"ts_ls",
	"vue_ls",
	"bashls",
	"clangd",
	"dockerls",
	"emmet_ls",
	"yamlls",
	"tailwindcss",
	"solidity_ls_nomicfoundation",
	"taplo",
	"marksman",
	"html",
	"cssls",
	"svelte",
}

-- Only enable a server whose executable is actually installed. Native vim.lsp.enable()
-- otherwise tries to SPAWN the configured cmd every time a matching filetype opens, and a
-- missing binary surfaces as a recurring "spawn <server> ENOENT" / "client quit" error on
-- every such buffer. That is exactly what produced the periodic vscode-json-language-server
-- errors: jsonls (servers/jsonls.lua) has no explicit cmd, so it inherits lspconfig's default
-- { "vscode-json-language-server", "--stdio" }, whose binary ships in Mason's json-lsp package —
-- which nothing installed before. Mason now installs it (plugins/conform.lua), and this guard
-- makes the whole stack resilient on any box where a server binary isn't present yet (fresh
-- machine, DOTFILES_OFFLINE, or a uv/npm-provided server like ruff/ty/solidity not installed).
local function binary_available(name)
	local cfg = vim.lsp.config[name]
	local cmd = cfg and cfg.cmd
	-- No resolvable cmd (nil) or a function launcher: don't second-guess it, let it try.
	if type(cmd) ~= "table" or cmd[1] == nil then
		return true
	end
	return vim.fn.executable(cmd[1]) == 1
end

local to_enable, missing = {}, {}
for _, name in ipairs(wanted) do
	if binary_available(name) then
		to_enable[#to_enable + 1] = name
	else
		missing[#missing + 1] = name
	end
end

vim.lsp.enable(to_enable)

-- Surface (once) which servers were skipped so a missing binary is discoverable, not silent.
-- Suppressed on engagement/offline boxes (DOTFILES_OFFLINE=1, see config/globals.lua), where
-- tools are intentionally not installed and the warning would just be startup noise.
if #missing > 0 and not vim.g.dotfiles_offline then
	vim.schedule(function()
		vim.notify(
			"LSP not enabled (binary not found): "
				.. table.concat(missing, ", ")
				.. "\nInstall via :Mason — except ruff/ty (uv tool install) and rust (rustup).",
			vim.log.levels.WARN,
			{ title = "gerrrt.servers" }
		)
	end)
end
