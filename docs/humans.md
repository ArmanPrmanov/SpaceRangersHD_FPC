# Humans

The game has any number of humans, each flying their own ranger in one galaxy
(ROADMAP.md, Phase 4). The decompiled code has one: `GetPlayer`. This page says
how code refers to humans instead, and how to convert a `GetPlayer` site.

## The model

- A **human** is a `THuman` (`source/game/aHuman.pas`). Its ranger is
  `Human.Player`, a `TPlayer`. Its id is the ranger's ship id, which is never
  reused within a game.
- **Every `TPlayer` in the galaxy is a human**, and nothing else is.
  `IsHuman(Ship)` is `Ship is TPlayer`.
- `Session.Humans` lists the humans in join order. Loops over humans use this
  order, so runs repeat.
- `LocalHuman` is the human at this machine, and `LocalPlayer` is its ranger:
  whose screen this is. They exist for the UI. The simulation must not depend
  on which human is local: on a host, the local human is just one of several.
- Per-human state lives on `THuman`, for example the star whose day is
  filmed, the message bubbles, the open shop, the conversation, the hold
  order, the item held on the ship screen's cursor and the government
  negotiation. `HumanOf(Ship)` finds the human for a ranger.
- **The ship screen.** `THuman.EditedShip` is the ship whose screen the human
  has open, from `OpenShipScreen` to the `CloseShipScreen` that leaves it (also
  while the screen is closed to show another one and comes back). One human at
  a time edits a ship that is not its own ranger (a sponsored station's): another
  human's `OpenShipScreen` is refused (`rrInUse`), since the screen lends the
  ship the editor's experience until it closes. `THuman.ReleaseShipScreen`
  gives the experience back and frees the ship for a human whose machine will
  not close it: `HoldPosition` (a disconnect), a respawn and leaving the game;
  a load forgets it. It is not saved.
- `Actor(Command)` and `ActorHuman(Command)` are the human who issued a
  command. Executors use them, never `LocalHuman`.

| Name | Meaning |
| --- | --- |
| `LocalPlayer`, `LocalHuman` | the human at this machine (UI only) |
| `Actor(Command)`, `ActorHuman(Command)` | the human who issued the command |
| `ActingHuman` | the human whose command is executing; nil outside a command |
| `ScriptHuman`, `ScriptPlayer` | the human of the script code that is running, and its ranger; nil outside script code |
| `BoundHuman(Script.HumanId)` | the human a script is bound to |
| `HostHuman` | the first human in `Session.Humans`: whoever created or hosted the game; nil when there are no humans. Galaxy-wide rules that used to read the one player (NPC catch-up, which star the dominators spare, whose home sets the distance tiers, the shop stock or a loot/reserve scale with nobody acting) follow this human. With one human it is that human. |
| `ContextHuman` | the human in context: `ActingHuman`, else `ScriptHuman`, else `HostHuman`; nil when there is none. Used where a site means "the human this code is working on behalf of" but is neither strictly inside a command nor strictly inside script code (an artefact's weight, a default hull's race or a satellite's owner, `<Player>` in localized text). With one human it is that human. |
| `Session.Humans` | every human |
| `IsHuman(Ship)` | whether a ranger is a human's |
| `HumanOf(Ship)` | the `THuman` of a human's ranger, or nil |
| `StarHasHuman(Star)` | whether some human's ranger is in the star |
| `StarHasHuman(Star, Ship)` | the same, not counting `Ship`, for example a human who is party to a talk others overhear |
| `StarHasHumanInSpace(Star)` | whether some human's ranger is in the star in normal space, where it sees the fights |
| `FilmHuman(Star)` | the human whose view the star's shared film follows (radar range, film path, camera): the local human when it is in the star, else the first human there; nil when none is |
| `HasLivingHuman` | whether some human's ranger still has hull points; the day stops when none does |
| `IsMultiplayer` | whether the game has more than one human, so the multiplayer rules of ROADMAP.md, Phase 6, apply (see Respawn) |
| `Human.Finished` | whether the human's game has ended while others play on (see Respawn) |
| `FindHuman(Id)` | the human with that id, or nil |
| `IsRuinsProxy(Station)` | whether a station is some human's ruins proxy, the storage station that is not part of the galaxy |
| `Human.AddOrUpdateBubble(...)` etc. | that human's message bubbles; the `Globals` functions of the old names are the local human's |
| `JoinHuman(Planet, Name, Preset)` | adds a human landed at a planet; the `JoinHuman` command (`JoinHumanAt`) does it so that a log replays it |
| `HumanHoldsDay(Human)`, `AllHumansEndedTurn`, `NextHumanToEndTurn` | the end-turn barrier (see End turn and hot-seat) |
| `SetLocalHuman(Human)` | hot-seat: another human becomes the local one; `Session.Humans` stays |

## Scripts

Every script instance (`TScript`) is bound to one human, `TScript.HumanId`, and
its code runs for that human.

- **Binding.** A script binds when it starts from its template
  (`TryStartScriptInstanceFromTemplate`) to, in order: the human of the script
  code that starts it (`ScriptHuman`), `ActingHuman`, the human the start is
  about (the `About` parameter: the human arriving in the star or landing), or
  the first human in `Session.Humans`. `RunGlobalScriptsForContext` takes the
  human it runs for; commands pass the actor and screens the local human. A
  restarted script keeps its human. `BoundHuman(Id)` gives the first human
  when the bound one has left. The per-human save block holds the binding
  (see Saving).
- **Context.** `ScriptHuman` is the human of the code that is running. Every
  entry into script code sets it and restores the previous value, so nested
  runs nest:
  - a script's own code (init, turn, dialog, answer, state, ship action code,
    the template condition, `RunFunctionFromScript`) and its loading run for
    its bound human; a template's condition runs for the human the script
    would bind to;
  - item code (`ScriptItemsAct`, `RunItemUseCode`, the artefact and
    custom-info action code) runs for the human whose ranger holds the item,
    else for the item's script's human, else as code of no script;
  - code of no script (`ExecuteScriptText`, gameplay UI code) runs for
    `DefaultScriptHuman`: the running script code's human when nested, else
    `ActingHuman`, else the first human.
- With one human every script is bound to it and `ScriptPlayer` is
  `GetPlayer`.

Converting the script functions (`aScriptFun`):

- "The player" is the script's player, `ScriptPlayer` (`ScriptHuman.Player`):
  `Player()`, the journal, the storage, programs, equipment sets, the
  `<Player>` text, the player's star in `Ether`. Messages and ether bubbles go
  to the script's human (`ScriptHuman.AddOrUpdateBubble`), as other bubbles go
  to their human. The open shop a script reads or changes is the script's
  human's; a change to a shop's stock rebuilds the other humans' grids there
  (see Shops).
- "Is this ship the player", `Ship = GetPlayer`, is decided per function:
  - The script asks whether a ship is its own player, as in `IsPlayer(ship)`
    or a star requirement of the player: `Ship = ScriptPlayer`. Most scripts
    are single-player content asking about their own player, so this is the
    default when the script logic means "my player".
  - The test only guards reading or writing `TPlayer` state of the ship it
    was given (kill counts, experience by type, pirate clan, ruins mode, a
    human's script bindings in `ScriptShipBindings`): `IsHuman(Ship)` and
    `TPlayer(Ship)`. Per-human state of that ship's human (the pending
    follow target, the open shop) is `HumanOf(Ship)`'s.
  - The test keeps human rangers out of NPC handling (group candidates, the
    NPC branch of a drop): `IsHuman(Ship)`.
- `GetPlayer.RuinsProxy = Ship` is `IsRuinsProxy(Ship)`; where the proxy's
  ranger is needed, `RuinsProxyOwner(Ship)`.
- UI builtins (dialogues, dialogue text and answers, screens, the star map's
  path overlay, sounds, the arcade ship, Steam achievements) stay on the local
  human (`LocalPlayer`, `LocalHuman`). A script's dialogue is not sent to a
  remote human's client ([network.md](network.md), Remote dialogue, says why);
  an NPC's offer or demand is. Text quests are off in multiplayer (ROADMAP.md,
  Phase 6), so they follow the local human.
