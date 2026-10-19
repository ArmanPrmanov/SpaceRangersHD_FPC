# 2026-10-19 — Text quests in multiplayer: plan

- Done: the plan; Phase A (the quest run out of the screen, the headless
  quest player); Phase B (the multiplayer rules in the game layer); Phase C
  (the network flow, waits and disconnects); Phase D (the pages to the
  watchers). See their notes below.
- In progress: nothing.
- Next: Phase E, then F, one subagent at a time.
- Notes: the owner asked for text quests in multiplayer, with the other
  players able to watch a quest but not act in it. This entry is the plan.
  The decisions marked **Owner** have the owner's answers (2026-10-19), in
  section 4 and at each rule.

## 1. How text quests work today

### Where a quest starts

There are three kinds, all shown by one screen, `TfPlanetQuest`
(`source/quests/fPlanetQuest.pas`, `screenPlanetQuest = 7`). `OnOpen`
picks the kind:

1. **Prison.** `LocalPlayer.InPrison` at a planet. The quest is
   `Prison` or `PirateClanPrison`, by name. Entered from the government
   (`TfGov.EnterPrison`: autosave, the `EnterPrison` command 410, then the
   screen).
2. **Queued by a script.** `SF_StartTextQuest` (`aScriptFun.pas` ~8061)
   adds a `TScriptTQRequest` to the global `QueuedTextQuests`
   (`aScript.pas`). `TryShowQueuedTextQuest` opens the screen. The outcome
   resumes the script (`CompleteQueuedTextQuest`: sets `GQuestStatus`, runs
   its turn code). The request has **no human id** and is not checked with
   `MayQueueScriptRequest`, unlike arcade battles, planet battles and videos
   (`TScriptABRequest.HumanId`, `SF_StartAB`).
3. **Government planet quest.** `GenerateQuestOffer` (`aRanger.pas`
   ~6103) runs in the `RequestQuest` executor (`aPlanetActions`, 420) and
   offers a `qtPlanetQuest` whose `ObjectiveTarget` is another planet with
   `Planet.TextQuestId <> -1` (set at generation by
   `TGalaxy.AssignTextQuestsToPlanets`). `AcceptQuest` (422) adds it to
   `P.Quests`. When the ranger lands on the target, the planet screen
   (`TfPlanet.RefreshTextQuestPrompt`, `StartTextQuest`; also `fPlanetNO`)
   offers it: autosave, then the screen. The offer does not check whether
   another human already holds a quest to the same planet.

A fourth path, the standalone quest from the main menu (`fLoadQuest`,
`StandaloneQuestMode`, `LocalPlayer = nil`), has no galaxy and is out of
scope.

### The engine

- `TTextQuest` (`TextQuest.pas`) with locations, paths, parameters and
  formulas (`LocationClass`, `PathClass`, `ParameterClass`,
  `CalcParseClass`, ...). It talks to the screen only through
  `TTextQuestInterface` (`TextQuestInterface.pas`): `ShowText`,
  `ShowPicture`, `PlayMusic`, `PlaySound`, `ShowParameters`, the `Add*Action`
  calls that build the choices, and `AdvanceDays`. The base class does
  nothing, so a headless player can subclass it.
- The engine reads no galaxy state. Grep finds no `Galaxy`, `LocalPlayer`
  or `Session` in the engine units.
- **Randomness.** One stream of its own: `TextQuestRandomState`, an LCG in
  `CPDiapClass.pas` (`TextQuestRandom`), a global. `StartLoadedQuest` seeds it
  with `QuestRandomSeed` (command 600), whose executor draws once from the
  galaxy stream (`GameRandomIntRange`). So a quest is deterministic given the
  seed and the choices. The draw itself is a recorded command, so the
  galaxy stream stays deterministic in replays.
- **Parameters in and out.** At start, `ImportExternalParameters` reads
  `GQuestVarExt_*` script variables (the queued script's own, else
  `Session.SharedScriptVariables`) and the player's money. On every page,
  `ShowParameters` calls `ExportMoneyToPlayer` (`SetQuestMoney`, 601: sets
  the money absolutely) and `ExportExternalParameters` (`SetQuestVariables`,
  602).
- **Days.** A location or path with `Days > 0` calls `AdvanceDays`
  (`TextQuest.pas` 959, 1164). The screen then runs full game days itself:
  `CalculatePlayerStarTurnAndWait` and `QueueGalaxyTurnCalculation`, with no
  end turn and no barrier, and imports money and variables again after each
  day. `DaysElapsed` only feeds the date text. So yes: in the original, some
  quests pass days in the galaxy (the prison sentence is the obvious case).

### The screen

`TfPlanetQuest` lays out the text (`SetQuestText`), the picture, the
parameter panel and the choices (`AddChoice`, `AddDisabledChoice`,
`ChoiceMouseUp`, digit keys). Single-player-only behaviour:

- Escape asks and then destroys the galaxy and goes to the main menu
  (`RequestLoadGame`).
- `R` reloads the autosave; failure and death offer to load it too.
- Entering a quest writes an autosave (`fPlanet`, `fGov`).

### What comes back to the game

All as commands (`aQuestActions`, 600–608, docs/commands.md):

