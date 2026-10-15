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
# Networked play (ROADMAP.md, Phase 5; docs/network.md, Tests): a headless host and this many
# headless clients over loopback, for this many days. With one client, a third run has the
# client leave after NET_LEAVE_DAY days and join again, and a fourth has it leave in the middle
# of a remote dialogue and join again. From day NET_TALK_DAY the host's day asks the remote
# humans of one star something (--sim-net-talk); the clients answer. The host sends the day's
# films before it asks (--sim-net-talk-after-film) and each client plays its film for NET_FILM_MS
# (--sim-net-film-ms), so the talk comes during the film and waits for its end. With one client,
# the rejoin is first cancelled once (--sim-net-cancel-join), and a fifth run has the host stop
# hosting after NET_STOP_DAY days (--sim-net-stop-at).
NET_CLIENT_COUNTS = (1, 7)
NET_DAYS = 10
NET_LEAVE_DAY = 3
NET_TALK_DAY = 2
NET_FILM_MS = 500
NET_STOP_DAY = 3
# A client notices that the host stopped hosting within this many ms.
NET_NOTICE_MS = 5000
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
    args, binary: Path, save: Path | None, count: int, log: Path | None = None, leave: str = ""
):
    """One networked session: a host with `count` clients (Net1..NetN) for NET_DAYS days. Without
    a save the host plays a new game (--sim-new-game).

    The host asks remote humans something from day NET_TALK_DAY (--sim-net-talk). With leave
    "day", Net1 leaves after NET_LEAVE_DAY days; with leave "talk", it leaves when the host asks
    it something, without answering. Once the host has run a day without it, Net1 joins again;
    after "day", a join as Net1 that cancels itself once let in comes first (the last client
    output is the real rejoin's, the one before it the cancelled one's). With leave "stop" the
    host stops hosting after NET_STOP_DAY days. Without leave the talk comes while the clients
    play their films. Returns (problem, host output, client outputs); problem is '' when every
    process ended cleanly.
    """
    host_options = [
        f"--sim-save={save}" if save is not None else "--sim-new-game", "--sim-net-host=0", f"--sim-net-clients={count}",
        f"--sim-turns={NET_DAYS}", f"--sim-seed={args.seed}", f"--sim-net-talk={NET_TALK_DAY}",
    ]  # fmt: skip
    if not leave:
        host_options.append("--sim-net-talk-after-film")
    elif leave == "stop":
        host_options.append(f"--sim-net-stop-at={NET_STOP_DAY}")
    if log is not None:
        host_options.append(f"--record-commands={log}")
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
        elif not leave:
            options.append(f"--sim-net-film-ms={NET_FILM_MS}")
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
        if code != 0:
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
    runs = []
    with tempfile.TemporaryDirectory(prefix="rangers-net-log-") as directory:
        log = Path(directory) / "host.srcl"
        for run in range(2):
            problem, host_output, outputs = run_network(
                args, binary, save, count, log if run == 0 else None
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
    return True, notes


def check_new_game_network(args, binary: Path) -> tuple[bool, list[str]]:
    """A host that starts a new game instead of loading a save (--sim-new-game) and one client:
    every state the client applies has the host's hash. A new game's galaxy is not one that a
    load gave, so this checks that a load gives back what a new game saves (the outline of the
    hidden constellation, for one)."""
    label = "new game, 2 humans networked"
    problem, host_output, outputs = run_network(args, binary, None, 1)
    if not problem:
        problem = compare_client_hashes(host_output, outputs)
    if problem:
        return False, [f"{label}: {problem}"]
    days = net_lines(host_output, "net host day=")
    if len(days) != NET_DAYS:
        return False, [f"{label}: the host ran {len(days)} days"]
    return True, [f"{label}: {NET_DAYS} days, client hashes match the host's"]


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
        runs.append(turn_lines(output))
    if runs[0] != runs[1]:
        return False, f"{count} humans nondeterministic: " + first_divergence(runs[0], runs[1])
    return True, (
        f"{count} humans: {HUMAN_TURNS} turns, round trip ok, deterministic, respawn ok, "
        "script game end ok"
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