- **Script code of another human.** On a host, a client's commands run its
  script code with `ScriptHuman` its human; so does script code bound to
  another human, in the day or in someone else's command, and in hot-seat
  script code of a human whose turn it is not. Its game effects happen for
  that human; nothing touches this machine's screens, boxes, video or music,
  or the local human's state. The human's own machine shows the UI when it
  runs the same command on its prediction.
  - `aScriptFun.ScriptUiAllowed` decides for the UI builtins: only script
    code of the local human (or of no human) may show UI, and a modal one
    (a box, a child or custom form) never on the turn thread. Otherwise the
    builtin gives a declining player's answer and `Rangers.log` gets
    `Script <builtin> for human N: not shown on this machine, default answer`:
    `MessageBoxYesNo` no (0), `CountBox` and `NumberBox` `'Cancel'`,
    `TextBox` its default text, `ListBox` -1, `OpenCustomForm` and
    `RunChildForm` 0, `CurrentForm` `''`, `FormCurShip` and the star map's
    position 0, `UICheckElement` and the custom form's queries 0 or `''`;
    `MessageBox`, `FormChange`, `UpdateFormShip`, `ButtonClick`, `SetFocus`,
    the custom form's changes, the star map's view, selection and message,
    the music and `ScriptActionsRun` do nothing.
  - `DText`, `DAddText`, `DAnswer` and `InjectAnswer` pick the dialogue
    screen from the script's ranger and write it only for the local human.
    For another human, `DAnswer 'exit'` still ends its ruins mode
    (`TPlayer.CloseRuinsMode`), `'main'` still leaves the script dialogue, and
    `'exit_end'` leaves `Session.GameEndReason` alone (the human's own machine
    sets its own); `InjectAnswer` still records the injected answer. The
    dialogue state itself (`Session.ScriptDialogIndex`, `CurrentScript`, the
    injections and overrides) is still one for all humans.
  - `FormShipCurItem` reads and changes the script's human's held item
    (`THuman.SelectedHoldItem`); only the local human's ship screen is
    redrawn.
  - `CustomWin` and `CustomLose` end the game for the script's human only in
    multiplayer, as `EndGame` does (Respawn and game end).
  - `GetTalkShip`, `GetTalkType` and `TalkByAI` read the talk of the human
    whose command runs (the one talking), else the script's human's, else the
    local human's. The script's human is not first: a ship's script can be
    another human's than the talker's.
  - `ExtremalTakeOff` and `ForceNextDay` set the script's human's
    `THuman.ScriptTakeoffRequested` and `ScriptEndTurnRequested`. Only the
    local human's are dispatched (`aScript.DispatchPendingScriptRequests`);
    `OrderScriptTakeoff` and `ClearScriptEndTurn` clear their actor's. They are
    UI requests and are not saved.
  - Queued arcade and planet battles and videos carry their human
    (`HumanId`). A request is queued when its human is local or the code runs
    in that human's own command (`aScript.MayQueueScriptRequest`): then the
    human's own machine runs the same command, shows the request and reports
    the outcome (`ArcadeBattleExit`, `FinishQueuedPlanetaryBattle`,
    `FinishQueuedVideo`), and the report finishes its actor's request. Any
    other request is not started: `StartAB` answers 0 and the status
    variables stay as they were. This machine shows only the local human's
    requests (`LocalScriptRequest`). Robot battles are automatic victories in
    any case (ROADMAP.md, Phase 6). A video for a human who is not local while
    that human's ship screen shows (`THuman.ShipScreenShown`, set by its own
    `OpenShipScreen` and cleared by `CloseShipScreen`) is not queued: the
    human's machine plays it at once on the ship screen and reports nothing,
    as single player sets no status for it.
  - Leaving or entering ruins mode opens the ruins or return screen only for
    the local human's ranger (`TPlayer.EnterRuinsMode`,
    `CloseRuinsModeScreen`).
  - A command that script code submits while a command executes, or on the
    turn thread, is the script's human's, else the executing command's
    actor's ([commands.md](commands.md), Threads).

