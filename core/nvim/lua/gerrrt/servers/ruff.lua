-- ================================================================================================
-- TITLE : ruff (Astral linter/formatter) LSP Setup
-- LINKS :
--   > docs   : https://docs.astral.sh/ruff/editors/
--   > github : https://github.com/astral-sh/ruff
-- ABOUT : Runs `ruff server` to provide lint diagnostics AND code actions (autofix, organize
--         imports) over LSP — richer than running ruff through nvim-lint, which is why Python
--         was removed from nvim-lint.lua. Formatting on save is still done by conform
--         (conform calls `ruff format`). Hover is disabled for ruff in utils/lsp.lua so that
--         ty owns hover on Python buffers.
-- INSTALL: uv tool install ruff    (preferred)  — or add "ruff" back to mason in conform.lua
-- ================================================================================================
return {
	cmd = { "ruff", "server" },
	filetypes = { "python" },
}
