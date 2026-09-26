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
  Globals,
  aGalaxy,
  aHold,
  aItem,
  aPlanet,
  aPlayer,
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
  // The human at this machine: whose screen this is. LocalPlayer is its ranger.
  LocalHuman: THuman;
// The human whose ranger is Ship, or nil when Ship is not a human's ranger.
function HumanOf(Ship: TObject): THuman;
// Whether Ship is a human's ranger. Every TPlayer is.
function IsHuman(Ship: TObject): Boolean; inline;
// Whether a human's ranger is in Star, in normal space, docked or landed. Excluded, when
// given, does not count: a human who overhears two others talking is not one of them.
function StarHasHuman(Star: TStar; Excluded: TObject = nil): Boolean;
// Whether Star is some human's PlayerStar. Those stars run their day in the player-star
// job, each with a film, and the galaxy job leaves them out (ROADMAP.md, Phase 4).
function IsFilmedStar(Star: TStar): Boolean;
// The filmed stars, in galaxy order.
procedure CollectFilmedStars(Stars: TList);
// The human with this id, or nil.
function FindHuman(Id: Integer): THuman;
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
  aSession,
  EC_Str;

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
    Result.PlayerStar := Player.CurrentStar;
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

destructor THuman.Destroy;
begin
  if PersistentPlayerMessageLock <> nil then
    ClearBubbles;
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
