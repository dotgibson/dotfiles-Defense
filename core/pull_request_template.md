<!-- Core fans out to all 9 OS repos — a defect here is an N-way
     defect. Keep changes truly Core, and green before merge. -->

## What & why

<!-- One or two lines. What changed in the Core layer, and why. -->

## Linked issue

<!-- A `fix(…)` PR must close an issue or say why it doesn't — pr-link-check enforces
     this. Use a CLOSING KEYWORD below (closes/fixes/resolves); "Refs #420" reads like
     a link but closes nothing, so the issue would stay open after merge.

       Closes #420

     No issue behind it? Replace the line above with a reason, e.g.

       No-Issue: found and fixed in one pass, never filed

     Editing this body re-runs the check. -->

## Is it actually Core?

- [ ] Identical on every machine — **not** OS-specific (pkg manager, paths, clipboard → the OS repo)
- [ ] **Not** offensive/engagement tooling (→ `dotfiles-Offense`)

## Contract & checks

- [ ] If a Core file was added/removed, `core.manifest` was updated in the same change
- [ ] `make audit` is green locally (manifest ↔ fs, exec-bits, syntax, lint, behavioral)
- [ ] Exec-bits correct: scripts `+x`, `zsh/*.zsh` modules **not** executable
- [ ] If a new file needs a symlink, each OS repo's `bootstrap.sh` was noted/updated

## Notes

<!-- Anything reviewers should know: load-order implications, follow-up sync, etc. -->
