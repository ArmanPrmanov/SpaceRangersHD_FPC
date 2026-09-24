#!/usr/bin/env python3
"""Run the save-based regression tests: round trip, determinism and golden hashes.

Saves cannot be redistributed, so golden files hold only hashes. They are named
after the SHA-256 of the save, so anyone with the same save checks the same
file. Pass --update to record or replace them.
"""

import argparse
import concurrent.futures
import hashlib
import os
import platform
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GOLDEN = ROOT / "tests" / "golden"
ROUNDTRIP_TURNS = 5


def target_name() -> str:
    system = {"win32": "windows", "darwin": "macos"}.get(sys.platform, sys.platform)
    machine = platform.machine().lower()
    machine = {"amd64": "x64", "x86_64": "x64", "aarch64": "arm64"}.get(machine, machine)
    return f"{system}-{machine}"


def binary_path(release: bool) -> Path:
    configuration = "release" if release else "debug"
    if os.name == "nt":
        return ROOT / ".local" / f"windows-{configuration}" / "Rangers/Rangers.exe"
    return ROOT / ".local" / configuration / "Space Rangers HD.app/Contents/MacOS/Rangers"


def find_saves(paths: list[Path]) -> list[Path]:
    saves = []
    for path in paths:
        if path.is_dir():
            saves.extend(sorted(path.glob("*.sav")))
        elif path.is_file():
            saves.append(path)
        else:
            raise SystemExit(f"No such save or directory: {path}")
    return saves


def save_digest(save: Path) -> str:
    return hashlib.sha256(save.read_bytes()).hexdigest()[:16]


def simulate(binary: Path, game_dir: Path, save: Path, options: list[str]) -> tuple[int, str]:
    # A throwaway profile keeps the player's settings and logs out of the test.
    with tempfile.TemporaryDirectory(prefix="rangers-test-") as profile:
        command = [
            str(binary),
            f"--game-dir={game_dir}",
            f"--user-dir={profile}",
            f"--sim-save={save}",
            *options,
        ]
        result = subprocess.run(command, capture_output=True, cwd=profile)
    output = result.stdout.decode("utf-8", "replace") + result.stderr.decode("utf-8", "replace")
    return result.returncode, output


def turn_lines(output: str) -> list[str]:
    return [line.strip() for line in output.splitlines() if line.startswith("turn ")]


def first_divergence(expected: list[str], actual: list[str]) -> str:
    for a, b in zip(expected, actual):
        if a != b:
            return f"expected '{a}', got '{b}'"
    return f"expected {len(expected)} turns, got {len(actual)}"


def check_save(args, binary: Path, save: Path) -> tuple[bool, list[str]]:
    notes = []
    passed = True
    # Round trip the save as loaded, then again after a few turns of play.
    code, output = simulate(
        binary, args.game_dir, save, ["--sim-roundtrip", f"--sim-turns={ROUNDTRIP_TURNS}"]
    )
    roundtrip = [line for line in output.splitlines() if line.startswith("roundtrip ")]
    if code != 0 or not roundtrip:
        passed = False
        notes.append("round trip failed:\n    " + "\n    ".join(output.strip().splitlines()[-12:]))
    else:
        notes.append("round trip ok")

    hash_options = [f"--sim-turns={args.turns}", "--sim-hash", f"--sim-seed={args.seed}"]
    runs = []
    for _ in range(2):
        code, output = simulate(binary, args.game_dir, save, hash_options)
        if code != 0:
            notes.append("simulation failed:\n    " + "\n    ".join(output.strip().splitlines()[-12:]))
            return False, notes
        runs.append(turn_lines(output))
    if runs[0] != runs[1]:
        notes.append("nondeterministic: " + first_divergence(runs[0], runs[1]))
        return False, notes
    notes.append(f"deterministic over {args.turns} turns")

    golden = GOLDEN / target_name() / f"{save_digest(save)}.txt"
    header = f"# {save.name}: {args.turns} turns, seed {args.seed}"
    if golden.is_file() and not args.update:
        lines = golden.read_text(encoding="utf-8").splitlines()
        expected = [line for line in lines if line.startswith("turn ")]
        if lines[:1] != [header]:
            notes.append(f"golden {golden.name} was recorded as '{lines[0]}'; rerun with --update")
            passed = False
        elif expected != runs[0]:
            notes.append(f"golden {golden.name} differs: " + first_divergence(expected, runs[0]))
            passed = False
        else:
            notes.append(f"matches golden {golden.name}")
    else:
        golden.parent.mkdir(parents=True, exist_ok=True)
        golden.write_text("\n".join([header, *runs[0]]) + "\n", encoding="utf-8")
        notes.append(f"recorded golden {golden.name}")
    return passed, notes


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", action="store_true", help="Test the optimized build.")
    parser.add_argument(
        "--game-dir", type=Path, default=ROOT / "game", help="Game asset directory."
    )
    parser.add_argument(
        "saves",
        nargs="*",
        type=Path,
        default=[ROOT / "tests" / "saves"],
        help="Save files or directories of saves (default: tests/saves).",
    )
    parser.add_argument("--turns", type=int, default=100, help="Turns to simulate per save.")
    parser.add_argument("--seed", type=int, default=0, help="Seed for the shared random stream.")
    parser.add_argument("--update", action="store_true", help="Record golden hashes again.")
    parser.add_argument("--jobs", type=int, default=min(4, os.cpu_count() or 1))
    args = parser.parse_args()
    # Save names are often Cyrillic; do not fail on a console code page.
    sys.stdout.reconfigure(errors="replace")
    binary = binary_path(args.release)
    if not binary.is_file():
        parser.error("Run ./tools/build.py first, with a matching --release option.")
    args.game_dir = args.game_dir.expanduser().resolve()
    saves = find_saves([path.expanduser().resolve() for path in args.saves])
    if not saves:
        parser.error("No saves found. Put .sav files in tests/saves/ or pass them as arguments.")

    failed = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = {save: pool.submit(check_save, args, binary, save) for save in saves}
        for save, future in futures.items():
            passed, notes = future.result()
            failed += not passed
            print(f"{'PASS' if passed else 'FAIL'} {save.name}")
            for note in notes:
                print(f"  {note}")
    print(f"{len(saves) - failed}/{len(saves)} saves passed ({target_name()})")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
