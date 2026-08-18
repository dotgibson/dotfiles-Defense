# demo.tape — VHS script for the README hero GIF.
#
# Render:  brew install vhs   (one-time; pulls ttyd + ffmpeg)
#          vhs assets/demo.tape
# Output:  assets/demo.gif  — commit it alongside this tape.
#
# Requires a Nerd Font installed locally (the icons in eza/starship). Re-render
# after any prompt/tooling change so the hero stays current. Keep it short.

Output assets/demo.gif

Set Shell "zsh"
Set FontFamily "JetBrainsMono Nerd Font"   # must be a Nerd Font, or icons break
Set FontSize 20
Set Width 1200
Set Height 700
Set Padding 20
Set Theme "TokyoNight"                      # match the nvim theme
Set TypingSpeed 55ms

# --- silent setup: land on a clean prompt ---
Hide
Type "source ~/.config/zsh/.zshrc" Enter
Type "cd ~/code/dotfiles/dotfiles-MacBook" Enter
Type "clear" Enter
Show
Sleep 3s

# --- the tour: a few marquee moments, then stop ---
Type "ll"             Sleep 700ms  Enter  Sleep 2s      # eza — icons + git status
Type "cat README.md"  Sleep 700ms  Enter  Sleep 2s      # bat — syntax highlighting
Type "z dotfiles"     Sleep 700ms  Enter  Sleep 2000ms  # zoxide — frecency jump
Type "core help"      Sleep 700ms  Enter  Sleep 2000ms  # the built-in command index
Type "q"              Sleep 700ms  Enter  Sleep 2000ms  # quit the help menu
Type "cd -"           Sleep 700ms  Enter  Sleep 2000ms  # go back a directory
Type "glog"           Sleep 700ms  Enter  Sleep 2000ms  # pretty git log
Type "q"              Sleep 700ms  Enter  Sleep 2000ms  # quit the git log
Type "clear"          Sleep 700ms  Enter  Sleep 2000ms  # clear the screen
Sleep 1s
