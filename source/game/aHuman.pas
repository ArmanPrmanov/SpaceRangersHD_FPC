{$EXCESSPRECISION OFF}
unit aHuman;
{$R-}
{$Q-}
{$B-}
{$A8}

// CHANGE: CLEANUP - The humans in the game and the state that belongs to each of them rather
// than to the galaxy. These were separate globals in aGalaxy and aRanger; the fields keep
// their names. The state is not part of TPlayer because it outlives the player's ship.
// docs/humans.md describes how the game code refers to humans (ROADMAP.md, Phase 4).
interface
uses
  Classes,
  SyncObjs,
  EC_Str,
  Globals,
  aGalaxy,
  aHold,
  aItem,
  aPlanet,
  aPlayer,
  aRanger,
  aRuins,
  aShip,
  aCommands;
type
  // Read back as TGoodsTradePriceEntry, so the layout must match it.
  TGoodsShopTradeRow = record
    Count: Integer;
    MaximumPrice: Single;
    PurchasePrice: Integer;
    BaseSalePrice: Integer;
  end;
  THuman = class
    // The human's ranger. Nil once it is destroyed in single player; the id stays.
    Player: TPlayer;
    // The ship id of the human's ranger. It is never reused within a game, so commands,
    // saves and logs can refer to a human who has left.
    Id: Integer;
    // Whether the human has pressed end turn for the coming day. The day runs only when no
    // human holds it (HumanHoldsDay); the player-star job clears it (StartDayRound).
    EndedTurn: Boolean;
    // CHANGE: ENHANCEMENT - The human ended its turn with "continue until arrival": it counts
    // as having ended every day while its travel goes on (HumanTravelContinues). Set by the
    // EndTurn command; not saved, so a load makes the human end its turns again.
    ContinueUntilArrival: Boolean;
    // A day passed while the human's ranger jumps: the jump screen's hyperspace step is due
    // (NeedsHyperspaceStep). The HyperspaceStep command clears it.
    HyperspaceStepPending: Boolean;
    // The star the human is in; its day is simulated with the film.
    PlayerStar: TStar;
    PlayerDialogueRequestCount: Byte;
    PendingPlayerFollowTarget: TShip;
    PlayerAutomaticControl: Boolean;
    PlayerEquipmentBrokenThisTurn: Boolean;
    PlayerOldQuests: TList;
    // Tips already shown, one bit each.
    ShownPlayerTips: Cardinal;
    // The message bubbles, guarded by PersistentPlayerMessageLock.
    FirstPersistentPlayerMessage: TMessagePlayer;
    LastPersistentPlayerMessage: TMessagePlayer;
    // The shop the human has open: its stock (aShopStock) and where it came from.
    TemporaryShopSlots: TList;
    TemporaryShopPlanet: TPlanet;
    TemporaryShopStation: TRuins;
    // CHANGE: BUGFIX - The columns the human's shop screen shows, which pad its shop grid
    // (aShopStock.ShopColumnCount); the commands that build the grid carry them. It was one
    // global, so a client's command set the host's. 0 until a command sets it: this machine's
    // screen's. Layout, not game state: not saved (the grid itself is).
    ShopColumnCount: Integer;
    // Ships shown in the hangar's nine slots, by id.
    HangarShipIds: array[0..8] of Integer;
    // The ship screen's hold order (aHold) and the ship it lists.
    PlayerHoldEntries: TList;
    PlayerHoldShip: TShip;
    // What the human holds on the ship screen's cursor (aHoldActions): taken out of the
    // hold, a slot or the storage, and in no galaxy list until it is put down. Origin 0 is
    // the ship, 1 the storage; Slot is where it goes back.
    SelectedHoldKind: TPlayerHoldKind;
    SelectedGoodsIndex: Byte;
    SelectedGoodsQuantity: Integer;
    SelectedGoodsCost: Integer;
    SelectedHoldItem: TItem;
    SelectedHoldOrigin: Integer;
    SelectedHoldSlot: Integer;
    SelectedHoldUsesDisplayOrder: Boolean;
    // The edited ship's own free experience while the screen shows the player's instead;
    // -1 when it does not.
    SavedShipExperience: Integer;
    // CHANGE: BUGFIX - The ship whose screen the human has open, from the OpenShipScreen
    // command to the CloseShipScreen that leaves it (also while the screen is closed to show
    // another one and comes back), and whether the ship screen shows now (until any
    // CloseShipScreen). Another human may not open a ship one human has open, but its own
    // ranger (aHoldActions, OpenShipScreen): two humans editing a sponsored station's ship
    // swapped their experience and took items by stale hold cells. Session state, not game
    // state: not saved; ReleaseShipScreen clears it when the human leaves, disconnects or
    // respawns, and a load (RebuildHumans) forgets it.
    EditedShip: TShip;
    ShipScreenShown: Boolean;
    // Prices while trading with a ship in space.
    TradeRows: array[0..7] of TGoodsShopTradeRow;
    // Whether the star map shows its weapon panel.
    StarMapWeaponPanelOpen: Boolean;
    // The conversation the human is in: with a ship or a planet, and what the turn thread
    // and the conversation screen pass each other.
    TalkShip: TShip;
    TalkPlanet: TPlanet;
    TalkScripted: Boolean;
    TalkType: Byte;
    TalkResponse: Byte;
    TalkText: WideString;
    TalkAmount: Integer;
    // The government the human talks to (aPlanetActions): the planet scripts with a dialog
    // for it and the one being shown, and the quest it offers and how far the human has
    // negotiated it.
    GovernmentDialogNames: TStringsEC;
    GovernmentDialogCursor: Integer;
    GovernmentQuestOffer: TQuest;
    GovernmentQuestLevel: Integer;
    GovernmentQuestRewardStep: Integer;
    GovernmentQuestDurationStep: Integer;
    // The satellite on the uninhabited planet's cursor (aPlanetActions), in neither the hold
    // nor the deployed satellites while it is held. Origin 0 is the hold, 1 an orbit.
    PlanetHeldSatellite: TSatellite;
    PlanetHeldSatelliteOrigin: Integer;
    // CHANGE: ENHANCEMENT - The cheats the human has used, by name, and the cheat points
    // they cost (ROADMAP.md, Phase 6: the host sees which humans used which cheats). Saved in
    // the per-human save block (aHumanSave).
    UsedCheats: array of WideString;
    CheatPoints: Integer;
    // CHANGE: ENHANCEMENT - Whether the human's game has ended while others play on: a quest
    // script's EndGame ends it for the script's human only in multiplayer (ROADMAP.md, Phase 6;
    // FinishHuman). FinishReason is the reason EndGame gave (Session.GameEndReason's values),
    // or -1 when it gave none, which is the ending with the credits. Saved in the per-human
    // save block (aHumanSave).
    Finished: Boolean;
    FinishReason: Integer;
    // CHANGE: ENHANCEMENT - Whether the human's machine is connected (ROADMAP.md, Phase 5;
    // docs/network.md, Disconnects). A disconnected human does not hold the day and its ranger
    // holds position until it rejoins. Session state, not game state: it is not saved, and it
    // is True everywhere but on a host.
    Connected: Boolean;
    // CHANGE: BUGFIX - The human's script asked it to take off (ExtremalTakeOff) or to end its
    // turn (ForceNextDay). They were two globals, so a remote human's script made the host's
    // own human take off, and a client's command cleared the host's request. The screens of
    // the machine the human plays on act on them (aScript.DispatchPendingScriptRequests); the
    // OrderScriptTakeoff and ClearScriptEndTurn commands clear their actor's. Requests for
    // the UI, not game state: not saved.
    ScriptTakeoffRequested: Boolean;
    ScriptEndTurnRequested: Boolean;
    // CHANGE: BUGFIX - The human's script dialogue state (aScript.TScriptDialogState: the dialog
    // message, the dialog's script, the injected answers, overrides and blocks) while it is not
    // in the globals that hold it. It was one for all humans, so a client's dialogue applied on
    // the host overwrote the host's own and freed answers its screen still showed. The globals
    // hold the local human's; a command of another human swaps that human's in while it runs
    // (aScript.EnterHumanDialogState). Created when first needed; UI state, not saved.
    ScriptDialogState: TObject;
    constructor Create;
    destructor Destroy; override;
    // The message bubbles, under PersistentPlayerMessageLock. SkipLock means the caller
    // holds it. Globals has the same functions for the local human.
    procedure ClearBubbles;
    function CountBubbles: Integer;
    function IsBubbleQueued(MessageEntry: TMessagePlayer; SkipLock: Boolean): Boolean;
    procedure RemoveBubble(MessageEntry: TMessagePlayer; SkipLock: Boolean);
    function RemoveBubblesExceptKinds(
        Key: WideString;
        ExcludedKinds: TPlayerMessageKindSet;
        SkipLock: Boolean
    ): Boolean;
    function FindBubbleByText(const Text: WideString; SkipLock: Boolean): TMessagePlayer;
    function FindBubbleByKey(const Key: WideString; SkipLock: Boolean): TMessagePlayer;
    procedure RemoveBubbleByKey(const Key: WideString);
    procedure RemoveBubblePages(const Prefix: WideString; FirstPage: Integer);
    function FindBubbleExceptKinds(
        const Key: WideString;
        ExcludedKinds: TPlayerMessageKindSet;
        SkipLock: Boolean
    ): TMessagePlayer;
    function CreateBubble: TMessagePlayer;
    function AddOrUpdateBubble(
        Kind: Byte;
        Turn: Integer;
        const Text, Key: WideString
    ): TMessagePlayer;
    procedure PruneExpiredBubbles;
    // Records that the human used the cheat Name, which cost Points. A cheat command's
    // executor calls it for the command's actor.
    procedure RecordCheat(const Name: WideString; Points: Integer);
    function HasUsedCheat(const Name: WideString): Boolean;
    function HasCheated: Boolean;
    procedure ClearCheats;
    // Closes the ship screen the human has open (EditedShip) as far as the game is concerned:
    // the ship's experience comes back from the player's, as CloseShipScreen does, and no
    // human has the ship open any more. For a human whose machine will not close it.
    procedure ReleaseShipScreen;
  end;
  // The humans in join order. Every TPlayer in the galaxy is in it, and nothing else is.
  THumanList = class(TList)
  private
    function GetHuman(Index: Integer): THuman; inline;
  public
    property Items[Index: Integer]: THuman read GetHuman; default;
  end;
