-- ================================================================================================
-- TITLE : bufferline.nvim | the visual buffer line across the top
-- LINKS : https://github.com/akinsho/bufferline.nvim
-- ABOUT : Renders open buffers as IDE-style tabs along the top — this is the "visual" layer you
--         asked for. It is a HEADS-UP DISPLAY, not your primary navigation: jumping stays with
--         harpoon (pinned files on <leader>1-4) and fzf-lua (<leader>fb). bufferline shows you
--         what's open at a glance + which buffers have LSP errors; harpoon is the fast lane.
--
-- THE MODEL (why this is "buffers", not "tabs"):
--   buffer = an open file in memory      window = a viewport onto a buffer (a split)
--   tab    = a whole window LAYOUT        ── other editors collapse "tab == open file"; this
--   line gives you that familiar visual while keeping vim's real model underneath.
--
-- INTEGRATIONS wired below:
--   • nvim-tree offset  — the line indents so it never sits on top of the file explorer.
--   • LSP diagnostics   — per-buffer error/warn counts (you run full LSP, so these are live).
--   • mini.bufremove    — closing a buffer here keeps your window/split layout intact.
--   • tokyonight        — colors come from your theme automatically (needs termguicolors, set).
--
-- KEYMAPS live HERE (lazy-loaded on first use) rather than in keymaps.lua, mirroring how
--   vim-tmux-navigator owns <C-h/j/k/l> and mini.move owns <A-h/j/k/l>. Jump-by-number is
--   deliberately NOT mapped to <leader>1-4 (harpoon owns those) — use <leader>bj pick mode.
--
-- ICONS : diagnostic glyphs use \u{XXXX} escapes (matching utils/diagnostics.lua + lualine) so
--         they survive transfer — raw Nerd-Font private-use glyphs get silently stripped.
-- LOOK  : palette-aware highlights (build_highlights below) push the line toward NvChad's tabufline:
--         the ACTIVE buffer lifts as a subtle raised block (bg = bg_highlight) with a bright accent
--         underline; inactive buffers dim into the transparent bar (bg = NONE, fg = comment). Colors
--         come from tokyonight's resolved palette so they track the theme, computed at load time (in
--         `config`, when tokyonight is guaranteed loaded) rather than at spec-eval — same reasoning
--         as the hand-built lualine theme. pcall-guarded so a fresh box falls back to bufferline's
--         own auto-theming instead of erroring.
-- ================================================================================================

-- Build bufferline's `highlights` from the tokyonight palette. Returns nil on a box where
-- tokyonight hasn't loaded, so setup() falls back to bufferline's colorscheme-derived defaults.
local function build_highlights()
	local ok, c = pcall(function()
		return require("tokyonight.colors").setup({ style = "storm" }) -- mirror plugins/theme.lua
	end)
	if not ok or type(c) ~= "table" then
		return nil
	end
	local none = "NONE"
	local active = { fg = c.fg, bg = c.bg_highlight } -- the raised active-buffer block
	local dim = { fg = c.comment, bg = none } -- inactive, blended into the transparent bar
	return {
		fill = { bg = none },
		background = dim,
		buffer_visible = { fg = c.fg_dark, bg = none },
		-- `sp` set here too: for indicator style="underline" bufferline draws the accent line on the
		-- selected buffer's own highlight using its `sp`, so pin it to the accent explicitly.
		buffer_selected = { fg = c.fg, bg = c.bg_highlight, bold = true, italic = false, sp = c.blue },
		-- thin separators kept hairline-subtle, never heavy dividers
		separator = { fg = c.bg_dark, bg = none },
		separator_visible = { fg = c.bg_dark, bg = none },
		separator_selected = { fg = c.bg_dark, bg = c.bg_highlight },
		-- accent underline under the active buffer (indicator style = "underline"). The underline
		-- color is taken from `sp`, not `fg` — and because setup deep-merges with bufferline's
		-- defaults, an unset `sp` would keep the default and the blue line wouldn't render. Set both.
		indicator_selected = { fg = c.blue, sp = c.blue, bg = c.bg_highlight },
		indicator_visible = { fg = none, bg = none },
		-- unsaved dot: green when active (matches lualine/incline), amber otherwise
		modified = { fg = c.orange, bg = none },
		modified_visible = { fg = c.orange, bg = none },
		modified_selected = { fg = c.green, bg = c.bg_highlight },
		-- per-buffer diagnostic counts track the gutter/statusline colors
		error = { fg = c.red, bg = none },
		error_visible = { fg = c.red, bg = none },
		error_selected = { fg = c.red, bg = c.bg_highlight, bold = true },
		warning = { fg = c.yellow, bg = none },
		warning_visible = { fg = c.yellow, bg = none },
		warning_selected = { fg = c.yellow, bg = c.bg_highlight, bold = true },
		-- tab-mode (mode="tabs") blocks, styled to match the buffer blocks
		tab = dim,
		tab_selected = active,
		tab_separator = { fg = c.bg_dark, bg = none },
		tab_separator_selected = { fg = c.bg_dark, bg = c.bg_highlight },
	}
