-- ================================================================================================
-- TITLE : palette | single source of truth for the active theme's colors
-- ABOUT : Every UI module that hand-paints its own chrome (lualine, bufferline, cheatsheet) needs
--         tokyonight's RESOLVED palette. Before this module each one re-called
--         `require("tokyonight.colors").setup({ style = "storm" })` inline — duplicating both the
--         pcall dance AND the "storm" string across four files, so a style swap meant four edits.
--         This centralizes both: change M.style here (and the mirror in plugins/theme.lua) and the
--         whole hand-painted UI follows.
-- SEMANTIC MAP : M.nvchad() re-expresses the palette in NvChad's base_30 vocabulary (black / black2,
--         statusline_bg, lightbg, nord_blue, dark_purple, ...) so the block/pill styling can be
--         written the way NvChad documents it while still tracking whatever `style` is active.
-- FRESH BOX : every getter is pcall-guarded and returns nil when tokyonight hasn't loaded, so
--         callers degrade to their plugin's own defaults instead of erroring — Core stays bootable
--         on a bare machine (same contract the inline calls had).
-- ================================================================================================
local M = {}

-- The active tokyonight style. Mirrors `style` in plugins/theme.lua — keep the two in sync.
M.style = "storm"

-- Resolve tokyonight's palette for M.style. Returns the raw color table, or nil on a box where
-- tokyonight isn't installed/loaded yet. Deliberately NOT cached: the table is cheap to rebuild and
-- staying un-cached keeps it correct if the colorscheme is ever reloaded at runtime.
function M.colors()
	local ok, c = pcall(function()
		return require("tokyonight.colors").setup({ style = M.style })
	end)
	if ok and type(c) == "table" then
		return c
	end
	return nil
end

-- NvChad base_30-style semantic names mapped onto the resolved palette. Returns nil when the
-- palette is unavailable. Surfaces run darkest → raised (darker_black → black → black2 → one_bg*);
-- accents keep NvChad's own names so block styling reads like NvChad's docs.
--
-- HYBRID NOTE : theme.lua runs transparent=true, so the EDITOR stays see-through. The bars that go
--         opaque in the hybrid look (statusline / tabline) use black2 = the darkest solid tint, with
--         the active block lifting to one_bg (lighter) so it reads as raised off the bar.
function M.nvchad()
	local c = M.colors()
	if not c then
		return nil
	end
	return {
		-- surfaces, darkest → raised
		darker_black = c.bg_dark,
		black = c.bg,
		black2 = c.bg_dark, -- the solid tabline/statusline bar (opaque, not NONE)
		one_bg = c.bg_highlight, -- raised block (active buffer body / pill body)
		one_bg2 = c.fg_gutter,
		one_bg3 = c.terminal_black or c.fg_gutter,
		statusline_bg = c.bg_dark,
		lightbg = c.bg_highlight,
		-- text / neutrals
		white = c.fg,
		light_grey = c.fg_dark,
		grey = c.comment,
		line = c.border,
		-- accents (NvChad name → tokyonight)
		red = c.red,
		green = c.green,
		blue = c.blue,
		nord_blue = c.blue,
		yellow = c.yellow,
		orange = c.orange,
		purple = c.purple,
		magenta = c.magenta,
		dark_purple = c.magenta, -- NvChad's Insert-mode accent is purple
		teal = c.teal,
		cyan = c.cyan,
	}
end

return M
