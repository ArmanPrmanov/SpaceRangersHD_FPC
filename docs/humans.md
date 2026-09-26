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
  filmed, the message bubbles, the open shop, the conversation and the hold
  order. `HumanOf(Ship)` finds the human for a ranger.
- `Actor(Command)` and `ActorHuman(Command)` are the human who issued a
  command. Executors use them, never `LocalHuman`.

| Name | Meaning |
| --- | --- |
| `LocalPlayer`, `LocalHuman` | the human at this machine (UI only) |
| `Actor(Command)`, `ActorHuman(Command)` | the human who issued the command |
| `ActingHuman` | the human whose command is executing; nil outside a command |
| `Session.Humans` | every human |
| `IsHuman(Ship)` | whether a ranger is a human's |
| `HumanOf(Ship)` | the `THuman` of a human's ranger, or nil |
| `StarHasHuman(Star)` | whether some human's ranger is in the star |
| `FindHuman(Id)` | the human with that id, or nil |
| `Human.AddOrUpdateBubble(...)` etc. | that human's message bubbles; the `Globals` functions of the old names are the local human's |
| `JoinHuman(Planet, Name, Preset)` | adds a human landed at a planet |

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
  `ActingHuman`. Elsewhere, pass the human in as a parameter from the caller
  that knows it.
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
  converted, since extra humans stop being treated as NPCs.