end

return {
	"akinsho/bufferline.nvim",
	version = "*",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	event = { "BufReadPost", "BufNewFile" },
	keys = {
		-- cycle in the order shown ON THE LINE (not raw :bnext order)
		{ "]b", "<cmd>BufferLineCycleNext<cr>", desc = "Next buffer" },
		{ "[b", "<cmd>BufferLineCyclePrev<cr>", desc = "Previous buffer" },
		{ "<leader>bn", "<cmd>BufferLineCycleNext<cr>", desc = "Next buffer" },
		{ "<leader>bp", "<cmd>BufferLineCyclePrev<cr>", desc = "Previous buffer" },
		-- reorder the buffer under the cursor along the line
		{ "<leader>b,", "<cmd>BufferLineMovePrev<cr>", desc = "Move buffer left" },
		{ "<leader>b.", "<cmd>BufferLineMoveNext<cr>", desc = "Move buffer right" },
		-- jump / pin / prune
		{ "<leader>bj", "<cmd>BufferLinePick<cr>", desc = "Pick buffer (jump)" },
		{ "<leader>bP", "<cmd>BufferLineTogglePin<cr>", desc = "Pin / unpin buffer" },
		{ "<leader>bo", "<cmd>BufferLineCloseOthers<cr>", desc = "Close other buffers" },
		{ "<leader>br", "<cmd>BufferLineCloseRight<cr>", desc = "Close buffers to the right" },
		{ "<leader>bh", "<cmd>BufferLineCloseLeft<cr>", desc = "Close buffers to the left" },
		-- close current buffer, KEEP the window layout (mini.bufremove)
		{
			"<leader>bd",
			function()
				require("mini.bufremove").delete(0, false)
			end,
			desc = "Delete buffer (keep layout)",
		},
	},
	opts = {
		options = {
			mode = "buffers", -- one entry per buffer (set to "tabs" to mirror vim tabpages instead)
			themable = true,
			numbers = "none", -- jump-by-number is harpoon's job; keep the line uncluttered
			indicator = { style = "underline" }, -- subtle; reads cleanly with your transparency
			separator_style = "thin", -- flat rectangular tabs like NvChad's tabufline (no slant)
			modified_icon = "\u{f111}", -- f111 nf-fa-circle (●) — same unsaved dot as lualine/incline
			show_buffer_close_icons = false,
			show_close_icon = false,
			always_show_bufferline = true, -- you like the visual — keep it up even at 1 buffer
			diagnostics = "nvim_lsp",
			diagnostics_indicator = function(_, _, diag)
				local icons = { error = "\u{f057}", warning = "\u{f071}" } -- f057 times_circle, f071 triangle
				local parts = {}
				if diag.error then
					parts[#parts + 1] = icons.error .. " " .. diag.error
				end
				if diag.warning then
					parts[#parts + 1] = icons.warning .. " " .. diag.warning
				end
				return #parts > 0 and (" " .. table.concat(parts, " ")) or ""
			end,
			-- closing via the line should also keep your layout intact
			close_command = function(n)
				require("mini.bufremove").delete(n, false)
			end,
			right_mouse_command = function(n)
				require("mini.bufremove").delete(n, false)
			end,
			-- keep the line clear of the nvim-tree panel
			offsets = {
				{
					filetype = "NvimTree",
					text = "File Explorer",
					text_align = "center",
					separator = true,
				},
			},
			hover = { enabled = true, delay = 150, reveal = { "close" } },
		},
	},
	config = function(_, opts)
		-- Attach the palette-aware highlights (nil on a fresh box → bufferline uses its own
		-- colorscheme defaults) and hand the merged table to setup. Kept in `config` rather than
		-- `opts` so build_highlights() runs at bufferline load, when tokyonight is loaded.
		opts.highlights = build_highlights()
		require("bufferline").setup(opts)
	end,
}