## Respawn and game end

The multiplayer rules (ROADMAP.md, Phase 6) apply when `IsMultiplayer`:
`Session.Humans.Count > 1` at the moment it is asked. With one human the game is
single player and keeps the original rules; the goldens check that. A human whose
game has ended still counts, so the rules do not switch back when one finishes.

**Death.** The damage that takes a human's ranger to zero hull (weapon, missile,
interceptor, asteroid, explosion, star heat, a destroyed station it is docked
to) calls `TShip.RecordHumanDeath`. It adds the `PlayerDeath` event with the
cause, which names the human (`TGalaxyEvent.HumanId`). With one human it also
records the game result, as native does. The kill counts for the killer as any
ranger kill: hull kills, rank points, reputation.

**Respawn.** The ranger stays in the star, destroyed, until the end of the
star's day (`TStar.NextDay`, where destroyed ships are freed). The film has then
shown the fatal hit. In multiplayer the ranger is not freed there:

- `TShip.FindRespawnPlanet` picks the nearest planet that takes it, by the rules
  `TryRelocateUnseenShip` moves unseen rangers by: a planet of a race or of the
  pirates, in a coalition star without a battle or a script faction, and not
  hostile to the ranger. The ranger's own star counts as nearest; there the planet
  nearest to the ranger wins. When no star passes, any star with such a planet
  will do.
