# Roadmap: code quality and multiplayer

This is a plan, not a commitment. It is based on a shallow survey of the tree
(unit sizes, the turn loop, the RNG, the observer, `GetPlayer` usage), not a full
audit. Counts are approximate and exist to size the work.

The target is true multiplayer: any number of humans, each flying their own
ranger in one shared galaxy, with a shared victory and optional PvP. No part of
the design may assume a fixed player count. Mixed platforms (Windows, macOS,
any architecture) play in the same game. Spectating is a milestone on the way,
not the goal. The game rules are fixed in Phase 6.

The two goals share most of their early steps. Multiplayer needs a simulation
that can run without the UI, be driven by recorded inputs, and be compared
between two machines. Those same three properties are what the code base lacks
most as ordinary engineering hygiene. Phases 0–3 are worth doing even if
multiplayer is dropped.

## Where the code stands

| Observation | Evidence |
| --- | --- |
| A few units hold most of the game. | `aScriptFun.pas` 659 KB, `aShip.pas` 615 KB, `aGalaxy.pas` 590 KB, `fRuinsTalk.pas` 404 KB. `source/game` is ~87k lines in 23 files; `source/screens` is ~80k in 45. |
| State is global. | `Globals.pas` is 161 KB. `Galaxy`, `PlayerStar`, `TurnCalculationPhase`, `PlayerStarDayPrepared` and the screen table are unit-level variables shared by the UI and the turn thread. |
| There is exactly one human. | [GetPlayer](source/game/aPlayer.pas#L292) returns a single `PlayerInstance` and is called ~5,900 times in 66 files (265 in `aGalaxy`, 206 in `CheatCode`, 130 in `aNormalShip`). |
| The simulation knows about the UI. | 20 of 23 units in `source/game` use screen, `GR_Main` or `GI_*` units: `aSaveLoad` 31 references, `aGalaxy` 30, `aShip` 17. [ProcessPlayerStarTurn](source/game/ThreadCalc.pas#L79) closes screens from the turn thread on error. |
| The turn is split around the player. | [TGalaxy.NextDay](source/game/aGalaxy.pas#L2658) simulates every star except the player's; the player's star runs separately with film recording. |
| Randomness is mostly, not fully, reproducible. | ~840 call sites use per-object seeds ([NextRandomIntRange](source/core/aMyFunction.pas#L252)). ~80 call sites in `game/`, `script/` and `quests/` use the shared [RandomIntRange](source/core/aMyFunction.pas#L193), which draws from the same stream as visuals. Chaotic-random mode sends everything to the shared stream. |
| Float behaviour differs by target. | x86 uses exact x87 math, other targets use OKGF native math ([ADDITIONS.md](ADDITIONS.md)). Bit-identical results across architectures should not be assumed. |
| Decompilation residue. | Untyped `TList` with casts (`TStar(Stars[I])`), numeric kinds (`Bubble.Kind = 3`), `Stage := 13` progress labels, `{$R-}{$Q-}` on every unit, exceptions logged and swallowed around `Free`. |
| No game tests. | The only test is [tools/test_compiler.py](tools/test_compiler.py). |

Two existing pieces make the plan realistic:

- The observer already advances the simulation with no player input:
  [TObserverWorker.Execute](source/observer/ObserverSimulation.pas#L62) runs the
  player-star job, then the galaxy job, with hooks for capture.
- [SaveGameToMemorySnapshot](source/game/aSaveLoad.pas#L549) already serialises
  the whole game to memory. That is a join/resync payload for free.

## Principles

- Behaviour stays identical unless a change is tagged with a `CHANGE:` comment,
  as [BUILDING.md](BUILDING.md) requires. The save layout stays compatible.
- No refactor lands before a test can detect that it changed the simulation.
  Phase 0 exists for that reason.
- Refactor units when a phase needs them, not wholesale. A mass rewrite of
  decompiled code makes the diff against `main` unreadable and buys little.
- Every phase ends with a single-player game that still plays normally.
- Every working session records its progress in
  [docs/progress/](docs/progress/README.md) before it ends. Short notes are
  enough. This file holds the plan; progress does not go here.

## Phase 0 — Safety net (small)

1. **Headless turn runner.** Add `--sim-turns=N --sim-hash` on top of the
   observer path: load a save, park the player, advance N turns, print a state
   hash per turn, exit. No window.
2. **State hash.** Hash the bytes `TGalaxy.SaveToBuffer` produces, minus
   fields known to be presentation-only. Reusing the save writer means no second
   serialiser to maintain.
3. **Golden files.** A few saves (early, mid, late game; one per difficulty
   extreme) with expected hashes for 100 turns, checked per target. Assets and
   saves cannot be redistributed, so these run locally through
   `tools/test.py --game-dir=...`.
4. **Asset-free tests in CI.** RNG functions, `EC_Str`, the expression
   evaluator, `TBufEC`, DAT and package codecs on synthetic input. Add a GitHub
   Actions job: `format.py --check`, Windows build, asset-free tests.
5. **Save round-trip test.** Load, save, compare bytes. This guards every later
   change to `aSaveLoad`, `aGalaxy` and `aShip`.

Exit: running the same save twice on one machine gives the same hashes. If it
does not, the cause is Phase 1 work and is now measurable.

## Spike — Second human (small, throwaway)

Phase 4 is the main risk, so probe it before investing in Phases 1–3. On a
scratch branch that is never merged:

1. Create a second `TPlayer` in a loaded galaxy and register it as human.
2. Run turns with the headless runner and in the game. Fix only what crashes
   or blocks the turn, with the crudest change that works.
3. Record every place that broke and why: turn loop, film, AI, scripts, save,
   UI assumptions.

Output is a note in `docs/progress/`, not code: which subsystems assume one
human, how deep each assumption goes, and a revised size for Phase 4. Adjust
Phase 2 scope from the findings before starting it.

## Phase 1 — Determinism (small to medium)

Networking does not need determinism, since only the host simulates (Phase 5).
Determinism is needed for replay tests (Phase 3) and for localising
regressions. Do items 1–6; item 7 is optional.

1. **Split the RNG.** Give the simulation its own stream
   (`Galaxy.RandomState` already exists) and leave `PresentationRandom` to
   visuals and audio. Audit the ~80 shared-stream call sites in `game/`,
   `script/` and `quests/`; each is either simulation (move it) or cosmetic
   (leave it). This changes random sequences, so tag it `CHANGE:` and regenerate
   golden hashes once.
2. **Chaotic-random mode.** Seed it from the save instead of the runtime so it
   is random to the player but reproducible given the seed.
3. **Remove wall-clock inputs from the simulation.** `AdaptiveBeginCalcNextTurn`
   is timing-driven; confirm it only affects when the job starts, never what it
   computes. Grep for `timeGetTime`, `Now`, `GetTickCount` in `source/game`.
4. **Pin thread ordering.** One turn thread today, which is good. Document that
   the UI thread must not mutate simulation state while
   [TThreadCalc.Execute](source/game/ThreadCalc.pas#L114) runs, and add a debug
   assertion at the main mutation points.
5. **Script references by id.** Script variables hold raw object addresses
   and the save writes them truncated to 32 bits, so after one turn a save
   no longer loads back to the same state, even in single player. Save and
   resolve them as object ids. This also blocks Phase 5 snapshots.
6. **Saving must not change state.** `TPlayer.SaveToBuffer` creates the ruins
   proxy lazily and draws from the galaxy stream. Create it with the player
   and check for other lazy creation in writers.
7. **Measure cross-target drift (optional).** Run the golden saves on Windows
   x64 and macOS ARM64 and record where hashes diverge. Do not try to fix it.
   It only decides whether golden hashes can be shared between targets.

## Phase 2 — Separate simulation from UI (medium, incremental)

Scope this phase to what the test runner and Phase 4 need. The host runs the
full game with its UI and clients receive state, so no client ever runs the
simulation headless; headless running exists for tests. Use the spike's
findings to pick which units to separate, and leave the rest alone.

1. **Events out, not calls out.** Replace direct uses of screen units from
   `source/game` with a small event interface, generalising
   `ObserverHooks`: `OnBubble`, `OnDialogueRequested`, `OnShipDestroyed`,
   `OnFatalError`. The UI subscribes; the headless runner and the network layer
   subscribe differently. Start with `aGalaxy`, `aShip`, `aSaveLoad`.
   The turn thread must never wait on a screen: today it sleeps until the
   score screen is dismissed when the player dies.
2. **Group the globals.** Move unit-level variables into three records:
   `Session` (galaxy, players, turn phase), `Settings` (what `GlobalsV` mostly
   holds) and `UiState`. Same names at first, accessed through the record, so
   the change is mechanical. This makes it visible which globals the simulation
   touches. The local player's state (`PlayerStar`,
   `PendingPlayerFollowTarget`, `PlayerAutomaticControl`, `PlayerOldQuests`,
   the message bubbles and the `TStar` player-visit fields) goes into a
   per-human record, since Phase 4 needs one per human.
3. **Enforce the direction.** Add a check to `tools/` that fails if a unit under
   `source/game`, `source/core` or `source/script` uses a unit under
   `source/screens` or `source/ui`. Start with an allowlist of current
   violations and shrink it.

Smaller clean-ups to fold in when a unit is already open:

- Typed list wrappers (`TStarList` with an inlined `Items[]: TStar`) instead of
  casts. Keep them thin so the RTL list inlining from the performance work still
  applies.
- Named enums for numeric kinds (`Bubble.Kind`, order states, message types).
- Drop `Stage := n` labels where `LogExceptionBackTrace` now gives the line.
- Turn on `{$R+}{$Q+}` in debug builds for new units only. The decompiled units
  rely on wraparound.
- Split the largest units by responsibility (`aShip`: combat, equipment, save;
  `aGalaxy`: generation, turn, economy, save). `aScriptFun` could become one
  registration table per domain.

## Phase 3 — Player commands (medium)

Every change a human makes to the simulation goes through one serialisable
command: set course, attack, land, take off, jump, buy, sell, equip, drop,
dialogue choice, government action, end turn.

1. Define `TPlayerCommand` (kind, actor ranger id, target ids, integers) with
   binary encode/decode through `TBufEC`.
2. Route the UI through `Session.Submit(Command)`. Object references become
   stable ids; check that every ship, planet, item and star has one in the save
   format, and add a lookup where missing.
3. Add a command log: `--record-commands` and `--replay-commands`. With Phase 0
   this gives real gameplay regression tests, which is the largest quality gain
   in this plan and is independent of networking.

Exit: a recorded 30-minute session replays headlessly to the same final hash.

## Phase 4 — More than one human (large)

1. **Split `GetPlayer`.** Introduce `LocalPlayer` (whose screen this is) and
   `Session.Humans` (who is human in the simulation). Migrate the ~5,900 call
   sites by directory: `screens/`, `ui/`, `arcade/` become `LocalPlayer`
   mechanically. `game/`, `script/` and `quests/` need a decision per site:
   "this human", "any human" or "every human".
2. **Turn structure.** `NextDay` skips one player star and one film is
   recorded. The film is the recording of the day that the star view plays
   back as the turn animation, so every star that holds a human needs one.
   Generalise to that set of stars; all humans in one star share one film. A
   day runs only when every human has pressed end turn (see Phase 6).
3. **NPC reactions.** AI in `aNormalShip`, `aPirate`, `aWarrior` reasons about
   "the player". `TPlayer` derives from the ranger hierarchy, so most logic can
   take the relevant human as a parameter.
4. **Scripts and quests.** Script functions that mean "the player" need a bound
   human per script instance. Default: the human who triggered the script.
5. **Save format.** Every `TPlayer` is already saved and loaded as one (ship
   tag 255), so extra humans need no new block. Add the per-human copy of
   the local-player state from Phase 2 as an additive block; a save with one
   human stays loadable by the original layout rules.
6. **No fixed player count.** `Session.Humans` is a list, not an array with a
   maximum. Per-human state (relations, reputation, messages, quest bindings,
   film viewpoint) lives on the human or in maps keyed by human id, never in
   `[0..MaxPlayers]` tables. Human ids are stable and never reused within a
   game, so commands, saves and logs can refer to a human who has left.
   Joining and leaving mid-game are normal operations, not special cases.
7. **Classify every `GetPlayer` site.** Each of the ~5,900 sites gets one of:
   *local* (whose screen, UI only), *actor* (the human performing this
   action or triggering this script), *each* (loop over all humans: day
   ticks, galaxy messages, victory checks), *any* (a condition true if some
   human qualifies: "is a human in this star"), or *nearest/target* (AI
   choosing which human to react to). Record the class in a tool-readable
   table so progress is measurable and review can check each decision.
8. **Humans as targets.** Targeting, weapons and AI code must treat another
   human like any other ranger when friendly fire is on, and refuse the
   target when it is off. Attacking a human applies the same reputation and
   law consequences as attacking an NPC ranger.
9. **Respawn.** A destroyed human respawns at the nearest planet instead of
   ending the game (see Phase 6). Single player keeps the original game over.
   `TryRelocateUnseenShip`, which already moves rangers destroyed where the
   player cannot see, is a starting point; its "not the player's star" test
   must become "no human in this star".
10. **Session flags.** Text quests off, friendly fire on/off, cheat tracking.
    Each flag is part of the saved session, and changing one is a command so
    every machine sees the change at the same point.

Test without a network: hot-seat on one machine, driven by one command log per
human. Run the suite with 1, 2 and a larger count (8 or more) so that code
which quietly assumes "one or two" fails a test.

## Phase 5 — Networking (medium)

Model: **host-authoritative, state streaming.** Only the host runs the day.

- Clients send commands to the host. Commands issued between days (buy, sell,
  equip, set course) are applied by the host at once and also applied locally
  on the client, so the UI responds without waiting. The client's local copy
  is a prediction; the host's state always wins.
- When every human has pressed end turn, the host runs the day, then sends
  each client the new state and the film for the star that client is in.
- State goes as a delta against the last snapshot that client acknowledged,
  compressed; a full snapshot only on join or when a client has no base. The
  save writer is the serialiser, so no per-object replication code is needed.
- Joining is the same path: the host sends a full snapshot.
- Deltas are computed on the uncompressed state. Compressed bytes change
  almost entirely even when little in the game changed, and a byte-for-byte
  diff breaks when lists change length. Use a diff that handles inserted
  bytes, such as zstd's `--patch-from` mode (the previous state as the
  reference), as one C library next to the native code.
- Order per day: the film first (small, needed immediately), then the state
  delta, which streams while the animation plays.

**Applying state on the client.** Screens hold direct references to ships,
planets and items. Loading new state frees those objects, so it must happen
only at a safe point:

- Apply new state only at the end of the day's animation, never mid-screen.
- Before applying, every open screen drops its object references and keeps
  ids instead; after applying, it looks them up again or closes.
- A debug build poisons freed objects so a stale reference fails at once
  instead of later.

Milestone 1 tests this, not only transfer sizes.

Why this and not lockstep: mixed platforms are required, and x87 and native
float math do not produce bit-identical results, so lockstep across targets
would desync constantly. State streaming also cannot desync at all, which
matters in a decompiled code base. The cost is bandwidth, measured in
Milestone 1. Lockstep between same-target clients remains a possible
optimisation later, not a requirement.

Implementation notes:

- TCP is enough; the game is turn-based. Put sockets in `platform/` next
  to the SDL layer (SDL_net or plain BSD/Winsock behind the existing C shim) and
  keep Pascal code transport-agnostic.
- Length-prefixed messages: `Hello(version, protocol, data hash)`,
  `Snapshot`, `StateDelta(day)`, `Film(day, star)`, `Command`, `Ack(day)`,
  `EndTurn`, `Chat`.
- Refuse connections when the protocol version or game-data/mod hashes
  differ. Build hashes may differ, since platforms differ.
- Direct IP and LAN first. No matchmaking, no NAT traversal.
- The host's upload grows with the number of clients. Clients in the same
  star get the same film: encode it once and reuse the bytes.
- There is no turn timer, so a human who disconnects must not block the day
  forever. A disconnected human counts as having pressed end turn and their
  ranger holds position; they rejoin through the snapshot path.

## Phase 6 — Multiplayer game rules (decided)

Decided with the project owner. Later versions may revisit any row.

| Question | Decision |
| --- | --- |
| Player count. | Unlimited. |
| When does a day pass? | When every connected human has pressed end turn (the play button), including docked humans. No turn timer. |
| A human is in a shop or dialogue. | No time passes. The day waits for their end turn like everyone else's. |
| Text quests. | Disabled in multiplayer. Not offered while the session flag is set. |
| Hyperspace arcade and black holes. | Solo instance, local to the human who entered. Because the day waits for everyone, the others wait until that human finishes and presses end turn. Shared instances are a future version. |
| Robot battles. | Already automatic victories, so nothing to sync. |
| PvP. | Allowed. A friendly-fire switch in the settings menu turns it off and on at any time during the game; the host owns the switch. |
| Game end. | Coalition victory is shared. A destroyed human respawns at the nearest planet. What they lose on death is to be tuned later. |
| Cheats. | Enabled for everyone. Cheat commands carry the actor, and the host sees which humans have used which cheats. |
| Mods. | Same mod set on every machine, enforced by the data hash in `Hello`. |
| Balance. | No scaling with player count. Quest supply, economies and war pacing stay as in single player. |

## Order and sizing

| Phase | Size | Useful without multiplayer |
| --- | --- | --- |
| 0 Safety net | S | Yes |
| Spike: second human | S, throwaway | No |
| 1 Determinism | S–M | Yes |
| 2 Sim/UI separation | M, incremental | Yes |
| 3 Commands and replay | M | Yes |
| 4 Multiple humans | L | No |
| 5 Networking | M | No |
| 6 Rules | decided | No |

Phase 4 is the expensive one. The spike
([findings](docs/progress/2026-09-24-spike-second-human.md)) showed that the
simulation already runs with many `TPlayer` objects; the cost is in code that
tests identity with `GetPlayer = Self`, which is wide but mechanical. Phase 6 is
settled, so Phase 4 can classify call sites against fixed rules.

## Milestones

Each milestone is playable and ships on its own.

1. **Spectator (after Phase 0 and the transport half of Phase 5).** The host
   sends `SaveGameToMemorySnapshot` after each turn; clients load it into the
   observer. Clients never simulate, so this needs no determinism, commands or
   `GetPlayer` changes. It proves the socket layer, the handshake and snapshot
   delivery, and it measures snapshot size, delta size, film size and load time
   on real saves across platforms. It also replaces the client's galaxy every
   day, which tests the safe-point rules in Phase 5 before any gameplay
   depends on them.
2. **Replayable single player (after Phases 1–3).** A recorded session replays
   headlessly to the same hash. This is the regression gate for Phase 4.
3. **Hot-seat multiplayer (after Phase 4).** Any number of humans on one
   machine, driven by one command log each in tests. All multi-human logic,
   PvP and respawn are exercised without a network.
4. **Networked multiplayer (Phase 5 complete).** Host-authoritative state
   streaming across mixed platforms.

## Risks

- **Stale object references on clients.** Replacing the galaxy every day frees
  objects that screens still point to, which gives crashes that are hard to
  reproduce. Mitigation: the safe-point rules in Phase 5, poisoned frees in
  debug builds, and Milestone 1 exercising the path daily.
- **Bandwidth and client load time.** A save is about 11 MB compressed. Sent
  in full every day, that is ~0.1 s per client on gigabit LAN but ~4.5 s per
  client on a 20 Mbit home upload, so full daily snapshots are not viable over
  the internet. Deltas (Phase 5) are expected to be a few hundred KB to 1–2 MB;
  this is a guess until Milestone 1 measures it. Many clients on one slow host
  upload remain the practical limit of "unlimited players".
- **Undiscovered nondeterminism** (uninitialised memory, pointer ordering,
  list iteration that depends on addresses). It no longer breaks networking,
  but it breaks replay tests. Mitigation: the per-turn hash, plus a debug mode
  that hashes after each star to localise the first difference.
- **One slow human stalls everyone.** No timer is a deliberate choice; arcade
  and black-hole sessions make the waits longest. Show every human who the
  day is waiting for.
- **Script and quest content assumes one player** in ways only visible in game
  data, not source. Mitigation: bind scripts to the triggering human and accept
  some single-player-flavoured text in multiplayer.
- **Diff growth against `main`.** Mitigation: mechanical renames in separate
  commits from behaviour changes.
- **Turn cost grows with the number of humans.** Every star that holds a human
  is simulated with film recording, so humans spread over many stars make each
  day slower than single player. Measure turn time against human count with
  the headless runner.
- **Game balance with many humans.** Balance is deliberately not scaled, so
  many humans can drain quests or end the war early. Accepted for now.
