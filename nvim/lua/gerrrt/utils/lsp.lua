-- ================================================================================================
-- TITLE : LSP on_attach
-- ABOUT : buffer-local keymaps bound whenever a language server attaches.
-- NOTE  : Neovim 0.12 ships capable native LSP, so this uses vim.lsp.buf.* directly
--         (hover / rename / code action / signature) and fzf-lua for the picker-style
--         lookups (definitions / references / symbols). lspsaga was removed — it only
--         duplicated what's now built in.
-- ================================================================================================
local M = {}

-- NOTE: M.with_snippets() was removed. It hand-deepcopied the shared capabilities table just to
-- flip completionItem.snippetSupport for html-lsp/css-lsp. Capabilities are now advertised once on
-- the "*" wildcard (servers/init.lua) and vim.lsp.config deep-merges each server's table over it,
-- so those two servers set only the snippetSupport LEAF and inherit everything else — no copy, no
-- risk of mutating the shared table. See servers/html.lua for the shape.

-- True when the server's advertised code-action support could include source.organizeImports.
-- A server that enumerates its codeActionKinds without a "source"/"source.organizeImports" kind is
-- ruled out; a bare boolean `true` (no kinds enumerated) is allowed through since we can't tell.
local function offers_organize_imports(client)
	local prov = client.server_capabilities and client.server_capabilities.codeActionProvider
	if prov == true then
		return true
	end
	if type(prov) == "table" then
		local kinds = prov.codeActionKinds
		if type(kinds) ~= "table" then
			return true -- provider present but kinds unspecified — allow it
		end
		-- Code-action kinds are HIERARCHICAL, so accept descendants too: some servers advertise a more
		-- specific kind (e.g. ruff → "source.organizeImports.ruff") while still honoring a request for
		-- the parent "source.organizeImports". Match the bare "source" umbrella, the exact kind, or any
		-- "source.organizeImports.*" descendant.
		for _, k in ipairs(kinds) do
			if k == "source" or k == "source.organizeImports" or vim.startswith(k, "source.organizeImports.") then
				return true
			end
		end
		return false
	end
	return false
end

-- Neovim 0.11+/0.12 ships default LSP maps grn/gra/grr/gri/grt/grx. Our `gr`=references (below)
-- is a *complete* mapping, so leaving these in place makes `gr` wait timeoutlen (500ms) before
-- firing. We have <leader>rn / <leader>ca / gr / gi for these already, so clear the defaults.
--
-- GLOBAL, NOT BUFFER-LOCAL, AND DONE ONCE. These are created with a plain `vim.keymap.set('n', ...)`
-- in the runtime (lua/vim/_core/defaults.lua), so they live in the global map table. The previous
-- form passed `{ buffer = bufnr }`, which raises E31 ("No such mapping") for every one of them —
-- swallowed by the pcall, so the maps survived and `gr` kept waiting. Deleting global state also
-- doesn't belong in on_attach, which re-runs per attaching client (twice on a Python buffer:
-- ruff + ty). grt (type_definition) and grx (codelens.run) were missing from the old list; any
-- remaining gr* keeps `gr` ambiguous, so all six must go.
--
-- EVERY DELETED DEFAULT HAS A REPLACEMENT — check this before adding to the list. grn -> <leader>rn,
-- gra -> <leader>ca, grr -> gr, gri -> gi, grt -> gy, grx -> <leader>cl (added with grx itself;
-- codelens was the one default with no prior equivalent here). Deleting a default with no
-- replacement silently removes a working LSP action.
-- pcall'd only to tolerate a future Neovim that stops shipping one of them.
for _, lhs in ipairs({ "grn", "gra", "grr", "gri", "grt", "grx" }) do
	pcall(vim.keymap.del, "n", lhs)
end