var
  // Guards every human's message bubbles; Globals creates and frees it.
  PersistentPlayerMessageLock: TCriticalSection;
  // The human whose command is executing (aCommands.ExecuteCommand), nil outside a command.
  // Code an executor calls uses it where it means "the human doing this".
  ActingHuman: THuman;
  // The human of the script code that is running (aScript): the script's bound human, the
  // human who holds the item whose code runs, or DefaultScriptHuman for code of no script.
  // Every entry into script code sets it and restores the previous value; nil outside.
  // Script functions use it where they mean "the player" (docs/humans.md, Scripts).
  ScriptHuman: THuman;
  // The human at this machine: whose screen this is. LocalPlayer is its ranger.
  LocalHuman: THuman;
  // CHANGE: ENHANCEMENT - Whether a human added other than the local one (a load, a join)
  // starts connected (THuman.Connected). A host sets it to False: the humans of a save it
  // loads start disconnected, and a joining peer's human is connected when the peer takes it
  // (docs/network.md, Disconnects).
  NewHumansConnected: Boolean = True;
// The human whose ranger is Ship, or nil when Ship is not a human's ranger.
function HumanOf(Ship: TObject): THuman;
// Whether Ship is a human's ranger. Every TPlayer is.
function IsHuman(Ship: TObject): Boolean; inline;
// Whether a human's ranger is in Star, in normal space, docked or landed. Excluded, when
// given, does not count: a human who overhears two others talking is not one of them.
function StarHasHuman(Star: TStar; Excluded: TObject = nil): Boolean;
// Whether a human's ranger is in Star in normal space, where it sees the star's fights.
function StarHasHumanInSpace(Star: TStar): Boolean;
// Whether some human's ranger still has hull points. The day stops when none does.
function HasLivingHuman: Boolean;
// Whether the game has more than one human. The multiplayer rules (ROADMAP.md, Phase 6)
// apply then: a destroyed human respawns (TShip.FindRespawnPlanet), and a script's EndGame
// ends the game for the script's human only. With one human the game is single player and
// keeps the original rules. A human who has finished (THuman.Finished) still counts.
function IsMultiplayer: Boolean;
// Whether Station is some human's ruins proxy: the station a human's ranger docks at to
// reach its storage, which is not a station of the galaxy. It asks every TPlayer in
// Galaxy.Rangers, not Session.Humans, because a joining human creates its proxy before it is
// added to the list.
function IsRuinsProxy(Station: TObject): Boolean;
// The human's ranger whose ruins proxy Station is, or nil; found as IsRuinsProxy finds it.
function RuinsProxyOwner(Station: TObject): TPlayer;
// Whether Star is some human's PlayerStar. Those stars run their day in the player-star
// job, each with a film, and the galaxy job leaves them out (ROADMAP.md, Phase 4).
function IsFilmedStar(Star: TStar): Boolean;
// The filmed stars, in galaxy order.
procedure CollectFilmedStars(Stars: TList);
// The human whose view the film of Star follows: the local human when it is in Star,
// otherwise the first human in Session.Humans who is. A human is in Star when Star is its
// PlayerStar or its ranger's current star. Nil when no human is in Star. All humans in a star
// share its one film (ROADMAP.md, Phase 4, item 2); the film's radar range, the player's film
// path and the camera follow this human.
function FilmHuman(Star: TStar): THuman;
// The human with this id, or nil.
function FindHuman(Id: Integer): THuman;
// CHANGE: ENHANCEMENT - The first human in Session.Humans: the one who created or hosted the
// game, since join order keeps that (ROADMAP.md, Phase 4/6). Nil when there are no humans. Code
// that used to mean "the one player" for a galaxy-wide rule (NPC catch-up, which star the
// dominators spare, the shop stock or reserve cap with nobody acting, whose home sets the
// distance tiers) uses this. With one human it is that human, so single player is unchanged.
function HostHuman: THuman;
// The human a script is bound to (TScript.HumanId), or the first human when it has left or
// the script is not bound; nil when there is none.
function BoundHuman(Id: Integer): THuman;
// ScriptHuman's ranger; nil when there is no script human or its ranger is gone.
function ScriptPlayer: TPlayer; inline;
// The human script code that belongs to no script runs for: ScriptHuman when it runs inside
// other script code, else ActingHuman, else the first human; nil when there is none.
function DefaultScriptHuman: THuman;
// CHANGE: ENHANCEMENT - The human in context: ActingHuman, else ScriptHuman, else HostHuman;
// nil when there is none. Code that used to read one player's state where there is no command
// or script to bind to more precisely (an artefact's weight, a default hull's race or a
// satellite's owner, <Player> in localized text) uses this. With one human it is that human.
function ContextHuman: THuman;
// Makes Player a human. The first human is the local one.
function AddHuman(Player: TPlayer): THuman;
// Forgets Player's human, as when its ranger is freed. The other humans stay. When Player is
// the local ranger, LocalPlayer becomes nil and the local human's state is kept.
procedure RemoveHuman(Player: TPlayer);
// Rebuilds the list from the TPlayer instances in Galaxy.Rangers, keeping the local
// human's state for Local.
procedure RebuildHumans(Galaxy: TGalaxy; Local: TPlayer);
// CHANGE: ENHANCEMENT - Forgets every human and gives the local one a new THuman, as at
// startup. A load fills the local human's state into the THuman that is local; a client that
// loads the host's state (written with the host's human local) calls this first, so that
// nothing of its own human's state stays in the host's (ROADMAP.md, Phase 5).
procedure ResetHumans(Galaxy: TGalaxy);
// Ends the game for Human alone (THuman.Finished), as a quest script's EndGame does in
// multiplayer. The human leaves play: its ranger holds position, it counts as having pressed
// end turn, and aCommands.ExecuteCommand refuses its commands. It stays in Session.Humans.
procedure FinishHuman(Human: THuman; Reason: Integer);
// The human who issued Command, and its ranger; nil when the human is gone.
function ActorHuman(const Command: TPlayerCommand): THuman;
function Actor(const Command: TPlayerCommand): TPlayer;
type
  // CHANGE: ENHANCEMENT - What the new-game screen chose for a human who joins a networked game
  // for the first time (docs/network.md, Joining). Without Chosen only the preset counts, as
  // before; the race is the planet's (FindJoinPlanet looks for one of Race).
  TJoinCharacter = record
    Chosen: Boolean;
    // The race (TPlanet.RaceId, the screen's PlayerRace); -1: any.
    Race: Integer;
    // The character preset, 1-5.
    Preset: Integer;
    // The portrait (PortraitFaceId); -1: none.
    Face: Integer;
    // The two starting skills (BaseSkills indexes) and items (item types, t_FuelTanks ..).
    Skills: array[0..1] of Byte;
    Items: array[0..1] of Byte;
  end;
