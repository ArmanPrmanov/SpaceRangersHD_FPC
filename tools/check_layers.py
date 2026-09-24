#!/usr/bin/env python3
"""Check that simulation units do not use UI units.

Units under source/game, source/core and source/script must not name a unit under
source/screens or source/ui in a uses clause. Existing violations are listed in
tools/layers_allowlist.txt; the check fails on a violation that is not listed, and on
a listed one that no longer exists, so the list only shrinks. Pass --update to rewrite
the list after removing violations.
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "source"
ALLOWLIST = Path(__file__).with_name("layers_allowlist.txt")
SIMULATION = ("game", "core", "script")
PRESENTATION = ("screens", "ui")

COMMENT = re.compile(r"\{[^}]*\}|\(\*.*?\*\)|//[^\n]*", re.DOTALL)
USES = re.compile(r"\buses\b(.*?);", re.IGNORECASE | re.DOTALL)


def units_in(layers: tuple[str, ...]) -> dict[str, Path]:
    return {
        path.stem.lower(): path
        for layer in layers
        for path in sorted((SOURCE / layer).glob("*.pas"))
    }


def used_units(path: Path) -> set[str]:
    # Both branches of a conditional uses clause count: directives are stripped as comments.
    text = COMMENT.sub(" ", path.read_text(encoding="utf-8", errors="replace"))
    names = set()
    for clause in USES.findall(text):
        for entry in clause.split(","):
            name = entry.split()[0] if entry.split() else ""
            names.add(name.lower())
    return names


def violations() -> set[str]:
    simulation = units_in(SIMULATION)
    presentation = units_in(PRESENTATION)
    found = set()
    for unit, path in simulation.items():
        for used in used_units(path) & presentation.keys():
            found.add(f"{path.stem} -> {presentation[used].stem}")
    return found


def read_allowlist() -> set[str]:
    if not ALLOWLIST.is_file():
        return set()
    lines = ALLOWLIST.read_text(encoding="utf-8").splitlines()
    return {line.strip() for line in lines if line.strip() and not line.startswith("#")}


def write_allowlist(entries: set[str]) -> None:
    header = [
        "# Simulation units that still use UI units. Written by tools/check_layers.py --update.",
        "# Remove entries by removing the dependency; never add one by hand.",
    ]
    ordered = sorted(entries, key=str.lower)
    ALLOWLIST.write_text("\n".join([*header, *ordered]) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update", action="store_true", help="Rewrite the allowlist.")
    args = parser.parse_args()
    found = violations()
    if args.update:
        write_allowlist(found)
        print(f"{len(found)} allowed violations written to {ALLOWLIST.relative_to(ROOT)}")
        return 0
    allowed = read_allowlist()
    new = sorted(found - allowed, key=str.lower)
    gone = sorted(allowed - found, key=str.lower)
    for entry in new:
        print(f"new dependency on a UI unit: {entry}")
    for entry in gone:
        print(f"removed, delete from the allowlist (or run --update): {entry}")
    if new or gone:
        return 1
    print(f"ok: {len(found)} allowed violations remain")
    return 0


if __name__ == "__main__":
    sys.exit(main())
