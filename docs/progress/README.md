# Multiplayer progress

The plan is in [ROADMAP.md](../../ROADMAP.md). This folder records how far it
has got.

- **This file** holds the current status only. Each session rewrites the
  Status section so that it stays short. Read it at the start of a session.
- **One file per session** (`YYYY-MM-DD-<topic>.md`) holds that session's
  notes. Once written it is not edited. Read an old entry only when the
  status points to it.

## Status

- Phase: 0-4 done (Phase 3 minus the arcade checkpoint and the recorded-session
  exit test; Phase 4's hot-seat UI still needs a hand check). Phase 5 under way:
  the headless networking core is done and tested over loopback.
- Next: Phase 5 UI (waiting screens, client film playback, applying state
  between screens), remote dialogue, host/join menus, poisoned frees.
- Open issues: chaotic mode is seeded from the clock (Phase 1 entry); a
  loaded game drifts from the live one (Phase 3 entry); no converted
  screen has been exercised in the UI yet; the gaps in the Phase 5 entry.
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
