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
  owner's go-ahead) and the recorded-session exit test. Phase 4 done in
  code and headless tests (Milestone 3, hot-seat, `--hotseat=N`); the
  hot-seat UI still needs a hand check (see the Phase 4 entry).
- Next: the hot-seat hand check, then Phase 5 (networking). The 49
  `// HUMANS:` markers left are Phase 5 or presentation: film viewpoint,
  remote dialogue, event human id in scripts, probe orbits, shared shop.
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
