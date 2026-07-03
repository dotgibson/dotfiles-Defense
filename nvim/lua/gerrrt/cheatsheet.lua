-- ================================================================================================
-- TITLE : cheatsheet | a full-screen, NVChad-style keybinding reference
-- ABOUT : which-key answers "I've started typing <leader>, what's next?" — great for discovery,
--         useless for "what do I even have?". This is the other half: one floating panel that
--         lays out EVERY curated binding in the config at once, grouped by task, so you can
--         eyeball the whole surface area and rediscover the features you're under-using.
-- WHY HAND-CURATED : the mappings live across ~30 lazy specs, most bound lazily and not registered
--         until their plugin loads — so scraping `nvim_get_keymap()` at open time would show a
--         half-empty, load-order-dependent list. This table is the intentional, always-complete
--         picture; when you add a binding to a plugin spec, add its row here too (they sit next to
--         each other in review). Descriptions mirror the `desc =` on the real keymaps.
-- ENTRY : `:Cheatsheet` (alias `:Cheat`) and `<leader>?` (see config/keymaps.lua). `q`/`<Esc>`
--         close; the panel is a throwaway scratch buffer, nothing to save.
-- DEPS  : none — pure Neovim API, so it survives on a bare box the same as the rest of Core.
-- ================================================================================================

local M = {}

