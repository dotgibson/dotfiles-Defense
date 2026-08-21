-- ================================================================================================
-- TITLE : ty (Astral Python type checker) LSP Setup
-- LINKS :
--   > docs   : https://docs.astral.sh/ty/editors/
--   > github : https://github.com/astral-sh/ty
-- NOTE  : `cmd = { "ty", "server" }` is REQUIRED. The minimal docs snippet omits it and ty then
--         reports no diagnostics in Neovim (see astral-sh/ty#2616). ty is beta — if it ever
--         feels thin, re-enable pyright in servers/init.lua.
-- INSTALL: uv tool install ty      (preferred)  — or: uvx ty / pip install ty
-- ================================================================================================
return {
	cmd = { "ty", "server" },
	filetypes = { "python" },
	settings = {
		ty = {
			-- ty language server settings go here, e.g.:
			-- configuration = { rules = { ["unresolved-reference"] = "warn" } },
		},
	},
}
