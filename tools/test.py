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
import statistics
import struct
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# The game is a console program; keep its runs from opening a window on Windows.
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)
GOLDEN = ROOT / "tests" / "golden"
ROUNDTRIP_TURNS = 5
LOG_TURNS = 10
# More than one human (ROADMAP.md, Phase 4): 2, and enough that code which assumes "one or
# two" fails.
HUMAN_COUNTS = (2, 8)
HUMAN_TURNS = 20
# The turn before which the runs with extra humans destroy two humans' rangers, which must
# respawn (ROADMAP.md, Phase 4, item 9).
HUMAN_KILL_TURN = 5
REPLAYS = ROOT / "tests" / "replays"
# Hot-seat (ROADMAP.md, Phase 4, test plan): days each human plays from its own command log.
HOTSEAT_DAYS = 10
# The command kind of EndTurn (source/game/aPlayerActions.pas).
END_TURN_KIND = 43
# Text quests in multiplayer (docs/progress/2026-10-19-text-quests-plan.md, Phase B): in a
# two-human hot-seat the second human plays this quest on the first day; the run goes on for at
# least QUEST_HOTSEAT_DAYS days, and until that human has paid the days the quest owes.
QUEST_HOTSEAT_QUEST = "Prison"
QUEST_HOTSEAT_DAYS = 3
# Networked play (ROADMAP.md, Phase 5; docs/network.md, Tests): a headless host and this many
# headless clients over loopback, for this many days. With one client, a third run has the
# client leave after NET_LEAVE_DAY days and join again, and a fourth has it leave in the middle
# of a remote dialogue and join again. From day NET_TALK_DAY the host's day asks the remote
# humans of one star something (--sim-net-talk); the clients answer. The host sends the day's
# films before it asks (--sim-net-talk-after-film) and each client plays its film for NET_FILM_MS
# (--sim-net-film-ms), so the talk comes during the film and waits for its end. With one client,
# the rejoin is first cancelled once (--sim-net-cancel-join), and a fifth run has the host stop
# hosting after NET_STOP_DAY days (--sim-net-stop-at). With one client, and in the new game, the
# host buys the goods of a client's queued purchase first, which it must refuse and tell the
# client (--sim-net-buy-race).
NET_CLIENT_COUNTS = (1, 7)
NET_DAYS = 10
NET_LEAVE_DAY = 3
NET_TALK_DAY = 2
NET_FILM_MS = 500
NET_STOP_DAY = 3
# A client notices that the host stopped hosting within this many ms.
NET_NOTICE_MS = 5000
# Silent losses (docs/network.md, Disconnects): with one client, a sixth run has the client's
# connection go silent before the turn of day NET_SILENT_DAY (--sim-net-silent-at), so the host
# must time it out after NetSilenceTimeoutMs (NET_SILENCE_MS; the client pings every NET_PING_MS
# when it has nothing to send, so its last bytes may be that much older), and the client then
# reconnects by itself; a seventh has it reconnect at once with its token (--sim-net-takeover),
# which the host must take within NET_TAKEOVER_MS. An eighth has the host go silent after day
# NET_SILENT_DAY (--sim-net-host-silent-at): the client must time it out and reconnect; a ninth
# has the host vanish then (--sim-net-host-exit-at): the client must give up after its reconnect
# window, NET_GIVE_UP_MS (--sim-net-reconnect-ms); each try connects for NET_TRY_MS at most.
NET_SILENT_DAY = 3
NET_SILENCE_MS = 10000
NET_PING_MS = 2000
NET_TAKEOVER_MS = 3000
NET_GIVE_UP_MS = 8000
NET_TRY_MS = 5000
# The command kind of TradeGoods (source/game/aShopActions.pas), and the reason a purchase of
# goods sold first is refused with (aCommands.RefusalReasonName).
TRADE_GOODS_KIND = 110
OUT_OF_STOCK = "out-of-stock"
# Trades (docs/commands.md, Trades; docs/network.md, Trades): the host applies a client's as it
# arrives and relays it to the clients at the same planet or station; nothing else is relayed.
# The run with --sim-net-shop: a new game, two clients at the host's human's planet, NET_SHOP_DAYS
# days.
TRADE_KINDS = {
    "BuyEquipment", "FinishStoredHullPurchase", "TradeGoods", "RepairHull", "Refuel",
    "SellHeld", "RepairHeld", "RefuelHeld", "ReloadHeld", "RepairAll", "BuyRockets",
    "SellHoldInventory", "SellHoldArtefact", "SellHoldGoods", "SellStoredItem",
    "PayForModernization", "BuyPirateNodes", "BuySatellite", "Invest", "BuySpecialShip",
    "BuildPirateShip", "BuyMap",
}  # fmt: skip
# The ship screen's sales: a host relays their effect (RelayedSale), never the sale itself
# (docs/network.md, Trades).
SHIP_SCREEN_SALES = {"SellHeld", "SellHoldInventory", "SellHoldArtefact", "SellHoldGoods", "SellStoredItem"}
# The commands that change the shared storage (docs/humans.md, Storage): trades whose effect a
# host relays (RelayedStorage), never the command itself.
STORAGE_COMMANDS = {
    "TakeStored", "TakeStoredHull", "StoreHeld", "CloseVacantStorageSlot", "ChangeHull",
    "TakeAllFromStorage", "PutAllIntoStorage", "SortStorage",
}  # fmt: skip
TRADE_KINDS |= STORAGE_COMMANDS
RELAYED_KINDS = (TRADE_KINDS - SHIP_SCREEN_SALES - STORAGE_COMMANDS) | {"RelayedSale", "RelayedTextQuest", "RelayedStorage"}
NET_SHOP_DAYS = 3
# Text quests in a session (docs/progress/2026-10-19-text-quests-plan.md, Phase C): a client plays
# a text quest on its NET_QUEST_DAY-th turn (--sim-net-quest). With two clients, both at one
# planet with a quest to it, the first plays it and the second's BeginTextQuest is refused
# (NET_QUEST_REFUSAL); with one client it plays QUEST_HOTSEAT_QUEST by name and owes its days;
# with one client that goes silent in the middle of its planet quest, it abandons the quest.
NET_QUEST_DAY = 1
NET_QUEST_REFUSAL = "in-use"
# A networked process that runs longer than this has hung.
NET_TIMEOUT = 600
# Any other game run that takes longer than this has hung (the longest, 100 turns of a save,
# takes a few minutes in the debug build, more with --poison-frees).
GAME_TIMEOUT = 1800
# Options every game run gets, such as --poison-frees (set in main).
GAME_OPTIONS: list[str] = []

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_commands  # noqa: E402


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


def timeout_note(seconds: float, command: list[str]) -> str:
    return f"TIMEOUT: killed after {seconds:.0f} s: " + subprocess.list2cmdline(command)


def run_game(binary: Path, game_dir: Path, options: list[str]) -> tuple[int, str]:
    """Runs the game to its end; a run that hangs is killed after GAME_TIMEOUT seconds and
    fails with a TIMEOUT line, the last of its output, naming the command."""
    # A throwaway profile keeps the player's settings and logs out of the test.
    with tempfile.TemporaryDirectory(prefix="rangers-test-") as profile:
        command = [
            str(binary), f"--game-dir={game_dir}", f"--user-dir={profile}", *GAME_OPTIONS, *options
        ]
        try:
            result = subprocess.run(
                command, capture_output=True, cwd=profile, creationflags=NO_WINDOW,
                timeout=GAME_TIMEOUT,
            )
        except subprocess.TimeoutExpired as expired:
            output = (expired.stdout or b"").decode("utf-8", "replace")
            output += (expired.stderr or b"").decode("utf-8", "replace")
            return -1, output + "\n" + timeout_note(GAME_TIMEOUT, command)
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
    """One human: session flags set by command, a cheat on record and text-quest days owed
    (THuman.QuestDaysOwed) survive a save.

    The probe (--sim-session-probe) sets them before the round trip, so the save carries the
    per-human block although the game has one human.
    """
    code, output = simulate(
        binary, args.game_dir, save, ["--sim-roundtrip", "--sim-session-probe", "--sim-humans-dump"]
    )
    roundtrip = [line for line in output.splitlines() if line.startswith("roundtrip ")]
    flags = "state session friendly-fire=0" in output.splitlines() and "state session cheats=0" in output.splitlines()
    owed = any(line.startswith("state human 0 ") and " quest-days=1" in line for line in output.splitlines())
    # One human: a cheat command applies, and the cheats flag does not stop it (single player).
    cheats = [line for line in output.splitlines() if line.startswith("probe cheat ")]
    cheated = bool(cheats) and all(" on=applied off=applied " in line + " " for line in cheats)
    if code != 0 or not roundtrip or any("=ok" not in line for line in roundtrip) or not flags or not owed:
        return False, "session flags failed:" + output_tail(output)
    if not cheated:
        return False, f"single-player cheat command failed: {cheats}"
    return True, "session flags, cheats and text-quest days owed survive a save; a cheat command applies"


def check_shared_shop(args, binary: Path, save: Path) -> tuple[bool, str]:
    """Two humans at one planet share its equipment stock (--sim-shared-shop).

    The save's open shop grid must load with its items back in the shop. Both humans see the
    whole stock; the second's purchase of what the first bought is refused as gone, and its
    purchase of another item by a slot that moved goes through; an item sold back can be
    bought; no item is lost or in two places; and both grids survive a round trip.
    """
    code, output = simulate(binary, args.game_dir, save, ["--sim-shared-shop"])
    lines = output.splitlines()
    if code != 0 or "shared shop ok" not in lines:
        return False, "shared shop failed:" + output_tail(output)
    loaded = last_line(output, "shared shop loaded ")
    return True, f"two humans share a shop's stock ({loaded})"


def check_shared_storage(args, binary: Path, save: Path) -> tuple[bool, str]:
    """Two humans at one planet share its storage (--sim-shared-storage; docs/humans.md, Storage).

    The save's humans share one pool. Two humans join at a planet: one stores two items, the
    other sees them and takes one; the first's take of it, by the cell and id its copy showed, is
    refused (item-gone), and so is a take naming another item in a cell. A save in which one human
    has a storage of its own (made before the pool) loads with it merged into the pool, a cell
    taken twice moved, and a round trip keeps the pool."""
    code, output = simulate(binary, args.game_dir, save, ["--sim-shared-storage", f"--sim-seed={args.seed}"])
    lines = [line.strip() for line in output.splitlines()]
    if code != 0 or "shared storage ok" not in lines:
        return False, "shared storage failed:" + output_tail(output)
    merged = last_line(output, "shared storage merged ")
    return True, f"two humans share a planet's storage, a second take is refused, per-human storages merge ({merged})"


def check_shared_quests(args, binary: Path, save: Path) -> tuple[bool, str]:
    """The humans share the government quests (--sim-shared-quests; docs/humans.md, Quests).

    Human A takes a letter quest and every human's journal shows it; human B, in another star,
    delivers A's letter: the reward is split equally (B gets what does not divide), every human
    gets the whole experience, the completion, the finished quest and the relation. While A holds a quest
    from a planet, another human there is offered none and its stale offer is refused
    (offer-gone). A quest's deadline fails it once for every human, and a round trip keeps
    every human's finished quests."""
    code, output = simulate(binary, args.game_dir, save, ["--sim-shared-quests", f"--sim-seed={args.seed}"])
    lines = [line.strip() for line in output.splitlines()]
    if code != 0 or "shared quests ok" not in lines:
        return False, "shared quests failed:" + output_tail(output)
    delivered = last_line(output, "shared quests delivered ")
    return True, f"the humans share the quests: another human delivers, the reward splits ({delivered})"


def check_arcade_hold(args, binary: Path, save: Path) -> tuple[bool, str]:
    """A remote human's black hole battle (--sim-arcade-hold; docs/network.md, Black hole
    battles).

    The fall of a human whose battles are played elsewhere holds the day, though in hyperspace,
    and a round trip keeps that; its battle's loot comes back by one command (an item with a
    new id, kills, goods); the exit clears the hold and the end turn after it ends the day."""
    code, output = simulate(binary, args.game_dir, save, ["--sim-arcade-hold", f"--sim-seed={args.seed}"])
    lines = [line.strip() for line in output.splitlines()]
    if code != 0 or "arcade hold ok" not in lines:
        return False, "arcade hold failed:" + output_tail(output)
    loot = last_line(output, "arcade hold loot ")
    return True, f"a remote black hole battle holds the day and sends its loot ({loot})"


def check_script_routing(args, binary: Path, save: Path) -> tuple[bool, str]:
    """Script builtins act for the script's human, on that human's machine (--sim-script-routing).

    Of two joined humans one is made local. The other's script code shows no box, screen or
    music and gets a declining player's answers; a command nested in its command is its own;
    its takeoff and end-turn requests are its own, and its commands clear only its own; its
    battles and videos are queued only in its own command, and only its own report finishes
    them; a video while its ship screen shows is not queued (its machine plays it at once and
    reports nothing); the talk builtins read the talking human's talk; and its ruins mode opens no screen.
    Its dialogue commands name scripts, injected answers and overrides by key: an answer reaches its
    script though the scripts are in another order, an injected answer runs its own action though
    the list was built again in another order, a stale key is refused (target-gone), and a log's
    index form still runs by index; they leave the local human's open dialogue as it was.
    """
    code, output = simulate(binary, args.game_dir, save, ["--sim-script-routing"])
    lines = output.splitlines()
    if code != 0 or "script routing ok" not in lines:
        return False, "script routing failed:" + output_tail(output)
    defaults = last_line(output, "script routing ui ")
    return True, f"script builtins act for the script's human ({defaults})"


