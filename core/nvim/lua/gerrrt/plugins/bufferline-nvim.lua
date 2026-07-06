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
-- ================================================================================================
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
}
