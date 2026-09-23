# Multiplayer progress

The plan is in [ROADMAP.md](../../ROADMAP.md). This folder records how far it
has got.

- **This file** holds the current status only. Each session rewrites the
  Status section so that it stays short. Read it at the start of a session.
- **One file per session** (`YYYY-MM-DD-<topic>.md`) holds that session's
  notes. Once written it is not edited. Read an old entry only when the
  status points to it.

## Status

- Phase: 0 done (runner, hash, goldens, unit tests, round trip). CI written, not yet run.
- Next: run CI and fix it; then the second-human spike or Phase 1.
- Open issues: script object references saved as raw addresses; some cannot
  be resolved to an object (see the Phase 0 entry). CI format job fails on
  files formatted before this session.
- Latest entry: [2026-09-24-phase0.md](2026-09-24-phase0.md)

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
