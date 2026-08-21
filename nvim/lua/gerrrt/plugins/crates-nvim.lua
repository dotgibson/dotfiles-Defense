-- ================================================================================================
-- TITLE : crates.nvim | Cargo.toml dependency intelligence
-- LINKS : https://github.com/saecki/crates.nvim
-- ABOUT : You run a full Rust stack (rustaceanvim.lua, taplo for TOML). crates.nvim completes the
--         loop on Cargo.toml itself: inline virtual text showing the latest version of each crate,
--         completion of crate names/versions/features (wired through your blink.cmp via its LSP
--         source), and hover/popups for available versions, features and the crate's docs.
-- LAZY  : event = "BufRead Cargo.toml" — it only ever needs to exist in a Cargo manifest, so it
--         costs nothing elsewhere. The `lsp` block lets it ride your existing completion engine
--         instead of registering a competing source.
-- ================================================================================================
return {
	"saecki/crates.nvim",
	event = { "BufRead Cargo.toml" },
	dependencies = { "nvim-lua/plenary.nvim" },
	opts = {
		completion = {
			crates = { enabled = true },
		},
		lsp = {
			enabled = true,
			actions = true,
			completion = true,
			hover = true,
		},
	},
}