def check_stale_commands(args, binary: Path, save: Path) -> tuple[bool, str]:
    """Two humans send the same command from copies made before either acted (--sim-stale-commands).

    Each part has the second human's command refused with its reason, its money unchanged, and
    no item lost or in two places: a one-off special ship, a satellite offer, an investment in a
    new station, building a ship at a Dominion with a shop part and relocating the Dominion (and
    the orders after it), selling to a ranger in space that can pay one sale, buying a map, and
    picking up surface loot (the second pickup of a moved entry goes through, found by its id).
    Also: a sponsored station's ship is open to one human at a time (the experience it lends
    comes back, also when the human goes without closing it), and a take from a hold cell another
    human emptied is refused without holding the item; a second payment for a modernization;
    gifts and a deposit beyond the money; a truce that would replace another human's; another
    human's medals and interceptors; an equipment configuration that is not there; a side
    change whose price went up; and nodes from an empty pirate base.
    """
    code, output = simulate(binary, args.game_dir, save, ["--sim-stale-commands"])
    lines = output.splitlines()
    if code != 0 or "stale commands ok" not in lines:
        return False, "stale commands failed:" + output_tail(output)
    skipped = [line for line in lines if line.startswith("stale ") and " skipped:" in line]
    note = "a second human's command from a stale copy is refused and changes nothing"
    if skipped:
        note += " (" + "; ".join(skipped) + ")"
    return True, note


def play_text_quest(args, binary: Path, save: Path, quest: str) -> tuple[bool, list[str], str]:
    """Plays one text quest headlessly twice (--sim-text-quest); returns whether both runs gave
    the same pages, outcome and state hash, the first run's lines, and a note."""
    runs = []
    for _ in range(2):
        code, output = simulate(
            binary, args.game_dir, save, [f"--sim-text-quest={quest}", f"--sim-seed={args.seed}"]
        )
        lines = [line for line in output.splitlines() if line.startswith(("quest ", "turn "))]
        if code != 0 or not any(line.startswith("quest done ") for line in lines):
            return False, lines, f"text quest {quest} failed:" + output_tail(output)
        runs.append(lines)
    if runs[0] != runs[1]:
        return False, runs[0], f"text quest {quest} nondeterministic: " + first_divergence(runs[0], runs[1])
    done = [line for line in runs[0] if line.startswith("quest done ")][-1]
    return True, runs[0], f"text quest {quest} repeats ({done.removeprefix('quest done ')})"


def check_text_quest(args, binary: Path, save: Path) -> tuple[bool, str]:
    """A text quest played without its screen (--sim-text-quest; docs/progress/
    2026-10-19-text-quests-plan.md, Phase A).

    The save's human plays the prison quest, and the save's first planet quest by its number,
    with the headless quest player, twice each: the page hashes, the outcome and the state hash
    after it must be the same both times. A ranger who dies in a quest leaves no state to hash.
    """
    passed, lines, note = play_text_quest(args, binary, save, "Prison")
    if not passed:
        return False, note
    notes = [note]
    planets = [line for line in lines if line.startswith("quest save planet-quests=")]
    first = int(planets[-1].split("first=")[-1]) if planets else -1
    if first >= 0:
        passed, _, note = play_text_quest(args, binary, save, str(first))
        notes.append(note)
    return passed, "; ".join(notes)


def check_quest_owed(lines: list[str]) -> str:
    """The days a hot-seat quest owes (--sim-text-quest with --sim-hotseat): the first "quest
    owed" line owes the quest's days, each day takes one off, the human holds no day while it
    owes one and holds the next once it owes none, its quest is no longer open, and while it
    owes days the day runs without its turn (its plan letter is "."). Returns what is wrong."""
    done = [line for line in lines if line.startswith("quest done ")]
    if not done:
        return "the quest did not end"
    days = int(done[0].split(" days=")[1].split()[0])
    previous = None
    for index, line in enumerate(lines):
        if not line.startswith("quest owed "):
            continue
        fields = dict(part.split("=", 1) for part in line.split()[2:])
        owed, holds = int(fields["days"]), fields["holds"]
        if fields["open"] != "0":
            return f"the quest is still open: {line}"
        if previous is None and owed != days:
            return f"the quest passed {days} days, the human owes {owed}"
        if previous is not None and owed != max(previous - 1, 0):
            return f"the days owed went from {previous} to {owed}"
        if (owed > 0) != (holds == "0"):
            return f"holds the day wrongly: {line}"
        following = [later for later in lines[index + 1:] if later.startswith("hotseat day=")]
        # The first is said on the quest's own day, whose plan has the quest ("q").
        if previous is not None and owed > 0 and following and not following[0].split("plan=")[1].split()[0].endswith("."):
            return f"the human played a turn while it owed days: {following[0]}"
        previous = owed
    if previous is None:
        return "no day after the quest"
    if previous != 0:
        return f"the run ended with {previous} days still owed"
    return ""


def check_hotseat_text_quest(args, binary: Path, save: Path) -> tuple[bool, str]:
    """A text quest in a two-human hot-seat (docs/progress/2026-10-19-text-quests-plan.md,
    Phase B): the second human plays QUEST_HOTSEAT_QUEST on the first day with the headless
    quest player. The quest runs no galaxy day; its days are owed (check_quest_owed), and the
    next days run without the human's end turn. A death in the quest respawns the ranger.
    Two runs print the same, and the recording, split into one log per human, replays merged
    (in reverse order) to the recording's hash with no day started before every end turn.
    """
    label = "text quest in a 2-human hot-seat"
    options = [
        "--sim-humans=2", f"--sim-hotseat={QUEST_HOTSEAT_DAYS}",
        f"--sim-text-quest={QUEST_HOTSEAT_QUEST}", "--sim-hash", f"--sim-seed={args.seed}",
    ]  # fmt: skip
    runs = []
    with tempfile.TemporaryDirectory(prefix="rangers-quest-hotseat-") as directory:
        log = Path(directory) / "session.srcl"
        for run in range(2):
            extra = [f"--record-commands={log}"] if run == 0 else []
            code, output = simulate(binary, args.game_dir, save, [*options, *extra])
            done = last_line(output, "done hotseat ")
            if code != 0 or "hotseat barrier ok" not in output or " humans=2 " not in done:
                return False, f"{label} failed:" + output_tail(output)
            runs.append(
                [line for line in output.splitlines() if line.startswith(("quest ", "hotseat ", "done hotseat "))]
            )
        if runs[0] != runs[1]:
            return False, f"{label} nondeterministic: " + first_divergence(runs[0], runs[1])
        problem = check_quest_owed(runs[0])
        if problem:
            return False, f"{label}: {problem}"
        done = [line for line in runs[0] if line.startswith("done hotseat ")][-1]
        expected = done.split("hash=")[-1].split()[0]
        logs = split_commands.split(log, Path(directory) / "humans")
        replay_logs = ",".join(str(path) for path in reversed(logs))
        code, output = run_game(
            binary, args.game_dir, [f"--replay-commands={replay_logs}", f"--sim-seed={args.seed}"]
        )
        summary = last_line(output, "done ")
        if (
            code != 0
            or f"hash={expected}" not in summary
            or " diverged=0 " not in summary
            or " barrier-waits=0 " not in summary
            or " logs=2 " not in summary
        ):
            return False, f"{label}: the per-human replay failed:" + output_tail(output)
    quest = next(line for line in runs[0] if line.startswith("quest done "))
    return True, (
        f"{label}: {quest.removeprefix('quest done ')}; the days owed count down without the "
        "human's end turn, repeat, and replay from one log per human"
    )


def check_quest_lock(args, binary: Path, save: Path) -> tuple[bool, str]:
    """One human at a time plays a planet's text quest (--sim-quest-lock; docs/progress/
    2026-10-19-text-quests-plan.md, Phase B, the lock): two humans hold a quest to one planet;
    while the first plays it the second's BeginTextQuest is refused (in-use), and after the
    first has ended it, again (offer-gone)."""
    code, output = simulate(binary, args.game_dir, save, ["--sim-quest-lock", f"--sim-seed={args.seed}"])
    skipped = last_line(output, "quest lock skipped")
    if code == 0 and skipped:
        return True, skipped
    if code != 0 or "quest lock ok" not in output.splitlines():
        return False, "quest lock failed:" + output_tail(output)
    result = last_line(output, "quest lock outcome=").removeprefix("quest lock ")
    return True, f"one human at a time plays a planet's text quest ({result})"


def drop_end_turns(log: Path) -> None:
    """Removes the EndTurn commands from one human's log, so its human never ends a turn."""
    header, records = split_commands.read_records(log)
    parts = [header]
    for record_type, payload in records:
        if record_type == split_commands.COMMAND and int.from_bytes(payload[:2], "little") == END_TURN_KIND:
            continue
        parts.append(record_type.to_bytes(1, "little") + len(payload).to_bytes(4, "little", signed=True))
        parts.append(payload)
    log.write_bytes(b"".join(parts))


def check_hotseat(args, binary: Path, save: Path, count: int) -> tuple[bool, str]:
    """Hot-seat driven by one command log per human (ROADMAP.md, Phase 4, test plan).

    A headless session (--sim-hotseat) where every human, in Session.Humans order, takes off,
    flies, lands or buys each day and then ends its turn; each day starts only when every human
    has ended it ("hotseat barrier ok"). The recording splits into one log per human
    (tools/split_commands.py), and the replay merges them, given in reverse order, by day and
    Session.Humans order: it must reach the recording's final hash without a divergence or a
    day that started before every end turn. With two humans, a log whose human never ends its
    turn must make the replay report the barrier.
    """
    with tempfile.TemporaryDirectory(prefix="rangers-hotseat-") as directory:
        log = Path(directory) / "session.srcl"
        code, output = simulate(binary, args.game_dir, save, [
            f"--sim-humans={count}", f"--sim-hotseat={HOTSEAT_DAYS}", f"--sim-seed={args.seed}",
            f"--record-commands={log}",
        ])  # fmt: skip
        done = last_line(output, "done hotseat ")
        if code != 0 or "hotseat barrier ok" not in output or f" humans={count} " not in done:
            return False, f"{count} humans hot-seat failed:" + output_tail(output)
        expected = done.split("hash=")[-1].split()[0]
        logs = split_commands.split(log, Path(directory) / "humans")
        if len(logs) != count:
            return False, f"{count} humans hot-seat: {len(logs)} per-human logs"
        replay_logs = ",".join(str(path) for path in reversed(logs))
        code, output = run_game(
            binary, args.game_dir, [f"--replay-commands={replay_logs}", f"--sim-seed={args.seed}"]
        )
        summary = last_line(output, "done ")
        if (
            code != 0
            or f"hash={expected}" not in summary
            or " diverged=0 " not in summary
            or " barrier-waits=0 " not in summary
            or f" logs={count} " not in summary
        ):
            return False, f"{count} humans hot-seat replay failed:" + output_tail(output)
        if count == 2:
            drop_end_turns(logs[-1])
            code, output = run_game(
                binary, args.game_dir, [f"--replay-commands={replay_logs}", f"--sim-seed={args.seed}"]
            )
            if code == 0 or " barrier-waits=0 " in last_line(output, "done ") + " ":
                return False, f"{count} humans hot-seat: a day started without an end turn:" + output_tail(output)
    return True, (
        f"{count} humans hot-seat: {HOTSEAT_DAYS} days, one log per human replays to the same hash"
        + (", a missing end turn holds the day" if count == 2 else "")
    )


def check_respawns(output: str) -> str:
    """The humans killed before a turn respawned: still humans, landed at a planet in the star
    they are filmed in, repaired, with the same money and items. Returns what is wrong."""
    kills = {}
    for line in output.splitlines():
        if line.startswith("kill human "):
            fields = dict(part.split("=", 1) for part in line.split()[2:])
            kills[fields["id"]] = fields
    if len(kills) < 2:
        return "fewer than two humans were killed"
    respawned = 0
    for line in output.splitlines():
        if not line.startswith("respawn human "):
            continue
        fields = dict(part.split("=", 1) for part in line.split()[2:])
        killed = kills.get(fields["id"])
        if killed is None or fields["present"] != "1":
            return f"not respawned: {line}"
        hull, weight = fields["hull"].split("/")
        if fields["planet"] == "0" or fields["star"] != fields["playerstar"] or hull != weight:
            return f"not landed and repaired: {line}"
        if any(fields[key] != killed[key] for key in ("money", "items", "cargo-free")):
            return f"lost belongings: {line}"
        if killed["local"] != "1" and fields["star"] == killed["star"]:
            return f"respawned among hostile planets: {line}"
        respawned += 1
    if respawned != len(kills):
        return f"{len(kills) - respawned} killed humans did not report"
    return ""


