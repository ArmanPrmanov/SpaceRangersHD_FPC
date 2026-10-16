# 2026-10-16 — Silent disconnects and reconnection

## Problem

TCP does not notice a silent loss (Wi-Fi gone, cable pulled, laptop asleep,
router reset). The network has no keepalive and no silence timeout
(`platform/net_native.c`, `source/net/NetTransport.pas`, `NetThread.pas`), so:

- a host that only waits for a client's end of turn never learns the client is
  gone, and the day waits for that human forever;
- the player cannot come back: the host refuses a name whose human is
  connected (`TNetHost.ProcessJoins`, "a human of that name plays");
- a client whose host went silent waits forever too;
- a client that does see the loss goes straight to the main menu.

The only way out today is Stop hosting and host again.

## Decisions

1. **Our own ping, not TCP keepalive.** TCP keepalive starts after 2 h by
   default and is set up differently on each OS. Every connection on the
   network thread sends `Ping` (kind 17, no payload) when it has sent nothing
   for `NetPingIntervalMs` (2 s). Any bytes received count as a sign of life,
   so a long state never looks like silence. A connection that has received
   nothing for `NetSilenceTimeoutMs` (10 s; one variable, for a slower
   internet link later) is closed by the network thread with the error "no
   answer for N s". After that, everything above it sees an ordinary closed
   connection: a disconnect on the host, a lost host on a client. Pings are
   sent and checked only on the network thread, never in a screen's loop, so a
   long day or an open box cannot cause a false timeout. The thread swallows
   `Ping`; no inbox ever sees it.
2. **The reconnection token.** `Welcome` carries a 64-bit random token per
   human (one per human per hosting session, kept by the host), and `Hello`
   carries the token the client holds (0: none). A Hello whose name is a
   connected human's and whose token matches takes the human over at once:
   the host removes the old peer (`TNetThread.RemovePeer`, so a turn thread in
   `RemoteTalk` sees it closed) and marks it `Leaving`. The usual
   `ProcessLeaving`, then `ProcessJoins`, then disconnect the old one and let
   the new one rejoin at the next quiet point. Without the token (another
   machine, a restarted game) the refusal stays as it is. The silence timeout
   frees the name within 10 s anyway, so nobody can throw a live player out by
   typing their name. The token comes from the OS (`sr_random_bytes` in
   `net_native.c`: `BCryptGenRandom` / `/dev/urandom`), never from `Random` or
   the game's generators, which the game's determinism depends on.
3. **The client reconnects by itself.** When a client that was joined loses
   its host (closed or silent, but not the host's `Bye` and not a refusal),
   `TNetClient` connects again to the same address with the same name and
   token, for `NetReconnectMs` (60 s) at most. Each try is a
   `TNetConnectAttempt` with a short timeout. Meanwhile the game shows a box,
   "Reconnecting to the host…", with Cancel. A successful rejoin brings a
   `Welcome` (same human id) and a whole `State`. That state goes through the
   existing safe-point path (Applying state) and the human's screen opens
   again. Everything else of the old connection is dropped: films, the talk,
   relays, the base states, the command numbers (the host numbers per
   connection). A trade waiting for its answer is refused here, the same as a
   timeout. The commands since the last state are lost, which is at most one
   day's unacknowledged actions of one human. Failure or Cancel goes to the
   main menu with the reason, as today.
4. **The host keeps doing what it does now.** The ranger holds position, the
   day runs without that human, and a rejoin takes the ranger as it stands.

`ProtocolVersion` becomes 9 (Hello and Welcome carry the token; `Ping`).

## Stages (one subagent each, run one at a time in the main tree)

**A. Liveness and takeover (network layer, host).**
- `nkPing`, the ping and silence timeout in `TNetThread`, error text, and the
  variables. A test switch `TNetThread.FreezePeer(Id)` stops reading, writing
  and pinging that peer without closing its socket.
- Token in Hello/Welcome, `sr_random_bytes`, host token map, takeover on
  Hello.
- Unit tests (`tests/TestNet.pas`): two threads over loopback, a frozen peer
  is closed by the other side within the timeout (shortened for the test); a
  peer that receives a large message slowly is not timed out; `Ping` never
  reaches an inbox.
- Headless: `--sim-net-silent-at=DAY` (the client freezes its connection), so
  the host must print the disconnect within the timeout (ticks, as the
  stop-at test does); `--sim-net-takeover` (the client freezes and at once
  joins again with its token), so the host must take the human over before any
  timeout. `tools/test.py` checks both.

**B. Client reconnection and its box.**
- The reconnection state machine in `TNetClient`, as in decision 3.
- `NetPlay`: the box with Cancel over the innermost screen (as
  `TNetWaitBoxGI`). `NetFrame` and `LeaveLostGame` go to the menu only after
  the reconnection gives up.
- Headless: the silent and takeover runs reconnect through `TNetClient`
  itself, and the client must get its human back and match the host's hashes
  afterwards.

**C. Review and docs.** Review of the diff by the orchestrator; update
`docs/network.md` (Messages, Joining, Disconnects, Tests, Not done yet) and
the progress status.

## Results

**Stage A** (4207331): `tools/test.py` 5/5 (goldens unchanged, replays). A
client that goes silent is timed out and disconnected by the host after about
8.9 s (the 10 s timeout less the age of its last ping); a client that joins
again with its token is taken over in 15 ms, without a timeout.

**Stage B.** The reconnect lives in `TNetClient` (`ConnectionLost`,
`BeginReconnect`, `ReconnectStep`, `StopReconnect`, `CancelReconnect`,
`LoseConnection` for the tests): in place, on the same object and network
thread, a new `TNetConnectAttempt` per try (5 s at most, 1 s apart) and the
old peer removed. `Connected` stays true while it reconnects, so the screens
keep waiting; commands are dropped until the state after the reconnect is
applied. `NetPlay` shows the reconnect in the client's waits (with Cancel) and
in a box of its own over the innermost screen (`ClientReconnectWait`), and
applies the rejoin's state at the next safe screen when no wait is open
(`ApplyRejoinState`, the screens `LeaveLostGame` leaves from).
`NetSession.JoinAgain` is gone. Measured with `tools/test.py` (5/5, goldens
unchanged, replays), per save:

| Run | Measured |
| --- | --- |
| client silent, then drops the frozen connection (rejoin) | host disconnects it after 8.7–9.0 s; welcomed again 47–438 ms after the drop (the host takes joins between days), 1 try |
| client silent, reconnects at once (takeover) | taken over in 0–15 ms, welcomed after 16–31 ms; 8 states after it with the host's hashes |
| host silent after day 3 | the client times it out after 9.3–9.4 s and is taken over in 31–63 ms, 1 try; 8 states after it with the host's hashes |
| host ends without Bye after day 3, window 8 s | noticed in 0–16 ms; 3 tries; gives up 8.0 s after the loss |

Unit tests (`tests/TestNet.pas`, a `TNetClient` against a scripted host): 540
checks pass. The reconnect box, the waits' Cancel and the apply of a rejoin
state outside a wait are not exercised (no window runs in the tests); the
headless client goes through the same `TNetClient` code. In one full run the
new game's buy race (`check_refusal`, "the host never bought a client's goods
first") failed once and passed in four runs alone and in the next full run;
it does not touch the reconnect.
