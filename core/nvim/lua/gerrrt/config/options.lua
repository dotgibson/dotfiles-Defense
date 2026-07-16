-- ================================================================================================
-- TITLE : NeoVim options
-- ABOUT : basic settings native to neovim
-- ================================================================================================

-- Basic Settings
vim.opt.number = true -- Line numbers
vim.opt.relativenumber = true -- Relative line numbers
vim.opt.cursorline = true -- Highlight current line
vim.opt.scrolloff = 10 -- Keep 10 lines above/below cursor
vim.opt.sidescrolloff = 8 -- Keep 8 columns left/right of cursor
vim.opt.wrap = false -- Don't wrap lines
vim.opt.cmdheight = 1 -- Command line height
vim.opt.spelllang = { "en", "de" } -- Set language for spellchecking

-- Tabbing / Indentation
vim.opt.tabstop = 2 -- Tab width
vim.opt.shiftwidth = 2 -- Indent width
vim.opt.softtabstop = 2 -- Soft tab stop
vim.opt.expandtab = true -- Use spaces instead of tabs
vim.opt.smartindent = true -- Smart auto-indenting
vim.opt.autoindent = true -- Copy indent from current line
vim.opt.grepprg = "rg --vimgrep" -- Use ripgrep if available
vim.opt.grepformat = "%f:%l:%c:%m" -- filename, line number, column, content

-- Search Settings
vim.opt.ignorecase = true -- Case-insensitive search
vim.opt.smartcase = true -- Case-sensitive if uppercase in search
vim.opt.hlsearch = false -- Don't highlight search results
vim.opt.incsearch = true -- Show matches as you type

-- Visual Settings
vim.opt.termguicolors = true -- Enable 24-bit colors
vim.opt.signcolumn = "yes" -- Always show sign column
vim.opt.colorcolumn = "100" -- Show column at 100 characters
vim.opt.showmatch = true -- Highlight matching brackets
vim.opt.matchtime = 2 -- How long to show matching bracket
vim.opt.completeopt = "menuone,noinsert,noselect" -- Completion options
vim.opt.showmode = false -- Don't show mode in command line
vim.opt.pumheight = 10 -- Popup menu height
vim.opt.pumblend = 10 -- Popup menu transparency
vim.opt.winblend = 0 -- Floating window transparency
-- Global default border for ALL floating windows (LSP hover, signature help, diagnostics
-- floats, etc.). One setting instead of per-plugin `border=` options. (Neovim 0.11+)
-- The diagnostics float already requests "rounded" explicitly in utils/diagnostics.lua;
-- this makes everything else match it for free.
vim.opt.winborder = "rounded"
-- NOTE: conceallevel/concealcursor are set per-filetype in the markdown autocmd
-- (config/autocmds.lua), not globally — concealing in non-markdown buffers can hide
-- characters unexpectedly (e.g. in some JSON/LSP setups).
vim.opt.redrawtime = 10000 -- Timeout for syntax highlighting redraw
vim.opt.maxmempattern = 20000 -- Max memory for pattern matching
vim.opt.synmaxcol = 300 -- Syntax highlighting column limit

