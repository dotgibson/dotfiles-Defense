-- ================================================================================================
-- TITLE : LSP on_attach
-- ABOUT : buffer-local keymaps bound whenever a language server attaches.
-- NOTE  : Neovim 0.12 ships capable native LSP, so this uses vim.lsp.buf.* directly
--         (hover / rename / code action / signature) and fzf-lua for the picker-style
--         lookups (definitions / references / symbols). lspsaga was removed — it only
--         duplicated what's now built in. DAP keymaps live in the nvim-dap plugin spec,
--         not here, so they aren't gated behind an LSP attach.
-- ================================================================================================
local M = {}

-- Return a COPY of `capabilities` with completionItem.snippetSupport advertised. Servers whose
-- completions ship as snippets (html-lsp, css-lsp) need this or their items arrive as plain text.
-- Extracted here so servers/html.lua and servers/cssls.lua stop hand-rolling the identical
-- deepcopy + nested-table dance (kept them in lockstep was pure drift risk). deepcopy so a server
-- flipping this can never mutate the shared `capabilities` table the other servers were built from.
function M.with_snippets(capabilities)
	local caps = vim.deepcopy(capabilities)
	caps.textDocument = caps.textDocument or {}
	caps.textDocument.completion = caps.textDocument.completion or {}
	caps.textDocument.completion.completionItem = caps.textDocument.completion.completionItem or {}
	caps.textDocument.completion.completionItem.snippetSupport = true
	return caps
end

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

	-- Neovim 0.11+/0.12 ships default LSP maps grn/gra/grr/gri. Our `gr`=references
	-- below is a *complete* mapping, so leaving these in place makes `gr` wait
	-- timeoutlen (500ms) before firing. We have <leader>rn / <leader>ca / gr / gi
	-- for these already, so clear the defaults to make `gr` instant.
	for _, lhs in ipairs({ "grn", "gra", "grr", "gri" }) do
		pcall(vim.keymap.del, "n", lhs, { buffer = bufnr })
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
	keymap("n", "<leader>rn", vim.lsp.buf.rename, opts("Rename symbol"))
	keymap({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts("Code action"))
	keymap("i", "<C-s>", function()
		vim.lsp.buf.signature_help(float_opts)
	end, opts("Signature help"))

	-- Auto signature help while resting in a function's arguments. blink.cmp already surfaces
	-- signatures DURING completion; this covers the other case — you've paused typing inside the
	-- parens and want the params without reaching for <C-s>. Gated on server support, and otherwise
	-- self-gating (signature_help draws nothing when the cursor isn't inside a signature). Skipped
	-- while the blink menu is open so two signature floats never stack. focusable=false so it can't
	-- steal the cursor; silent=true swallows the "no signature help" message. Fires after
	-- 'updatetime' (300ms, options.lua) of no typing. Per-buffer augroup (clear=true) dedupes across
	-- multiple attached clients.
	if client:supports_method("textDocument/signatureHelp", bufnr) then
		local sig_group = vim.api.nvim_create_augroup("GerrrtLspSignature_" .. bufnr, { clear = true })
		vim.api.nvim_create_autocmd("CursorHoldI", {
			group = sig_group,
			buffer = bufnr,
			callback = function()
				local blink_ok, blink = pcall(require, "blink.cmp")
				if blink_ok and blink.is_visible() then
					return
				end
				pcall(vim.lsp.buf.signature_help, {
					border = "rounded",
					max_width = 80,
					max_height = 25, -- same bounded card as manual K/<C-s> so many-overload sigs stay tidy
					focusable = false,
					silent = true,
				})
			end,
		})
	end

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