// A character with only Preset chosen, as the hot-seat and headless joins give.
function PresetCharacter(Preset: Integer): TJoinCharacter;
// Adds a new human whose ranger starts landed at Planet, as new-game setup starts the first
// one. CharacterPreset is the setup screen's choice (1-5).
function JoinHuman(Planet: TPlanet; const Name: WideString; CharacterPreset: Integer): THuman; overload;
// CHANGE: ENHANCEMENT - With the rest of the setup screen's choices, applied as a new game
// applies them: the portrait, the careers of the preset, the starting skills and items.
function JoinHuman(
    Planet: TPlanet;
    const Name: WideString;
    const Character: TJoinCharacter
): THuman; overload;
// CHANGE: ENHANCEMENT - The one friendly-fire rule (ROADMAP.md, Phase 4, item 8, and Phase 6).
// Whether Attacker may attack or damage Target: false when both are humans' rangers, they are
// different humans and friendly fire is off (Session.FriendlyFireEnabled); true otherwise. A
// missile or a tranclucator attacks for its owner ship. NPCs attack humans as always; the rule
// is about one human against another. With one human it is always true.
function CanHumanAttack(Attacker, Target: TObject): Boolean;
// Drops every attack that CanHumanAttack now refuses: each human's weapon and interceptor
// targets, its auto-battle target, its enemy and its follow-to-attack order (follow mode 1)
// on another human. SetSessionFlag calls it when friendly fire turns off.
procedure DropRefusedHumanAttacks;
// CHANGE: ENHANCEMENT - The end-turn barrier (ROADMAP.md, Phase 4, item 2, and Phase 6): a day
// runs only when every human who plays has pressed end turn.
// Whether Human holds the day: its ranger plays and it has not ended its turn. A finished
// human never holds it, nor does one whose ranger is in hyperspace, since a jump is travel
// that goes on until arrival, nor a disconnected one (THuman.Connected).
function HumanHoldsDay(Human: THuman): Boolean;
// Whether the day may start: no human holds it.
function AllHumansEndedTurn: Boolean;
// The first human, in Session.Humans order, who holds the day; nil when none does. This is
// the hot-seat order.
function NextHumanToEndTurn: THuman;
// Whether Human's travel goes on by itself for another day, as the star map continues the
// local human's travel (aGalaxy.ShouldContinuePlayerTravel): in hyperspace, or with a travel
// order it has not reached, without a fight or an interruption in its star this day.
function HumanTravelContinues(Human: THuman): Boolean;
// Whether Player's day in hyperspace needs the jump screen's step (aPlayerActions.HyperspaceStep).
function NeedsHyperspaceStep(Player: TPlayer): Boolean;
// A day has run (the player-star job): every human who plays holds the next one, except a
// human who continues until arrival while its travel goes on. Also marks the hyperspace
// steps that are due.
procedure StartDayRound;
type
  // Told before and after the local human changes (SetLocalHuman); the command log records it.
  TLocalHumanHook = procedure(Human: THuman; Before: Boolean);