-- File Handling
vim.opt.backup = false -- Don't create backup files
vim.opt.writebackup = false -- Don't backup before overwriting
vim.opt.swapfile = false -- Don't create swap files
vim.opt.undofile = true -- Persistent undo
vim.opt.updatetime = 300 -- Time in ms to trigger CursorHold
vim.opt.timeoutlen = 500 -- Time in ms to wait for mapped sequence
vim.opt.ttimeoutlen = 0 -- No wait for key code sequences
vim.opt.autoread = true -- Auto-reload file if changed outside
vim.opt.autowrite = false -- Don't auto-save on some events
vim.opt.diffopt:append("vertical") -- Vertical diff splits
vim.opt.diffopt:append("algorithm:histogram") -- Better diff algorithm (matches gitconfig's diff.algorithm)
vim.opt.diffopt:append("linematch:60") -- Better diff highlighting (smart line matching)

-- Set undo directory and ensure it exists. Derive from Neovim's own state dir
-- (vim.fn.stdpath("state")) rather than a hardcoded ~/.local/share path, so it lands
-- in the right tree under a relocated XDG_STATE_HOME and on non-Linux (macOS) nvim.
local undodir = vim.fn.stdpath("state") .. "/undodir" -- Undo directory path
vim.opt.undodir = vim.fn.expand(undodir) -- Expand to full path
local undodir_path = vim.fn.expand(undodir)
if vim.fn.isdirectory(undodir_path) == 0 then
  vim.fn.mkdir(undodir_path, "p") -- Create if not exists
end

-- Behavior Settings
vim.opt.errorbells = false -- Disable error sounds
vim.opt.backspace = "indent,eol,start" -- Make backspace behave naturally
vim.opt.autochdir = false -- Don't change directory automatically
vim.opt.iskeyword:append("-") -- Treat dash as part of a word
vim.opt.path:append("**") -- Search into subfolders with `gf`
vim.opt.selection = "inclusive" -- Use inclusive selection
vim.opt.mouse = "a" -- Enable mouse support
vim.keymap.set({ "n", "i", "v" }, "<LeftDrag>", "<Nop>", { silent = true })
vim.keymap.set({ "n", "i", "v" }, "<LeftRelease>", "<Nop>", { silent = true })

-- NOTE: system clipboard is handled in clipboard.lua via a custom provider and
-- the "+ register (opt-in). We deliberately do NOT force unnamedplus here, so
-- normal yanks/deletes stay in Neovim's registers (keeps <leader>p sane).
vim.opt.modifiable = true -- Allow editing buffers
-- NOTE: 'encoding' is intentionally NOT set — Neovim's internal encoding is always
-- UTF-8, and setting it post-startup is a no-op at best (a footgun at worst). Manage
-- file encodings via 'fileencoding'/'fileencodings' defaults instead.
vim.opt.wildmenu = true -- Enable command-line completion menu
vim.opt.wildmode = "longest:full,full" -- Completion mode for command-line
vim.opt.wildignorecase = true -- Case-insensitive tab completion in commands

-- Cursor Settings
vim.opt.guicursor = {
  "n-v-c:block", -- Normal, Visual, Command-line
  "i-ci-ve:block", -- Insert, Command-line Insert, Visual-exclusive
  "r-cr:hor20", -- Replace, Command-line Replace
  "o:hor50", -- Operator-pending
  "a:blinkwait700-blinkoff400-blinkon250-Cursor/lCursor", -- All modes: blinking & highlight groups
  "sm:block-blinkwait175-blinkoff150-blinkon175", -- Showmatch mode
}

-- Folding Settings
vim.opt.foldmethod = "expr" -- Use expression for folding
vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()" -- Use treesitter for folding
vim.opt.foldlevel = 99 -- Keep all folds open by default

-- Split Behavior
vim.opt.splitbelow = true -- Horizontal splits open below
vim.opt.splitright = true -- Vertical splits open to the right

-- Project-local config (:h exrc). Loads a per-project `.nvim.lua` / `.exrc` / `.nvimrc` from the
-- cwd, so a repo can carry its own settings without polluting the global config.
--
-- SECURITY: exrc executes code that lives IN the repo you open. On the offensive/Defense layers
-- you open UNTRUSTED repos, so this is a code-execution vector. Two mitigations, both on:
--   • Gated on `not dotfiles_offline` — never enabled on engagement/Kali boxes (same switch that
--     silences the update checker, mason, and the git-fetch toast). See config/globals.lua.
--   • Neovim 0.9+ exrc is trust-gated by vim.secure: an untrusted project file is NOT sourced
--     until you explicitly allow it (:trust), and any edit re-prompts. Legacy blind-source is gone.
-- If even the trusted-on-non-engagement-boxes behaviour is more than you want, set this to false.
vim.opt.exrc = not vim.g.dotfiles_offline
