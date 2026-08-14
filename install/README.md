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

| state                     | meaning                                                  |
| ------------------------- | -------------------------------------------------------- |
| `found: <tool>`           | on `$PATH` under its own name                             |
| `found: <tool> (as <alt>)`| on `$PATH` under a known alternate name — e.g. `vol` found as `vol.py` |
| `unreachable: …`          | installed, but somewhere `$PATH` never looks — prints the path and the `ln -s` that fixes it |
| `missing: <tool>`         | genuinely absent — install it via your OS layer            |

Both `found` states are clean; the other two are each counted and summarised on
their own line at the end (`N tool(s) missing` / `N tool(s) installed but off
$PATH`), and either one suppresses the `all probed tools present` line. The
probe stays report-only regardless — it never exits non-zero. The middle state exists
because several of these tools habitually install off `$PATH` — `zeek` under
its own prefix (`/opt/zeek/bin`), `volatility3` out of a checkout's venv — and
`defense/defense.zsh` calls them by bare name, so an unreachable tool is just
as unusable to this layer as an absent one. Reporting it as "missing" would
send you to reinstall something you already have; reporting it as "found"
would claim a tool this layer cannot actually call.