var
  LocalHumanHook: TLocalHumanHook;
// CHANGE: ENHANCEMENT - Hot-seat: the screen passes to another human, who becomes the local
// one. The humans stay as they are; only whose screen this is changes.
procedure SetLocalHuman(Human: THuman);
type
  // CHANGE: ENHANCEMENT - Remote dialogue (ROADMAP.md, Phase 5; docs/network.md, Remote
  // dialogue): on a host, the turn thread asks a remote human something (a hail, a demand, an
  // offer) through the network session, which sends TalkRequest to that human's client, runs
  // the answer's commands as they come and returns on TalkDone. The human's talk fields
  // (THuman.TalkShip and the rest) are set; the answer is in its TalkResponse. Returns whether
  // the talk ran; False (the peer left, or did not answer in time) ends it as a talk the
  // screen could not show. TShip.OpenPlayerConversation calls it, inside the turn thread's
  // wait for the UI. A host sets it; the command log's replay sets its own, which answers
  // the talk from the log.
  TRemoteTalkHook = function(Human: THuman): Boolean;
var
  RemoteTalkHook: TRemoteTalkHook;
// CHANGE: ENHANCEMENT - Whether a dialogue can reach Human (docs/network.md, Remote dialogue):
// the local human, or, where a network session can ask remote humans (RemoteTalkHook), a
// connected human who plays on. The answer about a remote human is recorded
// (SimEvents.RemoteTalkAnswer). Without a session only the local human is asked, as before.
function CanAskHuman(Human: THuman): Boolean;
// A planet where a joining human can start: an inhabited coalition planet in a coalition star
// of a visible constellation that holds no human, in the star nearest the first human's ranger
// (the first in galaxy order without one); nil when there is none. The choice depends only on
// the galaxy, so runs repeat. CHANGE: ENHANCEMENT - With Race, a planet of that race when there
// is one (the ranger's race is its home planet's).
function FindJoinPlanet(Race: Integer = -1): TPlanet;
implementation
uses
  aConst,
  aMyFunction,
  aMissile,
  aTranclucator,
  aGalaxyStruct,
  aSession,
  SimEvents;

function THumanList.GetHuman(Index: Integer): THuman;
begin
  Result := THuman(inherited Items[Index]);
end;

function HumanOf(Ship: TObject): THuman;
var
  I: Integer;
begin
  if Ship <> nil then
    for I := 0 to Session.Humans.Count - 1 do
    begin
      Result := Session.Humans[I];
      if Result.Player = Ship then
        Exit;
    end;
  Result := nil;
end;

function IsHuman(Ship: TObject): Boolean;
begin
  Result := Ship is TPlayer;
end;

function StarHasHuman(Star: TStar; Excluded: TObject): Boolean;
var
  I: Integer;
  Player: TPlayer;
begin
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Player := Session.Humans[I].Player;
    if (Player <> nil) and (Player <> Excluded) and (Player.CurrentStar = Star) then
      Exit(True);
  end;
  Result := False;
end;

function StarHasHumanInSpace(Star: TStar): Boolean;
var
  I: Integer;
  Player: TPlayer;
begin
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Player := Session.Humans[I].Player;
    if (Player <> nil) and (Player.CurrentStar = Star) and Player.InNormalSpace then
      Exit(True);
  end;
  Result := False;
end;

function HasLivingHuman: Boolean;
var
  I: Integer;
  Player: TPlayer;
begin
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Player := Session.Humans[I].Player;
    if (Player <> nil) and (Player.GetHull.HullPoints > 0) then
      Exit(True);
  end;
  Result := False;
end;

function IsMultiplayer: Boolean;
begin
  Result := Session.Humans.Count > 1;
end;

function IsRuinsProxy(Station: TObject): Boolean;
begin
  Result := RuinsProxyOwner(Station) <> nil;
end;

function RuinsProxyOwner(Station: TObject): TPlayer;
var
  I: Integer;
  Ranger: TObject;
begin
  if (Station <> nil) and (Galaxy <> nil) and (Galaxy.Rangers <> nil) then
    for I := 0 to Galaxy.Rangers.Count - 1 do
    begin
      Ranger := TObject(Galaxy.Rangers[I]);
      if (Ranger is TPlayer) and (TPlayer(Ranger).RuinsProxy = Station) then
        Exit(TPlayer(Ranger));
    end;
  Result := nil;
end;

function IsFilmedStar(Star: TStar): Boolean;
var
  I: Integer;
begin
  for I := 0 to Session.Humans.Count - 1 do
    if Session.Humans[I].PlayerStar = Star then
      Exit(True);
  Result := False;
end;

procedure CollectFilmedStars(Stars: TList);
var
  I: Integer;
  Star: TStar;
begin
  Stars.Clear;
  for I := 0 to Galaxy.Stars.Count - 1 do
  begin
    Star := TStar(Galaxy.Stars[I]);
    if IsFilmedStar(Star) then
      Stars.Add(Star);
  end;
end;

function FilmHuman(Star: TStar): THuman;
  function IsIn(Human: THuman): Boolean;
  begin
    Result :=
        (Human.Player <> nil)
            and ((Human.PlayerStar = Star) or (Human.Player.CurrentStar = Star));
  end;
var
  I: Integer;
begin
  if (Session.Humans.IndexOf(LocalHuman) >= 0) and IsIn(LocalHuman) then
    Exit(LocalHuman);
  for I := 0 to Session.Humans.Count - 1 do
    if IsIn(Session.Humans[I]) then
      Exit(Session.Humans[I]);
  Result := nil;
end;

function FindHuman(Id: Integer): THuman;
var
  I: Integer;
begin
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Result := Session.Humans[I];
    if Result.Id = Id then
      Exit;
  end;
  Result := nil;
end;

function HostHuman: THuman;
begin
  if Session.Humans.Count > 0 then
    Result := Session.Humans[0]
  else
    Result := nil;