-- ── the content ──────────────────────────────────────────────────────────────────────────────
-- Ordered list of cards. Each card = { title, { "keys", "description" }, ... }. Order here is the
-- order they get packed into the masonry columns (shortest-column-first), so keep related cards
-- adjacent and roughly grouped essentials → editing → navigation → git → lang → tools.
M.sections = {
	{
		"Essentials",
		{ "<leader>?", "Open this cheatsheet" },
		{ "<leader>wk", "Buffer-local keys" },
		{ "<leader>rc", "Edit init.lua" },
		{ "<Esc>", "Clear search highlight" },
		{ "<leader>pa", "Copy full file path" },
		{ "<leader>p", "Paste over, keep yank (x)" },
		{ "<leader>D", "Delete to black hole" },
		{ "gc / gcc", "Comment motion / line" },
	},
	{
		"Motion & Search",
		{ "j / k", "Down / up (wrap-aware)" },
		{ "n / N", "Next / prev match (centered)" },
		{ "<C-d> / <C-u>", "Half page down / up (centered)" },
		{ "J", "Join lines, keep cursor" },
		{ "< / >", "Indent, keep selection (v)" },
		{ "[c", "Jump to context (upwards)" },
	},
	{
		"Flash (jump)",
		{ "s", "Flash jump" },
		{ "S", "Flash Treesitter" },
		{ "r", "Remote Flash (o)" },
		{ "R", "Treesitter search (o/x)" },
		{ "<C-s>", "Toggle Flash in / search (c)" },
	},
	{
		"Windows & Splits",
		{ "<C-h/j/k/l>", "Move (crosses tmux panes)" },
		{ "<leader>sv", "Split vertically" },
		{ "<leader>sh", "Split horizontally" },
		{ "<leader>se", "Equalize sizes" },
		{ "<leader>sw", "Cycle to next split" },
		{ "<leader>sx", "Swap positions" },
		{ "<leader>sq", "Close split" },
		{ "<leader>so", "Close all OTHER splits" },
		{ "<C-arrows>", "Resize height / width" },
	},
	{
		"Buffers",
		{ "]b / [b", "Next / previous" },
		{ "<leader>bj", "Pick (jump to letter)" },
		{ "<leader>bd", "Delete, keep layout" },
		{ "<leader>bP", "Pin / unpin" },
		{ "<leader>bo/br/bh", "Close others / right / left" },
		{ "<leader>b, / b.", "Move left / right" },
	},
	{
		"Tabs (workspaces)",
		{ "<leader><tab>n", "New tab" },
		{ "<leader><tab>d", "Close tab" },
		{ "<leader><tab>o", "Close other tabs" },
		{ "]<tab> / [<tab>", "Next / previous" },
		{ "gt / gT", "Cycle (native)" },
	},
	{
		"Harpoon",
		{ "<leader>ha", "Add file" },
		{ "<leader>hh", "Toggle menu" },
		{ "<leader>hn / hN", "Next / previous file" },
		{ "<leader>1..4", "Jump to pinned file" },
	},
	{
		"Find (fzf-lua)",
		{ "<leader>ff", "Files" },
		{ "<leader>fg", "Live grep" },
		{ "<leader>fb", "Buffers" },
		{ "<leader>fr", "Recent files" },
		{ "<leader>fh", "Help tags" },
		{ "<leader>fk", "Keymaps" },
		{ "<leader>ft", "Todo comments" },
		{ "<leader>fd / fD", "Diagnostics doc / workspace" },
		{ "<leader>fs / fw", "Symbols doc / workspace" },
	},
	{
		"LSP & Code",
		{ "K", "Hover docs" },
		{ "gd / gD", "Definition / declaration" },
		{ "gr", "References" },
		{ "gi", "Implementations" },
		{ "gy", "Type definitions" },
		{ "<leader>ca", "Code action (n/v)" },
		{ "<leader>rn", "Rename symbol" },
		{ "<leader>cd", "Line diagnostics" },
		{ "[d / ]d", "Prev / next diagnostic" },
		{ "<C-s>", "Signature help (i)" },
		{ "<leader>oi", "Organize imports" },
		{ "<leader>cf", "Format buffer / range" },
		{ "<leader>co", "Code outline (Aerial)" },
		{ "<leader>cs", "Symbols (Trouble)" },
		{ "<leader>cn", "Annotation (Neogen)" },
		{ "<leader>;", "Breadcrumb pick (dropbar)" },
	},
	{
		"Trouble & Lists",
		{ "<leader>xx", "Workspace diagnostics" },
		{ "<leader>xX", "Buffer diagnostics" },
		{ "<leader>xL", "Location list" },
		{ "<leader>xQ", "Quickfix list" },
		{ "<leader>xt / xT", "Todos / Todo-Fix-Fixme" },
	},
	{
		"Git — hunks (gitsigns)",
		{ "]h / [h", "Next / prev hunk" },
		{ "<leader>gs", "Stage / unstage hunk" },
		{ "<leader>gS", "Stage whole buffer" },
		{ "<leader>gr", "Reset hunk" },
		{ "<leader>gp", "Preview hunk" },
		{ "<leader>gb", "Blame line" },
		{ "<leader>gd", "Diff this" },
		{ "ih", "Hunk text object (dih/vih)" },
	},
	{
		"Git — tools",
		{ "<leader>gg", "Status (fugitive)" },
		{ "<leader>gc", "Commit" },
		{ "<leader>gP", "Push" },
		{ "<leader>gl", "LazyGit (float)" },
		{ "<leader>gv / gV", "Diffview open / close" },
		{ "<leader>gH / gL", "History: file / repo" },
		{ "<leader>gy / gY", "Permalink: yank / open" },
	},
	{
		"Git — conflicts",
		{ "]x / [x", "Next / prev conflict" },
		{ "<leader>gxo / gxt", "Choose ours / theirs" },
		{ "<leader>gxb / gx0", "Choose both / none" },
		{ "<leader>gxl", "List conflicts (quickfix)" },
	},
	{
		"Debug (DAP)",
		{ "<leader>db / dB", "Breakpoint / conditional" },
		{ "<leader>dc", "Continue / start" },
		{ "<leader>do / di", "Step over / into" },
		{ "<leader>du", "Step out" },
		{ "<leader>dr", "Open REPL" },
		{ "<leader>dl", "Run last" },
		{ "<leader>dt", "Toggle UI" },
		{ "<leader>de", "Evaluate expression" },
		{ "<leader>dx", "Terminate" },
	},
	{
		"Test (neotest)",
		{ "<leader>tt", "Run nearest" },
		{ "<leader>tf", "Run current file" },
		{ "<leader>td", "Debug nearest (DAP)" },
		{ "<leader>ts", "Summary panel" },
		{ "<leader>to / tO", "Show output / panel" },
		{ "<leader>tx", "Stop" },
	},
	{
		"Search & Replace",
		{ "<leader>Sp", "Spectre panel (toggle)" },
		{ "<leader>Sw", "Search current word" },
		{ "<leader>Sc", "Search current file" },
		{ "<leader>Sr", "Search selection (v)" },
	},
	{
		"Folds (ufo)",
		{ "zR / zM", "Open / close all folds" },
		{ "zK", "Peek fold / hover" },
		{ "za / zc", "Toggle / close (native)" },
	},
	{
		"Text objects & Surround",
		{ "a/i + w b q p", "word / bracket / quote / para" },
		{ "a/i + f c o", "func / class / block (TS)" },
		{ "gsa / gsd / gsr", "Surround add / del / replace" },
		{ "gsf / gsF", "Find surround right / left" },
		{ "]f / [f", "Next / prev function" },
		{ "]a / [a", "Next / prev argument" },
		{ "<leader>j", "Split / join block (treesj)" },
	},
	{
		"Sessions",
		{ "<leader>qs", "Restore (this dir)" },
		{ "<leader>ql", "Restore last session" },
		{ "<leader>qd", "Stop saving session" },
	},
	{
		"UI & Toggles",
		{ "<leader>e", "File tree (nvim-tree)" },
		{ "-", "Parent dir (oil)" },
		{ "<leader>z", "Zen mode" },
		{ "<leader>U", "Undotree" },
		{ "<leader>um", "Markdown render" },
		{ "<leader>uD / uF", "Database UI / find buffer" },
	},
	{
		"Packages",
		{ "<leader>ns", "npm: show versions" },
		{ "<leader>nu / nd", "npm: update / delete" },
		{ "<leader>ni / nc", "npm: install / change ver" },
		{ "Cargo.toml", "crates.nvim inline versions" },
	},
}

