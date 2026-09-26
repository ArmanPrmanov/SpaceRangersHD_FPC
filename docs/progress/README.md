# Multiplayer progress

The plan is in [ROADMAP.md](../../ROADMAP.md). This folder records how far it
has got.

- **This file** holds the current status only. Each session rewrites the
  Status section so that it stays short. Read it at the start of a session.
- **One file per session** (`YYYY-MM-DD-<topic>.md`) holds that session's
  notes. Once written it is not edited. Read an old entry only when the
  status points to it.

## Status

- Phase: 0-2 done. Phase 3 done except the arcade checkpoint (needs the
  owner's go-ahead) and the recorded-session exit test. Phase 4 in
  progress: the foundation, the turn structure, scripts bound to humans,
  and the classification of `GetPlayer` sites (1,773 -> 118, the rest
  are `HUMANS:` markers) are done.
- Next: per-human save block and session flags, PvP, respawn, the day
  waiting for every human, hot-seat, then the `HUMANS:` decisions.
- Open issues: chaotic mode is seeded from the clock (Phase 1 entry); a
  loaded game drifts from the live one (Phase 3 entry); no converted
  screen has been exercised in the UI yet.
- Latest entry: [2026-09-26-phase4.md](2026-09-26-phase4.md)

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
