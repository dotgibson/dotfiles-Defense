-- ================================================================================================
-- TITLE : nvim-tree.lua | file explorer
-- LINKS : https://github.com/nvim-tree/nvim-tree.lua
-- NOTE  : Lazy-loads on its commands / <leader>e. netrw is disabled in config/globals.lua so
--         nvim-tree fully owns file exploration. The toggle keymap (which also closes Zen mode
--         if it's open) lives here so it can lazy-load the plugin — it can't from keymaps.lua.
-- NETRW : Two pieces make nvim-tree appear *instead of* an empty directory buffer:
--           1. hijack_netrw + hijack_directories below — covers `:edit some/dir` after startup.
--           2. the `init` block — force-loads + opens the tree when nvim is launched ON a
--              directory (`nvim .`, `nvim ~/proj`). Without it, the tree isn't loaded yet at
--              VimEnter, so there's nothing to take over the directory buffer. Normal file
--              edits stay lazy (the tree only loads on <leader>e or its commands).
-- ================================================================================================
return {
	"nvim-tree/nvim-tree.lua",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	cmd = { "NvimTreeToggle", "NvimTreeOpen", "NvimTreeFocus", "NvimTreeFindFile", "NvimTreeCollapse" },
	keys = {
		{
			"<leader>e",
			function()
				local ok, zen = pcall(require, "zen-mode.view")
				if ok and zen.is_open() then
					require("zen-mode").close()
				end
				local api = require("nvim-tree.api")
				if api.tree.is_visible() then
					api.tree.close()
				else
					api.tree.open()
				end
			end,
			desc = "Toggle NvimTree (closes Zen if active)",
		},
	},
	init = function()
		-- Launched on a directory? cd into it (project-style) and open the tree once nvim is ready.
		local argv = vim.fn.argv()
		if #argv == 1 and vim.fn.isdirectory(argv[1]) == 1 then
			local dir = argv[1]
			vim.api.nvim_create_autocmd("VimEnter", {
				once = true,
				callback = function()
					vim.api.nvim_set_current_dir(dir)
					require("nvim-tree.api").tree.open()
				end,
			})
		end
	end,
	config = function()
		require("nvim-tree").setup({
			hijack_netrw = true, -- take over netrw-style directory buffers
			hijack_directories = { -- ...including `:edit some/dir` opened after startup
				enable = true,
				auto_open = true,
			},
			filters = { dotfiles = false },
			-- `width = {}` is the current spelling of the old `adaptive_size = true` (a 2023-01-15
			-- legacy key). nvim-tree still accepts the old name but silently rewrites it
			-- (nvim-tree.lua/lua/nvim-tree/legacy.lua:73-81): with no explicit width it produces
			-- `width = { min = nil }`, i.e. exactly `{}`. Verified equivalent by running the
			-- migration: `{ adaptive_size = true }` and `{ width = {} }` compare deep-equal.
			-- An empty width table does NOT mean "unbounded": nvim-tree fills in its own defaults
			-- for the absent keys (view-state.lua:5-6,77-78) — `width.min or DEFAULT_MIN_WIDTH` (30)
			-- and `width.max or DEFAULT_MAX_WIDTH` (-1, i.e. no cap). So the pane sizes to its
			-- content but never narrower than 30 columns. Set `{ min = N }` / `{ max = N }` to
			-- change either bound.
			view = { width = {} },
		})
	end,
}
