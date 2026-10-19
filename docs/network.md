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
| `platform/net_native.c`, `platform/NetNative.pas` | sockets (Winsock / BSD), zstd, and the OS's random bytes (`sr_random_bytes`) |
| `source/net/NetTransport.pas` | `TNetConnection`: length-prefixed messages over TCP; `TNetListener` |
| `source/net/NetDelta.pas` | `CompressState` / `ExpandState`: whole states, deltas (zstd with the old state as reference, like `--patch-from`) and films |
| `source/net/NetProtocol.pas` | message kinds, their encoding, protocol version, the data hash |
| `source/net/NetThread.pas` | the network thread: owns every socket, moves bytes, queues whole messages per peer |
| `source/net/NetHost.pas` | the host session: peers, joins, commands in, states and films out |
| `source/net/NetClient.pas` | the client session: hello, commands out, films and states in, the reconnect |
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
  `NetInboxEvent` when a message arrives. It never touches game state. It also
  keeps each connection alive: a connection that has been sent nothing for
  `NetPingIntervalMs` (2 s) gets a `Ping`, behind what is queued and never in
  the place of a state still being compressed, nor once its close was asked
  for; one that has received no byte for `NetSilenceTimeoutMs` (10 s) is closed
  with the error "no answer for 10 s" (Disconnects). Any byte counts, so a
  large state that arrives slowly is no silence. The thread swallows `Ping`;
  no inbox sees it. Both are variables, so the unit tests shorten them. Pings
  and the timeout live only here, never in a screen's loop, so a long day or
  an open box cannot cause a false timeout. `TNetThread.FreezePeer` (tests
  only) stops reading, writing, pinging and timing out one peer and keeps its
  socket open, so the other side sees only silence.
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
  new game, the main menu's text quest, an arcade battle) or a memory snapshot
  is up. A game's text quest is a game screen (`NetPlay.NoGameScreen`; the quest
  is not in the galaxy): the host takes joins, leaves and trades while its own
  human plays one, and a client in one runs the relays and shows the reconnect
  box.
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
  closes its connection when it comes. A reconnect (Disconnects) connects the
  same way, from the client's pump, on the same `TNetClient` and its network
  thread: the old peer is removed and the new connection is added.
- Sending is thread-safe: it appends to the peer's outbox under the lock.

## Messages

A message is a 4-byte little-endian length, a kind byte and the payload
(`NetTransport`). Payloads are `TBufEC` encodings. Kinds are part of the
protocol; never renumber one, add new ones at the end and bump
`ProtocolVersion` when a payload changes.

| Kind | Direction | Payload |
| --- | --- | --- |
| `Hello` | client → host | protocol version, game version text, data hash, human name, whether it spectates, the reconnection token it holds (0: none) |
| `Welcome` | host → client | the client's human id, the host's name, the human's reconnection token |
| `Refuse` | host → client | reason text; the host then closes |
| `State` | host → client | state number, base state number (0 = whole), day number, state hash, zstd bytes (`NetDelta`) |
| `Film` | host → client | day number, star id, zstd bytes of the film (`TEFilm.SaveToBuffer`, `CompressState` with no reference) |
| `Command` | client → host | the client's number for the command (32 bits, from 1 per connection), then an encoded `TPlayerCommand` (`aCommands.EncodeCommand`) |
| `Ack` | client → host | the number of the last state the client applied |

The host numbers its states from 1. A day number cannot name a base: a join
between two days sends a state of the same day as the one before it.
`ProtocolVersion` is 9 (2: `TalkRequest` has its payload; 3: `Status` names
the human whose answer to a dialogue the day waits for; 4: `NewHuman` and
`Character`; 5: `Film` is compressed; 6: `Command` carries the client's number
for it, and `CommandResult`; 7: the host applies a trade as it arrives and
answers it, also when it applied it, and `RelayCommand`, Trades; 8:
`RelayCommand` carries a ship screen sale as its effect, `RelayedSale`, Trades;
9: `Hello` and `Welcome` carry the reconnection token, and `Ping`, Disconnects;
10: `Status` carries each human's text-quest activity and the days it owes for a
quest, Waiting). The text quests plan
([progress/2026-10-19-text-quests-plan.md](progress/2026-10-19-text-quests-plan.md))
adds `QuestPage` (18) in its Phase D.
| `Status` | host → client | per human: id, name, connected, holds the day, its text-quest activity (a byte: 0 none, 1 plays one, 2 owes days for one) and the days it owes; whether a day is running; the human whose answer to a dialogue the day waits for (0: none) |
| `TalkRequest` | host → client | human id, ship id, planet id (0: none), scripted, talk kind, amount, text: the human's talk fields (Remote dialogue) |
| `TalkDone` | client → host | nothing: the client's answer is complete, or it cannot show the talk |
| `Chat` | both | sender human id, text; the host relays it to every client |
| `Bye` | both | the sender leaves |
| `NewHuman` | host → client | nothing: the name is new, so the client chooses its character |
| `Character` | client → host | name, race, character preset, portrait, two starting skills, two starting items |
| `CommandResult` | host → client | the command's number (as in `Command`), its kind, applied (1) or refused (0), the reason (a byte, `aCommands.TRefusalReason`), the exception's text; sent for a refused command (Commands) and for every trade the host applied (Trades) |
| `RelayCommand` | host → client | a human id, then an encoded `TPlayerCommand`: a trade the host applied, of another human at the client's human's planet or station, or for a ship screen sale its effect (`RelayedSale`) (Trades) |
| `Ping` | both | nothing: the connection is alive; sent and swallowed by the network thread (Threads) |

## Joining

