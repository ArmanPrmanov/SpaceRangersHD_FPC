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
| `source/net/NetDelta.pas` | `CompressState` / `ExpandState`: whole states and deltas (zstd with the old state as reference, like `--patch-from`) |
| `source/net/NetProtocol.pas` | message kinds, their encoding, protocol version, the data hash |
| `source/net/NetThread.pas` | the network thread: owns every socket, moves bytes, queues whole messages per peer |
| `source/net/NetHost.pas` | the host session: peers, joins, commands in, states and films out |
| `source/net/NetClient.pas` | the client session: hello, commands out, films and states in |
| `source/net/NetSession.pas` | what the rest of the game calls: role, pump, hooks |

`source/game`, `source/core` and `source/script` do not use `source/net`. The
game layer exposes hooks (procedure variables, as `BeforeCommandHook`); the net
units set them. `tools/check_layers.py` keeps that direction.

## Threads

- **The network thread** owns the listener and every connection. It waits on
  the sockets (a few ms), sends what is queued, and cuts received bytes into
  messages, which it appends to the peer's inbox under one lock. It sets
  `NetInboxEvent` when a message arrives. It never touches game state.
- **The UI thread** pumps the inboxes once per frame (`NetSession.Pump`, from
  `GR_WinMessage`) and at the safe points below. Everything that changes the
  game from the network happens in the pump or at a safe point, never on the
  network thread.
- **The turn thread**, on the host, reads one peer's inbox only while it waits
  for that peer's human to answer a dialogue (Remote dialogue).
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
| `State` | host → client | day number, base day (0 = whole), state hash, zstd bytes (`NetDelta`) |
| `Film` | host → client | day number, star id, the film (`TEFilm.SaveToBuffer`) |
| `Command` | both | an encoded `TPlayerCommand` (`aCommands.EncodeCommand`) |
| `Ack` | client → host | the day of the last state the client applied |
| `Status` | host → client | per human: id, name, connected, holds the day; whether a day is running |
| `TalkRequest` | host → client | the dialogue the host's day asks the client's human (Remote dialogue) |
| `TalkDone` | client → host | the client's answer is complete |
| `Chat` | both | sender human id, text; the host relays it to every client |
| `Bye` | both | the sender leaves |

## Joining

1. The client connects and sends `Hello`.
2. The host refuses when the protocol version or the data hash differs. Build
   hashes may differ, since platforms differ.
3. The host takes the join at a quiet point: no turn job running and no day
   under way. A join that arrives mid-day waits in the peer's inbox.
4. **Rejoin.** When a disconnected human's ranger has the name the client
   gives, the client takes that human back. Otherwise the host submits the
   `JoinHuman` command (kind 44) as the host human, which adds a human landed
   at a coalition planet (`FindJoinPlanet`). The command log records it.
5. The host sends `Welcome` and a whole `State`. The client loads it, makes its
   human the local one and opens its screen (Applying state).

A human who joins or leaves is a normal operation. Human ids are ship ids and
are never reused, so a log or a save can name a human who has left.

## Commands

- The client's UI submits commands as always. `SubmitCommand` executes the
  command at once on the client, which is the prediction, and the client's
  `AfterCommandHook` sends it to the host.
- The host refuses a command whose actor is not the peer's human, and queues
  the rest per peer. It does not execute them as they arrive: arrival order
  depends on the network, and the day's outcome must not.
- A peer is **ready** when its queue holds an `EndTurn` (kind 43), or when its
  human does not hold the day anyway (`HumanHoldsDay` is false: continuing
  travel, in hyperspace, finished) or is disconnected.
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
- **Client.** A client never starts a day. Its end turn sends `EndTurn` and its
  screen waits until the host's state for the next day has been applied.
- A disconnected human does not hold the day (`THuman.Connected`, see
  Disconnects).

## Films

The player-star job records one film per star that holds a human (`aStarFilms`).
After the job, the host encodes the film of each star that holds a remote human
once and sends the same bytes to every client in that star (`Film`). The film
goes before the state: it is small and needed first.

The client plays it on the star map as the history viewer plays a stored film:
the film's objects bind to the client's scene objects by kind, graphics key
and id, and objects the client does not have (missiles, drops, ships that
arrived that day) are created for the film (`fFilm.CreateFilmSceneObjects`,
`ReuseSceneObjectsForPreloadedFilm`). The client needs the new state at the end
of the film, since the end-of-film branch reads it (landed, docked, in
hyperspace); it waits there for the state when it has not arrived.

A client that is landed, docked or in hyperspace plays no film.

## States

