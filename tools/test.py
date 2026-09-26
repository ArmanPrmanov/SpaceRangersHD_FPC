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
LOG_TURNS = 10
# More than one human (ROADMAP.md, Phase 4): 2, and enough that code which assumes "one or
# two" fails.
HUMAN_COUNTS = (2, 8)
HUMAN_TURNS = 20
REPLAYS = ROOT / "tests" / "replays"


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


def run_game(binary: Path, game_dir: Path, options: list[str]) -> tuple[int, str]:
    # A throwaway profile keeps the player's settings and logs out of the test.
    with tempfile.TemporaryDirectory(prefix="rangers-test-") as profile:
        command = [str(binary), f"--game-dir={game_dir}", f"--user-dir={profile}", *options]
        result = subprocess.run(command, capture_output=True, cwd=profile)
    output = result.stdout.decode("utf-8", "replace") + result.stderr.decode("utf-8", "replace")
    return result.returncode, output


def simulate(binary: Path, game_dir: Path, save: Path, options: list[str]) -> tuple[int, str]:
    return run_game(binary, game_dir, [f"--sim-save={save}", *options])


def output_tail(output: str) -> str:
    return "".join("\n    " + line for line in output.strip().splitlines()[-12:])


def last_line(output: str, prefix: str) -> str:
    lines = [line for line in output.splitlines() if line.startswith(prefix)]
    return lines[-1] if lines else ""


def check_command_log(args, binary: Path, save: Path) -> tuple[bool, str]:
    """Record a headless run as a command log and replay it to the same hashes."""
    with tempfile.TemporaryDirectory(prefix="rangers-log-") as directory:
        log = Path(directory) / "run.srcl"
        code, output = simulate(binary, args.game_dir, save, [
            f"--sim-turns={LOG_TURNS}", "--sim-hash-last", f"--sim-seed={args.seed}",
            f"--record-commands={log}",
        ])  # fmt: skip
        if code != 0:
            return False, "recording failed:" + output_tail(output)
        expected = last_line(output, "turn ").split("hash=")[-1].split()[0]
        code, output = run_game(
            binary, args.game_dir, [f"--replay-commands={log}", f"--sim-seed={args.seed}"]
        )
    summary = last_line(output, "done ")
    if code != 0 or f"hash={expected}" not in summary or " diverged=0 " not in summary:
        return False, "command log replay failed:" + output_tail(output)
    return True, f"command log of {LOG_TURNS} turns replays to the same hash"


def check_replay(args, binary: Path, log: Path) -> tuple[bool, list[str]]:
    """Replay a recorded play session; it must not diverge from the recording."""
    code, output = run_game(
        binary, args.game_dir, [f"--replay-commands={log}", f"--sim-seed={args.seed}"]
    )
    summary = last_line(output, "done ")
    notes = [line for line in output.splitlines() if line.startswith(("diverged ", "drift ", "checkpoint "))]
    notes = notes[:12] + ([f"... {len(notes) - 12} more"] if len(notes) > 12 else [])
    passed = code == 0 and " diverged=0 " in summary
    if not summary:
        notes.append("replay failed:" + output_tail(output))
    return passed, [summary, *notes]


def check_session(args, binary: Path, save: Path) -> tuple[bool, str]:
    """One human: session flags set by command, and a cheat on record, survive a save.

    The probe (--sim-session-probe) sets them before the round trip, so the save carries the
    per-human block although the game has one human.
    """
    code, output = simulate(
        binary, args.game_dir, save, ["--sim-roundtrip", "--sim-session-probe", "--sim-humans-dump"]
    )
    roundtrip = [line for line in output.splitlines() if line.startswith("roundtrip ")]
    flags = "state session textquests-off=1 friendly-fire=0" in output.splitlines()
    if code != 0 or not roundtrip or any("=ok" not in line for line in roundtrip) or not flags:
        return False, "session flags failed:" + output_tail(output)
    return True, "session flags and cheats survive a save"


def check_humans(args, binary: Path, save: Path, count: int) -> tuple[bool, str]:
    """Play with extra humans: no crash, a clean round trip, the same hashes twice.

    Before each round trip the probe gives every human, script and one event state that a
    load without the per-human save block would lose; the round trip compares it field by
    field (roundtrip humans=...), besides the state hash, which covers the block.
    """
    options = [
        f"--sim-humans={count}", "--sim-roundtrip", f"--sim-turns={HUMAN_TURNS}", "--sim-hash",
        f"--sim-seed={args.seed}", "--sim-session-probe",
    ]  # fmt: skip
    runs = []
    for _ in range(2):
        code, output = simulate(binary, args.game_dir, save, options)
        roundtrip = [line for line in output.splitlines() if line.startswith("roundtrip ")]
        if code != 0 or not roundtrip or any("=ok" not in line for line in roundtrip):
            return False, f"{count} humans failed:" + output_tail(output)
        # TODO(Phase 4, respawn): a lost human fails the test once destroyed humans respawn.
        lost = "" if f" humans={count} " in last_line(output, "done ") + " " else ", a human was lost"
        runs.append(turn_lines(output))
    if runs[0] != runs[1]:
        return False, f"{count} humans nondeterministic: " + first_divergence(runs[0], runs[1])
    return True, f"{count} humans: {HUMAN_TURNS} turns, round trip ok, deterministic{lost}"


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

    # The second run pins the presentation stream (visuals, audio) to another seed; the
    # simulation must not draw from it.
    runs = []
    for seed in (args.seed, args.seed + 1):
        hash_options = [f"--sim-turns={args.turns}", "--sim-hash", f"--sim-seed={seed}"]
        code, output = simulate(binary, args.game_dir, save, hash_options)
        if code != 0:
            notes.append("simulation failed:\n    " + "\n    ".join(output.strip().splitlines()[-12:]))
            return False, notes
        runs.append(turn_lines(output))
    if runs[0] != runs[1]:
        notes.append("nondeterministic: " + first_divergence(runs[0], runs[1]))
        return False, notes
    notes.append(f"deterministic over {args.turns} turns, independent of the presentation seed")

    # Hashing saves the galaxy; saving must not change what later turns compute.
    last_options = [f"--sim-turns={args.turns}", "--sim-hash-last", f"--sim-seed={args.seed}"]
    code, output = simulate(binary, args.game_dir, save, last_options)
    last = turn_lines(output)
    if code != 0 or last != runs[0][-1:]:
        notes.append("hashing changes the game: " + first_divergence(runs[0][-1:], last))
        return False, notes
    notes.append("hashing leaves the game unchanged")

    passed_log, note = check_command_log(args, binary, save)
    notes.append(note)
    if not passed_log:
        return False, notes

    passed_session, note = check_session(args, binary, save)
    notes.append(note)
    passed = passed and passed_session

    for count in HUMAN_COUNTS:
        passed_humans, note = check_humans(args, binary, save, count)
        notes.append(note)
        passed = passed and passed_humans

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
    parser.add_argument("--seed", type=int, default=0, help="Seed for the presentation stream.")
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

    replays = sorted(REPLAYS.glob("*.srcl")) if REPLAYS.is_dir() else []
    failed = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = {save: pool.submit(check_save, args, binary, save) for save in saves}
        futures.update({log: pool.submit(check_replay, args, binary, log) for log in replays})
        for path, future in futures.items():
            passed, notes = future.result()
            failed += not passed
            print(f"{'PASS' if passed else 'FAIL'} {path.name}")
            for note in notes:
                print(f"  {note}")
    total = len(saves) + len(replays)
    print(f"{total - failed}/{total} saves and replays passed ({target_name()})")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
