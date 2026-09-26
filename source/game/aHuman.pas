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
  Globals,
  aGalaxy,
  aHold,
  aItem,
  aPlanet,
  aPlayer,
  aRuins,
  aShip;
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
  end;
  // The humans in join order. Every TPlayer in the galaxy is in it, and nothing else is.
  THumanList = class(TList)
  private
    function GetHuman(Index: Integer): THuman; inline;
  public
    property Items[Index: Integer]: THuman read GetHuman; default;
  end;
var
  // The human at this machine: whose screen this is. LocalPlayer is its ranger.
  LocalHuman: THuman;
// The human whose ranger is Ship, or nil when Ship is not a human's ranger.
function HumanOf(Ship: TObject): THuman;
// Whether Ship is a human's ranger. Every TPlayer is.
function IsHuman(Ship: TObject): Boolean; inline;
// Whether a human's ranger is in Star, in normal space, docked or landed.
function StarHasHuman(Star: TStar): Boolean;
// The human with this id, or nil.
function FindHuman(Id: Integer): THuman;
// Makes Player a human. The first human is the local one.
function AddHuman(Player: TPlayer): THuman;
// Forgets Player's human, as when its ranger is destroyed. The local human's state is kept.
procedure RemoveHuman(Player: TPlayer);
// Rebuilds the list from the TPlayer instances in Galaxy.Rangers, keeping the local
// human's state for Local.
procedure RebuildHumans(Galaxy: TGalaxy; Local: TPlayer);
implementation
uses
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

function StarHasHuman(Star: TStar): Boolean;
var
  I: Integer;
  Player: TPlayer;
begin
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Player := Session.Humans[I].Player;
    if (Player <> nil) and (Player.CurrentStar = Star) then
      Exit(True);
  end;
  Result := False;
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

initialization
  LocalHuman := THuman.Create;
  Session.Humans := THumanList.Create;
finalization
  Session.Humans.Free;
  Session.Humans := nil;
  LocalHuman.Free;
  LocalHuman := nil;
end.