class GameProcess:
    """A game process whose output is collected line by line while it runs. One still running
    NET_TIMEOUT seconds after it started has hung: finish kills it and adds a TIMEOUT line,
    naming the command, to its output."""

    def __init__(self, binary: Path, game_dir: Path, options: list[str]):
        self.profile = tempfile.TemporaryDirectory(prefix="rangers-net-")
        self.command = [
            str(binary), f"--game-dir={game_dir}", f"--user-dir={self.profile.name}",
            *GAME_OPTIONS, *options,
        ]  # fmt: skip
        self.started = time.monotonic()
        self.process = subprocess.Popen(
            self.command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, cwd=self.profile.name,
            creationflags=NO_WINDOW,
        )
        self.lines: list[str] = []
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()

    def _read(self) -> None:
        for raw in self.process.stdout:
            self.lines.append(raw.decode("utf-8", "replace").rstrip("\r\n"))

    def wait_line(self, prefix: str, timeout: float) -> str:
        """The first line starting with prefix, waiting up to timeout seconds; '' if none."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for line in list(self.lines):
                if line.startswith(prefix):
                    return line
            if self.process.poll() is not None and not self.reader.is_alive():
                break
            time.sleep(0.05)
        return ""

    def finish(self, timeout: float | None = None) -> int:
        """Waits for the end, up to timeout seconds or what is left of NET_TIMEOUT."""
        if timeout is None:
            timeout = max(0.0, self.started + NET_TIMEOUT - time.monotonic())
        try:
            self.process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
            self.reader.join(timeout=10)
            self.lines.append(timeout_note(time.monotonic() - self.started, self.command))
        self.reader.join(timeout=10)
        self.profile.cleanup()
        return self.process.returncode

    @property
    def output(self) -> str:
        return "\n".join(self.lines)


def fields(line: str) -> dict[str, str]:
    return dict(part.split("=", 1) for part in line.split() if "=" in part)


def net_lines(output: str, prefix: str) -> list[dict[str, str]]:
    return [fields(line) for line in output.splitlines() if line.startswith(prefix)]


def run_network(
    args, binary: Path, save: Path | None, count: int, log: Path | None = None, leave: str = "",
    race: bool = False, nested: bool = False, shop: bool = False, cancel: bool = False,
    quest: str = "", host_quest: str = "", storage: bool = False, shared_quest: bool = False,
    transfer: bool = False,
):
    """One networked session: a host with `count` clients (Net1..NetN) for NET_DAYS days. Without
    a save the host plays a new game (--sim-new-game).

    The host asks remote humans something from day NET_TALK_DAY (--sim-net-talk). With leave
    "day", Net1 leaves after NET_LEAVE_DAY days; with leave "talk", it leaves when the host asks
    it something, without answering. Once the host has run a day without it, Net1 joins again;
    after "day", a join as Net1 that cancels itself once let in comes first (the last client
    output is the real rejoin's, the one before it the cancelled one's). With leave "stop" the
    host stops hosting after NET_STOP_DAY days. With leave "silent" Net1's connection goes silent
    before its turn of day NET_SILENT_DAY and Net1 reconnects in the same process once the host
    must have timed it out; with "takeover" it reconnects at once with its token. With leave
    "host-silent" the host goes silent after NET_SILENT_DAY days and the clients reconnect; with
    "host-exit" it ends then without Bye, and the clients, which try to reconnect for
    NET_GIVE_UP_MS, fail (their exit code is not checked).
    Without leave the talk comes while the clients
    play their films. With race, the clients buy goods whose whole stock they could pay for, and
    the host buys that stock first, once, so that a client's purchase is refused
    (--sim-net-buy-race). With nested, each client submits a command that submits another one
    from inside it (--sim-net-nested). With shop, the clients join at the host's human's planet and
    trade there on their first day (--sim-net-shop), for NET_SHOP_DAYS days. With cancel, each
    client takes its end turn back before the first day, which the host holds for that, and once
    the second day has begun; then its end turns continue the travel, and it stops a continuing
    travel before a day the host holds for that (--sim-net-cancel-end-turn). With quest, each
    client plays a text quest on its NET_QUEST_DAY-th turn (--sim-net-quest): "planet" for the
    planet quest the probe gives it, else the quest of that name (--sim-text-quest); the host
    lands every client at the first one's planet. With host_quest the host's own human plays the
    quest of that name on its NET_QUEST_DAY-th day instead, and the clients play none. With
    storage, the clients join at the host's human's planet and use its shared storage on their
    first day (--sim-net-storage), for NET_SHOP_DAYS days. With shared_quest, the clients join
    there too, Net1 takes a quest on its first day and the host's human fulfils it on its second
    (--sim-net-shared-quest), for NET_SHOP_DAYS days. With transfer, the host's human gives the
    last client money on its first day and Net1 gives Net2 money on its first turn, each also
    trying more than it has (--sim-net-transfer), for NET_SHOP_DAYS days. Returns
    (problem, host output, client outputs); problem is '' when every process ended cleanly.
    """
    days = NET_SHOP_DAYS if shop or storage or shared_quest or transfer else NET_DAYS
    host_options = [
        f"--sim-save={save}" if save is not None else "--sim-new-game", "--sim-net-host=0", f"--sim-net-clients={count}",
        f"--sim-turns={days}", f"--sim-seed={args.seed}", f"--sim-net-talk={NET_TALK_DAY}",
    ]  # fmt: skip
    if not leave:
        host_options.append("--sim-net-talk-after-film")
    elif leave == "stop":
        host_options.append(f"--sim-net-stop-at={NET_STOP_DAY}")
    elif leave == "host-silent":
        host_options.append(f"--sim-net-host-silent-at={NET_SILENT_DAY}")
    elif leave == "host-exit":
        host_options.append(f"--sim-net-host-exit-at={NET_SILENT_DAY}")
    if log is not None:
        host_options.append(f"--record-commands={log}")
    if race:
        host_options.append("--sim-net-buy-race")
    if nested:
        host_options.append("--sim-net-nested")
    if shop:
        host_options.append("--sim-net-shop")
    if storage:
        host_options.append("--sim-net-storage")
    if shared_quest:
        host_options.append("--sim-net-shared-quest")
    if transfer:
        host_options.append("--sim-net-transfer")
    if cancel:
        host_options.append("--sim-net-cancel-end-turn")
    quest_options = []
    if quest:
        quest_options.append(f"--sim-net-quest={NET_QUEST_DAY}")
        if quest != "planet":
            quest_options.append(f"--sim-text-quest={quest}")
    host_options.extend(quest_options[:1])
    if host_quest:
        host_options.extend([f"--sim-net-quest={NET_QUEST_DAY}", f"--sim-text-quest={host_quest}"])
    host = GameProcess(binary, args.game_dir, host_options)
    port_line = host.wait_line("net host port=", NET_TIMEOUT)
    if not port_line:
        host.finish(10)
        return "the host did not listen:" + output_tail(host.output), host.output, []
    port = fields(port_line)["port"]
    clients = []
    for index in range(count):
        options = [f"--sim-net-join=127.0.0.1:{port}", f"--sim-net-name=Net{index + 1}"]
        if leave == "day" and index == 0:
            options.append(f"--sim-net-leave-at={NET_LEAVE_DAY}")
        elif leave == "talk" and index == 0:
            options.append("--sim-net-talk-leave")
        elif leave in ("silent", "takeover") and index == 0:
            options.append(f"--sim-net-silent-at={NET_SILENT_DAY}")
            if leave == "takeover":
                options.append("--sim-net-takeover")
        elif leave == "host-exit":
            options.append(f"--sim-net-reconnect-ms={NET_GIVE_UP_MS}")
        elif not leave:
            options.append(f"--sim-net-film-ms={NET_FILM_MS}")
        if race:
            options.append("--sim-net-buy-race")
        if nested:
            options.append("--sim-net-nested")
        if shop:
            options.append("--sim-net-shop")
        if storage:
            options.append("--sim-net-storage")
        if shared_quest:
            options.append("--sim-net-shared-quest")
        if transfer:
            options.append("--sim-net-transfer")
        if cancel:
            options.append("--sim-net-cancel-end-turn")
        options.extend(quest_options)
        clients.append(GameProcess(binary, args.game_dir, options))
    codes = []
    if leave in ("day", "talk"):
        codes.append(clients[0].finish())
        # The days go on while it is away: wait for a day the host runs without it.
        deadline = time.monotonic() + NET_TIMEOUT
        while time.monotonic() < deadline and host.process.poll() is None and not any(
            line.get("away") == "1" for line in net_lines(host.output, "net host day=")
        ):
            time.sleep(0.05)
        rejoin = [f"--sim-net-join=127.0.0.1:{port}", "--sim-net-name=Net1"]
        if leave == "day":
            # A join cancelled once the host has let it in: the host must take it as a leave
            # before the real rejoin, which gets the human back all the same.
            cancelled = GameProcess(binary, args.game_dir, [*rejoin, "--sim-net-cancel-join"])
            clients.append(cancelled)
            codes.append(cancelled.finish())
            deadline = time.monotonic() + NET_TIMEOUT
            while time.monotonic() < deadline and host.process.poll() is None and host.output.count(
                "(Net1) disconnected"
            ) < 2:
                time.sleep(0.05)
        clients.append(GameProcess(binary, args.game_dir, rejoin))
        codes.extend(client.finish() for client in clients[len(codes):])
    else:
        codes.extend(client.finish() for client in clients)
    host_code = host.finish()
    outputs = [client.output for client in clients]
    if host_code != 0:
        return "the host failed:" + output_tail(host.output), host.output, outputs
    for code, output in zip(codes, outputs):
        if code != 0 and leave != "host-exit":
            return "a client failed:" + output_tail(output), host.output, outputs
    return "", host.output, outputs


def compare_client_hashes(host_output: str, outputs: list[str]) -> str:
    """Every state a client applied has the host's hash. Returns what is wrong."""
    host_hashes = {line["serial"]: line["hash"] for line in net_lines(host_output, "net host day=")}
    for output in outputs:
        for line in net_lines(output, "net client day="):
            expected = host_hashes.get(line["serial"])
            if line["match"] != "1" or (expected is not None and expected != line["hash"]):
                return f"client state {line['serial']} hash {line['hash']} differs from the host's"
    return ""


def check_talks(
    host_output: str, outputs: list[str], held: bool = False
) -> tuple[str, list[dict[str, str]]]:
    """The remote dialogues of a run (--sim-net-talk): the host asked some human, every human
    it asked answered on its client, the host saw the answer (response=1), and every client's
    status named the human asked. With held, each talk came while its client played its film
    and waited for the film's end. Returns what is wrong, and the host's talk lines."""
    talks = net_lines(host_output, "net talk day=")
    if not talks:
        return "the host asked no remote human anything", talks
    answers = [line for output in outputs for line in net_lines(output, "net client talk ")]
    for talk in talks:
        answered = [line for line in answers if line["human"] == talk["human"] and line["answered"] == "1"]
        if not answered:
            return f"human {talk['human']} did not answer the host's talk on its client", talks
        if talk["response"] != "1":
            return f"the host did not see human {talk['human']}'s answer (response {talk['response']})", talks
        if held and not any(line.get("held") == "1" for line in answered):
            return f"human {talk['human']}'s talk did not wait for the end of its film", talks
        # Every client's wait can say whose answer the day waits for (Status).
        for output in outputs:
            if f"net the day waits for human {talk['human']} to answer a hail" not in output:
                return f"a client's status did not name human {talk['human']}'s talk", talks
    return "", talks


def median(values: list[int]) -> int:
    return int(statistics.median(values)) if values else 0


