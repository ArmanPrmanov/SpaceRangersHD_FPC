# Multiplayer progress

The plan is in [ROADMAP.md](../../ROADMAP.md). This folder records how far it
has got.

- **This file** holds the current status only. Each session rewrites the
  Status section so that it stays short. Read it at the start of a session.
- **One file per session** (`YYYY-MM-DD-<topic>.md`) holds that session's
  notes. Once written it is not edited. Read an old entry only when the
  status points to it.

## Status

- Phase: 0 done; second-human spike done (branch `spike/second-human`,
  not for merging). CI written, not yet run (needs a push).
- Next: the two single-player-safe fixes from the spike (`GetPlayer`→`Self`
  in `TPlayer`, eager ruins proxy), then Phase 1 including the script
  raw-address fix.
- Open issues: script object references saved as raw addresses; after one
  turn a round trip no longer matches, even in single player. CI format job
  fails on files formatted before Phase 0.
- Latest entry: [2026-09-24-spike-second-human.md](2026-09-24-spike-second-human.md)

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
