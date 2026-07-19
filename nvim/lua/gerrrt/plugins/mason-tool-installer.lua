-- ================================================================================================
-- TITLE : mason-tool-installer | the central Mason install manifest
-- LINKS : https://github.com/WhoIsSethDaniel/mason-tool-installer.nvim
-- ABOUT : ONE manifest for EVERYTHING Mason owns — LSP servers, formatters (conform), linters
--         (nvim-lint). This is the install pass a fresh machine relies on to end up with a working
--         toolchain after a start.
-- WHY ITS OWN SPEC (not inside conform): this used to live in conform.nvim's `config`, but conform
--         is lazy (`event = BufWritePre`), so `run_on_start = true` really meant "run on the first
--         :w". Meanwhile servers enable earlier at BufReadPre and `vim.lsp.enable` silently skips a
--         server whose binary isn't on PATH yet (servers/init.lua's binary_available guard) — so on a
--         fresh box the LSP stack stayed dark until a save AND a restart. Loading on VeryLazy runs the
--         install pass near startup on EVERY launch.
-- SAME-SESSION LSP : the install is async, so the BufReadPre enable pass has already run (and skipped
--         the not-yet-installed servers) by the time it finishes. The `MasonToolsUpdateCompleted`
--         handler below re-runs servers/init.lua's enable pass when installs complete —
--         `vim.lsp.enable` attaches the freshly-installed servers to the already-open buffer, so a
--         fresh box gets a working LSP stack WITHIN the first session, no restart required.
-- DELIBERATELY NOT here (installed by other channels — listing them would double-install):
--   • ruff, ty ......... uv tool install (Astral; see plugins/conform.lua header + servers/ruff.lua)
--   • rust-analyzer .... rustaceanvim / rustup (plugins/rustaceanvim.lua)
--   • nomicfoundation-solidity-language-server — npm i -g @nomicfoundation/solidity-language-server
--     (not carried in the Mason registry under a stable name; servers/solidity_*.lua expects the
--      binary on PATH). solhint (its linter) IS mason-managed, below.
-- ================================================================================================
return {
	"WhoIsSethDaniel/mason-tool-installer.nvim",
	event = "VeryLazy",
	dependencies = { "mason-org/mason.nvim" },
	config = function()
		require("mason-tool-installer").setup({
			ensure_installed = {
				-- ── LSP servers (mason package names; enabled in servers/init.lua) ──────────
				"lua-language-server",
				"gopls",
				"json-lsp",
				"typescript-language-server",
				"bash-language-server",
				"clangd",
				"dockerfile-language-server",
				"emmet-ls",
				"yaml-language-server",
				"tailwindcss-language-server",
				"taplo", -- TOML (also the conform formatter for toml)
				"marksman", -- Markdown
				"html-lsp", -- HTML validation
				"css-lsp", -- CSS/SCSS/LESS validation
				"svelte-language-server", -- Svelte component LSP (you already format/lint svelte)
				"vue-language-server", -- Vue/Volar LSP (also ships @vue/typescript-plugin for ts_ls)
				-- ── formatters (conform) ───────────────────────────────────────────────────
				"stylua",
				"shfmt",
				"gofumpt",
				"clang-format",
				"prettierd",
				-- ── linters (nvim-lint) ────────────────────────────────────────────────────
				"shellcheck",
				"golangci-lint", -- Go meta-linter (supersedes revive; richer diagnostics)
				"eslint_d",
				"hadolint",
				"cpplint",
				"luacheck",
				"solhint",
				"stylelint", -- CSS/SCSS/LESS lint (only runs when a project stylelint config exists)
				"markdownlint-cli2", -- markdown lint (mirrors the repo's markdown gate)
				"yamllint", -- yaml lint
			},
			-- Skip the startup install/update pass on engagement boxes (DOTFILES_OFFLINE=1),
			-- which would otherwise hit the mason registry and download tools. See globals.lua.
			run_on_start = not vim.g.dotfiles_offline,
		})

		-- When installs finish, re-run the server enable pass so servers whose binaries the initial
		-- BufReadPre pass skipped (fresh box) get enabled + attached to the open buffer this session.
		vim.api.nvim_create_autocmd("User", {
			pattern = "MasonToolsUpdateCompleted",
			callback = function()
				pcall(function()
					require("gerrrt.servers").enable_available()
				end)
			end,
		})
	end,
}
