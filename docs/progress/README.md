# Multiplayer progress

The plan is in [ROADMAP.md](../../ROADMAP.md). This folder records how far it
has got.

- **This file** holds the current status only. Each session rewrites the
  Status section so that it stays short. Read it at the start of a session.
- **One file per session** (`YYYY-MM-DD-<topic>.md`) holds that session's
  notes. Once written it is not edited. Read an old entry only when the
  status points to it.

## Status

- Phase: 0, 1 and 2 done; Phase 3 in progress. The command log, headless
  replay and checkpoints are in place. Travel, orders, shops, the ship
  screen, conversations, planets and the government are commands. Stations
  and the 600 range (text quests, arcade, cheats, UI scripts) are not yet.
  CI is not used; tests run locally (`tools/test.py`,
  `tools/unit_tests.py`, `tools/check_layers.py`).
- Next: finish stations from the draft in `.local/drafts/station/`, then
  the 600 range, then record a real session for the exit test.
- Open issues: chaotic mode is seeded from the clock (Phase 1 entry); a
  loaded game drifts from the live one (Phase 3 entry); no converted screen
  has been exercised in the UI yet.
- Latest entry: [2026-09-25-phase3.md](2026-09-25-phase3.md)

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
