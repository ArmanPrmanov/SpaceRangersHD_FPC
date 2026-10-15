# Networking

Humans on different machines play one game (ROADMAP.md, Phase 5). The model is
**host-authoritative state streaming**: only the host runs the day. Clients run
the game UI on a copy of the state, send every command to the host, and replace
their copy with the host's state after each day. This page is the design; the
code follows it, and a change to the design changes this page first.

Read [humans.md](humans.md) (the barrier, hot-seat, `ActingHuman`) and
[commands.md](commands.md) (commands and the log) first.

## Units

| Unit | What it holds |
| --- | --- |
| `platform/net_native.c`, `platform/NetNative.pas` | sockets (Winsock / BSD) and zstd |
| `source/net/NetTransport.pas` | `TNetConnection`: length-prefixed messages over TCP; `TNetListener` |
| `source/net/NetDelta.pas` | `CompressState` / `ExpandState`: whole states, deltas (zstd with the old state as reference, like `--patch-from`) and films |
| `source/net/NetProtocol.pas` | message kinds, their encoding, protocol version, the data hash |
| `source/net/NetThread.pas` | the network thread: owns every socket, moves bytes, queues whole messages per peer |
| `source/net/NetHost.pas` | the host session: peers, joins, commands in, states and films out |
| `source/net/NetClient.pas` | the client session: hello, commands out, films and states in |
| `source/net/NetSession.pas` | what the rest of the game calls: role, pump, hooks |
| `source/observer/HeadlessNet.pas` | the headless host and client for tests (Tests) |
| `source/screens/NetPlay.pas` | the game's screens in a session: `--host`/`--join`, the waits, the client's film and state (The day, Films, Applying state, Waiting) |
| `source/screens/NetMenus.pas` | the main menu's join and the in-game menu's host and stop (Hosting and joining) |

`source/game`, `source/core` and `source/script` do not use `source/net`. The
game layer exposes hooks (procedure variables, as `BeforeCommandHook`); the net
units set them. `tools/check_layers.py` keeps that direction.

| Hook (game layer) | Set by | What for |
| --- | --- | --- |
| `ThreadCalc.StarDayHook` | host | the film of each filmed star after its `NextDay`, on the turn thread |
| `ThreadCalc.DayCompletedHook` | host | the player-star job has run the day; the pump sends the films |
| `aCommands.NetworkCommandHook` | client | every command the client submits goes to the host; called after `AfterCommandHook`, so the command log and the network both listen |
| `aHuman.RemoteTalkHook` | host; the command log's replay | the turn thread asks a remote human something (Remote dialogue) |
| `aHuman.NewHumansConnected` | host | humans a load or a join adds start disconnected |
| `aCalc.TurnWaitPumpHook` | `NetPlay` | the UI thread pumps while it waits for a job (`WaitForTurnCalculationUI`, `Calculate*AndWait`) |
| `ThreadCalc.TurnJobsForbidden` | `NetPlay`, client | starting a job raises: a client never runs one |

`GR_Main.FramePumpHook` (a root unit, not the game layer) is how `NetPlay` pumps
once per message-loop iteration.

## Threads

- **The network thread** owns the listener and every connection. It waits on
  the sockets (a few ms), sends what is queued, and cuts received bytes into
  messages, which it appends to the peer's inbox under one lock. It sets
  `NetInboxEvent` when a message arrives. It never touches game state.
- **The UI thread** pumps the inboxes once per frame (`NetPlay`'s frame hook,
  `GR_Main.FramePumpHook`, called by `GR_WinMessage`) and at the safe points
  below. Everything that changes the game from the network happens in the pump
  or at a safe point, never on the network thread. Where the UI thread blocks
  during a day it pumps too: `WaitForTurnCalculationUI` through
  `aCalc.TurnWaitPumpHook`, and the star map's waits for a job or a talk
  (`NetPlay.NetWaitForEvents`). These are loops with a 10 ms timeout rather than
  waits on `NetInboxEvent`: the star map waits on the platform shim's handles
  (`platform/Windows.pas`), which a `TEvent` handle is not. The host takes no
  join, leave or state while a screen that has no game (the menus, a load, a
  new game, a text quest, an arcade battle) or a memory snapshot is up.
- **The host's pump while a job runs** only moves messages into the queues:
  new peers wait for the job (the turn thread reads the peer list in
  `HostStarDay`), and so does `Status` (a job may free a ranger whose name it
  reads). Commands, joins and leaves wait for a quiet point as before.
- **The turn thread**, on the host, reads one peer's inbox only while it waits
  for that peer's human to answer a dialogue (Remote dialogue). The pump leaves
  that inbox alone meanwhile (`THostPeer.InTalk`, under a lock), and handles
  what the turn thread left for it (`THostPeer.Deferred`) first afterwards. It
  also sends `Status` before the talk and after it (the pump sends none while a
  job runs, so the two never overlap).
- **A client's connect** runs on a thread of its own (`TNetConnectAttempt`), so
  that the join can show its progress and be cancelled; the connection then
  goes to the network thread (`TNetThread.AddConnection`). A cancelled connect
  closes its connection when it comes.
- Sending is thread-safe: it appends to the peer's outbox under the lock.

## Messages

A message is a 4-byte little-endian length, a kind byte and the payload
(`NetTransport`). Payloads are `TBufEC` encodings. Kinds are part of the
protocol; never renumber one, add new ones at the end and bump
`ProtocolVersion` when a payload changes.

| Kind | Direction | Payload |
| --- | --- | --- |
| `Hello` | client → host | protocol version, game version text, data hash, human name, whether it spectates |
| `Welcome` | host → client | the client's human id, the host's name |
| `Refuse` | host → client | reason text; the host then closes |
| `State` | host → client | state number, base state number (0 = whole), day number, state hash, zstd bytes (`NetDelta`) |
| `Film` | host → client | day number, star id, zstd bytes of the film (`TEFilm.SaveToBuffer`, `CompressState` with no reference) |
| `Command` | client → host | the client's number for the command (32 bits, from 1 per connection), then an encoded `TPlayerCommand` (`aCommands.EncodeCommand`) |
| `Ack` | client → host | the number of the last state the client applied |

