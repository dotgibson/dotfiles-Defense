# Defense Aliases Cheat Sheet

Aliases sourced from two layers: `core/` (Core) and `defense/defense.zsh` (the
blue role layer). See `core/aliases.md` for the full Core alias reference
(modern CLI, git, safety nets). This repo is distro-agnostic — no OS layer of
its own; host tools come from whichever OS-native repo runs underneath.

---

## Defense Layer

Aliases and functions live in `defense/defense.zsh`. Every tool alias is
guarded by a `HAVE_*` detection flag and activates only when the tool is
installed. Case/evidence data never lives in the repo — it lives in
`$CASES_DIR` (defaults to `~/cases`).

### Tool Shortcuts

| Alias        | Expands To                                                                         | Requires                    |
| ------------ | ---------------------------------------------------------------------------------- | --------------------------- |
| `hunt-evtx`  | `chainsaw hunt --mapping /usr/share/chainsaw/mappings/sigma-event-logs-all.yml -s` | chainsaw                    |
| `sigma-lint` | `sigma check`                                                                      | sigma (sigma-cli / pySigma) |
| `pcap-conv`  | `tshark -q -z conv,tcp -r`                                                         | tshark                      |
| `velo`       | `velociraptor`                                                                     | velociraptor                |

### Detection Lab (Docker)

| Function          | Purpose                                                                                                                                 |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `siemup`          | Bring up the `$DEFENSE_STACK` compose stack (default `detection-lab`) detached, from `$DEFENSE_DIR/docker/${DEFENSE_STACK}.compose.yml` |
| `siemdown [args]` | Tear the stack down (`docker compose down`, or legacy `docker-compose` if the plugin isn't available)                                   |
| `siemlogs [args]` | Follow (`-f`) logs for the stack                                                                                                        |

### Case Scaffolding

| Function                        | Purpose                                                                                                                                                                                                                                                                                                                                                       |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `mkcase <incident-or-codename>` | Create a dated case workspace at `$CASES_DIR/<YYYYMMDD>-<slug>/{evidence,network,timeline,iocs,report,notes}`; renders `case.md` from `defense/templates/case.md` (or a minimal stub), copies `defense/templates/hunt.md` if present, sets `$CASE`, `cd`s in, and opens `case.md` in `${EDITOR:-nvim}` — fill in scope/authorization before touching evidence |
| `gocase`                        | fzf-jump between existing cases under `$CASES_DIR` (previews `case.md`); sets `$CASE` and `cd`s in                                                                                                                                                                                                                                                            |
| `note <text>`                   | Append a timestamped line to the active case's `notes/notes.md` (`$CASE/notes`, falls back to `$PWD/notes`); empty **or whitespace-only** text is a usage error, so the audit trail never gets a contentless entry                                                                                                                                            |