- **What.** `WriteGameCheckpoint` (`aSaveLoad`): the galaxy as the save writer
  writes it, the per-human block with every human, the exact values and the
  local human's state. It touches no screen and changes nothing. The host takes
  it on the UI thread at a quiet point after the day: no job running and the
  next day prepared (`Session.PlayerStarDayPrepared`), or, when the host's
  screen does not prepare days (landed, docked, in hyperspace, headless),
  after the galaxy job.
- **Deltas.** The host keeps the uncompressed states that some client may still
  use as a base: each client's last acknowledged day, and the newest. A state
  goes to a client as a delta against its acknowledged day (`CompressState`
  with that state as reference), or whole when it has none. Clients with the
  same base get the same bytes; the host compresses once per base. The
  compression runs on the network thread.
- **Hash.** `State` carries the host's state hash of the day. After loading, the
  client hashes its state the same way; a difference is logged as a desync (it
  should never happen, since the client loads the host's bytes).
- **Ack.** A client acknowledges a day after applying it, and keeps those
  uncompressed bytes as the base of the next delta.

## Applying state (the safe point)

Loading a state frees every galaxy object, and screens hold direct references
to ships, planets and items. So a client applies a state only at a safe point:

- The client is waiting (its human ended the turn), so it is on one of the
  screens that start a day (star map, planet or station panel, jump screen),
  and no shop, dialogue or other screen is open above it.
- The waiting screen closes, and the state is applied between two screens, where
  hot-seat applies a turn pass (`HotSeat.ApplyTurnPass`): `ReadGameCheckpoint`,
  then `SetLocalHuman` back to the client's own human (the state was written
  with the host's human as local), then the human's screen opens: the planet,
  the station, the jump screen or the star map centred on its ship.
- A debug build started with `--poison-frees` fills freed memory with a pattern
  and holds it back from reuse for a while, so a stale reference fails at once.

## Waiting

A screen that waits for the day shows who it waits for (from `Status`: the
humans who hold the day, and who is disconnected), stays modal and does not
change the game. On the host it waits for the barrier; on a client it waits
for the state. A remote dialogue can open above a waiting client screen.

## Remote dialogue

During the host's day an NPC or a script may ask a human something: a hail, a
demand, an offer, a partner's complaint (`TShip.OpenPlayerConversation`,
`ShowPlayerDialogue`, `TPlanet.RequestDialog`). For the local human the turn
thread waits while the UI thread shows the talk screen. For a remote human:

1. The turn thread sets the talk fields on that human's `THuman` (`TalkShip`,
   `TalkPlanet`, `TalkType`, `TalkAmount`, `TalkText`, `TalkScripted`), and calls
   the net hook, which sends `TalkRequest` to the human's client and waits.
2. The client, which is waiting for the day, opens the talk screen over its
   previous-day state for the ship or planet the request names. Every answer is a
   command (kinds 300-399), predicted locally and sent to the host as usual.
   When the talk screen closes, it sends `TalkDone`.
3. On the host, the waiting turn thread reads that peer's inbox itself: it
   executes each `Command` through the same path the pump uses (recorded, actor
   checked), and returns on `TalkDone`. The day goes on with the answer in the
   human's `TalkResponse`.
4. When the client cannot show the talk (the ship or planet is not in its state,
   or it is not waiting) it sends `TalkDone` at once, and when the peer
   disconnects the wait ends; either way the talk ends as it does for a human
   on automatic control.

Every other human waits meanwhile, as for any dialogue: the day is paused.

## Disconnects

- A peer whose connection closes, or who sends `Bye`, is disconnected:
  `THuman.Connected` is false, the human does not hold the day, and its ranger
  holds position (the host submits the stop order as that human). It stays in
  `Session.Humans` and in saves.
- It rejoins by joining with the same ranger name (Joining).
- Humans in a save that the host loads start disconnected, except the host's.
- `Connected` is not saved; it is session state, not game state.

## Hosting and joining

- Command line: `--host=PORT` (with `--load-save=PATH`) hosts a game;
  `--join=HOST:PORT --name=NAME` joins one.
- In the game: the in-game menu hosts the running game; the main menu joins one
  (address and name).
- Headless, for tests: `--sim-net-host=PORT --sim-net-clients=N` with
  `--sim-save`, and `--sim-net-join=HOST:PORT`; see Tests.

## Tests

`tools/test.py` plays every save networked over loopback: a headless host and N
headless clients as separate processes (N = 1 and 7, so 2 and 8 humans). Each
client plays scripted days (take off, fly, land, buy) and ends its turn; the host
runs the days. Every client's state hash must equal the host's for every day;
two runs must give the host the same hashes, however the commands arrived; the
host's command log must replay to the host's final hash; and a client that
drops and rejoins must get its human back. The runs print the sizes of whole
states, deltas and films, and the load time, per day.