| Kind | Command | When |
| --- | --- | --- |
| 600 | `QuestRandomSeed` | start |
| 601 | `SetQuestMoney` | each page |
| 602 | `SetQuestVariables` | start and each page |
| 603 | `CompleteGovernmentQuest` | success of a planet quest (`TextQuestId := -1`, item, relation) |
| 604 | `ReleaseFromPrison` | prison quest lost |
| 605 | `FailGovernmentQuest` | planet quest lost (`TextQuestId := -1`, archived) |
| 606 | `DieInQuest` | death: `Actor.Free`, `Session.GameEndReason := 1` |
| 607 | `FinishQueuedTextQuest` | a queued quest ends (resumes `QueuedTextQuests[0]`'s script) |
| 608 | `CloseQuest` | leaving: money cap, `ProcessQuestTimersAndOutcomes` |

`OnOpen`/`OnClose` also run `RunScriptItemsAct` (a command). Kinds 609–624
are free.

### What is saved

Nothing of a running quest. The interpreter is outside the galaxy save, as
in the original (you cannot save inside a quest; the autosave is before it).
`QueuedTextQuests` is not saved either. `Planet.TextQuestId` and the
government quest in `P.Quests` are.

### What the session flag blocks, every site

(Before Phase B. The owner has since retired the flag: text quests are always
on in multiplayer; see section 4.)

`Session.TextQuestsDisabled` (`aSession`, flag 0, `SetSessionFlag` 42,
host only):

- `aRanger.pas:6108`: no government planet quest is offered. **That is the
  only gameplay site.**
- `aHumanSave.pas:364/437`: saved in the per-human block.
- Tests: `TestCommands.pas` 27–32, `HeadlessSim.ProbeSession` (sets it),
  `HeadlessSim` 410 (`state session textquests-off=`), `HeadlessNet` 1147
  and 1498 (a client's flag change is refused), `tools/test.py` 219, 1052.

Findings that matter:

- **Nothing sets the flag in a real hosted game.** Only the headless probes
  do. So in a real session government quests are offered now.
- The prison and script-queued quests were never gated.
- In a session, a client that reaches a page with `Days > 0` starts a turn
  job, which raises (`ThreadCalc.TurnJobsForbidden`). On the host it would
  run a day past the barrier.
- `NetPlay.NoGameScreens` holds `screenPlanetQuest`: while the host's own
  human plays a quest the host takes no joins, leaves, commands or trades
  (clients' trades time out after 10 s), and a client in a quest gets no
  reconnect box.
- A script quest queued by another human's script code on the host shows on
  the host's screen (one global queue).
- `DieInQuest` frees the ranger and ends the game, against Phase 6 (a
  destroyed human respawns). `ArcadeDefeat` (628) has the same gap.
- Three game-layer sites read the local screen: `CountsTowardStarControl`
  (`aGalaxy` ~11151), the deadline check in `aRanger` ~4657 and
  `ConsecutiveDockedDays` in `aShip` ~2562 (`HumanScreen =
  screenPlanetQuest`). They matter only while days run inside a quest.

## 2. Design

### Who runs the engine: the player's own machine

**Decision: the human who plays the quest runs the engine on its own
machine. Only the effects go to the host, as the commands it already
sends. The other machines get rendered pages to watch.**

Why:

- It is the model the code already has. Phase 3 made every write a command
  and kept the interpreter in the screen. Arcade battles do the same (Phase
  6: "solo instance, local to the human").
- No latency per click. A host-run engine needs a round trip per choice and
  a new remote screen protocol, like the remote dialogue but longer.
- Replays need no engine. The host's command log has the effects; the
  merged per-human replay applies them in queue order.
- The client's prediction already works: each command runs at once on the
  client and is queued on the host until the barrier. The queue is also the
  quest's atomicity: if the client drops before its end turn, the host drops
  the whole queue and the quest never happened there.
- Cheating does not matter (co-op).

Randomness: keep `QuestRandomSeed` as it is. On a client it draws from its
copy's stream (the prediction), and the host draws again at the barrier in
queue order. The two values differ, which does not matter: the host never
runs the engine. The host's log replays the same draw. The quest's own
stream (`TextQuestRandomState`) never touches the galaxy streams. Do not
make the seed a trade: a trade runs on arrival, and arrival order must not
move the galaxy stream.

Absolute money: `SetQuestMoney` sets the money. Between days only the
actor's own commands change its money, and they reach the host in order, so
the absolute value is right. Keep it.

### Rules in multiplayer (`IsMultiplayer`: hot-seat and network alike)

1. **Days in a quest.** **Owner: as the default** (decided). The quest runs no game days. The
   days it would pass are counted (`DaysElapsed`) and sent with `CloseQuest`
   (a new last integer). Its executor stores them as
   `THuman.QuestDaysOwed`. While that is above 0 the human does not hold the
   day (`HumanHoldsDay`), as in hyperspace, and `StartDayRound` takes one
   off after each day. The ranger stays landed meanwhile. So the quest still
   costs its time, and the others do not wait for it. The date text shows
   `CurrentTurn + DaysElapsed`. Alternative: ignore the days (simpler,
   free time). Single player keeps running the days in the quest.
2. **Death.** **Owner: respawn** (decided, instead of the default). In
   multiplayer a death in a quest is a ship loss: the ranger is killed and
   respawns as a destroyed human does (`FindRespawnPlanet`, `RespawnHuman`),
   after the quest's failure (a prison quest frees it with the planet hostile,
   a government planet quest fails, a script's quest resumes with a failure).
   It does not end the game for anyone; single player still ends it. (The
   rejected default was: a failure that leaves the ranger as it is.)
3. **No reload, no exit.** In multiplayer: no autosave before a quest on a
   client, no `R`, no "load the autosave?" box, and Escape does nothing (a
   quest always ends by its own choices). The host may keep its autosave.
4. **One quest per planet offer.** `GenerateQuestOffer` with `IsMultiplayer`
   skips a planet that another human's open `qtPlanetQuest` targets. It runs
   in the `RequestQuest` executor, so the host decides at the barrier. Single
   player is unchanged.
5. **Script quests are per human.** `TScriptTQRequest` gets `HumanId`;
   `SF_StartTextQuest` checks `MayQueueScriptRequest` (declines otherwise, as
   `SF_StartAB`); `TryShowQueuedTextQuest` shows `LocalScriptRequest
   (srqTextQuest)`; `FinishQueuedTextQuest` finishes its actor's request
   (`CompleteQueuedTextQuest(Status, HumanId)`; `HumanId` 0 matches any, so
   old logs replay).
6. **The flag is gone.** **Owner: text quests are always on in multiplayer**
   (decided, instead of the default, which kept the flag as the host's
   switch). `Session.TextQuestsDisabled` is removed; its number stays taken
   (`SessionFlagTextQuestsRetired`, which `SetSessionFlag` ignores) and its
   byte in the per-human save block is written off and ignored on load, so old
   logs and saves load.

### The lock: one human per quest

"Others cannot interact while one plays" is mostly given by the rules: a
government planet quest is in one human's `P.Quests`, and the planet screen
offers it only to that human; prison and script quests are per human. The
remaining race is two humans who hold a quest to the same planet (a save from
before rule 4, or two offers predicted on the same day). Both could play it
before the barrier and both be paid.

New command **`BeginTextQuest` (609), a trade**, submitted by
`TfPlanetQuest.OnOpen` before `StartLoadedQuest`, through a wrapper that
catches the refusal (as `aShopActions.TradeGoods` does). Arguments: the kind
(planet, prison, script) and, for a planet quest, the planet by `AddRef`.

- The executor refuses before any change: `rrOfferGone` when the planet's
  `TextQuestId` is -1 or the actor holds no `qtPlanetQuest` to it; `rrInUse`
  when another human's lock names the planet. Then it sets
  `THuman.TextQuestPlanetId` (session state like `Connected`: not saved, not
  hashed).
- The lock goes when the barrier applies the human's `CloseQuest` (which is
  then also when `TextQuestId` becomes -1), when the human disconnects, and
  on the client with every state (a fresh `THuman`).
- As a trade it runs on the host on arrival and is relayed to the clients at
  that planet, so their planet screens can show "<Player> is playing this
  quest" and grey out the start. A refusal shows the usual bubble
  (`Multiplayer.RefusedInUse`, `RefusedOfferGone`) and the screen goes back.
- Prison and script quests send it too, with no planet: it always applies.
  This keeps one start point. Single player and hot-seat run it at once.

### The day

A human in a quest has not ended its turn, so it holds the day. Nothing new
is needed for that. What changes:

- `NoGameScreens` loses `screenPlanetQuest` when a galaxy and a local player
  exist (not the standalone quest). The quest screen is a `TMessageLoopGI`,
  so the frame pump and `MayChangeUnderScreen` work there: the host takes
  joins, leaves and trades while its own human plays, and a client in a
  quest runs relayed trades and sees the reconnect box. A join's checkpoint
  is safe: the quest is not in the galaxy.
- `Status` gets, per human, an activity byte (0 none, 1 in a text quest, 2
  busy with quest days) and the days owed. The waits say "Waiting for Guest
  (text quest)" and "Guest is busy with a text quest for 3 more days"
  (`Multiplayer.InTextQuest`, `Multiplayer.QuestBusy`, English fallbacks).
  The host knows "in a quest" from the pages (below) for clients and from its
  own screen for its human; days owed come from the state.
- Owed days: a client whose state says its human owes days opens the planet
  screen and waits for the next state, as a continuing traveller waits
  (`DeferredNetContinue`). The host's own human's planet screen starts the
  next day by itself while it owes days, as the star map's automatic continue
  does. `MayCancelEndTurn` is false then.

### Watching

What a watcher sees: the same page the player sees, read-only, updated live:
the text, the picture, the parameter panel and the choices, greyed and not
clickable, plus a line "<Player>'s text quest" and a Close button (also
Escape). Closing never changes game state.

**The page, not the choices.** The player's machine sends what it rendered
(`TQuestPage`): the human id, a run number, a page number, the quest's name,
the text as shown (with its colour tags), the picture name, the parameter
text, each choice's text and whether it is enabled, and an end marker with
the outcome (success, failure, death, abandoned). Not the choice indices:
the watchers would have to run the engine on the player's money and
variables, and players may have different languages (the data hash leaves
language files out), so the quest files can differ. A watcher therefore
sees the player's language. Pictures go by name; a missing one is left out.

**Messages (protocol 10).** One new kind, `QuestPage` (18), both ways:

- client → host: its own human's page, after each page is laid out, and the
  end page from `OnClose`;
- host → client: any other human's page, sent to every joined client but
  the player's. Pages are a few KB and come at a click's pace, so a
  broadcast costs nothing, needs no subscription state, and lets a watcher
  open the window late.
- The host keeps the latest page per human (its own human's from a hook,
  `QuestPageHook`, set by `NetPlay`). On a peer's disconnect it broadcasts an
  end page (abandoned) for that human. A client keeps the latest page per
  human (`TNetClient.QuestPage(HumanId)`), dropped on reconnect.
- `Status` changes (activity, days owed), so the version goes to 10 anyway.
- Pages are presentation: not commands, not logged, not hashed.

**Where to open it.** **Owner: as the default** (decided; Phase E). (a) every wait box for the day that
names a human in a quest gets a line "W: watch <Player>'s text quest." and
the `W` key (the box's buttons are pictures, as with Cancel); (b) the in-game
round menu gets a "Watch text quest" button while some other human plays one
(as the host button). The watch window is a box over the innermost screen,
like the reconnect box: it opens no game screen and closes none, so no
`OnOpen`/`OnClose` command runs. From a wait it runs inside the wait loop: the
wait returns "watch", the loop opens the watch box, which polls the same
"wait done" condition and closes when the day's film or state comes, then the
loop goes on. It also closes on the end page, and when its own client starts
reconnecting.

### Disconnects

- **The player's client loses the host mid-quest.** The reconnect box now
  opens over the quest screen. On reconnect the quest is abandoned: the
  screen closes without sending an outcome (the host dropped the queue with
  the old connection, so the quest never happened there; `TextQuestId` is
  still set), the rejoin state is applied at the next safe screen, and a
  bubble says the quest was abandoned and can be started again. If the
  reconnect fails, the client leaves as it does today. This matches the
  documented loss of one day's commands on a reconnect.
- **The host sees the player leave.** It drops the queue (as now), clears
  the lock and broadcasts the abandoned end page.
- **The host's own quest.** Nothing new: the host does not disconnect from
  itself. Stop hosting mid-quest leaves a single-player quest.
- **A watcher drops.** Its watch box closes; nothing on the host.
- Hot-seat: the rules apply (`IsMultiplayer`); no watching, no network.

### Command and protocol numbers

| What | Number |
| --- | --- |
| `BeginTextQuest` (trade) | command 609 |
| `CloseQuest` | 608, a new last integer: the days owed (absent: 0) |
| `DieInQuest`, `FinishQueuedTextQuest` | 606, 607: same arguments, new behaviour in multiplayer |
| `QuestPage` | message 18 |
| `ProtocolVersion` | 10 (`Status` carries activity and days); 11 (`QuestPage`, Phase D) |
| Per-human save block | version 4: `THuman.QuestDaysOwed` |

## 3. Phases

Each phase leaves the tree building and the tests green. Every phase runs:

- `python tools/build.py`
- `python tools/unit_tests.py`
- `python tools/check_layers.py`
- `python tools/test.py --game-dir="D:/Games/by Decepticon/Space Rangers HD A War Apart"`
  (goldens must not change unless the phase says so)

No visible windows: only headless runs. Each phase updates the docs it
changes (docs/network.md says the design changes the page first) and writes
its own progress entry.

### Phase A — Extract the quest run (no behaviour change)

- Goal: the engine can run without the screen, so tests can play a quest.
- Files: new `source/quests/QuestRun.pas`; `fPlanetQuest.pas`; new
  `source/observer/HeadlessQuest.pas`; `HeadlessSim.pas`; `tools/test.py`.
- Steps:
  1. Move out of `TfPlanetQuest` into `TQuestRun` everything that is not
     layout: the choice of kind and quest in `OnOpen`, the texts set before
     start, `StartLoadedQuest`, the parameter export/import, `AdvanceDays`,
     the outcome handlers' commands (`CompleteQuestSuccess/Failure/Death`
     minus the boxes and screen requests), `CloseQuest`. The run holds the
     current page as a `TQuestPage` record (text, picture, parameters,
     choices with enabled flags and callbacks by index) and calls a view
     interface to show it. `Choose(Index)` runs a choice.
  2. `TfPlanetQuest` becomes the view: it lays out the page and maps clicks
     and keys to `Choose`. The message boxes and screen changes stay there.
  3. `THeadlessQuestPlayer` runs a `TQuestRun` with a deterministic chooser:
     a test-local LCG over the enabled choices (never the game streams),
     capped at 1000 steps (then it reports `abandoned`).
  4. `--sim-text-quest=ID|NAME` (single player): run that quest on the
     loaded save's human, print each page's hash and the outcome, then the
     state hash.
- Verify: goldens unchanged; `tools/test.py` runs `--sim-text-quest=Prison`
  twice on one save and checks equal output and hash; a planet quest id
  from the save too.

#### Phase A notes (done)

- `source/quests/QuestRun.pas`: `TQuestRun` is the engine's
  `TTextQuestInterface` (it replaces `TTextQuestPlayerInterface`) and holds
  everything that was not layout: `Open` (the kind and the quest, the texts,
  the money limit, stages 4–22 of the old error label), `StartLoadedQuest`,
  the template and `ext_` text expansion, the money and variable
  export/import, `AdvanceDays` (one day is `RunQuestDay`, the seam for Phase
  B's owed days), the outcomes' commands and `Close` (`CloseQuest`). Kinds:
  `qrkStandalone`, `qrkPrison`, `qrkQueued`, `qrkPlanet`, and `qrkNamed` for a
  quest given by name or number (`OpenNamed`, the headless player; it ends as
  a planet quest does). `ActiveGovernmentQuest` and `ActiveQueuedTextQuest`
  became the run's `GovernmentQuest` and `QueuedQuest`.
- The page is `TQuestPage` (text and parameters as shown, with colour tags;
  the picture's name; the choices with their text as shown, enabled flag,
  action and value; the outcome, `qroAbandoned` when closed without one). It
  lives in `QuestRun` for now; Phase D moves it to `QuestPage.pas` with its
  codec. `Choose(Index)` plays a choice; a disabled one does nothing.
- `TQuestView` gets each change in the order the screen drew it (`ShowText`,
  `ShowPicture`, `ShowParameters`, `ClearChoices`, `AddChoice`, `FinishPage`
  after the start and after each choice: the place for Phase D's
  `QuestPageHook`), plus `ConfirmDeath` (before `DieInQuest`; the screen's
  autosave box and score) and `EndQuest` (after the outcome's commands and
  before a queued quest's script resumes: the screen's boxes, achievements,
  completion records, `TryTakeOff` and next screen). Command order is the
  old one.
- `TfPlanetQuest` is the view (`TPlanetQuestView` forwards to it). A choice's
  panel holds its index plus one in `UserValue` (the `TfQuestA` object is
  gone); clicks and digit keys reach `Run.Choose`. `GetQuestContentHash`
  became `QuestRun.QuestContentHash` (`fGov`, `fPlanet`, `fPlanetNO` use it),
  `GetTextColorTag` is `QuestTextColorTag`.
- `TTextQuest.ReportError`: the engine's four message boxes (no start, no
  answers, a missing location or path) go to `TTextQuestInterface.ShowError`,
  a box by default; the headless player prints them, so no test can open one.
- `source/observer/HeadlessQuest.pas`: `THeadlessQuestPlayer` plays a run with
  an LCG of its own over the enabled choices (seeded by `--sim-seed`), at most
  `MaxQuestSteps` (1000) choices, and prints `quest page=N hash= choices=
  enabled=` per page. `--sim-text-quest=ID|NAME` (`HeadlessSim.RunTextQuest`,
  single player): prints `quest save planet-quests= first=`, parks the human,
  sets `CurrentScreenId` to the quest screen for the quest's days, plays,
  prints `quest done name= outcome= pages= steps= days= errors=` and the
  state hash (`turn 0 ...`), or `quest state none: the ranger died` after a
  death (the ranger is freed and the galaxy cannot be saved).
- `tools/test.py` (`check_text_quest`): each save plays `Prison` and its
  first planet quest twice each; the lines must match. On the three local
  saves with seed 0: Prison dies after 36 and 23 quest days on two saves (so
  the galaxy days in a quest run headless), fails at once on the third;
  planet quests 38 and 21 fail in 4–8 choices.
- A race found on the way: after a quest day the screen queues the galaxy
  job and goes on with the page (money import, text, parameters) while the
  job runs, so a page after a day can read the galaxy mid-change. Under load
  two headless runs of one save differed there. The screen keeps the old
  behaviour; the headless player sets `TQuestRun.WaitForQuestDays`, which
  waits for the job before the quest goes on. Phase B's owed days remove
  the race in multiplayer (no galaxy day inside a quest); single player
  could adopt the wait as a bugfix later.
- `tools/player_sites.txt` was already stale before this phase; left as it
  was.

### Phase B — Multiplayer rules in the game layer

- Goal: the rules of section 2 hold in hot-seat; no network yet.
- Files: `aQuestActions.pas`, `aHuman.pas`, `aHumanSave.pas`, `aRanger.pas`,
  `aGalaxy.pas`, `aShip.pas`, `aScript.pas`, `aScriptFun.pas`, `QuestRun.pas`,
  `fPlanetQuest.pas`, `fPlanet.pas`, `fPlanetNO.pas`, `fGov.pas`.
- Steps:
  1. `TScriptTQRequest.HumanId`; `SF_StartTextQuest` with
     `MayQueueScriptRequest` and the flag; `TryShowQueuedTextQuest`,
     `HasPendingScriptRequests` and the resuming lookup by human;
     `CompleteQueuedTextQuest(Status, HumanId)` from the actor.
  2. Days: in `IsMultiplayer`, `AdvanceDays` counts only. `CloseQuest`
     gets the days; `THuman.QuestDaysOwed` (save block version 4, read only
     from 4); `HumanHoldsDay` false while it is above 0; `StartDayRound`
     takes one off. The three `HumanScreen = screenPlanetQuest` sites also
     treat a human who owes quest days as in the quest.
  3. `DieInQuest` in multiplayer: the default of rule 2.
  4. `GenerateQuestOffer`: rule 4.
  5. Screens: rule 3 when `IsMultiplayer` (no `R`, no load boxes, Escape
     ignored, no client autosave).
  6. `BeginTextQuest` (609) as a trade, with the lock in
     `THuman.TextQuestPlanetId` (not saved), cleared by `CloseQuest`.
     Register it in commands.md's trades table.
- Headless tests: a hot-seat run (2 humans) where human 2 plays a quest
  with days (`--sim-text-quest` with `--hotseat=2`): the next days run
  without its end turn, `QuestDaysOwed` counts down, two runs give the same
  hashes, and the merged per-human replay reaches the recording's hash. A
  probe gives both humans a quest to one planet: the second
  `BeginTextQuest` is refused `in-use` while the first plays, `offer-gone`
  after. A save round trip keeps `QuestDaysOwed`. Single-player goldens
  unchanged (all of this is behind `IsMultiplayer`).

#### Phase B notes (done)

- Decisions applied: 1 (owed days), 2 (respawn), 4 (no flag); 3 is Phase E's.
- **The flag.** `Session.TextQuestsDisabled` is gone (`aSession`); flag 0 is
  `SessionFlagTextQuestsRetired`, which `SetSessionFlag` ignores. The save
  block writes its byte off and skips it on load. `GenerateQuestOffer` no
  longer reads it. The probes that used it use friendly fire instead: the
  session probe (a finished human's `SetSessionFlag` turning friendly fire
  back on must be refused), the networked client's refused flag
  (`net client session flag friendly-fire=`, `net host session flag
  friendly-fire=`), `state session friendly-fire=` (the `textquests-off=`
  field is gone), and the unit test checks that the retired flag changes
  nothing.
- **Script quests per human** (rule 5): `TScriptTQRequest.HumanId` (after
  `Script`, so the native record view of the other queues is unchanged);
  `StartTextQuest` declines (0) unless `MayQueueScriptRequest`, and its count
  is the human's; `TryShowQueuedTextQuest`, `HasPendingScriptRequests`,
  `FindResumingScriptRequest` and the run (`Open`, `ComputeMoneyLimit`) take
  the local human's request; `CompleteQueuedTextQuest(Status, HumanId)` takes
  the actor's (`TakeScriptRequest`; 0 any, and none to finish now logs instead
  of raising).
- **Days** (rule 1): `TQuestRun.OwesDays` is `IsMultiplayer` when the quest
  starts. Then `AdvanceDays` exports money and variables as before and only
  counts; the quest's `<CurDate>` is the galaxy's day plus the days counted;
  `Close` sends them as `CloseQuest`'s second integer, which the executor adds
  to `THuman.QuestDaysOwed` (save block version 4; written also for one human
  who owes days). `HumanHoldsDay` is false while it is above 0, and
  `StartDayRound` takes one off. The three local-screen sites use
  `aHuman.OwesQuestDays`: star control (`CountsTowardStarControl`), the
  planet quest's deadline (`aRanger.InTextQuestAt`, the human at its own
  planet), the docked-days count. Single player sends 0 and is unchanged.