end;

function BoundHuman(Id: Integer): THuman;
begin
  Result := nil;
  if Id >= 0 then
    Result := FindHuman(Id);
  if (Result = nil) and (Session.Humans.Count > 0) then
    Result := Session.Humans[0];
end;

function ScriptPlayer: TPlayer;
begin
  if ScriptHuman <> nil then
    Result := ScriptHuman.Player
  else
    Result := nil;
end;

function DefaultScriptHuman: THuman;
begin
  Result := ScriptHuman;
  if Result = nil then
    Result := ActingHuman;
  if (Result = nil) and (Session.Humans.Count > 0) then
    Result := Session.Humans[0];
end;

function ContextHuman: THuman;
begin
  Result := ActingHuman;
  if Result = nil then
    Result := ScriptHuman;
  if Result = nil then
    Result := HostHuman;
end;

function AddHuman(Player: TPlayer): THuman;
begin
  Result := HumanOf(Player);
  if Result <> nil then
    Exit;
  if (Session.Humans.Count = 0) or (LocalHuman.Player = Player) then
    Result := LocalHuman
  else
    Result := THuman.Create;
  Result.Player := Player;
  Result.Id := Player.Id;
  if Result <> LocalHuman then
  begin
    Result.Connected := NewHumansConnected;
    Result.PlayerStar := Player.CurrentStar;
    // The original layout saves the local human's; the per-human save block (aHumanSave)
    // fills this one when a save holds it.
    Result.PlayerOldQuests := TList.Create;
  end;
  Session.Humans.Add(Result);
end;

procedure RemoveHuman(Player: TPlayer);
var
  Human: THuman;
begin
  // CHANGE: ENHANCEMENT - The local ranger leaves alone (ROADMAP.md, Phase 4, item 9);
  // SetPlayer(nil, ...) would forget every human.
  if (Player <> nil) and (LocalPlayer = Player) then
    ClearLocalPlayer(Galaxy);
  Human := HumanOf(Player);
  if Human = nil then
    Exit;
  // CHANGE: BUGFIX - A ship the human left with open is free for the others.
  Human.ReleaseShipScreen;
  Session.Humans.Remove(Human);
  Human.Player := nil;
  if Human <> LocalHuman then
    Human.Free;
end;

procedure RebuildHumans(Galaxy: TGalaxy; Local: TPlayer);
var
  I: Integer;
  Ranger: TObject;
begin
  for I := 0 to Session.Humans.Count - 1 do
    if Session.Humans[I] <> LocalHuman then
      Session.Humans[I].Free;
  Session.Humans.Clear;
  LocalHuman.Player := nil;
  // CHANGE: BUGFIX - The ship it had open is not in the galaxy that replaces this one.
  LocalHuman.EditedShip := nil;
  LocalHuman.ShipScreenShown := False;
  if Local = nil then
    Exit;
  AddHuman(Local);
  if Galaxy.Rangers <> nil then
    for I := 0 to Galaxy.Rangers.Count - 1 do
    begin
      Ranger := TObject(Galaxy.Rangers[I]);
      if Ranger is TPlayer then
        AddHuman(TPlayer(Ranger));
    end;
end;

procedure ResetHumans(Galaxy: TGalaxy);
var
  Old: THuman;
begin
  if Galaxy <> nil then
    SetPlayer(nil, Galaxy)
  else
    RebuildHumans(nil, nil);
  Old := LocalHuman;
  LocalHuman := THuman.Create;
  Old.Free;
end;

procedure THuman.ClearBubbles;
var
  Next, Entry: TMessagePlayer;
begin
  PersistentPlayerMessageLock.Enter;
  try
    Next := FirstPersistentPlayerMessage;
    while Next <> nil do
    begin
      Entry := Next;
      Next := Next.Next;
      Entry.Free;
    end;
    FirstPersistentPlayerMessage := nil;
    LastPersistentPlayerMessage := nil;
  finally
    PersistentPlayerMessageLock.Leave;
  end;
end;
function THuman.CountBubbles: Integer;
var
  Entry: TMessagePlayer;
  Count: Integer;
begin
  PersistentPlayerMessageLock.Enter;
  try
    Count := 0;
    Entry := FirstPersistentPlayerMessage;
    while Entry <> nil do
    begin
      Inc(Count);
      Entry := Entry.Next;
    end;
    Result := Count;
  finally
    PersistentPlayerMessageLock.Leave;
  end;
end;
function THuman.IsBubbleQueued(MessageEntry: TMessagePlayer; SkipLock: Boolean): Boolean;
var
  Entry: TMessagePlayer;
begin
  if not SkipLock then
    PersistentPlayerMessageLock.Enter;
  try
    Entry := FirstPersistentPlayerMessage;
    while Entry <> nil do
    begin
      if Entry = MessageEntry then
      begin
        Result := True;
        Exit;
      end;
      Entry := Entry.Next;
    end;
    Result := False;
  finally
    if not SkipLock then
      PersistentPlayerMessageLock.Leave;
  end;
end;
procedure THuman.RemoveBubble(MessageEntry: TMessagePlayer; SkipLock: Boolean);
begin
  if not SkipLock then
    PersistentPlayerMessageLock.Enter;
  try
    if MessageEntry.Prev <> nil then
      MessageEntry.Prev.Next := MessageEntry.Next;
    if MessageEntry.Next <> nil then
      MessageEntry.Next.Prev := MessageEntry.Prev;
    if LastPersistentPlayerMessage = MessageEntry then
      LastPersistentPlayerMessage := MessageEntry.Prev;
    if FirstPersistentPlayerMessage = MessageEntry then
      FirstPersistentPlayerMessage := MessageEntry.Next;
    MessageEntry.Free;
  finally
    if not SkipLock then
      PersistentPlayerMessageLock.Leave;
  end;
end;
function THuman.RemoveBubblesExceptKinds(
    Key: WideString;
    ExcludedKinds: TPlayerMessageKindSet;
    SkipLock: Boolean
): Boolean;
var
  MessageEntry: TMessagePlayer;
begin
  Result := False;
  if not SkipLock then
    PersistentPlayerMessageLock.Enter;
  try
    repeat
      MessageEntry := FindBubbleExceptKinds(Key, ExcludedKinds, True);
      if MessageEntry <> nil then
      begin
        RemoveBubble(MessageEntry, True);
        Result := True;
      end;
    until MessageEntry = nil;
  finally
    if not SkipLock then
      PersistentPlayerMessageLock.Leave;
  end;
