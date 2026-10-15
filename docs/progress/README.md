# Multiplayer progress

The plan is in [ROADMAP.md](../../ROADMAP.md). This folder records how far it
has got.

- **This file** holds the current status only. Each session rewrites the
  Status section so that it stays short. Read it at the start of a session.
- **One file per session** (`YYYY-MM-DD-<topic>.md`) holds that session's
  notes. Once written it is not edited. Read an old entry only when the
  status points to it.

## Status

- Phase: 0-5 done. Phase 5 (networking) passes `tools/test.py` with and
  without `--poison-frees` (3/3, goldens unchanged, networked checks with 2
  and 8 humans, remote talks); see the Phase 5 entry's last section.
- Next: the hand checks in the real game (Phase 4 hot-seat, Phase 5 UI,
  remote dialogue, menus), first host and client on one machine, then LAN.
- Open issues: chaotic mode is seeded from the clock (Phase 1 entry); a
  loaded game drifts from the live one (Phase 3 entry); no converted
  screen has been exercised in the UI yet; the Phase 5 known gaps.
- Multiplayer sync audit (2026-10-15): script builtins act on the host's
  machine and human, and several commands race on shared objects. The fix
  order is in the entry.
- Latest entry: [2026-10-15-mp-audit.md](2026-10-15-mp-audit.md)

## Session entry format

```
# YYYY-MM-DD — <phase/step>

- Done: …
- In progress: …
- Next: …
- Notes: measurements and findings a later session would otherwise
  have to rediscover.
```

Short notes are enough. Put commit hashes next to things that landed.
