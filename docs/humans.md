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
- `Actor(Command)` and `ActorHuman(Command)` are the human who issued a
  command. Executors use them, never `LocalHuman`.

| Name | Meaning |
| --- | --- |
| `LocalPlayer`, `LocalHuman` | the human at this machine (UI only) |
| `Actor(Command)`, `ActorHuman(Command)` | the human who issued the command |
| `ActingHuman` | the human whose command is executing; nil outside a command |
| `ScriptHuman`, `ScriptPlayer` | the human of the script code that is running, and its ranger; nil outside script code |
| `BoundHuman(Script.HumanId)` | the human a script is bound to |
| `Session.Humans` | every human |
| `IsHuman(Ship)` | whether a ranger is a human's |
| `HumanOf(Ship)` | the `THuman` of a human's ranger, or nil |
| `StarHasHuman(Star)` | whether some human's ranger is in the star |
| `StarHasHuman(Star, Ship)` | the same, not counting `Ship`, for example a human who is party to a talk others overhear |
| `StarHasHumanInSpace(Star)` | whether some human's ranger is in the star in normal space, where it sees the fights |
| `FilmHuman(Star)` | the human whose view the star's shared film follows (radar range, film path, camera): the local human when it is in the star, else the first human there; nil when none is |
| `HasLivingHuman` | whether some human's ranger still has hull points; the day stops when none does |
| `FindHuman(Id)` | the human with that id, or nil |
| `IsRuinsProxy(Station)` | whether a station is some human's ruins proxy, the storage station that is not part of the galaxy |
| `Human.AddOrUpdateBubble(...)` etc. | that human's message bubbles; the `Globals` functions of the old names are the local human's |
| `JoinHuman(Planet, Name, Preset)` | adds a human landed at a planet |

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
  when the bound one has left. The save does not hold the binding yet, so a
  loaded script is bound to the first human (`HUMANS: per-human save block`
  in `TScript.ResolveLoadedReferences`).
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
  human's.
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
  human (`LocalPlayer`, `LocalHuman`). A builtin that opens a dialogue or a
  screen does so only when `ScriptHuman` is the local human, and is marked
  `// HUMANS: remote dialogue (Phase 5)`; so are the queued battles. Text
  quests are off in multiplayer (ROADMAP.md, Phase 6), so they follow the
  local human.

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
  converted, since extra humans stop being treated as NPCs.
