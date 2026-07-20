-- ================================================================================================
-- TITLE : nvim-lint | standalone linter runner
-- LINKS : https://github.com/mfussenegger/nvim-lint
-- ABOUT : Runs a filetype's linter on write / leaving insert mode, surfacing results as
--         normal diagnostics (Trouble, <leader>cd, [d/]d all work). Binaries installed by
--         mason-tool-installer in plugins/mason-tool-installer.lua.
-- ASTRAL: Python is intentionally NOT here — the ruff language server (servers/ruff.lua)
--         provides Python lint diagnostics AND code actions. Listing ruff here too would
--         double-report.
-- ================================================================================================
return {
	"mfussenegger/nvim-lint",
	-- `User FilePost` (config/autocmds.lua). Nothing to replay: linting is driven entirely by the
	-- BufWritePost/InsertLeave autocmds registered below, both of which fire long after load.
	event = "User FilePost",
	config = function()
		local lint = require("lint")
		lint.linters_by_ft = {
			lua = { "luacheck" },
			sh = { "shellcheck" },
			bash = { "shellcheck" },
			go = { "golangcilint" }, -- meta-linter; richer than revive but heavier (runs the whole package on save)
			c = { "cpplint" },
			cpp = { "cpplint" },
			javascript = { "eslint_d" },
			javascriptreact = { "eslint_d" },
			typescript = { "eslint_d" },
			typescriptreact = { "eslint_d" },
			svelte = { "eslint_d" },
			vue = { "eslint_d" },
			dockerfile = { "hadolint" },
			solidity = { "solhint" },
			-- CSS family: cssls (servers/cssls.lua) validates syntax; stylelint adds style/lint rules.
			-- Gated below to only run when a project stylelint config exists (mirrors the eslint guard).
			css = { "stylelint" },
			scss = { "stylelint" },
			less = { "stylelint" },
			markdown = { "markdownlint-cli2" }, -- mirrors this repo's markdown gate; formatting stays prettierd (conform)
			yaml = { "yamllint" }, -- schema validation is yamlls' job; yamllint adds style/lint rules
			-- NOTE: no zsh entry. shellcheck only supports sh/bash/dash/ksh and emits SC1071
			-- ("ShellCheck only supports sh/bash/dash/ksh scripts") on a zsh file — i.e. a useless
			-- error diagnostic on every zsh buffer. Nothing reliably lints zsh, so we don't.
		}

		-- ADAPTIVE: eslint_d errors out (and spams a phantom diagnostic on every buffer) when a
		-- JS/TS project has no eslint config in its tree. Mirror the SC1071/ruff guards above by
		-- only linting the eslint family when a config is actually present upward from the buffer.
		local eslint_fts = {
			javascript = true,
			javascriptreact = true,
			typescript = true,
			typescriptreact = true,
			svelte = true,
			vue = true,
		}
		local eslint_cfgs = {
			".eslintrc",
			".eslintrc.js",
			".eslintrc.cjs",
			".eslintrc.json",
			".eslintrc.yaml",
			".eslintrc.yml",
			"eslint.config.js",
			"eslint.config.mjs",
			"eslint.config.cjs",
			"eslint.config.ts",
			"eslint.config.mts",
			"eslint.config.cts",
		}
		local function has_eslint_config()
			return vim.fs.find(eslint_cfgs, {
				upward = true,
				path = vim.fs.dirname(vim.api.nvim_buf_get_name(0)),
				type = "file",
			})[1] ~= nil
		end

		-- Same guard for stylelint: it hard-errors ("No configuration provided") when a project has
		-- no stylelint config, which would otherwise spam every CSS/SCSS/LESS buffer. Only lint when
		-- one exists upward from the buffer. (A "stylelint" key in package.json is NOT detected here —
		-- add a dedicated rc/config file to opt a project in.)
		local stylelint_fts = { css = true, scss = true, less = true }
		local stylelint_cfgs = {
			".stylelintrc",
			".stylelintrc.json",
			".stylelintrc.yaml",
			".stylelintrc.yml",
			".stylelintrc.js",
			".stylelintrc.cjs",
			".stylelintrc.mjs",
			"stylelint.config.js",
			"stylelint.config.cjs",
			"stylelint.config.mjs",
		}
		local function has_stylelint_config()
			return vim.fs.find(stylelint_cfgs, {
				upward = true,
				path = vim.fs.dirname(vim.api.nvim_buf_get_name(0)),
				type = "file",
			})[1] ~= nil
		end

		-- HEAVY linters that scan the WHOLE package/translation-unit per run (golangci-lint on go,
		-- cpplint on c/cpp) are too costly to fire on every InsertLeave — async, but the invocations
		-- pile up while you edit. Restrict them to BufWritePost (save-only); the fast per-file linters
		-- (luacheck, shellcheck, eslint_d, ...) keep the snappier BufWritePost+InsertLeave cadence.
		local heavy_fts = { go = true, c = true, cpp = true }
		local grp = vim.api.nvim_create_augroup("NvimLint", { clear = true })
		vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave" }, {
			group = grp,
			callback = function(args)
				local ft = vim.bo.filetype
				if args.event == "InsertLeave" and heavy_fts[ft] then
					return -- heavy whole-package linter → save-only, don't run on InsertLeave
				end
				if eslint_fts[ft] and not has_eslint_config() then
					return -- no eslint config in tree → skip (avoids eslint_d's hard error)
				end
				if stylelint_fts[ft] and not has_stylelint_config() then
					return -- no stylelint config in tree → skip (avoids stylelint's hard error)
				end
				require("lint").try_lint()
			end,
		})
	end,
}