end;
function THuman.FindBubbleByText(const Text: WideString; SkipLock: Boolean): TMessagePlayer;
var
  Entry: TMessagePlayer;
begin
  Result := nil;
  if not SkipLock then
    PersistentPlayerMessageLock.Enter;
  try
    Entry := FirstPersistentPlayerMessage;
    while Entry <> nil do
    begin
      if Entry.Text = Text then
      begin
        Result := Entry;
        Exit;
      end;
      Entry := Entry.Next;
    end;
  finally
    if not SkipLock then
      PersistentPlayerMessageLock.Leave;
  end;
end;
function THuman.FindBubbleByKey(const Key: WideString; SkipLock: Boolean): TMessagePlayer;
var
  Entry: TMessagePlayer;
begin
  Result := nil;
  if not SkipLock then
    PersistentPlayerMessageLock.Enter;
  try
    Entry := FirstPersistentPlayerMessage;
    while Entry <> nil do
    begin
      if Entry.Key = Key then
      begin
        Result := Entry;
        Exit;
      end;
      Entry := Entry.Next;
    end;
  finally
    if not SkipLock then
      PersistentPlayerMessageLock.Leave;
  end;
end;
procedure THuman.RemoveBubbleByKey(const Key: WideString);
var
  Entry: TMessagePlayer;
begin
  PersistentPlayerMessageLock.Enter;
  try
    Entry := FirstPersistentPlayerMessage;
    while Entry <> nil do
    begin
      if Entry.Key = Key then
      begin
        if Entry.Prev <> nil then
          Entry.Prev.Next := Entry.Next;
        if Entry.Next <> nil then
          Entry.Next.Prev := Entry.Prev;
        if LastPersistentPlayerMessage = Entry then
          LastPersistentPlayerMessage := Entry.Prev;
        if FirstPersistentPlayerMessage = Entry then
          FirstPersistentPlayerMessage := Entry.Next;
        Entry.Free;
        Exit;
      end;
      Entry := Entry.Next;
    end;
  finally
    PersistentPlayerMessageLock.Leave;
  end;
end;
procedure THuman.RemoveBubblePages(const Prefix: WideString; FirstPage: Integer);
var
  Entry, Next: TMessagePlayer;
  PrefixLength: Integer;
  Suffix: WideString;
begin
  PersistentPlayerMessageLock.Enter;
  try
    Entry := FirstPersistentPlayerMessage;
    while Entry <> nil do
    begin
      Next := Entry.Next;
      PrefixLength := Pos(Prefix, Entry.Key);
      if PrefixLength = 1 then
      begin
        PrefixLength := Length(Prefix);
        Suffix :=
            CopyWideStringUnchecked(Entry.Key, PrefixLength + 1, Length(Entry.Key) - PrefixLength);
        if IsIntegerTextW(Suffix) and (ExtractDigitsToIntW(Suffix) >= FirstPage) then
        begin
          if Entry.Prev <> nil then
            Entry.Prev.Next := Entry.Next;
          if Entry.Next <> nil then
            Entry.Next.Prev := Entry.Prev;
          if LastPersistentPlayerMessage = Entry then
            LastPersistentPlayerMessage := Entry.Prev;
          if FirstPersistentPlayerMessage = Entry then
            FirstPersistentPlayerMessage := Entry.Next;
          Entry.Free;
        end;
      end;
      Entry := Next;
    end;
  finally
    PersistentPlayerMessageLock.Leave;
  end;
end;
function THuman.FindBubbleExceptKinds(
    const Key: WideString;
    ExcludedKinds: TPlayerMessageKindSet;
    SkipLock: Boolean
): TMessagePlayer;
var
  MessageEntry: TMessagePlayer;
begin
  Result := nil;
  if not SkipLock then
    PersistentPlayerMessageLock.Enter;
  try
    MessageEntry := FirstPersistentPlayerMessage;
    while MessageEntry <> nil do
    begin
      if not (MessageEntry.Kind in ExcludedKinds)
          and ((Length(Key) = 0) or (Pos(Key, MessageEntry.Key) > 0)) then
      begin
        Result := MessageEntry;
        Exit;
      end;
      MessageEntry := MessageEntry.Next;
    end;
  finally
    if not SkipLock then
      PersistentPlayerMessageLock.Leave;
  end;
end;
function THuman.CreateBubble: TMessagePlayer;
var
  Entry: TMessagePlayer;
begin
  PersistentPlayerMessageLock.Enter;
  try
    Entry := TMessagePlayer.Create;
    if LastPersistentPlayerMessage <> nil then
      LastPersistentPlayerMessage.Next := Entry;
    Entry.Prev := LastPersistentPlayerMessage;
    Entry.Next := nil;
    LastPersistentPlayerMessage := Entry;
    if FirstPersistentPlayerMessage = nil then
      FirstPersistentPlayerMessage := Entry;
  finally
    PersistentPlayerMessageLock.Leave;
  end;
  Result := Entry;
end;
function THuman.AddOrUpdateBubble(
    Kind: Byte;
    Turn: Integer;
    const Text, Key: WideString
): TMessagePlayer;
var
  Entry: TMessagePlayer;
begin
  PersistentPlayerMessageLock.Enter;
  try
    if Key <> '' then
    begin
      Entry := FindBubbleByKey(Key, True);
      if Entry <> nil then
      begin
        if Entry.Kind <> Kind then
        begin
          Entry.WasRead := False;
          Entry.NotificationSoundPlayed := False;
        end;
        Entry.Kind := Kind;
        Entry.Turn := Turn;
        if Text <> '' then
          Entry.Text := Text;
        Result := Entry;
        Exit;
      end;
    end;
    Entry := FindBubbleByText(Text, True);
    if Entry <> nil then
    begin
      Result := Entry;
      Exit;
    end;
    Entry := TMessagePlayer.Create;
    if LastPersistentPlayerMessage <> nil then
      LastPersistentPlayerMessage.Next := Entry;
    Entry.Prev := LastPersistentPlayerMessage;
    Entry.Next := nil;
    LastPersistentPlayerMessage := Entry;
    if FirstPersistentPlayerMessage = nil then
      FirstPersistentPlayerMessage := Entry;
    Entry.Key := Key;
    Entry.Kind := Kind;
    Entry.Turn := Turn;
    Entry.Text := Text;
    Entry.WasRead := False;
    Entry.NotificationSoundPlayed := False;
    Result := Entry;
  finally
    PersistentPlayerMessageLock.Leave;
  end;
end;
procedure THuman.PruneExpiredBubbles;
var
  Next, Entry: TMessagePlayer;