def check_network(args, binary: Path, save: Path, count: int) -> tuple[bool, list[str]]:
    """Networked play over loopback (ROADMAP.md, Phase 5; docs/network.md, Tests).

    A headless host (--sim-net-host) and `count` headless clients (--sim-net-join), each its
    own process: every client's hash equals the host's for every state it applies; two runs
    give the host the same hashes however the commands arrived; the host's command log replays
    to its final hash. From day NET_TALK_DAY the host's day asks remote humans something: each
    answers on its client, the host sees the answer, and the replay of the host's log asks and
    answers the same. With one client, a client that leaves after NET_LEAVE_DAY days gets its
    human back when it joins again, and the days go on while it is away; so does one that
    leaves in the middle of a talk, which ends the talk without hanging the host.
    """
    label = f"{count + 1} humans networked"
    # With one client, the host also refuses a purchase of it (check_refusal).
    race = count == 1
    runs = []
    with tempfile.TemporaryDirectory(prefix="rangers-net-log-") as directory:
        log = Path(directory) / "host.srcl"
        for run in range(2):
            problem, host_output, outputs = run_network(
                args, binary, save, count, log if run == 0 else None, race=race
            )
            if not problem:
                problem = compare_client_hashes(host_output, outputs)
            if not problem:
                problem, _ = check_talks(host_output, outputs, held=True)
            if problem:
                return False, [f"{label}: {problem}"]
            days = [f"{line['serial']} {line['hash']}" for line in net_lines(host_output, "net host day=")]
            if len(days) != NET_DAYS:
                return False, [f"{label}: the host ran {len(days)} days"]
            runs.append((days, host_output, outputs))
        if runs[0][0] != runs[1][0]:
            return False, [f"{label} nondeterministic: " + first_divergence(runs[0][0], runs[1][0])]
        expected = fields(last_line(runs[0][1], "done net host "))["hash"]
        code, output = run_game(
            binary,
            args.game_dir,
            [f"--replay-commands={log}", f"--sim-seed={args.seed}", f"--sim-net-talk={NET_TALK_DAY}"],
        )
        summary = last_line(output, "done ")
        if code != 0 or f"hash={expected}" not in summary or " diverged=0 " not in summary:
            return False, [f"{label}: the host's command log does not replay:" + output_tail(output)]
        host_talks = [line for line in runs[0][1].splitlines() if line.startswith("net talk day=")]
        replay_talks = [line for line in output.splitlines() if line.startswith("net talk day=")]
        if replay_talks != host_talks:
            return False, [
                f"{label}: the replay's talks differ from the host's: {replay_talks} != {host_talks}"
            ]
        refusal_note = ""
        if race:
            problem, refusal_note = check_refusal(runs[0][1], runs[0][2], log)
            if problem:
                return False, [f"{label}: {problem}"]
    _, host_output, outputs = runs[0]
    host_days = net_lines(host_output, "net host day=")
    client_days = [line for output in outputs for line in net_lines(output, "net client day=")]
    _, talks = check_talks(host_output, outputs)
    notes = [
        f"{label}: {NET_DAYS} days, client hashes match the host's, deterministic, "
        "the host's log replays",
        f"{label}: {len(talks)} remote talks on day {talks[0]['day']}, each during its client's "
        "film and answered at the film's end, named in every client's status, seen by the host "
        "and by the replay",
        "  sizes: whole state {} bytes, {} compressed; median delta {}; median films of a day {} "
        "({} raw); median load {} ms (client), take {} ms (host)".format(
            host_days[-1]["state"], host_days[-1]["whole"],
            median([int(line["delta"]) for line in host_days if int(line["delta"]) > 0]),
            median([int(line["film"]) for line in host_days if int(line["film"]) > 0]),
            median([int(line["filmraw"]) for line in host_days if int(line["filmraw"]) > 0]),
            median([int(line["load"]) for line in client_days]),
            median([int(line["take"]) for line in host_days]),
        ),
    ]  # fmt: skip
    if refusal_note:
        notes.append(f"{label}: {refusal_note}")
    if count == 1:
        problem, host_output, outputs = run_network(args, binary, save, count, leave="day")
        if not problem:
            problem = compare_client_hashes(host_output, outputs)
        if problem:
            return False, [*notes, f"{label} leave and rejoin: {problem}"]
        left = [line for line in outputs[0].splitlines() if line.startswith("net client left ")]
        first = fields(last_line(outputs[0], "done net client "))
        second = fields(last_line(outputs[-1], "done net client "))
        away = [line for line in net_lines(host_output, "net host day=") if line["away"] == "1"]
        cancelled = net_lines(outputs[1], "net client join cancelled ")
        if not cancelled or "done net client cancelled" not in outputs[1]:
            return False, [*notes, f"{label}: the join did not cancel:" + output_tail(outputs[1])]
        if cancelled[0]["human"] != first.get("human") or host_output.count("(Net1) rejoined") < 2:
            return False, [*notes, f"{label}: the cancelled join was not let in as human {first.get('human')}"]
        if not left or first.get("human") in (None, "-1") or first.get("human") != second.get("human"):
            return False, [
                *notes,
                f"{label}: the rejoined client got human {second.get('human')}, not {first.get('human')}",
            ]
        if not away:
            return False, [*notes, f"{label}: no day ran while the client was away"]
        notes.append(
            f"{label}: a client that leaves after day {NET_LEAVE_DAY} gets human {first['human']} "
            f"back; {len(away)} days ran without it; a join cancelled once let in, before its state "
            f"was applied ({cancelled[0]['have']} of {cancelled[0]['size']} bytes had come), left "
            "the host as a leave"
        )
        problem, host_output, outputs = run_network(args, binary, save, count, leave="talk")
        if not problem:
            problem = compare_client_hashes(host_output, outputs)
        if problem:
            return False, [*notes, f"{label} leave in a talk: {problem}"]
        left = [line for line in outputs[0].splitlines() if line.startswith("net client left in a talk ")]
        ended = [line for line in host_output.splitlines() if " ended: " in line and "net talk with human" in line]
        first = fields(last_line(outputs[0], "done net client "))
        second = fields(last_line(outputs[1], "done net client "))
        if not left:
            return False, [*notes, f"{label} leave in a talk: the host asked the client nothing"]
        if not ended or not any(word in ended[-1] for word in (" left,", " disconnected,")):
            return False, [*notes, f"{label} leave in a talk: the host's talk did not end: {ended}"]
        if first.get("human") in (None, "-1") or first.get("human") != second.get("human"):
            return False, [
                *notes,
                f"{label} leave in a talk: the rejoined client got human {second.get('human')}, "
                f"not {first.get('human')}",
            ]
        notes.append(f"{label}: a client that leaves in a talk ends it ({ended[-1].split(' ended: ')[1]}); "
                     "the day goes on and the client gets its human back")
        problem, host_output, outputs = run_network(args, binary, save, count, leave="stop")
        if not problem:
            problem = compare_client_hashes(host_output, outputs)
        if problem:
            return False, [*notes, f"{label} stop hosting: {problem}"]
        stopped = net_lines(host_output, "net host stopped hosting ")
        noticed = net_lines(outputs[0], "net client host left ")
        if not stopped or "(Net1) disconnected" not in host_output:
            return False, [*notes, f"{label} stop hosting: the host did not disconnect its client"]
        if not noticed or noticed[0].get("bye") != "1":
            return False, [*notes, f"{label} stop hosting: the client did not notice:" + output_tail(outputs[0])]
        delay = int(noticed[0]["tick"]) - int(stopped[0]["tick"])
        if delay > NET_NOTICE_MS:
            return False, [*notes, f"{label} stop hosting: the client noticed after {delay} ms"]
        notes.append(
            f"{label}: a host that stops hosting after day {NET_STOP_DAY} disconnects its client, "
            f"which notices it by itself within {max(delay, 0)} ms"
        )
        problem, note = check_silence(args, binary, save, count)
        if problem:
            return False, [*notes, f"{label} silent client: {problem}"]
        notes.append(f"{label}: {note}")
        problem, note = check_takeover(args, binary, save, count)
        if problem:
            return False, [*notes, f"{label} takeover: {problem}"]
        notes.append(f"{label}: {note}")
        problem, note = check_host_silence(args, binary, save, count)
        if problem:
            return False, [*notes, f"{label} silent host: {problem}"]
        notes.append(f"{label}: {note}")
        problem, note = check_reconnect_gives_up(args, binary, save, count)
        if problem:
            return False, [*notes, f"{label} vanished host: {problem}"]
        notes.append(f"{label}: {note}")
    return True, notes


def tick_lines(output: str, text: str) -> list[dict[str, str]]:
    """The lines of a run that contain text, with their fields (tick= among them)."""
    return [fields(line) for line in output.splitlines() if text in line]


def states_after(output: str, prefix: str) -> list[dict[str, str]]:
    """The states a client applied after its first line that starts with prefix."""
    lines = output.splitlines()
    went = next((i for i, line in enumerate(lines) if line.startswith(prefix)), len(lines))
    return [fields(line) for line in lines[went:] if line.startswith("net client day=")]


def replay_host_log(args, binary: Path, log: Path, expected: str, extra: list[str]) -> str:
    """Replays the host's command log, with its talk probe (--sim-net-talk) and the extra options;
    returns what is wrong ('' when it reaches expected)."""
    options = [f"--replay-commands={log}", f"--sim-seed={args.seed}", f"--sim-net-talk={NET_TALK_DAY}", *extra]
    code, output = run_game(binary, args.game_dir, options)
    summary = last_line(output, "done ")
    if code != 0 or f"hash={expected}" not in summary or " diverged=0 " not in summary:
        return "the host's command log does not replay:" + output_tail(output)
    return ""


def quest_pages(output: str, what: str, human: str) -> list[tuple[str, str, str, str]]:
    """The text-quest pages of human that a process logged as what (sent, relayed, received,
    abandoned; NetLogQuestPage), in order: (run, page, hash, end)."""
    return [
        (line["run"], line["page"], line["hash"], line["end"])
        for line in net_lines(output, f"net quest page {what} ")
        if line.get("human") == human
    ]  # fmt: skip


def check_page_relay(sent: list, others: list[tuple[str, list]], name: str) -> str:
    """The pages a player sent (sent) reached every other machine (others: label and the pages
    it logged) the same, in the same order, and the run has its end page. Returns what is wrong."""
    if not sent:
        return f"{name} sent no text-quest page"
    if sent[-1][3] == "none":
        return f"{name} sent no end page: {sent[-1]}"
    for label, pages in others:
        if pages != sent:
            return f"{label} got {name}'s pages {pages[:3]}..., not as sent {sent[:3]}... ({len(pages)} of {len(sent)})"
    return ""


def check_pages_kept(output: str, side: str, human: str, last: tuple) -> str:
    """The process kept last as human's latest page (net SIDE quest pages)."""
    kept = [line for line in net_lines(output, f"net {side} quest pages ") if line.get("human") == human]
    if not kept or (kept[0]["run"], kept[0]["count"], kept[0]["last"], kept[0]["end"]) != last:
        return f"the {side} kept {kept}, not the page {last}"
    return ""


# The line of a wait for the day that offers the watch window (NetPlay.QuestWatchLine; Phase E).
WATCH_HINT = "W: watch "


def check_net_quest_lock(args, binary: Path, save: Path) -> tuple[str, str]:
    """Two clients at one planet, each with a quest to it (--sim-net-quest): Net1 plays the
    planet's text quest headless before its end turn; the host ran its BeginTextQuest as it came
    and its status said so (activity=1), and the host's barrier applied the quest's commands
    (none before it); the host's wait for its peers named Net1's text quest, and so did Net2's
    wait from the status, and both offered to watch it (W, Phase E); the relay of Net1's
    BeginTextQuest told Net2 who plays the planet's quest, and the host refused Net2's own
    (in-use). Every state's hash is the host's, and the
    host's log replays. Every page of Net1's quest reaches the host and Net2 as Net1 sent it, in
    order, with the end page (Phase D), and both keep its last page. Returns what is wrong, and
    a note."""
    with tempfile.TemporaryDirectory(prefix="rangers-net-quest-") as directory:
        log = Path(directory) / "host.srcl"
        problem, host_output, outputs = run_network(args, binary, save, 2, log, quest="planet")
        if not problem:
            problem = compare_client_hashes(host_output, outputs)
        if problem:
            return problem, ""
        days = net_lines(host_output, "net host day=")
        if len(days) != NET_DAYS:
            return f"the host ran {len(days)} days", ""
        opened = net_lines(outputs[0], "net client quest open ")
        if opened and opened[0]["quest"] == "-1":
            return "", "no planet quest in the save's galaxy: the networked quest was not played"
        expected = fields(last_line(host_output, "done net host "))["hash"]
        problem = replay_host_log(args, binary, log, expected, [f"--sim-net-quest={NET_QUEST_DAY}"])
        if problem:
            return problem, ""
    net1, net2 = outputs
    opened = net_lines(net1, "net client quest open ")
    status = net_lines(net1, "net client quest status ")
    done = net_lines(net1, "net client quest done ")
    if not opened or opened[0]["opened"] != "1" or not done:
        return "Net1 did not play its quest:" + output_tail(net1), ""
    human1 = opened[0]["human"]
    if not status or status[0]["activity"] != "1":
        return f"the host's status did not say that Net1 plays a text quest: {status}", ""
    quest = fields(last_line(host_output, "net host quest begun="))
    if quest.get("begun") != "1" or int(quest.get("barrier", "0")) < 2 or quest.get("closed") != "1":
        return f"the host's barrier did not apply Net1's quest: {quest}", ""
    if quest.get("early") != "0":
        return f"the host applied quest commands before its barrier: {quest}", ""
    waits = [line for line in host_output.splitlines() if line.startswith("net host wait ")]
    if not any("(text quest)" in line for line in waits):
        return f"the host's wait did not name Net1's text quest: {waits}", ""
    if not any(WATCH_HINT in line for line in waits):
        return f"the host's wait did not offer to watch Net1's text quest: {waits}", ""
    holder = net_lines(net2, "net client quest holder ")
    if not holder or holder[0]["human"] != human1 or holder[0]["status"] != human1:
        return f"Net2 did not see that Net1 plays the planet's quest: {holder}", ""
    tried = net_lines(net2, "net client quest open ")
    if not tried or tried[0]["opened"] != "0" or tried[0]["refused"] != "1":
        return "Net2's quest was not refused:" + output_tail(net2), ""
    refused = [line for line in net_lines(net2, "net client refused ") if line["kind"] == "BeginTextQuest"]
    if not refused or refused[0]["reason"] != NET_QUEST_REFUSAL:
        return f"the host did not refuse Net2's BeginTextQuest {NET_QUEST_REFUSAL}: {refused}", ""
    waited = [line for line in net2.splitlines() if line.startswith("net client wait ")]
    if not any("(text quest)" in line for line in waited):
        return f"Net2's wait did not name Net1's text quest: {waited}", ""
    if not any(WATCH_HINT in line for line in waited):
        return f"Net2's wait did not offer to watch Net1's text quest: {waited}", ""
    sent = quest_pages(net1, "sent", human1)
    problem = check_page_relay(
        sent,
        [("the host", quest_pages(host_output, "relayed", human1)), ("Net2", quest_pages(net2, "received", human1))],
        "Net1",
    )
    if not problem and net_lines(net2, "net quest page sent "):
        problem = "Net2 sent pages of a quest that was refused"
    for output, side in ((host_output, "host"), (net2, "client")):
        problem = problem or check_pages_kept(output, side, human1, sent[-1])
    if problem:
        return problem, ""
    return "", (
        f"a client plays a text quest headless ({done[0]['outcome']} in {done[0]['steps']} choices); "
        f"the host's barrier applies its {quest['barrier']} quest commands with the client's hashes, "
        "its wait and the other client's name it and offer to watch it, and the other client's BeginTextQuest for the "
        f"planet is refused {NET_QUEST_REFUSAL}; the host's log replays; its {len(sent)} pages "
        f"(end {sent[-1][3]}) reach the host and the other client in order with the same hashes"
    )


