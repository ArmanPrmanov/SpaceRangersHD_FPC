# Player commands

Every change a human makes to the game goes through a command (ROADMAP.md,
Phase 3). A screen builds a command and submits it. The command's executor,
in the game layer, does what the screen used to do itself. The command log
records the command, and the headless runner replays it.

- `source/game/aCommands.pas`: the command record, its encoding, and
  `SubmitCommand` / `ExecuteCommand`.
- `source/game/aPlayerActions.pas`: travel, orders and the day. This is the
  model to follow.
- `source/CommandLog.pas`: the recorder (`--record-commands=PATH`) and the
  headless replay (`--replay-commands=PATH`). Several logs, one per human
  (`tools/split_commands.py`), replay merged in hot-seat order
  ([humans.md](humans.md), End turn and hot-seat).

## Converting a UI action

1. **Find what changes the game.** This means writes to galaxy objects, the
   player, `LocalHuman` fields the simulation reads, and `Session`. It also
   includes calls that run scripts: `ScriptItemsAct`, `RunTurnCode`,
   `RunActionCode`, `CallDialog*`, `ExecuteDialogAnswer`. Many are implicit:
   look at `OnOpen`, `OnClose`, hover and refresh code, not only buttons.
   Pure presentation (images, sounds, scroll, which panel is open) stays in
   the screen.
2. **Move the change into an executor.** Move the code verbatim. The
   executor gets the acting ranger from the command (`Actor(Command)`),
   never from the screen. It must not touch controls.
3. **Pass inputs as arguments.**
   - Objects are passed by id with `AddRef`: stars, planets, ships, items,
     holes, constellations, asteroids and missiles.
   - Items in the open shop's grid (`LocalHuman.TemporaryShopSlots`) are in
     their planet's or station's list; the grid is the human's view of it
     ([humans.md](humans.md), Shops). Pass the slot index plus the item id. The
     executor finds the item by its id in the shop's stock
     (`aShopActions.ShopItemArg`) and refuses with `rrItemGone` when it is
     gone; the slot only places it in the actor's grid.
   - Integers go in with `AddInt`, floats with `AddFloat`/`AddPoint` (sent
     bit for bit), and text with `Command.Text`.
   - A value the screen computed from UI state, such as a layout width or a
     quote shown in a dialog, travels in the command. A value computed from
     game state is computed again in the executor. An executor keeps such a
     value in the actor's `THuman`, never in a global this machine's screen
     reads (the shop's columns, `THuman.ShopColumnCount`).
4. **Keep decisions where they were.** The screen may still decide which
   command to send from what the player selected. The executor redoes
   checks that depend on game state, exactly as the screen did.
5. **Return results through a unit variable.** An example is
   `ScriptItemsActResult`. The screen reads it right after
   `SubmitCommand`.
6. **Keep the order of effects.** If a screen changes the game, shows a
   dialog, then changes it again, that is two commands with the dialog in
   between.

Each actions unit declares its kinds as constants in its own range and
registers them in `initialization` with
`RegisterCommand(Kind, 'Name', @Executor)`. Never renumber a kind: the
numbers are part of the log format.

| Range | Unit |
| --- | --- |
| 0–99 | `aPlayerActions`: travel, orders, the day, session flags (42 `SetSessionFlag`), end turn (43 `EndTurn`, 45 `StopContinuing`), joining (44 `JoinHuman`), a disconnected human holding position (46 `HoldPosition`) |
| 100–199 | shops: equipment, goods, hangar |
| 200–299 | the ship and hold screen (`fShip2`), awards (`fRewards`, 250–252) |
| 300–399 | conversations (`fTalk`, script dialogs) |
| 400–499 | planets and the government (`fGov`, `fPlanet`, `fPlanetNO`, `fInfo`, `fJournal`) |
| 500–599 | stations (`fRuinsTalk`) |
| 600–699 | text quests, arcade battles, cheats, UI scripts |

Behaviour stays identical. Tag deliberate changes `CHANGE:` (BUILDING.md).

- **Changing a command's arguments.** The log stores the integers and
  references a command had, and old logs must still replay. Add arguments at
  the end, and let the executor treat a command without them as the old one did
  (`Length(Command.Ints)`, `Length(Command.Refs)`). So far:
  - `BuyMap` (413) names the constellation the government offered (a
    reference); without it the map is the first uncharted neighbour, as before.
  - `BuySatellite` (552) carries the offer's item id and the price shown;
    without them it buys the offer as it stands, as before.

## Threads

- The UI thread submits commands while no turn job runs. It also submits
  them while the turn thread waits for it, which happens during a
  conversation (`BeginTurnWaitForUi`).
- A command submitted on the turn thread is part of the job and is not
  recorded. The exception is a remote human's answer to a dialogue: the host's
  turn thread submits its client's commands with `InTurnJob` off, so they are
  recorded in the talk's wait as a local human's answer is
  ([network.md](network.md), Remote dialogue).
- **The actor.** `NewCommand` makes a command of the local human: the UI
  submits for the human at this machine. A command submitted while another
  one executes (`ActingHuman` is set), or on the turn thread, is for the human
  whose code runs: the human of the running script code (`ScriptHuman`), else
  the executing command's actor. So a command nested in a client's command on
  the host is the client's human's, as it is on the client. The command log
  records only the outermost command; a replay submits the nested ones again
  by the same rule.
- `SubmitCommand` tells `BeforeCommandHook` and `AfterCommandHook` (the command
  log) and then `NetworkCommandHook` (a client sends the command to its host,
  [network.md](network.md)). `NetworkCommandHook` hears only a command submitted
  while none executes on that thread: the host rebuilds the nested ones by
  executing the outer one, as a replay does. A command that raises tells `CommandFailedHook`
  instead of the last two and the exception goes on to the caller; the log
  does not record it (the replay would raise too), and the next boundary
  writes a checkpoint for whatever it changed before it raised.
- An executor that refuses a command for a reason the player should hear
  raises `ECommandRefused` with a `TRefusalReason` (out of stock, not enough
  money, the item is gone, the offer is gone, the target has changed, no room);
  a host tells the client why ([network.md](network.md), Commands). Where
  another human's command between days can change what a screen offered (a
  shared shop, a one-off offer, a station's order, a constellation's map), the
  executor checks again what the screen checked before it offered it, and
  refuses before its first change. Raise it only before the executor's
  first change: the log writes no checkpoint after such a command (the next
  boundary still does if the hash changed). Never show a message box from an
  executor: on a host it would block the day.
- Keep the `aCalc.WaitForTurnCalculationUI` calls the screen already makes
  before changing the game.

## Checking a conversion

- `python tools/build.py --target windows`, `python tools/unit_tests.py`,
  `python tools/check_layers.py`.
- `python tools/test.py --game-dir=...` runs the save tests and replays
  `tests/replays/*.srcl`. The goldens must not change.
- The recorder hashes the state after each command and before the next one.
  If the two differ, something that is not a command changed the game. The
  recorder then writes a checkpoint and names the screen that was open.
  Replaying a recorded session (`--replay-commands=... --replay-verbose`)
  lists them. Checkpoints and `diverged` records are what is left to
  convert.
- Game state the save leaves out, such as a path or a cache, is not in the
  hash. A missed change to it shows up later as a divergence after a job.
