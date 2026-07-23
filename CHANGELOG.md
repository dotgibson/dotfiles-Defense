# Changelog

All notable changes to **dotfiles-core** are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Core is the single source of truth vendored into eight repos via
`git subtree pull --prefix=core <core-remote> main --squash` (see `scripts/sync-core.sh`).
Every entry below is therefore a change those repos receive on their next sync —
this file is the human-readable record of _what_ a sync will bring, complementing
the SHA that `scripts/sync-core.sh` now prints. To cut a release, move the
`[Unreleased]` items under a new `## [vX.Y.Z] - YYYY-MM-DD` heading and tag the
commit (`git tag -a vX.Y.Z -m vX.Y.Z`).

## [Unreleased]

### Fixed

- **nvim: first file opened in a bare session got no filetype — no syntax/treesitter
  highlighting, no LSP, no linter.** When Neovim started without a file argument
  (dashboard, `nvim` then `:e`, any picker), the first real buffer's `BufReadPost`
  fired `User FilePost` synchronously, loading nvim-lspconfig _inside_ that autocmd
  chain. `vim.lsp.enable()`'s post-startup `doautoall … FileType` replay set Vim's
  global `did_filetype` flag mid-chain, so when the runtime's `filetypedetect`
  handler (registered after ours) reached `:setf`, it was a documented no-op — the
  buffer ended up with an empty filetype and nothing keyed off `FileType` ever ran.
  Every _subsequent_ buffer worked (the FilePost augroup had self-deleted), which is
  why the bug looked like "the first file is dead until I open a second one".
  `nvim <file>` startups were unaffected (FilePost fires at `UIEnter` there, outside
  any read chain). Fix: fire FilePost via `vim.schedule()` so the deferred-plugin
  burst lands after the read chain completes — filetype detection runs unpoisoned,
  and the exactly-once contract is preserved by deleting the augroup _before_
  scheduling. The D3 contract test now also asserts the first file ends up with a
  non-empty filetype, simulating vim.lsp.enable's group-scoped FileType replay in
  the hermetic probe so the poisoning path stays covered (verified red on the
  pre-fix code, green after). (`nvim/lua/gerrrt/config/autocmds.lua`,
  `scripts/test-core.sh`)

## [v4.0.2] - 2026-07-21

### Added

- **`aliases.md` documents the shell functions, not just the aliases.** The cheat sheet
  covered `zsh/20-aliases.zsh`/`25-git.zsh` but said nothing about the user-facing
  functions in `zsh/30-functions.zsh`, deferring them to `core help` — so the one
  reference people actually open omitted nine commands they type daily. New **Shell
  Functions** section covering `mkcd`, `cdup`, `fcd`, `extract`, `mkbak`, `serve`,
  `genpw`, `please`, and `pullall`, plus the `cdup`-vs-`up` naming trap and the
  fail-safe (no-TTY declines) behaviour of the `extract`/`please` confirmations. Each row
  reuses that function's own `_core_help` one-liner verbatim, so the doc and the
  `--help`/`core help` output can't drift apart. Docs only — no behavior change.

### Changed

- **Docs/comments: finish the v4 numbered-fragment rename.** The v4.0.0 rename moved the
  files and updated the manifest/docs but left the pre-v4 flat names (`tools.zsh`,
  `plugins.zsh`, …) scattered through the fragments' own cross-reference comments and a
  few dev scripts. Renumbered them all to the `NN-name.zsh` form — every fragment's
  self-header and every "loads after `10-options.zsh`" / "guarded by `00-tools.zsh`"
  comment across `zsh/*.zsh`, plus `bench-core.sh`, `audit-core.sh`, `update-plugins.sh`,
  `ci.yml`, `lib/ux.sh`, `jujutsu/config.toml`, and others. Deliberately left untouched:
  historical `CHANGELOG.md` entries, `V4-PROPOSAL.md`, and the intentional pre-v4 names in
  the migration path (`bootstrap-lib.sh`'s stale-symlink cleanup, `test-core.sh`'s migration
  fixtures). Also: `aliases.md` gains a **Named Directories** section for the `~dots`/`~proj`
  `hash -d` shortcuts, and `PORTING-MATRIX.md` clarifies that `Defense` is a distro-agnostic
  Role repo (absent from the OS-stamp table by design, not omission). Comment/doc only —
  no behavior change.

### Security

- **`actions/checkout` no longer leaves the job token in `.git/config` on 32 of 35 steps.**
  Checkout persists the token by default, so any later step in the job — a third-party
  linter, a scripted tool, one of the LLM routines reading the tree — can read it back out
  of the working copy. Every checkout in the repo now states `persist-credentials:`
  explicitly: `false` on the 32 that only read code, `true` on the three that genuinely
  push (auto-tag's tag push and the freshness bot's two branch pushes), each carrying a
  comment saying why. The eight `claude-routines` checkouts are the biggest win — those
  jobs run an agent over repository content, so the persisted token was a standing
  exfiltration target alongside the `--allowedTools` restriction already in place. Enforced
  by a new `require_explicit_persist_credentials` dimension in
  `scripts/modern-baseline.yml`; `check-modern.sh` associates each `with:` block with its
  own `uses:` by walking step bounds, so a `persist-credentials:` on a neighbouring step
  cannot satisfy the rule. Requiring the _key_ rather than the _value_ `false` is what
  keeps the pushers' exemptions at the call site instead of in a drift-prone list.
- **CI floor raised: every workflow must declare a top-level `permissions:` block, and the
  node20 opt-out is banned.** Two additions to `scripts/modern-baseline.yml`, both of which
  the fleet already satisfied — this encodes existing practice as a floor rather than asking
  for a migration. (1) New `require_workflow_permissions` dimension: without a top-level
  block a job inherits the repo-wide default token scope, so naming it makes the
  least-privilege grant a deliberate, reviewable line. `check-modern.sh` anchors the match at
  column 0 — a job-level `permissions:` narrows a default, it doesn't establish one — and
  scopes the rule to `.github/workflows/` since the key is invalid in a composite
  `action.yml`. (2) `ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION` joins `banned_patterns`: it
  forces a node20 action to keep running on node20, which stops working outright when node20
  leaves the runners in fall 2026, so it's a dead end worth closing before something lands on
  it. Fleet-wide via the `lint-call.yml@v3` reusable workflow the OS repos inherit.

## [v4.0.1] - 2026-07-20

### Fixed

- **`loader.zsh` profile resolution reads only the first field of `$ZSH_CFG/profile`.**
  A trailing space or stray extra token in the profile one-liner previously landed in
  `CORE_PROFILE` verbatim, so the `case` matched no arm and silently fell through to
  `full`. `read -r CORE_PROFILE _ < …` now takes just the first word (and trims
  surrounding whitespace), so a slightly-malformed one-liner still resolves to the
  intended profile. Also clarified the loader header comment: `CORE_PROFILE` is
  deliberately left in scope after sourcing (so subshells and the user can read the
  active profile), not only the `_cl_*` scratch vars.

## [v4.0.0] - 2026-07-20

### Added

