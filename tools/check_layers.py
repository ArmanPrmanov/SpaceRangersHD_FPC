#!/usr/bin/env python3
"""Check that simulation units do not use UI units or UI globals.

Units under source/game, source/core and source/script must not name a unit under
source/screens, source/ui or source/arcade in a uses clause. They also reach the UI through
the root units' globals (Globals, GlobalsV, GR_Main): every root global they use must be
classified in tools/layers_globals.txt, and they must not use one classified as ui.

Existing violations are listed in tools/layers_allowlist.txt; the check fails on a violation
that is not listed, and on a listed one that no longer exists, so the list only shrinks.
Pass --update to rewrite the list after removing violations.
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "source"
ALLOWLIST = Path(__file__).with_name("layers_allowlist.txt")
GLOBAL_KINDS = Path(__file__).with_name("layers_globals.txt")
SIMULATION = ("game", "core", "script")
PRESENTATION = ("screens", "ui", "arcade")
ROOT_UNITS = ("Globals", "GlobalsV", "GR_Main")

COMMENT = re.compile(r"\{[^}]*\}|\(\*.*?\*\)|//[^\n]*", re.DOTALL)
USES = re.compile(r"\buses\b(.*?);", re.IGNORECASE | re.DOTALL)
VAR_BLOCK = re.compile(
    r"^(?:var|threadvar)\b(.*?)(?=^(?:type|const|var|threadvar|procedure|function)\b)",
    re.IGNORECASE | re.MULTILINE | re.DOTALL,
)
VAR_NAMES = re.compile(r"^\s{2}(\w+(?:\s*,\s*\w+)*)\s*:", re.MULTILINE)
# A bare name, or one qualified by its root unit. A field of the same name after a dot does
# not count.
NAME = re.compile(
    r"(?:(?<![.\w])|" + "|".join(rf"(?<=\b{unit}\.)" for unit in ROOT_UNITS) + r")(\w+)\b"
)


def units_in(layers: tuple[str, ...]) -> dict[str, Path]:
    return {
        path.stem.lower(): path
        for layer in layers
        for path in sorted((SOURCE / layer).glob("*.pas"))
    }


def source_text(path: Path) -> str:
    return COMMENT.sub(" ", path.read_text(encoding="utf-8", errors="replace"))


def used_units(path: Path) -> set[str]:
    # Both branches of a conditional uses clause count: directives are stripped as comments.
    names = set()
    for clause in USES.findall(source_text(path)):
        for entry in clause.split(","):
            words = entry.split()
            names.add(words[0].lower() if words else "")
    return names


def root_globals() -> set[str]:
    names = set()
    for unit in ROOT_UNITS:
        text = source_text(SOURCE / f"{unit}.pas")
        interface = text[: text.lower().index("\nimplementation")] + "\nprocedure"
        for block in VAR_BLOCK.findall(interface):
            for group in VAR_NAMES.findall(block):
                names.update(name.strip() for name in group.split(","))
    return names


def global_kinds() -> dict[str, str]:
    kinds = {}
    for line in GLOBAL_KINDS.read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.startswith("#"):
            kind, name = line.split()
            kinds[name] = kind
    return kinds


def violations() -> tuple[set[str], set[str]]:
    simulation = units_in(SIMULATION)
    presentation = units_in(PRESENTATION)
    names = root_globals()
    kinds = global_kinds()
    found, unclassified = set(), set()
    for path in simulation.values():
        for used in used_units(path) & presentation.keys():
            found.add(f"{path.stem} -> {presentation[used].stem}")
        for name in set(NAME.findall(source_text(path))) & names:
            if name not in kinds:
                unclassified.add(f"{path.stem} -> {name}")
            elif kinds[name] == "ui":
                found.add(f"{path.stem} -> {name}")
    return found, unclassified


def read_allowlist() -> set[str]:
    if not ALLOWLIST.is_file():
        return set()
    lines = ALLOWLIST.read_text(encoding="utf-8").splitlines()
    return {line.strip() for line in lines if line.strip() and not line.startswith("#")}


def write_allowlist(entries: set[str]) -> None:
    header = [
        "# Simulation units that still use UI units or ui globals (tools/layers_globals.txt).",
        "# Written by tools/check_layers.py --update.",
        "# Remove entries by removing the dependency; never add one by hand.",
    ]
    ordered = sorted(entries, key=str.lower)
    ALLOWLIST.write_text("\n".join([*header, *ordered]) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update", action="store_true", help="Rewrite the allowlist.")
    args = parser.parse_args()
    found, unclassified = violations()
    for entry in sorted(unclassified, key=str.lower):
        print(f"root global not classified in {GLOBAL_KINDS.name}: {entry}")
    if args.update:
        write_allowlist(found)
        print(f"{len(found)} allowed violations written to {ALLOWLIST.relative_to(ROOT)}")
        return 1 if unclassified else 0
    allowed = read_allowlist()
    new = sorted(found - allowed, key=str.lower)
    gone = sorted(allowed - found, key=str.lower)
    for entry in new:
        print(f"new dependency on a UI unit or global: {entry}")
    for entry in gone:
        print(f"removed, delete from the allowlist (or run --update): {entry}")
    if new or gone or unclassified:
        return 1
    print(f"ok: {len(found)} allowed violations remain")
    return 0


if __name__ == "__main__":
    sys.exit(main())