- The ranger leaves the film as a landing ship does (detached, graphics kept).
- `TShip.RespawnHuman` clears what the ranger's destruction would have cleared
  in other ships (enemy and truce targets, orders to it, interceptors, missiles,
  weapon targets, follow and land orders in the star) and its own orders and
  targets. Partners and ships docked to it stay. The shop grid it had open
  closes (the stock never left the shop). The hull is repaired; equipment, cargo,
  money and quests are kept.
- It lands at the planet. In another star it travels through
  `Galaxy.ShipsInTransit` at the end of the turn job, like a ship that jumps. The
  human's `PlayerStar` follows, and the human gets a bubble
  (`Multiplayer.Respawned` in the language data, English when missing).

Only when no planet at all takes it is the ranger freed: the human leaves
`Session.Humans` (`RemoveHuman`) and the others stay. For the local human that
is the game over on this machine. `SetPlayer(nil, ...)`, which forgets every
human, is left for clearing the galaxy.

**Script game end.** In multiplayer a quest script's `EndGame` ends the game for
the script's human only (`FinishHuman`): `Finished` and `FinishReason` (the
reason `EndGame` gave, or -1 for the ending with the credits) are set, the
ranger holds position, the human counts as having ended its turn, and
`ExecuteCommand` refuses its commands. It stays in `Session.Humans`. The ending
shows only when that human is the local one. With one human `EndGame` is as
native.

## PvP

Humans may fight each other (ROADMAP.md, Phase 6). The host's friendly-fire switch,
`Session.FriendlyFireEnabled`, turns it off and on at any time. One rule decides:
`CanHumanAttack(Attacker, Target)` (`aHuman`) is false when both are humans' rangers,
different humans, and friendly fire is off; true otherwise. A missile or a tranclucator
attacks for its owner ship. NPCs attack humans as always, and a human attacks NPCs as always:
the switch is about one human against another. With one human the rule is always true, so
single player does not change.

Where it applies, with friendly fire off:

- **Orders.** `OrderAutoBattle`, `SetPendingFollowTarget`, `SetWeaponTargets` and
  `SetInterceptorTarget` on another human are refused (the command changes nothing).
  `OrderFollow` at weapon range (mode 1) becomes a plain follow (mode 0).
  `TPlayer.CanSelectShipTarget` is false for another human, so the star map offers a follow,
  not an attack, and a ship in a talk does not offer a joint attack on it.
- **The auto-battle target.** `ProcessPendingPlayerFollowTargeting` drops a target the rule
  refuses before it aims.
- **Automatic control and AI.** A human's ranger on automatic control flies the NPC ranger
  logic; it does not pick another human as its enemy (`SelectEnemyShipInStar`, the partner's
  enemy), aim at one (`TRanger.AssignWeaponTargetsInStar`, including the chameleon pass) or
  go after one (`EngageEnemyShip`). NPCs do not ask a human to join an attack on another human
  (`RequestAlliesAttackShip`), and a joint attack (`SetJointAttackTarget`) leaves out the
  human side that may not attack. Interceptors do not pick another human
  (`SelectInterceptorTarget`) or keep one set by hand (`LaunchInterceptors`).
- **Firing.** A weapon aimed at another human does not fire, whatever aimed it: the star's
  combat step drops the target (`TStar.NextDay`, where weapon targets become combat events).
- **Damage.** A hit does nothing, not even a reaction, when the rule refuses it:
  `ApplyWeaponHit`, `ApplyMissileHit`, `ApplyDamage` (interceptors, script damage) and
  `ApplyExplosionDamage`. Area damage follows the same rule: splash around another target, a
  bomb, cistern or mine a human's shot or missile set off, return no damage to another human.
  An explosion nobody set off hurts everyone as before.

**The switch.** `SetSessionFlag` is a command, so every machine sees the change at the same
point. When friendly fire turns off, its executor drops at once every attack the rule now
refuses (`DropRefusedHumanAttacks`): each human's weapon and interceptor targets, auto-battle
target and enemy on another human, and a follow at weapon range becomes a plain follow. Missiles
already in flight stay, but their hits do nothing. When it turns on again, nothing is restored;
humans give new orders.

