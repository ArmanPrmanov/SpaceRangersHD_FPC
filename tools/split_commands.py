#!/usr/bin/env python3
"""Split a command log (.srcl) into one log per human, for the hot-seat replay.

A log is 'SRCL', a version, then records: a type byte, a 32-bit size and the payload
(source/CommandLog.pas). A command record's payload starts with the command kind (16 bits)
and the actor, the human's ranger id (32 bits). Each human's log gets that human's commands
and a copy of every other record (loads, jobs, checkpoints, local-human changes): those are
the points where the logs meet again. `Rangers --replay-commands=DIR` (or a comma-separated
list) merges the logs: between two shared records, each human's commands in Session.Humans
order, then the shared record.

The logs are named human-<id>.srcl, so a directory of them sorts in no particular human
order; the replay orders by Session.Humans, not by file.
"""

import argparse
import struct
import sys
from pathlib import Path

MAGIC = b"SRCL"
COMMAND = 2


def read_records(path: Path) -> tuple[bytes, list[tuple[int, bytes]]]:
    data = path.read_bytes()
    if data[:4] != MAGIC:
        raise SystemExit(f"{path}: not a command log")
    header = data[:8]
    records = []
    offset = 8
    while offset < len(data):
        record_type, size = struct.unpack_from("<Bi", data, offset)
        offset += 5
        records.append((record_type, data[offset : offset + size]))
        offset += size
    return header, records


def split(path: Path, out_dir: Path) -> list[Path]:
    header, records = read_records(path)
    actors = []
    for record_type, payload in records:
        if record_type == COMMAND:
            actor = struct.unpack_from("<I", payload, 2)[0]
            if actor not in actors:
                actors.append(actor)
    if not actors:
        raise SystemExit(f"{path}: no commands to split")
    out_dir.mkdir(parents=True, exist_ok=True)
    written = []
    for actor in actors:
        parts = [header]
        for record_type, payload in records:
            if record_type == COMMAND and struct.unpack_from("<I", payload, 2)[0] != actor:
                continue
            parts.append(struct.pack("<Bi", record_type, len(payload)))
            parts.append(payload)
        target = out_dir / f"human-{actor}.srcl"
        target.write_bytes(b"".join(parts))
        written.append(target)
    return written


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("log", type=Path, help="The recorded log.")
    parser.add_argument("out_dir", type=Path, help="Directory for the per-human logs.")
    args = parser.parse_args()
    for path in split(args.log, args.out_dir):
        print(path)


if __name__ == "__main__":
    sys.exit(main())