begin
  PersistentPlayerMessageLock.Enter;
  try
    Next := FirstPersistentPlayerMessage;
    while Next <> nil do
    begin
      Entry := Next;
      Next := Next.Next;
      if Entry.WasRead and (Entry.Kind in [6]) and (Galaxy.CurrentTurn - Entry.Turn >= 7) then
        RemoveBubble(Entry, True)
      else if Galaxy.CurrentTurn - Entry.Turn
          >= PlayerMessagePresentations[Entry.Kind].LifetimeTurns then
        RemoveBubble(Entry, True)
      else if Entry.WasRead and (Entry.Kind in [0..2, 4, 5, 8]) then
        RemoveBubble(Entry, True)
      else if not Player.InNormalSpace and (Entry.Kind = 1) then
        RemoveBubble(Entry, True);
    end;
  finally
    PersistentPlayerMessageLock.Leave;
  end;
end;

procedure THuman.RecordCheat(const Name: WideString; Points: Integer);
begin
  Inc(CheatPoints, Points);
  if HasUsedCheat(Name) then
    Exit;
  SetLength(UsedCheats, Length(UsedCheats) + 1);
  UsedCheats[High(UsedCheats)] := Name;
end;

function THuman.HasUsedCheat(const Name: WideString): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(UsedCheats) do
    if UsedCheats[I] = Name then
      Exit(True);
  Result := False;
end;

function THuman.HasCheated: Boolean;
begin
  Result := (CheatPoints <> 0) or (Length(UsedCheats) > 0);
end;

procedure THuman.ClearCheats;
begin
  UsedCheats := nil;
  CheatPoints := 0;
end;

procedure FinishHuman(Human: THuman; Reason: Integer);
var
  SavedAbsoluteOrder: Byte;
begin
  if (Human = nil) or Human.Finished then
    Exit;
  Human.Finished := True;
  Human.FinishReason := Reason;
  Human.EndedTurn := True;
  Human.PlayerAutomaticControl := False;
  Human.PendingPlayerFollowTarget := nil;
  // In hyperspace it arrives first; there is no position to hold there.
  if (Human.Player = nil) or Human.Player.InHyperspace then
    Exit;
  SavedAbsoluteOrder := Human.Player.AbsoluteScriptOrder;
  Human.Player.AbsoluteScriptOrder := 0;
  Human.Player.OrderNone(False);
  Human.Player.AbsoluteScriptOrder := SavedAbsoluteOrder;
  Human.Player.QueuedTravelTarget := nil;
end;

constructor THuman.Create;
begin
  inherited Create;
  GovernmentDialogNames := TStringsEC.Create;
  FinishReason := -1;
  Connected := True;
end;

destructor THuman.Destroy;
begin
  if PersistentPlayerMessageLock <> nil then
    ClearBubbles;
  // As TGalaxy.LoadFromBuffer releases the local human's list.
  PlayerOldQuests.Free;
  FinalizePlayerHoldView(Self);
  GovernmentDialogNames.Free;
  ScriptDialogState.Free;
  inherited Destroy;
end;

procedure THuman.ReleaseShipScreen;
begin
  if EditedShip = nil then
    Exit;
  // OpenShipScreen lent the player's experience to the ship only when SavedShipExperience
  // was set (aHoldActions.CanUsePlayerExperience).
  if (SavedShipExperience >= 0) and (Player <> nil) and (EditedShip <> Player) then
  begin
    Player.FreeExperience := EditedShip.FreeExperience;
    EditedShip.FreeExperience := SavedShipExperience;
  end;
  SavedShipExperience := -1;
  if PlayerHoldShip = EditedShip then
    PlayerHoldShip := nil;
  EditedShip := nil;
  ShipScreenShown := False;
end;

function ActorHuman(const Command: TPlayerCommand): THuman;
begin
  Result := FindHuman(Integer(Command.Actor));
end;

function Actor(const Command: TPlayerCommand): TPlayer;
var
  Human: THuman;
begin
  Human := ActorHuman(Command);
  if Human = nil then
    Result := nil
  else
    Result := Human.Player;
end;

function PresetCharacter(Preset: Integer): TJoinCharacter;
begin
  Result := Default(TJoinCharacter);
  Result.Race := -1;
  Result.Preset := Preset;
  Result.Face := -1;
end;

function JoinHuman(Planet: TPlanet; const Name: WideString; CharacterPreset: Integer): THuman;
begin
  Result := JoinHuman(Planet, Name, PresetCharacter(CharacterPreset));
end;

function JoinHuman(Planet: TPlanet; const Name: WideString; const Character: TJoinCharacter): THuman;
var
  Player: TPlayer;
  Money, I: Integer;
begin
  Money := GalaxyDifficultyTuning[Galaxy.DifficultyLevels[1]].DifficultyValue18;
  Player := TPlayer.Create;
  if Character.Chosen and (Character.Face >= 0) then
    Player.PortraitFaceId := Character.Face;
  Player.InitializePlayerAtPlanet(Planet, Money, Character.Preset);
  // In the new game's order (fGameSettings): the careers, the skills, the items, the preset.
  if Character.Chosen then
  begin
    Player.ApplyPresetCareer(Character.Preset);
    for I := 0 to 1 do
      if Character.Skills[I] <= High(Player.BaseSkills) then
        Inc(Player.BaseSkills[Character.Skills[I]]);
    for I := 0 to 1 do
      Player.AddStartingItem(Character.Items[I]);
  end;
  Player.HomePlanet.ChangeRelationToRanger(Player, 100);
  Player.Name := Name;
  Player.ApplyCharacterPreset(Planet, Money, Character.Preset);
  if Player.RuinsProxy = nil then
    Player.CreateRuinsProxy;
  Galaxy.RefreshRangerWealthStats;
  Galaxy.RefreshRangerStrengthStats;
  Result := AddHuman(Player);
  Result.PlayerStar := Planet.CurrentStar;
  if Result.PlayerOldQuests = nil then
    Result.PlayerOldQuests := aMyFunction.TObjectList.Create;
end;

// The ship an attack comes from: a missile's or a tranclucator's owner, else Source.
function AttackingShip(Source: TObject): TObject;
begin
  Result := Source;
  if Result is TMissile then
    Result := TMissile(Result).OwnerShip
  else if Result is TTranclucator then
    Result := TTranclucator(Result).OwnerShip;
end;

function CanHumanAttack(Attacker, Target: TObject): Boolean;
begin
  if Session.FriendlyFireEnabled or not IsHuman(Target) then
    Exit(True);
  Attacker := AttackingShip(Attacker);
  Result := not IsHuman(Attacker) or (Attacker = Target);