**Consequences.** With friendly fire on, a human is a ranger like any other to the one who
attacks it. Each hit makes the target react (`ReactToAttack`: its enemy, and its relation to
the attacker and the attacker's partner). While the attack goes on, nearby NPC ships, military
ones included, judge the attacker by their relation to the target
(`UpdateRelationsForNearbyCombat`). A kill changes
the attacker's standing across the galaxy (`ApplyAttackReputationChanges`: ships and coalition
planets, the pirates' main planet, the target's home planet) and counts as a ranger kill
(`ProcessShipKill`: `RangerKillCount`, awards, the `PlayerKillsShip` event). The dead human
respawns as any destroyed human does (see Respawn). None of this needed a change: the code
already applied it to whichever ranger was hit.

**Relations between humans** are ranger relations (`RangerRelations`). A joining human
(`JoinHuman`) starts from `TRanger.InitializeAtPlanet`, as an NPC ranger does: every ranger's
relation to it and its relation to every ranger is the default between their races
(`OwnerRelations`). Attacks and kills change them as between NPC rangers.

## End turn and hot-seat

A day runs only when every human who plays has pressed end turn (ROADMAP.md, Phase 4,
item 2, and Phase 6). There is no turn timer; a human in a shop or a dialogue holds the day
like everyone else.

**The barrier.** `HumanHoldsDay(Human)` (`aHuman`) is true while the human's ranger plays and
the human has not ended its turn (`THuman.EndedTurn`). A finished human never holds the day,
nor does one whose ranger is in hyperspace: a jump is travel that goes on until arrival,
nor a disconnected one (`THuman.Connected`, session state that is not saved; see
[network.md](network.md), Disconnects).
`AllHumansEndedTurn` is true when no human holds the day, and `NextHumanToEndTurn` is the
first human in `Session.Humans` order who does.

- Ending the turn is the `EndTurn` command (kind 43). The UI sends it through
  `aPlayerActions.EndTurn`, which sends it only when the local human holds the day and
  returns whether the day may start. Every place where a human's end turn starts the day
  asks it first, right before the player-star job: the star map's end turn and its automatic
  continue, the planet and station panel's end turn, the takeoffs from the planet, hangar and
  station screens, and the jump screen. The day is committed when the player-star job
  starts; the preparation job before it only prepares the local star's day and does not
  count.
- The player-star job starts the next round when it ends (`StartDayRound`): every human who
  plays holds the day again.
- With one human `EndTurn` always returns true, so the day starts at once, as before. The
  command changes nothing the state hash covers, and a log without it replays as before.

