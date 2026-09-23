# 2026-09-24 — Direction review

- Done: reviewed the plan against the chosen network model. The direction
  stands; three changes went into ROADMAP.md:
  - A throwaway second-human spike right after Phase 0, to size Phase 4
    before investing in Phases 1–3.
  - Phase 1 cut to what replay tests need; Phase 2 cut to what the test
    runner and Phase 4 need. Neither is needed by clients, since only the
    host simulates.
  - Client state replacement: apply only at a safe point, with screens
    holding ids instead of object references. Tested in Milestone 1.
- Next: build-loop speed-up, `tools/outline.py`, Phase 0, spike.
- Notes: saves are zlib-compressed and hold previews and films too
  (`aSaveLoad.pas` around line 139); a typical save is ~11 MB. Daily full
  snapshots only work on LAN, so deltas (zstd `--patch-from` on uncompressed
  state) are required for internet play.
