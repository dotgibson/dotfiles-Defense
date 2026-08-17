local M = {}

-- Diagnostic gutter signs. Written as \u{XXXX} escapes (Nerd Font codepoints) so
-- the glyphs survive copy/paste — raw private-use glyphs get silently stripped.
-- These match the statusline's diagnostic icons (lualine) for a consistent look.
local diagnostic_signs = {
	Error = "\u{f057}", -- f057 nf-fa-times_circle
	Warn = "\u{f071}", -- f071 nf-fa-exclamation_triangle
	Hint = "\u{f0eb}", -- f0eb nf-fa-lightbulb
	Info = "\u{f05a}", -- f05a nf-fa-info_circle
}

M.setup = function()
	vim.diagnostic.config({
		signs = {
			text = {
				[vim.diagnostic.severity.ERROR] = diagnostic_signs.Error,
				[vim.diagnostic.severity.WARN] = diagnostic_signs.Warn,
				[vim.diagnostic.severity.INFO] = diagnostic_signs.Info,
				[vim.diagnostic.severity.HINT] = diagnostic_signs.Hint,
			},
		},
		severity_sort = true,
		-- Inline diagnostics. Neovim 0.13 defaults virtual_text/virtual_lines to OFF, so without
		-- this the message text only shows on hover (<leader>cd / float). virtual_text prints a
		-- concise message at end of line; the \u{25cf} (●) prefix is written as an escape so it
		-- survives copy/paste like the other glyphs here. `source` is kept to the float to avoid
		-- cluttering the end-of-line text when several servers attach.
		virtual_text = { spacing = 2, prefix = "\u{25cf}" }, -- 25cf BLACK CIRCLE
		-- The diagnostic float (<leader>cd, and [d/]d jumps) styled to match the LSP hover/signature
		-- cards: rounded border (also the global winborder), no "Diagnostics:" header row (the border
		-- is chrome enough), a 2-space prefix so text doesn't kiss the border, and a width cap so a
		-- long multi-server message wraps into a tidy padded box instead of a full-width strip.
		float = {
			border = "rounded",
			source = true,
			header = "",
			prefix = "  ",
			max_width = 80,
		},
	})
end

return M
