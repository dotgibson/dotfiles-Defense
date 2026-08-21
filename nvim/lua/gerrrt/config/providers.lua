-- nvim/lua/gerrrt/config/providers.lua
-- ─────────────────────────────────────────────────────────────────────────────
-- Disable the language "providers" you don't use. Neovim's perl/ruby/node/python
-- providers exist only for a small set of legacy remote plugins; disabling an
-- unused one is the CORRECT, intentional way to clear its :checkhealth warning —
-- not a workaround. It also makes startup marginally faster (no probe spawn).
-- ─────────────────────────────────────────────────────────────────────────────

vim.g.loaded_perl_provider = 0 -- almost never needed
vim.g.loaded_ruby_provider = 0 -- enable only if some plugin actually needs ruby

-- Node provider: DISABLED, because nothing in this config can reach it.
--   • Its only consumers are remote plugins (node rplugins) — there is no `:node` command and no
--     vimscript/Lua entry point equivalent to py3eval.
--   • config/lazy.lua disables the `rplugin` runtime plugin (the remote-plugin MANIFEST loader),
--     so a remote plugin could not register even if one were installed.
--   • None of the installed plugins ships a remote-plugin manifest, and none references node_host.
-- Leaving it on bought nothing and cost a permanent `:checkhealth` WARNING ("Missing 'neovim' npm
-- package") — the ONLY warning in the whole config. Disabling is the documented, intended way to
-- clear that (vim.provider's own advice line says so), not a workaround.
vim.g.loaded_node_provider = 0

-- Python3 provider: DISABLED too. vimade is the ONLY thing in the tree that mentions python at all,
-- and it never reaches that path on any Neovim this config supports. vimade#SetupRenderer()
-- (vimade/autoload/vimade.vim:30-43) short-circuits to the Lua renderer whenever
-- `renderer == 'auto'` and `supports_lua_renderer`; only the ELSE branch calls SetupPython().
-- supports_lua_renderer is `(nvim_get_hl or nvim__get_hl_defs) and nvim_win_set_hl_ns` (:112), all
-- present since 0.11 — and nvim-treesitter's main branch already hard-requires 0.12 here, so the
-- fallback is unreachable. Confirmed at runtime: renderer=auto, supports_lua_renderer=1,
-- ACTIVE renderer=lua, vimade_python_setup=0, and has_python3 was never even evaluated.
-- Nothing else references py3eval/pynvim (nvim-dap-python spawns debugpy as an external DAP
-- adapter — that is a subprocess, not this provider).
-- Disabling makes the provider cleanup PORTABLE: without it, any fleet machine lacking pynvim keeps
-- emitting the same :checkhealth warning we just removed for node.
vim.g.loaded_python3_provider = 0
