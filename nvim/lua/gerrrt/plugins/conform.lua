-- ================================================================================================
-- TITLE : conform.nvim | formatter runner
-- LINKS : https://github.com/stevearc/conform.nvim
-- ABOUT : Maps filetypes to formatters and runs them. Format-on-save is wired in
--         config/autocmds.lua (trailing whitespace trimmed first); <leader>cf formats on demand.
-- ASTRAL: Python formatting uses ruff (format + import-sort). ruff + ty are installed via uv
--         (the Astral way), NOT mason — run once:
--             uv tool install ruff
--             uv tool install ty
--         The NON-Python tools (formatters + linters + servers) are installed by the central Mason
--         manifest in plugins/mason-tool-installer.lua. Prefer mason for ruff? add "ruff" there.
-- ================================================================================================
return {
	"stevearc/conform.nvim",
	event = { "BufWritePre" },
	cmd = { "ConformInfo" },
	keys = {
		{
			"<leader>cf",
			function()
				require("conform").format({ async = true, lsp_format = "fallback" })
			end,
			mode = { "n", "v" },
			desc = "Format buffer / range",
		},
	},
	opts = {
		formatters_by_ft = {
			lua = { "stylua" },
			python = { "ruff_format", "ruff_organize_imports" },
			sh = { "shfmt" },
			bash = { "shfmt" },
			go = { "gofumpt" },
			c = { "clang_format" },
			cpp = { "clang_format" },
			json = { "prettierd" },
			jsonc = { "prettierd" },
			css = { "prettierd" },
			html = { "prettierd" },
			markdown = { "prettierd" },
			yaml = { "prettierd" },
			javascript = { "prettierd" },
			javascriptreact = { "prettierd" },
			typescript = { "prettierd" },
			typescriptreact = { "prettierd" },
			svelte = { "prettierd" },
			vue = { "prettierd" },
			toml = { "taplo" }, -- taplo formats TOML; the same binary also serves as its LSP (servers/taplo.lua)
			-- NOTE: zsh is intentionally absent. shfmt is a POSIX/bash/mksh formatter and does
			-- NOT understand zsh — it mangles zsh-only syntax (glob qualifiers (#qN), ${(%):-%x},
			-- $+widgets[name-with-hyphens], &|, ...). There is no safe zsh formatter, so zsh files
			-- are never auto-formatted. (autocmds.lua also hard-skips formatting for ft=zsh, and
			-- utils/lsp.lua disables bashls's LSP formatting so the "fallback" path can't shfmt it.)
		},
	},
	-- No `config` function: `config = function(_, opts) require("conform").setup(opts) end` is
	-- byte-for-byte what lazy.nvim does by default for a spec that has `opts` and a main module,
	-- so writing it out only invited drift.
}
