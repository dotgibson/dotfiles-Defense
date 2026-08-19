-- ================================================================================================
-- TITLE : undotree | visualise & navigate the persistent undo history
-- LINKS : https://github.com/mbbill/undotree
-- ABOUT : You already run `undofile = true` (options.lua) with a dedicated undodir, so every buffer
--         carries a full, persistent undo TREE — not just a linear stack. undotree exposes it: a
--         side panel showing every branch, with diffs of each state, so you can recover an edit you
--         "undid past" days ago. The natural companion to persistent undo you weren't surfacing yet.
-- LAZY  : cmd + a single `<leader>U` toggle (capital U so it doesn't shadow the `<leader>u`
--         ui/toggles which-key group). Loads only when you open it.
-- ================================================================================================
return {
	"mbbill/undotree",
	cmd = { "UndotreeToggle", "UndotreeShow", "UndotreeFocus" },
	keys = {
		{ "<leader>U", "<cmd>UndotreeToggle<cr>", desc = "Toggle Undotree" },
	},
	init = function()
		vim.g.undotree_WindowLayout = 2 -- tree on the left, diff along the bottom
		vim.g.undotree_SetFocusWhenToggle = 1 -- jump into the panel on open
	end,
}