-- ── rendering ────────────────────────────────────────────────────────────────────────────────
-- Layout is a simple masonry: cards are packed one at a time into whichever column is currently
-- shortest, so the panel stays roughly rectangular regardless of how many cards / how tall each is.

local CARD_W = 32 -- inner text width of a card, in display cells
local GUTTER = 3 -- blank cells between columns
local MARGIN = 2 -- blank cells inside the window border, left/right

local HL = {
	title = "GerrrtCheatTitle",
	rule = "GerrrtCheatRule",
	key = "GerrrtCheatKey",
	sep = "GerrrtCheatSep",
	footer = "GerrrtCheatFooter",
}

local function define_highlights()
	-- default = true so a user's colorscheme / overrides always win. Linked to semantic groups
	-- every theme defines, so it inherits tokyonight here and Just Works on a bare box too.
	local set = vim.api.nvim_set_hl
	set(0, HL.title, { link = "Title", default = true })
	set(0, HL.key, { link = "Constant", default = true })
	set(0, HL.rule, { link = "Comment", default = true })
	set(0, HL.sep, { link = "Comment", default = true })
	set(0, HL.footer, { link = "Comment", default = true })
end

-- Build one card into an array of "rich lines" ({ text = str, hls = { {s,e,hl}, ... } }) where s/e
-- are BYTE offsets local to that line. Multibyte (the ─ rule) is fine because everything downstream
-- measures with #str (bytes) for offsets and strdisplaywidth() for padding.
local function build_card(section)
	local lines = {}
	local function rich(text, hls)
		table.insert(lines, { text = text, hls = hls or {} })
	end

	-- widest key column, so descriptions align within the card
	local keyw = 0
	for i = 2, #section do
		keyw = math.max(keyw, vim.fn.strdisplaywidth(section[i][1]))
	end
	keyw = math.min(keyw, CARD_W - 6) -- never let keys eat the whole card

	rich(section[1], { { s = 0, e = #section[1], hl = HL.title } })
	local rule = string.rep("─", CARD_W)
	rich(rule, { { s = 0, e = #rule, hl = HL.rule } })

	for i = 2, #section do
		local key, desc = section[i][1], section[i][2]
		local kw = vim.fn.strdisplaywidth(key)
		local keycell = key .. string.rep(" ", math.max(1, keyw - kw + 2))
		-- truncate desc so key + desc never overflows the card
		local avail = CARD_W - vim.fn.strdisplaywidth(keycell)
		if vim.fn.strdisplaywidth(desc) > avail and avail > 1 then
			desc = vim.fn.strcharpart(desc, 0, avail - 1) .. "…"
		end
		local text = keycell .. desc
		rich(text, { { s = 0, e = #keycell, hl = HL.key } })
	end

	rich("", {}) -- trailing spacer row between stacked cards
	return lines
end

-- Pack cards into `ncol` columns, shortest-first. Returns the columns (each a list of rich lines)
-- and the tallest column height.
local function pack(cards, ncol)
	local cols, heights = {}, {}
	for c = 1, ncol do
		cols[c], heights[c] = {}, 0
	end
	for _, card in ipairs(cards) do
		-- pick the currently shortest column (ties → leftmost, so reading order stays natural)
		local target = 1
		for c = 2, ncol do
			if heights[c] < heights[target] then
				target = c
			end
		end
		for _, line in ipairs(card) do
			table.insert(cols[target], line)
		end
		heights[target] = heights[target] + #card
	end
	local tallest = 0
	for c = 1, ncol do
		tallest = math.max(tallest, heights[c])
	end
	return cols, tallest
end

-- Merge the packed columns into flat buffer lines + a flat highlight list (0-indexed rows, byte
-- cols) ready for nvim_buf_set_lines / nvim_buf_add_highlight.
local function compose(cols, height)
	local ncol = #cols
	local out_lines, out_hls = {}, {}
	for row = 1, height do
		local line = { text = "", hls = {} }
		local function padto(dispcol)
			local cur = vim.fn.strdisplaywidth(line.text)
			if cur < dispcol then
				line.text = line.text .. string.rep(" ", dispcol - cur)
			end
		end
		for c = 1, ncol do
			padto(MARGIN + (c - 1) * (CARD_W + GUTTER))
			local cell = cols[c][row]
			if cell then
				local base = #line.text -- byte offset where this cell starts
				for _, h in ipairs(cell.hls) do
					table.insert(line.hls, { s = base + h.s, e = base + h.e, hl = h.hl })
				end
				line.text = line.text .. cell.text
			end
		end
		table.insert(out_lines, line.text)
		for _, h in ipairs(line.hls) do
			table.insert(out_hls, { row = row - 1, s = h.s, e = h.e, hl = h.hl })
		end
	end
	return out_lines, out_hls
end

function M.open()
	define_highlights()

	-- decide column count from available width
	local max_w = math.floor(vim.o.columns * 0.92)
	local ncol = math.max(1, math.floor((max_w - MARGIN * 2 + GUTTER) / (CARD_W + GUTTER)))
	ncol = math.min(ncol, #M.sections)

	local cards = {}
	for _, s in ipairs(M.sections) do
		table.insert(cards, build_card(s))
	end

	local cols, tallest = pack(cards, ncol)
	local lines, hls = compose(cols, tallest)

	local content_w = MARGIN * 2 + ncol * CARD_W + (ncol - 1) * GUTTER
	local footer = "q / <Esc> close   •   <C-d> / <C-u> scroll"
	table.insert(lines, "")
	table.insert(lines, string.rep(" ", MARGIN) .. footer)
	table.insert(hls, { row = #lines - 1, s = MARGIN, e = MARGIN + #footer, hl = HL.footer })

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	local ns = vim.api.nvim_create_namespace("gerrrt_cheatsheet")
	for _, h in ipairs(hls) do
		vim.api.nvim_buf_add_highlight(buf, ns, h.hl, h.row, h.s, h.e)
	end
	vim.bo[buf].modifiable = false
	vim.bo[buf].filetype = "cheatsheet"
	vim.bo[buf].bufhidden = "wipe"

	-- The rounded border adds a cell on every side, so the *outer* window is width+2 × height+2.
	-- Clamp the inner size to columns-4 / lines-4 (border + a 1-cell margin) so nvim_open_win can
	-- never be asked for a float larger than the grid — which would error on a very small terminal.
	local width = math.max(1, math.min(content_w, vim.o.columns - 4))
	local height = math.max(1, math.min(#lines, math.floor(vim.o.lines * 0.9), vim.o.lines - 4))
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		style = "minimal",
		border = "rounded",
		title = "  gerrrt • cheatsheet ",
		title_pos = "center",
	})
	vim.wo[win].wrap = false
	vim.wo[win].cursorline = false

	-- close keys — the buffer wipes on hide, so just close the window
	for _, key in ipairs({ "q", "<Esc>" }) do
		vim.keymap.set("n", key, function()
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end, { buffer = buf, nowait = true, silent = true })
	end
end

return M