def check_net_quest_days(args, binary: Path, save: Path) -> tuple[str, str]:
    """One client plays QUEST_HOTSEAT_QUEST by name on its first turn (--sim-net-quest with
    --sim-text-quest): the quest runs no galaxy day and owes its days. The quest's day ends with
    the client's EndTurn, which the host's day waits for; afterwards each state owes one day
    less, the host runs its days without waiting for the client, and its wait and status say the
    client is busy with a text quest. Hashes match and the host's log replays. Returns what is
    wrong, and a note."""
    with tempfile.TemporaryDirectory(prefix="rangers-net-quest-days-") as directory:
        log = Path(directory) / "host.srcl"
        problem, host_output, outputs = run_network(args, binary, save, 1, log, quest=QUEST_HOTSEAT_QUEST)
        if not problem:
            problem = compare_client_hashes(host_output, outputs)
        if problem:
            return problem, ""
        if len(net_lines(host_output, "net host day=")) != NET_DAYS:
            return "the host did not run its days", ""
        expected = fields(last_line(host_output, "done net host "))["hash"]
        problem = replay_host_log(args, binary, log, expected, [f"--sim-net-quest={NET_QUEST_DAY}"])
        if problem:
            return problem, ""
    net1 = outputs[0]
    done = net_lines(net1, "net client quest done ")
    if not done:
        return "the client did not play its quest:" + output_tail(net1), ""
    quest_days = int(done[0]["days"])
    lines = net1.splitlines()
    after = next(i for i, line in enumerate(lines) if line.startswith("net client quest done "))
    owed = [int(fields(line)["quest-days"]) for line in lines[after:] if line.startswith("net client day=")]
    if quest_days == 0:
        if owed and owed[0] != 0:
            return f"a quest of no days owes {owed[0]}", ""
        return "", f"a client's {QUEST_HOTSEAT_QUEST} quest passed no days (nothing owed)"
    expected_owed = [max(quest_days - 1 - i, 0) for i in range(len(owed))]
    if owed != expected_owed:
        return f"the days owed went {owed}, not {expected_owed}", ""
    busy = [
        line for line in host_output.splitlines()
        if line.startswith("net host wait ") and "busy with a text quest" in line
    ]  # fmt: skip
    if not busy:
        return "the host's wait did not say the client is busy with a text quest", ""
    if " activity=2 " not in net1:
        return "the client's status never said it owes days for a quest", ""
    return "", (
        f"a client's {QUEST_HOTSEAT_QUEST} quest by name ({done[0]['outcome']}, respawned="
        f"{done[0]['respawned']}) owes {quest_days} days: its states count them down ({len(owed)} "
        "states), the host runs the days without it and its wait says the client is busy; hashes "
        "match, the log replays"
    )


def check_net_quest_abandon(args, binary: Path, save: Path) -> tuple[str, str]:
    """One client goes silent in the middle of its planet quest (--sim-net-quest with
    --sim-net-silent-at): the host times it out, drops its queue and releases its lock, and its
    barrier never applies the quest's commands; the client reconnects, abandons the quest without
    CloseQuest, gets its human back, and the planet's quest is still there for it. Returns what
    is wrong, and a note."""
    problem, host_output, outputs = run_network(args, binary, save, 1, leave="silent", quest="planet")
    if not problem:
        problem = compare_client_hashes(host_output, outputs)
    if problem:
        return problem, ""
    net1 = outputs[0]
    opened = net_lines(net1, "net client quest open ")
    if opened and opened[0]["quest"] == "-1":
        return "", "no planet quest in the save's galaxy: the abandoned quest was not played"
    abandoned = net_lines(net1, "net client quest abandoned ")
    if not abandoned:
        return "the client did not abandon its quest:" + output_tail(net1), ""
    if "(Net1) abandoned its text quest" not in host_output:
        return "the host did not release the client's lock:" + output_tail(host_output), ""
    # The pages: the host got some of what Net1 sent before it went silent, and ended the quest
    # for its watchers; Net1 sent no end page of its own (the reconnect drops it).
    human = abandoned[0]["human"]
    sent = quest_pages(net1, "sent", human)
    relayed = quest_pages(host_output, "relayed", human)
    ended = quest_pages(host_output, "abandoned", human)
    if not relayed or relayed != sent[: len(relayed)]:
        return f"the host got Net1's pages {relayed}, not a start of {sent}", ""
    if any(page[3] != "none" for page in sent):
        return f"Net1 sent an end page of the quest it abandoned: {sent}", ""
    last = relayed[-1]
    if len(ended) != 1 or ended[0][:2] != (last[0], str(int(last[1]) + 1)) or ended[0][3] != "abandoned":
        return f"the host's abandoned end page {ended} does not follow {last}", ""
    problem = check_pages_kept(host_output, "host", human, ended[0])
    if problem:
        return problem, ""
    quest = fields(last_line(host_output, "net host quest begun="))
    if quest.get("begun") != "1" or quest.get("barrier") != "0" or quest.get("early") != "0":
        return f"the host applied the abandoned quest's commands: {quest}", ""
    after = net_lines(net1, "net client quest after rejoin ")
    if not after or after[0].get("rejoin") != "1" or after[0].get("quest") == "-1" or after[0].get("holds") != "1":
        return f"the quest is not there after the reconnect: {after}", ""
    if after[0].get("open") != "0" or after[0].get("holder") != "0":
        return f"a lock is left after the reconnect: {after}", ""
    problem, _ = check_reconnected(net1, abandoned[0]["human"], "net client quest abandoned ", False)
    if problem:
        return problem, ""
    return "", (
        f"a client that goes silent in its text quest (after {abandoned[0]['steps']} choice) is timed "
        "out, the host releases its lock and drops the quest's commands; it reconnects, abandons "
        f"the quest and gets its human back with the planet's quest {after[0]['quest']} still there; "
        f"the host ends the quest's pages with an abandoned one after the {len(relayed)} it got"
    )


def check_net_quest_host(args, binary: Path, save: Path) -> tuple[str, str]:
    """The host's own human plays QUEST_HOTSEAT_QUEST by name on its first day, two clients
    watching (--sim-net-quest with --sim-text-quest on the host): every page reaches both clients
    as the host sent it, in order, with the end page, and both keep its last page. The pages
    change nothing: every state's hash is the host's and the host's log replays. Returns what is
    wrong, and a note (docs/progress/2026-10-19-text-quests-plan.md, Phase D)."""
    with tempfile.TemporaryDirectory(prefix="rangers-net-quest-host-") as directory:
        log = Path(directory) / "host.srcl"
        problem, host_output, outputs = run_network(args, binary, save, 2, log, host_quest=QUEST_HOTSEAT_QUEST)
        if not problem:
            problem = compare_client_hashes(host_output, outputs)
        if problem:
            return problem, ""
        if len(net_lines(host_output, "net host day=")) != NET_DAYS:
            return "the host did not run its days", ""
        expected = fields(last_line(host_output, "done net host "))["hash"]
        problem = replay_host_log(args, binary, log, expected, [f"--sim-net-quest={NET_QUEST_DAY}"])
        if problem:
            return problem, ""
    done = fields(last_line(host_output, "quest done "))
    human = fields(last_line(host_output, "net host quest begun=")).get("host", "")
    if not done or not human:
        return "the host did not play its quest:" + output_tail(host_output), ""
    sent = quest_pages(host_output, "sent", human)
    problem = check_page_relay(
        sent,
        [(f"Net{index + 1}", quest_pages(output, "received", human)) for index, output in enumerate(outputs)],
        "the host",
    )
    for output in outputs:
        problem = problem or check_pages_kept(output, "client", human, sent[-1])
    if problem:
        return problem, ""
    return "", (
        f"the host plays {QUEST_HOTSEAT_QUEST} ({done['outcome']} in {done['steps']} choices): its "
        f"{len(sent)} pages reach both clients in order with the same hashes; hashes match, the log replays"
    )


def check_network_quests(args, binary: Path, save: Path) -> tuple[bool, list[str]]:
    """Text quests in a networked session (docs/progress/2026-10-19-text-quests-plan.md, Phases C
    and D): check_net_quest_lock, check_net_quest_days, check_net_quest_abandon,
    check_net_quest_host."""
    notes = []
    for label, check in (
        ("text quest, 3 humans networked", check_net_quest_lock),
        ("text quest days, 2 humans networked", check_net_quest_days),
        ("abandoned text quest, 2 humans networked", check_net_quest_abandon),
        ("host's text quest watched, 3 humans networked", check_net_quest_host),
    ):
        problem, note = check(args, binary, save)
        if problem:
            return False, [*notes, f"{label}: {problem}"]
        notes.append(f"{label}: {note}")
    return True, notes


def check_reconnected(
    output: str, human: str | None, after: str, play_on: bool = True
) -> tuple[str, list[dict[str, str]]]:
    """The client reconnected in place (TNetClient's reconnect) after its first line that starts
    with after: it was welcomed as the same human, applied a whole state marked rejoin=1, with
    play_on played on with at least one more state, and ended as that human. Returns what is
    wrong, and the states it applied after the line."""
    reconnected = tick_lines(output, "net client reconnected ")
    states = states_after(output, after)
    done = fields(last_line(output, "done net client "))
    if not reconnected:
        return "the client did not reconnect:" + output_tail(output), states
    if human in (None, "-1") or reconnected[0].get("human") != human or done.get("human") != human:
        return f"the client reconnected as human {reconnected[0].get('human')}, not {human}", states
    rejoins = [i for i, line in enumerate(states) if line.get("rejoin") == "1"]
    if not rejoins or (play_on and rejoins[0] + 1 >= len(states)):
        return f"the client did not play on after the reconnect: {len(states)} states", states
    return "", states


def check_silence(args, binary: Path, save: Path, count: int) -> tuple[str, str]:
    """A client whose connection goes silent before its turn of day NET_SILENT_DAY
    (--sim-net-silent-at): its socket stays open, it reads and writes nothing. The host must time
    it out after NET_SILENCE_MS ("no answer for"), disconnect its human and run the days without
    it; the client then drops the frozen connection and reconnects by itself, in the same
    process, with its token: a rejoin, since the host has let the human go. It must get its
    human back and play on with the host's hashes. Returns what is wrong, and a note."""
    problem, host_output, outputs = run_network(args, binary, save, count, leave="silent")
    if not problem:
        problem = compare_client_hashes(host_output, outputs)
    if problem:
        return problem, ""
    silent = net_lines(outputs[0], "net client silent ")
    lost = tick_lines(host_output, "(Net1) lost: no answer for ")
    gone = tick_lines(host_output, "(Net1) disconnected")
    if not silent or silent[0].get("takeover") != "0":
        return "the client did not go silent:" + output_tail(outputs[0]), ""
    if not lost or not gone:
        return "the host did not time the client out:" + output_tail(host_output), ""
    delay = int(gone[0]["tick"]) - int(silent[0]["tick"])
    if not NET_SILENCE_MS - NET_PING_MS - 500 <= delay <= NET_SILENCE_MS + 3000:
        return f"the host disconnected the silent client after {delay} ms", ""
    away = [line for line in net_lines(host_output, "net host day=") if line["away"] == "1"]
    if not away:
        return "no day ran while the client was silent", ""
    if len(outputs) != 1:
        return f"{len(outputs)} client processes, not one", ""
    if "(Net1) taken over " in host_output or "(Net1) rejoined" not in host_output:
        return "the host did not take the reconnect as a rejoin:" + output_tail(host_output), ""
    # The host runs the days without the human quickly, so it may have run them all by the time
    # the client is back; the other reconnect runs check that a client plays on.
    problem, states = check_reconnected(outputs[0], silent[0].get("human"), "net client silent ", False)
    if problem:
        return problem, ""
    reconnected = tick_lines(outputs[0], "net client reconnected ")
    return "", (
        f"a client whose connection goes silent before day {NET_SILENT_DAY} is timed out and "
        f"disconnected after {delay} ms; {len(away)} days ran without it; it drops the connection, "
        f"reconnects by itself in {reconnected[0]['after']} ms ({reconnected[0]['tries']} tries), "
        f"gets its human back as a rejoin ({len(states)} states with the host's hashes after it)"
    )


def check_takeover(args, binary: Path, save: Path, count: int) -> tuple[str, str]:
    """A client whose connection goes silent before its turn of day NET_SILENT_DAY and that
    reconnects at once, in place, as the same name with its token, while the frozen connection
    stays open (--sim-net-takeover): the host must take the human over from the silent
    connection within NET_TAKEOVER_MS, well before any timeout, send it a whole state, and the
    client must play on with the host's hashes. Returns what is wrong, and a note."""
    problem, host_output, outputs = run_network(args, binary, save, count, leave="takeover")
    if not problem:
        problem = compare_client_hashes(host_output, outputs)
    if problem:
        return problem, ""
    silent = net_lines(outputs[0], "net client silent ")
    taken = tick_lines(host_output, "(Net1) taken over by a new connection")
    if not silent or silent[0].get("takeover") != "1":
        return "the client did not go silent:" + output_tail(outputs[0]), ""
    if not taken:
        return "the host did not take the human over:" + output_tail(host_output), ""
    delay = int(taken[0]["tick"]) - int(silent[0]["tick"])
    if delay > NET_TAKEOVER_MS:
        return f"the host took the human over after {delay} ms", ""
    if "(Net1) lost: no answer for " in host_output:
        return "the host timed the old connection out", ""
    lines = host_output.splitlines()
    over = next(i for i, line in enumerate(lines) if "(Net1) taken over " in line)
    if not any("(Net1) rejoined" in line for line in lines[over:]):
        return "the new connection did not rejoin", ""
    problem, states = check_reconnected(outputs[0], silent[0].get("human"), "net client silent ")
    if problem:
        return problem, ""
    reconnected = tick_lines(outputs[0], "net client reconnected ")
    return "", (
        f"a client that reconnects in place with its token after its connection went silent is "
        f"taken over in {max(delay, 0)} ms (welcomed after {reconnected[0]['after']} ms) and plays "
        f"on ({len(states)} states with the host's hashes)"
    )