- **Death** (rule 2 as decided): `DieInQuest` carries whether a government
  quest fails with it (the run's `QueuedQuest = nil`, as `Fail`). In
  multiplayer its executor applies the failure (`ApplyReleaseFromPrison` or
  `ApplyFailGovernmentQuest`, split out of their executors), records the
  `PlayerDeath` event (`RecordHumanDeath('KilledInQuest')`) and respawns the
  ranger at once (`FindRespawnPlanet`, `RespawnHuman`), as
  `ApplyPlanetCaptured` does; only when no planet takes it is the ranger
  freed, and the game ends only on that human's machine. The run says
  `Respawned`, resumes a queued quest's script with a failure, and the screen
  goes to the planet. The ranger usually respawns where it was: its own
  planet is the nearest.
- **Offers** (rule 4): `GenerateQuestOffer` with `IsMultiplayer` skips a
  planet whose quest another human holds (`PlanetQuestHeldByOtherHuman`).
- **Screens** (rule 3): with `IsMultiplayer` the quest screen ignores Escape,
  the exit button and `R`, and shows no load box after a failure or a death.
  `fPlanet`, `fPlanetNO` and `fGov.EnterPrison` write no autosave on a
  networked client (`NetRole = nrClient`); hot-seat and a host keep it.
- **The lock** (`BeginTextQuest`, 609, a trade): `TQuestRun.Open` and
  `OpenNamed` send it before the quest starts (`BeginRun`; kinds `tqkPlanet`,
  `tqkPrison`, `tqkQueued`, `tqkNamed`); a refusal leaves `Refused` set and
  nothing started (the screen goes back; a session's `TradeRefusedHook`
  shows the bubble). The lock is `THuman.TextQuestOpen` and
  `TextQuestPlanetId`, not saved; `CloseQuest` and a load (`RebuildHumans`)
  release it (`THuman.ReleaseTextQuest`).
- **Tests.** `--sim-text-quest=NAME` with `--sim-hotseat=DAYS` (and
  `--sim-humans=2`): the last human is made local and plays the quest on the
  first day (`HeadlessSim.PlayQuestTurn`); the run goes on until it has paid
  its days and played two more. `check_hotseat_text_quest` checks the owed
  days (`quest owed ...`), two equal runs, and the merged per-human replay.
  On the three local saves (seed 0) the prison quest dies after 37, 71 and 39
  quest days and the ranger respawns; the replay reaches the hash with
  `barrier-waits=0`. `--sim-quest-lock` (`RunQuestLock`, `check_quest_lock`):
  in-use while the first plays, offer-gone after (its planet quests 38 and 11
  fail). `THeadlessQuestPlayer` gained `Start`, `OpenVisit` and `Finish`.
  The session probe gives every human quest days owed, and `check_session`
  checks that a round trip keeps them.
- Left for Phase C, as planned: the host clearing a disconnected human's lock
  and a client's fresh lock after a state; the owed-day waits and the host's
  automatic day start (in hot-seat a human who owes days is skipped by the
  screen switch already, as `NextHumanToEndTurn` skips it); the planet
  screen's "<Player> is playing this quest" (the refusal bubble covers it for
  now).

