return {
	cmd = { "nomicfoundation-solidity-language-server", "--stdio" },
	filetypes = { "solidity" },
	-- Native root detection. The old `settings = { rootMarkers = ... }` was a no-op:
	-- `settings` is forwarded to the server, not used by Neovim for root detection, and the
	-- native field is the top-level `root_markers`. `single_file_support` was also a legacy
	-- lspconfig-framework field that native vim.lsp.config ignores. Match Foundry/Hardhat
	-- project layouts, falling back to .git.
	root_markers = { "foundry.toml", "hardhat.config.js", "hardhat.config.ts", "remappings.txt", ".git" },
}