def check_host_silence(args, binary: Path, save: Path, count: int) -> tuple[str, str]:
    """A host that goes silent after NET_SILENT_DAY days (--sim-net-host-silent-at): it freezes
    every peer, so its clients hear nothing. The client must notice within NET_SILENCE_MS (less
    the host's ping interval), reconnect with its token (the host still counts the frozen
    connection, so it takes the human over), get its human back and play on with the host's
    hashes. Returns what is wrong, and a note."""
    problem, host_output, outputs = run_network(args, binary, save, count, leave="host-silent")
    if not problem:
        problem = compare_client_hashes(host_output, outputs)
    if problem:
        return problem, ""
    silent = tick_lines(host_output, "net host silent ")
    if not silent or silent[0].get("exit") != "0":
        return "the host did not go silent:" + output_tail(host_output), ""
    lost = tick_lines(outputs[0], "net client lost the host")
    if not lost or "no answer for" not in last_line(outputs[0], "net client lost the host"):
        return "the client did not time the host out:" + output_tail(outputs[0]), ""
    delay = int(lost[0]["tick"]) - int(silent[0]["tick"])
    if not NET_SILENCE_MS - NET_PING_MS - 500 <= delay <= NET_SILENCE_MS + 3000:
        return f"the client noticed the silent host after {delay} ms", ""
    if "(Net1) taken over " not in host_output and "(Net1) rejoined" not in host_output:
        return "the host did not take the reconnect:" + output_tail(host_output), ""
    days = net_lines(host_output, "net host day=")
    if len(days) != NET_DAYS:
        return f"the host ran {len(days)} days", ""
    human = fields(last_line(outputs[0], "net client day=")).get("human")
    problem, states = check_reconnected(outputs[0], human, "net client lost the host")
    if problem:
        return problem, ""
    reconnected = tick_lines(outputs[0], "net client reconnected ")
    how = "taken over" if "(Net1) taken over " in host_output else "rejoined"
    return "", (
        f"a host that goes silent after day {NET_SILENT_DAY} is timed out by its client after "
        f"{delay} ms; the client reconnects in {reconnected[0]['after']} ms "
        f"({reconnected[0]['tries']} tries, {how}), gets human {human} back and plays on "
        f"({len(states)} states with the host's hashes)"
    )


def check_reconnect_gives_up(args, binary: Path, save: Path, count: int) -> tuple[str, str]:
    """A host that ends after NET_SILENT_DAY days without Bye (--sim-net-host-exit-at): its
    clients see the connection close, try to reconnect for NET_GIVE_UP_MS
    (--sim-net-reconnect-ms) and give up, ending as host lost with the reason. Returns what is
    wrong, and a note."""
    problem, host_output, outputs = run_network(args, binary, save, count, leave="host-exit")
    if not problem:
        problem = compare_client_hashes(host_output, outputs)
    if problem:
        return problem, ""
    gone = tick_lines(host_output, "net host silent ")
    if not gone or gone[0].get("exit") != "1" or "done net host exited " not in host_output:
        return "the host did not vanish:" + output_tail(host_output), ""
    lost = tick_lines(outputs[0], "net client lost the host")
    tries = tick_lines(outputs[0], "net client reconnect try=")
    failed = tick_lines(outputs[0], "net client reconnect failed after=")
    if not lost:
        return "the client did not notice the host was gone:" + output_tail(outputs[0]), ""
    if not failed or not tries:
        return "the client did not give up reconnecting:" + output_tail(outputs[0]), ""
    if "net client reconnected " in outputs[0]:
        return "the client reconnected to a host that is gone", ""
    if "net client failed: could not reconnect within " not in outputs[0]:
        return "the client did not end as host lost:" + output_tail(outputs[0]), ""
    notice = int(lost[0]["tick"]) - int(gone[0]["tick"])
    window = int(failed[0]["tick"]) - int(lost[0]["tick"])
    if not NET_GIVE_UP_MS <= window <= NET_GIVE_UP_MS + NET_TRY_MS + 1000:
        return f"the client gave up {window} ms after it lost the host", ""
    attempts = len({line["try"] for line in tries})
    return "", (
        f"a host that vanishes after day {NET_SILENT_DAY} is noticed by its client in "
        f"{max(notice, 0)} ms; the client tries to reconnect {attempts} times and gives up "
        f"{window} ms after the loss (window {NET_GIVE_UP_MS} ms), ending as host lost"
    )


def check_refusal(host_output: str, outputs: list[str], log: Path | None) -> tuple[str, str]:
    """A run with --sim-net-buy-race: the host bought the goods of a client's queued purchase
    first, so the purchase failed on the host without blocking its day; the host's command log,
    when there is one, does not record it (it records as many purchases of remote humans as the
    host applied); and the client got the refusal with the reason out-of-stock and showed it as a
    bubble, again after the next state. Returns what is wrong, and a note."""
    bought = net_lines(host_output, "net host buys first ")
    if not bought:
        return "the host never bought a client's goods first", ""
    first = bought[0]
    failed = [
        line for line in net_lines(host_output, "net command failed ")
        if line["human"] == first["human"] and line["seq"] == first["seq"]
    ]
    if not failed or failed[0]["kind"] != "TradeGoods" or not failed[0]["reason"].startswith(OUT_OF_STOCK):
        return f"the host did not refuse human {first['human']}'s purchase {first['seq']}: {failed}", ""
    refused = [
        line for output in outputs for line in net_lines(output, "net client refused ")
        if line["human"] == first["human"] and line["seq"] == first["seq"]
    ]
    if not refused or refused[0]["reason"] != OUT_OF_STOCK or refused[0]["kind"] != "TradeGoods":
        return f"the client did not get the refusal of purchase {first['seq']}: {refused}", ""
    if refused[0]["bubble"] != "1":
        return "the client did not show the refusal as a bubble", ""
    # A trade is refused while the client waits for it, not at the barrier.
    answered = [
        line for output in outputs for line in net_lines(output, "net trade answered ")
        if line["seq"] == first["seq"] and line["kind"] == "TradeGoods"
    ]
    if not answered or answered[0]["ok"] != "0" or answered[0]["reason"] != OUT_OF_STOCK:
        return f"the client did not get the refusal of purchase {first['seq']} while it waited: {answered}", ""
    again = [line for output in outputs for line in net_lines(output, "net client refusal after state ")]
    if not again or again[0]["bubble"] != "1":
        return "the client did not show the refusal again after the next state", ""
    note = (
        f"a client's purchase of goods the host bought first (good {first['good']}) is refused "
        f"({OUT_OF_STOCK}) while the client waits for it ({answered[0]['ms']} ms) and shown as a bubble"
    )
    if log is None:
        return "", note
    trades = net_lines(host_output, "net host trades ")
    if not trades:
        return "the host did not count the purchases it applied", ""
    _, records = split_commands.read_records(log)
    logged = 0
    for record_type, payload in records:
        if record_type == split_commands.COMMAND:
            kind, actor = struct.unpack_from("<HI", payload, 0)
            if kind == TRADE_GOODS_KIND and str(actor) != trades[0]["host"]:
                logged += 1
    if logged != int(trades[0]["remote"]):
        return (
            f"the command log records {logged} purchases of remote humans, the host applied "
            f"{trades[0]['remote']}"
        ), ""
    return "", f"{note}; the log has the {logged} purchases of remote humans the host applied, not it"


def check_new_game_network(args, binary: Path) -> tuple[bool, list[str]]:
    """A host that starts a new game instead of loading a save (--sim-new-game) and one client:
    every state the client applies has the host's hash. A new game's galaxy is not one that a
    load gave, so this checks that a load gives back what a new game saves (the outline of the
    hidden constellation, for one). The run also has the host refuse a client's purchase
    (--sim-net-buy-race, check_refusal), and the client submit a command that submits another
    from inside it, which the host must run once (--sim-net-nested), and a session flag, which
    only the host sets: the host refuses it, and its flag stays. The client also takes its end
    turn back before the first day and ends it again, and tries once the second day has begun,
    which the host refuses (check_cancel_end_turn)."""
    label = "new game, 2 humans networked"
    # A new game loads no save, so its commands are not recorded (the log starts at a load).
    problem, host_output, outputs = run_network(args, binary, None, 1, race=True, nested=True, cancel=True)
    if not problem:
        problem = compare_client_hashes(host_output, outputs)
    if problem:
        return False, [f"{label}: {problem}"]
    days = net_lines(host_output, "net host day=")
    if len(days) != NET_DAYS:
        return False, [f"{label}: the host ran {len(days)} days"]
    problem, note = check_refusal(host_output, outputs, None)
    if problem:
        return False, [f"{label}: {problem}"]
    nested = net_lines(host_output, "net host nested ")
    sent = [line for output in outputs for line in net_lines(output, "net client nested ")]
    if not sent or sent[0]["inner"] != "1":
        return False, [f"{label}: the client did not run its nested command: {sent}"]
    if not nested or nested[0]["outer"] != "1" or nested[0]["inner"] != "1":
        return False, [f"{label}: the host did not run the client's nested command once: {nested}"]
    flag_sent = [line for output in outputs for line in net_lines(output, "net client session flag ")]
    flag_host = net_lines(host_output, "net host session flag ")
    flag_failed = [
        line for line in net_lines(host_output, "net command failed ")
        if line.get("kind") == "SetSessionFlag" and line.get("reason", "").startswith("other")
    ]
    flag_refused = [
        line for output in outputs for line in net_lines(output, "net client refused ")
        if line.get("kind") == "SetSessionFlag"
    ]
    if not flag_sent or not flag_host:
        return False, [f"{label}: no session flag probe: {flag_sent} {flag_host}"]
    if flag_host[0]["friendly-fire"] == flag_sent[0]["friendly-fire"]:
        return False, [f"{label}: a client's session flag changed the host's"]
    if not flag_failed or not flag_refused:
        return False, [f"{label}: the host did not refuse a client's session flag: {flag_failed} {flag_refused}"]
    # The client's cheat (a Cheat command): its prediction gave its ranger the experience, and
    # the host applied it for that human; the hashes compared above show both agree after it.
    cheat_sent = [line for output in outputs for line in net_lines(output, "net client cheat ")]
    cheat_host = net_lines(host_output, "net host cheat ")
    if not cheat_sent or cheat_sent[0]["gained"] != "1000000" or cheat_sent[0]["used"] != "1":
        return False, [f"{label}: the client's cheat did not run there: {cheat_sent}"]
    applied = [line for line in cheat_host if line["human"] == cheat_sent[0]["human"]]
    if not applied or applied[0]["used"] != "1" or applied[0]["cheats"] != "1":
        return False, [f"{label}: the host did not apply the client's cheat: {cheat_host}"]
    if any(line["used"] != "0" for line in cheat_host if line["human"] != cheat_sent[0]["human"]):
        return False, [f"{label}: the client's cheat went to another human: {cheat_host}"]
    problem, cancel_note = check_cancel_end_turn(host_output, outputs)
    if problem:
        return False, [f"{label}: {problem}"]
    return True, [
        f"{label}: {NET_DAYS} days, client hashes match the host's",
        f"{label}: {note}",
        f"{label}: a command a client submits from inside another reaches the host once",
        f"{label}: a client's session flag is refused, and the host's stays",
        f"{label}: a client's cheat runs on the client and on the host, for its human",
        f"{label}: {cancel_note}",
    ]


def check_cancel_end_turn(host_output: str, outputs: list[str]) -> tuple[str, str]:
    """A run with --sim-net-cancel-end-turn (docs/network.md, Waiting and Tests): the client took
    its end turn back before the first day; the host took the EndTurn out of its queue, after
    which its peer was not ready, and the client's human held the day again and ended it again,
    after which the day ran. Once the second day had begun, the host refused the same (too-late),
    and the client heard it. Later, after a state that said its travel continued, the client
    stopped it before the host's next day: the host queued a StopContinuing and was no longer
    ready, the client's human held the day and played it, and the days went on. When the first
    turn took off (the human was landed or docked), the takeoff was taken back with the end turn:
    the host ran the cancel in the EndTurn's place (takeoff=1), the client's human stayed, and
    the next state still had it landed or docked. Returns what is wrong, and a note."""
    probes = [line for output in outputs for line in net_lines(output, "net client end turn cancel ")]
    first = [line for line in probes if line.get("first") == "1"]
    late = [line for line in probes if line.get("first") == "0"]
    if not first or first[0]["accepted"] != "1" or first[0]["holds"] != "1":
        return f"the client could not take its end turn back: {first}", ""
    human = first[0]["human"]
    cancelled = [line for line in net_lines(host_output, "net end turn cancelled ") if line["human"] == human]
    if len(cancelled) != 1 or cancelled[0]["ready"] != "0":
        return f"the host did not take human {human}'s end turn back, or was still ready: {cancelled}", ""
    took_off = first[0].get("takeoff") == "1"
    takeoff_note = ""
    if took_off:
        after = [line for output in outputs for line in net_lines(output, "net client after takeoff cancel ")]
        if first[0].get("landed") != "1" or cancelled[0].get("takeoff") != "1":
            return f"the takeoff was not taken back with the end turn: {first} {cancelled}", ""
        if not after or after[0].get("landed") != "1":
            return f"the host's next day did not keep the human landed after its takeoff was taken back: {after}", ""
        takeoff_note = " (with its takeoff: it stays landed for the day)"
    if not late or late[0]["sent"] != "1" or late[0]["accepted"] != "0":
        return f"a cancelled end turn after the day began was not refused: {late}", ""
    failed = [
        line for line in net_lines(host_output, "net command failed ")
        if line["human"] == human and line["kind"] == "CancelEndTurn"
    ]
    if len(failed) != 1 or not failed[0]["reason"].startswith("too-late"):
        return f"the host did not refuse the late cancel as too-late: {failed}", ""
    answered = [line for output in outputs for line in net_lines(output, "net end turn cancel answered ")]
    if [line["ok"] for line in answered[:2]] != ["1", "0"] or answered[1]["reason"] != "too-late":
        return f"the client did not hear both answers: {answered}", ""
    travel = [line for output in outputs for line in net_lines(output, "net client travel cancel day=")]
    untried = [line for output in outputs for line in net_lines(output, "net client travel cancel untried ")]
    if not travel and untried and untried[0].get("in-space-turns") == "0":
        # Some new games' clients never leave their planet: no travel continues to stop.
        return "", (
            f"a client takes its end turn back{takeoff_note} before the day (the host is no longer "
            f"ready) and ends it again; once day {late[0]['day']} has begun it is refused (too-late); the "
            "client never left its planet, so no continuing travel was stopped in this new game"
        )
    if not travel or travel[0].get("accepted") != "1" or travel[0].get("holds") != "1":
        return f"the client could not stop its continuing travel: {travel} {untried}", ""
    stopped = [line for line in net_lines(host_output, "net travel stopped ") if line["human"] == human]
    if len(stopped) != 1 or stopped[0]["ready"] != "0":
        return f"the host did not stop human {human}'s travel, or was still ready: {stopped}", ""
    return "", (
        f"a client takes its end turn back{takeoff_note} before the day (the host is no longer "
        f"ready) and ends it again; once day {late[0]['day']} has begun it is refused (too-late); a client whose "
        f"travel continues stops it before day {travel[0]['day']} and plays that day"
    )