**Continue until arrival.** In single player the star map runs day after day while the
player's travel goes on, until something interrupts it. With several humans the same
automatic continue sends `EndTurn` with `ContinueUntilArrival`: the human counts as having
ended every day while its travel goes on. `StartDayRound` decides that for every such human
with `HumanTravelContinues`, the star map's test without the parts that only the local screen
has: in hyperspace, a travel order not yet reached, no fight and no interruption in its star
that day, the equipment not broken. When it stops, the human holds the next day. A break in
the film (the star map's break button) ends it at once (`StopContinuing`, kind 45). The flag
is not saved; after a load the human ends its turns again. Other humans' days still need
their end turns, so a continuing human's travel waits for them.

**Hyperspace.** The jump screen runs the local human's hyperspace step after each
player-star job (`HyperspaceStep`). A human whose jump screen is not shown still needs it,
so the player-star job marks it due (`THuman.HyperspaceStepPending`) and the galaxy job's
start (`aCalc.QueueGalaxyTurnCalculation`, `CalculateGalaxyTurnAndWait`) runs it as that
human (`StepHumansInHyperspace`). Only in multiplayer.

**Hot-seat.** `--hotseat=N` adds humans after a save loads or a new game starts, by the
`JoinHuman` command (kind 44), until there are N; each lands at the first coalition planet in
a coalition star that holds no human (`FindJoinPlanet`). A hot-seat save keeps its humans.
Then, on one screen:

- When the local human ends its turn and another human still holds the day, a notice says
  whose turn it is (`Multiplayer.Turn` in the language data, English when missing) and the
  screen passes to the first human in `Session.Humans` order who holds the day
  (`HotSeat.SwitchToNextHuman`). The switch happens between screens (`ApplyTurnPass`), so the
  old screen closes as the old human's: `SetLocalHuman` changes `LocalHuman` and
  `LocalPlayer` without touching `Session.Humans` (unlike `SetPlayer`, which rebuilds it,
  or `ClearLocalPlayer`, which forgets the local ranger). The new human's screen opens: the
  planet (`screenPlanet`, or `screenPlanetNO` when uninhabited), the station
  (`screenRuinsTalk`) or the star map, centred on its ship.
- The day runs on the screen of the human who ends the turn last, with that human's film.
- After the day, the first human in `Session.Humans` order who holds the next day has the
  turn: the star map passes the screen when it would enter order mode, the planet panel when
  the day has run. So every day starts with the first human, and the commands of a day are in
  `Session.Humans` order, as the merged replay (below) applies them.
- **Films.** Every human's star records its own film (`aStarFilms`); the local star records
  into `PrimaryFilm`. On a switch, `ExchangeLocalStarFilm` gives `PrimaryFilm` the film of
  the new local star and moves the old one to the old star, so each star keeps the day
  prepared for it, and the next day's film is the new local human's. The humans who were not
  local while a day ran do not see its film; replaying each human's film of the last day is
  not done.
- The space background of the new star is generated when the star changes, as after a jump.
- A switch changes which human the save writes first, so the state hash changes with it. The
  command log records the switch (a Local record) and the replay repeats it.

**One log per human.** `tools/split_commands.py LOG DIR` splits a recorded log into
`human-<id>.srcl`, one per actor. Each holds its human's commands and a copy of every other
record (loads, jobs, checkpoints, Local records), where the logs meet. `--replay-commands`
with several logs (a comma-separated list or a directory) merges them
(`CommandLog.RunMergedReplay`): between two shared records it applies each human's commands
in `Session.Humans` order, then the shared record. The order of the files does not matter.
The merged replay reaches the recording's hashes when the recording was made in that order,
which the headless hot-seat and the hot-seat UI both follow. A networked host's log is not:
it applies each client's trades, and what the client sent before them, as they arrive, before
the barrier ([network.md](network.md), Trades). Its single log replays as it was recorded. Before each player-star job it
checks that no human holds the day (`barrier-waits`).

**Not covered.** Days that other screens start without an end turn: the old hyperspace
arcade battle, the planet battles (Terron), text quests (off in multiplayer), and the new
game's opening days. The film-end steps of a day (landing wear, the black-hole scripts) run
for the human whose film it was. A human who is not local while its ship lands or docks does
not see the landing; the next turn opens the planet or station screen.

## Saving

Every `TPlayer` is saved as a ship, so every human's ranger survives a save.
The original layout also writes the local human's `THuman` state. The rest is
in the **per-human save block** (`source/game/aHumanSave.pas`), which
`TGalaxy.SaveToBuffer` appends after the original layout and the object
reference table:

- the session flags;
- every human, keyed by id, in `Session.Humans` order: its cheats, and for
  every human except the local one, its `THuman` state (the player star, the
  follow target, automatic control, tips, bubbles, finished quests, the hangar
  slots, the hold order and the open shop);
- the human each script is bound to (`TScript.HumanId`);
- the human each galaxy event is about (`TGalaxyEvent.HumanId`);
- from version 2, whether each human's game has ended (`Finished`,
  `FinishReason`). A version 1 block loads with every human playing;
- from version 3, the items of the shop grids that write their slots empty, by
  id (see Shops). An older block has none.

The block is written only when a save without it would load differently: more
than one human, a flag that is not its default, a cheat on record, a finished
human, or a script or event bound to a human other than the first. A single-player save is
therefore byte for byte as before. A save without the block loads as the
original does: every script and event is bound to the first human. After a
load the local human is still the saved `PlayerRangerIndex`, and
`Session.Humans` is in the saved order.

The block starts with `SRHU`, a version and its size. A later version only
appends fields; a reader reads the fields it knows and skips the rest.

**Session flags** (`Session` in `aSession`) are part of the saved session and
change only through the `SetSessionFlag` command (`SetSessionFlagValue`). They
are the host's: a host refuses a client's `SetSessionFlag` before it is queued
([network.md](network.md), Commands).

| Flag | Default | Effect |
| --- | --- | --- |
| `TextQuestsDisabled` | off | no text quest is offered at a government (`TRanger.GenerateQuestOffer`) |
| `FriendlyFireEnabled` | on | whether a human may attack another human (see PvP) |

**Cheats.** `Human.RecordCheat(Name, Points)` records that a human used a
cheat. A cheat command's executor calls it for the command's actor. Nothing
calls it yet, since `CheatCode` is not built.

## Shops

