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
    // Whether the human has pressed end turn for the coming day.
    EndedTurn: Boolean;
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
// The human a script is bound to (TScript.HumanId), or the first human when it has left or
// the script is not bound; nil when there is none.
function BoundHuman(Id: Integer): THuman;
// ScriptHuman's ranger; nil when there is no script human or its ranger is gone.
function ScriptPlayer: TPlayer; inline;
// The human script code that belongs to no script runs for: ScriptHuman when it runs inside
// other script code, else ActingHuman, else the first human; nil when there is none.
function DefaultScriptHuman: THuman;
// Makes Player a human. The first human is the local one.
function AddHuman(Player: TPlayer): THuman;
// Forgets Player's human, as when its ranger is destroyed. The local human's state is kept.
procedure RemoveHuman(Player: TPlayer);
// Rebuilds the list from the TPlayer instances in Galaxy.Rangers, keeping the local
// human's state for Local.
procedure RebuildHumans(Galaxy: TGalaxy; Local: TPlayer);
// The human who issued Command, and its ranger; nil when the human is gone.
function ActorHuman(const Command: TPlayerCommand): THuman;
function Actor(const Command: TPlayerCommand): TPlayer;
// Adds a new human whose ranger starts landed at Planet, as new-game setup starts the first
// one. CharacterPreset is the setup screen's choice (1-5).
function JoinHuman(Planet: TPlanet; const Name: WideString; CharacterPreset: Integer): THuman;
implementation
uses
  aConst,
  aMyFunction,
  aSession;

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
  Human := HumanOf(Player);
  if Human = nil then
    Exit;
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

constructor THuman.Create;
begin
  inherited Create;
  GovernmentDialogNames := TStringsEC.Create;
end;

destructor THuman.Destroy;
begin
  if PersistentPlayerMessageLock <> nil then
    ClearBubbles;
  // As TGalaxy.LoadFromBuffer releases the local human's list.
  PlayerOldQuests.Free;
  FinalizePlayerHoldView(Self);
  GovernmentDialogNames.Free;
  inherited Destroy;
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

function JoinHuman(Planet: TPlanet; const Name: WideString; CharacterPreset: Integer): THuman;
var
  Player: TPlayer;
  Money: Integer;
begin
  Money := GalaxyDifficultyTuning[Galaxy.DifficultyLevels[1]].DifficultyValue18;
  Player := TPlayer.Create;
  Player.InitializePlayerAtPlanet(Planet, Money, CharacterPreset);
  Player.HomePlanet.ChangeRelationToRanger(Player, 100);
  Player.Name := Name;
  Player.ApplyCharacterPreset(Planet, Money, CharacterPreset);
  if Player.RuinsProxy = nil then
    Player.CreateRuinsProxy;
  Galaxy.RefreshRangerWealthStats;
  Galaxy.RefreshRangerStrengthStats;
  Result := AddHuman(Player);
  Result.PlayerStar := Planet.CurrentStar;
  if Result.PlayerOldQuests = nil then
    Result.PlayerOldQuests := aMyFunction.TObjectList.Create;
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