def check_network_shop(args, binary: Path) -> tuple[bool, list[str]]:
    """Trades between humans at one planet (docs/network.md, Trades and Tests): a new game whose
    host's human opens the planet's shop, and two clients that join there (--sim-net-shop).

    Net1 buys an item X; the host applies it as it arrives and relays it to Net2, whose grid no
    longer shows X; the host's own purchase of X, from its grid as it was, is refused (item-gone)
    and the host's grid was rebuilt and its screen told. Net1 buys a good and sells it back, and
    Net2 sees the planet's stock go down and up again from the relays. Net1 sells an item from
    the ship screen: the three hold commands before the sale apply with it, in order; it also sells
    an item from its storage. Both sales reach Net2 as their effects (RelayedSale) before any
    state: the items are back in the shop, Net2's grid shows them, and Net1 no longer has them on
    Net2's copy. Net2's purchase of X is refused (item-gone) while it waits for it. Only trades
    are relayed, and a ship screen sale only as its effect. A
    purchase Net2 sends right after its end turn applies after that day. Every client state has
    the host's hash. Net1 goes through a government dialogue before buying X: the host applies
    it with the purchase while its own script dialogue is open, and its own dialogue state (the
    message, the script and an injected answer) stays as it was."""
    label = "new game, 3 humans trading at one planet"
    problem, host_output, outputs = run_network(args, binary, None, 2, shop=True)
    if not problem:
        problem = compare_client_hashes(host_output, outputs)
    if problem:
        return False, [f"{label}: {problem}"]
    net1, net2 = outputs[0], outputs[1]
    id1 = fields(last_line(net1, "done net client ")).get("human")
    id2 = fields(last_line(net2, "done net client ")).get("human")
    bought = net_lines(net1, "net client shop bought ")
    if not bought or bought[0]["reason"] != "":
        return False, [f"{label}: Net1 did not buy its item: {bought}" + output_tail(net1)]
    item = bought[0]["item"]
    applied = net_lines(host_output, "net trade applied ")
    if not any(line["human"] == id1 and line["kind"] == "BuyEquipment" for line in applied):
        return False, [f"{label}: the host did not apply Net1's purchase as it came: {applied}"]
    own = net_lines(host_output, "net host own trade refused ")
    grid = net_lines(host_output, "net host shop grid ")
    if not own or own[0]["reason"] != "item-gone":
        return False, [f"{label}: the host's own purchase of item {item} was not refused: {own}" + output_tail(host_output)]
    if not grid or grid[0]["shows"] != "0" or int(grid[0]["notified"]) < 1:
        return False, [f"{label}: the host's grid was not rebuilt after Net1's purchase: {grid}"]
    relay = net_lines(net2, "net client shop relay ")
    if not relay:
        return False, [f"{label}: Net2 saw no relay:" + output_tail(net2)]
    relay = relay[0]
    if relay["grid-shows-x"] != "0" or int(relay["low"]) >= int(relay["goods-before"]) or relay["after"] != relay["goods-before"]:
        return False, [f"{label}: Net2's copy did not follow Net1's trades: {relay}"]
    gone = net_lines(net2, "net client shop buy-gone ")
    if not gone or gone[0]["reason"] != "item-gone":
        return False, [f"{label}: Net2's purchase of item {item} was not refused: {gone}"]
    answered = [line for line in net_lines(net2, "net trade answered ") if line["kind"] == "BuyEquipment"]
    if not answered or answered[0]["ok"] != "0" or answered[0]["reason"] != "item-gone":
        return False, [f"{label}: Net2 did not get the refusal while it waited: {answered}"]
    purchase = [line for line in applied if line["human"] == id1 and line["kind"] == "BuyEquipment"]
    dialogue = net_lines(host_output, "net host dialogue ")
    if "net client shop dialogue sent" not in net1.splitlines() or not purchase or int(purchase[0]["before"]) < 4:
        return False, [f"{label}: Net1's government dialogue did not apply with its purchase: {purchase}"]
    if (not dialogue or dialogue[0]["kept"] != "1" or int(dialogue[0]["checks"]) < 2
            or int(dialogue[0]["remote"]) < 3):
        return False, [f"{label}: Net1's dialogue changed the host's own open dialogue: {dialogue}"]
    sale = [line for line in applied if line["human"] == id1 and line["kind"] == "SellHeld"]
    if not sale or sale[0]["before"] != "3":
        return False, [f"{label}: the hold commands before Net1's sale did not apply with it: {sale}"]
    relayed = net_lines(host_output, "net relayed ")
    ran = net_lines(net2, "net relayed command ran ")
    kinds = {line["kind"] for line in relayed} | {line["kind"] for line in ran}
    if not relayed or not kinds <= RELAYED_KINDS:
        return False, [f"{label}: the host relayed {sorted(kinds - RELAYED_KINDS) or 'nothing'}, not only trades and sales' effects"]
    sales = {line.get("sale") for line in relayed if line["human"] == id1 and line["kind"] == "RelayedSale"}
    if not {"SellHeld", "SellStoredItem"} <= sales:
        return False, [f"{label}: Net1's sales were not relayed as their effects: {relayed}"]
    failed = [line for line in ran if line["ok"] != "1"]
    if failed:
        return False, [f"{label}: a relay failed on Net2: {failed}" + output_tail(net2)]
    stored = net_lines(net1, "net client shop sold stored item=")
    effect = net_lines(net2, "net client shop sale relay ")
    if not stored or stored[0]["bought"] != "":
        return False, [f"{label}: Net1 did not sell an item from its storage: {stored}" + output_tail(net1)]
    if not effect or any(effect[0][key] != value for key, value in
                         {"y-grid": "1", "y-owned": "0", "z-grid": "1", "z-owned": "0"}.items()):
        return False, [f"{label}: Net1's sales did not reach Net2's shop before the state: {effect}" + output_tail(net2)]
    if not {"BuyEquipment", "TradeGoods"} <= {line["kind"] for line in relayed if line["human"] == id1}:
        return False, [f"{label}: Net1's purchases were not relayed: {relayed}"]
    sent = net_lines(net2, "net client shop sent after end turn ")
    if not sent:
        return False, [f"{label}: Net2 sent nothing after its end turn"]
    seq = sent[0]["seq"]
    host_lines = host_output.splitlines()
    first_day = next((i for i, line in enumerate(host_lines) if line.startswith("net host day=")), None)
    late = next(
        (i for i, line in enumerate(host_lines)
         if line.startswith("net trade applied ") and fields(line).get("human") == id2 and fields(line).get("seq") == seq),
        None,
    )  # fmt: skip
    if first_day is None or late is None or late < first_day:
        return False, [f"{label}: the purchase Net2 sent while the day ran was not applied after it"]
    result = [line for line in net_lines(net2, "net client result ") if line["seq"] == seq]
    if not result:
        return False, [f"{label}: Net2 did not hear that its purchase {seq} was applied"]
    return True, [
        f"{label}: {NET_SHOP_DAYS} days, client hashes match the host's",
        f"{label}: a purchase applies on the host as it comes ({bought[0]['item']}), the other client's grid "
        "follows from the relay and its purchase of the item is refused (item-gone) while it waits, the host's own "
        "purchase of it is refused and its grid rebuilt",
        f"{label}: a sale of goods is seen by the other client; a sale from the ship screen applies with the 3 hold "
        f"commands before it; only trades are relayed ({', '.join(sorted(kinds))})",
        f"{label}: a sale from the hand and one from the storage reach the other client's shop and grid as their "
        "effects (RelayedSale) before the next state, and leave the seller's possessions there",
        f"{label}: a purchase sent while the day runs applies after it",
        f"{label}: a client's government dialogue applies with its purchase and leaves the host's own open "
        f"dialogue as it was ({dialogue[0]['checks']} checks, {dialogue[0]['remote']} dialogue commands)",
    ]


def check_network_storage(args, binary: Path) -> tuple[bool, list[str]]:
    """The shared storage between networked humans (docs/humans.md, Storage; --sim-net-storage):
    a new game whose host's human stays at its planet, and two clients that join there.

    Net1 buys two items X and Y, stores them, takes X back and puts it into its hold; the host
    applies each store and the take as they arrive and relays their effect (RelayedStorage) to
    Net2, whose copy shows both stored, then X gone, before any state; the host's own screen is
    told. Net2's take of X, by the cell and id it had, is refused (item-gone) while it waits (the
    host applies a client's trades once the clients before it have ended their turns, so the
    later client is the one refused); then it takes Y. At the end every human shares one pool on
    the host, X is Net1's and Y Net2's. Only trades are relayed, a storage command only as its
    effect, and every client state has the host's hash."""
    label = "new game, 3 humans sharing a planet's storage"
    problem, host_output, outputs = run_network(args, binary, None, 2, storage=True)
    if not problem:
        problem = compare_client_hashes(host_output, outputs)
    if problem:
        return False, [f"{label}: {problem}"]
    net1, net2 = outputs[0], outputs[1]
    id1 = fields(last_line(net1, "done net client ")).get("human")
    id2 = fields(last_line(net2, "done net client ")).get("human")
    stored = net_lines(net1, "net client storage stored ")
    if not stored:
        return False, [f"{label}: Net1 stored nothing:" + output_tail(net1)]
    x, y = stored[0]["x"], stored[0]["y"]
    took1 = net_lines(net1, "net client storage took ")
    if not took1 or took1[0]["item"] != x or took1[0]["reason"] or took1[0]["held"] != "1" or took1[0]["stored"] != "0":
        return False, [f"{label}: Net1 did not take X back: {took1}" + output_tail(net1)]
    applied = net_lines(host_output, "net trade applied ")
    kinds1 = [line["kind"] for line in applied if line["human"] == id1]
    if kinds1.count("StoreHeld") < 2 or "TakeStored" not in kinds1:
        return False, [f"{label}: the host did not apply Net1's stores and take as they came: {kinds1}"]
    relay = net_lines(net2, "net client storage relay ")
    if not relay or relay[0]["x"] != x or relay[0]["y"] != y or int(relay[0]["notified"]) < 1:
        return False, [f"{label}: Net2's copy did not show Net1's stores before the state: {relay}" + output_tail(net2)]
    saw = net_lines(net2, "net client storage saw take ")
    if not saw or saw[0]["y-stored"] != "1" or int(saw[0]["notified"]) <= int(relay[0]["notified"]):
        return False, [f"{label}: Net2's copy did not follow Net1's take: {saw}" + output_tail(net2)]
    gone = net_lines(net2, "net client storage take-gone ")
    if not gone or gone[0]["reason"] != "item-gone" or gone[0]["held"] != "0":
        return False, [f"{label}: Net2's second take of X was not refused: {gone}"]
    answered = [line for line in net_lines(net2, "net trade answered ") if line["kind"] == "TakeStored"]
    if not answered or answered[0]["ok"] != "0" or answered[0]["reason"] != "item-gone":
        return False, [f"{label}: Net2 did not get the refusal while it waited: {answered}"]
    took2 = net_lines(net2, "net client storage took ")
    if not took2 or took2[0]["item"] != y or took2[0]["reason"] or took2[0]["held"] != "1" or took2[0]["stored"] != "0":
        return False, [f"{label}: Net2 did not take Y: {took2}" + output_tail(net2)]
    relayed = net_lines(host_output, "net relayed ")
    ran = net_lines(net1, "net relayed command ran ") + net_lines(net2, "net relayed command ran ")
    kinds = {line["kind"] for line in relayed} | {line["kind"] for line in ran}
    if not kinds <= RELAYED_KINDS or "RelayedStorage" not in kinds:
        return False, [f"{label}: the host relayed {sorted(kinds - RELAYED_KINDS) or sorted(kinds)}, not trades and storage effects"]
    failed = [line for line in ran if line["ok"] != "1"]
    if failed:
        return False, [f"{label}: a relay failed on a client: {failed}"]
    host = net_lines(host_output, "net host storage notified=")
    if not host or host[0]["shared"] != "1" or int(host[0]["notified"]) < 4:
        return False, [f"{label}: the host's pool or screen did not follow: {host}"]
    stored_ids = host[0]["stored"].split(",") if host[0]["stored"] else []
    owns = {line["human"]: line["owns"].split(",") for line in net_lines(host_output, "net host storage human=")}
    if x in stored_ids or y in stored_ids or x not in owns.get(id1, []) or y not in owns.get(id2, []):
        return False, [f"{label}: the host ends with stored {stored_ids}, Net1 owning {owns.get(id1)}, Net2 {owns.get(id2)} (x={x} y={y})"]
    return True, [
        f"{label}: {NET_SHOP_DAYS} days, client hashes match the host's",
        f"{label}: stores and takes apply on the host as they come and reach the other client as their effect "
        "(RelayedStorage) before the next state; the host's screen is told",
        f"{label}: a second take of the same item is refused (item-gone) while the client waits; each taken item ends "
        "in its taker's hold",
    ]