- **`CORE_PROFILE` (`minimal` / `standard` / `full`).** Selects which
  Core-band fragments (`00`–`69`) the loader sources — `minimal` stops after `30-functions`,
  `standard` after `50-op`, `full` loads all Core — so a headless box can skip the
  interactive-heavy stages `minimal` omits: fzf widgets (`35`), vi-mode bindings (`40`), the
  plugin stack (`45` — autosuggestions/syntax-highlighting/carapace/fzf-tab), the 1Password
  helpers (`50`), and the maintenance + update surface (`55`/`60`). (Atuin/history and the
  aliases live in `00`–`30`, so they still load under `minimal`.) It resolves from the
  environment or a `$ZSH_CFG/profile` one-liner, and gates **only** Core fragments;
  OS/role/host fragments (`>=70`) always load, so
  a lean profile never drops essential OS setup or `99-local.zsh`. It is a pure loader
  concern — install-time provisioning selection stays with `bootstrap.sh`'s existing
  `--only`/`--skip` (`blib_want`) groups, so `bootstrap.sh --only zsh` + `CORE_PROFILE=minimal`
  compose orthogonally. Defaults to `full` (today's behaviour).
- **Neovim: debugging via `nvim-dap` + `nvim-dap-python`.** Breakpoints, stepping, and variable
  inspection under a new `<leader>d` which-key group, with palette-aware gutter signs and rows in
  the cheatsheet. Loaded on its keymaps and `Dap*` commands **only** — it costs nothing at startup
  and nothing on file open, not even the `User FilePost` hook. That required turning off
  rustaceanvim's `dap.autoload_configurations` (on by default): it calls `require('dap')` on
  rust-analyzer attach, which lazy.nvim module-autoloads, so merely opening a `.rs` file pulled in
  the whole DAP stack and could kick off background `cargo` work. The tradeoff is explicit — a bare
  `<leader>dc` no longer sees rust-analyzer's debuggables, so Rust sessions start from the new
  `<leader>dR` (`:RustLsp debuggables`), after which the normal `<leader>d*` keys apply.
  `nvim-dap-ui` is deliberately not
  included: `dap.ui.widgets` covers scopes/frames/hover (`<leader>ds`/`df`/`dw`) without the extra
  plugin, its `nvim-nio` dependency, or session-driven window management. The debug adapter is
  resolved most-preferred-first — Mason's `debugpy` if you installed it, then `uv`, then
  `python3`. `debugpy` is deliberately **not** in `ensure_installed`: Mason's PyPI installer always
  runs `python -m venv` then pip, so listing it would fail the install pass on every startup on the
  Debian/Kali and Alpine hosts that lack `python3-venv`/`py3-pip` — the exact dependency the `uv`
  fallback exists to avoid. Install it by hand with `:MasonInstall debugpy` where you want it. Verified end to end on a real session via the `uv` path: breakpoint hit,
  frame `add @ line 2`, locals `a = 2` / `b = 3`.
  This also revives `plugins/rustaceanvim.lua`'s DAP adapter block, which was dead code — it needs
  `nvim-dap` present, and `nvim-dap` was never installed.
- **Neovim: the statusline shows the active Python virtual environment.** A new block left of the
  LSP server list renders the uv/venv name (`.venv`) in Python buffers, resolving
  `VIRTUAL_ENV` → `UV_PROJECT_ENVIRONMENT` → `<project root>/.venv`, probing `pyvenv.cfg` so it is
  correct on every platform. Absolute `UV_PROJECT_ENVIRONMENT` values are detected in all three
  forms — POSIX `/…`, Windows drive-qualified `C:\…`, and UNC `\\server\share` — since a
  leading-`/` test alone would misread the latter two as relative and silently report the wrong env. It walks upward from the buffer, so a file in a subdirectory still
  reports the project's env, and it collapses to nothing outside Python so no width is spent
  elsewhere. The lookup is memoised in `vim.b` — a statusline component is re-evaluated on every
  redraw, so the filesystem walk runs once per buffer, never inline. Display only: it does not
  configure ty, which already discovers `.venv` on its own.

### Removed

- **Neovim: the `matchparen`, `rplugin` and `spellfile` runtime plugins are no longer sourced**, and
  `showmatch` is no longer set. `matchparen` was the costly one: it registers 10 autocmds, three of
  which (`CursorMovedI`, `TextChangedI`, `TextChangedP`) re-scan for a matching bracket on _every
  keystroke_ in insert mode. `showmatch` doubled that from the other side — it does not highlight
  the match, it jumps the cursor to it for `matchtime` tenths of a second every time you type a
  closing bracket. `rplugin` (remote-plugin manifest) is dead weight with the perl/ruby providers
  already off, and `spellfile` auto-downloads spellfiles over the network — unwanted generally and
  wrong on a `DOTFILES_OFFLINE` box. **`%` is unaffected**: `matchit` (extended `%` over
  `if`/`end`, tags, …) and `editorconfig` are deliberately kept, and both the matchit and builtin
  `%` motions were verified identical before and after. What this does give up is the automatic
  highlight of the bracket paired with the one under the cursor — `rainbow-delimiters` colors by
  nesting depth and only where a treesitter parser is installed, so it is a different cue, not a
  replacement. NvChad disables 26 runtime plugins including
  `matchit`; that list is not copied — each entry here carries a stated reason.

### Changed

- **BREAKING (v4.0.0) — loader & layout overhaul.** Core's zsh modules are renamed to
  numbered fragments (`00-tools` … `60-update`), and the loader (`zsh/loader.zsh`) now
  globs `NN-*.zsh` in `$ZSH_CFG`, sorts by the `NN` prefix, and sources each — replacing
  the hand-declared `_CORE_MODULES` name array an OS `.zshrc` used to pass. The `NN`
  prefix is the ordering contract; bands are Core `00`–`69`, OS-native `70`–`84`, role
  `85`–`94`, host-local `95`–`99` (the OS layer is now `80-os.zsh`, a role stage `85-*.zsh`,
  host tweaks `99-local.zsh`). A layer may still place a fragment in a Core gap to run
  mid-chain, but gating and ordering key off the `NN` number, not authorship: a fragment in
  `00`–`69` is profile-gated as Core (number always-load setup `>=70`), and a same-`NN` tie
  breaks lexically by filename. This aligns the zsh module structure with the
  PowerShell host layer's `NN-name` convention (`PARITY.md`). **Every OS/Role repo must
  re-vendor and update its `bootstrap.sh` loader stanza** — `blib_write_zshrc_loader` now
  emits a stanza that simply `source`s `$ZSH_CFG/loader.zsh` (managed marker
  `dotfiles-managed v4`) and takes no module list; it deliberately does **not** assign
  `CORE_PROFILE`, leaving resolution to the loader (env → `$ZSH_CFG/profile` one-liner →
  `full`). `blib_migrate_v4` relocates the pre-v4 layout automatically on re-bootstrap.
  Design + per-repo runbook in `V4-PROPOSAL.md`.
- **BREAKING (v4.0.0) — mutable zsh state moves to XDG dirs.** History
  (`$XDG_STATE_HOME/zsh/history`), the completion dump (`$XDG_CACHE_HOME/zsh/zcompdump`),
  and plugins (`$XDG_DATA_HOME/zsh/plugins`) leave the symlinked `$ZDOTDIR` config tree,
  which now holds config **plus** the byte-compiled `.zwc` wordcode written beside each
  fragment symlink — the one deliberate exception, because that is how zsh's automatic
  wordcode pickup works (`source file` loads `file.zwc` only when it sits beside `file`).
  `bootstrap.sh` (`blib_migrate_v4`) relocates an existing `~/.config/zsh/.zsh_history`,
  `plugins/`, and drops the stale pre-v4 symlinks/compdump on re-bootstrap so nothing is
  lost. Hosts must **re-bootstrap**, not just re-source.
- **Neovim: statusline components now read the statusline's window, not the current one.** With
  `globalstatus = true` one bar is shared by every window, so `bufnr = 0` was subtly wrong whenever
  the bar was redrawn for a window you weren't in. Custom components now resolve through
  `vim.g.statusline_winid` (the discipline NvChad's `stl/utils.lua` uses). The attached-server list
  is also width-gated at 100 columns, since the diagnostic counts beside it carry the actionable
  information on a narrow window.
- **Neovim: LSP server modules are now plain config tables, and the server list exists once.**
  Each `lua/gerrrt/servers/<name>.lua` returned a `function(capabilities)` factory that called
  `vim.lsp.config()` itself; `servers/init.lua` then invoked all 19 by hand and re-listed the same
  19 names in a separate `wanted` table, so every name was written twice. The leaves are now pure
  data, capabilities are advertised once on the `vim.lsp.config("*")` wildcard, and one `servers`
  list drives both registration and enabling. `utils/lsp.lua`'s `with_snippets()` is gone —
  html/cssls set only the `snippetSupport` leaf and inherit the rest via the wildcard deep-merge.
  Verified by diffing the fully-resolved config of all 19 servers before and after: **identical**.
  Note the configs deliberately stay on explicit `vim.lsp.config(name, …)` calls rather than moving
  to `lsp/<name>.lua` on the runtimepath: rtp files are merged in rtp order with the user config dir
  _first_, so nvim-lspconfig's own `lsp/<name>.lua` would override ours (verified — a probe setting
  `cmd = { "PROBE_CMD" }` resolved to `cmd = { "gopls" }`). Explicit calls always win.
  `scripts/test-core.sh` is updated to assert the new contract (a non-empty table, not a function).
- **Neovim: the SchemaStore catalogues are no longer built unconditionally.** `servers/jsonls.lua`
  and `servers/yamlls.lua` resolved `require("schemastore").{json,yaml}.schemas()` inline in their
  `settings`, which ran while the server was being _configured_ — and `servers/init.lua` configures
  all 19 servers in one pass. That pass runs **once per session** (the `User FilePost` loader is
  one-shot), so the cost was not per-buffer; the problem is that it was paid **regardless of
  filetype** — a session that only ever opens Lua files still materialised the entire 1,368-entry
  JSON schema catalogue. Both now resolve it in `before_init`, which Neovim runs once per client
  instance, so the cost lands only when a jsonls/yamlls client actually starts. Verified: a Lua
  buffer no longer loads the `schemastore` module at all, a JSON buffer still gets all 1,368 schemas.
- **Neovim: treesitter's installed-parser lookup is cached.** `get_installed()` walks two install
  directories off disk (~0.19ms) and returns a fresh list; it was called inside the `FileType`
  callback and then scanned linearly, so every buffer open paid a directory walk plus an O(n)
  search. It is now built once into a set and answered by hash lookup, and invalidated on every
  parser mutation — including `:TSInstall`/`:TSUpdate`/`:TSUninstall`, which bypass the plugin's own
  install entry point — so the set can never go stale against what is on disk.
- **Neovim: `lazy.nvim` now defaults specs to `lazy = true`.** Every spec is already covered — most
  declare an `event`/`ft`/`cmd`/`keys` trigger, and the pure-data/dependency specs
  (`webdev-icons.lua`, `schemastore.lua`, the luvit-meta entry in `lazydev-nvim.lua`) declare
  `lazy = true` explicitly and load via `require` or another spec's `dependencies`. So the
  loaded-plugin set is byte-identical before and after (verified, 25 plugins on first file open).
  This is a regression net: a future spec added with neither a trigger nor an explicit `lazy` stays
  lazy instead of silently landing on the startup path.

- **Neovim: file-plugins now load after the UI is ready (`User FilePost`)** — `nvim-lspconfig`,
  `gitsigns`, `nvim-lint` and `todo-comments` hung off `BufReadPre`/`BufReadPost`, which fire
  _before_ Neovim finishes starting. Measured on a real TTY, `BufReadPost` lands at ~44ms while the
  UI isn't ready until ~131ms, so ~87ms of plugin work sat in front of the editor appearing. A new
  self-deleting autocmd in `config/autocmds.lua` emits a `User FilePost` event once startup is done
  and a real file buffer is open, and those four specs now load on it.
  **Opening a file: 165.9ms → 99.0ms (-40%).** Bare `nvim` is unchanged (~37ms).
  The event waits for `UIEnter` when a UI exists, and falls back to `VimEnter` only when there is
  genuinely no UI (`nvim --headless`), where `UIEnter` never fires — gating on `UIEnter` alone (as
  NvChad does) would silently disable LSP, linting and git signs in every headless/CI session,
  including this repo's own audit, while accepting `VimEnter` in a TTY would fire ~5ms early and pull
  the plugins back in front of the first paint. `scripts/test-core.sh` asserts the exactly-once
  contract in both startup shapes. No `FileType` replay is needed; each of the
  four self-attaches to already-open buffers (`vim.lsp.enable()` re-runs `doautoall`, gitsigns
  iterates `nvim_list_bufs()`, todo-comments attaches to visible windows, nvim-lint is write-driven).

### Fixed

- **Neovim: focusing the file tree blanked the whole statusline.** `plugins/lualine-nvim.lua` set
  both `disabled_filetypes = { statusline = { "NvimTree" } }` and `extensions = { "nvim-tree", … }`.
  lualine evaluates `disabled_filetypes` and returns `nil` **before** it consults extensions
  (`lualine.nvim/lua/lualine.lua:298-306`), so the `nvim-tree` extension was permanently unreachable
  — and because `globalstatus = true` means one shared bar, that `nil` blanked the statusline for
  _every_ window whenever the tree held focus. Dropped the disable and kept the extension. Verified:
  with `ft=NvimTree` focused, `lualine.statusline()` returned `nil` before, renders 81 cells now.
- **Neovim: visual-mode git staging silently staged the entire hunk.** `<leader>gs` / `<leader>gr`
  were mapped in `{ "n", "v" }` to bare `gs.stage_hunk` / `gs.reset_hunk`. `range` is the **first**
  parameter of both (`gitsigns.nvim/lua/gitsigns/actions.lua:288`, `:376`) and a Lua keymap rhs is
  invoked with no arguments, so `range` was always `nil` — partial-hunk staging, the only reason to
  map visual mode, never happened. (Nothing reads the visual selection implicitly; only the
  `:Gitsigns` command wrapper populates `range`, from command modifiers.) Normal and visual are now
  separate mappings, with the visual pair passing `{ line("."), line("v") }` — upstream's documented
  form — and bound to `x` rather than `v` so they do not also fire in select-mode. Verified end to
  end in a real repo: staging lines 2-3 of a 3-line hunk staged exactly those two.
- **Neovim: the Node.js and python3 providers are disabled, clearing the config's only health
  warning.** The node provider's sole consumers are remote plugins, but `config/lazy.lua` disables
  the `rplugin` manifest loader, no installed plugin ships a manifest, and nothing references
  `node_host` — so it was unreachable while still emitting a permanent `:checkhealth` WARNING.
  python3 goes too: `vimade` is the only thing in the tree that mentions python, and it never
  reaches that path here. `vimade#SetupRenderer()` (`vimade/autoload/vimade.vim:30-43`)
  short-circuits to the Lua renderer whenever `renderer == 'auto'` and `supports_lua_renderer`, and
  only the _else_ branch calls `SetupPython()`; `supports_lua_renderer` needs
  `nvim_get_hl` + `nvim_win_set_hl_ns`, present since 0.11, and nvim-treesitter's main branch
  already hard-requires 0.12 here — so the python fallback is unreachable. Confirmed at runtime:
  `ACTIVE renderer = lua`, `vimade_python_setup = 0`, and `has('python3')` was never evaluated.
  (nvim-dap-python spawns debugpy as an external DAP adapter — a subprocess, not this provider.)
  Disabling both makes the cleanup portable: otherwise any fleet machine without `pynvim` keeps
  emitting the same warning. `:checkhealth` is now **0 errors, 0 warnings** across every section.
- **Neovim: `gsn` (surround `update_n_lines`) never existed.** `plugins/mini-nvim.lua` passed
  `update_n_lines = "gsn"` in mini.surround's `mappings`, but that is not a key in its schema
  (`add`/`delete`/`find`/`find_left`/`highlight`/`replace`/`suffix_last`/`suffix_next`) and unknown
  keys are accepted silently — `setup()` returned OK and no mapping was created, while every other
  `gs*` map did exist. Mapped explicitly instead, as upstream's own docs prescribe
  (`mini/surround.lua:909`), so the prefix the file advertises is real.

- **Neovim: SchemaStore catalogues never reached `jsonls` or `yamlls`.** Both resolved their
  schemas in `before_init` by re-binding `config.settings` with `vim.tbl_deep_extend`. The client
  binds `client.settings = config.settings` in `Client.create()` (runtime
  `lua/vim/lsp/client.lua:409`) **before** `before_init` runs (`:571`), and `tbl_deep_extend`
  returns a _new_ table — so the client kept the original and the catalogue was silently dropped.
  Both delivery paths (`workspace/didChangeConfiguration` push and the `lookup_section` pull) read
  `client.settings`. `yamlls` was the worse case: it disables its own built-in store
  (`schemaStore.enable = false`) and so ended up with _neither_ catalogue. Now mutated in place.
  Verified live: `jsonls` 0 → **1368** schemas, `yamlls` 0 → **1279** with the built-in store still
  off. Note Neovim's own docs demonstrate the broken re-binding form (`client.lua:36-41`).
- **Neovim: the `gr*` default-keymap cleanup deleted nothing, so `gr` still waited `timeoutlen`.**
  `utils/lsp.lua` called `vim.keymap.del("n", lhs, { buffer = bufnr })`, but Neovim creates
  `grn`/`gra`/`grr`/`gri`/`grt`/`grx` as **global** maps (`lua/vim/_core/defaults.lua`). Every
  delete raised `E31: No such mapping`, swallowed by the `pcall`. Dropped the `buffer` key, added
  the two 0.12 additions (`grt`, `grx`) that were missing, and hoisted the loop out of `on_attach`
  — it is global state that was being re-attempted per attaching client (twice on a Python buffer:
  `ruff` + `ty`). Verified: all six now report unmapped after boot. `grx` (`vim.lsp.codelens.run`)
  was the one default with no existing equivalent in this config, so it gains a replacement under
  the `<leader>c` "code" prefix: **`<leader>cL` runs CodeLens** (capital L — lowercase
  `<leader>cl` is Trouble's LSP refs/defs, and these maps are buffer-local, so taking it would have
  shadowed Trouble on every LSP-attached buffer). The others already had
  one (`grn` → `<leader>rn`, `gra` → `<leader>ca`, `grr` → `gr`, `gri` → `gi`, `grt` → `gy`).
- **Neovim: `binary_available()` was a no-op for `ts_ls`, `yamlls` and `tailwindcss`.** Current
  nvim-lspconfig ships `cmd` as a _function_ (a project-local `node_modules/.bin` probe) for those,
  and the guard's `type(cmd) ~= "table" → return true` branch waved them straight through. They
  were enabled unconditionally, still produced the recurring `spawn … ENOENT` the guard exists to
  suppress, and never appeared in the "LSP not enabled" notice. Now available if the well-known
  global binary is on `PATH` **or** a `node_modules/.bin/<binary>` is reachable from the cwd. Both
  tests are needed: those launchers prefer a project-local binary and only then fall back to the
  global one, but this enable pass runs before any client (so before `root_dir` exists) — answering
  "unavailable" means no client ever starts and the launcher never runs, so a global-only test would
  break the common "no global install, just a devDependency" layout. The local test is a heuristic
  and is deliberately biased to fail open.
- **Neovim: `mini.nvim` dragged the whole treesitter stack onto the startup path.** It declared
  `nvim-treesitter-textobjects` as a `dependencies` entry, and lazy.nvim loads dependencies _with_
  the parent — so mini's `VeryLazy` overrode the `BufReadPost`/`BufNewFile` trigger that both
  nvim-treesitter and -textobjects declare, running treesitter's parser-directory scan and possible
  `install` pass on the dashboard. Removed; mini.ai resolves the `textobjects` queries lazily at
  textobject-use time, by which point `BufReadPost` has loaded them. Measured in a real PTY: a bare
  `nvim` went from **13 loaded plugins to 11**, dropping ~15.5 ms of post-`UIEnter` work.
  (Time-to-`NVIM STARTED` is unchanged — this work always landed _after_ that marker.)
- **Neovim: `vim.hl.on_yank` is version-gated rather than hard-coded.** It is deprecated on Neovim
  HEAD (0.13-dev) in favour of `vim.hl.hl_op`, which does **not** exist on 0.12.4 — so a rename
  would break every machine still on stable. Probes for the new name and falls back, and the
  adjacent comment asserting "there is no `vim.hl.hl_op`" is corrected.
- **Neovim: `blink.cmp` is now a declared dependency of `nvim-lspconfig`.** `servers/init.lua`
  calls `require("blink.cmp").get_lsp_capabilities()`, which lazy's require-hook already pulled
  blink (and `friendly-snippets`) in at `User FilePost` — so blink's own `event = "InsertEnter"`
  was never the trigger that loaded it. This declares what already happened; it is not a speed-up,
  and blink cannot be deferred further because capabilities must be advertised in `initialize`.

### Changed (internal)

- **Neovim: the cheatsheet now covers what it claims to.** An audit against the real keymaps found
  the panel had drifted from the config it documents. Added a **Completion (blink.cmp)** card — the
  seven completion-menu keys had no row at all — and a **Move lines (mini.move)** card for
  `<A-hjkl>`, another whole feature that was absent. Also added `<leader>bn`/`bp`, `<leader>cl`
  (Trouble LSP refs/defs), `]t`/`[t`, `gsh` and `gsn`; corrected two descriptions (`<leader>rc` said
  "Edit init.lua" where the keymap's `desc` is "Edit config"; `<leader>e` dropped the load-bearing
  "closes Zen if active" side effect). The header's "EVERY curated binding" claim is now scoped to
  say what is deliberately excluded (transient-UI keys: the rename float, oil buffers, alpha's
  buttons, the panel's own `q`/`<Esc>`) rather than overstating.
- **Neovim: which-key names three prefixes that rendered as unnamed.** `<leader>r` (edit config,
  rename symbol), `<leader>o` (organize imports) and `<leader>p` (copy file path) had real children
  but no `group` entry. `<leader>p` is declared for normal mode only — in visual it is itself a
  mapping (paste-without-yank), not a prefix.
- **Neovim: removed dead and misleading plugin config.** Each verified against the installed plugin
  source, not assumed:
  - `bufferline`: dropped `hover.reveal = { "close" }`. `get_close_icon()`
    (`bufferline.nvim/lua/bufferline/ui.lua:263-270`) consults `reveal` and then unconditionally
    bails on `if not options.show_buffer_close_icons then return end` — which is `false` here, so
    there was never a close icon to reveal. `hover` stays on for hover highlighting.
  - `nvim-tree`: `view = { adaptive_size = true }` → `view = { width = {} }`. `adaptive_size` is a
    2023-01-15 legacy key that nvim-tree silently rewrites (`legacy.lua:73-81`); with no explicit
    width it produces `{ min = nil }`, i.e. `{}`. Verified equivalent by running the migration and
    comparing deep-equal. Note `{}` is not "unbounded" — nvim-tree fills the absent keys with its
    own defaults (`view-state.lua:5-6,77-78`), so the pane sizes to content but never narrower than
    30 columns; confirmed at runtime as `width = 30`, `max_width = -1`.
  - `fidget`: `winblend = 0` → `100` (its default). The old comment said this matched "transparent
    floats" — backwards; fidget's docs (`notification/window.lua:33-49`) describe `100` as the
    see-through setting and anything less as blending with what's underneath.
  - `nvim-treesitter-context`: dropped `separator = nil` — assigning `nil` in a table literal omits
    the key, and `nil` is already the default, so it read as a setting but did nothing.
  - `conform`: dropped a `config` function that re-implemented lazy.nvim's default for a spec with
    `opts`. Verified the 20 `formatters_by_ft` entries still apply without it.
  - `blink.cmp`: corrected a comment claiming the snippet keys use native `vim.snippet` — with
    `preset = "luasnip"` they route to LuaSnip; blink picks the engine by preset.
- **Neovim: `<leader>ha` refuses an unnamed buffer.** harpoon keys its list by file path, so adding
  a scratch buffer stored an unnavigable empty entry and toasted a bare `"Harpoon: added "`.
- **Neovim: `keymaps.lua` Ex-command maps use `<Cmd>…<CR>` instead of `:…<CR>`** (11 split/tab/
  resize maps). `:` switches to cmdline-mode first — it echoes, is subject to cmdline mappings and
  abbreviations, and clobbers a pending count or visual selection; `<Cmd>` does not.
- **Neovim: `<leader>pa` reports via `vim.notify`, not `print`**, so the copied path lands in the
  mini.notify toast like every other message instead of the message area (and no longer risks a
  hit-enter prompt on a long path). Also handles the no-file case.
- **Neovim: the `<LeftDrag>`/`<LeftRelease>` maps moved from `options.lua` to `keymaps.lua`**, and
  the undodir setup dropped two redundant `vim.fn.expand()` calls on an already-absolute
  `stdpath("state")` path (now built with `vim.fs.joinpath`).

## [v3.9.0] - 2026-07-19

### Added

- **Neovim: shared `utils/palette.lua`** — a single source of truth for the active tokyonight
  palette. The `"storm"` style string and the `require("tokyonight.colors").setup{}` pcall dance
  were duplicated across lualine, bufferline, and the cheatsheet; they now all resolve through this
  one module (change the style once). It also exposes a NvChad-`base_30` semantic map (`black2`,
  `statusline_bg`, `nord_blue`, `dark_purple`, …) so the block/pill styling is written in NvChad's
  own vocabulary while still tracking the theme.
- **Neovim: scroll-percentage indicator** in the lualine statusline (right bubble, next to the
  cursor location) so you can see how far through a file you are.
- **Neovim: NvChad-style inline LSP renamer** (`utils/renamer.lua`) — `<leader>rn` now opens a
  small cursor-anchored, git-red-bordered prompt prefilled with the symbol (`<CR>` applies across
  the workspace, `<Esc>`/`q` cancels) instead of the bare cmdline prompt.
- **Neovim: colorify-style colour highlighter** (`nvim-colorizer.lua`, catgoose fork) — inline
  colour swatches over the visible viewport: CSS colour literals (`#rrggbb`, `rgb()/hsl()`) plus
  Tailwind utility-class colours via the Tailwind LSP. ccc.nvim is kept for the interactive
  `:CccPick` picker (its always-on highlighter is now off).

### Changed

- **Neovim: statusline & tabline go hybrid-NvChad.** The bufferline adopts NvChad's tabufline model
  where buffer state is conveyed by BACKGROUND on a solid opaque bar — the active buffer lifts to a
  lighter raised block, inactive buffers recede to the bar colour — while the editor stays
  transparent. The blink.cmp menu gains NvChad's colored kind-icon column (via `BlinkCmpKind*`
  highlights) with an icon-left / kind-text-right layout. The `<leader>?` cheatsheet renders as a
  solid opaque card.
- **Neovim: signature help is owned by blink.cmp.** The manual `CursorHoldI`
  `vim.lsp.buf.signature_help` autocmd was removed — blink's own signature window handled the same
  case and the two floats could stack while idle. `<C-s>` stays as the manual trigger.
- **Neovim: the central Mason install manifest moved** out of conform.nvim (which is lazy on
  `BufWritePre`, so `run_on_start` really meant "on first save") into its own `VeryLazy`-loaded
  `plugins/mason-tool-installer.lua`, so a fresh box installs its toolchain near startup.

### Removed

- **Neovim: trimmed unused plugins** — the full in-editor **debugger stack** (nvim-dap,
  nvim-dap-ui, nvim-dap-virtual-text, mason-nvim-dap, and every `<leader>d*` keymap), the **test
  runner** (neotest + neotest-python/-golang), vim-dadbod (DB UI), incline.nvim (dropbar's winbar
  covers split identity), aerial.nvim (Trouble + fzf-lua + dropbar cover symbols), nvim-spectre,
  git-conflict.nvim, and mini.indentscope — along with their keymaps, which-key groups, and
  cheatsheet sections. (16 entries removed from `lazy-lock.json`, including transitive dependencies.)

### Fixed

- **Neovim: heavy linters no longer run on `InsertLeave`.** golangci-lint / cpplint scan the whole
  package per run; they are now restricted to `BufWritePost` (save-only) while fast per-file linters
  keep the snappier cadence.
- **Neovim: bash-language-server no longer emits `SC1071` on zsh.** Its built-in shellcheck
  integration is disabled (`bashIde.shellcheckPath = ""`) so zsh buffers keep completion/hover
  without the "shellcheck only supports sh/bash/…" phantom diagnostic.
- **Neovim: `:w` can't be broken by a missing mini.nvim.** The format-on-save
  `mini.trailspace.trim()` call is now pcall-guarded.

## [v3.8.0] - 2026-07-18

### Changed

- **Neovim UI moves to an NvChad-styled statusline + bufferline.** `lualine` now uses a
  hand-built theme derived from tokyonight's resolved palette (mode/location render as rounded
  accent **pills**, git/cwd as a lighter block, filename on the base run) instead of the bundled
  `tokyonight` theme — so the blocks read as opaque islands on the transparent bar and follow
  NvChad's structure. `bufferline` gains palette-aware highlights so the active buffer lifts as a
  subtle raised block with an accent underline while inactive buffers dim into the bar. Both are
  computed at plugin-load (pcall-guarded), so a fresh box falls back to the bundled/auto theming.
