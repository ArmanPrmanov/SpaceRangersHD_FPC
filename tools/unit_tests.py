#!/usr/bin/env python3
"""Compile and run the asset-free Pascal unit tests in tests/.

The tested units reach the whole game through their uses clauses, so the test program
links every game unit and loads the game's native libraries. Build the game first with
`tools/build.py`; this script compiles its own units under `.local/*-tests/`.
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path

from build import compile_pascal, output, pascal_flags, run_step
from compiler import prepare_compiler
from windows_sources import stage_windows_sources

ROOT = Path(__file__).resolve().parents[1]
PROGRAM = ROOT / "tests/UnitTests.dpr"


def require_game(directory: Path, library: str) -> Path:
    if not (directory / library).is_file():
        raise FileNotFoundError(f"{directory / library} is missing; run tools/build.py first.")
    return directory


def build_windows(release: bool, rebuild: bool) -> tuple[Path, dict[str, str]]:
    game = require_game(
        ROOT / ".local" / ("windows-release" if release else "windows-debug") / "Rangers",
        "gamenative.dll",
    )
    compiler, compiler_flags = prepare_compiler("windows", run_step)
    work = ROOT / ".local" / ("windows-release-tests" if release else "windows-tests")
    units, binaries = work / "units", work / "bin"
    for directory in (units, binaries):
        directory.mkdir(parents=True, exist_ok=True)
    # Same staged copy as the game build, so the Win32 shims do not shadow the RTL.
    sources = stage_windows_sources(work / "sources")
    compile_pascal(work, [
        compiler, *compiler_flags, *pascal_flags(release, root=sources), "-Twin64",
        f"-FU{units}", f"-FE{binaries}", PROGRAM,
    ], rebuild)  # fmt: skip
    # The game's DLLs and their MSYS2 dependencies sit beside Rangers.exe.
    env = {**os.environ, "PATH": str(game) + os.pathsep + os.environ["PATH"]}
    return binaries / "UnitTests.exe", env


def build_macos(release: bool, rebuild: bool) -> tuple[Path, dict[str, str]]:
    app = ROOT / ".local" / ("release" if release else "debug") / "Space Rangers HD.app"
    game = require_game(app / "Contents/MacOS", "libgamenative.dylib")
    compiler, compiler_flags = prepare_compiler("macos", run_step)
    sdk = output("xcrun", "--show-sdk-path")
    work = ROOT / ".local" / ("release-tests" if release else "debug-tests")
    units, binaries = work / "units", work / "bin"
    for directory in (units, binaries):
        directory.mkdir(parents=True, exist_ok=True)
    compile_pascal(work, [
        compiler, *compiler_flags, *pascal_flags(release), "-Aclang-llvm-darwin",
        f"-FU{units}", f"-FE{binaries}", f"-Fl{game}",
        "-k-lgamenative", "-k-lokgf", "-k-lz", "-k-rpath", f"-k{game}", f"-XR{sdk}",
        PROGRAM,
    ], rebuild)  # fmt: skip
    return binaries / "UnitTests", dict(os.environ)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", action="store_true", help="Test against the release build.")
    parser.add_argument("--rebuild", action="store_true", help="Rebuild all test units.")
    args = parser.parse_args()
    try:
        if os.name == "nt":
            program, env = build_windows(args.release, args.rebuild)
        elif sys.platform == "darwin":
            program, env = build_macos(args.release, args.rebuild)
        else:
            parser.error("Unit tests run on Windows and macOS hosts only.")
    except subprocess.CalledProcessError as error:
        parser.exit(1, error.output or str(error))
    except (OSError, RuntimeError) as error:
        parser.exit(1, f"{error}\n")
    scratch = program.parent / "scratch"
    return subprocess.run([program, scratch], env=env, check=False).returncode


if __name__ == "__main__":
    sys.exit(main())
