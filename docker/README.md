# docker/ — the detection lab

The heavy blue stack runs in containers, not on the host — that's why this repo
is distro-agnostic. `siemup` / `siemdown` (in `defense/defense.zsh`) bring a
stack up/down; pick it with `DEFENSE_STACK` (default `detection-lab`).

The shipped `detection-lab.compose.yml` is a single-node **OpenSearch + OpenSearch
Dashboards** stack — the log store plus its query/visualization console. Add other
components (Zeek, Suricata, Wazuh, Velociraptor) as discrete compose stacks beside
it and select them with `DEFENSE_STACK`.

Why containers and not Security Onion: SO bundles Zeek + Suricata + Elastic +
Wazuh + Velociraptor behind an appliance — great as a turnkey sensor, wrong
shape for a version-controlled config repo. Here you run the same components as
discrete compose stacks, adding them as you need them.

## First run

```sh
cp docker/detection-lab.env.example docker/.env   # gitignored; set a STRONG password
sudo sysctl -w vm.max_map_count=262144            # OpenSearch needs this (see below)
siemup                                            # → http://127.0.0.1:5601  (admin / your pw)
siemlogs                                           # follow startup; siemdown to tear down
```

`docker/.env` is loaded automatically — `siemup`/`siemdown` pass `--env-file` when
it exists. The placeholder needed no secrets; the real stack requires the admin
password, so `siemup` will fail fast with a clear message if `docker/.env` is missing.

### The `vm.max_map_count` requirement

OpenSearch (like Elasticsearch) memory-maps its indices and refuses to start if the
host's `vm.max_map_count` is below `262144`. Set it once per boot with
`sudo sysctl -w vm.max_map_count=262144`, or persist it in `/etc/sysctl.d/`. Under
**WSL2** set it inside the distro (or via `/etc/wsl.conf`'s `[boot] systemd=true` +
a sysctl drop-in), not on the Windows host. This is a host kernel setting, so it
lives here in docs rather than in the compose file.

## Rules

- **No data volumes in git** — `docker/**/data/` and `.env` are gitignored; index
  data lives under `docker/detection-lab/data/` and never gets committed.
- **Pin image tags** — no bare `:latest`. Tags are pinned (`opensearch:2.19.0`) and
  Renovate's `docker:pinDigests` maintains the `@sha256:…` digest pin on top,
  grouped into the fleet's weekly `ci(deps):` PR.
- **Secrets in a local `.env`** — copied from `detection-lab.env.example`, never committed.
- **Localhost-only** — every published port binds `127.0.0.1`; the lab is never LAN-exposed.
- **Compose v2 required** — Dashboards is gated on OpenSearch being *healthy* via a
  long-form `depends_on: condition: service_healthy`, which only `docker compose` (v2)
  honors. Legacy `docker-compose` (v1, EOL) ignores it — `siemup` warns and still runs,
  but startup ordering isn't health-gated. Install Compose v2.
