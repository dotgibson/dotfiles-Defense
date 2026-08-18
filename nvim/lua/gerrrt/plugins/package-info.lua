-- ================================================================================================
-- TITLE : package-info.nvim | package.json dependency intelligence
-- LINKS : https://github.com/vuki656/package-info.nvim
-- ABOUT : The JS/TS counterpart to crates.nvim. In a package.json it shows each dependency's
--         current vs. latest version as inline virtual text, flags outdated/vulnerable ones, and
--         lets you change/delete/install dependencies without leaving the buffer. You already do
--         TS/JS/Svelte/Vue work (ts_ls, eslint_d, prettierd), so this rounds out the manifest side.
-- LAZY  : event = "BufRead package.json" + keys. Reads versions via your package manager on demand.
-- KEYS  : under a new `<leader>n` (npm) group — ns show · nu update · nd delete · ni install · nc change
-- ================================================================================================
return {
	"vuki656/package-info.nvim",
	dependencies = { "MunifTanjim/nui.nvim" },
	event = { "BufRead package.json" },
	opts = {
		autostart = true,
		hide_up_to_date = false,
	},
	keys = {
		{
			"<leader>ns",
			function()
				require("package-info").show()
			end,
			desc = "Package versions: show",
		},
		{
			"<leader>nu",
			function()
				require("package-info").update()
			end,
			desc = "Package: update under cursor",
		},
		{
			"<leader>nd",
			function()
				require("package-info").delete()
			end,
			desc = "Package: delete under cursor",
		},
		{
			"<leader>ni",
			function()
				require("package-info").install()
			end,
			desc = "Package: install new",
		},
		{
			"<leader>nc",
			function()
				require("package-info").change_version()
			end,
			desc = "Package: change version",
		},
	},
}
