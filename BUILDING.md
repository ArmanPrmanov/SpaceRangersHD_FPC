# Building

## macOS

The macOS ARM64 build requires Python 3, FPC 3.2.2 for bootstrapping, GNU Make,
Xcode command-line tools, CMake, pkg-config, SDL2, SDL2_mixer, libjpeg, and libpng.

The build creates the pinned FPC 3.3.1 LLVM compiler in `.local/fpc/` on first
use and rebuilds it when its source changes. `FPC_BOOTSTRAP` selects the installed
bootstrap compiler. The same generated compiler serves macOS and Android, with
a runtime compiled for each target. Pascal compiles through LLVM IR and Clang;
C code also uses Clang.

All builds use an RTL compiled with `CLASSESINLINE`; the pinned FPC also marks
the list error routine `noreturn`, allowing safe list accesses to optimize better.
macOS link-time optimization is a separate opt-in. Pass `--lto` to both scripts:

```sh
./tools/build.py --release --lto
./tools/run.py --release --lto
```

Normal builds keep their existing output paths. LTO builds use `.local/release-lto/`
or `.local/debug-lto/`, with separate RTL and game-unit caches. Switching between
them does not rebuild the compiler or overwrite the other configuration.
LTO takes longer to link. Android currently builds without LTO.

```sh
git submodule update --init --recursive
./tools/build.py
./tools/run.py --game-dir=/path/to/game
```

Place the game assets in `game/` using this layout:

```text
game/
  INSTALL.TXT
  INSTALL_ENGLISH.TXT
  INSTALL_RUSSIAN.TXT
  CFG.TXT
  CFG/        # configuration data and language subfolders
  DATA/*.pkg  # original game packages
```

Optional mods go in `game/Mods/` and are selected through the original mod manager.

`game/` is ignored by Git. With assets there, run `./tools/run.py` without arguments.
Generated output stays in `.local/`.
Use `--release` with both scripts for an optimized build.

Builds reuse unchanged Pascal units. On macOS, the native libraries also build
incrementally. Use `./tools/build.py --rebuild` (with `--release` if needed) to
force a full game rebuild. Changes to the compiler or Pascal flags automatically
rebuild the units.

Both macOS configurations keep matching `.dSYM` bundles beside `Rangers` and the
native libraries. Keep these with the corresponding binaries: crash backtraces
use them to print source paths and line numbers, including in release builds.
The macOS runtime uses `/usr/bin/atos` when FPC cannot resolve an address itself.

Saves/settings default to `~/Library/Application Support/SpaceRangersHD/`.
Game options include `--user-dir=/path/to/profile`, `--language=english`,
`--renderer=sdl`, and `--transitions=original`. A debug build also takes
`--poison-frees[=MB]`: freed memory is filled with `$DE` bytes and held back from reuse
(128 MB by default), so a stale reference faults at once (docs/network.md, Applying state).

To open a save in the galaxy observer:

```sh
./tools/run.py --observer-save=/path/to/save.sav --user-dir=/path/to/observer-profile
```

## Windows

The Windows x64 build uses FPC's native x86-64 code generator (no LLVM) and
MSYS2 UCRT64 for the C side.

- Python 3, CMake, and the FPC 3.2.2 installer `fpc-3.2.2.win32.and.win64.exe`,
  whose `bin/i386-win32/ppcrossx64.exe` bootstraps the vendored compiler.
  Set `FPC_BOOTSTRAP` to that path, or put the directory on `PATH`.
- MSYS2 with `mingw-w64-ucrt-x86_64-{gcc,ninja,SDL2,SDL2_mixer,libjpeg-turbo,libpng,zlib}`.
  `MSYS2_PREFIX` selects a UCRT64 prefix other than `C:/msys64/ucrt64`.

```powershell
git submodule update --init --recursive
$env:FPC_BOOTSTRAP = 'C:\FPC\3.2.2\bin\i386-win32\ppcrossx64.exe'
python tools\build.py --target windows
python tools\run.py --game-dir="C:\Games\Space Rangers HD A War Apart"
```

`.local/windows-debug/Rangers/` holds `Rangers.exe` with `okgf.dll`, `gamenative.dll`
and the MSYS2 DLLs they import. A GOG installation already has the `game/` layout below.
Saves/settings default to `%APPDATA%\SpaceRangersHD`, apart from the original
game's `Documents\SpaceRangersHD`.

The Windows RTL has real `windows` and `messages` units, which the port's Win32
shims cannot shadow. The build therefore compiles a copy of the Pascal sources staged
in `.local/windows-debug/sources/` (or `windows-release`), where
[tools/windows_sources.py](tools/windows_sources.py) renames the shims to `SRWindows`
and `SRMessages`. The repository keeps the upstream names. Line numbers are unchanged,
so compiler messages and backtraces point at the same lines in `source/` and `platform/`.

If FPC reports an internal error, compile the one unit with `-O-` first: if that
passes, it is the x86 backend, not game code.

## Android

`./tools/build.py --target android` produces `.local/android/Rangers.apk`.
Build from macOS ARM64 with the bootstrap tools above, JDK 21, CMake, Ninja,
and the Android SDK/NDK. Set these dependency paths:

- `ANDROID_HOME`: SDK with platform/build-tools 35 or newer.
- `ANDROID_NDK_HOME`: NDK installation.
- `ANDROID_PREFIX`: Android ARM64 libraries/headers for SDL2, SDL2_mixer, libjpeg,
  and libpng; SDL2_mixer and image libraries are linked statically.
- `SDL_SOURCE`: matching SDL2 source tree, supplying its Android Java classes.

Android Pascal and C code use the NDK's LLVM tools. The compiler submodule includes
[Android LLVM support](vendor/fpc/PORT.md).

