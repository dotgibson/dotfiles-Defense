<!-- Core fans out to all 8 OS repos via git subtree — a defect here is an N-way
     defect. Keep changes truly Core, and green before merge. -->

## What & why

<!-- One or two lines. What changed in the Core layer, and why. -->

## Is it actually Core?

- [ ] Identical on every machine — **not** OS-specific (pkg manager, paths, clipboard → the OS repo)
- [ ] **Not** offensive/engagement tooling (→ `dotfiles-Kali`)

## Contract & checks

- [ ] If a Core file was added/removed, `core.manifest` was updated in the same change
- [ ] `make audit` is green locally (manifest ↔ fs, exec-bits, syntax, lint, behavioral)
- [ ] Exec-bits correct: scripts `+x`, `zsh/*.zsh` modules **not** executable
- [ ] If a new file needs a symlink, each OS repo's `bootstrap.sh` was noted/updated

## Notes

<!-- Anything reviewers should know: load-order implications, follow-up sync, etc. -->