The host numbers its states from 1. A day number cannot name a base: a join
between two days sends a state of the same day as the one before it.
`ProtocolVersion` is 6 (2: `TalkRequest` has its payload; 3: `Status` names
the human whose answer to a dialogue the day waits for; 4: `NewHuman` and
`Character`; 5: `Film` is compressed; 6: `Command` carries the client's number
for it, and `CommandResult`).
| `Status` | host → client | per human: id, name, connected, holds the day; whether a day is running; the human whose answer to a dialogue the day waits for (0: none) |
| `TalkRequest` | host → client | human id, ship id, planet id (0: none), scripted, talk kind, amount, text: the human's talk fields (Remote dialogue) |
| `TalkDone` | client → host | nothing: the client's answer is complete, or it cannot show the talk |
| `Chat` | both | sender human id, text; the host relays it to every client |
| `Bye` | both | the sender leaves |
| `NewHuman` | host → client | nothing: the name is new, so the client chooses its character |
| `Character` | client → host | name, race, character preset, portrait, two starting skills, two starting items |
| `CommandResult` | host → client | the command's number (as in `Command`), its kind, applied (1) or refused (0), the reason (a byte, `aCommands.TRefusalReason`), the exception's text; sent for a refused command (Commands) |

## Joining

1. The client connects and sends `Hello`.
2. The host refuses when the protocol version or the data hash differs. Build
   hashes may differ, since platforms differ. It also refuses an empty name, a
   spectator (not supported yet), a name whose human is connected, and a join
   when no planet takes a new human.
3. The host takes the join at a quiet point: no turn job running and no day
   under way. A join that arrives mid-day waits in the peer's inbox. Joins
   that wait together are taken in name order.
