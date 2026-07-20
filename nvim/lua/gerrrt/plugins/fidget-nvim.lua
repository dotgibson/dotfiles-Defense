-- ================================================================================================
-- TITLE : fidget.nvim | LSP progress spinner (bottom-right)
-- LINKS : https://github.com/j-hui/fidget.nvim
-- ABOUT : Shows live "$/progress" notifications from your language servers — indexing, analysis,
--         formatting — as an unobtrusive bottom-right feed. Fills the one gap mini.notify leaves:
--         it has no LSP-progress handler.
-- COEXIST: deliberately leaves vim.notify ALONE (override_vim_notify = false, the default) so it
--          does NOT clash with mini.notify (mini-nvim.lua), which owns your toasts. Only the
--          `progress` half of fidget is used here; the `notification` backend stays passive.
-- LAZY  : event = LspAttach — it can't possibly have anything to show before a server attaches,
--         so there's no reason to load it any earlier.
-- ================================================================================================
return {
	"j-hui/fidget.nvim",
	event = "LspAttach",
	opts = {
		progress = {
			suppress_on_insert = true, -- don't pop progress while you're typing
			ignore_done_already = true,
		},
		notification = {
			-- keep mini.notify as THE notifier; fidget only renders LSP progress.
			override_vim_notify = false,
			-- winblend 100 is fidget's DEFAULT and is the fully see-through setting; its own docs
			-- (fidget.nvim/lua/fidget/notification/window.lua:33-49) call anything under 100 the
			-- blend-with-whatever-is-underneath case and "usually not desirable". The old comment
			-- here ("match your transparent floats") had that backwards — 0 is the OPAQUE end.
			-- Practically invisible either way under tokyonight (normal_hl = "Comment" carries no
			-- bg), so keep the default rather than move away from it for a stated reason that was
			-- the reverse of the truth.
			window = { winblend = 100 },
		},
	},
}
