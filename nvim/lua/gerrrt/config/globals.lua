-- Leader keys (set before any plugin loads so <leader> mappings register correctly)
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Disable netrw entirely so nvim-tree owns file exploration. This MUST be set before plugins
-- load — config/lazy.lua requires this file first, which is the earliest safe point. Setting
-- these globals is the method nvim-tree's own docs recommend, and it's what lets nvim-tree
-- hijack a directory you open. (Belt-and-suspenders with the disabled_plugins entry in lazy.lua.)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Fleet "offline" switch. When the environment exports DOTFILES_OFFLINE=1 (the offensive/Kali
-- layer sets it on engagement boxes), Neovim suppresses unattended/background network activity:
--   • lazy.nvim's update checker        — config/lazy.lua
--   • mason-tool-installer run_on_start  — plugins/mason-tool-installer.lua
-- Read once here into a boolean so every consumer just checks `vim.g.dotfiles_offline`. globals
-- is required before lazy.setup, so this is set before any plugin spec/opts/config evaluates.
vim.g.dotfiles_offline = vim.env.DOTFILES_OFFLINE == "1"
