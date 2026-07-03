-- ================================================================================================
-- TITLE: NeoVim keymaps
-- ABOUT: global, non-plugin quality-of-life keymaps
-- NOTE : Window MOVEMENT (<C-h/j/k/l>) is intentionally NOT here — vim-tmux-navigator owns those
--        keys and moves seamlessly between nvim splits and tmux panes. Line moving (<A-h/j/k/l>)
--        is owned by mini.move. BUFFER keymaps (cycle/pick/move/pin/close) now live in the
--        bufferline spec (plugins/bufferline-nvim.lua) so they lazy-load the visual line on first
--        use — same philosophy. All three were duplicated here before and the plugins silently won.
-- ================================================================================================

-- Quick config editing
vim.keymap.set("n", "<leader>rc", "<Cmd>e ~/.config/nvim/init.lua<CR>", { desc = "Edit config" })

-- Cheatsheet — the full-panel counterpart to which-key. which-key answers "I pressed <leader>,
-- now what?"; this lays out EVERY curated binding at once so you can rediscover what the config
-- actually gives you. `<leader>?` shadows which-key's old buffer-local-keys binding on purpose:
-- the whole map is the more useful thing to have on the mnemonic key. Also exposed as
-- :Cheatsheet / :Cheat. `require` is deferred so it costs nothing at startup — the module only
-- loads on first open. One opener shared by all three entry points so behaviour can never drift
-- between them (and a future option/arg is a single edit).
local function open_cheatsheet()
	require("gerrrt.cheatsheet").open()
end
vim.keymap.set("n", "<leader>?", open_cheatsheet, { desc = "Cheatsheet (all keybindings)" })
vim.api.nvim_create_user_command("Cheatsheet", open_cheatsheet, { desc = "Open the keybinding cheatsheet" })
vim.api.nvim_create_user_command("Cheat", open_cheatsheet, { desc = "Open the keybinding cheatsheet" })

-- Wrap-aware vertical motion
vim.keymap.set("n", "j", function()
	return vim.v.count == 0 and "gj" or "j"
end, { expr = true, silent = true, desc = "Down (wrap-aware)" })
vim.keymap.set("n", "k", function()
	return vim.v.count == 0 and "gk" or "k"
end, { expr = true, silent = true, desc = "Up (wrap-aware)" })

-- Clear search highlight on <Esc> (freed up <leader>c to be the 'code' prefix).
vim.keymap.set("n", "<Esc>", "<Cmd>nohlsearch<CR>", { desc = "Clear search highlights" })

-- Centered search / scroll
vim.keymap.set("n", "n", "nzzzv", { desc = "Next search result (centered)" })
vim.keymap.set("n", "N", "Nzzzv", { desc = "Previous search result (centered)" })
vim.keymap.set("n", "<C-d>", "<C-d>zz", { desc = "Half page down (centered)" })
vim.keymap.set("n", "<C-u>", "<C-u>zz", { desc = "Half page up (centered)" })

-- Black-hole register helpers.
-- (Deliberately not on <leader>x — that's Trouble's prefix now. Plain "_d also works.)
vim.keymap.set("x", "<leader>p", '"_dP', { desc = "Paste without yanking" })
vim.keymap.set({ "n", "v" }, "<leader>D", '"_d', { desc = "Delete without yanking" })

-- Buffers
-- NOTE: buffer keymaps now live in plugins/bufferline-nvim.lua (lazy-loaded on first use):
--         ]b / [b ............. next / previous (in the order shown on the line)
--         <leader>bn / bp ..... same, discoverable under the buffer group
--         <leader>bj .......... pick mode (press the letter shown on a buffer to jump)
--         <leader>bd .......... delete buffer, keep window layout (mini.bufremove)
--         <leader>bP .......... pin / unpin     <leader>bo/br/bh .... close others/right/left
--       Jump-by-number is NOT here — harpoon owns <leader>1-4.

-- Windows / splits
-- NOTE: moving BETWEEN splits is vim-tmux-navigator's <C-h/j/k/l> (it crosses into tmux panes).
vim.keymap.set("n", "<leader>sv", ":vsplit<CR>", { desc = "Split vertically" })
vim.keymap.set("n", "<leader>sh", ":split<CR>", { desc = "Split horizontally" })
vim.keymap.set("n", "<leader>se", "<C-w>=", { desc = "Equalize split sizes" })
vim.keymap.set("n", "<leader>sw", "<C-w>w", { desc = "Cycle to next split" })
vim.keymap.set("n", "<leader>sx", "<C-w>x", { desc = "Swap split positions" })
vim.keymap.set("n", "<leader>sq", "<C-w>q", { desc = "Close current split" })
vim.keymap.set("n", "<leader>so", "<C-w>o", { desc = "Close all OTHER splits" })
vim.keymap.set("n", "<C-Up>", ":resize +2<CR>", { desc = "Increase window height" })
vim.keymap.set("n", "<C-Down>", ":resize -2<CR>", { desc = "Decrease window height" })
vim.keymap.set("n", "<C-Left>", ":vertical resize -2<CR>", { desc = "Decrease window width" })
vim.keymap.set("n", "<C-Right>", ":vertical resize +2<CR>", { desc = "Increase window width" })

-- Tabs
-- NOTE: vim "tabs" are whole window LAYOUTS (think workspaces — e.g. one tab of engagement
--       notes, another of exploit code), NOT one-file-per-tab like other editors. Your per-file
--       visuals are the bufferline up top. Natives still apply: gt / gT cycle tabs, and
--       <C-w>T breaks the current split out into its own tab.
vim.keymap.set("n", "<leader><tab>n", ":tabnew<CR>", { desc = "New tab" })
vim.keymap.set("n", "<leader><tab>d", ":tabclose<CR>", { desc = "Close tab" })
vim.keymap.set("n", "<leader><tab>o", ":tabonly<CR>", { desc = "Close other tabs" })
vim.keymap.set("n", "]<tab>", ":tabnext<CR>", { desc = "Next tab" })
vim.keymap.set("n", "[<tab>", ":tabprevious<CR>", { desc = "Previous tab" })

-- Indent and keep selection
vim.keymap.set("v", "<", "<gv", { desc = "Indent left and reselect" })
vim.keymap.set("v", ">", ">gv", { desc = "Indent right and reselect" })

-- Join lines, keep cursor put
vim.keymap.set("n", "J", "mzJ`z", { desc = "Join lines and keep cursor position" })

-- Copy current file path to system clipboard
vim.keymap.set("n", "<leader>pa", function()
	local path = vim.fn.expand("%:p")
	vim.fn.setreg("+", path)
	print("file:", path)
end, { desc = "Copy full file path" })