### Phase C — Network flow

- Goal: a client and the host can play quests in a session.
- Files: `NetPlay.pas`, `NetHost.pas`, `NetClient.pas`, `NetProtocol.pas`,
  `HeadlessNet.pas`, `tools/test.py`.
- Steps:
  1. `NoGameScreens`: the quest screen is a game screen when a galaxy and a
     local player exist.
  2. `Status`: activity and days owed; protocol 10; the wait texts.
  3. Owed days: the client's wait after a state (as `DeferredNetContinue`),
     the host's own automatic day start, `MayCancelEndTurn`.
  4. Disconnect: the host clears the lock; the client abandons the quest
     after a reconnect (closes the screen, sends nothing, bubble).
- Headless tests: `--sim-net-quest=DAY` on a client: on that day it plays a
  quest with `THeadlessQuestPlayer` before its end turn (a test-only probe,
  registered only with the flag as `--sim-net-nested` does, gives it a
  planet quest at its planet). Check: every state's hash equals the
  host's; the host's log replays to its final hash; the host applied the
  quest's commands at the barrier (`net host quest commands=`); the status
  said `activity=1` for that human while it played. With two clients and
  the shared-planet probe: the second client's `BeginTextQuest` is refused
  `in-use`. With `--sim-net-silent-at` on the quest day: the client
  abandons, gets its human back, and the quest is still there
  (`TextQuestId` set).