end;

procedure DropRefusedHumanAttacks;
var
  I, J: Integer;
  Human: THuman;
  Player: TPlayer;
  Weapon: TWeapon;
begin
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Human := Session.Humans[I];
    Player := Human.Player;
    if Player = nil then
      Continue;
    for J := 1 to Player.WeaponCount do
    begin
      Weapon := Player.Weapons[J];
      if (Weapon <> nil) and not CanHumanAttack(Player, TObject(Weapon.Target)) then
        Weapon.Target := nil;
    end;
    if (Player.GetHull <> nil)
        and not CanHumanAttack(Player, TObject(Player.GetHull.InterceptorTarget)) then
      Player.GetHull.InterceptorTarget := nil;
    if not CanHumanAttack(Player, Human.PendingPlayerFollowTarget) then
      Human.PendingPlayerFollowTarget := nil;
    if not CanHumanAttack(Player, Player.EnemyShip) then
      Player.EnemyShip := nil;
    if (Player.Order = soFollowShip)
        and (Byte(Player.OrderStateData) = 1)
        and not CanHumanAttack(Player, Player.OrderTarget) then
      Player.OrderStateData := 0;
  end;
end;

function HumanHoldsDay(Human: THuman): Boolean;
begin
  // A disconnected human counts as having ended its turn; its ranger holds position.
  Result :=
      not Human.EndedTurn
          and not Human.Finished
          and Human.Connected
          and (Human.Player <> nil)
          and not Human.Player.InHyperspace;
end;

function AllHumansEndedTurn: Boolean;
begin
  Result := NextHumanToEndTurn = nil;
end;

function NextHumanToEndTurn: THuman;
var
  I: Integer;
begin
  for I := 0 to Session.Humans.Count - 1 do
    if HumanHoldsDay(Session.Humans[I]) then
      Exit(Session.Humans[I]);
  Result := nil;
end;

// The star map's test, for any human and without the tip it shows or the path it builds:
// travel goes on unless something in the day asks the human to look.
function HumanTravelContinues(Human: THuman): Boolean;
var
  P: TPlayer;
  Star: TStar;
begin
  P := Human.Player;
  if (P = nil) or Human.Finished then
    Exit(False);
  if P.InHyperspace then
    Exit(True);
  if not P.InNormalSpace then
    Exit(False);
  Star := Human.PlayerStar;
  if Star = nil then
    Exit(False);
  if Star.KeepFilmRunning then
    Exit(True);
  if Human.PlayerEquipmentBrokenThisTurn or Star.PlayerCombatOccurred or Star.InterruptLongTravel then
    Exit(False);
  if Human.PendingPlayerFollowTarget <> nil then
    Exit(P.GetHullIntegrityPercent >= 25);
  if Human.PlayerAutomaticControl then
    Exit(True);
  case P.Order of
    soMove: Result := PointDistanceSquared(P.Position, P.OrderDestination) > 19600;
    soLand, soJump, soJumpHole, soTeleport: Result := True;
    soFollowShip:
      Result :=
          (P.OrderTarget is TShip)
              and (PointDistanceSquared(P.Position, TShip(P.OrderTarget).Position) >= Sqr(P.Speed));
  else
    Result := False;
  end;
end;

function NeedsHyperspaceStep(Player: TPlayer): Boolean;
begin
  Result :=
      (Player <> nil)
          and Player.InHyperspace
          and (Player.Order in [soJump, soJumpHole, soTeleport])
          and not ((Player.Order = soJumpHole) and (Player.OrderStateData = -65536));
end;

procedure StartDayRound;
var
  I: Integer;
  Human: THuman;
begin
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Human := Session.Humans[I];
    Human.HyperspaceStepPending := NeedsHyperspaceStep(Human.Player);
    if Human.ContinueUntilArrival and not HumanTravelContinues(Human) then
      Human.ContinueUntilArrival := False;
    Human.EndedTurn := Human.Finished or Human.ContinueUntilArrival;
  end;
end;

procedure SetLocalHuman(Human: THuman);
begin
  if (Human = nil) or (Human = LocalHuman) then
    Exit;
  if Assigned(LocalHumanHook) then
    LocalHumanHook(Human, True);
  LocalHuman := Human;
  SetLocalRanger(Human.Player, Galaxy);
  if Assigned(LocalHumanHook) then
    LocalHumanHook(Human, False);
end;

function CanAskHuman(Human: THuman): Boolean;
begin
  if Human = nil then
    Exit(False);
  if Human = LocalHuman then
    Exit(True);
  if not Assigned(RemoteTalkHook) then
    Exit(False);
  Result :=
      RemoteTalkAnswer(Human.Connected and not Human.Finished and (Human.Player <> nil));
end;

function FindJoinPlanet(Race: Integer): TPlanet;
var
  I, J: Integer;
  Star: TStar;
  Planet: TPlanet;
  Origin: TStar;

  function JoinPlanetIn(Star: TStar): TPlanet;
  var
    K: Integer;
  begin
    if (Star.ControlFaction = sfCoalition)
        and ((Star.Constellation = nil) or Star.Constellation.Visible)
        and not StarHasHuman(Star) then
      for K := 0 to Star.Planets.Count - 1 do
      begin
        Result := TPlanet(Star.Planets[K]);
        if (Result.OwnerId <= Byte(oiGaal)) and ((Race < 0) or (Result.RaceId = Race)) then
          Exit;
      end;
    Result := nil;
  end;

begin
  Origin := nil;
  if (Session.Humans.Count > 0) and (Session.Humans[0].Player <> nil) then
    Origin := Session.Humans[0].Player.CurrentStar;
  if (Origin <> nil) and (Length(Origin.StarDistances) > 0) then
    for I := 0 to High(Origin.StarDistances) do
    begin
      Result := JoinPlanetIn(Origin.StarDistances[I].Star);
      if Result <> nil then
        Exit;
    end;
  for J := 0 to Galaxy.Stars.Count - 1 do
  begin
    Star := TStar(Galaxy.Stars[J]);
    Planet := JoinPlanetIn(Star);
    if Planet <> nil then
      Exit(Planet);
  end;
  if Race >= 0 then
    Exit(FindJoinPlanet(-1));
  Result := nil;
end;

initialization
  LocalHuman := THuman.Create;
  Session.Humans := THumanList.Create;
finalization
  Session.Humans.Free;
  Session.Humans := nil;
  LocalHuman.Free;
  LocalHuman := nil;
end.
