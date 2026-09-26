#!/usr/bin/env python3
"""Count how each unit refers to humans (ROADMAP.md, Phase 4; docs/humans.md).

`GetPlayer` means "the one human" and is being replaced by names that say which human a
site means. The class of a site is the name it uses:

    unclassified  GetPlayer
    local         LocalPlayer, LocalHuman: whose screen this is
    actor         Actor(...), ActorHuman(...), ActingHuman, script bindings: who did this
    each          Session.Humans, ForEachHuman: every human
    any           IsHuman, StarHasHuman, HumanOf, FindHuman: some human qualifies

Sites that became `Self` or a parameter are not counted; the unclassified count is the
measure of progress. The table is written to tools/player_sites.txt. With --check the
script fails if the table is stale or if a simulation unit uses GetPlayer more often than
the table allows, so the count only goes down.
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "source"
TABLE = ROOT / "tools" / "player_sites.txt"
SIMULATION = ("game", "core", "script")

CLASSES = {
    "unclassified": r"\bGetPlayer\b",
    "local": r"\bLocal(?:Player|Human)\b",
    "actor": r"\bActor(?:Human)?\(|\bActingHuman\b|\bScriptHuman\b|\bScriptPlayer\b|\bBoundHuman\b|\bDefaultScriptHuman\b",
    "each": r"\bSession\.Humans\b|\bForEachHuman\b",
    "any": r"\b(?:IsHuman|StarHasHuman|StarHasHumanInSpace|HumanOf|FindHuman|NearestHuman|IsRuinsProxy|RuinsProxyOwner|HasLivingHuman|IsFilmedStar|FilmHuman)\(",
}
COMMENT = re.compile(r"//[^\n]*|\{[^}]*\}|\(\*.*?\*\)", re.S)
STRING = re.compile(r"'[^'\n]*'")


def count(text: str) -> dict[str, int]:
    code = STRING.sub("''", COMMENT.sub("", text))
    return {name: len(re.findall(pattern, code)) for name, pattern in CLASSES.items()}


def layer(path: Path) -> str:
    parts = path.relative_to(SOURCE).parts
    return "simulation" if len(parts) > 1 and parts[0] in SIMULATION else "presentation"


def scan() -> list[tuple[str, str, dict[str, int]]]:
    rows = []
    for path in sorted(SOURCE.rglob("*.pas")):
        counts = count(path.read_text(encoding="utf-8", errors="replace"))
        if any(counts.values()):
            rows.append((path.relative_to(SOURCE).as_posix(), layer(path), counts))
    return rows


def render(rows) -> str:
    names = list(CLASSES)
    lines = [
        "# How each unit refers to humans. Written by tools/player_sites.py --update.",
        "# " + "\t".join(["unit", "layer", *names]),
    ]
    totals = {layer_name: dict.fromkeys(names, 0) for layer_name in ("simulation", "presentation")}
    for unit, layer_name, counts in rows:
        lines.append("\t".join([unit, layer_name, *(str(counts[name]) for name in names)]))
        for name in names:
            totals[layer_name][name] += counts[name]
    for layer_name, counts in totals.items():
        lines.append("\t".join(["total", layer_name, *(str(counts[name]) for name in names)]))
    return "\n".join(lines) + "\n"


def read_table() -> dict[str, int]:
    allowed = {}
    if TABLE.is_file():
        for line in TABLE.read_text(encoding="utf-8").splitlines():
            if line.startswith("#"):
                continue
            fields = line.split("\t")
            allowed[fields[0] + "/" + fields[1]] = int(fields[2])
    return allowed


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument("--update", action="store_true", help="Rewrite the table.")
    parser.add_argument("--check", action="store_true", help="Fail if the table is stale.")
    args = parser.parse_args()
    rows = scan()
    text = render(rows)
    if args.update:
        TABLE.write_text(text, encoding="utf-8")
    failed = False
    if args.check:
        allowed = read_table()
        for unit, layer_name, counts in rows:
            limit = allowed.get(unit + "/" + layer_name, 0)
            if layer_name == "simulation" and counts["unclassified"] > limit:
                print(f"{unit}: {counts['unclassified']} GetPlayer uses, the table allows {limit}")
                failed = True
        if not failed and TABLE.read_text(encoding="utf-8") != text:
            print(f"{TABLE.relative_to(ROOT)} is stale; run tools/player_sites.py --update")
            failed = True
    for line in text.splitlines():
        if line.startswith("total"):
            print(line.replace("\t", "  "))
    print("columns: " + "  ".join(CLASSES))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
