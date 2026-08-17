-- ================================================================================================
-- .luacheckrc — Luacheck configuration for this Neovim config
-- Lives at the config root so luacheck (run by nvim-lint on lua files) discovers it by
-- searching upward. This is what stops the false "accessing undefined variable vim" warnings.
-- ================================================================================================

-- NOTE: Neovim sets filetype=lua for .luacheckrc, so lua_ls (the LSP) attaches and analyzes this
-- file as if it were a Lua module. It isn't — it's luacheck's config DSL, where std/cache/globals/
-- ignore/etc. are MEANT to be bare top-level globals. Without the next line lua_ls flags each of
-- them as "lowercase-global" ("did you miss `local`?"). We silence that ONE diagnostic for THIS
-- file only. Do NOT disable lowercase-global globally in servers/lua_ls.lua — it's a real catch
-- for accidental globals in your actual gerrrt.* modules.
---@diagnostic disable: lowercase-global

-- Neovim embeds LuaJIT
std = "luajit"

cache = true

-- Neovim injects `vim` as a global; allow reading and writing vim.* fields.
globals = { "vim" }

-- Let stylua / your colorcolumn own line width — don't double-warn on it.
max_line_length = false

ignore = {
	"212", -- unused argument (very common in callbacks like on_attach(event))
}
