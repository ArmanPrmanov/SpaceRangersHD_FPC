# Multiplayer progress

The plan is in [ROADMAP.md](../../ROADMAP.md). This folder records how far it
has got.

- **This file** holds the current status only. Each session rewrites the
  Status section so that it stays short. Read it at the start of a session.
- **One file per session** (`YYYY-MM-DD-<topic>.md`) holds that session's
  notes. Once written it is not edited. Read an old entry only when the
  status points to it.

## Status

- Phase: 0 and 1 done (item 7, cross-target drift, skipped); second-human
  spike done (branch `spike/second-human`, not for merging). Phase 2 in
  progress: layer check in place (65 violations left), `SimEvents` for
  calls out of the turn, `LocalHuman` for the first per-human globals.
  CI is not used: the workflow exists but the repository is not connected
  to a runner, so tests run locally (`tools/test.py`, `tools/unit_tests.py`,
  `tools/check_layers.py`).
- Next: Phase 2 item 2 (the rest of the per-human state, then grouping
  `Globals`), and the remaining UI edges listed in the latest entry.
- Open issues: chaotic mode is seeded from the clock, not the save (a
  deliberate deviation, see the Phase 1 entry); a save with the object
  reference table is untested in the original game; `format.py --check`
  fails on files formatted before Phase 0; the player-death and shop-refresh
  handlers are untested in the game.
- Latest entry: [2026-09-24-phase2.md](2026-09-24-phase2.md)

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