A planet's or station's equipment stock is its `EquipmentShop` list, whoever
looks at it (`source/game/aShopStock.pas`). Native moved the items into the
player's grid while the shop was open, so a second human at the same place
saw an empty shop, and one human's purchase moved the slots another's commands
named.

- A human's grid, `THuman.TemporaryShopSlots`, is a view of the list: the
  slots point at the location's items and own none.
  `BuildTemporaryShopSlotGrid` (the `OpenShopStock` command) sorts the list as
  native sorted the grid (its exchange sort, ties included) and shows it in
  that order, padded to the human's columns, so single player shows the same
  grid. `RestoreTemporaryShopStock` (`ReturnShopStock`, a takeoff with
  `tfReturnShopStock`, a respawn) only closes the grid.
- A shop command names an item by its slot and its id. The executor finds it
  by id in the stock of the shop the actor has open, else of the shop it is at
  (`aShopActions.ShopItemArg`), and refuses with `rrItemGone` before changing
  anything when another human took it. The slot only places it: a purchase
  takes the item out of the list and leaves the buyer's slot empty, as native
  did (`TakeShopStockItem`); a sale puts it in the list and builds the seller's
  grid again.
- `ShopStockChanged(Location, Actor)` rebuilds every other human's grid at the
  location that no longer shows the list, in the list's order and without
  sorting it (`RefreshShopView`), and tells the local screen
  (`SimEvents.NotifyShopStockChanged`, which rebuilds the equipment shop's
  controls), also when a host applies a client's trade or a client runs a trade
  its host relayed ([network.md](network.md), Trades). The purchase and sale commands, a grid that is built (it sorts the
  list), the scripts' `AddItemToShop`/`GetItemFromShop`, the daily restocking of
  planets and stations, a bank's deposit prize and a pirate ship built from
  shop parts call it. An NPC that buys at a shop closes and builds the grids
  there as before. A planet or station that is freed closes its grids
  (`DropShopViewsAt`).
- **Saving.** The original layout stays. While the galaxy is written
  (`BeginShopStockSave`, also while the state hash collects identities), the
  first grid at each location (the local human's first, then
  `Session.Humans` order; only a grid at the place its ranger is) writes the
  items it shows as native wrote its grid, and the location's list leaves them
  out. A single-player save is therefore byte for byte what it was. Another
  grid at the same place writes its slots empty, and the per-human block
  (version 3) names its items by id. A load gives a grid's items back to the
  place its ranger is, in front of the list in grid order
  (`AdoptLoadedShopView`), so a save made before this change loads the same
  way, and a round trip gives back the same list order.
