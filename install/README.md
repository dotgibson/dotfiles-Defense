# install/ — host tools (distro-agnostic)

No `packages.txt` here — the OS-native layer you run owns package installation,
and the heavy stack runs in `docker/`. This is the host-tool shopping list so
`bootstrap.sh` can report what's missing without assuming a package manager.

Tools probed: `docker` + compose, `jq`, `tshark`/`tcpdump`, `zeek`, `suricata`,
`chainsaw`, `hayabusa`, `sigma-cli`, `yara`, `velociraptor`, `volatility3`,
`plaso` (`log2timeline`). `bootstrap.sh` probes for these — it never installs
them. If you later pin this repo to one base OS, this file becomes that
distro's real `packages.txt`.

The probe reports **three** states, not two, because "not on `$PATH`" and "not
on the box" are different problems with different fixes:

| state              | meaning                                                        |
| ------------------ | -------------------------------------------------------------- |
| `found: <tool>`    | on `$PATH` (or under a known alternate name, e.g. `vol.py`)      |
| `unreachable: …`   | installed, but somewhere `$PATH` never looks — prints the path and the `ln -s` that fixes it |
| `missing: <tool>`  | genuinely absent — install it via your OS layer                  |

Only `missing` counts toward the failure summary. The middle state exists
because several of these tools habitually install off `$PATH` — `zeek` under
its own prefix (`/opt/zeek/bin`), `volatility3` out of a checkout's venv — and
`defense/defense.zsh` calls them by bare name, so an unreachable tool is just
as unusable to this layer as an absent one. Reporting it as "missing" would
send you to reinstall something you already have; reporting it as "found"
would claim a tool this layer cannot actually call.