`JAVA_HOME` selects the JDK. The APK contains code; the launcher imports game
resources from a ZIP of the `game/` layout above:

```sh
ditto -c -k --keepParent game .local/game.zip
```

After applying mods or settings that need a restart, tap Play in the launcher.
`--release` enables optimized native code. Keep `.local/android/debug.keystore`
for subsequent updates signed with the same local key.

## Tests

`python tools/unit_tests.py` builds and runs `tests/UnitTests.dpr`: RNG, `EC_Str`,
the expression evaluator, `TBufEC`, DAT and package codecs, on synthetic input.
It needs no game assets, but it links the game units, so build the game first.
CI runs it on Windows, plus `format.py --check`.

The save tests need assets and saves, which cannot be redistributed:

```sh
python tools/test.py --game-dir=/path/to/game path/to/saves-or-dir
```

For each save it checks a save → load → save round trip, both as loaded and after
five turns of play, runs 100 turns twice
and requires the same per-turn hashes, and compares them with
`tests/golden/<target>/<save sha256>.txt`. A missing golden file is recorded;
`--update` records it again after an intended change. `tests/saves/` is the
default save directory and is ignored by Git.

The runner behind it is the game binary itself:

```sh
Rangers --sim-save=save.sav --sim-turns=100 --sim-hash|--sim-hash-last [--sim-roundtrip]
        [--sim-seed=0] [--sim-dump=DIR]
```

It runs without a window or audio, parks the player as the observer does, and
prints `turn N day=D hash=H bytes=B unresolved=U` per turn. `--sim-roundtrip`
checks the round trip before the turns and, with `--sim-turns`, again after them.
`--sim-hash-last` hashes only the last turn; the tests compare it with a run that
hashes every turn, since hashing runs the save writer and must change nothing. The hash covers
`TGalaxy.SaveToBuffer`, with script references to objects written by id instead
of address; `unresolved` counts references it could not name. `--sim-dump`
writes each hashed state so two runs can be diffed.

`--sim-humans=N` adds humans until there are N. The round trip also compares
each human's state, the script bindings and the session flags field by field
(`roundtrip humans=ok`). `--sim-session-probe` sets that state before each round trip,
so that the per-human save block has something to carry, and `--sim-humans-dump`
prints it at the end (`state ...` lines).

`--sim-pvp` tests humans as targets instead of running turns: a second human joins
in the local human's star, and the local one attacks it with friendly fire on and
then off (`pvp ...` lines, ending in `pvp ok` or `pvp failed: ...`). With
`--sim-humans=N` the other humans join elsewhere.

`--sim-hotseat=DAYS` plays hot-seat instead of running turns (docs/humans.md, End turn
and hot-seat): with `--sim-humans=N`, each day every human in turn sends its own commands
(take off, fly, land, buy) and ends its turn, and the day runs when the last one has. It prints
`hotseat day=D plan=... hash=H` per day with `--sim-hash`, `hotseat barrier ok`, and
`done hotseat ... hash=H`.

The game records play with `--record-commands=LOG` and replays it headlessly with
`--replay-commands=LOG`. For hot-seat, `python tools/split_commands.py LOG DIR` splits a log
into one log per human (`human-<id>.srcl`), and `--replay-commands=DIR`, or a comma-separated
list of logs, replays them merged: between two shared records (loads, jobs), each human's
commands in the game's human order. The summary adds `logs=`, `humans=` and `barrier-waits=`,
the days that started before every human had ended its turn.

`--hotseat=N` starts the game for hot-seat: after a save loads or a new game starts, humans
join until there are N, and they take turns at this screen. It cannot be combined with the
headless options. `--load-save=PATH` opens a save at startup, past the main menu.

```sh
./tools/run.py --hotseat=2 --load-save=/path/to/save.sav
```

`python tools/check_layers.py` fails when a unit under `source/game`, `source/core` or
`source/script` uses a unit under `source/screens`, `source/ui` or `source/arcade`
(minigames), or a root global (`Globals`, `GlobalsV`, `GR_Main`) that
`tools/layers_globals.txt` classifies as `ui`. Every root global that the simulation uses
must be classified there. The violations that remain are listed in
`tools/layers_allowlist.txt`. When you remove one, run the check with `--update` so the
list gets shorter. The simulation reaches the UI through handlers in
[SimEvents](source/game/SimEvents.pas), which the UI installs at startup.

## Threads

The turn thread (`TThreadCalc`) runs the day while the UI thread plays the film.
The UI thread must not change simulation state while a turn job runs, except while
the turn thread waits for it (a dialogue or the score screen). Debug builds compile
assertions (`-Sa`) and log the first violation at each checked site to the session
log with a backtrace: money, ship orders and seeded random draws.
[CheckSimulationThread](source/core/SimulationThread.pas).

## Formatting

Install [pasfmt](https://github.com/integrated-application-development/pasfmt),
clang-format, Ruff, cmakelang (`cmake-format`), and libxml2 (`xmllint`).
Run `./tools/format.py` to format Pascal, C, Java, Python, CMake, and XML source;
`./tools/format.py --check` checks the same files.

## Source comments

In Pascal game source, place comments beside changed statements, declarations, or routines:

```pascal
// CHANGE: ENHANCEMENT - Add search bookmark navigation.
// CHANGE: BUGFIX - Avoid floating-point underflow near path endpoints.
// CHANGE: PERFORMANCE - Reuse rendered thumbnails within a turn.
```

Use `PORTABILITY`, `LIMITATION`, or `CLEANUP` for those kinds of game-source changes.
Keep comments short and explain the reason. Use the same category at related
sites so a text search finds them together.