4. **Rejoin.** When a disconnected human's ranger has the name the client
   gives, the client takes that human back. Otherwise it is a **first join**:
   the host sends `NewHuman` (`TNetHost.AskCharacters`, at a quiet point even
   while joins are held), and the join waits until the client's `Character`
   comes (`JoinReady`). The client's join box closes and the new-game screen
   opens (`NetPlay.NetCharacterScreen`, `TfGameSettings2`) without the
   difficulty panel and the extended rules, which are the host's game's; the
   name proposed is the join's. OK sends `Character` and the join goes on over
   the main menu (the session stays on the way there, `JoinResumes`); Cancel
   ends the join. The name in `Character` replaces Hello's, and is checked
   again when the join is taken (another human's name is a rejoin or a
   refusal). The host then submits the `JoinHuman` command (kind 44) as the
   host human, which adds a human landed at a coalition planet
   (`FindJoinPlanet`) of the chosen race if there is one, nearest the host's
   ranger (a ranger's race is its home planet's), with the choices applied as
   a new game applies them (`aHuman.JoinHuman`: portrait, the preset's careers,
   skills, items, then the preset's ship). With no planet of that race the
   portrait is the other race's first. The command carries the choices after
   the preset, so an older log replays as before. The command log records it.
   The headless test clients choose a fixed character.
5. The host sends `Welcome` and a whole `State`. The client loads it, makes its
   human the local one and opens its screen (Applying state).

A human who joins or leaves is a normal operation. Human ids are ship ids and
are never reused, so a log or a save can name a human who has left.

**The data hash** (`NetProtocol.DataHash`, computed once per process) is XXH64
(`sr_hash64`, chained over 1 MB chunks) over the packages `INSTALL.TXT` lists,
`CFG\Main.dat`, `CFG\CacheData.dat`, and every file of each selected mod except
its language files (`Install_*.txt`, `CFG\<language>\`), then the selected mod
names. The language packages and `Lang.dat` are left out, so players with
different languages can play together; settings are not files it reads. It
reads about 1.6 GB, which takes well under a second once the files are cached.

## Commands

- The client's UI submits commands as always. `SubmitCommand` executes the
  command at once on the client, which is the prediction, and the client's
  `AfterCommandHook` sends it to the host.
- The host refuses a command whose actor is not the peer's human, and queues
  the rest per peer. It does not execute them as they arrive: arrival order
  depends on the network, and the day's outcome must not.
- A peer is **ready** when its queue holds an `EndTurn` (kind 43), or when its
  human does not hold the day anyway (`HumanHoldsDay` is false: continuing
  travel, in hyperspace, finished) or is disconnected. A queue without an
  `EndTurn` is not applied; it waits for the day its `EndTurn` arrives,
  except a `StopContinuing` (Continuing travel), and a continuing peer must have
  applied the state before the last one. A
  command the peer sends while its human does not hold the day can race the
  host's apply, so it waits too rather than landing in whichever day it
  happened to reach.
- A queued command that raises when the host applies it is logged and dropped.
  The command log does not record it, and records the commands after it
  (`CommandFailedHook`, [commands.md](commands.md)). The same holds for a
  command of a remote dialogue.
- **Refusals.** The client numbers the commands it sends, from 1 per
  connection (`TNetClient.LastCommandSequence`). For a command that raises on
  the host, the host sends `CommandResult` to that client (`TNetHost.CommandFailed`,
  also from the turn thread in a remote dialogue) with the number, the kind, the
  exception's text, and a reason: an executor that can say why raises
  `aCommands.ECommandRefused` with one of `TRefusalReason`; any other exception
  is `rrOther`. The reasons (their byte, and the log's name):

  | Reason | Byte | Log | Raised by |
  | --- | --- | --- | --- |
  | `rrOther` | 0 | `other` | any other exception |
  | `rrOutOfStock` | 1 | `out-of-stock` | a purchase of goods beyond the stock (`TShip.CheckGoodsPurchase`) |
  | `rrNoMoney` | 2 | `no-money` | a purchase of goods or equipment, a refuel, reload or rockets the human cannot pay |
  | `rrItemGone` | 3 | `item-gone` | a shop command whose item (by id) the shop's stock no longer holds (`aShopActions.ShopItemArg`) |

  A reason the client does not know reads as `rrOther`. The host logs
  `command failed human= seq= kind= reason=`; the client logs `command refused
  seq= kind= reason=`, keeps the result for `TakeCommandResult`, and shows the
  refusal to its player as a message bubble of its human (`TNetClient.ShowRefusal`),
  with a `Multiplayer.Refused*` text: `RefusedOutOfStock` ("The host refused
  your purchase: not enough in stock."), `RefusedNoMoney`, `RefusedItemGone`,
  `RefusedOther` (English fallbacks, as Waiting's texts). The next state
  replaces the human's bubbles, so the client shows the refusals of the day
  again after applying it. Today the host sends `CommandResult` for refusals
  only; the message can also say that a command was applied (`Ok`), for a
  host that answers commands as they arrive.
- A purchase of goods that the stock or the money no longer allows raises
  (`TShip.BuyGoodsFromLocation`, which showed a Windows message box that
  blocked the host's day); the goods screen checks the same before it trades,
  and a purchase refused on this machine is only logged (`aShopActions.TradeGoods`).
- **The shop's columns.** The commands that build a shop grid carry the
  columns the sender's screen shows (`aShopStock.ShopVisibleColumnCount`), and
  the executor keeps them in the actor's `THuman.ShopColumnCount`, which pads
  that human's grid (`ShopColumnCount`): a client's command does not change the
  host's own grid. It is layout and is not saved; the grid itself is.
- **Shared shop stock.** The equipment a planet or station sells stays in its
  list while humans shop there; each human's grid is a view of it
  ([humans.md](humans.md), Shops). Two humans at one shop see the same items.
  A shop command names its item by id, so the slots that another human's
  purchase moved do not matter, and an item already bought is refused as
  `rrItemGone` before anything changes. A change to a shop's stock rebuilds the
  other humans' grids there (`aShopStock.ShopStockChanged`) and tells the local
  equipment shop screen (`SimEvents.NotifyShopStockChanged`); a host that
  applies a trade as it arrives, and a client that applies another human's
  trade, refresh the open shop that way.
- When the host's human has ended its turn and every peer is ready, the host
  applies the queued commands, human by human in `Session.Humans` order, each
  queue up to and including its `EndTurn`, through `SubmitCommand`, so the
  host's command log records them. Then the barrier
  (`AllHumansEndedTurn`) holds and the day starts. This is the order the merged
  hot-seat replay uses, so the same commands give the same day however they
  arrived. Commands after a peer's `EndTurn` stay queued for the next day.
- The host's own human is first in `Session.Humans`
  (`HostHuman`), and its commands execute at once, so they come first anyway.
- The exception is a remote dialogue: its commands execute as they arrive,
  on the turn thread (Remote dialogue).
- `EndTurn` is an ordinary command. There is no separate end-turn message.
- The client's copy is a prediction. Nothing on the client is reconciled: the
  next `State` replaces it. Where two humans compete (the last item in a shop),
  the host's order decides and the next state shows the outcome.

## The day

- **Host.** When the host's human ends its turn and some peer is not ready,
  the host's screen waits (Waiting). When the last peer becomes ready, the host
  applies the queues and starts the day from the screen that is waiting, as if
  its human had ended the turn again: `aPlayerActions.EndTurn` now returns true.
  Every screen that starts a day asks `NetPlay.NetEndTurn` where it asked
  `EndTurn` (the star map, the planet and station panels, the takeoffs from the
  planet, hangar and station, the jump screen); on the host it sends the last
  day's state if it has not gone, waits, applies the queues and calls
  `BeginDay` right before the player-star job (`HostDayMayStart`). Without a
  session it is `EndTurn`.
- **Host, continuing travel.** The star map's automatic continue ends the host
  human's turn (`EndTurn` with `ContinueUntilArrival`) during the film, but the
  next day starts at the film's end: there the state goes, the host waits for
  its peers, and the next player-star job runs (`TfStarMap.StartDeferredNetDay`).
  A break in the film, or a human who holds the day again, ends it as when the
  travel stops. Without a session the next day's job still starts during the
  film.
- **Client.** A client never starts a day (`ThreadCalc.TurnJobsForbidden`). Its
  end turn sends `EndTurn` and its screen waits until the host's film or state
  comes (Films, Applying state).
- **Client, continuing travel.** See Continuing travel below: the client's end
  turn asks the host to go on with its travel, and the host runs the next days
  without waiting for it.
- Hot-seat passes nothing in a session (`TurnPassesToAnother` is false): the
  other humans play on their own machines.

## Continuing travel

A travelling human's days follow one another without a click, as the star
map's automatic continue does in single player. For a client that used to cost
a round trip every day: the host waited for the client's end turn, which came
only after the client had played the film and applied the state. Now the host
does not wait for it:

- **The end turn asks for it.** A client's end turn is `EndTurn` with
  `ContinueUntilArrival` (not with the break key held, `BreakOnNextFilm`). The
  host's copy of the human then ends every later day by itself
  (`StartDayRound`) while `HumanTravelContinues` holds for it: a travel order
  it has not reached, no fight, no interruption. So the peer is ready at once,
  and the host starts the next day at its own film's end.
- **The state says so.** A state (the checkpoint, version 2) carries each
  human's `EndedTurn` and `ContinueUntilArrival`. After applying one, a client
  whose human continues opens the star map, sends nothing (its human does not
  hold the day) and waits for the next film (`OpenClientScreen`,
  `DeferredNetContinue`). When the host has stopped the travel, the human holds
  the day and the client is in order mode.
- **The break.** A break in the client's film sends `StopContinuing` at once
  (`TfStarMap.BreakTurnClicked`). The host applies a queued `StopContinuing` of
  a human who continues, with what comes before it, at its next `ApplyQueues`,
  without waiting for an `EndTurn`, so the next day holds for the client. When
  it came after the host had begun that day, it holds the day after; the state
  of the day it missed still says the human continues, and the client, whose
  film was broken, sends `StopContinuing` again (harmless) and goes to order
  mode. Its orders and end turn then wait in the host's queue for the day they
  reach.
- **Films ahead of the state.** The host may send the next day's film before
  the client has applied the last state. Films are kept per day
  (`TNetClient.TakeFilmOfDay`): the one to play after a state of day D is the
  film of day D (films are recorded before the galaxy job counts the day);
  films of earlier days go, and films of later days stay.
- **One day ahead at most.** A peer whose human continues is ready only when
  it has applied the state before the last one (`TNetHost.LagsBehind`), so the
  host runs at most one day ahead of a client and the client's films are not
  skipped. A client that falls behind anyway applies the newest state, drops
  the films it missed and plays on from there. It keeps its last two states as
  delta bases, since the host may take a state before the client's last
  acknowledgement reaches it.
- A disconnected human does not hold the day (`THuman.Connected`, see
  Disconnects).

## Films

The player-star job records one film per star that holds a human (`aStarFilms`).
Right after each star's day, on the turn thread, the host encodes the film of a
star whose `PlayerStar` humans include a connected remote human
(`StarDayHook`), once, and compresses it there (`CompressState` with no
reference, level 3, about 1 ms for a star's film of 70 KB), so the pump only
sends. After the job it sends the same bytes to every client whose human was in
that star (`Film`), from the pump as soon as the day has run
(`DayCompletedHook` marks it; the galaxy job may be running), or, headless, at
once. The film goes before the state: it is small and needed first. A day that
was not filmed sends nothing. The client expands it as it arrives
(`ExpandState`), so `TakeFilmOfDay` holds the film's own bytes.

A film compresses to about 0.63 of its size. The previous film of the same star
as a reference (as the state deltas do) saves only 14% more, measured over the
films of 10 days with 8 humans, so films go without one: a client that skips or
drops a film would need the same reference.

The client plays it on the star map as the history viewer plays a stored film:
the film's objects bind to the client's scene objects by kind, graphics key
and id, and objects the client does not have (missiles, drops, ships that
arrived that day) are created for the film (`fFilm.CreateFilmSceneObjects`,
`ReuseSceneObjectsForPreloadedFilm`). The client's scene objects are those of
its star's galaxy objects (`StarScene.OpenSpaceScene`: the star, planets and
satellites, asteroids, ships, items, missiles, holes, and the jump gates, which
films name with id 0); `NetPlay.TakeClientFilm` loads the film into
`PrimaryFilm`, binds it, and `StartTurnFilm` makes it `SecondaryFilm` as for a
film the client recorded. The client needs the new state at the end of the
film, since the end-of-film branch reads it (landed, docked, in hyperspace); it
waits there for the state when it has not arrived (`CompleteHostedTurnFilm`),
then the star map closes and the state is applied between screens.

A client plays a film when its ranger was in space or taking off when it
ended its turn, and only the film of its own star. Taking off from a planet,
the hangar or a station, the star map opens (through the load screen) and plays
it (`smrNetFilm`). A client that is landed, docked or in hyperspace plays no
film; a client arriving from hyperspace does not see the arrival film either
(its state before the day has no ranger in that star), and goes to the star
map in order mode.

## States

- **What.** `WriteGameCheckpoint` (`aSaveLoad`): the galaxy as the save writer
  writes it, the per-human block with every human, the exact values and the
  local human's state. It touches no screen and changes nothing. The host takes
  it on the UI thread at a quiet point after the day: no job running and the
  next day prepared (`Session.PlayerStarDayPrepared`), or, when the host's
  screen does not prepare days (landed, docked, in hyperspace, headless),
  after the galaxy job. Only the star map prepares days (after its film), so on
  the star map the state waits for the preparation; on any other screen it goes
  after the galaxy job (`NetPlay.QuietAfterDay`, from the frame hook). A star
  map whose travel goes on (`NetDayDeferred`) prepares no day, so its state goes
  as soon as the galaxy job has run, while the film plays: the next day then
  starts at the film's end without taking it, and the clients have it by the
  end of theirs. A day
  taken off from the hangar or a station is sent there, before the star map
  prepares the next one. The next end turn sends a state that has not gone yet
  before it waits for the peers.
- **Deltas.** The host keeps the uncompressed states that some client may still
  use as a base: each client's last acknowledged day, and the newest. A state
  goes to a client as a delta against its acknowledged day (`CompressState`
  with that state as reference), or whole when it has none. Clients with the
  same base get the same bytes; the host compresses once per base. The
  compression runs on the network thread.
- **Hash.** `State` carries the host's `GalaxyStateHash`, taken with the
  host's human local. It is a second serialisation on each side every day, so
  only debug builds and the headless tests take it (`NetProtocol.StateHashes`);
  otherwise it is 0 and the client does not check it. `--net-dump=DIR` writes
  the hashed bytes of each state on both sides (`host-state-N.bin`,
  `client-state-N.bin`) with the offset of each object in them (`.index`), to
  find where a desync starts. The client hashes right after `ReadGameCheckpoint`, while
  the host's human is still the local one, and only then makes its own human
  local; the hash starts with the local human, so hashing after the switch
  could never match. A difference is logged as a desync. It checks that the
  checkpoint is a faithful serialiser, not only the transport: loading a state
  and writing it again must give the same state.
- **Ack.** A client acknowledges a state after applying it, and keeps those
  uncompressed bytes as the base of the next delta. The host keeps its last
  four states and each client's acknowledged one.
- **A fresh local human.** A load fills the local human's state into the
  `THuman` that is local, and on a client that is its own human. So the client
  first calls `aHuman.ResetHumans`, which gives the local human a new `THuman`,
  as at startup; otherwise its own human's lists (the shop, old quests) would
  mix into the host's.
- **What a checkpoint cannot carry.** A shop grid left open while its human's
  ranger is in space is dropped by a load (`aShopStock.AdoptLoadedShopView`
  keeps a grid only while landed or docked). Its items stay in the shop: a save
  writes them there, not in a grid away from its ranger. The screens close the
  grid on leaving anyway; the headless turn takes off with `tfReturnShopStock`.

## Applying state (the safe point)

Loading a state frees every galaxy object, and screens hold direct references
to ships, planets and items. So a client applies a state only at a safe point:

- The client is waiting (its human ended the turn), so it is on one of the
  screens that start a day (star map, planet or station panel, jump screen),
  and no shop, dialogue or other screen is open above it.
- The waiting screen closes, and the state is applied between two screens, where
  hot-seat applies a turn pass (`HotSeat.ApplyTurnPass`, then
  `NetPlay.NetBetweenScreens`): `ReadGameCheckpoint`, then `SetLocalHuman` back
  to the client's own human (the state was written with the host's human as
  local), then the human's screen opens: the planet, the station, the jump
  screen or the star map centred on its ship. The star map rebuilds its scene
  and background when it opens; a new star goes through the load screen first,
  as after a takeoff.
- **The space background** is in the state, and it is the host's screen's. The
  client keeps its own when its star did not change, and generates one for a
  new star, as hot-seat does.
- **The end of a film.** After a film, the star map's end-of-film steps run on
  the new state, as commands of the client's human that go to the host with its
  next day's: the engine wears after a landing (`ApplyLandingWear`) and the
  scripts run for a jump into a black hole (`RunScriptTurns`). So a remote
  human gets them too, a day later than a local one. The old hyperspace arcade
  battle and the Terron planet battle are not offered to a client; it goes to
  the jump screen or the station.
- **In hyperspace** the host runs the client's steps and does not wait for it;
  the jump screen applies each state that comes (`ClientTravelTick`) and opens
  again, until the ranger arrives.
- **Poisoned frees.** A debug build started with `--poison-frees` fills freed
  memory with a pattern and holds it back from reuse for a while, so a stale
  reference fails at once instead of following a new object at the same address
  (as a script's reference to a freed item did, ef2e7da).
  [PoisonFrees](../platform/PoisonFrees.pas) wraps the memory manager as the
  first thing `ReadOptions` does: a freed block is filled with `$DE` bytes and
  queued in a FIFO quarantine of 128 MB (`--poison-frees=MB` for another size)
  before it is really freed; a block larger than a quarter of the quarantine is
  poisoned and freed at once. A block that moves when it is resized is
  poisoned too; one that shrinks by at most half stays and has its tail
  poisoned. The wrapper has no header of its own, so blocks allocated before
  it free like its own; one lock guards the quarantine, since the UI, turn and
  network threads all free. Release builds compile it out and refuse the flag.
  `python tools/test.py --poison-frees` passes it to every game run.
  - **Recognising it.** A freed object's VMT reads `$DEDEDEDEDEDEDEDE`, which is
    not a valid x64 address, so a virtual call, `is`, `as` or `Free` through a
    stale reference, or a pointer or string field read from it, faults at once.
    Windows reports a fault on such a non-canonical address at
    `$FFFFFFFFFFFFFFFF`; the session log's backtrace is followed by a
    `Poisoned frees:` line that says whether the address was poisoned (the
    pattern plus an offset, or `$FFFFFFFFFFFFFFFF`). A value read from a freed
    object is `$DEDEDEDE` (-555819298) as an Integer, `$DEDE` (57054) as a
    Word, 222 as a Byte, about -1.2e148 as a Double: seen in a log, a hash or a
    dump, it came from freed memory.
  - A block freed twice while in the quarantine raises `EInvalidPointer` ("was
    freed twice") at the second free. A write to a quarantined block is found
    when the block leaves the quarantine; shutdown flushes it and logs
    `Poisoned frees: ... N written after free (first at $ADDRESS, offset K)`,
    also on stderr in a headless run when N is not 0.

## Waiting

A screen that waits for the day shows who it waits for (from `Status`: the
humans who hold the day, and who is disconnected), stays modal and does not
change the game. On the host it waits for the barrier; on a client it waits
for the film or the state. A remote dialogue can open above a waiting client
screen. While the host's day waits for a remote human's answer to a dialogue,
every other client's wait says so ("Waiting for Guest to answer a hail",
`Status.TalkHumanId`), and so does the host: its waits for a job (the star
map's `NetWaitForEvents`, `aCalc.TurnWaitPumpHook`) open a box
(`NetPlay.HostTalkWait`) until the talk ends, only over a screen that runs
(`RunningScreenLoop`: the loop on top of `MessageLoopStack` is the innermost
screen's).

The wait is a message box without buttons (`NetPlay.TNetWaitBoxGI`) over the
innermost screen; it pumps every 20 ms, closes by itself, and opens again with
the new text when the text changes. The texts come from the language data with
an English fallback, as `Multiplayer.Turn` does: `Multiplayer.Waiting`
("Waiting for <Players>."), `Multiplayer.Away` ("Away: <Players>."),
`Multiplayer.DayRuns`, `Multiplayer.WaitingHost`, `Multiplayer.WaitingPlayers`,
`Multiplayer.WaitingTalk` ("Waiting for <Players> to answer a hail."), the
join's `Multiplayer.JoinConnecting`, `JoinWaiting`, `JoinReceivingStart`,
`JoinReceiving`, and for the main menu `Multiplayer.Refused`,
`Multiplayer.Lost`, `Multiplayer.HostLeft`, `Multiplayer.NoState`. None is in
the game's language data. The only way to add texts to it is a mod: a selected
mod's `Mods\<mod>\CFG\<language>\Lang.dat` is merged into it
(`GR_Main.LoadDatConfigAndModOverrides`), in the game's binary `.dat` format. The port
ships no data files of its own (the build places the executable and its
libraries only), and a mod the players must select is not a fit for a few
texts, so the English fallbacks stay.

A client that loses its host, or is refused, shows why on the main menu and
the session ends there. A client that loses its host while it plays its turn
notices it in the per-frame pump (`NetFrame`) and goes to the main menu, which
says why, at the next safe point: when a screen that starts a day is the one
running (the star map, the planet, uninhabited planet, station, hangar or
jump screen, with no box or dialogue above it, `LostHostLeaveScreens`), not
while the star map plays a film (its end leaves anyway), and never from a shop
or the ship screen, which move goods when they close. It does not offer to play
on offline: the client's copy is a prediction the host no longer backs.

## Remote dialogue

During the host's day an NPC may ask a human something: a demand for money or
cargo, a truce offer, a request to attack, a partner's complaint
(`TShip.ShowPlayerDialogue`, `OpenPlayerConversation`). The conversation
machinery addresses the human asked, not the local one: the talk fields and
`TalkResponse` are that human's `THuman`'s, `PlayerDialogueRequestCount` too,
and every talk command acts on its actor's. For the local human the turn thread
waits while the UI thread shows the talk screen, as before. For a remote one:

1. **Who is asked.** A site asks `aHuman.CanAskHuman`: the local human, or,
   where a session can ask remote humans (`RemoteTalkHook` is set), a connected
   human who has not finished. That answer is recorded (the query
   `sqRemoteTalk`). A human who cannot be asked answers automatically, as on
   automatic control, as before. The entry conditions are the local human's
   (in normal space in the ship's star, a job running, no special mode), except
   the screen: the host's screen holds back only its own human.
2. **Host.** The turn thread sets the human's talk fields (`TalkShip`,
   `TalkPlanet`, `TalkType`, `TalkAmount`, `TalkText`, `TalkScripted`) and,
   inside `BeginTurnWaitForUi`, calls `RemoteTalkHook`
   (`NetHost.TNetHost.RemoteTalk`). It sends `TalkRequest` and reads that peer's
   inbox only: each `Command` of the human runs at once through `SubmitCommand`
   with `InTurnJob` off, so it is actor checked and the command log records it in
   the talk's wait exactly as a local human's answer (a command that raises is
   logged and dropped); an `EndTurn` waits for the next day; acknowledgements,
   chat and `Bye` wait for the pump. `TalkDone` ends the talk and the day goes
   on with the answer in the human's `TalkResponse`.
3. **Client.** The request is kept until the client's wait takes it
   (`NetPlay.WaitModal`, which also covers the wait at the film's end): the box
   closes, the star map's talk screen opens on the state before the day for the
   ship the request names (`TfStarMap.RunTalkDialogs`, as for a local talk), its
   answers are commands, predicted and sent as usual, then `TalkDone`, and the
   wait opens again. A request that comes while the client plays the host's
   film on the star map (`ClientFilmPlaying`) waits for the film's end, where
   the wait for the state answers it; it waits `ClientTalkHoldMs` (60 s) at most
   and is declined after that, so the host's day is not held for long
   (`TNetClient.MayHoldTalk`). The film is not paused: it shows the day before,
   and the talk screen needs the star map in order mode. When it cannot show the
   talk (the ship is not in its state, its ranger is not in normal space in that
   star, the star map is not the open screen, or no wait is open and no film
   plays) it sends `TalkDone` at once. The headless client answers a scripted
   talk with its first answer (`AcceptScriptedTalk`).
   In the present flow a talk reaches a client before the film of that day (the
   talk is in the player-star job, the films go after it), and the next day
   waits for the client's end turn, so a talk during a film needs a client that
   does not hold the day; the hold is for that case, and the tests make it
   happen (Tests).
4. **The end.** When the peer leaves (`Bye`), its connection closes, the host
   stops, or no `TalkDone` comes within 10 minutes (`RemoteTalkTimeoutMs`), the
   talk ends; the host logs how (`talk with human N ended: ...`).
   `OpenPlayerConversation` then returns False and the talk ends as one the
   screen could not show: the caller gets no answer (0), whatever commands had
   already run. It is not answered automatically afterwards: the NPC's side
   has already been decided by then.
5. **Replay.** The host's log holds the `sqRemoteTalk` answers (who was asked,
   and whether the talk ended with `TalkDone`) in the job's answers, and the
   human's commands in the job's talk wait. The replay sets its own
   `RemoteTalkHook`, which asks for the talk as the local one does, so
   `ReplayJob` runs the recorded commands; the recorded answers decide the rest.
   A log without a session (hot-seat) never asked, and the replay takes that as
   "nobody remote is asked".

Every other human waits meanwhile, as for any dialogue: the day is paused.

**What stays with the local human.** A script's dialogue (`SF_Dialog`, and
`TPlanet.RequestDialog`, which only it calls) opens only for a script of the
local human, as before: its text and answers are written into this machine's
talk screen by the script's `DText`/`DAnswer` builtins while the day runs, and
its answers run the script's answer code, so a client could not show it from
its own state. Deploying a tranclucator while docked stays with the local human
too: it opens a screen, not a dialogue a client could answer mid-day.

**A client's script code on the host.** The host runs a client's commands, and
so the client's script code, with `ScriptHuman` the client's human. The script's
game effects happen there as on the client, but the UI builtins touch nothing
of the host's: a box, a form or a screen change gives a declining player's
answer and is logged, the dialogue text and answers (`DText`, `DAnswer`) are
not written into the host's screens, music and video do not play, and the talk
builtins read the talking human's talk ([humans.md](humans.md), Scripts). The
client, which runs the same command on its prediction, shows all of it on its
own screen. Its takeoff and end-turn requests (`ExtremalTakeOff`,
`ForceNextDay`) are its human's: the client dispatches them as its own
`OrderScriptTakeoff` and `EndTurn`, and the host does not act on them for its
own human. Entering or leaving ruins mode (`EnterRuinsMode`, `CloseBridge`)
changes the client's human's state and opens no screen on the host. A queued
arcade or planet battle or video that the client's command starts is queued on
both for the client's human: the client plays it and reports the outcome by a
command, which finishes the client's request on the host, never the host's
own. One that the host's day or another human's command starts for the
client's human is not started, since the client never sees it. A command that
a client's command submits from inside it is the client's human's (the actor
of the executing command, or the script's human), not the host's.

## Disconnects

- A peer whose connection closes, or who sends `Bye`, is disconnected:
  `THuman.Connected` is false, the human does not hold the day, and its ranger
  holds position (the host submits `HoldPosition`, kind 46, as that human,
  unless it is in hyperspace or finished: no order, no follow target, and
  automatic control off, so it does not fly on without its player). It stays in
  `Session.Humans` and in saves. The host handles disconnects at the next quiet
  point, in `Session.Humans` order, before joins, and drops the peer's queued
  commands. A rejoin restores nothing: the human takes its ranger back as it
  stands.
- It rejoins by joining with the same ranger name (Joining).
- Humans in a save that the host loads start disconnected, except the host's.
- `Connected` is not saved; it is session state, not game state.

## Hosting and joining

- Command line: `--host=PORT` hosts the game that runs, from the first game
  screen that opens (with `--load-save=PATH`, after a new game, or after a load
  from the menu); port 0 picks one, and the log says which (`Network: host
  listens on port`). The host's name is its ranger's. `--join=HOST[:PORT]
  --name=NAME` joins one after the startup load: it connects, waits for the
  whole state (60 s at most), applies it and opens the human's screen. A refusal,
  a failed connection or no state go to the main menu with a message. `--join`
  takes no `--host` or `--load-save`. An address without a port takes
  `NetPlay.DefaultNetPort` (47300), which the menus also propose. The join
  itself runs over the main menu (`NetPlay.RunPendingJoin`), for `--join` as
  for the menu's entry: a box shows its progress (connecting to the address;
  connected, waiting for the host to let the client in; receiving the game,
  kilobytes received of the state's size) and has a Cancel (also Escape), which
  ends the session (`Bye`) and stays on the main menu. The box gives up after
  60 s without progress (no new phase and no new bytes). Once the whole state
  has come the main menu closes and the state is applied between screens.
- **The main menu joins** (`NetMenus`): a Network game entry in the row of
  Mods (a copy of the Mods button, which has the only fitting picture, and of
  its label; the J key too) opens a dialog for the address (`HOST` or
  `HOST:PORT`) and the name. The last address and name are kept in the user
  settings (`NetJoinAddress`, `NetJoinName` in `cfg.txt`); the first name
  proposed is the new-game screen's. Join closes the menu and the join runs
  between screens exactly as `--join`'s does (`NetPlay.RequestJoin`), so its
  failures come back to the main menu as a message box, and the join shows its
  progress and can be cancelled as `--join`'s.
- **The in-game menu hosts** (`NetMenus`): a button under the round menu (the
  new-game screen's caption button; the N key too) asks for the port (the last
  one, `NetHostPort`, else 47300; 0 picks one) and hosts the running game as
  `--host` does (`NetPlay.HostRunningGame`). A box then says the port, the
  machine's IPv4 addresses (`sr_net_local_addresses`: the host name's, else the
  interface of the default route) and who is connected. While it hosts, the
  button reads Stop hosting and a line under it shows the port and the
  connected players, refreshed every second. Stop hosting asks first, then
  disconnects every joined peer's human as a leaver's (`TNetHost.DisconnectHumans`:
  not connected, `HoldPosition`, queued commands dropped), says `Bye` to every
  peer (`StopNetwork`) and goes on without a session; those humans can rejoin
  by name once the game is hosted again. A client has no host button.
- The in-game menu refuses to host (a message says why, `NetPlay.HostingRefusal`)
  on a client, while hot-seat is on (`--hotseat=N`, a turn pass pending, or the
  screen held by another human than the first: hosting would turn the other
  local humans into remote ones), in a special game mode
  (`Galaxy.SpecialSimulationMode`), and without a game. The observer and the
  headless modes never open the in-game menu, and `GameBootstrap` refuses
  `--host` and `--join` there.
- A save with several humans loaded without `--hotseat` can be hosted, from the
  first human's screen: the others start disconnected, as with `--host`, and
  their players rejoin by name.
- The dialogs are built in code like the chameleon dialog: the message box's
  window, font and OK/Cancel buttons, and `TEditGI` fields. Their texts are
  `Multiplayer.*` keys with English fallbacks (`MultiplayerText`).
- Headless, for tests: `--sim-net-host=PORT --sim-net-clients=N` with
  `--sim-save` (or `--sim-new-game`: the new-game screen's defaults) and
  `--sim-turns=DAYS`, and `--sim-net-join=HOST:PORT --sim-net-name=NAME` with `--sim-net-leave-at=DAY`; see Tests for the
  others.

## Tests

`tools/test.py` plays every save networked over loopback: a headless host and N
headless clients as separate processes (N = 1 and 7, so 2 and 8 humans). Each
client plays scripted days (take off, fly, land, buy) and ends its turn; the host
runs the days. Every client's state hash must equal the host's for every day;
two runs must give the host the same hashes, however the commands arrived; the
host's command log must replay to the host's final hash; and a client that
drops and rejoins must get its human back. From day 2 the host's day asks the
remote humans of one star something (`--sim-net-talk=2`): each must answer on
its client, the host must see the answer, and the replay of the host's log
(with the same flag) must ask and answer the same; a client that leaves in the
middle of such a talk (`--sim-net-talk-leave`) must not hang the host, and gets
its human back when it rejoins. In the two runs that are compared, the host
sends the day's films before its probe asks (`--sim-net-talk-after-film`) and
each client plays each film of its star for 500 ms (`--sim-net-film-ms=500`),
so every talk comes while its client plays its film: it must wait for the
film's end (`held=1`), and every client's `Status` must name the human asked.
With one client, a join as the leaver's name that cancels itself once let in
(`--sim-net-cancel-join`) comes before the rejoin: the host takes it as a leave,
and the rejoin still gets the human back; and a fifth run has the host stop
hosting after 3 days (`--sim-net-stop-at=3`), which must disconnect the client's
human and which the client must notice by itself within 5 s (both print
`GetTickCount64`, which is system-wide on Windows). The runs print the sizes of
whole states, deltas and films, and the load time, per day. Once per run, a host
that starts a new game (`--sim-new-game`) and one client check the hashes too: a
new game's galaxy has not been through a load, so this checks that a load gives
back what it saved (a hidden constellation has no outline, and the load once
gave it the constructor's empty one, so every state of a new game differed).

With one client, and in the new game, the host refuses a purchase
(`--sim-net-buy-race`, `check_refusal`): the client buys one unit of the good
whose whole stock it could pay for, and before the host applies the queues it
buys as much of that good in the client's human's name as leaves too little
(`net host buys first`; joins never put two humans in one star, so the host's
own human cannot be at the client's planet). The client's purchase must fail on
the host without holding its day, with the reason `out-of-stock`; the host's
command log must hold as many purchases of remote humans as the host applied
(`net host trades remote=`), so not the refused one; and the client must get
the refusal (`net client refused seq= reason= bubble=1`) and show it as a bubble,
again after the next state (`net client refusal after state bubble=1`). A new
game is not recorded (the command log starts at a load), so there only the
refusal is checked.

The headless runner (`HeadlessNet`):

- **Host.** Listens (port 0 picks one; it prints `net host port=`), holds the
  joins until all N clients have said Hello and then takes them by name, so the
  humans are the same every run. Each day its own human plays the hot-seat turn
  (`HeadlessSim.PlayHumanTurn`), it pumps until every peer is ready, applies the
  queues, runs the player-star job, sends the films, runs the galaxy job, and
  sends the state. It ends when N clients are joined and have acknowledged the
  last state (a client that left may join again at the end).
- **Client.** Joins with the connect on its own thread, as the game does, and
  prints each phase (`net client join phase= have= size=`); with
  `--sim-net-cancel-join` it cancels once let in (`net client join cancelled`).
  After each state it applies it plays the same turn for its own human when
  that human holds the day (once a day), then ends it. It decodes each film
  (`TEFilm.LoadFromBuffer`) and counts it; with `--sim-net-film-ms=MS` it plays
  a film of its star for MS ms, applies no state meanwhile, and keeps a talk
  that comes then for the film's end, as the star map does (`MayHoldTalk`). It
  answers each `TalkRequest` with the talk screen's first answer to a scripted
  talk (`AcceptScriptedTalk`) and prints `net client talk ship= kind= answered=
  response= human= held= wait=`. A `Status` that names a talk prints `net the
  day waits for human N to answer a hail`; a host that says `Bye` prints `net
  client host left bye=1 tick=`.
- **Stopping.** `--sim-net-stop-at=DAY` on the host: after DAY days, once every
  client has the state, it stops hosting as the in-game menu does
  (`DisconnectHumans`, then `Bye`) and prints `net host stopped hosting day=
  tick=`.
- **The talk probe** (`--sim-net-talk=DAY`, `HeadlessNet.InstallNetTalkProbe`):
  from the DAY-th day the player-star job runs, right after the day of the first
  filmed star that holds remote humans who can be asked, the first ship of that
  star that is no human's offers each of them a truce (`ShowPlayerDialogue`),
  once in the run; an answer that agrees gives the human one credit, so the
  state shows it. It prints `net talk day= human= ship= response=`. The replay
  installs it with the same flag, so the log's talk is asked again.
- One line per day: host `net host day= serial= hash= state= whole= delta= film=
  filmraw= take= compress= humans= away= plan=` (state: the uncompressed
  checkpoint; whole: it compressed; delta: the largest delta sent; film: the
  compressed bytes of the distinct films of that day, each counted once however
  many clients get it; filmraw: the same films uncompressed; take: checkpoint
  and hash, ms), client `net client day= serial= hash= match= human= state=
  received= delta= film= films= load=` (film: the compressed bytes of the films
  it received).

Measured on Windows x64, debug build, 10 days (`tools/test.py` prints these per
save):

| Save | Humans | Whole state (raw / zstd) | Median delta | Median films of a day (raw / zstd) | Client load | Host take |
| --- | --- | --- | --- | --- | --- | --- |
| AutoSave | 2 | 2.91 MB / 558 KB | 93 KB | 71 KB / 45 KB | 453 ms | 187 ms |
| AutoSave | 8 | 2.98 MB / 561 KB | 95 KB | 516 KB / 319 KB | 938 ms | 289 ms |
| Система Солнце (1) | 2 | 2.79 MB / 534 KB | 99 KB | 76 KB / 50 KB | 359 ms | 109 ms |
| Система Солнце (1) | 8 | 2.84 MB / 539 KB | 98 KB | 477 KB / 298 KB | 765 ms | 273 ms |
| Система Солнце | 2 | 2.77 MB / 531 KB | 90 KB | 87 KB / 60 KB | 344 ms | 164 ms |
| Система Солнце | 8 | 2.84 MB / 535 KB | 91 KB | 517 KB / 330 KB | 734 ms | 258 ms |

With 8 humans nine processes share the machine, which is most of the slower
load. Every client with the same base gets the same delta, compressed once.
A delta is about a sixth of the compressed whole state, and the compressed
film of one star's day is about half a delta. The films of a day count each
star's film once; every client in that star gets it.

## Not done yet

- The `Multiplayer.*` texts in the language data (the menus and the waits show
  their English fallbacks; only a selected mod's `Lang.dat` could add them,
  Waiting).
- Network play has no picture of its own in the main menu (it wears the Mods
  button's).
- A join takes the host's prepared day as it is: a human who joins in a star
  the preparation job did not see runs that star's first day without its
  preparation (no news, no planet day).
- A client closes and opens its screen once a day, so the scripts the star map
  runs when it opens and closes (`RunScriptItemsAct` `$18`/`$19`) and
  `CancelInvalidTravelOrder` run once a day more than in single player; they go
  to the host as commands.
- Remote dialogue: a script's dialogue stays with the local human; the NPC's
  line is in the host's language (the host builds the text); a talk a client
  cannot show (it is on another screen than the star map) is declined, not
  queued; one held for a film's end is declined after 60 s.
- A client sends every command it submits, also one submitted while another
  of its commands executes; the host runs the outer one, which submits the
  inner one again, and then the inner one from the queue.
- A video a client's command starts on the client's ship screen plays there at
  once, but the host queues it for the client's human (it cannot see the
  client's screen), and no report finishes it there.
- The script dialogue state (`Session.ScriptDialogIndex`, `CurrentScript`, the
  injected answers and overrides) is still one for all humans, and scripts are
  named by index.
- A client that loses its host on a screen that does not start a day (a shop,
  the ship, the galaxy map) finds out when it next opens one of those.
- Chat is in the protocol (the host relays it); nothing shows it.
- `ContinueUntilArrival` and `EndedTurn` are not in a state; this is harmless
  (The day).