1. The client connects and sends `Hello`.
2. The host refuses when the protocol version or the data hash differs. Build
   hashes may differ, since platforms differ. It also refuses an empty name, a
   spectator (not supported yet), a name whose human is connected, and a join
   when no planet takes a new human. **Takeover.** A Hello whose name is a
   connected remote human's and whose token is that human's (not 0) takes the
   human over instead (`TNetHost.TakeOver`, from the pump, not while a job
   runs: a job may free a ranger whose name it reads): the host logs `human N
   (name) taken over by a new connection`, removes the old peer from the network
   thread at once (`RemovePeer`, so nothing more goes to it; `IsClosed` is
   true from then on) and marks it leaving. A remote talk runs in a job, so
   a talk of that human ends first, by the silence timeout or its answer. At the next quiet point
   `ProcessLeaving` disconnects it (Disconnects) and `ProcessJoins` lets the new
   peer rejoin (step 4), in the same pump. Without the token (another machine,
   a restarted game) the refusal stays; the silence timeout frees the name
   within 10 s anyway, so nobody throws a live player out by typing its name.
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
   human the local one and opens its screen (Applying state). `Welcome`
   carries the human's reconnection token: 64 random bits from the OS
   (`NetProtocol.NewToken`, `sr_random_bytes` in `net_native.c`:
   `BCryptGenRandom` / `/dev/urandom`; never `Random` or the game's generators,
   which its determinism depends on), issued at the human's first Welcome in
   this hosting session and given again at each rejoin (`TNetHost.HumanToken`).
   The client keeps it (`TNetClient.Token`) and sends it in its Hello; a
   `TNetClient` created with a token (the constructor's `Token`) says Hello
   with it, and so does its reconnect (Disconnects).

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
  `NetworkCommandHook` sends it to the host; a trade is not predicted, it waits
  for the host's answer (Trades). Only a command submitted while
  none executes goes: one that a command submits from inside it (script code
  it runs, a nested action) is submitted again when the host executes the outer
  one, as the command log records only the outermost and its replay rebuilds the
  rest ([commands.md](commands.md), Threads). The host's remote dialogue gets
  only such commands too.
- The host refuses a command whose actor is not the peer's human, and queues
  the rest per peer. A command only the host's human gives (`SetSessionFlag`:
  the session flags are the host's, [humans.md](humans.md); and a relay's form,
  `RelayedSale`, Trades) is refused as it
  arrives, also in a remote dialogue, and the peer gets a `CommandResult`
  (`rrOther`); it is never queued (`TNetHost.RefuseHostOnlyCommand`). It does
  not execute them as they arrive, except a trade (Trades): arrival order
  depends on the network, and the day's outcome must not, except between the
  trades of humans who compete for the same thing.
- A peer is **ready** when its queue holds an `EndTurn` (kind 43), or when its
  human does not hold the day anyway (`HumanHoldsDay` is false: continuing
  travel, in hyperspace, finished) or is disconnected. A queue without an
  `EndTurn` is not applied; it waits for the day its `EndTurn` arrives, and a
  continuing peer must have applied the state before the last one. A
  continuing peer whose queue holds a `StopContinuing` is not ready either
  until its `EndTurn` comes (`StopPending`, Continuing travel). A
  command the peer sends while its human does not hold the day can race the
  host's apply, so it waits too rather than landing in whichever day it
  happened to reach.