- **LSP hover, signature help, and the diagnostic float share one padded, rounded card style.**
  Hover/signature pass an explicit rounded border with width/height caps (a huge docstring becomes
  a tidy box); the diagnostic float drops its header row and gains a left pad + width cap.
  Signature help now also pops **automatically** when you rest inside a function's arguments
  (`CursorHoldI`, gated on server support, suppressed while the completion menu is open).
- **`which-key` and the `<leader>?` cheatsheet restyled to mirror NvChad's keymap visualizer.**
  which-key gets a minimal rounded, padded, left-aligned column popup with NvChad-palette colors
  (blue keys, red descriptions, green groups); the cheatsheet's category headings become
  full-width accent **pill** bars (cycling colors) with blue keys — both palette-aware, with a
  semantic-link fallback on a bare box.

### Fixed

- **Neovim `taplo` (TOML) root detection.** `root_markers` listed the glob `"*.toml"`, which
  `vim.fs.root`/`vim.fs.find` do not support — so it never matched and taplo always fell back to
  `.git`, giving a lone TOML file outside a repo a cwd root. Replaced with real manifest names
  (`pyproject.toml`, `Cargo.toml`, `foundry.toml`, `taplo.toml`, `.taplo.toml`, `.git`).
- **Neovim `<leader>oi` (organize imports) no longer binds where it can't work or races the
  formatter.** A server that ENUMERATES its code-action kinds without `source[.organizeImports]` is
  now skipped (so the map no longer silently no-ops on e.g. `lua_ls`); a server that only reports a
  bare `true` or a provider table without kinds still gets the map, since it can't be ruled out. The
  racy fixed-`50ms` post-format timer is dropped — formatting stays owned by format-on-save and
  `<leader>cf`.
- **Neovim cursor-restore skips commit buffers.** `gitcommit`/`gitrebase` buffers open at the top
  again instead of jumping to a stale mark from a previous commit.
- **Neovim folding has a single owner.** `nvim-ufo` computes folds via its own treesitter+indent
  providers, so the global `foldmethod=expr` + treesitter `foldexpr` in `options.lua` was redundant
  per-buffer work (UFO never reads `foldexpr`). Dropped it; UFO now owns folding outright.

### Changed (internal)

- Deduped the identical `snippetSupport` capability boilerplate in the Neovim `html`/`cssls`
  server specs into a shared `utils.lsp.with_snippets` helper; standardized autocmd augroups on an
  explicit `{ clear = true }`; corrected a stale comment claiming no `vim.notify`-competing
  notifier is installed (fidget is, for LSP progress only — no clash).

## [v3.7.0] - 2026-07-17

### Changed

- **Neovim clipboard gains a gated OSC52 last-resort provider.** When no native clipboard
  backend is on PATH (no Core `clip`/`clip-paste`, no `clip.exe`, and none of `pbcopy` /
  `wl-copy` / `xclip` / `xsel` / `win32yank`), `"+y`/`"+p` route over the terminal's OSC52
  sequence — closing the "yank does nothing over tmux/psmux/SSH" gap on headless/remote boxes.
  A working native provider is never overridden, so a normal desktop is unaffected.
- **Neovim clipboard paste uses `Get-Clipboard -Raw` on Windows**, so multi-line pastes no
  longer arrive split/CRLF-mangled.
- **Windows-correct Neovim Python DAP + LuaSnip build.** debugpy/venv interpreters resolve to
  `Scripts\python.exe` (and `python`, not `python3`) on Windows; LuaSnip skips its
  `make install_jsregexp` build where there's no toolchain. All gated on `has("win32")`.
- **Neovim LSP capabilities fetch is `pcall`-guarded** (a blink load failure no longer aborts
  the whole server stack), and `emmet_ls` now attaches to `html`.
- **Starship prompt gains venv, package, git-metrics, and WSL indicators.** `[python]` shows the
  active `$virtualenv`; a `$package` version indicator and an `$env_var` slot are wired into
  `format` (surfacing a previously-unplaced `ENGAGEMENT` var and a new `WSL_DISTRO_NAME` badge);
  `git_metrics` is enabled; a documented opt-in `docker_version` custom is included (off by default).
- **`git_main_branch` resolves the trunk in one call.** It reads `origin/HEAD` directly
  (`git symbolic-ref`) and only falls back to probing the trunk-name candidate list when
  that is unset — instead of firing up to 18 `git show-ref` subprocesses every call. It sits
  on the hot path (`gcom` / `gswm` / `grbm`).
- **`git_current_branch` uses the git porcelain.** It now reads `git branch --show-current`
  (git 2.22+) instead of the hand-rolled `symbolic-ref` + return-code dance; the short-SHA
  fallback on a detached HEAD and the empty result outside a repo are both preserved.
- **`_core_suggest` no longer forks per candidate.** `_core_lev` gained a fork-free out-var
  mode, so scoring a mistyped Core verb against the alias/subcommand list runs in-process
  rather than spawning a command substitution for each candidate (~80+ on a bad `please`).
- **`pullall` tallies its summary in a single `awk` pass** instead of four `grep -c` scans of
  the same buffer.
- **Collapsed a dead `status-left` conditional** in `tmux/tmux.conf` to a constant — all three
  branches resolved to the same colour.
- **Decoupled `--help` from header line numbers.** `update-plugins.sh`,
  `update-nvim-plugins.sh`, and `freshness-dashboard.sh` now print usage from a heredoc rather
  than `sed -n '<a>,<b>p' "$0"`, which silently mis-printed whenever the header comment moved
  (the coupling `sync-core.sh` already documents having removed).
- **Removed redundant zsh history setopts** (`zsh/history.zsh`): `INC_APPEND_HISTORY` (implied
  by `SHARE_HISTORY`) and `HIST_IGNORE_DUPS` (superseded by `HIST_IGNORE_ALL_DUPS`) were
  no-ops, so they are dropped.

### Security

- **session-start hook verifies its tool downloads.** `install_tarball` and the neovim
  install in `.claude/hooks/session-start.sh` now download to a file and check the pinned
  SHA-256 from `scripts/tool-versions.env` before extracting — failing closed when a
  checksum is absent or mismatched — instead of piping `curl … | tar` unverified. Brings the
  remote-session gate toolchain in line with the CI composite action, which already verifies.
- **claude-routines run with least-privilege tools.** Each job's `--allowedTools` now mirrors
  its routine's own `allowed-tools` frontmatter rather than granting unrestricted `Bash`; the
  web-reading routines (tool-scout, freshness-triage, modernize, release-readiness,
  drift-triage) no longer pair arbitrary shell with `WebFetch`/`WebSearch`, closing a
  prompt-injection → `CLAUDE_CODE_OAUTH_TOKEN` exfiltration path. `drift-triage`'s command
  frontmatter is scoped to match.
- **`HISTORY_IGNORE` covers more secret shapes** (`zsh/history.zsh`): `--flag=value` forms and
  env-assignment credentials (`TOKEN=`, `PASSWORD=`, `*ACCESS_KEY=`, `APIKEY`) that the
  space-only patterns let slip now stay out of the plaintext `$HISTFILE`.

### Fixed

- **Cheatsheet uses a non-deprecated highlight API.** `nvim/lua/gerrrt/cheatsheet.lua` now
  calls `nvim_buf_set_extmark` instead of the deprecated `nvim_buf_add_highlight` (slated for
  removal on Neovim nightly), so `:Cheatsheet` / `<leader>?` keeps working on current Neovim.

## [v3.6.1] - 2026-07-16

### Documentation

- **`docs(runbook)`: spell out how release cuts differ by bump type.**
  `RELEASE-RUNBOOK.md` now adds the Core-release bump-selection table, the step-4
  `@vN` alias split for PATCH/MINOR vs MAJOR, the extra MAJOR rollout `uses:` bump,
  the htpx SemVer guide, and the "undo a staged `make release`" troubleshooting
  path. `RELEASE-STRATEGY.md` is updated alongside it so the current-version examples
  stay aligned with the live Core release line.

## [v3.6.0] - 2026-07-16

### Added

- **`feat(nvim)`: five editor quality-of-life tweaks.** Cherry-picked from an external
  config the handful of behaviours that beat or fill a gap in ours (the rest we already run
  better-configured equivalents of). (1) `i`/`a`/`A` on a blank line auto-indents via `"_cc`
  (black-hole register, guarded on `count == 0` so `3i`/`10a` keep native behaviour);
  (2) an async `git fetch` on `VimEnter` toasts when the upstream is ahead of `HEAD` — pinned
  to the startup cwd, argv-form (Windows-portable), and only reported after a _successful_
  fetch; (3) `vimade` dims inactive windows and cursorline is now shown only in the active
  window (markdown/text/gitcommit keep their cursorline-off policy); (4) a macro-recording
  indicator in the lualine mode block; (5) `exrc` for project-local config. The `git fetch`
  toast and `exrc` are both gated on `DOTFILES_OFFLINE` so they stay inert on engagement boxes,
  and `exrc` additionally relies on Neovim's `vim.secure` trust prompt for untrusted repos.

## [v3.5.2] - 2026-07-14

### Fixed

- **`fix(tmux)`: trailing space after the copy-mode icon.** The status-bar copy-mode
  indicator was `󰆏#S` (glyph abutting the session name); it is now `󰆏 #S` — a single
  space keeps the pill readable at a glance without otherwise changing the layout.

### Documentation

- **`docs(runbook,strategy)`: document the deliberate dotfiles-Windows minor/major
  release flow.** `RELEASE-RUNBOOK.md` §3 only covered the automatic PATCH path
  (mirror-sync → auto-tag). A new §3b covers the human-driven minor/major flow: the
  version decision via `/release-readiness` + `/release-notes`, the
  `packages.lock.json` re-pin (including the winget-export-vs-ARP mapping gap that
  silently drops installed-but-unmapped apps), CHANGELOG promotion, and
  `gh release create` (there is no `release.yml` on the Windows repo). Simultaneously,
  `RELEASE-STRATEGY.md` is corrected: dotfiles-Windows is now carved out as the
  standalone exception that carries its own vX.Y.Z but no `core/` subtree, and the
  notes-source column is fixed (`--notes-file` via auto-tag.sh is the automatic path;
  `--generate-notes` is only the fallback for empty/unconventional ranges).

## [v3.5.1] - 2026-07-14

### Changed

- **`ci(modern)`: ban the `macos-14` runner in the modern-CI floor.** `macos-14`
  (Sonoma) images entered deprecation on 2026-07-06 and are fully unsupported on
  2026-11-02, so `scripts/modern-baseline.yml` now lists it under `banned_runners`
  alongside `macos-13`. Pre-emptive and free — the fleet rides `macos-latest`, so no
  workflow references the pinned label today; `check-modern.sh` enforces it.

### Documentation

- **`docs(matrix)`: `watch`→`viddy` is now a first-class, provisioned tool.**
  `PORTING-MATRIX.md` gains a `viddy` row so the `watch`→`viddy` alias Core already
  ships (`HAVE_VIDDY`-guarded in `zsh/aliases.zsh`) is actually installed — macOS
  already had it via Homebrew; the Linux/Kali repos now install it best-effort in
  `bootstrap.sh` via `cargo install viddy` (viddy is a Rust CLI, so the same cargo path
  as yazi/dust — Arch, which ships no rust toolchain, prints a `paru -S viddy` hint).
  Inert without the binary, so boxes that skip it keep classic `watch`.

## [v3.5.0] - 2026-07-13

### Changed

- **`fix(git)`: delta's `syntax-theme` is now `ansi` (was `TwoDark`).** delta now follows
  the terminal's Tokyo Night ANSI palette, matching `BAT_THEME=ansi` (already set in
  `aliases.zsh`) so `git diff` and `bat` render syntax the same way — and matching the
  Windows host, which already used `ansi`. Part of the Windows↔Mac terminal parity pass.

### Fixed

- **`fix(nvim)`: `<leader>rc` and the alpha dashboard "Config" button open `init.lua`
  on Windows too.** Both hardcoded `~/.config/nvim/init.lua`, which doesn't exist on the
  Windows host — Neovim there reads `%LOCALAPPDATA%\nvim` — so the binding opened a phantom
  path. They now resolve the config dir at runtime via `vim.fn.stdpath("config")`, so the
  same binding lands on the real `init.lua` on every platform.

### Parity (cross-shell contract)

- **`feat(parity)`: the aligned tool-swap manifest gains `df`→duf, `top`/`htop`→btop,
  `fm`/`y`→yazi, `md`→glow (pwsh `gmd`), and `ping`→gping.** These were already defined
  in `zsh/aliases.zsh`; adding them to `scripts/parity-aliases.txt` makes
  `parity-check.sh` enforce them bidirectionally against the pwsh host's `provides:`
  contract (the Windows PowerShell port added the matching functions in the same pass).
