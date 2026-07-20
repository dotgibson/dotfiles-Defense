# core/zsh/bindings.zsh
# Vi-mode keybindings. zsh-vi-mode resets all bindings on init, so we register
# them via its zvm_after_init hook. Load this BEFORE plugins.zsh (which sources
# zsh-vi-mode) so the hook is defined before vi-mode fires it. Most widgets it
# references are defined in fzf.zsh / by atuin / by synchronously-loaded plugins and
# are present by the time the hook executes. The exception is autosuggest-toggle
# (deferred) — see the Ctrl+\ note below for why it's bound unconditionally.

# Cursor shape per vi mode
ZVM_INSERT_MODE_CURSOR=$ZVM_CURSOR_BEAM
ZVM_NORMAL_MODE_CURSOR=$ZVM_CURSOR_BLOCK
ZVM_VISUAL_MODE_CURSOR=$ZVM_CURSOR_BLOCK

# Disable command mode line highlight
ZVM_VI_HIGHLIGHT_BACKGROUND=none
ZVM_VI_HIGHLIGHT_FOREGROUND=none
ZVM_VI_HIGHLIGHT_EXTRASTYLE=none

# zsh-vi-mode resets all bindings on init — register via hook to survive
zvm_after_init() {
  # --- Insert mode ---
  bindkey -M viins '^[[1;5C' forward-word   # Ctrl+Right
  bindkey -M viins '^[[1;5D' backward-word  # Ctrl+Left
  bindkey -M viins '^T' _fzf_file_no_hidden # Ctrl+T  → file picker (parity w/ pwsh PSFzf)
  bindkey -M viins '^R' _fzf_history_clean  # Ctrl+R  → history
  # Ctrl+E → Atuin TUI. GUARDED: atuin registers _atuin_search_widget only when
  # it's installed (tools.zsh runs `atuin init zsh` earlier in load order).
  (($+widgets[_atuin_search_widget])) && bindkey -M viins '^E' _atuin_search_widget
  # Ctrl+\ → toggle autosuggestions. NOT guarded, on purpose. zsh-autosuggestions is
  # DEFERRED (plugins.zsh) and is even queued AFTER zsh-vi-mode loads, so autosuggest-toggle
  # does NOT exist when this hook fires — a $+widgets guard here is always false and silently
  # disables the bind. (That was the bug: a formatter spaced the subscript into arithmetic in
  # `[autosuggest - toggle]`, but even un-spaced the guard never passed because of the deferral.)
  # bindkey records a binding to a not-yet-defined widget fine, and the widget materialises
  # right after the first prompt — long before you could press the key. If autosuggestions
  # isn't installed at all, Ctrl+\ is a harmless "no such widget".
  bindkey -M viins '^\' autosuggest-toggle
  bindkey -M viins '^[[A' history-substring-search-up
  bindkey -M viins '^[[B' history-substring-search-down
  bindkey -M viins '^[z' _fzf_zoxide_jump # Alt+Z   → zoxide jump
  bindkey -M viins '^G' _tmux_sessionizer # Ctrl+G  → sesh session picker

  # --- Normal / command mode ---
  bindkey -M vicmd '^[[1;5C' forward-word
  bindkey -M vicmd '^[[1;5D' backward-word
  bindkey -M vicmd '^[[A' history-substring-search-up
  bindkey -M vicmd '^[[B' history-substring-search-down
}
