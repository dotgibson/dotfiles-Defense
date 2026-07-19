-- ================================================================================================
-- TITLE : taplo (TOML language server) LSP Setup
-- LINKS : https://github.com/tamasfe/taplo  ·  https://taplo.tamasfe.dev/
-- ABOUT : Completion, validation, hover and formatting for TOML — which is everywhere in your
--         stack: pyproject.toml (ruff/ty), Cargo.toml (rust), foundry.toml (solidity), plus
--         starship/mise configs in this very dotfiles repo. Schema-aware via SchemaStore.
-- INSTALL: mason — package name "taplo" (added to ensure_installed in plugins/conform.lua).
-- ================================================================================================
return function(capabilities)
	vim.lsp.config("taplo", {
		capabilities = capabilities,
		cmd = { "taplo", "lsp", "stdio" },
		filetypes = { "toml" },
		-- Real base names only: vim.fs.root / vim.fs.find do NOT support globs (see neovim
		-- runtime/lua/vim/fs.lua — "paths and globs are not supported"). The old "*.toml" never
		-- matched, so taplo silently always fell back to .git and a lone TOML file outside a repo
		-- got a cwd root. List the TOML manifests this stack actually uses instead.
		--
		-- The manifests are NESTED into one inner list so they share EQUAL priority — root at the
		-- NEAREST ancestor holding ANY of them. A flat sequential list is priority order (neovim
		-- fs.lua: "to indicate 'equal priority', specify items in a nested list"), which in a mixed
		-- monorepo would prefer a distant pyproject.toml over a nearer Cargo.toml. `.git` stays a
		-- lower-priority fallback for a TOML file that sits in a repo without a manifest above it.
		root_markers = { { "pyproject.toml", "Cargo.toml", "foundry.toml", "taplo.toml", ".taplo.toml" }, ".git" },
	})
end
