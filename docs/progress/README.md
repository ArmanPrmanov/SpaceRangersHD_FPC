# Multiplayer progress

The plan is in [ROADMAP.md](../../ROADMAP.md). This folder records how far it
has got.

- **This file** holds the current status only. Each session rewrites the
  Status section so that it stays short. Read it at the start of a session.
- **One file per session** (`YYYY-MM-DD-<topic>.md`) holds that session's
  notes. Once written it is not edited. Read an old entry only when the
  status points to it.

## Status

- Phase: 0-5 done in code. Phase 5 (networking) still owes game runs: the
  owner paused them; the list is in the Phase 5 entry's Close section.
- Next: the owed `tools/test.py` run, then the hand checks (Phase 4 hot-seat,
  Phase 5 UI, remote dialogue, menus).
- Open issues: chaotic mode is seeded from the clock (Phase 1 entry); a
  loaded game drifts from the live one (Phase 3 entry); no converted
  screen has been exercised in the UI yet; the Phase 5 known gaps.
- Latest entry: [2026-09-28-phase5.md](2026-09-28-phase5.md)

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
