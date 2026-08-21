-- ================================================================================================
-- TITLE : harpoon (v2) | jump to your pinned files fast
-- LINKS : https://github.com/ThePrimeagen/harpoon/tree/harpoon2
-- NOTE  : Now LAZY-LOADED via `keys` instead of loading at startup. Functionally identical to
--         before (same <leader>ha/hh/hn/hN + <leader>1-4), but harpoon + plenary only load the
--         first time you press one of its keys. lazy.nvim runs `config` (the setup) before it
--         fires the triggering key, so :list() is always ready. `keys` is a function purely so
--         the <leader>1-4 loop stays a loop rather than four copy-pasted entries.
-- ================================================================================================
return {
	"ThePrimeagen/harpoon",
	branch = "harpoon2",
	dependencies = { "nvim-lua/plenary.nvim" },
	keys = function()
		local keys = {
			{
				"<leader>ha",
				function()
					-- Guard the unnamed buffer: harpoon keys its list by file path, so adding a
					-- scratch/[No Name] buffer stored an empty entry AND toasted a bare
					-- "Harpoon: added " (expand("%:t") is "" there). Refuse instead of silently
					-- polluting the list with a slot that can never be navigated back to.
					if vim.api.nvim_buf_get_name(0) == "" then
						vim.notify("Harpoon: buffer has no file to add", vim.log.levels.WARN)
						return
					end
					require("harpoon"):list():add()
					vim.notify("Harpoon: added " .. vim.fn.expand("%:t"), vim.log.levels.INFO)
				end,
				desc = "Harpoon add file",
			},
			{
				"<leader>hh",
				function()
					local harpoon = require("harpoon")
					harpoon.ui:toggle_quick_menu(harpoon:list())
				end,
				desc = "Harpoon menu",
			},
			{
				"<leader>hn",
				function()
					require("harpoon"):list():next()
				end,
				desc = "Harpoon next",
			},
			{
				"<leader>hN",
				function()
					require("harpoon"):list():prev()
				end,
				desc = "Harpoon prev",
			},
		}
		for i = 1, 4 do
			table.insert(keys, {
				"<leader>" .. i,
				function()
					require("harpoon"):list():select(i)
				end,
				desc = "Harpoon file " .. i,
			})
		end
		return keys
	end,
	config = function()
		require("harpoon"):setup({ settings = { save_on_toggle = true, sync_on_ui_close = true } })
	end,
}
