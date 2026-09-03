# Contributing to dotfiles-Defense

This repo is the **defensive role layer**: detections (`detections/`), the analyst
workflow (`defense/`), the validation lab (`docker/`), and the packages that back them
(`install/`). It vendors **one** subtree, `core/`, from
[dotfiles-core](https://github.com/dotgibson/dotfiles-core).

Most review mistakes here are one of two kinds: *right change, wrong layer*, or a rule
edit that leaves a generated artifact behind. Both are covered below.

## 1. Which layer owns the change?

| It changes with… | It belongs in |
| --- | --- |
| nothing — identical on every box (zsh, tmux, nvim, git, starship) | **dotfiles-core**, upstream |
| the **OS** (packages, paths, an `ID=` gate) | the matching **OS repo** |
| the **analyst** (a detection, a hunt template, the lab) | **here** |
| the **attack** being detected | **[htpx](https://github.com/dotgibson/htpx)** |

If you are unsure, ask which file would have to change when you switch distro. If the
answer is "none", it is Core's.

## 2. Never hand-edit `core/`

`core/` is a vendored subtree, materialized by `dotfiles-core`'s own
`scripts/sync-core.sh`. Anything you change there is **overwritten on the next sync**,
and `core-integrity.yml` will report the tree as TAMPERED before that even happens.

Note the direction: Core is pushed *into* this repo by `make sync` **in dotfiles-core**.
There is no pull from this side, which is why there is no `make core-sync` here.
`make core-check` answers whether a sync is owed — is there a **newer** Core upstream?
`make core-verify` answers the different question the fleet vocabulary names: is **this**
`core/` the tree `core.lock` pins? It delegates to `dotfiles-core`'s own
`scripts/core-integrity.sh`, so it needs a checkout of that repo — a sibling clone by
default, or `make core-verify CORE_REPO=/path/to/dotfiles-core`.

## 3. Environment data never enters this repo

No real hostnames, internal IPs, user names, credentials, or telemetry captured from a
live estate — in rules, fixtures, tests, or issue reports. Validation fixtures are
synthetic or vendor-documented, and `docker/validation/check-fixture-provenance.sh`
gates that.

## 4. Running the gates

```bash
make lint
```

```bash
make test
```

Everything CI checks has a local target. `make help` lists them; the ones worth knowing:

| Target | What it answers |
| --- | --- |
| `make lint` | shellcheck (at CI's **pinned** version) + markdownlint |
| `make test` | the behavioural suite |
| `make drift` | are the generated artifacts in step with the rules? |
| `make methodology` | does `DEFENSE-METHODOLOGY.md` still describe the rules that exist? |
| `make validation-gates` | does every rule have validation coverage, every fixture provenance? |
| `make sigma` | the offline `sigma.yml` hard gates, together |
| `make attack-tags` | are the ATT&CK IDs real? (needs the network) |
| `make lab-smoke` | does the validation lab come up? (needs docker, slow) |

**`make shellcheck` is not a bare `shellcheck` call, on purpose.** It goes through
`tests/lint-shell.sh`, which reads the pinned version from
`core/scripts/tool-versions.env` and the flags from `core/.github/workflows/lint-call.yml`,
then refuses to run under a mismatched local shellcheck. A distro shellcheck and the
pinned one disagree about which checks exist, so "clean locally, red in CI" is the
default failure without it — that script's header records the afternoon it cost.

The sigma-dependent targets **skip with a reason** when the Sigma CLI is not installed
rather than failing. They are hard gates in CI, which installs the pinned tool.

The CLI answers to **two names**: the PyPI `sigma-cli` package installs its entrypoint as
`sigma` (what CI gets), while distro packages ship it as `sigma-cli`. The targets look for
both, so a distro install no longer reads as "not installed" and silently skips the SIEM
deploy-form gate. Set `SIGMA_BIN=/path/to/it` to override. Note the CLI can be present
*without* the backends it converts through — a separate pip install, and a separate error
that names what is missing.

## 5. Adding or changing a detection

1. Write the rule under `detections/sigma/`, with real ATT&CK tags.
2. **Regenerate, do not hand-edit, the artifacts.** `COVERAGE.md`,
   `coverage-layer.json` and the SIEM deploy forms are generated from the rule corpus
   and **byte-compared** in CI. Run `make drift` before pushing — a drift failure in CI
   reads as an unrelated red gate, several steps away from the rule you touched.
3. Give it validation coverage (`docker/validation/`), and provenance for any new
   fixture. A `filter_*` rule needs a true negative.
4. Keep `DEFENSE-METHODOLOGY.md` honest — `make methodology` checks that its claims and
   the README's gate list still match what exists.
5. If the technique has an attack side, it belongs in
   [htpx](https://github.com/dotgibson/htpx) as a paired entry, not here.

## 6. What `main` enforces

Every workflow under `.github/workflows/` runs on a PR. The `sigma.yml` gates are all
**hard** — there are no advisory steps to ignore. `make sigma` reproduces the offline
subset; `make attack-tags` covers the one that needs the network.

## 7. Commits

Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`), imperative mood, and a body
that explains *why* rather than restating the diff. A commit that fixes a detection
should say what it would have missed.
