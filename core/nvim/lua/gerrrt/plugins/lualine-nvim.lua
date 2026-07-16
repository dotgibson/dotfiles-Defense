-- ================================================================================================
-- TITLE : lualine.nvim | statusline (NvChad-styled)
-- LINKS : https://github.com/nvim-lualine/lualine.nvim
-- ABOUT : NvChad's block statusline, rebuilt as a STANDARD lualine config — no NvChad backend,
--         no statusline caching, no managed toggle state. Just lualine's own theming with
--         NvChad's rounded "bubble" separators and section layout:
--           left  : mode (rounded bubble) · git branch · git diff (+~-)
--           center: filename (relative) with modified/readonly markers
--           right : search count · attached LSP servers · diagnostics · filetype · cwd · location
-- LOOK  : the signature NvChad move is the ROUNDED block — half-circle caps  (U+E0B6) and
--          (U+E0B4) instead of powerline arrows, with NO inner component separators so each
--         half reads as one clean run of blocks. Colors come from lualine's tokyonight theme
--         (which sets a bg per section), so this stays readable even under transparency.
-- ICONS : All glyphs are written as \u{XXXX} escapes (Nerd Font private-use codepoints),
--         NOT raw glyphs. Raw glyphs get silently stripped when text passes through tools
--         that don't preserve the private-use area; escapes are plain ASCII in the file and
--         decode to the glyph at runtime, so they survive copy/paste/transfer intact.
--         Each escape is named in a trailing comment. Requires a Nerd Font in your terminal.
--         If any single glyph shows as a box (tofu), your font lacks it — swap that codepoint.
--         Diagnostic glyphs are kept IDENTICAL to utils/diagnostics.lua + bufferline so the
--         gutter, tabline and statusline never disagree (this matters more than matching
--         NvChad's exact glyphs — the NvChad look here is the block styling, not the icons).
-- ================================================================================================
return {
	"nvim-lualine/lualine.nvim",
	event = "VeryLazy",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = function()
		-- Show the language servers attached to the current buffer.
		local function lsp_servers()
			local clients = vim.lsp.get_clients({ bufnr = 0 })
			if #clients == 0 then
				return ""
			end
			local names = {}
			for _, client in ipairs(clients) do
				names[#names + 1] = client.name
			end
			return "\u{f085} " .. table.concat(names, ", ") -- f085 nf-fa-cogs
		end

		-- Current working directory basename — NvChad shows this on the right; it's the fast
		-- "which project am I in" cue that a global statusline otherwise loses.
		local function cwd()
			return "\u{f07c} " .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t") -- f07c nf-fa-folder_open
		end

		require("lualine").setup({
			options = {
				theme = "tokyonight",
				icons_enabled = true,
				globalstatus = true,
				-- NvChad's rounded blocks: half-circle section caps, and NO component separators
				-- (an empty string) so each half is one clean run instead of arrow-chevroned.
				section_separators = { left = "\u{e0b4}", right = "\u{e0b6}" }, -- e0b4  / e0b6
				component_separators = "",
				disabled_filetypes = { statusline = { "NvimTree", "dapui_scopes", "dapui_breakpoints" } },
			},
			sections = {
				lualine_a = {
					-- the outer half-circle cap (e0b6) turns the mode block into NvChad's bubble
					{ "mode", icon = "\u{e62b}", separator = { left = "\u{e0b6}" } }, -- e62b nf-custom-vim, e0b6
					-- Macro recording indicator. showmode=false (options.lua) means the cmdline is the
					-- only native cue that you're recording; this surfaces it in the block instead.
					-- Empty string when not recording, so the component collapses and adds no width.
					{
						function()
							local reg = vim.fn.reg_recording()
							return reg == "" and "" or "\u{f111} REC " .. reg:upper() -- f111 nf-fa-circle
						end,
					},
				},
				lualine_b = {
					{ "branch", icon = "\u{e0a0}" }, -- e0a0 powerline branch
					{
						"diff",
						symbols = {
							added = "\u{f067} ", -- f067 nf-fa-plus
							modified = "\u{f111} ", -- f111 nf-fa-circle
							removed = "\u{f068} ", -- f068 nf-fa-minus
						},
					},
				},
				lualine_c = {
					{
						"filename",
						path = 1, -- relative path
						symbols = {
							modified = " \u{f111}", -- f111 nf-fa-circle (●-style "unsaved" dot)
							readonly = " \u{f023}", -- f023 nf-fa-lock
							unnamed = "[No Name]",
						},
					},
				},
				lualine_x = {
					{ "searchcount" },
					{
						lsp_servers,
						color = { gui = "italic" },
					},
					{
						"diagnostics",
						symbols = {
							error = "\u{f057} ", -- f057 nf-fa-times_circle
							warn = "\u{f071} ", -- f071 nf-fa-exclamation_triangle
							info = "\u{f05a} ", -- f05a nf-fa-info_circle
							hint = "\u{f0eb} ", -- f0eb nf-fa-lightbulb
						},
					},
					{ "filetype" },
				},
				lualine_y = {
					{ cwd },
				},
				lualine_z = {
					-- outer half-circle cap (e0b4) closes the right bubble, mirroring the mode block
					{ "location", icon = "\u{e0a1}", separator = { right = "\u{e0b4}" } }, -- e0a1 line-number, e0b4
				},
			},
			inactive_sections = {
				lualine_c = { { "filename", path = 1 } },
				lualine_x = { "location" },
			},
			extensions = { "nvim-tree", "lazy", "quickfix", "trouble", "mason" },
		})
	end,
}