- **Taking an end turn back.** A peer's `CancelEndTurn` (kind 47) is never
  queued: the host takes the peer's `EndTurn` out of its queue
  (`TNetHost.CancelEndTurn`), so the peer is not ready any more, and answers
  `CommandResult` (applied). The commands before the `EndTurn` stay queued for
  the barrier; those after it now belong to this day. It is refused
  (`rrTooLate`) once the day has begun or while the barrier applies the queues,
  when no `EndTurn` waits, and when the day it names (`Galaxy.CurrentTurn` on the
  client) is not the host's (that day has run). A remote dialogue refuses it
  too. Neither the `EndTurn` nor the cancel runs on the host, so the command log
  records neither (Waiting). With its second integer set (`StopTravel`) it is
  the Cancel of a human whose travel continues, which sent no `EndTurn`: the
  host queues a `StopContinuing` of that human as if the peer had sent it
  (Continuing travel) and answers applied when its next day has not begun,
  else refused (`rrTooLate`) with the stop queued all the same; not while the
  barrier applies the queues (refused, nothing queued).
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
  | `rrOther` | 0 | `other` | any other exception; also a sale in space of goods the seller does not carry, a dominator program the human has none of, another human's medals, an equipment configuration that is not there, and a client's `SetSessionFlag` |
  | `rrOutOfStock` | 1 | `out-of-stock` | a purchase of goods beyond the stock (`TShip.CheckGoodsPurchase`); nodes from a pirate base that has none |
  | `rrNoMoney` | 2 | `no-money` | a purchase of goods or equipment, a refuel, reload or rockets the human cannot pay; a sale in space the partner cannot pay in full; a ship built at a Dominion, a map, a satellite, an investment or a Dominion order the human cannot pay; a repair of the held item or of everything, a bribe, a gift to a partner, a deposit, a modernization, a side change, a pirate raid or nodes the money does not cover |
  | `rrItemGone` | 3 | `item-gone` | a shop command whose item (by id) the shop's stock no longer holds (`aShopActions.ShopItemArg`); a ship built at a Dominion with a part no longer in the shop, the hold or the storage, or named twice; surface loot (by id) no longer on the planet; a hold cell whose item is no longer in the edited ship, or (`TakeHoldEntry`) is not the item the sender's cell showed |
  | `rrOfferGone` | 4 | `offer-gone` | a station's one-off special ship already sold; a satellite offer that is not the one the human accepted, or no more satellites allowed; an investment the business center would not offer now (too soon, or the star or its constellation has the station or no room for it); a map of a constellation that is charted or no longer an uncharted neighbour; a station's modernization someone has paid for; a side change or pirate raid whose price went above the quote |
  | `rrTargetGone` | 5 | `target-gone` | a script dialog command whose script, injected answer or override (by key, [commands.md](commands.md)) is not there, or an override command with no override; a request for protection when the partner is after no ship; a dominator a program already hacked; a Dominion relocation, ambush or assault when the Dominion has other plans (it flies or teleports, a script controls it, or it lacks the energy), the star has a Dominion, or an ambush at the star is under way; a truce with a ship that keeps one with another human (the offer itself is declined); a recall of interceptors that are not the human's |
  | `rrNoRoom` | 6 | `no-room` | a sale in space that does not fit in the partner's hold |
  | `rrInUse` | 7 | `in-use` | opening the screen of a ship (not the human's own ranger) another human has open (`THuman.EditedShip`, [humans.md](humans.md)) |
  | `rrTooLate` | 8 | `too-late` | a `CancelEndTurn` after the day has begun (Waiting) |

  The checks are those the screens make before they offer the action, so they
  never fire in a single-player game; they refuse a command a client predicted
  from a copy another human's command has made stale (`--sim-stale-commands`,
  `HeadlessSim.RunStaleCommands`, checks each). The values fit the byte that
  always carried the reason, so the protocol did not change; a reason the client
  does not know reads as `rrOther`. The host logs
  `command failed human= seq= kind= reason=`; the client logs `command refused
  seq= kind= reason=`, keeps the result for `TakeCommandResult`, and shows the
  refusal to its player as a message bubble of its human (`TNetClient.ShowRefusal`),
  with a `Multiplayer.Refused*` text: `RefusedOutOfStock` ("The host refused
  your purchase: not enough in stock."), `RefusedNoMoney`, `RefusedItemGone`,
  `RefusedOfferGone`, `RefusedTargetGone`, `RefusedNoRoom`, `RefusedInUse`,
  `RefusedTooLate`, `RefusedOther` (English fallbacks, as Waiting's texts). A
  refused `CancelEndTurn` shows no bubble: the wait for the day goes on. The next state
  replaces the human's bubbles, so the client shows the refusals of the day
  again after applying it. The host also sends `CommandResult` (`Ok`) for every
  trade it applied, which its client waits for (Trades); for other commands it
  sends refusals only.
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
  trade, refresh the open shop that way. Hulls for sale are items of that
  stock, shown in the equipment shop's grid. The hangar has no list of them: it
  shows the ships docked there (`THuman.HangarShipIds`, by id, checked again
  every 20 ms). A docked ship's picture is loaded when it appears, so the same
  notification redraws the other humans' rangers in an open hangar
  (`TfHangar.RefreshOtherHumansPortraits`): one that bought a hull shows it.
- When the host's human has ended its turn and every peer is ready, the host
  applies the queued commands, human by human in `Session.Humans` order, each
  queue up to and including its `EndTurn`, through `SubmitCommand`, so the
  host's command log records them. Then the barrier
  (`AllHumansEndedTurn`) holds and the day starts. Without trades this is the
  order the merged hot-seat replay uses, so the same commands give the same day
  however they arrived. The trades, and what each human sent before them, were
  applied earlier, as they arrived (Trades), so the host's log is in the order
  the host applied them; it replays to the same hash as it is, but split into
  one log per human and merged it would apply a human's whole queue at once.
  Commands after a peer's `EndTurn` stay queued for the next day.
- The host's own human is first in `Session.Humans`
  (`HostHuman`), and its commands execute at once, so they come first anyway.
- The exception is a remote dialogue: its commands execute as they arrive,
  on the turn thread (Remote dialogue).
- `EndTurn` is an ordinary command. There is no separate end-turn message.
- The client's copy is a prediction. Nothing on the client is reconciled: the
  next `State` replaces it. Where two humans compete for a trade (the last item
  in a shop), the order in which the trades reach the host decides, and the
  client hears it at once (Trades); for other commands the host's order at the
  barrier decides and the next state shows the outcome.

## Trades

A trade (the kinds registered as trades, [commands.md](commands.md), Trades:
buying and selling, the hangar and the services that cost money, and the
station's and government's one-off offers) is decided on the host as soon as it
arrives, and its client waits for the answer instead of predicting it. Other
humans at the same planet or station see it before the next state.

- **The host applies it between days.** When a peer's `Command` is a trade with
  no `EndTurn` before it in the peer's queue, the host applies that queue up to
  and including the trade, in order, through `SubmitCommand`
  (`TNetHost.ApplyTrade`): the commands before it go first, since the trade may
  depend on them (taking an item out of the hold, then selling it), and the
  command log records them in that order. A script dialogue among them (a
  government screen visited first, say) keeps to the peer's human's dialogue
  state, which the host swaps in for each of its commands, and shows nothing on
  the host ([humans.md](humans.md), Scripts), so it may apply while the host's own
  dialogue is open. A command before the trade that
  raises is refused as at the barrier (`CommandFailed`); the trade gets
  `CommandResult`, applied or refused. The commands after the trade stay queued
  for the barrier. The order in which trades of different humans arrive decides
  between them (the owner's decision): the pump applies a trade while it reads
  the peer's inbox.
- **Only at a quiet point the screen allows.** The pump applies trades when no
  turn job runs and no day is under way (`TNetHost.Quiet`) and
  `TNetHost.MayApplyTrades` says so; a trade that comes otherwise waits in the
  queue for the next such pump (`ApplyWaitingTrades`, in `Session.Humans` order),
  or for the barrier, which answers it too. On the game's host this is
  `NetPlay.MayChangeUnderScreen`: no command runs, a game screen is open and
  not closing, and either the pump runs from the message loop of the innermost
  screen between two of its messages (`FramePumpHook`; no box or dialogue is
  above the screen, no screen is being built, and no handler is between a
  `SubmitCommand` and its read of the result globals), or the host's end turn
  waits for its peers (its wait box), where the queues are applied next anyway.
  Not from the waits inside a handler (`TurnWaitPumpHook`, the star map's
  `NetWaitForEvents`). A host whose player keeps a box open holds the trades.
- **A remote dialogue's** commands run as they arrive, as before; a trade among
  them gets `CommandResult` too.
- **Relay.** After a trade is applied, by a peer or by the host's own human, the
  host sends that one command (`RelayCommand`) to every other joined client
  whose human is at the actor's planet or station (`aShopStock.HumanShopLocation`;
  `TNetHost.RelayTrade`, the host's `NetworkCommandHook`). A trade in space (with
  an NPC partner) goes to nobody: no other human trades with that partner, and
  the state shows it. Nothing else is relayed: not the commands before the
  trade, not a dialogue's or a script's, not session commands, and not what the
  barrier applies (the state after the day carries it). A first attempt relayed
  every command and spread script side effects to other machines.
- **A sale from the ship screen goes as its effect.** `SellHeld`,
  `SellHoldInventory`, `SellHoldArtefact`, `SellHoldGoods` and `SellStoredItem`
  (`aHoldActions.IsShipScreenSale`) run on what the actor holds and on the ship
  its screen edits, which the hold commands before them (`TakeHoldEntry`,
  `OpenShipScreen`, ...) set up, and those are not relayed: relayed as
  themselves they failed on the other clients. So the host relays, in
  `RelayCommand`, a `RelayedSale` (254) of the same actor instead, built right
  after the sale ran (`aHoldActions.RelayedSaleOf`; the sale's executor records
  what it put into the location): the location (a planet or a station), the
  actor's money after the sale, the ids of the items the sale put into the
  location's equipment shop, and the goods it sold to the location's market (the
  good and the count). A sale that put nothing there (an item the shop does not
  take back is destroyed, part of a stack) is not relayed (`net no relay`), and
  the host logs the sale's kind with the relay (`net relayed human= kind=RelayedSale
  to= sale=SellHeld`). The client runs it as any relay
  (`ExecuteRelayedSale`): the actor must be at that location on its copy, and
  each item must be the actor's there, wherever it is: its ranger's equipment
  (unequipped first) or artefacts, the ship its screen edits, its storage, or
  the item it holds; otherwise nothing changes and the relay is logged and
  dropped. The items move into the location's shop list, the goods are added to
  the market's stock, the actor's money is set to the host's (the client's copy
  of it may differ, since the commands before the sale did not run there, and
  the next state carries it anyway; the actor's cargo is left to that state),
  and `ShopStockChanged` rebuilds the grids there that no longer show the list,
  the local one's with its screen told (the goods too). `RelayedSale` is
  registered as relay only (`aCommands.RegisterRelayCommand`): `SubmitCommand`
  refuses it, so the command log never records it, and the host refuses it from
  a peer (`IsHostOnlyCommand`). The purchases and `TradeGoods` (counts on the
  goods screen's own cargo) are relayed as themselves; they run on the
  client's copy as on the host's.
- **A text quest's start goes as its lock.** `BeginTextQuest` (609, a trade:
  one human at a time plays a planet's quest, [commands.md](commands.md)) is
  relayed as a `RelayedTextQuest` (610, relay only;
  `aQuestActions.RelayedTextQuestOf`) with the same arguments, which sets the
  actor's lock (`THuman.TextQuestOpen`, `TextQuestPlanetId`) without the
  checks: the host made them, and a client's copy need not have the actor's
  quest (an offer of the same day, or a probe). So the planet screens of the
  other humans there say who plays the planet's quest and offer no start
  (`aQuestActions.TextQuestHolder`, `NetPlay.TextQuestTakenText`), until the next
  state. A client's own `BeginTextQuest`, which runs there only once the host
  applied it, does not check another human's lock: one it knows of is a relay
  the host may have released since.
- **A client runs a relayed trade** as its human, through the executor
  (`aCommands.ExecuteRelayedCommand`: no hook, and what it submits from inside
  goes nowhere), only at a safe point: the frame pump with
  `MayChangeUnderScreen`, no state waiting to be applied, no film playing, and
  not while it waits for its own trade (`TNetClient.ApplyRelayed`). The shop
  grids there follow: the executor's `ShopStockChanged` rebuilds the local
  human's grid and tells the equipment shop screen
  (`SimEvents.NotifyShopStockChanged`); the host's own open shop is told the same
  way when a client's trade changes its stock. A relayed trade that fails on
  the client's copy (it differs from the host's) is logged and dropped; the next
  state fixes the copy. A relay that came before
  a state is dropped with it: the state holds it.
- **The client waits** (`TNetClient.SendTrade`, `aCommands.TradeSubmitHook`).
  `SubmitCommand` of an outermost trade on a client sends it and does not
  execute it; it waits, pumping the network, for the `CommandResult` with the
  trade's number. Applied: the trade runs here, on the client's copy and the
  relayed trades that have already run, as a command of its human (the command
  log listens as usual), and `SubmitCommand` returns, so the result globals the
  screen reads right after it (`EquipmentPurchase`, `PurchasedItem`,
  `SalePrice`, `SaleChanged`, `RepairAllPaid`, `StationText`, ...) are this
  run's. Refused: `SubmitCommand` raises `ECommandRefused` with the host's
  reason before anything runs, and the client shows the refusal as before. The
  wait blocks the screen's handler, so the screen takes no second trade on what
  it showed: the window is kept alive meanwhile (`TradeWaitIdleHook`: the
  message loop's work without dispatching input, after `ClientTradeIdleMs`), and
  the input that comes is dropped. A LAN round trip takes milliseconds. One
  generic wait instead of work per screen, because every trade site already
  reads its results right after `SubmitCommand`; the wait is safe in the screen
  loop since no handler runs and no screen is built meanwhile.
- **No answer.** After `ClientTradeTimeoutMs` (10 s) the client stops waiting:
  the trade is refused here (`rrOther`, a bubble `Multiplayer.TradeNoAnswer`,
  "The host did not answer your action in time."), and the next trade first
  waits for that answer, so the host never holds two trades the player could
  not see. An answer that comes later and says applied runs the trade at the
  next safe point, as a relay. A lost host ends the wait at once and the
  lost-host flow goes on (Waiting); the trade is dropped.
- **Refused trades on the screens.** The trade commands' wrappers submit with
  `aCommands.SubmitTrade`: a refusal (another human was first, or the host's
  answer on a client) is shown as a bubble of the local human
  (`TradeRefusedHook`; on the host `Multiplayer.Late*`, "Another player was
  first: the item is gone.", on a client the host's `Multiplayer.Refused*`), and
  then ends the UI action that submitted it (`TradeAbortHook`, the screens'
  `BreakUiMessage`), as a dialogue choice ends its own, so nothing after the
  submit acts as if it had been done (the success sound, text, or result). The
  goods screen keeps its own handling (`aShopActions.TradeGoods` logs the
  refusal) and shows the goods as they stand. Without a session the hooks are
  nil and `SubmitTrade` raises the refusal as `SubmitCommand` does.
- **The ship screen** of a sponsored station's ship that another human has open
  is refused (`rrInUse`); the host's own human can now lose that race against a
  client. The screens check it first (`aHoldActions.ShipScreenInUse`): the
  station's modernization dialogue tells the player and stays, and the ship
  screen opens the player's own ship instead (`TfShip2.OnOpen`).
- **Single player and hot-seat** are unchanged: no hook is set, a trade
  executes at once, and a refusal raises as before. The host's own trades
  execute at once as before.
- **Determinism.** Arrival order depends on the network, so the headless host
  (Tests) applies trades only while it waits for its peers and a human's only
  once every human before it in `Session.Humans` is ready
  (`TNetHost.OrderedTrades`): a client blocked on its trade is the first not
  ready, so it never waits on a later one, and the host applies the same
  commands in the same order every run.

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
  session it is `EndTurn`. The host's player can take the end turn back while
  it waits (Waiting): `HostDayMayStart` then returns false without applying the
  queues, and the screen goes on in order mode, as when the day does not start.
- **Host, continuing travel.** The star map's automatic continue ends the host
  human's turn (`EndTurn` with `ContinueUntilArrival`) during the film, but the
  next day starts at the film's end: there the state goes, the host waits for
  its peers, and the next player-star job runs (`TfStarMap.StartDeferredNetDay`).
  A break in the film, or a human who holds the day again, ends it as when the
  travel stops. Without a session the next day's job still starts during the
  film.
- **Client.** A client never starts a day (`ThreadCalc.TurnJobsForbidden`). Its
  end turn sends `EndTurn` and its screen waits until the host's film or state
  comes (Films, Applying state), or until the host has applied its
  `CancelEndTurn` (Waiting); then the screen goes on in order mode.
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
  (`TfStarMap.BreakTurnClicked`). A queued `StopContinuing` of a human who
  continues (not in hyperspace) makes its peer not ready (`StopPending`): the
  next day that has not begun waits for the client, and its status names it.
  The barrier applies the stop with the peer's `EndTurn` and what comes between.
  When it came after the host had begun that day, it holds the day after; the
  state of the day it missed still says the human continues, and the client,
  whose film was broken, sends `StopContinuing` again (harmless) and goes to
  order mode. Its orders and end turn then wait in the host's queue for the day
  they reach. (Before, the stop was applied at the next barrier without an
  `EndTurn`, which then found a human who holds the day and waited again; the
  headless host took that for a failure.)
- **Cancel stops it too** (Waiting). A client's waits while its travel
  continues (for the film, `nwClientDay`, and for the state after it,
  `nwClientState`) offer Cancel, once per state, with the line
  `Multiplayer.CancelTravel` ("Cancel: stop your travel and take your turn
  back."). It sends `CancelEndTurn` with `StopTravel`; the host queues the stop
  (above). Applied (the next day had not begun): the wait ends, the cancel runs
  here (`EndedTurn` and `ContinueUntilArrival` clear) and the star map is in
  order mode; the player can open the ship, the hangar or a shop, and ends the
  turn as usual (which asks to continue again). Refused (that day had begun):
  the wait goes on, says "Taking your end turn back...", and the screen after
  the next state stops the travel here (`ClientStopRequested`,
  `OpenClientScreen`, as after a broken film), so the client holds the day
  after. The host's own wait at the end of a film whose travel goes on
  (`StartDeferredNetDay`, `nwHostPeers`) offers Cancel too: its human's
  `CancelEndTurn` clears both flags, `HostDayMayStart` returns false, and the
  film ends in order mode, as when the travel stops. The other humans keep
  travelling; they wait for the human that stopped.
- **The host's break.** The host's own break in its film works as in single
  player: the film ends without starting the next day, and `StartOrderMode`
  submits `StopContinuing`, so the host's human holds the day, and every
  client's status names it.
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
the new text when the text changes. Who it waits for is who the day waits for:
the humans who hold the day and whose peer has no `EndTurn` queued, and the
continuing humans whose peer lags behind (`TNetHost.DayWaitsFor`); the host's
`WaitingFor` and the status's `HoldsDay` both say this, so a client's wait no
longer names a peer that has ended its turn before the barrier. During the day
the status says who holds it, as before. The texts come from the language data with
an English fallback, as `Multiplayer.Turn` does: `Multiplayer.Waiting`
("Waiting for <Players>."), `Multiplayer.Away` ("Away: <Players>."),
`Multiplayer.DayRuns`, `Multiplayer.WaitingHost`, `Multiplayer.WaitingPlayers`,
`Multiplayer.WaitingTalk` ("Waiting for <Players> to answer a hail."),
`Multiplayer.CancelEndTurn` ("Cancel: take your end turn back."),
`Multiplayer.CancellingEndTurn` ("Taking your end turn back..."), the text
quests' `Multiplayer.InTextQuest` ("(text quest)" after the name of a human the
day waits for who plays one), `Multiplayer.QuestBusy` ("<Players> is busy with a
text quest for <Days> more days."), `Multiplayer.QuestTaken` ("<Players> is
playing this quest.", the planet screens) and `Multiplayer.QuestAbandoned` (a
bubble, Disconnects), the join's `Multiplayer.JoinConnecting`, `JoinWaiting`, `JoinReceivingStart`,
`JoinReceiving`, the reconnect's `Multiplayer.Reconnecting` ("The connection to
the host is lost. Reconnecting... (<Seconds> s)"), and for the main menu
`Multiplayer.Refused`, `Multiplayer.Lost`, `Multiplayer.HostLeft`,
`Multiplayer.NoState`. None is in
the game's language data. The only way to add texts to it is a mod: a selected
mod's `Mods\<mod>\CFG\<language>\Lang.dat` is merged into it
(`GR_Main.LoadDatConfigAndModOverrides`), in the game's binary `.dat` format. The port
ships no data files of its own (the build places the executable and its
libraries only), and a mod the players must select is not a fit for a few
texts, so the English fallbacks stay.

**Text quests** ([progress/2026-10-19-text-quests-plan.md](progress/2026-10-19-text-quests-plan.md),
The day). A human who plays a text quest has not ended its turn, so the day
waits for it, and the waits say so ("Waiting for Guest (text quest)."): the
host knows it from the lock its `BeginTextQuest` left there, which runs on the
host as it arrives, until its barrier applies the quest's `CloseQuest`. In a
session a quest runs no galaxy day; the human owes its days
(`THuman.QuestDaysOwed`) and holds no day while it does, and the waits name it
on a line of its own ("Guest is busy with a text quest for 3 more days."). Its
`EndTurn` for the quest's own day still goes: the quest's `CloseQuest` ran on
the client, so its copy owes the days already, but the host's has them only
once its barrier applies that `CloseQuest`, and its day waits for the `EndTurn`
until then (`NetPlay.ClientQuestDayEnds`: the last state said the human owes
none, `TNetClient.StateQuestDays`). A human who owes days cannot take an end
turn back (`MayCancelEndTurn`). Its planet screen (`TfPlanet`, `TfPlanetNO`, a
poll every 250 ms, `NetScreenPollMs`) ends its turns by itself while it owes
days (`NetQuestDayDue`), as the star map's automatic continue does: on the host
each ends the day once the peers are ready, on a client each waits for the next
state and sends nothing (the host does not wait for it).

A client that loses its host, or is refused, shows why on the main menu and
the session ends there. A client that loses its host while it plays its turn
notices it in the per-frame pump (`NetFrame`) and goes to the main menu, which
says why, at the next safe point: when a screen that starts a day is the one
running (the star map, the planet, uninhabited planet, station, hangar or
jump screen, with no box or dialogue above it, `LostHostLeaveScreens`), not
while the star map plays a film (its end leaves anyway), and never from a shop
or the ship screen, which move goods when they close. It does not offer to play
on offline: the client's copy is a prediction the host no longer backs.

**Taking the end turn back.** The wait for the day has a Cancel (also Escape)
while the end turn can be taken back, and a line under the text says so
(`Multiplayer.CancelEndTurn`, or `Multiplayer.CancelTravel` while the travel
continues); the message box's buttons are pictures, so the line names it. Only
where taking it back makes the human hold the day again
(`NetPlay.MayCancelEndTurn`): not in hyperspace (a jump cannot stop), not when
the human has finished, and not while it takes off (the screen that took off
would stay with the ranger leaving; the takeoffs from the planet, hangar and
station have no Cancel). While the travel continues, Cancel stops it
(Continuing travel); a client may also do that while the host's day runs, and
then it holds the day after. The reconnect's Cancel comes first: while a
client reconnects, Cancel ends the reconnect.

- **Host** (`nwHostPeers`): Cancel submits `CancelEndTurn` (kind 47) for its
  human (`aPlayerActions.CancelEndTurn`), whose executor clears `EndedTurn` and
  `ContinueUntilArrival`; the command log records it after the `EndTurn`, and a
  replay runs both. The wait ends and `HostDayMayStart` returns false before it
  applies the queues, so the peers' `EndTurn`s stay queued (and can still be
  taken back). The next end turn waits again.
- **Client** (`nwClientDay`): Cancel sends `CancelEndTurn` for the `EndTurn` it
  sent since its last state (`TNetClient.SendCancelEndTurn`, once per `EndTurn`)
  and does not block: the wait goes on, says "Taking your end turn back..."
  (`Multiplayer.CancellingEndTurn`) and has no Cancel meanwhile. The host's
  answer (`EndTurnCancel`): applied, the wait ends, the cancel runs here as a
  relay does (`TakeCancelledEndTurn`: the human holds the day again, no
  continuing), and the screen goes on in order mode; refused (the day has
  begun), the wait goes on for the film or the state as before, with no Cancel.
  The answer has no timeout: one that comes later still ends the wait, and a
  film or a state ends it as always. A reconnect drops it; the state after the
  reconnect replaces the end turn anyway. The client shows no Cancel once the
  host's status says the day runs.
- The other humans' waits change their text: the host's (`WaitingFor`) and
  the clients' (the status's `HoldsDay`) name the human again.

**Reconnecting.** A joined client whose connection was lost first reconnects
(Disconnects); `Connected` stays true meanwhile, so neither `NetFrame` nor
`LeaveLostGame` goes to the menu, and only a reconnect that fails or is
cancelled ends as above. While it reconnects:

- A wait for the day (`nwClientDay`, `nwClientState`) shows
  `Multiplayer.Reconnecting` with the seconds left instead of whom it waits for,
  and has a Cancel (also Escape); it opens again without one when the reconnect
  ends, and the state after it ends the wait as any state does.
- Outside such a wait, a box with the same text and Cancel
  (`NetPlay.ClientReconnectWait`, `nwReconnect`) opens over the innermost screen
  from the frame pump, between two messages of that screen's loop
  (`RunningScreenLoop`), over any screen of a game, a shop too, since the box
  changes nothing; not while the star map plays the host's film (its end waits
  anyway, and then shows the reconnect). It pumps every 20 ms, shows the seconds
  again at most twice a second, and closes by itself when the host has let the
  client in again (`Welcome` as the same human).
- Cancel says `Bye` on a connection that is up, ends the client as host lost
  (`Error` "reconnecting was cancelled; ..."), and the lost game leaves for
  the main menu at the next safe screen as above.
- The whole state after the reconnect can come while no wait is open (the
  player was in the middle of the turn). It is applied between screens like any
  other (Applying state), once a screen that starts a day is the one open (the
  same safe screens and conditions as for leaving, `NetPlay.ApplyRejoinState`):
  that screen closes and the human's screen opens on the host's state, where the
  human plays its turn again and ends it. In a wait, or on the jump screen, the
  wait or the jump screen's tick applies it. Until it is applied, the commands
  the client submits are dropped (logged `command dropped while reconnecting`)
  and a trade is refused as unanswered (`Multiplayer.TradeNoAnswer`).

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
own screen. The client's dialogue commands keep to the client's human's script
dialogue state (the dialog message, its script, the injected answers and
overrides), which the host swaps in for each of them; the host's own open
dialogue stays as it was, and the injected answers its screen shows stay valid
([humans.md](humans.md), Scripts). They name scripts and injected answers by
key, so a script the host started in another order is still the one meant, and
one that is gone is refused. Its takeoff and end-turn requests (`ExtremalTakeOff`,
`ForceNextDay`) are its human's: the client dispatches them as its own
`OrderScriptTakeoff` and `EndTurn`, and the host does not act on them for its
own human. Entering or leaving ruins mode (`EnterRuinsMode`, `CloseBridge`)
changes the client's human's state and opens no screen on the host. A queued
arcade or planet battle or video that the client's command starts is queued on
both for the client's human: the client plays it and reports the outcome by a
command, which finishes the client's request on the host, never the host's
own. One that the host's day or another human's command starts for the
client's human is not started, since the client never sees it. A video that
starts while the client's ship screen shows (its own `OpenShipScreen` came, its
`CloseShipScreen` has not: `THuman.ShipScreenShown`) plays at once on the
client, which reports nothing, so the host does not queue it. A command that
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
- **A silent loss** (Wi-Fi gone, a cable pulled, a machine asleep) closes no
  TCP connection. The network thread closes one that has received nothing for
  `NetSilenceTimeoutMs` (Threads); from then on it is an ordinary closed
  connection: the host logs `connection of peer N (name) lost: no answer for
  10 s` and disconnects the human as above, and a client sees its connection
  closed ("the connection closed: no answer for 10 s") and reconnects (below).
  Our own ping rather than TCP keepalive, which starts after 2 h by default and
  is set up differently on each OS.
- It rejoins by joining with the same ranger name (Joining); a client that
  still has its token can take its human over before the timeout (Joining,
  Takeover).
- **The client reconnects by itself.** A client that has had a state and
  whose connection closes or goes silent (not the host's `Bye`, not a refusal)
  does not give up: `TNetClient` connects again in place, on the same object
  and network thread (so every reference to it stays valid), to the same
  address with the same name and its token, for `NetReconnectMs` (60 s, a
  variable) at most. It logs `client lost the host: <why>; reconnecting for 60
  s`, removes the old peer and drops what came on it: films, the held talk,
  relays, results, and the trades the host has not answered. Each try is a
  `TNetConnectAttempt` of 5 s at most (`client reconnect try=N`), 1 s after the
  last failed one; a connect that succeeds says Hello and waits for `Welcome`.
  `Reconnecting` is true until then (`ReconnectElapsedMs`,
  `ReconnectRemainingMs`, `CancelReconnect`), and `Connected` stays true, so the
  screens keep waiting (Waiting). The host takes the Hello as any: a takeover
  while it still counts the old connection, a rejoin once it has timed it out.
  `Welcome` as the same human ends it (`client reconnected human= after= ms
  tries=`): the delta bases go (the state that follows is whole and taken as
  whole) and the command numbers start again from 1 (the host numbers per
  connection). The whole `State` comes into the usual slot, marked as the
  rejoin's (`RejoinStatePending`, `TNetApplyReport.Rejoin`) and is applied at a
  safe point (Waiting). Until it is applied, commands are dropped and not
  numbered; a trade `SendTrade` waits for when the connection is lost is
  refused as unanswered at once (`rrOther`, the `Multiplayer.TradeNoAnswer`
  bubble) and not kept for a later answer, and so is a trade submitted then. A
  state that came before the loss and was not applied yet stays and is applied
  as usual; it is not acknowledged on the new connection.
- **It ends as host lost** (`HostLeft`, `HostSaidBye` false, `Error` why, and
  the main menu says so, Waiting) when `Welcome` names another human ("could not
  reconnect: the host gave human N, not M"), the host asks for a character
  (`NewHuman`: it no longer has the human), refuses, says `Bye`, or the window
  ends ("could not reconnect within 60 s: <the last try's error>", logged
  `client reconnect failed after= ms tries=`), and when the player cancels. It
  says `Bye` on a connection that is up.
- **A text quest** ([progress/2026-10-19-text-quests-plan.md](progress/2026-10-19-text-quests-plan.md),
  Disconnects). The host drops a peer's queue with the peer, so a quest the
  peer's human was playing never happened there: only its `BeginTextQuest`,
  which applied as it came, did, and the host releases that lock when it
  disconnects the human (`net human N (name) abandoned its text quest
  planet=`). A client that reconnects in the middle of a quest abandons it
  once the state after the reconnect has come: the quest screen
  (`NetPlay.ClientQuestScreen`) closes without `CloseQuest`
  (`TQuestRun.Abandon`), the state is applied, and a bubble says the quest was
  abandoned and can be started again (`Multiplayer.QuestAbandoned`); the
  planet's quest is still in the state. A client that cannot reconnect leaves
  the quest for the main menu the same way. The reconnect box opens over the
  quest screen as over any game screen.
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
  `--sim-turns=DAYS`, and `--sim-net-join=HOST:PORT --sim-net-name=NAME` with `--sim-net-leave-at=DAY`
  or `--sim-net-silent-at=DAY [--sim-net-takeover]` and `--sim-net-reconnect-ms=MS`; the host
  takes `--sim-net-stop-at=DAY`, `--sim-net-host-silent-at=DAY` and `--sim-net-host-exit-at=DAY`;
  see Tests for the others.

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
`GetTickCount64`, which is system-wide on Windows). A sixth run has the client's
connection go silent before its turn of day 3 (`--sim-net-silent-at=3`,
`check_silence`): the host must time it out (`lost: no answer for`) and
disconnect its human 8 to 13 s after the client went silent (the timeout, less
the ping interval its last bytes may be older) and run the days without it; the
client then drops the frozen connection and reconnects by itself, in the same
process (TNetClient's reconnect): the host takes it as a rejoin, and the client
must get its human back and apply the whole state (`rejoin=1`) with the host's
hash (the host, which does not wait for an away human, may have run the other
days by then). A seventh has the client reconnect at once, with its token, while
the frozen connection stays open (`--sim-net-takeover`, `check_takeover`): the
host must take the human over within 3 s, without timing the old connection
out, and the client must play on with the host's hashes. An eighth has the host
go silent after day 3 (`--sim-net-host-silent-at=3`, `check_host_silence`): the
client must time it out 8 to 13 s later, reconnect (the host still counts the
frozen connection, so it is a takeover), get its human back and play the other
days with the host's hashes. A ninth has the host end after day 3 without `Bye`
(`--sim-net-host-exit-at=3`, `check_reconnect_gives_up`), and the client tries
to reconnect for 8 s (`--sim-net-reconnect-ms=8000`): it must give up 8 to 14 s
after the loss and end as host lost ("could not reconnect within"). The unit
tests (`tests/TestNet.pas`) run a `TNetClient` against a scripted host on a
network thread: the reconnect with name and token, commands dropped meanwhile,
the rejoin's state, and its ends (another human, Cancel, the window; a refusal
and `Bye` start none). The runs print the sizes of
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
again after the next state (`net client refusal after state bubble=1`). The
host buys first right before it applies the purchase as it arrives
(`TNetHost.TradeHook`), so the purchase is refused while the client waits for
it (`net trade answered seq= ok=0 reason=out-of-stock`), not at the barrier.
A new game is not recorded (the command log starts at a load), so there only
the refusal is checked. In that run the client also submits, on its first day, a
command whose executor submits another one (`--sim-net-nested`, two probe kinds
registered only then): the client must send the outer one only, and the host
must run each once (`net host nested outer=1 inner=1`). It then sets a session
flag, which the host must refuse (`net command failed ... kind=SetSessionFlag`,
and the client's `net client refused`) without changing its own
(`net host session flag friendly-fire=` differs from what the client predicted).
The client then takes its end turn back (`--sim-net-cancel-end-turn`,
`check_cancel_end_turn`): after its first day's turn it sends `CancelEndTurn`
and waits for the answer, while the host holds its first day until it has taken
an end turn back. The host must take the `EndTurn` out of the queue and be no
longer ready (`net end turn cancelled human= seq= queued= ready=0`), the
client's human must hold the day again (`net client end turn cancel first=1
accepted=1 holds=1`) and ends its turn again, and the day runs. After its
second day's turn, once the host's status says the day runs (or the state has
come), it tries again: the host must refuse it (`net command failed ...
kind=CancelEndTurn reason=too-late`) and the client must hear it (`net end turn
cancel answered ok=0 reason=too-late`). From then on its turns in normal space
fly to the farthest planet of its star and ask to continue until arrival
(`HeadlessNet.PlayFarTravel`); after the first state that says it continues
(not in hyperspace) it stops the travel (`CancelEndTurn` with `StopTravel`),
while the host holds that day until a travel has been stopped: the host must
queue the stop and be no longer ready (`net travel stopped human= seq=
ready=0`), the client's human must hold the day (`net client travel cancel
accepted=1 holds=1`) and plays it, and the other days run with the host's
hashes. Some new games' clients never leave their planet (each takeoff stays
landed); such a run says the travel was untried (`net client travel cancel
untried in-space-turns=0`) and passes. The unit tests check the client's side
against a scripted host: once per `EndTurn`, sent with its number, not waited
for, an applied one taken once, a refusal kept; a continuing travel's stop
without an `EndTurn`, once.

A host that starts a new game and two clients trade at one planet
(`--sim-net-shop`, `check_network_shop`): the host's human is landed at a
planet of its star with a shop (a new game's is docked, so the test moves it)
and opens the shop; the clients join there (`TNetHost.JoinPlanetHook`), with
money and room. On its first day Net1 buys an item X, buys a good and sells it
back, buys an item Y and sells it from the ship screen, buys an item Z, puts it
into its storage and sells it from there (`net client shop sold stored item=`),
and ends its turn. The
host applies each trade as it comes (`net trade applied human= seq= kind=
before=`; the sale with the 3 hold commands before it) and relays it to Net2
(`net relayed human= kind= to=`, trades only, and the two sales as
`RelayedSale` with `sale=SellHeld` and `sale=SellStoredItem`). Right after X is applied, the
host's own human buys X from its grid as it was: refused (`item-gone`), and the
host's grid was rebuilt and its screen told (`net host shop grid shows=0
notified=`). Net2 runs the relays one by one (`net relayed command ran`): its
grid no longer shows X and the planet's stock of the good goes down and up
again (`net client shop relay`), and Y and Z leave the shop and come back from
the sales' relays before any state, its grid shows them and Net1 no longer has
them on its copy (`net client shop sale relay`); every relay runs there
(`ok=1`). Then its purchase of X is refused (`item-gone`)
while it waits. It then ends its turn and at once sends a purchase without
waiting for it (`net client shop sent after end turn seq=`): the host applies it
after that day, and Net2 hears it was applied. Every state has the host's hash.
Before it buys X, Net1 goes through a government dialogue (`EnterGovernment`,
`BeginGovernmentDialog`, `RunScriptsAuxiliaryCode`, `LeaveGovernment`), which the
host applies with the purchase while the host's human has a script dialogue open
(a message, a script and an injected answer): the host's dialogue state must be
as it was after every trade and after the barrier (`net host dialogue kept=1
checks= remote=`).

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
  client host left bye=1 tick=`. With `--sim-net-silent-at=DAY`, after its
  DAY-th state and before that day's turn, it freezes its connection
  (`TNetClient.FreezeConnection`) and prints `net client silent day= human=
  takeover= tick=`; then it waits, reading nothing, for the silence timeout and
  0.5 s more, and drops the connection as if it had closed
  (`TNetClient.LoseConnection`), so it reconnects by itself and plays on. With
  `--sim-net-takeover` it drops it at once and the frozen connection stays open
  until the end, so the host still counts it. The state after a reconnect says
  `rejoin=1` in its day line, and the turn of its day is played again (the host
  never got the one sent before the loss). With `--sim-net-reconnect-ms=MS` it
  tries to reconnect for MS. The host's lines for a disconnect, a lost
  connection and a takeover end with `tick=`, and so do the client's steps of a
  reconnect (`net client lost the host`, `net client reconnect ...`).
- **A silent host.** `--sim-net-host-silent-at=DAY` on the host: after DAY days,
  once every client has the state, it freezes every peer
  (`TNetHost.FreezePeers`), prints `net host silent day= peers= exit=0 tick=`
  and goes on; the peers still there after the silence timeout and 5 s more are
  removed (`net host dropped the frozen peers`). `--sim-net-host-exit-at=DAY`
  freezes them the same way (`exit=1`) and ends without `Bye` (`done net host
  exited`), so its sockets close and nothing listens.
- **Stopping.** `--sim-net-stop-at=DAY` on the host: after DAY days, once every
  client has the state, it stops hosting as the in-game menu does
  (`DisconnectHumans`, then `Bye`) and prints `net host stopped hosting day=
  tick=`.
- **Text quests** (`--sim-net-quest=DAY`, host and clients; docs/progress/
  2026-10-19-text-quests-plan.md, Phase C): on its DAY-th turn a client plays a
  text quest with the headless quest player (`HeadlessQuest`) instead of its
  turn and ends the turn: the planet quest a probe command gives it at its
  planet (`NetQuestProbe`, 1003, registered with the flag, also by the replay),
  or with `--sim-text-quest=NAME` that quest by name. The host lands every client
  at the first one's planet and prints `net host wait day= text=` when its wait
  names a quest and `net host quest begun= barrier= closed= early=` at the end
  (the remote humans' `BeginTextQuest`s, the quest commands its barrier applied,
  the `CloseQuest`s among them, and those applied anywhere else); a client
  prints `net client quest open|status|done|owed ...`, the wait its host's status
  gives (`net client wait human= text=`, through `NetClient.ClientStatusHook`),
  and its day lines say `quest-days=`. A client but Net1 tries once the status
  says another human plays a quest: `net client quest holder` names who holds
  the planet's (the relay), and its `BeginTextQuest` must be refused `in-use`.
  With `--sim-net-silent-at` the client goes silent after one choice of its
  quest instead of before a turn, reconnects, abandons the quest (`net client
  quest abandoned`) and checks the quest is still there after the state (`net
  client quest after rejoin`). `tools/test.py` runs three of these per save: two
  clients (the lock, the barrier, the waits, the replay), one with the prison
  quest by name (the days owed count down while the host runs the days, the
  replay), one silent.
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
- A client that loses its host on a screen that does not start a day (a shop,
  the ship, the galaxy map) finds out when it next opens one of those.
- Chat is in the protocol (the host relays it); nothing shows it.
- A reconnect loses the client's actions since the last state the host took
  for it: at most one day's commands of one human, which the host never got or
  dropped with the old connection. Until the state after the reconnect is
  applied the client drops its commands; a client that stays in a shop or on
  the ship screen meanwhile plays on its old copy (its trades are refused as
  unanswered) until it leaves for a screen that starts a day.
- The reconnect's box and the waits' Cancel are not exercised by the tests (no
  window runs in them); the headless client reconnects through the same
  `TNetClient` code. The same holds for the Cancel that takes the end turn back:
  the headless runs send `CancelEndTurn` through `TNetClient` directly, and
  nothing runs the host's own Cancel.
- A takeoff's end turn cannot be taken back, nor a jump in hyperspace. The
  host's own Cancel at the end of a continuing film, and its break, are not
  run by the tests (they need the star map's film).
- A client's stop that comes while the host's barrier applies the queues is
  refused without a stop queued; the client stops after the next state, which
  may cost it one more day of travel.
- In some new games the headless client's takeoff (`PlayHumanTurn`) never
  leaves the planet: every day it is landed again. Not looked into.
- A host whose player keeps a box open holds its clients' trades; they give up
  after 10 s and get the answer later (Trades).
- `ContinueUntilArrival` and `EndedTurn` are not in a state; this is harmless
  (The day).
- Text quests: no one can watch another human's quest yet (the plan's Phases D
  and E); the planet screens' "is playing this quest" and the automatic owed
  days are not run by the tests (they need the screens). A released prisoner who
  owes days takes off as in single player, and the star map then ends its turns
  only when the player does.
