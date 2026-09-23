# 2026-09-24 — Spike: second human

- Done: the throwaway spike. Code is on the local branch
  `spike/second-human` (685bf15), never to be merged. It adds
  `--sim-humans=N` and `--sim-spike=hotseat,samestar,travel,kill` to the
  headless runner. Extra humans are created the way new-game setup creates
  the first (`InitializePlayerAtPlanet`, `ApplyCharacterPreset`), each
  docked at a coalition planet in its own star.
- Result: **the simulation tolerates many `TPlayer` instances.** With 2, 4
  and 8 humans on the late autosave (day 535), 20–40 turns run without a
  crash when humans are docked, share the local player's star, jump and land
  between stars, the local player rotates between humans each turn, and a
  human is destroyed in or out of the local player's star. Save and load
  keep every extra human as a `TPlayer`.
- Not tested: the UI with two humans (the GUI cannot be driven from this
  session), humans as combat targets (PvP), scripts and quests bound to a
  second human, arcade and black holes.
- Next: Phase 1, with the scope changes below. Two cheap items can land on
  `coop` first because they change nothing in single player: the
  `GetPlayer`→`Self` fixes inside `TPlayer`, and the lazy ruins proxy.

## What broke, and why

Crude fixes on the spike branch, in the order they were hit:

1. **The ranger AI flies other humans.** `TRanger.NextDay` decides who is
   human with `GetPlayer = Self`, so a second `TPlayer` gets `NextDayLogic`:
   it trades, lands and jumps like an NPC. Spike: skip the AI for any other
   `TPlayer`. The same identity test gates order cancelling
   (`TShip.NextDay`), cargo auto-drop and auto-equip (`TStar.NextDay`),
   stasis mode and ~640 other comparisons in `source/game`.
2. **`TPlayer` methods say `GetPlayer` where they mean `Self`.** 54 uses in
   `aPlayer.pas`. Two crashed or corrupted state:
   `CreateRuinsProxy` creates the proxy in `GetPlayer.CurrentStar` and then
   deletes it from `Self.CurrentStar` (`Delete(-1)`, access violation on the
   first save); `ApplyCharacterPreset` puts starting items into
   `GetPlayer.StorageEntries`, the first human's storage. A third is visible
   in `TPlayer.NextDay` (`GetPlayer.GetTotalStatBonus`). In single player
   `GetPlayer = Self` at every one of these, so replacing them is
   behaviour-preserving and can land before Phase 4.
3. **Saving mutated the galaxy.** `TPlayer.SaveToBuffer` creates the ruins
   proxy lazily, and `TRuins.Init` draws from `Galaxy.RandomState`. A
   player without a proxy therefore changes the RNG state by being saved,
   and hashing it changes the next turn. Spike: create the proxy up front.
   Fix: create it at player creation or load, never in the writer.
4. **Derived stats.** After adding a ranger, `RefreshRangerWealthStats` and
   `RefreshRangerStrengthStats` must run, as new-game setup does; otherwise
   the saved average capital differs from the value a load recomputes.

## Findings that do not crash but decide design

- **Save format already holds N humans.** Every `TPlayer` is written with
  ship tag 255 and loads back as a `TPlayer`. Only "which one is local" is
  singular (`PlayerRangerIndex`). Phase 4 item 5 shrinks from a new block to
  per-human copies of the local-player globals (next point).
- **Local-player state is global, not on `TPlayer`.** `PlayerStar`,
  `PendingPlayerFollowTarget`, `PlayerAutomaticControl`,
  `PlayerEquipmentBrokenThisTurn`, `PlayerOldQuests`,
  `PlayerDialogueRequestCount`, the message bubbles in `Globals.pas`
  (`AddOrUpdatePlayerBubble`, 101 call sites) and `TStar` fields
  `DaysSincePlayerVisit`, `PlayerPresenceLevel`, `PlayerFilmPath`. A second
  human's disease and licence messages go into the first human's bubbles
  today. This is the Phase 2 grouping work that Phase 4 needs.
- **Unseen-death rule.** In `TStar.NextDay` (stage 35), a ranger destroyed in
  a star the local player is not in is relocated by
  `TryRelocateUnseenShip` instead of dying. A second human killed out of
  sight came back at another star with a repaired hull and more money. With
  several humans the test must become "no human in this star"; the routine
  itself is a candidate base for the Phase 6 respawn.
- **Death of the local player is game over.** In hot-seat, the rotated-in
  human was destroyed while local; the ship destructor calls
  `SetPlayer(nil)` and the turn stops ("The player no longer exists"). A
  non-local `TPlayer` destroyed in view is freed cleanly and the game goes
  on (12 more turns, no dangling references found).
- **The turn thread waits for the UI.** Stage 37 of `TStar.NextDay` sleeps
  in a loop until the score screen is dismissed when the player dies. The
  host must not block the day on one human's screen; this belongs in Phase 2
  item 1.
- **Round trip after turns fails in single player too.** Script variables
  such as `CurShip` hold raw addresses (the Phase 0 open issue); after one
  turn, 16–17 of them come back `unresolved`. Diffs were the same kind and
  count with 1, 2 and 8 humans, so extra humans add none. This now blocks a
  meaningful round-trip test and Phase 5 snapshots, so it moves into
  Phase 1.

## Sizing

| Area | Depth | Notes |
| --- | --- | --- |
| Turn loop | shallow | runs with N humans as is; the film and `PlayerStar` split still need generalising (Phase 4 item 2) |
| "Who is human" | deep, mechanical | ~640 `GetPlayer =`/`<>` comparisons and ~790 `GetPlayer.` dereferences in `source/game`; most comparisons become `is TPlayer` or a humans set |
| `TPlayer` self-references | shallow | 54 sites in `aPlayer.pas`, safe to fix now |
| Local-player globals | medium | ~10 globals, 3 `TStar` fields, the bubble list |
| AI reactions | not probed | `aPirate` has one `is TPlayer`; the rest go through `GetPlayer` |
| Scripts and quests | not probed | `aScriptFun` 315 `GetPlayer`, `fPlanetQuest` 93 (text quests are off in multiplayer) |
| Save | shallow | tag 255 already; add per-human local state |
| UI | not probed | `screens/` 3,900 `GetPlayer`, all *local* by construction |

Phase 4 stays **large**, but its risk moves from "the simulation assumes one
`TPlayer` object" (it mostly does not) to "the code tests identity with
`GetPlayer`", which is wide but mechanical and suits the classification table
in Phase 4 item 7.