M.on_attach = function(event)
	if not event.data then
		return
	end

	local ok, client = pcall(vim.lsp.get_client_by_id, event.data.client_id)
	if not ok or not client then
		return
	end

	local bufnr = event.buf
	-- Astral: let ty own hover on Python; ruff's hover is minimal and would clash.
	if client.name == "ruff" then
		client.server_capabilities.hoverProvider = false
	end

	-- bash-language-server formats by shelling out to shfmt, which mangles zsh. We attach
	-- bashls to zsh files for completion, but must NOT let it format them — otherwise the
	-- conform lsp_format="fallback" path (and <leader>cf) would re-introduce the corruption
	-- we removed from conform. sh/bash are unaffected: conform formats those with shfmt
	-- directly, so the LSP fallback never runs for them anyway.
	if client.name == "bashls" then
		client.server_capabilities.documentFormattingProvider = false
		client.server_capabilities.documentRangeFormattingProvider = false
	end

	local keymap = vim.keymap.set
	local function opts(desc)
		return { noremap = true, silent = true, buffer = bufnr, desc = desc }
	end

	-- ── Native LSP (built into Neovim 0.12) ──────────────────────────────────
	-- hover/signature pass an explicit rounded border + size caps. winborder (options.lua) already
	-- makes floats rounded globally; passing `border` here is self-documenting AND lets us bound the
	-- width/height so a huge docstring becomes a tidy, padded NvChad-style card instead of a wall.
	local float_opts = { border = "rounded", max_width = 80, max_height = 25 }
	keymap("n", "K", function()
		vim.lsp.buf.hover(float_opts)
	end, opts("Hover documentation"))
	keymap("n", "gD", vim.lsp.buf.declaration, opts("Go to declaration"))
	-- NvChad-style inline rename float (prefilled prompt at the cursor) instead of the bare
	-- cmdline vim.lsp.buf.rename. Falls back to the native prompt when there's no <cword>.
	keymap("n", "<leader>rn", function()
		require("gerrrt.utils.renamer").rename()
	end, opts("Rename symbol"))
	keymap({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts("Code action"))
	-- REPLACEMENT for the deleted `grx` default (vim.lsp.codelens.run — see the deletion loop at
	-- the top of this file). Unlike the other five defaults we delete, grx had NO equivalent
	-- anywhere in this config: grn -> <leader>rn, gra -> <leader>ca, grr -> gr, gri -> gi,
	-- grt -> gy, but codelens had nothing. Deleting it without this line would have silently
	-- dropped a working LSP action.
	--
	-- <leader>cL, NOT <leader>cl: lowercase cl is Trouble's "LSP refs/defs" (plugins/trouble-nvim.lua).
	-- These maps are BUFFER-LOCAL and buffer-local wins over global, so taking cl here would have
	-- shadowed Trouble's binding on precisely the LSP-attached buffers where it is used.
	keymap("n", "<leader>cL", vim.lsp.codelens.run, opts("Run CodeLens"))
	keymap("i", "<C-s>", function()
		vim.lsp.buf.signature_help(float_opts)
	end, opts("Signature help"))

	-- AUTOMATIC signature help is owned by blink.cmp (plugins/blink-cmp.lua, signature.enabled):
	-- it pops the params float as you type inside the parens, in its own rounded window. A manual
	-- CursorHoldI vim.lsp.buf.signature_help used to live here too, but blink's signature window is
	-- a SEPARATE surface from its completion menu, so the two floats could stack while idle. blink
	-- owns the automatic case now; <C-s> above stays the on-demand manual trigger.

	-- ── Diagnostics (native) ─────────────────────────────────────────────────
	keymap("n", "<leader>cd", vim.diagnostic.open_float, opts("Line diagnostics"))
	keymap("n", "[d", function()
		vim.diagnostic.jump({ count = -1, float = true })
	end, opts("Previous diagnostic"))
	keymap("n", "]d", function()
		vim.diagnostic.jump({ count = 1, float = true })
	end, opts("Next diagnostic"))

	-- ── fzf-lua pickers (nice fuzzy UI for the list-style lookups) ───────────
	keymap("n", "gd", "<cmd>FzfLua lsp_definitions<CR>", opts("Definitions"))
	keymap("n", "gr", "<cmd>FzfLua lsp_references<CR>", opts("References"))
	keymap("n", "gi", "<cmd>FzfLua lsp_implementations<CR>", opts("Implementations"))
	keymap("n", "gy", "<cmd>FzfLua lsp_typedefs<CR>", opts("Type definitions"))
	keymap("n", "<leader>fs", "<cmd>FzfLua lsp_document_symbols<CR>", opts("Document symbols"))
	keymap("n", "<leader>fw", "<cmd>FzfLua lsp_workspace_symbols<CR>", opts("Workspace symbols"))

	-- ── Organize imports (only where the server actually offers it) ──────────
	-- The old guard was generic `textDocument/codeAction` support — nearly every server advertises
	-- that, so <leader>oi bound even for servers (lua_ls, etc.) that have no organizeImports action
	-- and would silently no-op. Now we inspect the advertised codeActionKinds: a server that
	-- ENUMERATES its kinds without "source[.organizeImports]" is skipped; a server that only reports
	-- a bare `true` (kinds unknown) still gets the map, since we can't rule it out.
	--
	-- The old body also formatted after a fixed `defer_fn(…, 50)` — racy: 50ms could fire before the
	-- import edit applied (formatting stale text) or needlessly late. Dropped entirely; formatting is
	-- owned by format-on-save (config/autocmds.lua) and <leader>cf, so organizeImports just does the
	-- one thing it names.
	if offers_organize_imports(client) then
		keymap("n", "<leader>oi", function()
			vim.lsp.buf.code_action({
				context = { only = { "source.organizeImports" }, diagnostics = {} },
				apply = true,
			})
		end, opts("Organize imports"))
	end
end

return M
