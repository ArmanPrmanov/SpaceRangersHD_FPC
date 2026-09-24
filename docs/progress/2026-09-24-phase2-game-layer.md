# 2026-09-24 — Phase 2, second session: game layer separated

- Done:
  - Per-human state (item 2). `LocalHuman` now also holds:
    - the message bubbles and shown tips (1e1030f)
    - the open shop's grid (de8a4b3)
    - the hangar's saved ship ids (1a25c24)
    - the hold order (3e7c5de; the model moved from fShip2 to the new unit
      `aHold`)
    - the ship trade price table (30894b0)
    - the star map weapon panel flag (6085036)
  - Script interface overrides (4c57f1a). The data and save format stay in
    aGalaxy; the code that touches controls moved verbatim into UI subclasses
    (`InterfaceOverrideViews`), created through class variables.
  - The star map scene setup moved from `TStar` into a class helper in
    `scene/StarScene` (7a79319). Callers are unchanged.
  - Reclassified by location:
    - `Robot.pas` moved to `arcade/`, and the check now counts `arcade/` as
      presentation (280c299).
    - `aSaveLoad.pas` moved to `source/` (8f473db). Nothing in the
      simulation uses it; it is the application's save/load controller.
  - The check now covers root globals (92cea12). The 101 globals from
    `Globals`/`GlobalsV`/`GR_Main` that the simulation uses are classified in
    `tools/layers_globals.txt` (session, film, scene, app, data, settings,
    ui). Using an unclassified one, or a ui one, fails the check.
  - Game units ask the UI through new `SimEvents` queries instead of reading
    screen globals: `HumanScreen`, `InspectedShip`, `TalkScreenOpen` and
    `PlaySound` (6085036).
- State: every unit under `source/game` and `source/core` is free of UI
  units and ui globals, except `aPlayer -> RequestedScreenId` (the ordering
  case in `CloseRuinsModeScreen`, see the first Phase 2 entry). The 66
  remaining allowlist entries are all `aScript`/`aScriptFun`. Save tests,
  unit tests and the layer check pass after every commit.
- Deviations from the roadmap text:
  - The `TStar` fields `DaysSincePlayerVisit`, `PlayerPresenceLevel` and
    `PlayerFilmPath` stay on `TStar`. They are star-level aggregates ("days
    since a human visited", "human presence", the path the film camera
    follows). Phase 4 changes their update condition from "the player is
    here" to "a human is here"; moving them into a per-human record would be
    wrong.
  - The `Session`/`Settings`/`UiState` records are not done. Grouping every
    root global would rewrite about 11,200 sites (Globals 3,657, GlobalsV
    2,848, GR_Main 4,699), the kind of mass rewrite the principles warn
    against. The classification table meets the stated purpose (it shows
    which globals the simulation touches) and the check enforces it. Waiting
    on the project owner's decision.
- Next:
  - The script builtins. `aScriptFun` has 713 routines; about 60 are UI
    builtins (dialogs, forms, message boxes, interface and star map
    control, arcade ships). Split them into a UI unit. Registration order
    must be kept, because scripts may bind builtins by index. Keep the
    `Scope.Add` lines where they are and take the function pointer from a
    table that the UI unit fills in its initialization section. It must run
    before `InitializeScriptHostRuntime`, which runs before
    `InitializeScreens`.
- Notes:
  - Not covered by the save tests: interface overrides (no test save has
    any) and `GetBoostStatusText` (tooltip only).
  - A class helper (`TStarScene`) is the least invasive way to move
    presentation methods off a simulation class: `Self` and name lookup
    work as in a method, so the bodies stay verbatim. Use `with` instead
    and locals can resolve to fields.
  - After removing a unit from a `uses` clause, check that none of its
    top-level names is still referenced. Otherwise a name that exists in two
    units could silently bind to the other one. Every removal this session
    was checked this way.
  - The workflow for a UI edge: scan for identifiers declared only in that
    UI unit, then either move the state (to `LocalHuman` or a game unit),
    move the presentation code (a subclass or helper), or route it through
    `SimEvents`.