def check_network_shared_quest(args, binary: Path) -> tuple[bool, list[str]]:
    """The shared quests between networked humans (docs/humans.md, Quests; --sim-net-shared-quest):
    a new game whose host's human stays at its planet, and two clients that join there.

    Net1 takes a letter quest on its first day (predicted, applied by the host at the barrier)
    and hands the letter to the host's human, who delivers it on its second day. The host's own
    journal shows the quest before it delivers it; the reward is split equally among the three
    humans (the deliverer gets what does not divide), and every human's journal has the
    completion. Each client's journal shows the accepted quest after the first day's state and
    the completed one after the second's: Net2 never ran Net1's command, so it has them from the
    host. Every client state has the host's hash."""
    label = "new game, 3 humans sharing a quest"
    problem, host_output, outputs = run_network(args, binary, None, 2, shared_quest=True)
    if not problem:
        problem = compare_client_hashes(host_output, outputs)
    if problem:
        return False, [f"{label}: {problem}"]
    accepted = net_lines(outputs[0], "net client shared-quest accepted ")
    if not accepted or accepted[0]["held"] != "1" or accepted[0]["entry"] != "3":
        return False, [f"{label}: Net1 did not take the quest: {accepted}" + output_tail(outputs[0])]
    before = net_lines(host_output, "net host shared-quest before ")
    if not before or before[0]["entry"] != "3":
        return False, [f"{label}: the host's journal lacks Net1's quest: {before}" + output_tail(host_output)]
    turned = net_lines(host_output, "net host shared-quest turned-in=")
    if not turned or turned[0]["turned-in"] != "1":
        return False, [f"{label}: the host's human did not deliver Net1's quest: {turned}" + output_tail(host_output)]
    reward = int(turned[0]["reward"])
    gains = net_lines(host_output, "net host shared-quest human=")
    share = reward // len(gains) if gains else 0
    expected = sorted([share] * (len(gains) - 1) + [reward - share * (len(gains) - 1)])
    if len(gains) != 3 or sorted(int(line["gain"]) for line in gains) != expected or any(
        line["entry"] != "4" for line in gains
    ):
        return False, [f"{label}: the reward or the journal did not reach every human: {gains}"]
    for name, output in zip(("Net1", "Net2"), outputs):
        entries = [line["entry"] for line in net_lines(output, "net client shared-quest day=")]
        if "3" not in entries or "4" not in entries or entries.index("3") > entries.index("4"):
            return False, [f"{label}: {name}'s journal after each state was {entries}"]
    return True, [
        f"{label}: {NET_SHOP_DAYS} days, client hashes match the host's",
        f"{label}: a client's accepted quest shows in every journal (host and both clients, after the state); "
        f"the host's human delivers it and the reward splits {expected}",
    ]


def check_network_transfer(args, binary: Path) -> tuple[bool, list[str]]:
    """Money transfers between networked humans (docs/commands.md, TransferMoney;
    --sim-net-transfer): a new game with two clients.

    The host's human gives Net2 50 on its first day; Net1 gives Net2 100 on its first turn, a trade
    the host applies as it comes. Each transfer moves exactly its amount on the host, and the host
    relays it (RelayedTransfer) to every other client: Net1 and Net2 apply the host's transfer,
    Net2 applies Net1's, and Net1 applies its own once the host has answered, each leaving the
    sender the host's money and the recipient a bubble. A transfer of more than the sender has is refused
    (no-money) on the host and, through the host's answer, on Net1, and changes nothing. Net2
    also talks with the host's human's ranger, wherever it is (the players' buttons' talk: the
    talk's commands, applied by the host at the barrier). Every client state has the host's
    hash."""
    label = "new game, 3 humans transferring money"
    problem, host_output, outputs = run_network(args, binary, None, 2, transfer=True)
    if not problem:
        problem = compare_client_hashes(host_output, outputs)
    if problem:
        return False, [f"{label}: {problem}"]
    net1, net2 = outputs
    id1 = fields(last_line(net1, "done net client ")).get("human")
    id2 = fields(last_line(net2, "done net client ")).get("human")
    host_id = fields(last_line(host_output, "net host transfer sent ")).get("human")
    expected = {(host_id, id2, "50"), (id1, id2, "100")}
    for side, output in (("host", host_output), ("Net1", net1), ("Net2", net2)):
        prefix = "net host transfer from=" if side == "host" else "net client transfer from="
        seen = net_lines(output, prefix)
        if {(line["from"], line["to"], line["amount"]) for line in seen} != expected or any(
            line["bubble"] != "1" for line in seen
        ):
            return False, [f"{label}: {side} applied the transfers {seen}, expected {sorted(expected)}"]
    host_seen = {(line["from"], line["amount"]): line for line in net_lines(host_output, "net host transfer from=")}
    for output, name in ((net1, "Net1"), (net2, "Net2")):
        for line in net_lines(output, "net client transfer from="):
            host_line = host_seen[(line["from"], line["amount"])]
            # Only the sender gives its own money away, so its money after the transfer is the
            # host's everywhere; the recipient's may still lack another relay that came later.
            if line["from-money"] != host_line["from-money"]:
                return False, [f"{label}: {name}'s money after a transfer {line} is not the host's {host_line}"]
    for side, output, prefix in (("host", host_output, "net host transfer "), ("Net1", net1, "net client transfer ")):
        sent = net_lines(output, prefix + "sent ")
        over = net_lines(output, prefix + "over ")
        if not sent or int(sent[0]["before"]) - int(sent[0]["after"]) != int(sent[0]["amount"]):
            return False, [f"{label}: {side}'s transfer did not move its amount: {sent}"]
        if not over or over[0]["reason"] != "no-money" or over[0]["before"] != over[0]["after"]:
            return False, [f"{label}: {side}'s transfer of more than it has was not refused: {over}"]
    talk = net_lines(net2, "net client remote talk ")
    if not talk or talk[0]["ship"] != host_id or talk[0]["talking"] != "0":
        return False, [f"{label}: Net2's talk with the host's human's ranger did not run: {talk}" + output_tail(net2)]
    relays = net_lines(host_output, "net relayed human=")
    to_clients = {(line["human"], line["to"]) for line in relays if line.get("kind") == "RelayedTransfer"}
    if to_clients != {(host_id, id1), (host_id, id2), (id1, id2)}:
        return False, [f"{label}: the host relayed the transfers to {sorted(to_clients)}"]
    return True, [
        f"{label}: {NET_SHOP_DAYS} days, client hashes match the host's",
        f"{label}: the host's and a client's transfers move their amounts on every machine, with the "
        "recipient's bubble; more than the sender has is refused (no-money)",
        f"{label}: a client's talk with another human's ranger at any distance keeps the hashes "
        f"(same star: {talk[0]['same-star']})",
    ]


def check_humans(args, binary: Path, save: Path, count: int) -> tuple[bool, str]:
    """Play with extra humans: no crash, a clean round trip, the same hashes twice.

    Before each round trip the probe gives every human, script and one event state that a
    load without the per-human save block would lose; the round trip compares it field by
    field (roundtrip humans=...), besides the state hash, which covers the block. The probe
    also ends the last human's game, whose commands must then be refused. Before turn
    HUMAN_KILL_TURN the local human's ranger and the last human's are destroyed; they must
    respawn, and no human may leave the game.
    """
    options = [
        f"--sim-humans={count}", "--sim-roundtrip", f"--sim-turns={HUMAN_TURNS}", "--sim-hash",
        f"--sim-seed={args.seed}", "--sim-session-probe", f"--sim-kill-human={HUMAN_KILL_TURN}",
    ]  # fmt: skip
    runs = []
    for _ in range(2):
        code, output = simulate(binary, args.game_dir, save, options)
        roundtrip = [line for line in output.splitlines() if line.startswith("roundtrip ")]
        if code != 0 or not roundtrip or any("=ok" not in line for line in roundtrip):
            return False, f"{count} humans failed:" + output_tail(output)
        if f" humans={count} " not in last_line(output, "done ") + " ":
            return False, f"{count} humans: a human was lost:" + output_tail(output)
        problem = check_respawns(output)
        if problem:
            return False, f"{count} humans: {problem}"
        probes = [line for line in output.splitlines() if line.startswith("probe finished ")]
        if not probes or any(not line.endswith("command=refused") for line in probes):
            return False, f"{count} humans: a finished human's command was not refused"
        # A human's cheat command runs for it while cheats are allowed, and is refused once the
        # session turns them off (--sim-session-probe, ProbeCheats).
        cheats = [line for line in output.splitlines() if line.startswith("probe cheat ")]
        if not cheats or any(" on=applied off=refused " not in line + " " for line in cheats):
            return False, f"{count} humans: the cheat probe failed: {cheats}"
        runs.append(turn_lines(output))
    if runs[0] != runs[1]:
        return False, f"{count} humans nondeterministic: " + first_divergence(runs[0], runs[1])
    return True, (
        f"{count} humans: {HUMAN_TURNS} turns, round trip ok, deterministic, respawn ok, "
        "script game end ok, cheats follow the session flag"
    )


def check_pvp(args, binary: Path, save: Path, count: int) -> tuple[bool, str]:
    """Humans as targets (ROADMAP.md, Phase 4, item 8), with `count` humans.

    The local human attacks a second human in its star (--sim-pvp): with friendly fire on its
    hits must do damage; after the SetSessionFlag command turns it off, the attack order must be
    gone, new ones refused, and no hit may do damage, from the weapons or a direct hit. The run
    reports "pvp ok" or "pvp failed: ...". Twice, with the same lines.
    """
    runs = []
    for _ in range(2):
        code, output = simulate(
            binary, args.game_dir, save, [f"--sim-humans={count}", "--sim-pvp", f"--sim-seed={args.seed}"]
        )
        lines = [line.strip() for line in output.splitlines() if line.startswith("pvp ")]
        if any(line.startswith("pvp skipped") for line in lines):
            return True, f"{count} humans pvp: " + lines[-1]
        if code != 0 or "pvp ok" not in lines:
            return False, f"{count} humans pvp failed:" + output_tail(output)
        runs.append(lines)
    if runs[0] != runs[1]:
        return False, f"{count} humans pvp nondeterministic: " + first_divergence(runs[0], runs[1])
    fire = next(line for line in runs[0] if line.startswith("pvp friendly-fire=1 "))
    return True, (
        f"{count} humans pvp: damage with friendly fire on ({fire.split()[3]}), "
        "none and orders refused with it off"
    )


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

    passed_shop, note = check_shared_shop(args, binary, save)
    notes.append(note)
    passed = passed and passed_shop

    passed_storage, note = check_shared_storage(args, binary, save)
    notes.append(note)
    passed = passed and passed_storage

    passed_quests, note = check_shared_quests(args, binary, save)
    notes.append(note)
    passed = passed and passed_quests

    passed_arcade, note = check_arcade_hold(args, binary, save)
    notes.append(note)
    passed = passed and passed_arcade

    passed_routing, note = check_script_routing(args, binary, save)
    notes.append(note)
    passed = passed and passed_routing

    passed_stale, note = check_stale_commands(args, binary, save)
    notes.append(note)
    passed = passed and passed_stale

    passed_quest, note = check_text_quest(args, binary, save)
    notes.append(note)
    passed = passed and passed_quest

    passed_quest, note = check_hotseat_text_quest(args, binary, save)
    notes.append(note)
    passed = passed and passed_quest

    passed_quest, note = check_quest_lock(args, binary, save)
    notes.append(note)
    passed = passed and passed_quest

    for count in HUMAN_COUNTS:
        passed_humans, note = check_humans(args, binary, save, count)
        notes.append(note)
        passed = passed and passed_humans
        passed_pvp, note = check_pvp(args, binary, save, count)
        notes.append(note)
        passed = passed and passed_pvp
        passed_hotseat, note = check_hotseat(args, binary, save, count)
        notes.append(note)
        passed = passed and passed_hotseat

    for count in NET_CLIENT_COUNTS:
        passed_network, network_notes = check_network(args, binary, save, count)
        notes.extend(network_notes)
        passed = passed and passed_network

    passed_network, network_notes = check_network_quests(args, binary, save)
    notes.extend(network_notes)
    passed = passed and passed_network

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
    parser.add_argument(
        "--poison-frees",
        nargs="?",
        const=0,
        type=int,
        metavar="MB",
        help="Run every game with poisoned frees (debug builds; docs/network.md), optionally "
        "with a quarantine of MB megabytes.",
    )
    args = parser.parse_args()
    if args.poison_frees is not None:
        if args.release:
            parser.error("--poison-frees needs the debug build.")
        GAME_OPTIONS.append(
            f"--poison-frees={args.poison_frees}" if args.poison_frees else "--poison-frees"
        )
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
        futures[Path("new game")] = pool.submit(check_new_game_network, args, binary)
        futures[Path("new game shop")] = pool.submit(check_network_shop, args, binary)
        futures[Path("new game storage")] = pool.submit(check_network_storage, args, binary)
        futures[Path("new game shared quest")] = pool.submit(check_network_shared_quest, args, binary)
        futures[Path("new game transfer")] = pool.submit(check_network_transfer, args, binary)
        for path, future in futures.items():
            passed, notes = future.result()
            failed += not passed
            print(f"{'PASS' if passed else 'FAIL'} {path.name}")
            for note in notes:
                print(f"  {note}")
    total = len(futures)
    print(f"{total - failed}/{total} saves, replays and the new game passed ({target_name()})")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
