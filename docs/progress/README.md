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
- Silent disconnects (2026-10-16): ping and a 10 s silence timeout, a
  reconnection token with takeover, and the client's automatic reconnect
  (protocol 9). The reconnect box and its Cancel are not hand-checked yet.
- Text quests in multiplayer (2026-10-19): the plan; Phase A done (the
  quest run out of the screen, `--sim-text-quest`); Phase B done (the rules
  in the game layer: always on, owed quest days, respawn on a death, the
  `BeginTextQuest` lock, script quests per human); Phase C done (the network
  flow: protocol 10, `Status` with each human's quest activity and owed days,
  the waits, the quest screen as a game screen, the lock relayed and released
  on a disconnect, a reconnect abandons the quest; `--sim-net-quest`); Phase D
  done (the pages to the watchers: protocol 11, `QuestPage` relayed by the
  host, the latest page per human on every machine, an abandoned end page on a
  disconnect); Phase E done (the watch window: W in the waits for the day and a
  button in the in-game menu, read-only, live, closes with its wait); Phase F
  done (docs). The plan is done. Next: its hand checks (the plan's Phase F
  notes); a released prisoner who owes quest days still takes off (documented).
- Latest entry: [2026-10-19-text-quests-plan.md](2026-10-19-text-quests-plan.md)

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