#### Phase C notes (done)

- **The quest screen is a game screen** (`NetPlay.NoGameScreen`): `NoGameScreens`
  lost `screenPlanetQuest`, which counts as no game only for the main menu's quest
  (no galaxy or player, or `StandaloneQuestMode`). So the host takes joins, leaves and
  trades while its own human plays one, a client in one runs the relays, and the
  reconnect box opens over it.
- **Protocol 10.** `TStatusHuman` has `Activity` (`TStatusActivity`: `saNone`,
  `saInTextQuest`, `saQuestDays`; a byte) and `QuestDays` (`THuman.QuestDaysOwed`), after
  `HoldsDay`. The host takes "in a quest" from the lock (`THuman.TextQuestOpen`), which
  its `BeginTextQuest` sets on the host as it arrives (the host's own human's at once)
  and the barrier's `CloseQuest` clears: so between a client's quest end and the
  barrier the status still says 1, but the human's `EndTurn` is queued then and the
  day does not wait for it, so no wait names it. Phase D's `QuestPage` (kind 18) can go
  under 10 or bump to 11; nothing reads the version but `Hello`.
- **Waits** (`NetPlay.HostWaitText`, `ClientWaitText`, both now exported for the
  tests): a human the day waits for who plays a quest is named "Name (text quest)"
  (`Multiplayer.InTextQuest`); a human who owes days gets a line "Name is busy with a
  text quest for N more days." (`Multiplayer.QuestBusy`); English fallbacks as the
  other texts. The client logs each change of a human's activity in the status (`net
  status human= activity= quest-days= holds=`).
- **The quest's own day.** Found on the way: a client's `CloseQuest` runs there at once
  (the prediction), so its copy owes the days and `EndTurn` sent nothing, while the
  host's copy has the days only after its barrier and waits for that `EndTurn`: a
  deadlock. `NetEndTurn` now sends the `EndTurn` itself in that case
  (`ClientQuestDayEnds`: the human owes days here, the last state said it owed none,
  `TNetClient.StateQuestDays`, and it has not ended this turn). On later owed days it
  sends nothing: a stale `EndTurn` in the host's queue would end the human's first
  turn after the days.
- **Owed days** (`NetPlay.NetQuestDayDue`, `MayCancelEndTurn` false while the human
  owes days): `TfPlanet` and `TfPlanetNO` poll every 250 ms (`NetScreenPollMs`) in a
  session, with nothing above them, and end the turn by themselves while the local
  human owes days, through their own `EndTurnClicked`: the host's then waits for its
  peers and runs the day, a client's waits for the next state, which reopens the
  screen. The same poll refreshes the quest prompt when the planet's lock changes.
- **The planet screens' grey-out.** A `BeginTextQuest` is relayed as
  `RelayedTextQuest` (610, relay only, `aQuestActions.RelayedTextQuestOf`), which sets
  the actor's lock without the checks: relayed as itself it failed on the other
  clients, whose copies do not have the actor's quest (`offer-gone`). The prompt shows
  "Name is playing this quest." (`Multiplayer.QuestTaken`, `TextQuestTakenText`) and
  hides its start button (`aQuestActions.TextQuestHolder`). A client's own
  `BeginTextQuest`, which runs there only after the host applied it, no longer checks
  other humans' locks (a relayed one may be stale after a disconnect).
- **Disconnects.** `TNetHost.DisconnectHuman` releases a human's lock (`net human N
  (name) abandoned its text quest planet=`); its queue goes with the peer as before, so
  the quest's commands after `BeginTextQuest` never apply. A client whose rejoin state
  comes while its quest screen runs (`ClientQuestScreen`) abandons the quest
  (`TfPlanetQuest.AbandonQuest`, `TQuestRun.Abandon`: no `CloseQuest`), applies the
  state and shows `Multiplayer.QuestAbandoned` as a bubble after it; a client whose
  reconnect fails leaves the quest for the main menu the same way.
- **Phase B's edge case.** A prison, queued or named quest whose `BeginTextQuest` is
  refused (only a networked client's unanswered trade can refuse it) now starts all
  the same (`TQuestRun.BeginRun`), instead of returning to a screen that would open the
  quest again. `TQuestRun.Close` sends no `CloseQuest` for a refused run.
- **Tests.** `--sim-net-quest=DAY` (host, clients, and the replay, which registers the
  probe `NetQuestProbe`, 1003): see docs/network.md, Tests. `tools/test.py`
  (`check_network_quests`) runs per save: two clients at one planet (Net1 plays the
  planet quest; the host's status says `activity=1`; its barrier applies the quest's
  commands, `net host quest begun=1 barrier= closed=1 early=0`; the host's and Net2's
  waits say "(text quest)"; Net2 sees the relayed lock and is refused `in-use`; hashes
  and the host's log replay), one client playing `Prison` by name (owes 23 days on
  AutoSave: each state owes one less, the host runs its days without it and its wait
  says it is busy; hashes, replay), and one client silent after one choice (the host
  times it out and releases the lock, its barrier applies none of the quest; the
  client abandons the quest after the reconnect and the planet's quest is still there).
  `HeadlessQuest` gained `Step`; `GiveProbePlanetQuest` is shared from `HeadlessSim`;
  the client's day line has `quest-days=`; `NetClient.ClientStatusHook` is for the
  tests.
- Left: the watchers (Phases D and E). A released prisoner who owes days still takes
  off (`HangarScreen.TryTakeOff`), and the star map ends its turns only when the player
  does; the screens' poll, grey-out and abandon box are hand checks.

### Phase D — Pages to the watchers

- Goal: every machine has the latest page of every other human in a quest.
- Files: new `source/quests/QuestPage.pas` (record, encode/decode, hook);
  `NetProtocol.pas` (kind 18), `NetHost.pas`, `NetClient.pas`, `NetPlay.pas`,
  `QuestRun.pas`, `HeadlessNet.pas`, `tests/TestNet.pas`.
- Steps: the run calls `QuestPageHook` after each page and at the end; the
  client sends; the host stores and broadcasts, and sends the abandoned end
  page on a disconnect; the client caches per human and drops the cache on
  reconnect.
- Headless tests: in the `--sim-net-quest` run with two clients, Net2 and
  the host print the page count and the last page's hash for Net1
  (`net quest pages human= count= last= end=`); they must equal Net1's own.
  A silent Net1 gives `end=abandoned` on Net2. Unit tests: page codec round
  trip; the client's cache against the scripted host (`TestNet`).

#### Phase D notes (done)

- **`source/quests/QuestPage.pas`.** `TQuestRunOutcome`, `TQuestChoiceAction`,
  `TQuestChoice` and `TQuestPage` moved here from `QuestRun` (units that name
  them use `QuestPage`; `QuestOutcomeName` moved here from `HeadlessQuest`).
  `TWatchedQuestPage` is what travels: the human id, the run's number on the
  player's machine (from 1, per process), the page's number in the run (from
  1), the quest's name (its number or file name) and the `TQuestPage`; a
  choice travels as its text and enabled flag only (its action and value stay
  with the player). A page with an outcome is the end page. The codec
  (`EncodeWatchedQuestPage`, `DecodeWatchedQuestPage`, which refuses a bad
  outcome byte or choice count) and `WatchedQuestPageHash` (the hash of the
  encoding, so it is the same on every machine); `AbandonedQuestPage`.
  `QuestPageHook` is the seam.
- **The run** (`TQuestRun.PublishPage`): after `View.FinishPage` (the start and
  each choice) and in `Close` (the end page, unless the outcome's page was it;
  abandoned when closed without one, `Abandon` too), when the hook is set and
  the run is a game's (a local human, not the main menu's quest). Nothing is
  published after the end page; a refused run publishes nothing.
- **Protocol 11.** `QuestPage` (18, both ways). A v10 peer would ignore the
  kind and silently have no pages, so the version went up instead of keeping
  10: a peer either watches or does not join.
- **The store** (`TQuestPageStore`): the latest page per human; `Latest(Id)`,
  `Playing(Id)` (its latest page has no outcome), `PlayingHumans(ExceptId)`,
  `ChangeCount` (one more per page, for the window to redraw), `Clear`. The
  host's (`TNetHost.QuestPages`) and the client's (`TNetClient.QuestPages`)
  both keep their own human's too; `NetSession.QuestPages` is whichever this
  machine has (nil without a session). That is Phase E's API: who plays is
  `PlayingHumans(LocalHuman.Id)` (or the status's activity), the page is
  `Latest`, and a change is `ChangeCount`.
- **The flow.** `NetSession` sets the hook (`SessionQuestPage`) in
  `StartHosting` and `JoinGame` and clears it in `StopNetwork`. A client sends
  its page (`TNetClient.SendQuestPage`, as its own human's, only when it may
  send: not between a loss and the state after the reconnect). The host takes
  a peer's page at any time (also while a job runs: it touches no game state),
  names the peer's human in it, keeps it and sends it to every joined peer but
  the player's; its own human's page goes the same way
  (`TNetHost.PublishQuestPage`). On a disconnect of a human whose latest page
  has no outcome the host keeps and sends an abandoned end page after it. A
  join or rejoin gets the latest page of each other human's open quest right
  after its `Welcome`. A client empties its store when it loses its host
  (`DropConnectionState`, also at the reconnect's `Welcome`, before those
  pages). Every page is a `NetLog` line (`quest page sent|relayed|received|
  caught-up|abandoned human= run= page= hash= end= choices= [to=]`), in the
  game's log too, as the trades are.
- **Spectating changes nothing.** A page is no command (not submitted, not
  logged, not relayed as one), is not in a state and not hashed; the runs of
  the existing checks keep their hashes and replays, and the goldens are
  unchanged.
- **Tests.** `TestNet.RunQuestPageTests`: the codec round trip (a choice's
  action is not carried; equal hashes; an unknown outcome and a negative count
  are refused), the store, and a client against the scripted host (keeps the
  host's pages, sends its own as its human's, drops them on a lost connection,
  sends none while it reconnects). `tools/test.py`: `check_net_quest_lock`
  checks that Net1's pages reach the host (`relayed`) and Net2 (`received`) as
  sent, in order, ending with the end page, that both keep the last one (`net
  host|client quest pages`), and that Net2's refused quest sent none;
  `check_net_quest_abandon` that the host relayed a start of Net1's pages and
  then its abandoned end page (numbered one after the last it got), and that
  Net1 sent no end page; the new `check_net_quest_host` has the host's own human
  play `Prison` by name (`--sim-net-quest` with `--sim-text-quest` on the host,
  `HeadlessSim.PlayQuestTurn`, now exported) with two clients: all its 207–323
  pages reach both clients in order, every state's hash is the host's, and the
  host's log replays. Two fixes the new check needed: a silent client flushes
  what it sent before it freezes (`TNetClient.FreezeConnection(True)`;
  otherwise the host could have none of its pages), and a headless client
  counts each page it gets as progress (the host's prison quest of 300 choices
  took over the 120 s stall timeout under the parallel test load).
- Plan deviations: the abandoned end page is checked on the host, not on a
  second client (the silent run has one client); the host also sends the open
  quests' latest pages to a joining client, which the plan left open.

### Phase E — The watch window

- Goal: the UI of section 2, Watching.
- Files: new `source/screens/NetQuestWatch.pas`; `NetPlay.pas` (wait loop,
  the `W` line), `NetMenus.pas` (the round-menu button).
- Steps: the box, built in code like the join dialogs, renders a
  `TQuestPage` (reuse the quest screen's text formatting by moving
  `SetQuestText`'s paragraph builder into a shared routine); the wait loop's
  "watch" result; the menu button; closing rules.
- Tests: keep the decisions (which page, when to close) in a pure function
  and unit-test it. The window itself is a hand check, listed in the status
  with the other hand checks. No window is opened by any test.

### Phase F — Docs and status

- `docs/network.md`: Messages (18, version 10, `Status`), Trades
  (`BeginTextQuest`), Waiting (texts, watch), Disconnects (abandon), a
  "Text quests" section, Tests, Not done yet.
- `docs/commands.md`: 609, `CloseQuest`'s new integer, 606/607 behaviour.
- `docs/humans.md`: the flag table, the save block version 4, "Not covered"
  (text quests no longer off), Scripts (text quests per human).
- `ROADMAP.md` Phase 6: the text quests row.
- `docs/progress/README.md`: status.

## 4. Risks and open questions

- **Owner decisions** (decided 2026-10-19):
  1. Days in a quest: the quest runs no galaxy day in multiplayer; afterwards
     the human owes those days and does not hold them, and the others play on
     without waiting for it (the default).
  2. Death in a quest in multiplayer: the ranger is killed and respawns as
     after a ship loss (not the default "count as a failure"). Single player
     keeps ending the game.
  3. Watching: the `W` key in the wait boxes and a button in the in-game
     menu (the default; Phase E).
  4. The flag: text quests are always on in multiplayer; the
     `text-quests` session flag is removed as a switch (not the default
     "kept, quests on"), with protocol and save compatibility kept.
- Two humans predicted an offer to the same planet on the same day: the
  host's barrier gives the second a different planet or none, and that
  client sees it only in the next state.
- `SetQuestVariables` with no script writes shared variables. Two humans in
  quests with `ext_` parameters at the same time overwrite each other at the
  barrier, last in `Session.Humans` order. Rare; accepted.
- The watcher sees the player's language.
- A player who leaves the keyboard inside a quest holds the day, as on any
  screen. No timer (Phase 6).
- `ArcadeDefeat` frees a human in multiplayer, like `DieInQuest`. Out of
  scope here; worth its own fix.
- The engine's stream `TextQuestRandomState` is a global. Only one quest
  runs per process, which holds as long as the watchers do not run the
  engine.
- Quests whose pages depend on days passing in the galaxy (money or
  variables changing between quest days) see no change under owed days.