- **`feat(parity)`: `Ctrl+\` autosuggest/prediction toggle is now `aligned`, not
  `deliberate`.** The Windows host binds `Ctrl+\` to flip PSReadLine's `PredictionSource`,
  mirroring zsh's `autosuggest-toggle`; `parity-check.sh` now enforces the needle on both
  shells. PARITY.md's Aliases prose also now documents the full curated git shorthand set
  as aligned across zsh + pwsh.
  > **Merge order:** the pwsh side of these rows ships in the `dotfiles-Windows` parity PR.
  > Merge (or land together with) that PR so the weekly `parity-check.yml` — which clones
  > `dotfiles-Windows` `main` — sees the matching pwsh definitions and stays green.

## [v3.4.0] - 2026-07-12

### Added

- **`feat(freshness)`: the weekly fleet board gains three live cross-repo signals.**
  `scripts/freshness-dashboard.sh` now queries the GitHub API (best-effort, gated on `gh` +
  a token — the workflow provides both, a local run degrades to an "unavailable" note) for:
  **own-tag release drift** (commits each repo has merged since its last release tag — its
  own unreleased work, distinct from Core-tag vendoring drift), an **open Renovate PR tally**
  per repo (how many dependency PRs are waiting right now, beside the existing dashboard
  links), and **judgment-layer routine issues** (links to each repo's open `.claude`-routine
  issues — doc-audit, os-package-availability, coverage-gap, … — so the board references the
  stale-docs and coverage-hole signals rather than recomputing them). Still a never-failing
  reporter (always exits 0).
- **`feat(routines)`: three new judgment routines + a reusable OS-repo routine workflow.**
  - `/shell-review` (`.claude/commands/shell-review.md`) — weekly (Tue 11:00) read of the
    week's changed `zsh`/`bash` for runtime footguns lint can't catch (the tmux-scratchpad
    and doctor-hint classes), report-first.
  - `/drift-triage` (`.claude/commands/drift-triage.md`) — weekly (Tue 12:00) interpretation
    of Monday's `fleet-drift` sweep into ranked per-repo remediation, report-first.
  - `/os-package-availability` (`.claude/commands/os-package-availability.md`) — audits an OS
    repo's `install/packages.txt`/`Brewfile` for renamed/dropped/moved packages against
    upstream + `PORTING-MATRIX.md`. Shipped as a **reusable workflow**
    (`.github/workflows/claude-routines-call.yml`) so each OS repo consumes it as a ~5-line
    `@v3` caller (inverted checkout, like `lint-call.yml`) rather than a 6× copy.
  All inert-by-default (preflight `CLAUDE_CODE_OAUTH_TOKEN` gate) and report-first.

### Changed

- **`perf(zsh)`: drop `zstyle ':completion:*' rehash true` — no more per-Tab `$PATH` stat storm.**
  `rehash true` (`zsh/options.zsh`) forced zsh to rebuild its external-command hash — stat every
  directory in `$PATH` — on _every_ completion attempt, which is perceptible on an NFS home,
  linuxbrew, or a large mise-shims `$PATH`, and fanned out to all eight OS repos. Removed; a
  newly-installed binary now surfaces after `hash -r` or a new shell (the maint runner already
  refreshes the command hash after installs). A regression-guard comment records why it stays out.
- **`chore(bin)`: make `.bin/sync-upstream.sh` overridable for forks/mirrors.**
  `CORE_REPO_URL` and `TARGET_BRANCH` now read `${VAR:-default}`, so a fork, a mirror, or a
  renamed org can `gsync` without editing this vendored file.

### Fixed

- **`docs(porting)`: correct the `PORTING-MATRIX.md` package cells the `/os-package-availability`
  routine flagged as drifted.** Alpine `duf`/`glow` are back to `testing` (they were never
  promoted to `community` on stable, incl. 3.24 — a July flip that claimed otherwise is reverted,
  and footnote ¹⁴ restored); Alpine `tldr` now shows `cargo³` (`testing`-only → bootstrap builds
  it from source) and Alpine `ouch` is corrected to `testing` (`testing`-only, not auto-installed);
  and Gentoo `tealdeer`/`yazi`/`lazygit` are marked GURU-only
  (footnote ¹²) alongside a note that `direnv` is `app-shells/direnv`, not the non-existent
  `dev-util/direnv`. Matches the OS-repo bootstrap reality (Alpine cargo/go-install fallbacks;
  Gentoo `guru_install`). Also: Arch `atuin` drops the stale "(AUR for some)" qualifier and Arch
  `doggo` moves from `AUR³` to `doggo` (both now first-class in `extra`), and the openSUSE
  `tealdeer` footnote ¹ is de-hedged (it's in Tumbleweed main OSS, not devel-only).
- **`fix(zsh)`: `compinit` block no longer leaks a global `zcd` into every interactive shell.**
  `zsh/options.zsh` declared `local zcd=…` at the file's sourced top level, where zsh (which has
  only function scope) silently promotes `local` to an ordinary **global** — polluting the
  namespace on every shell start across all eight OS repos and contradicting the codebase's own
  anon-function convention (`zsh/aliases.zsh`) and `loader.zsh`'s "no top-level `local`" rule. The
  cache body is now wrapped in an anonymous function so `zcd` is genuinely function-scoped;
  `compinit` declares its state `typeset -g`, so the completion system persists unchanged.
- **`fix(zsh)`: `serve` now prints a reachable URL and QR on macOS.**
  `serve` (`zsh/functions.zsh`) gated all tunnel/LAN IP discovery on `command -v ip`, but macOS
  ships no `ip(8)`, so on a Mac it degraded to a bare "serving on port N" with no LAN URL and no
  QR. Added a `route(8)` + `ipconfig` fallback branch — the same Linux/macOS split
  `tmux/scripts/tmux-netinfo.sh` already uses — so tunnel-first, then default-route LAN discovery
  works on a Mac. No change on Linux/WSL.
- **`fix(nvim)`: undo dir now derives from `stdpath("state")`, not a hardcoded path.**
  `options.lua` hardcoded `~/.local/share/nvim/undodir`; it now uses `vim.fn.stdpath("state")`,
  so undo history lands in the right tree under a relocated `XDG_STATE_HOME` and on macOS.
- **`fix(nvim)`: drop the no-op `vim.opt.encoding = "UTF-8"`.**
  Neovim's internal encoding is always UTF-8; setting it post-startup is a no-op at best and a
  footgun at worst. Removed; a comment records why it stays out.
- **`fix(tmux)`: popup previews degrade on Debian / a bare box.**
  `tmux-menu.sh`'s engagement preview now falls back `bat`→`batcat` (Debian renames the binary),
  and `tmux-sesh.sh`'s project preview falls back `eza`→`ls` when eza is absent — matching how
  the zsh widgets already resolve these.
- **`fix(starship)`: the Linux VPN segment uses a portable `ip link show` probe, not `ifconfig`.**
  `custom.vpn_linux` shelled out to `ifconfig` (net-tools), which modern distros don't ship by
  default, so the tunnel indicator silently never appeared. It now parses `ip link show` — the
  common form supported by BOTH iproute2 AND BusyBox's `ip` applet (Alpine's default), so it works
  on every Linux target including the BusyBox outlier. `custom.vpn_macos` keeps `ifconfig` (native).
- **`docs(git)`: spell out the `includeIf` work-identity failure mode.**
  Clarified that a missing `~/.config/git/config-work` makes git silently fall back to your
  default identity (no error), with the exact commands to seed it.
- **`fix(git)`: `prune-branches` uses `grep -E`, not deprecated `egrep`.**
  The `prune-branches` alias (`git/gitconfig`) shelled out to `egrep`, which GNU grep ≥3.8 prints
  a deprecation warning for on every invocation. Switched to `grep -Ev`; `xargs -r` is kept (GNU
  needs it to skip empty input, and modern BSD/macOS xargs supports it), so the alias is quiet on
  the Linux target and unchanged in behaviour on the macOS/BSD target it ships to.
- **`fix(scripts)`: checksum refresh falls back to `shasum -a 256` off-Linux.**
  `scripts/update-tool-checksums.sh` hard-called `sha256sum` (GNU coreutils); a run on the macOS
  box (which ships `shasum -a 256`, not `sha256sum`) died. It now probes and falls back, so the
  tool works on either platform.
- **`fix(maint)`: `dotfiles-maint.sh` enables `set -uo pipefail`.**
  The unattended daily runner had no `set` options, so a typo'd env knob expanded to empty and a
  mid-pipe failure was masked. Added `set -uo pipefail` (every env knob is already `:=`/`:-`
  defaulted); `-e` stays deliberately omitted so one failed step never aborts the rest — that
  remains `step()`'s job.
- **`fix(tmux)`: the popup scripts enable `set -u`.**
  `tmux-menu.sh`, `tmux-scratch.sh`, and `tmux-sesh.sh` carried no `set` options, unlike their
  siblings; a typo'd variable would expand to empty silently. Added `set -u` (all three already
  guard `${TMUX:-}`/`${TERM:-}` etc.); `-e`/`pipefail` stay off because the fzf pickers exit
  non-zero on a normal operator cancel.
- **`fix(scripts)`: the freshness board's live signals honour an env token.**
  `scripts/freshness-dashboard.sh` gated its GitHub-API "live signals" on `gh auth status`
  alone, whose exit/output varies by `gh` version — so in CI (which authenticates via
  `GH_TOKEN`, not `gh auth login`) the release-drift / Renovate-count / routine-issue
  sections could be mis-detected as unavailable. It now treats a `GH_TOKEN`/`GITHUB_TOKEN`
  env var as sufficient (what `gh api` actually uses), falling back to `gh auth status`
  for local runs with stored credentials.

## [v3.3.0] - 2026-07-09

### Changed

- **`perf(zsh)`: cut per-shell subprocess forks on the interactive startup path.**
  `_cache_eval` (`zsh/tools.zsh`) now resolves each tool's binary via zsh's fork-free
  `$commands` hash instead of `$(command -v …)`, removing one command-substitution fork
  per cached tool (~8/shell across starship/zoxide/mise/atuin/carapace + the os-layer
  gh/uv/ty callers). The `diff --color` capability probe (`zsh/aliases.zsh`) is now
  cached (keyed on the `diff` binary's mtime, invalidated on a toolchain change) instead
  of running the real `diff` on every shell; a live probe still decides correctly when
  the cache dir isn't writable. No behavioural change — same aliases, faster launch.
- **`docs(zsh)`: make `core-doctor`'s "install missing" hint honest about unpackaged tools.**
  The batch hint printed a blanket `<pkg-manager> install <all-missing>`, implying the package
  manager can install every tool. On some distros a few modern-CLI tools aren't packaged at
  all (they're binary-distributed, and the right method — a distro package, `mise use -g`,
  `go install`, `cargo install`, or a vendor repo — varies per tool and distro), so the line
  fails on those. The caveat now states that names differ per distro **and** that not every
  tool is packaged everywhere, pointing to `PORTING-MATRIX.md` for the authoritative per-tool
  install path instead of implying the package manager covers all of them. Output-only; the
  package-manager line itself is unchanged.

### Fixed

- **`fix(tmux)`: scratchpad popup (`prefix + T`) no longer hijacks the main session on close.**
  `tmux-scratch.sh` runs the scratchpad as a persistent `_popup_scratchpad` session the popup
  `attach`es to. On close, exiting the shell destroys that session, and the global
  `detach-on-destroy off` (tmux.conf) made the popup's client jump to the MAIN session instead
  of closing — attaching a second, popup-sized (80%×80%) client, so tmux clamped the main
  session to the popup's size and double-drew it (the scratchpad "took over" and the real
  terminal was left garbled). The scratch session now sets `detach-on-destroy on` for itself,
  so its client detaches (popup closes cleanly) when it's destroyed; real sessions keep the
  global jump-don't-exit behaviour.

## [v3.2.0] - 2026-07-08

### Removed

- **`token-health.yml` — the weekly PAT-expiry probe, now redundant (G2 finish line).** The
  probe existed to catch a `FLEET_SYNC_TOKEN` / `WEBHOOK_SECRET` PAT silently expiring before it
  broke the fan-out or the docs-refresh. With every consumer migrated to GitHub App
  installation tokens (`GITHUB-APP-AUTH.md`) and both PATs deleted, there is nothing left to
  probe — a minted token lives ~1 hour and cannot silently expire. Removed the workflow and its
  references (the freshness dashboard's "Token health" section is now a "Fleet auth" note; the
  cron-stagger and sync-fanout failure-hint comments no longer mention it).

- **`dotfiles-Defense-PLAN.md` — the pre-build planning skeleton, now obsolete.**
  The doc was a "ready-to-instantiate skeleton for a future `dotfiles-Defense`
  repo," written before that repo existed. `dotfiles-Defense` is now a public,
  released repo (v1.0.x) that actively vendors Core, so the plan is spent — and,
  worse, it actively misled the `/doc-audit` routine into reporting Defense as
  "unbuilt/absent." Deleted (git history retains it) and dropped from the
  `audit-core.sh` META_ALLOWLIST.

### Added

- **`ast-grep` is now a recognized opt-in tool.** AST-aware structural code
  search/rewrite — the syntax-tree complement to `ripgrep` (text), `sd` (regex), and
  `gron` (JSON). `tools.zsh` sets `HAVE_ASTGREP` when the binary is present; it's its
  own command with **no alias** (like `gron`/`sd`), so it shadows nothing and is inert
  without the binary. `PORTING-MATRIX.md` documents install sources (Arch `extra`,
  Alpine `community` musl build, Homebrew; else `cargo`/`mise`/`npm`/`pip`). Surfaced
  by `/tool-scout` as the one true capability gap in the stack.

- **ci: raised the modernization floor — banned retired runners + old action runtimes.**
  `scripts/modern-baseline.yml` now bans `macos-13` (retired 2025-12-04), `windows-2019`
  (unsupported 2025-06-30), and `ubuntu-22.04` (deprecation opens 2026-09-17) as runner
  labels, and the `using: node16` / `using: node20` action runtimes (Node 24 is the
  default since 2026-06-16). Pure no-regression guard — the fleet uses none of these, so
  `check-modern.sh` stays green; it just bars re-introducing a dead runner or runtime.
  Surfaced by `/modernize`.

- **Cross-platform alias parity is now a data-driven manifest (Track A).** The aligned
  modern-CLI tool-swap aliases (`ls`→eza, `cat`→bat, `ps`→procs, …) live in a flat
  `scripts/parity-aliases.txt` manifest; `parity-check.sh` reads it and asserts each row
  **bidirectionally** — the zsh alias is defined in `zsh/aliases.zsh` AND the pwsh name is
  in `dotfiles-Windows`'s `00-aliases.ps1` `provides:` contract — so a rename or drop on
  either shell fails the weekly `parity-check`. Naming exceptions (`ps`→procs is `pss` on
  pwsh) are recorded in the manifest. Extends the check from a handful of hand-coded
  needles to the full tool-swap surface; adding an aligned alias is one manifest row.

- **`notify-web` dispatch mints a GitHub App token; sync-fanout mint gated on the key (G2).**
  The reusable `notify-web-call.yml` now mints a short-lived `dotfiles-web`-scoped GitHub App
  token for the `repository_dispatch` (replacing the `WEBHOOK_SECRET` Bearer PAT) when the
  fleet App is configured and the caller passes `FLEET_APP_PRIVATE_KEY`, else it falls back to
  `WEBHOOK_SECRET`. Because `FLEET_APP_ID` is one org-wide variable, the mint is gated on a
  `HAS_APP_KEY` presence flag (an env derived from a secret comparison — secrets can't be
  tested in `if:`) so a caller that hasn't been migrated (or a repo the key isn't scoped to)
  falls back cleanly instead of failing on an empty key. The same defensive gate is added to
  the Core `sync-fanout` mint. Core's own standalone `notify-web.yml` dispatcher (not a caller
  of the reusable) mints the App token inline via the same pattern. Reusable-caller repos pass
  the key in a follow-up (after `v3` advances).

- **`sync-fanout` mints a GitHub App token for the Core fan-out (G2 canary).** Following
  `GITHUB-APP-AUTH.md`, the Core fan-out now mints a short-lived GitHub App installation
  token (`actions/create-github-app-token`, SHA-pinned), scoped to the App's installed repos
  (the fan-out targets — no second copy of `scripts/os-repos.txt` to drift), instead of
  relying on the broad, hand-rotated `FLEET_SYNC_TOKEN` PAT. It is **backward-compatible**: the mint
  step runs only when the `FLEET_APP_ID` variable is set and otherwise falls back to the PAT,
  so this is inert until the fleet App is registered. First consumer migrated; `htpx`
  `sync-fanout` and the `notify-web` dispatch follow the same pattern.

- **`GITHUB-APP-AUTH.md` — the runbook to retire the fleet's cross-repo PATs (G2).** Both
  `FLEET_SYNC_TOKEN` (cross-repo push + PR in `sync-fanout`) and `WEBHOOK_SECRET` (the
  `repository_dispatch` Bearer to `dotfiles-web`) are broad, hand-rotated PATs that expire
  on a date nobody watches. The runbook specifies replacing them with **one GitHub App**
  that mints **short-lived, per-repo-scoped installation tokens** at run time
  (`actions/create-github-app-token`), a **backward-compatible** workflow pattern (mint when
  `vars.FLEET_APP_ID` is set, else fall back to the legacy PAT — so merging is inert until
  the App is registered), and the migrate → verify → retire order. Registering the App and
  resolving the action's pinned SHA are owner actions; the runbook is the design + the exact
  steps. Once it lands, the `token-health` probe becomes redundant (a minted token cannot
  silently expire).

- **`/release-readiness` + `/release-notes` maintenance routines — the judgment layer over the
  release mechanics.** `/release-readiness` is the go/no-go gate in front of `RELEASE-RUNBOOK.md`:
  it weighs the unreleased `CHANGELOG` work, the audit status, version coherence, and fleet drift
  into a **READY-to-cut-vX.Y.Z / HOLD** verdict with the next command to run. `/release-notes`
  drafts the next release's grouped notes from Conventional Commits (git-cliff, or the first-party
  `gen-release-notes.sh` when the binary is absent) as raw material to curate into `[Unreleased]`.
  Both are report-first (they edit nothing). `release-readiness` rides the `claude-routines` rail
  weekly (Tue 10:00 UTC, last in the Opus stagger); `release-notes` is dispatch-only (you draft at
  release time, not on a beat). Both `fetch-depth: 0` for the `git log <last-release>..HEAD` range.

- **Real release notes for OS-repo tags — `scripts/gen-release-notes.sh` (G5).** OS-repo
  auto-releases shipped a bare tag with GitHub's raw PR-list (`--generate-notes`); they now
  ship a grouped Conventional-Commit changelog. `auto-tag.sh --release` drafts the notes for
  the `latest..NEXT` range and feeds them to `gh release create --notes-file`, falling back
  to `--generate-notes` when a range has no conventional commits. The generator is the
  **first-party twin of Core's `cliff.toml`** — same grouping (Features / Bug Fixes / … in
  commit-parser order) and one-bullet-per-commit shape, but pure `git` + `awk` so it needs
  no git-cliff binary (the fleet's "no third-party CI tool we can't pin" discipline — the
  same reason zizmor stayed deferred). Also bumps `auto-tag-call.yml`'s internal core
  checkout from the stale `@v2` to `@v3` (it now carries both release scripts).

- **A weekly fleet freshness dashboard — one hub health board.** `scripts/freshness-dashboard.sh`
  consolidates the fleet's otherwise-scattered freshness signals — vendoring drift
  (`fleet-drift.sh`), vendored-`core/` integrity (`core-integrity.sh`), and zsh/nvim
  plugin-pin freshness (`update-*-plugins.sh --check`) — into a single glanceable markdown
  board, with links to each repo's Renovate dependency dashboard and the token-health probe.
  `.github/workflows/freshness-dashboard.yml` runs it Mondays 10:00 UTC (after the morning
  sweeps settle) and files a deduplicated issue that updates in place. It _reports_, never
  mutates — the sub-gates still enforce; this is the "how healthy is the fleet this week?"
  view in one place. Run locally with `make freshness-dashboard`.

- **A `/modernize` maintenance routine — the judgment half of the modernization floor.**
  `check-modern.sh` _enforces_ the current floor (`scripts/modern-baseline.yml`); this
  routine scouts what the _next_ floor should be. It reads the declared floor and the
  fleet's workflows, researches the latest runner/action deprecations (EOL runner
  labels, the `node16`→`node20`→`node24` action-runtime treadmill, pinning-discipline
  gaps, new hardening dimensions), and files a **report-first** proposal — the exact
  baseline edit, the dated upstream source, and whether it is enforceable today or needs
  fix-first workflow changes. Runs headless weekly on the `claude-routines` rail (Tue
  09:00 UTC, last in the Opus stagger) and files a deduplicated issue; edits nothing.

- **Renovate adoption via a shared org preset (replaces Dependabot).** The fleet's
  dependency-update policy now lives once in `dotgibson/.github` (`default.json`) and
  every repo opts in with a three-line `renovate.json` that extends it — the same
  hub-and-spoke centralization Phase 1 applied to reusable workflows, now for
  dependency management (closes the "no Dependabot/Renovate outside core & Windows"
  gap). The preset keeps Renovate in lock-step with the modernization floor
  (`scripts/modern-baseline.yml`): it _maintains_ SHA-pinned actions and `@sha256:`
  container digests rather than un-pinning them, groups third-party action bumps into
  one weekly `ci(deps):` PR, and deliberately leaves the fleet's own `dotgibson/**`
  reusable-workflow refs on their moving `@v3` major tag (advanced by the release
  process, not a bot). Core retires its standalone `.github/dependabot.yml`;
  `renovate.json` is allowlisted in `audit-core.sh` as repo-meta.

- **A modernization floor for CI: `scripts/modern-baseline.yml` + `scripts/check-modern.sh`,
  gated by `audit-core.sh` (section 8c).** The baseline declares what "modern" means — no
  removed workflow commands (`::set-output`/`::save-state`/…), no EOL runners, every external
  action pinned to a 40-hex SHA (the fleet's own `@vN` reusable workflows exempt), and every
  container image pinned to an `@sha256:` digest — and the checker enforces it so a workflow
  can't silently regress below it. This generalizes the fleet's existing SHA-pin discipline
  into one contract and closes the last break in it (mutable container tags: `alpine:3.21` and
  `archlinux:latest` in `ci.yml` are now digest-pinned). Run standalone with `make check-modern`.

- **difftastic (`difft`): an opt-in, structure-aware diff companion to delta.**
  `tools.zsh` now detects it (`HAVE_DIFFT`), `git/gitconfig` defines a
  `difftool "difftastic"` plus a `git dft` alias, and `aliases.zsh` adds a
  `HAVE_DIFFT`-guarded `gdft` shortcut. difftastic diffs by AST (tree-sitter), so
  formatting-only churn — rewraps, moved elements, trailing commas — shows as no
  syntactic change. It is deliberately **additive, never the default**: delta stays
  the `git diff` syntax-highlighting pager and difft is only reached on demand via
  `git dft`/`gdft`, so nothing changes on a box without the binary. Documented in
  `PORTING-MATRIX.md` (packaged on Arch/Alpine-musl/Fedora/Gentoo/openSUSE/Homebrew/
  Debian-Kali; `cargo`/`mise` where unpackaged).

### Fixed

- **docs: `PORTING-MATRIX.md` clipboard section claimed the backend is "swapped
  in `os/<distro>.zsh`".** Clipboard selection actually lives in Core's cross-OS
  `clip`/`clip-paste` scripts — each `os/*.zsh` only aliases `pbcopy`/`pbpaste` to
  them. Reworded the heading to "Clipboard packages to install" (the table's
  package names were always correct); surfaced by `/doc-audit`.

- **ci: `update-nvim-plugins.sh` exited non-zero when the lock was already
  current.** In apply mode the "already current" branch ended on `((CHECK))`
  (exit status 1 when `CHECK=0`), so the script returned 1 with nothing wrong —
  and under the freshness bot's `set -e` that turned a no-op week into a red nvim
  job (and, now that failure-alerting works, a false issue). It exits 0 explicitly.

- **docs: `aliases.md` was missing `gdft`.** The difftastic-backed `git difftool`
  shortcut (added alongside `HAVE_DIFFT` and `git dft`) landed in `zsh/aliases.zsh`
  without a matching entry in the cheat sheet — added to the Diff table.

- **maint: the daily runner now reconciles pinned zsh plugins by CONFIG, not
  checkout state.** `maint/dotfiles-maint.sh` decided "pinned vs unpinned" by
  asking whether a plugin's `HEAD` was detached — but a plugin cloned before
  `plugins.zsh` began pinning (or by the old floating `--depth=1` path) sits on a
  branch even though it IS pinned in `ZPLUGIN_PINS`. Those were wrongly
  `git pull --ff-only`'d every run: floating them off their pins, and logging a
  false `✗ … (pull failed)` for any whose branch couldn't fast-forward (e.g.
  `zsh-syntax-highlighting`). The loop now reads the pins straight from
  `plugins.zsh` (same grep `update-plugins.sh` uses — bash-3.2 safe) and, for any
  pinned plugin, re-asserts the recorded SHA (fetch + detach, mirroring
  `zplugin-update`): a branch checkout is reconciled back onto its pin, a rolled
  pin is now actually applied by the runner, and plugins already at their pin do
  zero network. Only genuinely unpinned plugins still fast-forward.

## [v3.1.0] - 2026-07-06

### Added

- **`assets/`: a reproducible VHS tape for the README hero demo.**
  `assets/demo.tape` scripts a short terminal tour (eza, bat, zoxide, `core help`,
  `glog`) that renders to `assets/demo.gif` via `vhs assets/demo.tape`, so the hero
  can be regenerated rather than hand-recorded. `assets/README.md` documents the
  render steps; `assets/` is allowlisted in `audit-core.sh` as repo-meta (it rides
  along in the subtree copy but is never symlinked).
- **README: a structured four-row badge block at the top.** Row 1 is repo
  status & automation — live `ci` and `core-integrity` Actions status,
  open-issue / open-PR counts, repo size, and latest release. Row 2 is the
  MIT license (auto-detected from `LICENSE`) plus last-commit / commit-activity.
  Row 3 is the languages (Zsh, Bash, Lua, TOML, YAML, JSON) and Row 4 the
  tooling (Neovim, Vim, tmux, Starship, Git, 1Password). Tools with no
  simpleicon (`mise`, `lazygit`, `jujutsu`, `sesh`, `fzf`) share a substitute
  `gnometerminal` glyph on a Tokyo Night purple label.
  Every brand color is taken from the `simple-icons` dataset (e.g. Lua `000080`,
  Git `F03C2E`, 1Password `145FE4`). Vim is the `vim/vimrc` fallback editor for
  boxes with no nvim, not just the `vim=nvim` alias; the tooling row covers
  every tool Core ships a dedicated config for. Each Row 3/4 badge links to its
  upstream project on GitHub and, where the project publishes releases/tags,
  shows the current upstream version live (Neovim, Vim, tmux, Starship, Git,
  Lua, TOML, mise, lazygit, jujutsu, sesh, fzf); Zsh, Bash, YAML, JSON, and
  1Password have no clean upstream version and stay plain. On the versioned
  badges the name side carries the brand color and the version side is a Tokyo
  Night blue (not grey). Row 1 leads with a `dotgibson` badge that shows the
  current release version (dynamic `github/v/release`) with the org avatar as
  its icon (base64 data-URI logo) and links to the latest release. All `flat-square`; the old hardcoded `audit-passing`
  shield is replaced by the live `ci` status it stood in for.
- **nvim: `utils/ui-highlights.lua` — a flat table of NvChad-flavored highlight
  overrides.** Hairline window splits (`WinSeparator`/`VertSplit`), minimal
  rounded floats (`NormalFloat`/`FloatBorder`/`FloatTitle`), a border-tinted
  fzf-lua palette (`FzfLua*`), a matching blink.cmp menu/docs palette
  (`BlinkCmp*`), and NvChad's dim-linenr / bright-current-line gutter. Applied
  through tokyonight's `on_highlights` in `plugins/theme.lua`, so it re-runs on
  every `:colorscheme` and recolors from whatever `style`/theme is active — no
  `ColorScheme` autocmd, no per-plugin hardcoded hexes. Deliberately one flat
  function, not a helper framework.

### Changed

- **README: reworked into a lean public landing page.** Replaced the long-form
  technical README with a concise landing page — a lead stating Core is the vendored
  foundation layer (you install an OS repo, not this one), an at-a-glance three-layer
  table, a modern-CLI Usage section framed by the `HAVE_*` detection-flag fallback,
  and the repo's real contribution contract. The deep architecture and reference
  material now lives on the documentation hub at `dotfiles-web`. Fixed broken links
  along the way (`LICENSE`, `aliases.md`, the issue-template deep-links, a malformed
  acknowledgment link), and scoped MD033 in `.markdownlint.jsonc` with
  `allowed_elements` so the intentional showcase inline HTML passes the markdown gate
  while the rule still catches unexpected tags. The hero image is now the rendered
  terminal demo (`assets/demo.gif`, produced from `assets/demo.tape`).
- **nvim: the statusline now wears NvChad's rounded block look.** `plugins/lualine-nvim.lua`
  keeps its sections and (intentionally) its existing diagnostic glyphs — which
  stay in lockstep with `utils/diagnostics.lua` and the tabline — but swaps
  powerline arrows for NvChad's half-circle bubble caps (U+E0B6 / U+E0B4)
  and drops inner component separators so each half reads as one clean run of
  blocks. Adds a cwd (project basename) segment on the right, the cue a global
  statusline otherwise loses. Still a standard lualine config — no NvChad
  backend, no statusline caching, no managed toggle state.
- **nvim: fzf-lua now mirrors NvChad's telescope layout.** `plugins/fzf-lua.lua`
  gains `winopts`/`fzf_opts` translated 1:1 from `nvchad/configs/telescope.lua`
  (width 0.87, height 0.80, 55% preview on the right, prompt on top, a
  U+F002 magnifier prompt prefix, a U+F0DA selection caret) with rounded
  borders — the minimal
  NvChad finder look, on the finder you actually run (fzf-lua, not telescope).
- **nvim: the bufferline tabline picks up NvChad's flat-tab modified dot.**
  `plugins/bufferline-nvim.lua` sets `modified_icon` to the same ● (f111) used by
  lualine and incline, and annotates `separator_style = "thin"` as the flat,
  NvChad-tabufline-style rectangular tabs it already produces.

## [v3.0.1] - 2026-07-03

### Changed

- **nvim: the cheatsheet's three entry points now share one opener.** `<leader>?`
  and the `:Cheatsheet` / `:Cheat` user commands each inlined the same
  `require("gerrrt.cheatsheet").open()` thunk; they now call a single local
  `open_cheatsheet`, so the three can't drift and a future option/argument is a
  one-line edit. No user-visible change — `require` is still deferred to first open.

### Fixed

- **`gsync` was undocumented in `aliases.md`.** The upstream-sync helper
  (`zsh/aliases.zsh`, pushes an OS repo's vendored `core/` back to dotfiles-core)
  had no entry in the aliases cheat sheet. Added an "Upstream Sync" section.

## [v3.0.0] - 2026-07-02

### Added

- **nvim: a full-screen keybinding cheatsheet — the whole map, not the live
  prompt.** which-key is great at "I pressed `<leader>`, what's next?" but useless
  for "what do I even have?" — so the config's ~30 lazy plugin specs accreted
  features faster than muscle memory could keep up. The new
  `lua/gerrrt/cheatsheet.lua` renders every curated binding at once in a centered,
  NVChad-style floating panel: task-grouped cards (Essentials, Flash, LSP & Code,
  the three Git groups, Debug, Test, Folds, Text objects & Surround, Sessions, …)
  auto-packed into as many columns as the terminal is wide, tokyonight-themed via
  `default = true` highlight links so it also degrades cleanly on a bare box.
  Opened with **`<leader>?`** or **`:Cheatsheet`** (`:Cheat`); `q` / `<Esc>` close.
  Pure Neovim API, no new plugin dependency, and the module is `require`-d lazily
  so it costs nothing at startup. It is **hand-curated on purpose**: most mappings
  are bound lazily and aren't registered until their plugin loads, so scraping
  `nvim_get_keymap()` at open time would show a half-empty, load-order-dependent
  list — the table is the intentional, always-complete picture, and lives beside
  the specs it mirrors so a new binding gets a new row in the same review.

### Changed

- **nvim: `<leader>?` now opens the new cheatsheet instead of which-key's
  buffer-local-keys popup; that popup moves to `<leader>wk`.** Repointing a public
  binding is the one intentional breaking change in this release — the whole map
  is the more useful thing to keep on the mnemonic "help" key, and the live
  per-buffer prompt is one keystroke away under a new (which-key-labelled) `w`
  group. Existing `<leader>?` muscle memory now lands on the bigger view.

- **starship: pin an explicit `command_timeout = 1300` (was the implicit 500ms
  default).** The value is both a correctness knob and a safety valve. Correctness:
  a `git status` on a large or cold repo can exceed 500ms, and the default would
  blank the git segment mid-render; 1300ms clears that on real repos. Safety valve:
  `command_timeout` is the bound at which starship abandons AND kills the external
  command backing a segment (the `git_*` modules, any `[custom]` command). When a
  git call wedges — a stale `.git/index.lock`, a repo on a slow `\\wsl$`/network
  path, a hung credential probe — the child is now reaped at this bound instead of
  left running. That matters most on Windows, where an un-reaped git child orphans
  and one-per-prompt-render piles up into hundreds of stuck `git.exe` (enough that
  scoop/winget can't then replace the in-use git binary to update it). Pairs with a
  Windows-side pwsh change that makes shell-spawned git fail fast rather than block
  on an auth prompt.
- **Repo-location references migrated from the `Gerrrt` personal account to the
  `dotgibson` org.** Vendored-out URLs (`.bin/sync-upstream.sh`, `ARCHITECTURE.md`),
  the reusable-workflow `uses:` refs, the showcase Pages badge (`gerrrt.github.io` →
  `dotgibson.github.io`), and the `github.repository_owner == 'dotgibson'` guards in
  `release`/`sync-fanout`/`notify-web` (which silently no-op under any other owner)
  now point at the new org. The nvim `lua/gerrrt/**` module namespace and the
  `@gerrrt` code-owner are deliberately unchanged — those are the personal handle,
  not repo locations.

## [v2.6.0] - 2026-06-30

### Added

- **`sesh` detection (`HAVE_SESH`) — finishing wiring Core already half-shipped.**
  `sesh` (joshmedeski's smart tmux session manager) was already driven by the
  `Ctrl-G` shell widget (`fzf.zsh`), the `prefix + f` tmux popup (`tmux-sesh.sh`),
  a seeded `sesh/sesh.toml.example`, and listed in `core-doctor`'s integrations —
  but `tools.zsh` never set a `HAVE_SESH` flag for it the way it does for the
  other detected tools. (Detection itself still worked — the `Ctrl-G`/`prefix + f`
  fallback keys off `command -v sesh`, and `core-doctor` already probes `sesh`
  the same way.) `tools.zsh` now sets
  `HAVE_SESH` (like `HAVE_GUM`, no `_core_wired` arm — sesh registers no persistent
  shell hook, so presence ≈ wired), and `PORTING-MATRIX.md` gains a `sesh` row +
  footnote documenting the `go install github.com/joshmedeski/sesh/v2@latest` build
  path (the **v2** module path; `go` is already a pinned mise runtime) for the
  distros that don't package it. No `core.manifest` change — the `.example` is
  already listed.
- **`RELEASE-RUNBOOK.md`** — the step-by-step, copy-paste recipe for cutting a release
  (Core, the OS-repo fan-out rollout, and htpx), plus a "dry-run a new cross-repo
  workflow before relying on it" habit and a troubleshooting table. Complements
  `RELEASE-STRATEGY.md` (the policy); cross-linked from it and `CLAUDE.md`.

### Changed

- **nvim: disable `<LeftDrag>` and `<LeftRelease>` in all modes unconditionally.**
  Previously these were suppressed only when inside a `$TMUX` session, in Normal and
  Visual modes. They are now `<Nop>` in Normal, Insert, and Visual modes regardless of
  environment, eliminating accidental mouse-drag selections during terminal use.

- **`bootstrap-test.yml` retries the per-distro `prep` step (up to 5x with backoff).**
  The reusable links-only job ran the dep install once; a transient distro-mirror
  timeout (notably openSUSE Tumbleweed's OSS CDN) then redded the job — and every Core
  fan-out PR — on a network blip. The retry is fleet-wide (one place, every caller);
  a genuinely broken prep still fails loud after the attempts are exhausted.

## [v2.5.0] - 2026-06-29

### Added

- **jujutsu (`jj`) as an OPT-IN, colocated git companion.** Additive — it never replaces
  git. New `jujutsu/config.toml` (symlinked to `~/.config/jj/config.toml`, in
  `core.manifest`) sets a sensible colocated-friendly default (`ui.default-command = "log"`,
  `auto-local-bookmark`; identity intentionally unset — jj does NOT inherit git's
  `user.name`/`user.email`, so an opt-in author sets it once with `jj config set --user
  user.name/user.email`). `tools.zsh` gains `HAVE_JJ`
  detection and `aliases.zsh` a few `HAVE_JJ`-guarded verbs (`jjs`/`jjl`/`jjd`); nothing
  is aliased over `git`. On a box without `jj` everything is inert. `PORTING-MATRIX.md`
  documents per-distro packaging (packaged on Arch/openSUSE/Gentoo/Fedora/Homebrew/nix;
  `cargo install jujutsu` on Alpine(musl)/Debian-Kali — same pattern as yazi/ouch).

### Changed

- **zsh syntax highlighter swapped: `fast-syntax-highlighting` →
  `zsh-users/zsh-syntax-highlighting` (z-sy-h).** The pin moves to z-sy-h (a maintained,
  first-party `zsh-users` plugin) and the load order is corrected per its README: the
  highlighter is now the LAST widget-wrapping plugin sourced, with
  `zsh-history-substring-search` deferred immediately after it so its widgets get wrapped.
  The `FAST_THEME`/`FAST_HIGHLIGHT` theming is replaced by minimal `ZSH_HIGHLIGHT_HIGHLIGHTERS`
  (`main` + `brackets`) and `ZSH_HIGHLIGHT_STYLES` recoloured to the Tokyo Night Storm palette.
- **`fleet-drift.sh` anchors to the latest released Core tag by default, not the working
  tip.** Fan-out stamps each OS repo with the Core _tag_ it carries, so the dashboard now
  measures against the newest `vX.Y.Z` (via `git describe`), falling back to
  `origin/main`/`main`/`HEAD`. An explicit `--ref`/`$CORE_REF_SHA` still wins. This stops
  the false "BEHIND by N" the report showed for every unreleased commit on `main`
  (CHANGELOG/auto-tag churn between releases); the `fleet-drift.yml` workflow drops its
  `--ref HEAD` accordingly.

### Fixed

- **`auto-tag.sh` exit-code contract hardened + tested.** Added a defence-in-depth guard so
  `_next_version` fails loudly (non-zero) on a non-`X.Y.Z` input instead of producing a
  garbage component, and the call site now propagates that failure rather than tagging a
  bogus `v`. The behavioral suite (`test-core.sh`) now asserts the full exit-code contract
  hermetically (no network/gh): success → 0, no-op → 0, validation error → 2, and a real
  create failure (a `--push` onto an already-taken tag name, tripping Guard 2) → non-zero.

- **`auto-tag.sh --release` fails CI when an opted-in Release create actually fails.** The
  `gh release create` error branch called `fail` but the script still exited 0, so a real
  failure (gh present, API error) went green with no Release. It now `exit 1`s there — the
  tag still stands (pushed above), but CI goes red so you create the Release manually. The
  two non-failure exits stay deliberate: gh absent → skip, Release already exists → no-op.
  Also added `--release` to the `usage()` synopsis line (it was only in the flag list) and
  clarified its gh/skip semantics.

## [v2.4.1] - 2026-06-29

### Changed

- **`tag-release.sh` recipe spells out the land-then-tag order.** The printed next-steps
  now make the sequence explicit — land the release commit via PR (a merge commit), _then_
  tag `origin/main` (the merged tip) so the tag sits on `main`'s HEAD and `git describe`
  stays clean — instead of tagging the pre-merge commit and re-pointing. The two tag pushes
  use `;`, not `&&` (an "already exists" on the first must not skip the second — the `vN`
  move). `PUSH=1` now warns that it tags the pre-merge commit and prints the re-point steps.

## [v2.4.0] - 2026-06-29

### Added

- **OS-repo / Windows auto-tags now publish a GitHub Release too (`auto-tag.sh
  --release`).** Core releases already become Releases on tag push (`release.yml`), but the
  OS-repo tags `auto-tag.sh` cuts in CI were bare — no Releases page entry. A token-pushed
  tag can't trigger a separate `on: push: tags` workflow (GitHub anti-recursion), so the
  Release is now created in the SAME job: `auto-tag.sh --release` runs `gh release create
  <tag> --generate-notes` right after pushing (idempotent — a no-op if the Release exists;
  a missing `gh` just leaves the tag, never fails). `auto-tag-call.yml` gained a `release`
  input (default `true`) and passes `--release`, so every consumer of `@v2` gets Releases
  on its next fan-out. Reusable beyond `core/` consumers: any repo (e.g. dotfiles-Windows
  on an `nvim/`/`starship/` sync) can call the workflow to self-tag-and-release.

## [v2.3.0] - 2026-06-29

### Fixed

- **`auto-tag.sh` hardened against irregular tags + arg edge cases.** Tag discovery now
  filters to a strict `^vX.Y.Z$` regex instead of git's loose `--list` glob, so a
  prerelease/suffixed tag (`v1.2.3-rc1`) or a moving major alias (`v2`) can no longer be
  mistaken for the latest release (which would have double-tagged or fed a non-numeric
  component into the bump). Version components are coerced base-10 (`10#`) so a zero-padded
  tag (`v1.08.0`) doesn't trip octal arithmetic. `--bump`/`--initial`/`--color` now error
  cleanly on a missing value instead of mis-consuming the next flag. `usage()` documents
  every flag + default, and the re-push hint quotes `$REPO`/`$NEXT`.
- **`auto-tag-call.yml` pins its `dotfiles-core` checkout to `@v2`.** The script is now
  fetched from the same major line callers pin the workflow to, so the tag-cutter's
  behavior can't drift from the pinned `@v2` definition between releases (matching the
  `@vN` policy). Dropped the redundant `fetch-tags` (fetch-depth 0 already brings tags).

## [v2.2.0] - 2026-06-29

### Added

- **Automatic OS-repo release tagging on Core fan-out
  (`.github/workflows/auto-tag-call.yml` + `scripts/auto-tag.sh`).** An OS repo carries two version lines — the Core it vendors
  (`core.lock`, advanced by `sync-core.sh` on every sync) and its OWN `vX.Y.Z` tag, which
  used to move only by hand and so drifted (most repos froze at an old tag; the newest had
  none). A new reusable `workflow_call` lets each OS repo cut its next tag automatically
  when a fan-out lands new `core/` on its `main`: PATCH-bump by default (a new Core is a
  maintenance bump of the consumer), `bump: minor|major` for a deliberate release. The
  version math lives in `scripts/auto-tag.sh` (shellcheck-clean, dry-run by default), is idempotent
  (a no-op when HEAD is already a `vX.Y.Z` release), and tags in CI — so no operator
  round-trip and no reliance on a local tag push. Each OS repo adds a three-line caller
  (`on: push` to `main`, `paths: ['core/**']`).

## [v2.1.1] - 2026-06-29

### Fixed

- **`bootstrap.sh --links-only` no longer aborts when zsh isn't installed.**
  `blib_set_login_shell` did `zsh_path="$(command -v zsh)"`; with zsh absent that
  substitution exits non-zero, and under the bootstrap's `set -e` it aborted the run
  _before_ the `[[ -n "$zsh_path" ]] || return 0` guard that was meant to handle the
  missing-zsh case — surfacing as a links-only CI failure in the one base image
  without zsh preinstalled (`gentoo/stage3`). Now `command -v zsh || true`, so the
  guard decides, not errexit. No behavior change where zsh is present.
- **`tag-release.sh --push` no longer pushes the protected `main` branch.** `main`
  enforces required status checks (GH013), so the old step — `git push origin "$BRANCH"
  && git push origin "$TAG" && git push -f origin "$MAJOR"`, branch FIRST — had its
  branch push rejected, which short-circuited the `&&` chain so the tags never pushed
  either: `--push` failed outright and could never complete a release through the push
  path. The step now pushes the immutable `vX.Y.Z` tag and force-moves the `vN` major
  alias ONLY (tags aren't branch-protected), then prints the PR recipe to land the
  release commit on `main` (`HEAD:release/vX.Y.Z` → PR → merge commit), matching how
  releases actually ship (e.g. #95). The non-push recipe block was corrected the same way.

## [v2.1.0] - 2026-06-29

### Fixed

- **`starship.toml` VPN segment no longer spams on Windows.** The `[custom.vpn]`
  probe (`ifconfig …`) is Unix-only; once the canonical file synced to the Windows
  host verbatim, starship ran it every prompt and hit `command_timeout` with a noisy
  `custom command … timed out` WARN. Split it into OS-gated `[custom.vpn_macos]` /
  `[custom.vpn_linux]` modules (a custom module's `os` takes one value — no "unix"),
  so Windows matches neither and never runs the probe. Unchanged on macOS/Linux.

### Added

- **Core-integrity CI guard (`make core-integrity` + `core-integrity.yml`).** A
  durable, CI-runnable tamper check: it compares each OS repo's vendored `core/` tree
  object against the commit its `core.lock` pins (content-addressed, so any hand-edit
  diverges the hash). Replaces the local-only `.git/hooks` core-guard, which couldn't
  run on a fresh clone or in CI. Companion to `fleet-drift` (integrity vs staleness) —
  both run weekly and on demand.
- **Per-repo core-guard (`core-integrity-call.yml` + `core-integrity.sh --self`).**
  A reusable `workflow_call` an OS repo invokes from its own CI to BLOCK a hand-edit
  to its vendored `core/` at PR time (prevention), where the central sweep only
  DETECTS one after the fact. Runs the same tree-SHA comparison via a new `--self`
  mode that checks exactly one repo against its `core.lock`. Each OS repo adds a
  three-line caller.

### Changed

- **Reusable-workflow pin policy: `@vN` moving major tag.** `tag-release.sh` now
  force-advances a `vN` major tag (e.g. `v2`) to each `vN.x` release, alongside the
  immutable `vX.Y.Z` tag. Cross-repo callers of the fleet's reusable workflows
  (`bootstrap-test.yml`, `core-integrity-call.yml`) pin to `@vN` instead of `@main`:
  deterministic between releases (a caller's CI can't change with zero diff in its
  repo) yet still auto-propagating patch/minor guard fixes. Documented in
  `RELEASE-STRATEGY.md`. (Foundation only — re-pinning the existing `@main` callers
  fleet-wide is a follow-up once a `v2` tag is published.)
- **`fleet-drift.sh` labels the Windows row by release tag too.** `_check_repo`
  gained a fourth `tag-key` argument (default `core_tag`); the Windows row passes
  `tag`, so once `dotfiles-Windows`'s `nvim-sync.ps1` stamps a `tag = <release>`
  field into `nvim/.core-ref` (its companion change), the dashboard shows `v2.0.0`
  for Windows instead of the bare SHA — all nine rows now speak in release names.
  Backward compatible: with no tag recorded it still falls back to the short SHA,
  and the drift verdict stays SHA-based. Verified both paths against a fixture.
- **`starship.toml` is now cross-shell (one canonical file).** Added
  `powershell_indicator` to `[shell]` so the single Core `starship.toml` renders under
  both zsh and PowerShell, and dotfiles-Windows now syncs this file verbatim (its new
  `starship-sync.ps1`) instead of carrying a drifted copy. Benign on zsh — starship
  only renders the active shell's indicator.

## [v2.0.0] - 2026-06-28

> **Breaking — keybindings realigned.** The zsh file-picker moved off `Ctrl+F` to
> **`Ctrl+T`**, and the cross-shell keys were settled fleet-wide: **`Ctrl+E`** atuin
> TUI, **`Ctrl+R`** quick fzf history, **`Ctrl+G`** jump-to-session (navi dropped its
> `Ctrl+G` widget for the `navi` command), **`Alt+Z`** zoxide jump. Update muscle
> memory and re-source your shell (or restart it) after the next `make sync`. This is
> the breaking change that makes this release **2.0.0** rather than a 1.x bump;
> everything else below is additive or a fix.

### Changed

- **`/freshness-triage` now covers the CLI tool pins.** The routine reviewed zsh/nvim/
  actions bumps but said nothing about `scripts/tool-versions.env` — the one bump class
  that also needs `make update-tool-checksums` to refresh its `*_SHA256`. Added a section
  so a `*_VERSION` change without its checksum is flagged **Hold** (the audit only checks
  the hash is _present_, not correct, so a stale hash otherwise fails late at the action's
  `sha256sum -c` in CI). Routine-doc only; no code change.
- **Cross-shell keybindings aligned (PARITY.md decisions resolved).** The four open
  parity decisions are settled and implemented on both shells: **Ctrl+T** = file picker
  (zsh moved off `Ctrl+F`), **Ctrl+E** = atuin TUI / **Ctrl+R** = quick fzf history,
  **Ctrl+G** = jump-to-session everywhere (zsh sesh; the host gets a psmux sessionizer,
  with navi demoted from its Ctrl+G widget to the `navi` command), and **Alt+Z** = zoxide
  jump + `gaf`/`grf`/`grsf` fuzzy git staging ported to pwsh. Core's functional change is
  the file-picker rebind (`zsh/bindings.zsh`: `Ctrl+F`→`Ctrl+T`), with the announced key
  updated everywhere it appears (`zsh/fzf.zsh` warning + comments, the `core-help` cheat
  row in `zsh/functions.zsh`, `tmux/scripts/tmux-cheat.sh`, `README.md`, and the
  `test-core.sh` assertions); the pwsh half lands in `dotfiles-Windows`. The six rows
  moved to `aligned` (file-picker, atuin, dir-jump, session-picker, fuzzy-git, cheat) are
  each enforced by a `scripts/parity-check.sh` needle. `make audit` + `make parity-check` green.
- **`bootstrap-lib.sh` gains opt-in dry-run + tallies** (`lib/bootstrap-lib.sh`) — the
  shared provisioning scaffold now honors `BLIB_DRY=1`: `blib_link` / `blib_seed` /
  `blib_link_core` / `blib_write_zshrc_loader` / `blib_set_login_shell` PRINT what they
  would do and change nothing — every mutation (symlink, backup, seed copy, chmod, the tpm
  clone, the ssh perms, the `.zshrc` write, the `chsh`) is guarded — so an OS bootstrap's
  `--dry-run` can preview the whole plan instead of each repo hand-rolling it. `blib_link`
  also gained an idempotent already-correct-link no-op and a missing-source skip; the two
  inline git/sesh seed blocks are unified into a new `blib_seed`; `BLIB_*` counters +
  `blib_wire_summary` give a "N linked · M seeded · K backed up" footer. **Backward
  compatible** — `BLIB_DRY` defaults off and the non-dry path is byte-for-byte the prior
  behaviour, so the already-adopted Fedora/Arch/Alpine/openSUSE/Gentoo/Kali bootstraps are
  unaffected. This unblocks MacBook adopting the shared scaffold without losing its
  `--dry-run`. Verified: dry run creates zero files; a real run wires all 25 links + 2
  seeds; a re-run backs up nothing.
- **De-forked `update.zsh`'s per-shell path** (`zsh/update.zsh`) — the throttle check
  and the upgrade nudge ran `date +%s` once and `sed -n Np` twice on **every**
  interactive shell, three subprocess spawns (~1.7 ms each, measured) on the critical
  path before the first prompt — the exact fork tax this stack's cached inits + deferred
  plugins exist to avoid. Replaced with zsh builtins: `$EPOCHSECONDS` (a `zsh/datetime`
  param) for the clock and `$(<file)` + `${(f)…}` for the two-line cache read, removing
  all three forks (~5 ms off a warm shell) with byte-identical behaviour and a `date`
  fallback if the module is unavailable. Profiled with `make profile`; the `_pkgup_*`
  parse + nudge unit tests are unchanged and green. (A profile-led pivot: caching
  `tools.zsh`'s `command -v` probes — only ~1.8 ms total, and a stale cache could hide a
  newly-installed tool — was measured and rejected as not worth the footgun.)
- **Dropped `dotfiles-Debian` from the documented fleet.** The Debian OS-native
  repo was only ever planned, never created, and is no longer being pursued — so
  the fleet docs that named it as a real target were ahead of reality. Removed it
  from the OS-native repo lists (`README.md`, `CLAUDE.md`, `CONTRIBUTING.md`,
  `SECURITY.md`, `PORTING-MATRIX.md`), reframed it in `scripts/os-repos.txt` from
  "planned" to a documented permanent absence (so it is not re-added), and dropped
  it from the `claude-routines` fleet-clone loop. This also reconciles the
  "nine-repo system" / "seven vendoring OS repos" counts, which the phantom Debian
  entry had thrown off by one. Debian _distro-family_ facts (the `bat`→`batcat` /
  `fd`→`fdfind` renames, Kali being Debian-family) are unaffected and retained.
- **Hardened the Track B module selector** (`lib/bootstrap-lib.sh`) — two fixes from
  review of the fan-out PRs. `blib_select` now **fails fast on an unknown flag** (a
  `*)` arm warns + `exit 1` instead of silently falling through without recording a
  selection, so a caller typo can't make filtering appear to "work" while wiring
  everything). And `blib_selected_note` now **mirrors `blib_want`'s precedence**: since
  `--only` is an allowlist that wins when set, a co-present `--skip` is ignored — the
  note reports a single active mode (`only` when set, otherwise `skip`) rather than
  appending a misleading `(skipped: …)` suffix that was never applied. **Backward
  compatible** — the single-selector and no-selector paths are unchanged. `test-core.sh`
  Section G gains an unknown-flag rejection case, a `--skip`/both-set precedence check on
  the note, and a `BLIB_MODULES` drift guard pinning the production group list to the
  tested oracle. `make audit` green.

### Added

- **Auto-published GitHub Releases on tag push** (`.github/workflows/release.yml`).
  Pushing a `vX.Y.Z` tag now publishes the GitHub Release automatically, finishing
  the `make release … && make tag PUSH=1` path. The Release body is the curated
  `CHANGELOG.md` section for that version (not a git-cliff commit digest — CHANGELOG
  is the source-of-truth prose), and the job refuses to publish unless the tag is a
  clean SemVer that matches `core.version` at the tagged commit and the section
  exists. Uses the built-in `GITHUB_TOKEN` via the preinstalled `gh` CLI — no PAT,
  no third-party action. Re-running updates the existing Release's notes idempotently.
  Also refreshed `cliff.toml`'s header (the repo DOES git-tag now) and
  `RELEASE-STRATEGY.md` (§5 checklist + §6) to match.
- **Release-automation: the three gaps `RELEASE-STRATEGY.md` flagged are now
  wired.** (1) `sync-core.sh` stamps a `core_tag` field (`git describe` of the
  vendored commit) into each OS repo's `core.lock`, and `fleet-drift.sh` shows it
  in the `RECORDED` column — so the drift dashboard speaks in named releases, not
  just SHAs (the SHA still drives the verdict; the tag is display only, and the
  line is emitted only once Core actually carries a tag, keeping `core.lock`
  byte-identical to today until the first release). (2) A new `audit-arch` leg in
  `ci.yml` runs the shell-scope audit inside `archlinux:latest` (rolling glibc
  toolchain, newer than Ubuntu LTS), mirroring the existing `audit-alpine`
  (musl/busybox) leg — so Core is proven on both named container userlands before
  a tag. (3) `scripts/tag-release.sh` + `make tag` finish a release: commit
  `core.version` + `CHANGELOG`, create the annotated `vX.Y.Z` tag, re-run the
  audit gate; pushing is opt-in (`make tag PUSH=1`). `make release VERSION=X.Y.Z
  && make tag` is now the whole cut end to end.
- **`RELEASE-STRATEGY.md` — the cadence, tagging, and rollout policy.** The repo
  shipped all the release _machinery_ (`core.version`, `scripts/release.sh`, the
  `sync-core.sh` fan-out gate, `core.lock` provenance, the Monday freshness/drift
  bots) but no documented _policy_ tying it together. The new doc adds that: Core
  as the sole versioned unit, a three-track cadence (continuous / weekly pin bumps
  / monthly + security tags), SemVer mapped to host blast-radius, why the
  three-layer subtree model beats `common/`-plus-conditionals, and a canary-first
  staged rollout so a Core release reaches one OS before all eight. Registered in the audit's
  `META_ALLOWLIST`. Docs-only; no behavioral change.
- **`dotfiles-Defense` joins the fleet as the defensive (blue) Role.** The
  three-layer model always had room for a second Role beside `dotfiles-Kali`;
  defender-authored capability (Sigma rules, Sysmon baselines, Zeek/Suricata
  tuning, SIEM content, the hunt/triage workflow, a Dockerized detection lab) now
  has its own repo instead of living as attack-paired notes in Kali's
  `PURPLE-TEAM.md`. Core is vendored into it like any OS/Role repo, so the fleet
  grows: **nine → ten** config repos, **eight → nine** machine repos, **seven →
  eight** Core-vendoring targets. This sync carries the count + Role-layer wording
  updates fleet-wide (`README.md`, `CLAUDE.md`, `ARCHITECTURE.md`, `SECURITY.md`,
  `CONTRIBUTING.md`, the issue templates) and adds `dotfiles-Defense` to
  `scripts/os-repos.txt` so `sync-core.sh` fans Core into it. Docs/data only; no
  behavioral change to Core.
- **`bootstrap-lib.sh` gains `--only`/`--skip` module selection** (`lib/bootstrap-lib.sh`)
  — the shared scaffold can now wire a SUBSET of the Core groups: `zsh nvim tmux git
  prompt tools`. New `blib_select <--only|--skip> <csv>` (validates a comma-separated
  selector — empty / leading / trailing / doubled commas and unknown groups all abort),
  `blib_want <group>` (consulted by `blib_link_core`, `blib_link_os_layer`,
  `blib_write_zshrc_loader`, `blib_set_login_shell`), and `blib_selected_note` for a
  summary suffix. Each OS overlay rides with its Core group (`os.zsh`→zsh, `os.conf`→tmux,
  `os.gitconfig`→git). This is the Core half of the dotfiles-web Bootstrap Command
  Generator's "Track B"; each OS `bootstrap.sh` just routes its `--only`/`--skip` here.
  **Backward compatible** — with neither selector set everything is wired exactly as
  before, so every existing caller is unaffected. `make audit` green.
- **`gsync` upstream-sync shortcut** (`.bin/sync-upstream.sh`, `zsh/aliases.zsh`) —
  a one-word alias that `git subtree push`es an OS repo's vendored `core/` subtree
  back upstream to dotfiles-core (`main`) — the prefix that matches the registered
  `core/` ⇄ root@main subtree boundary. The runner refuses to run unless a `core/`
  subtree is present (so it no-ops in dotfiles-core, the source of truth) and bails
  on a dirty working tree. The alias resolves the script relative to the sourced
  module via the `${(%):-%x}` trick (the same one `maint.zsh` uses), so the
  shortcut survives the `core/` subtree vendoring without putting `.bin` on `PATH`.
  Registered in `core.manifest`.
- **`ARCHITECTURE.md`** — a strategic architecture overview: the three-layer
  model and its boundary test, the full fleet map (which repos vendor `core/`
  and which don't), the one-directional subtree vendoring topology, the
  load-bearing zsh load order, the audit gate, and the rationale for the model.
  Sits above `README.md`/`CONTRIBUTING.md` (which stay operational) and
  cross-references them. Added to the audit's repo-meta allowlist; it is docs,
  not shipped Core.
- **`parity-check` gate** (`scripts/parity-check.sh`, `make parity-check`, weekly
  `.github/workflows/parity-check.yml`) — mechanises the `aligned` rows of `PARITY.md`:
  asserts a distinctive needle (starship/zoxide/atuin init, the fzf tokyonight palette,
  the `fd` default command) is present in **both** a zsh source and the pwsh source,
  failing when one side drifts. Reads pwsh from a sibling `dotfiles-Windows` checkout
  (skipped with a notice if absent, unless `--strict`; the workflow clones it and runs
  `--strict`), the same cross-repo pattern as `fleet-drift.sh`. The fzf-palette row is
  the regression guard for the parity fix just shipped; keybinding rows join the checker
  as each open decision is made. `make audit` green.
- **`PARITY.md` — the cross-shell parity contract** — the source of truth for what
  "the same on zsh and PowerShell" means, mapping every prompt/alias/keybinding/
  function capability to `aligned` (must stay in step), `deliberate` (intentional
  platform difference), or `gap` (open item). Makes the WSL-zsh ↔ Windows-pwsh
  divergences a documented decision instead of silent drift, and names the open
  decisions (the `Ctrl+G` sesh-vs-navi collision, the file-picker key, the atuin
  key, the `gaf`/`grf`/`grsf` + `Alt+Z` ports). Paired with a same-change fix that
  brings the **fzf tokyonight-storm palette to pwsh** (`dotfiles-Windows`
  `powershell/core/10-tools.ps1`), which previously fell back to terminal-default
  colours — the first `aligned` row closed. A future `scripts/parity-check.sh` can
  mechanise the `aligned` rows the way `fleet-drift.sh` mechanised provenance.
- **`core/` edit guard** (`blib_install_core_guard` in `lib/bootstrap-lib.sh`, wired into
  `scripts/sync-core.sh`) — a local `pre-commit` hook that refuses commits touching the
  vendored `core/` subtree, turning the prose rule "never hand-edit `core/`" into a
  mechanical block. Motivated by a real incident: an upstream "Lazy lock update" edited a
  vendored `core/nvim/lazy-lock.json` directly, drifting it from canonical Core. `sync-core.sh`
  now (re)installs the hook into every repo it fans out to (so the protection lands on the
  maintainer's machine, where the edit happens) and exempts its own legitimate subtree
  writes via `DOTFILES_ALLOW_CORE_EDIT=1`; a one-off bypass is the standard
  `git commit --no-verify`. Idempotent and non-destructive — it never clobbers a
  pre-existing unrelated `pre-commit` hook. Covered by hermetic git tests in
  `scripts/test-core.sh`. (Wiring it into each OS `bootstrap.sh` for fresh clones rides
  along with the pending `bootstrap-lib.sh` adoption.)
- **Fleet-drift check** (`scripts/fleet-drift.sh`, `make fleet-drift`, and a weekly
  `.github/workflows/fleet-drift.yml`) — reads every OS repo's `core.lock`
  (`core_sha=…`) plus `dotfiles-Windows`'s `nvim/.core-ref` (`commit = …`) and reports
  which repos lag Core's tip (BEHIND/AHEAD/DIVERGED, quantified in commits). Closes the
  gap where the per-repo provenance markers existed but nothing compared them, so a repo
  could silently sit on a stale Core (how the nvim lockfile drifted). Read-only — the
  fix is a human running `make sync`; a not-checked-out repo is skipped unless `--strict`.
  The reference commit is `--ref`/`$CORE_REF_SHA` → `origin/main` → `main` → `HEAD`.
  Fleet list is the same `scripts/os-repos.txt` `sync-core.sh` reads; the scheduled
  workflow anonymously shallow-clones the public repos and fails red on drift.
- **`.github/workflows/bootstrap-test.yml`** — a _reusable_ (`workflow_call`)
  bootstrap integration test, authored once here and called by a thin ~10-line
  stub in each OS repo, so the OS repos gain CI without each carrying a duplicated
  copy of the logic (the same fan-out the Core layer exists to kill). Two jobs:
  `lint` runs `shellcheck -x` + `bash -n` + `--help` on `bootstrap.sh` (the OS
  repos previously had no CI at all, so this is their first gate); `links-only`
  runs `bootstrap.sh --links-only` inside the target distro's container and
  asserts the symlink graph + the generated `~/.zshrc` (it pre-seeds the tpm dir
  to skip the network clone, mirroring `test-core.sh`'s offline technique, and
  leaves the actual module load — already covered hermetically by `test-core.sh` —
  alone). Callers pass `image`/`prep`/`offensive`; Kali sets `offensive: true`.
- **`lib/bootstrap-lib.sh`** — a vendored BASH provisioning scaffold that ends the
  per-repo bootstrap fan-out. Roughly half of each OS bootstrap.sh was the _same_
  code — `link()`, `read_pkgs()`, WSL detection, the Core-symlink loop, the `.zshrc`
  loader heredoc, the default-login-shell logic — copy-pasted and then independently
  reformatted, so a fix had to be made in every repo by hand (the exact N-way drift
  Core exists to kill, leaking through the one file that can't be vendored). The
  shared half now lives here as `blib_*` helpers (`blib_link`, `blib_read_pkgs`,
  `blib_is_wsl`, `blib_link_core`, `blib_link_os_layer`, `blib_write_zshrc_loader`,
  `blib_set_login_shell`), sourced by each bootstrap.sh alongside `lib/ux.sh`. The
  loader writer takes the module list as an argument, so a role repo (Kali) injects
  its `offensive` stage; the login-shell helper takes `$BLIB_SU` so a doas-only or
  root box works. The `core/`-presence check stays inline per bootstrap (you cannot
  source a lib out of `core/` before confirming `core/` exists). Listed in
  `core.manifest`; sourced (non-exec) like `lib/ux.sh`. Adopting it in each OS
  bootstrap.sh is a follow-up that lands after this is synced out.
- **`pullall [dir]` shell function** (`zsh/functions.zsh`) — fast-update every git
  repo under a parent directory in parallel: prunes deleted remote branches,
  stashes uncommitted tracked changes, switches to each repo's auto-detected trunk
  (main/master/trunk/… via `origin/HEAD`, not a hard-coded `main`), fast-forwards
  it, pops the stash back (reporting a pop conflict instead of swallowing it), then
  prints a summary card. The parent directory is configurable (argument →
  `$PULLALL_DIR` → CWD) so Core stays machine-agnostic; parallelism via
  `xargs -P` (`$PULLALL_JOBS`, default 10). Colour is TTY/`NO_COLOR`-aware and
  repo paths are passed positionally (no shell injection from odd names). Ships
  with a `_pullall` completion, a `core-help` row, and behavioural tests.
- **`dotfiles-Defense-PLAN.md`** — a forward-looking architecture note plus a
  complete, ready-to-instantiate skeleton for a future `dotfiles-Defense` repo
  (the defensive/blue Role layer that mirrors `dotfiles-Kali`). Records the
  red/blue split decision, the trigger for standing the repo up, the layer-table
  identity, and every scaffold file verbatim (README, CLAUDE.md, bootstrap,
  `defense.zsh`, methodology, gitignore, compose stub, templates) so the repo can
  be `git init`-ed when the trigger is met. Added to the audit's repo-meta
  allowlist; it is planning, not shipped Core.
- **Claude Code project memory + maintenance routines** (`CLAUDE.md`, `.claude/`) —
  a root `CLAUDE.md` encoding the three-layer model, the "is it Core?" test, the
  manifest contract, and the load order so every Claude session reasons from the
  real rules. Three on-demand slash commands automate the judgment-heavy chores the
  audit can't: `/doc-audit` (prose-vs-reality drift across the fleet, via the
  `doc-consistency` subagent), `/tool-scout` (research the modern-CLI stack for
  tools worth adopting, via the `tool-scout` subagent), and `/freshness-triage`
  (review dependency-bump PRs against upstream changelogs). All report-first; none
  vendor out without a green `make audit`. `CLAUDE.md` added to the audit's
  repo-meta allowlist (`.claude/` was already a prefix).
- **Scheduled maintenance bots** (`.github/workflows/claude-routines.yml`) — run the
  `/doc-audit` and `/tool-scout` routines headless on a weekly cron (and on demand),
  filing findings as a deduplicated GitHub issue. The Claude Code CLI is installed
  from npm (pinned via `CLAUDE_CODE_VERSION` in `scripts/tool-versions.env`) — no
  third-party action, mirroring `freshness.yml`. Auth is a Claude subscription token
  (`CLAUDE_CODE_OAUTH_TOKEN`, from `claude setup-token`); inert until that secret is
  set (the workflow no-ops with a warning otherwise).
- **`make release-notes` + `cliff.toml`** — git-cliff config + a Makefile target that
  drafts a GitHub Release body from Conventional Commits since the last release commit.
  Scoped dev-tooling (audit allowlist, not `core.manifest`, zero runtime cost); it does
  **not** generate `CHANGELOG.md` (that stays hand-curated and is promoted by
  `scripts/release.sh`). Surfaced by `/tool-scout` (issue #44).
- **`aliases.md`** is now surfaced in the changelog — the cross-fleet aliases cheat
  sheet (Core + per-OS + offensive layers), previously shipped without an entry.

### Fixed

- **`blib_set_login_shell` no longer trusts a non-executable `command -v zsh`.**
  `command -v` also resolves aliases/functions, so a shadowed `zsh` could yield an
  alias body rather than a path; it's now required to resolve to a real executable
  (`[[ -x ]]`) before being handed to `chsh`/`usermod`. The `/etc/passwd` fallback
  (used when `getent` is absent, e.g. busybox/Alpine) switched from a `grep "^$user:"`
  regex to `awk -F: -v u="$user"`, so a username containing a regex metacharacter
  can't mis-match. Robustness only; no behavior change for normal setups.
- **Startup nudges no longer execute under a substitution prompt** (`zsh/update.zsh`).
  `_pkgup_notice` ("N updates available — run \`up\` to apply") and `_core_welcome`
  ("dotfiles Core loaded — run \`core\`…") rendered their hints with `print -P` and wrapped
  the verb in **backticks**. Under `setopt prompt_subst` — which starship and any
  substitution prompt enable — `print -P` performs command substitution, so the backtick'd
  word was _executed_ rather than printed: the update nudge fires from a precmd hook before
  `up()` is defined, surfacing as `command not found: up` on every package-manager box (and,
  once defined, silently triggering a privileged upgrade). Both hints now use single quotes
  (`'up'` / `'core'`), which are literal under prompt expansion; the `NO_COLOR` branch already
  used the safe `print -r`. Surfaced by a `make sync` audit failing on a starship MacBook. A
  new `test-core.sh` regression seeds a cached count under `prompt_subst` with an `up()`
  sentinel and asserts the nudge mentions `up` but never runs it.
- **`dotfiles-Defense-PLAN.md` scaffold: `bootstrap.sh` `--links-only` was dead.** The
  reproduced `bootstrap.sh` set `LINKS_ONLY` but never read it, so `--links-only` still ran
  the host-tool/docker probe (and shellcheck flagged the unused var). Guard the probe with
  `(( DO_CHECK && ! LINKS_ONLY ))` so `--links-only` truly just wires symlinks, and rewrite
  the `(( missing == 0 )) && ok || warn` line as if/then/else. The scaffold is now
  shellcheck-clean and was exercised end-to-end in a sandbox (`--links-only` wires Core +
  the defense stage); the "validated" note now says so. Planning doc only (allowlisted
  repo-meta) — nothing shipped/vendored.
- **`gsync` runner + core-guard installer hardening** (review follow-up to the
  fan-out PRs). `.bin/sync-upstream.sh`: normalize to the git toplevel first so
  `gsync` works from any subdirectory (it is an absolute-path runner); use
  `git status --porcelain` for the clean-tree check so untracked files also block
  (`git diff-index HEAD` missed them); and reword the failure hint to be
  auth-agnostic (the remote is HTTPS, not SSH) and point at the right re-pull
  command for an OS repo. `zsh/aliases.zsh`: `gsync` is now a wrapper function,
  not an alias, so a dotfiles path containing whitespace stays one word and args
  pass through — with a matching `_gsync` completion and `core-help` row.
  `lib/bootstrap-lib.sh` `blib_install_core_guard`: detect the git work tree and
  hooks dir via `git rev-parse` (so worktrees/submodules, where `.git` is a file,
  get the guard too), skip with a warning when `core.hooksPath` is set (installing
  into the ignored `.git/hooks` was false protection), and return non-zero instead
  of silently succeeding if the hooks dir can't be created. New hermetic test
  covers the `core.hooksPath` skip.
- **`sync-core.sh` pre-fan-out audit no longer false-fails on the core-guard test.**
  The script `export`s `DOTFILES_ALLOW_CORE_EDIT=1` for its own legitimate subtree
  commits, but that exemption was still in the environment when it ran the
  pre-fan-out `audit-core.sh` — whose behavioral suite commits to a throwaway
  `core/` and asserts the guard hook BLOCKS it. The inherited exemption made that
  assertion fail, reding an otherwise-green tree and forcing `SYNC_SKIP_AUDIT=1`.
  The audit now runs via `env -u DOTFILES_ALLOW_CORE_EDIT` (it never writes to
  `core/`, so it needs no exemption); the fan-out commits keep theirs.
- **`bootstrap-lib.sh` now wires three Core files it silently dropped.**
  `blib_link_core` linked starship/nvim/mise/git/tmux/clip but omitted
  `core/lazygit/config.yml` (→ `~/.config/lazygit/config.yml`), `core/vim/vimrc`
  (→ `~/.vimrc`), and the `core/sesh/sesh.toml.example` seed
  (→ `~/.config/sesh/sesh.toml`) — three files that are in `core.manifest` (the
  manifest comments even spell out their destinations) yet reached no machine,
  inherited from the per-repo bootstraps this library consolidated. lazygit + vim
  symlink like starship; sesh is seeded (copied, never relinked) like the git
  identity file. The matching `bootstrap-test.yml` assertions for these three were
  briefly **deferred** — that reusable test is referenced `@main` by every adopter, so
  it can only assert what each adopter's CURRENT vendored `core/` produces, and asserting
  the wiring before `make sync` propagated it would have red-flagged Fedora/Kali. They are
  **now re-added**: every adopter's `core.lock` is at a Core that includes the wiring, so
  the `@main` test asserts lazygit/`~/.vimrc`/seeded-sesh again without false reds.
- **`freshness.yml` opens its pin-bump PRs against the default branch**, not the
  dispatched ref (`GITHUB_REF_NAME`), and uses a ref-independent concurrency group —
  so a manual run from a feature branch can't target the wrong base or race the cron.
- **`aliases.md`** — corrected the `myip` expansion (it redirects stderr:
  `curl -fsS https://ifconfig.me 2>/dev/null && echo`) and repo-qualified the
  cross-repo source paths in the header so they don't read as broken local links.
- **`doc-consistency` subagent** — aligned its system description with the canonical
  nine-repo, three-layer (Core → OS-native → Role) wording.
- **`audit-core.sh`** — clarified the META-allowlist comments: those files are "not
  shipped Core" (absent from `core.manifest`), not "never vendored" (the subtree copy
  carries them physically).
- **Doc drift caught by `/doc-audit`** — corrected "vendored into/fans out to _nine_
  OS repos" → _eight_ (Windows vendors no `core/`) in `CHANGELOG.md` + `CONTRIBUTING.md`;
  added the manifest-listed `zsh/loader.zsh` and `lazygit/config.yml` to the README
  Layout tree; completed the README tmux-scripts list (added `tmux-battery`/`tmux-cheat`);
  and attributed the `cheat` alias to `functions.zsh` (not `aliases.zsh`) in `aliases.md`.

### Security

- **CI tool downloads are now SHA-256 verified.** The `setup-core-tools` composite
  action previously fetched its pinned gate binaries (shellcheck, actionlint, gitleaks,
  neovim) with `curl … | tar` and **no integrity check** — a tampered or MITM'd release
  asset would have executed inside the gate. Each install now downloads to a file,
  verifies it against a pinned hash from `scripts/tool-versions.env`, and only then
  installs; a mismatch fails the build. `shfmt` was folded into the action (it was the
  last tool still installed via inline `curl` in the OS-repo lint workflows), so one
  verified definition now covers every downloaded gate tool.
- **`scripts/tool-versions.env`** gained a `*_SHA256` per downloaded tool (the single
  source the action reads alongside each `*_VERSION`), plus `SHFMT_VERSION`.
- **`scripts/audit-core.sh`** gained a "tool download integrity" section that fails the
  audit if any pinned `*_VERSION` lacks a 64-hex `*_SHA256` — a version can no longer be
  bumped without refreshing its checksum.
- **`scripts/update-tool-checksums.sh`** (new) recomputes the pinned hashes from the
  exact assets the action downloads, so a version bump is a one-command checksum refresh.
- **`setup-core-tools` skips only on its OWN verified binary, not any `command -v` match.**
  The install steps short-circuited on `command -v <tool>`, which also matches a binary
  preinstalled on the runner (`ubuntu-latest` ships shellcheck) — so the verified install
  was silently skipped and the gate ran the unpinned, unverified system shellcheck. Each
  step now skips only when the binary is already in the action's own `bindir` (a genuine
  cache restore); the caller prepends `bindir` to `PATH`, so the verified binary always
  shadows any preinstalled one. Restores the integrity + pinning guarantee for shellcheck.

## [v1.2.0] - 2026-06-21

### Added

- **fzf-assisted git staging** (`zsh/git.zsh`) — `gaf` / `grf` / `grsf`, fuzzy
  multi-select counterparts to `git add` / `restore` / `restore --staged`. Each
  guards on `fzf` like the `fzf.zsh` zle widgets, depends only on git + fzf (both
  in the Core stack), and NUL-pipes paths so filenames with spaces survive `xargs`.
- **`vim/vimrc`** — a plugin-free, self-contained vim fallback for boxes where only
  stock vim exists (minimal containers, rescue shells, freshly-SSH'd servers). netrw
  as the file browser, no network, keybindings echoing the Neovim config. The OS
  bootstrap symlinks it to `~/.vimrc`.

### Changed

- **Adaptive eslint linting** (`nvim/lua/gerrrt/plugins/nvim-lint.lua`) — the eslint
  family (js/ts/jsx/tsx/svelte/vue) now lints only when an eslint config is found
  upward from the buffer, mirroring the existing SC1071/ruff guards. Prevents
  `eslint_d`'s hard error from surfacing as a phantom diagnostic in projects with no
  eslint config. Non-eslint linters still run unconditionally.

## [v1.1.0] - 2026-06-19

## [v1.0.0] - 2026-06-18

### Added

- **lazygit theme** (`lazygit/config.yml`) — a tokyonight-storm theme matching
  `starship.toml`, the tmux bar, and `zsh/fzf.zsh`, so lazygit (reached via the `lg`
  alias and the `prefix + g` tmux popup) reads as one palette with the rest of the
  stack. Bootstrap symlinks it to `~/.config/lazygit/config.yml`.
- **`genpw [length]`** — portable random-password generator (`zsh/functions.zsh`):
  prefers `openssl`, falls back to `/dev/urandom` so it works on a bare rescue shell.
  Ships with its completion (`zsh/completions/_genpw`) and a `core-help` entry.
- **fzf tokyonight palette** — `FZF_DEFAULT_OPTS` (`zsh/fzf.zsh`) now sets an explicit
  tokyonight-storm `--color` set instead of inheriting the terminal palette, keeping
  fzf on-theme even over SSH into an unthemed box.
- Audit **`--strict`** now fails only on gates skipped because their TOOL is absent (an
  out-of-scope skip stays intentional), so CI runs it on the Linux leg — closing the last
  "green because a linter silently failed to install" gap. CI also installs `python3-yaml`
  so the YAML-parse gate is honest under `--strict`.
- **Core⇄OS boundary** audit gate: portable `zsh/*.zsh` modules may carry no OS-absolute
  paths (`/opt/homebrew`, `~/Library`, …), mechanically enforcing the README's "if it
  changes with the OS it isn't Core" rule. `zsh/maint.zsh` (the OS-switched scheduler
  surface) is the documented exception.
- **`core.version` ↔ `CHANGELOG`** coherence gate: a prerelease stamp must keep an
  `[Unreleased]` section open; a release stamp must have a matching `## [vX.Y.Z]` heading.
- Behavioral coverage for `git.zsh` (`git_main_branch`/`git_current_branch` trunk +
  detached-HEAD resolution) and for `_pkgup_count`/`_pkgup_list` parsing on
  apk/dnf/zypper/pacman — previously only apt was exercised.
- `core-help` now lists the most-used **git aliases** (the OMZ-style set in `git.zsh`),
  so they are discoverable from the cheat sheet.
- `core.version` — a human-readable SemVer stamp vendored into every OS repo, plus a
  `core-version` verb that reads it, so you can tell WHICH Core a given OS repo carries
  from inside it (the subtree squash records the commit; this records the version).
  `scripts/sync-core.sh` prints it on fan-out and the audit asserts it is well-formed.
- `core-doctor` — the shell counterpart to nvim's `:checkhealth gerrrt`: a scannable
  report of which modern-CLI tools Core detected on this box and which integrations are
  live, including the RESOLVED binary names (`fd`/`fdfind`, `bat`/`batcat`) and the
  detected package manager. Read-only.
- `up -n`/`--dry-run` — list the packages that WOULD upgrade and exit, touching nothing
  (the non-destructive inspect the count-only nudge didn't offer).
- `make audit-changed` (`audit-core.sh --changed`) — scope the audit to what your local
  git diff touches, via the SAME `scripts/ci-classify.sh` CI uses; fails safe to the
  full run when the diff can't be resolved.
- First-party completions for `fif`, `fbr`, `core-version`, and `core-doctor`, and a
  `core.version`/`up --dry-run`-aware `_up`; the completion-parity test now covers them.
- `.shellcheckrc` — repo-wide ShellCheck config (`external-sources`, `source-path`,
  `shell=bash`) so author-time, CI, and editor lint identically.
- `zsh/ui.zsh` — shared terminal-UX primitives (`_core_err`/`_core_warn`/`_core_ok`/
  `_core_hint`/`_core_usage`/`_core_confirm`/`_core_spin`), gum-aware with a plain
  fallback on every helper. Loads right after `tools` in the canonical chain and is
  adopted across `functions.zsh`, `op.zsh`, `update.zsh`, and `plugins.zsh`, replacing
  ad-hoc `echo "Usage: …"` lines with one consistent voice (colour only on a TTY,
  `NO_COLOR` honoured, diagnostics to stderr).
- `core-help` (alias `cheat`): a grouped, column-aligned cheat sheet of Core's
  functions, keybindings, and maintenance verbs — the shell counterpart to which-key.
  Plus a once-per-machine first-run hint pointing at it (`CORE_WELCOME=0` to silence).
- First-party zsh completions (`zsh/completions/`) for Core's own verbs — `up`,
  `extract` (archive files only), `mkcd`, `mkbak`, `maint-log`, `openv` — fpath-added
  by `options.zsh` (symlink-safe; no bootstrap symlink needed). The audit now `zsh -n`s
  them alongside `zsh/*.zsh`.
- `scripts/lib/common.sh` — one definition of the colour palette + `pass`/`skip`/`fail`/
  `hdr`/`have` shared by all five gate scripts (the block had been copy-pasted ×5). A
  sourced lib, so — like `zsh/*.zsh` — it stays mode 100644; the audit's exec-bit
  section gained a `scripts/lib/*.sh` arm to assert exactly that.
- `scripts/tool-versions.env` — single source for the pinned dev-tool versions, read by
  CI (loaded into `$GITHUB_ENV`), `make setup`, and the audit. `scripts/setup.sh` +
  `make setup`: a one-command dev bootstrap (pre-commit hooks + version doctor + audit).
- `actionlint` gate on the workflows: an audit section (graceful skip when absent) plus
  a pinned CI install — the workflow YAML is now validated, not just parsed.
- Audit version-consistency section: the `.pre-commit-config.yaml` hook revs are gated
  to equal `scripts/tool-versions.env`, so a one-sided pin bump fails the audit.
- Hermetic behavioral tests for `bin/clip` / `bin/clip-paste` (the highest-fan-out
  runtime artifact — used by zsh, tmux, and nvim): a new section in
  `scripts/test-core.sh` drives the WSL→macOS→Wayland→X11 detection ladder against a
  fake `PATH`, asserting the right backend is chosen. Runs even where zsh is absent.
- Headless Neovim config-load smoke test in `scripts/test-core.sh`: loads the authored
  config layer and every plugin spec offline (no install), catching luacheck-clean Lua
  that is nonetheless a broken config. CI ships a pinned `nvim` (`NVIM_VERSION`) so it
  runs on both userlands instead of skipping.
- Alpine (musl/busybox) CI leg, run via a bind-mounted container, finally exercising
  the busybox-coreutils compatibility the scripts have always claimed.
- `scripts/update-plugins.sh` + `make update-plugins`: deliberately roll the pinned
  zsh-plugin SHAs to upstream HEAD — the runtime-plugin mirror of `make update-hooks`.
- Markdown lint gate: `.markdownlint.jsonc` rule config, a `markdownlint` section in
  `scripts/audit-core.sh` (graceful skip when absent), a `markdownlint-cli2` pre-commit
  hook, and a pinned CI install step — so the docs (the deliverable on a public
  showcase repo) are gated like everything else.
- `scripts/bench-core.sh` gained an optional `CORE_BENCH_BUDGET_MS` budget gate (fails
  when the canonical-chain startup mean exceeds the budget), plus a non-blocking CI
  `bench` job that reports the number on every push.
- `SECURITY.md` and `.github/ISSUE_TEMPLATE/` (bug + feature + config) round out the
  GitHub community profile; `CONTRIBUTING.md` documents a Conventional Commits
  convention.
- Broader behavioral coverage in `scripts/test-core.sh`: `mkbak` byte-identity,
  `extract` unknown-format rejection, and `extract` round-trips for `.tar.gz`/`.gz`
  (the latter skip gracefully when `tar`/`gzip` are absent).
- CI runs the audit on a `[ubuntu-latest, macos-latest]` matrix, gating the macOS
  (bash 3.2 / BSD userland) target — `dotfiles-MacBook` — alongside Linux.
- `scripts/audit-core.sh` and the pre-commit config parse-check every tracked TOML and
  YAML file, catching malformed `starship.toml` / `mise/config.toml` / workflow
  YAML that is valid text but dead at runtime for every consumer.
- This `CHANGELOG.md`.
- `scripts/sync-core.sh` reports the exact dotfiles-core revision (short SHA) each OS
  repo receives, so a sync is traceable.
- `scripts/bench-core.sh` + `make bench`: a hermetic hyperfine benchmark of the
  canonical Core load chain, so startup-perf regressions (the thing tools.zsh's
  caching and plugins.zsh's deferral exist to prevent) are measurable, not silent.
- A `command_not_found_handler` (zsh): a mistyped command now gets a Core-voice miss
  that suggests the nearest Core verb on a near typo (`extarct` → `extract`, via a
  small built-in Levenshtein) or, failing that, an install line for this box's detected
  package manager — instead of zsh's terse default. Interactive-only; `CORE_CNF_ENABLED=0`
  opts out.
- `make doctor` (`scripts/setup.sh --doctor`): the read-only half of `make setup` —
  reports each dev tool against its pin with no install and no audit, for quick "is my
  toolchain aligned with CI?" triage.
- `core-help <word>` filters the cheat sheet to matching rows (and reports a no-match
  cleanly), so jumping to one verb beats scanning the whole sheet.
- `serve` renders the reachable URL as a terminal QR code when `qrencode` is present
  (scan-to-open from a phone) — graceful skip when it isn't.
- `scripts/audit-core.sh --strict`: treat any SKIP as a failure (a gate whose tool was
  absent did not actually run), for release/CI verification where every gate must execute.
- `ui.zsh` primitives: `_core_errbox` (multi-line what/why/fix error blocks),
  `_core_suggest`/`_core_lev` (did-you-mean), reused across the runtime helpers.

### Changed

- The `command_not_found_handler` now also weighs this shell's **aliases** when proposing
  a "did you mean?", so a near miss like `gts`→`gst` is caught, not just the Core verbs.
- The markdown gate resolves `markdownlint-cli2` via PATH → `npx --no-install` →
  `node_modules`, so an off-PATH global install runs instead of skipping (the most-skipped
  gate in remote sessions).
- `_cache_eval` gained `--salt`; the `atuin`/`carapace` inits fold `ATUIN_NOBIND`/
  `CARAPACE_BRIDGES` into the cache filename, so flipping that env busts the cache
  instead of serving a stale init.
- Higher-friction failures now use the structured `_core_errbox` (headline + why/fix):
  `up` with no package manager, and `serve` without `python3`.
- `scripts/setup.sh` provisions `luacheck` via `luarocks` (no clean mise source) and
  emits precise, actionable install hints — closing the last manual onboarding gap.
- Defensive confirms on impactful interactive actions: `please` now previews the exact
  `sudo …` line and confirms before eval'ing it as root (and refuses with no previous
  command); `up` pre-confirms `Apply updates with <mgr>?` before touching the system
  (skipped by `-y`); `serve` warns plainly that it binds `0.0.0.0` and exposes the CWD.
- First-run plugin install shows a spinner on the network-bound `git fetch`/`clone`
  (gum spin when present, a hand-rolled braille spinner otherwise), guarded so an OS
  loader that hasn't adopted `ui.zsh` yet still installs plainly.
- CI is now incremental: a `changes` job classifies the diff and gates the narrow,
  expensive legs — `nvim`+`luacheck` installs run only when `nvim/` changed, and the
  Alpine and bench jobs only when the shell layer changed. SAFE DEFAULT: an unresolved
  diff base or any infra change runs everything, so detection can never hide a check.
- The startup-perf `bench` CI job is now an enforced regression gate
  (`CORE_BENCH_BUDGET_MS=120` over 50 warmed runs), not a report-only, continue-on-error
  step — a gross startup regression now fails the build instead of shipping silently.
- The pinned linter versions moved out of `ci.yml`'s `env:` block into
  `scripts/tool-versions.env`; CI loads them via a "Load pinned tool versions" step.
- Split `bin/` into shipped vs. tooling: `bin/` now holds only what is vendored into
  the OS repos (`clip`, `clip-paste`); the gate scripts moved to `scripts/`
  (`audit-core.sh`, `test-core.sh`, `bench-core.sh`, `sync-core.sh`,
  `update-plugins.sh`). The audit allowlists `scripts/` wholesale, so a new dev tool
  is covered the moment it lands. No consumer impact — those scripts were never in
  the manifest, so they were never vendored.
- `scripts/audit-core.sh` no longer uses the bash-4-only `mapfile`, so the gate itself
  runs on macOS's stock bash 3.2.
- The audit summary now NAMES the checks that skipped (tool absent) and labels such a
  run PARTIAL rather than hiding the gap behind a bare count — several skipped gates
  (markdownlint, actionlint, gitleaks, luacheck, nvim) are CI-enforced, so a clean local
  box can still differ from the gate.
- `core-doctor` now turns its `✗` tools into a copy-pasteable install line for this box's
  package manager, instead of leaving the reader to look each one up.
- Spinner (`_core_spin`) shows elapsed time and ends with a still `✓`/`✗` result frame, so
  a long step reads as progress and finishes with a legible outcome; `extract` routes the
  quiet unpack formats through it. Unknown-format `extract` errors print a what/why/fix block.
- `serve`/`up` suggest the nearest valid flag on an unknown option (did-you-mean).
- De-duplicated the gate scripts: the `_set_scope` area parser, the hermetic plugin-seed
  list, and the `ci-classify.sh` output reader now live once in `scripts/lib/common.sh`
  (consumed by `audit-core.sh`, `test-core.sh`, `bench-core.sh`) — they had drift-prone
  copies. `op.zsh` verbs gained the `emulate -L zsh` every other Core verb uses.

### Security

- Pinned the seven runtime zsh plugins to commit SHAs (`ZPLUGIN_PINS` in
  `zsh/plugins.zsh`) — the last unpinned link in a toolchain that already pins CI
  linters, pre-commit hooks, and GitHub Actions. An unpinned `master` clone fanned an
  upstream breaking change — or a compromised tag — out to all eight machines on the
  next install; installs now fetch exactly the pinned commit.

### Fixed

- `fbr`'s fzf preview used `{1}`, which on the current-branch row (`* main`) is the
  literal `*` — so the preview ran `git log *` and broke. It now lists clean branch
  names (`--format='%(refname:short)'`, `*/HEAD` dropped) and previews `{}`; a remote-only
  pick strips `origin/` on checkout to create the matching local tracking branch.
- `mkbak` could prompt or clobber: `cp -i` (from `aliases.zsh`, parsed first) bled into
  it, so a same-second second backup stopped for a y/n. It now picks the next free `.bak`
  suffix and copies via `command cp`, staying collision-safe and non-interactive.
- `_core_confirm`'s gum path defaulted to **Yes** while the `[y/N]` fallback defaulted to
  No — so the same destructive prompt (`please`/`up`/extract-overwrite) was one-Enter-to
  confirm under gum. It now passes `gum confirm --default=false`, a consistent safe default.
- The `_core-help` completion claimed "takes no arguments", but `core-help` accepts a
  `[filter]`; it now completes that filter with the verbs/sections the cheat sheet knows.
- `serve` now pre-checks the port is bindable (with `SO_REUSEADDR`, as `http.server`
  does) and fails in Core's voice instead of letting a taken port surface a Python traceback.
- `diff` was unconditionally aliased to `diff --color=auto`, which BSD/macOS `diff` (the
  dotfiles-MacBook target) does not support — every `diff` invocation would error there.
  The alias is now applied only after a feature-probe confirms this box's `diff` accepts it.
- fzf / fzf-tab previews hardcoded `bat`/`eza`, so every preview pane printed
  "command not found" on Debian/Ubuntu (bat ships as `batcat`) and on any box without
  eza. Previews now resolve `$BAT_BIN` with a `cat`/`ls` fallback, and a new audit
  section (`fzf preview binary resolution`) locks it so the regression can't recur.
- `fif`, `fbr`, and the Alt-Z zoxide-jump widget assumed `fzf`/`rg`/`git`/`zoxide`
  were present; they now degrade in Core's voice (`_core_err`/`_core_hint`) like `fcd`,
  instead of a raw "command not found".
- Removed leaked `</content>`/`</invoke>` template artifacts from the end of this
  changelog — the exact bug class the new markdown gate now catches.
- Restored non-executable mode (`100644`) on the twelve `zsh/*.zsh` modules. They
  are sourced, not executed, and had regressed to `100755`, failing the audit's
  exec-bit invariant — the exact bug class the audit exists to catch, fanning out
  to all eight OS repos.
- Registered `CODEOWNERS`, `dependabot.yml`, and `pull_request_template.md` in the
  audit's `META_ALLOWLIST` so the manifest reverse-drift scan accounts for them.