- The stock no longer leaves the list while a grid is open, so simulation code
  that reads the list sees the whole stock. Play gives the stock back before
  every day, so single player does not change; a headless run that keeps a
  grid open over days (the observer's parked turns) restocks from the real
  stock.

## Classifying a site

Each `GetPlayer` or `LocalHuman` use in the simulation (`source/game`,
`source/script`, `source/core`) gets one of these classes. Choose from what the
code means, not from what is shortest.

- **local**: whose screen this is. Only for presentation, such as which film
  to play, which sound to make or what the star map shows. It is rare in the
  simulation. If a site feeds game state, it is not local.
- **actor**: the human doing this. Inside a `TPlayer` method that is `Self`.
  Inside a `TShip`/`TRanger` method after `IsHuman(Self)`, it is
  `TPlayer(Self)`. In an executor it is `Actor(Command)`. In code an executor
  calls (the actions units' helpers, shop stock, the hold order) it is
  `ActingHuman`. A routine that screens or the turn thread also call runs
  outside a command, where `ActingHuman` is nil, so it takes the human as a
  parameter instead, and screens pass `LocalHuman`. Elsewhere, pass the human
  in as a parameter from the caller that knows it.
- **each**: every human. Day ticks, galaxy news, victory and defeat checks,
  and messages that every human gets.
  `for I := 0 to Session.Humans.Count - 1 do ... Session.Humans[I] ...`.
- **any**: a condition that is true if some human qualifies, such as
  `Ship = GetPlayer` becoming `IsHuman(Ship)`, or `GetPlayer.CurrentStar = Star`
  becoming `StarHasHuman(Star)`.
- **target**: the AI choosing which human to react to, such as the human it
  attacks, fears or talks to. Usually the human is already known: the ship's
  target, the ship that hit it, or the ship in the conversation. Use that. If
  the code really means "the player, wherever they are", pick the relevant
  human in the same star, or leave out humans in other stars.

Patterns that come up often:

| Old | New | Class |
| --- | --- | --- |
| `if Ship = GetPlayer then` | `if IsHuman(Ship) then` | any |
| `if GetPlayer = Self then ... GetPlayer.X` | `if IsHuman(Self) then ... TPlayer(Self).X` | actor |
| `GetPlayer.X` inside `TPlayer` | `X` / `Self.X` | actor |
| `if GetPlayer.CurrentStar = Star then` | `if StarHasHuman(Star) then` | any |
| `if GetPlayer <> nil then GetPlayer.DailyThing;` | loop over `Session.Humans` | each |
| `LocalHuman.PlayerStar` in the turn | the human's `PlayerStar`, or a loop | each/actor |
| `AddOrUpdatePlayerBubble(...)` about a ranger's event | `HumanOf(Ship).AddOrUpdateBubble(...)` when `Ship` is human | actor |
| `Relation(GetPlayer)` in AI | `Relation(Target)` for the human it deals with | target |

### Single player must not change

With one human every class gives the same answer as `GetPlayer`, so the save
tests' goldens must not move. A loop over `Session.Humans` runs once, and it
must draw random numbers in the same order as the code it replaces.

Two differences are accepted and need no `CHANGE:` tag:

- `X = GetPlayer` was also true when both were nil, which happens only after
  the player has died. `IsHuman(nil)` is false. After the player dies, single
  player is over.
- `IsHuman` is also true for a human's ranger that is not the local one. That
  is the point of the conversion.

Anything else that would change single player needs a `CHANGE:` tag and a
note in the progress entry.

### What to leave

- Do not rename in bulk. Each site is a decision, and the reviewer checks it.
- Keep `GetPlayer` where the right class depends on a design question that
  ROADMAP.md, Phase 6, does not answer. Mark the site with a
  `// HUMANS: <question>` comment and list it in your report.
- Code under `source/screens`, `source/arcade`, `source/scene`,
  `source/quests` and the root units is presentation. It already says
  `LocalPlayer`.

## Checking

- `python tools/player_sites.py --update` rewrites `tools/player_sites.txt`,
  which counts each unit's sites by class. `--check` fails if a simulation
  unit gains a `GetPlayer`. Commit the table with the conversion.
- `python tools/build.py --target windows`, `python tools/unit_tests.py`,
  `python tools/check_layers.py`.
- `python tools/test.py --game-dir=...`. Single-player goldens must not
  change. The same run plays each save with 2 and 8 humans
  (`--sim-humans=N`) and checks for crashes, a clean round trip and
  determinism. Hashes with several humans are expected to change as sites are
  converted, since extra humans stop being treated as NPCs. Those runs also
  destroy two humans' rangers (`--sim-kill-human=TURN`: the local one, and the
  last one among planets made hostile to it) and check that they respawn
  landed, repaired and with the same money and items, that no human is lost,
  and that a finished human's command is refused.
- The same counts play hot-seat headless (`--sim-hotseat=DAYS`): each day every human, in
  `Session.Humans` order, takes off, flies, lands or buys, and ends its turn; the day must
  wait until the last one has (`hotseat barrier ok`). The recording is split into one log per
  human and replayed from those, given in reverse order; it must reach the same final hash
  with no divergence and no day started early. With two humans, a log stripped of its
  human's end turns must make the replay report the barrier.
- Each save also runs `--sim-shared-shop` (Shops): the save's open grids must
  load with their items back in their shops; then two humans join at one
  planet and open its shop. Both must see the whole stock; the second's
  purchase of what the first bought is refused as `item-gone`, and its purchase
  of another item by the slot its grid showed before (which has moved) goes
  through; an item the first sells back shows in the second's grid and can be
  bought; no item is lost or in two places; and a round trip keeps both grids.
- Each save also runs `--sim-script-routing` (Scripts): two humans join and
  one is made local. The other's script code must show nothing and get the
  declining answers; a command nested in its command, or in another's command
  for its script, must be its own; its takeoff and end-turn requests must be
  its own and its commands must clear only its own; its battles and videos
  must be queued only in its own command and finished only by its own report;
  the talk builtins must read the talker's talk; and its ruins mode must open
  no screen while the local human's does.
- The same counts run `--sim-pvp` on each save: a second human joins in the
  local human's star and the local one attacks it. With friendly fire on its
  hits must do damage; after the `SetSessionFlag` command turns it off, the
  attack order must be gone, new attack orders refused, and neither hits nor a
  direct `ApplyWeaponHit` may do damage while the attacker is in range.
