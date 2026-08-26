#!/usr/bin/env python3
"""Emit the real-bootstrap matrix, DERIVED from each repo's own bootstrap-test.yml caller.

The per-PR gate runs bootstrap.sh with --links-only (and, opt-in, with the package managers
shimmed). Neither installs anything, so a wrong package name, a rotated repo key, or any
failure branch is invisible to both (dotgibson/dotfiles-core#589). The only thing that sees
those is a real bootstrap on a real image — which is what the weekly job this feeds runs.

The image and prep are READ FROM THE CALLER rather than listed here, deliberately. A frozen
copy would drift from what the per-PR gate actually uses, and this repo has been burned by
frozen counts before (#519 fixed eleven). If a repo bumps `image: fedora:latest` to something
else, the weekly run follows it with no edit here.

Usage: fleet-bootstrap-matrix.py <fleet-root>   → JSON array on stdout
"""
import json
import pathlib
import sys

import yaml

CALLER = "dotgibson/dotfiles-core/.github/workflows/bootstrap-test.yml@"

# Minutes, when a caller declares no `bootstrap_timeout:`. Matches what real-bootstrap.yml
# applied to every leg before the per-leg value existed, so a repo that declares nothing is
# unaffected. Emitted on EVERY leg rather than left absent: the workflow interpolates this
# straight into `timeout-minutes:`, and an empty value there is a workflow-level error.
DEFAULT_TIMEOUT = 45


def legs(repo_dir: pathlib.Path):
    """Every bootstrap-test.yml caller job in this repo, with its image + prep."""
    wf = repo_dir / ".github" / "workflows"
    if not wf.is_dir():
        return
    for f in sorted(wf.glob("*.yml")) + sorted(wf.glob("*.yaml")):
        try:
            doc = yaml.safe_load(f.read_text())
        except Exception:
            continue
        if not isinstance(doc, dict):
            continue
        for job, spec in (doc.get("jobs") or {}).items():
            if not isinstance(spec, dict):
                continue
            if CALLER not in str(spec.get("uses", "")):
                continue
            w = spec.get("with") or {}
            image, prep = w.get("image"), w.get("prep")
            if not image:
                continue
            # A repo declaring a non-numeric timeout gets the default rather than a crashed
            # matrix job — that would take the whole eight-leg sweep down over one typo.
            try:
                timeout = int(w.get("bootstrap_timeout", DEFAULT_TIMEOUT))
            except (TypeError, ValueError):
                print(
                    f"::warning::{repo_dir.name}/{job}: bootstrap_timeout is not a number "
                    f"({w.get('bootstrap_timeout')!r}) — falling back to {DEFAULT_TIMEOUT}m",
                    file=sys.stderr,
                )
                timeout = DEFAULT_TIMEOUT
            yield {
                "repo": repo_dir.name,
                "leg": job,
                "name": f"{repo_dir.name.replace('dotfiles-', '')} / {image}",
                "image": str(image),
                "prep": str(prep or ""),
                "offensive": bool(w.get("offensive", False)),
                "timeout": timeout,
            }


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    listed = root / "dotfiles-core" / "scripts" / "os-repos.txt"
    if not listed.is_file():
        listed = pathlib.Path("scripts/os-repos.txt")
    names = []
    for line in listed.read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            names.append(line)

    out = []
    for n in names:
        d = root / n
        if d.is_dir():
            out.extend(legs(d))
    # Stable order so a re-run's job names do not shuffle in the Actions UI.
    out.sort(key=lambda x: (x["repo"], x["leg"]))
    json.dump(out, sys.stdout)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
