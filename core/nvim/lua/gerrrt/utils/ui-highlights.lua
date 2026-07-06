-- ================================================================================================
-- TITLE : ui-highlights | NvChad-flavored highlight overrides
-- ABOUT : The "clean up the chrome" layer of the NvChad look — hairline window splits, minimal
--         rounded floating windows, and a finder/completion palette that reads as one system.
--         This is deliberately a FLAT table of `nvim_set_hl`-style overrides, not a helper
--         framework: one function, one pass, no nested state.
-- WHY HERE (not a ColorScheme autocmd): tokyonight calls `on_highlights(hl, c)` on every
--         `:colorscheme`, so routing through it (see plugins/theme.lua) makes these overrides
--         RELOAD-SAFE and PALETTE-AWARE for free — `c` is tokyonight's already-resolved palette,
--         so swapping `style`/theme recolors everything below without touching this file.
--         Mutating the `hl` table is exactly how tokyonight wants overrides applied; any key
--         added here (incl. plugin groups like FzfLua*/BlinkCmp*) is passed to nvim_set_hl.
-- TRANSPARENCY: theme.lua runs `transparent = true`, so backgrounds are `NONE` throughout —
--         borders are TINTED, never boxed, which is the core of NvChad's minimal float look.
-- ================================================================================================
local M = {}

-- hl : tokyonight's highlights table (mutate in place)
-- c  : tokyonight's resolved color palette (bg_visual, border, blue, ...)
function M.apply(hl, c)
	local none = "NONE"

	-- ── carried over from the previous inline on_highlights ─────────────────────────────────
	hl.Visual = { bg = c.bg_visual }
	hl.Comment = { fg = c.comment, italic = true }

	-- ── window splits: one soft hairline instead of a heavy divider ──────────────────────────
	hl.WinSeparator = { fg = c.border, bg = none }
	hl.VertSplit = { fg = c.border, bg = none }

	-- ── floating windows: minimal, rounded, border-tinted (LSP hover, diagnostics, :help) ────
	hl.NormalFloat = { bg = none }
	hl.FloatBorder = { fg = c.border_highlight, bg = none }
	hl.FloatTitle = { fg = c.blue, bg = none, bold = true }

	-- ── fzf-lua: NvChad's minimal finder — border tint = accent, titles = accents, no boxes ──
	hl.FzfLuaNormal = { bg = none }
	hl.FzfLuaBorder = { fg = c.border_highlight, bg = none }
	hl.FzfLuaTitle = { fg = c.blue, bg = none, bold = true }
	hl.FzfLuaPreviewNormal = { bg = none }
	hl.FzfLuaPreviewBorder = { fg = c.border_highlight, bg = none }
	hl.FzfLuaPreviewTitle = { fg = c.purple, bg = none, bold = true }
	hl.FzfLuaCursorLine = { bg = c.bg_highlight, bold = true }
	hl.FzfLuaCursorLineNr = { fg = c.blue }
	hl.FzfLuaHeaderText = { fg = c.red }
	hl.FzfLuaHeaderBind = { fg = c.yellow }
	hl.FzfLuaScrollBorderFull = { fg = c.border_highlight }
	hl.FzfLuaScrollBorderEmpty = { fg = c.fg_gutter }

	-- ── blink.cmp: rounded menu + docs float that match the floats above ─────────────────────
	hl.BlinkCmpMenu = { bg = none }
	hl.BlinkCmpMenuBorder = { fg = c.border_highlight, bg = none }
	hl.BlinkCmpDoc = { bg = none }
	hl.BlinkCmpDocBorder = { fg = c.border_highlight, bg = none }
	hl.BlinkCmpSignatureHelp = { bg = none }
	hl.BlinkCmpSignatureHelpBorder = { fg = c.border_highlight, bg = none }
	hl.BlinkCmpLabelMatch = { fg = c.blue, bold = true }

	-- ── gutter: NvChad's dim line numbers with a bright, obvious current line ────────────────
	hl.LineNr = { fg = c.fg_gutter }
	hl.CursorLineNr = { fg = c.orange, bold = true }
end

return M
