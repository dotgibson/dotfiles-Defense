return function(capabilities)
	vim.lsp.config("bashls", {
		capabilities = capabilities,
		filetypes = { "sh", "bash", "zsh" },
		settings = {
			-- bash-language-server runs shellcheck ITSELF (separate from nvim-lint). shellcheck only
			-- supports sh/bash/dash/ksh, so on a zsh buffer it emits SC1071 ("only supports ...") — the
			-- exact noise nvim-lint (plugins/nvim-lint.lua) and the format-on-save guard deliberately
			-- avoid for zsh. Empty shellcheckPath disables bashls's built-in shellcheck integration so
			-- zsh stays attached (completion/hover) without the phantom diagnostic. sh/bash are linted
			-- by nvim-lint's shellcheck instead, so nothing is lost.
			bashIde = { shellcheckPath = "" },
		},
	})
end
