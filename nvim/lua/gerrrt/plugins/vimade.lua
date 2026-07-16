-- ================================================================================================
-- TITLE : vimade | dim inactive windows for split focus
-- LINKS : https://github.com/tadaa/vimade
-- ABOUT : You run globalstatus=true and a split-heavy workflow (vim-tmux-navigator, <leader>sv/sh),
--         which leaves no cue for WHICH split is live. incline (plugins/incline-nvim.lua) labels each
--         window with its filename; vimade completes the picture by fading the INACTIVE windows so
--         the focused split pops. Paired with the active-only cursorline autocmd (config/autocmds.lua).
-- THEME : Works under tokyonight transparent=true (theme.lua) — the minimalist recipe fades the
--         FOREGROUND text, it does not rely on painting a background, so transparency is preserved.
-- LAZY  : VeryLazy — purely visual, nothing needs it before first paint.
-- ================================================================================================
return {
	"tadaa/vimade",
	event = "VeryLazy",
	opts = {
		recipe = { "minimalist", { animate = true } },
		-- vimade fades inactive-window highlights TOWARD the background by this amount:
		-- 0.0 = completely faded, 1.0 = not faded at all (upstream default 0.4). 0.6 dims
		-- noticeably while keeping inactive text readable.
		fadelevel = 0.6,
	},
}
