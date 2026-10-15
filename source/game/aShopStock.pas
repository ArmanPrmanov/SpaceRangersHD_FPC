{$EXCESSPRECISION OFF}
unit aShopStock;
{$R-}
{$Q-}
{$B-}
{$A8}

// CHANGE: CLEANUP - The equipment stock the player has open in a shop, moved out of
// fEquipmentShop. The screen adds its images in a subclass of TShopStockSlot and sets
// ShopSlotClass.
// CHANGE: BUGFIX - The stock belongs to the planet or station: its items stay in the
// location's EquipmentShop list. A human's shop grid (THuman.TemporaryShopSlots) is a view of
// that list, sorted and padded for the human's screen, and owns no item. Native moved the
// items into the grid while the shop was open, so a second human at the same location saw
// an empty shop, and one human's purchase rebuilt the grid the other's commands named slots
// in. Commands name an item by its id in the location's list (aShopActions); the slot only
// places it. When a location's stock changes, ShopStockChanged rebuilds the other humans'
// grids there and tells the local screen (SimEvents.NotifyShopStockChanged).
//
// Saves keep the original layout. While it is written (BeginShopStockSave), the first open
// grid at each location (the local human's first, then Session.Humans order) writes the
// items it shows, as native wrote its grid, and the location's list leaves them out. Other
// grids at the same location write their slots empty, and the per-human save block
// (aHumanSave, version 3) names their items by id. A load gives a grid's items back to its
// location (AdoptLoadedShopView), so saves made before this change load the same way.
interface
uses
  Classes,
  Types,
  EC_Buf,
  EC_Struct,
  aItem,
  aPlanet,
  aRuins,
  aGalaxy;
type
  TShopStockSlot = class(TObjectEx)
    GridPoint: TPoint;
    // The item shown in the slot, in the location's list; the slot does not own it.
    Item: TItem;
    constructor Create; virtual;
    destructor Destroy; override;
    // WithItem: whether the slot writes its item (its grid is the one that saves the
    // location's shown items); otherwise it is written as empty.
    procedure SaveToBuffer(Buffer: TBufEC; WithItem: Boolean = True);
    // A saved item is created and is the slot's until AdoptLoadedShopView gives it to the
    // location.
    procedure LoadFromBuffer(Buffer: TBufEC; Galaxy: TGalaxy);
  end;
  TShopStockSlotClass = class of TShopStockSlot;
var
  ShopSlotClass: TShopStockSlotClass = TShopStockSlot;
  // The screen widens the grid with the window, which adds empty slots.
  ShopGridRowCount: Integer = 4;
  // CHANGE: BUGFIX - The columns this machine's shop screen shows; the commands that build a
  // grid carry it, and the grid is padded to its human's (ShopColumnCount).
  ShopVisibleColumnCount: Integer = 6;
procedure TemporaryShopStockHook(Argument: Pointer);
// CHANGE: BUGFIX - The columns of Human's shop grid (THuman.ShopColumnCount), or this
// machine's screen's while the human's commands have set none. Human is a THuman; nil means
// the local human.
function ShopColumnCount(Human: TObject = nil): Integer;
// CHANGE: CLEANUP - Human, a THuman, is the human whose shop it is; nil means the local
// human. It is a TObject because this interface cannot use aHuman without a unit cycle.
// Opens the human's grid at the planet it is on or the station it is docked to. The
// location's list is sorted as native sorted the grid, and the grid shows it in that order.
procedure BuildTemporaryShopSlotGrid(Human: TObject = nil);
// Closes the human's grid. The stock stays where it is, at its location.
procedure RestoreTemporaryShopStock(Human: TObject = nil);
// Frees the human's grid; the items are the location's.
procedure ClearTemporaryShopSlotGrid(Human: TObject = nil);

// The equipment list of a shop location (a TPlanet or a TRuins), or nil.
function ShopStockOf(Location: TObject): TList;
// The location whose stock the human's open grid shows, or nil.
function ShopViewLocation(Human: TObject): TObject;
// Where the human's ranger can shop: the planet it is on or the station it is docked to.
function HumanShopLocation(Human: TObject): TObject;
// The item with that id in the location's stock, or nil.
function FindShopStockItem(Location: TObject; Id: Integer): TItem;
// The slot of the human's grid that shows Item, or nil.
function ShopViewSlotOf(Human: TObject; Item: TItem): TShopStockSlot;
// Rebuilds the human's open grid from its location's list as the list stands, without
// sorting it, padded as BuildTemporaryShopSlotGrid pads.
procedure RefreshShopView(Human: TObject);
// The stock at Location changed: every other human's grid there that no longer shows the
// list (Actor's is left to its caller) is rebuilt, and the local screen is told when the
// local human's was. Simulation code that adds or removes items while a grid may be open
// calls it; it does nothing when no grid is open there.
procedure ShopStockChanged(Location: TObject; Actor: TObject = nil);
// Takes Item out of Location's stock for Human: out of the list, out of the human's slot
// (which stays, empty, as native left it), and the other grids there are rebuilt.
procedure TakeShopStockItem(Human: TObject; Location: TObject; Item: TItem);
// Closes every grid at Location, which is being freed.
procedure DropShopViewsAt(Location: TObject);
// After a load: the human's grid belongs to where its ranger is, as native found it. The
// items the grid was saved with go back to that location's list, in front, in grid order;
// with no location they are freed with the grid. Player is the human's ranger when the load
// has not given the human it yet (the local one), else nil.
procedure AdoptLoadedShopView(Human: TObject; Player: TObject = nil);

// Bracket a galaxy save or a state hash; they nest. Inside, ShopItemSavedByView tells the
// location writers which items a grid writes instead, and ShopViewSavesItems which grids
// write them.
procedure BeginShopStockSave;
procedure EndShopStockSave;
function ShopItemSavedByView(Item: TObject): Boolean;
function ShopViewSavesItems(Human: TObject): Boolean;
implementation
uses
  SysUtils,
  aHuman,
  aConst,
  aPlayer,
  aSession,
  SimEvents;

var
  SaveDepth: Integer;
  // During a save: the grids that write their items, and those items.
  SaveOwners: TList;
  SaveItems: TList;

procedure TemporaryShopStockHook(Argument: Pointer);
begin
end;

function HumanArg(Human: TObject): THuman;
begin
  Result := THuman(Human);
  if Result = nil then
    Result := LocalHuman;
end;

// Every human, and the local one when it is not (yet) among them.
procedure CollectHumans(List: TList);
var
  I: Integer;
begin
  if Session.Humans <> nil then
    for I := 0 to Session.Humans.Count - 1 do
      List.Add(Session.Humans[I]);
  if (LocalHuman <> nil) and (List.IndexOf(LocalHuman) < 0) then
    List.Add(LocalHuman);
end;

function ShopColumnCount(Human: TObject): Integer;
var
  H: THuman;
begin
  H := HumanArg(Human);
  if (H <> nil) and (H.ShopColumnCount > 0) then
    Result := H.ShopColumnCount
  else
    Result := ShopVisibleColumnCount;
end;

function ShopStockOf(Location: TObject): TList;
begin
  if Location is TPlanet then
    Result := TPlanet(Location).EquipmentShop
  else if Location is TRuins then
    Result := TRuins(Location).EquipmentShop
  else
    Result := nil;
end;

function ShopViewLocation(Human: TObject): TObject;
var
  H: THuman;
begin
  H := HumanArg(Human);
  Result := nil;
  if (H = nil) or (H.TemporaryShopSlots = nil) then
    Exit;
  if H.TemporaryShopPlanet <> nil then
    Result := H.TemporaryShopPlanet
  else
    Result := H.TemporaryShopStation;
end;

function PlayerShopLocation(P: TPlayer): TObject;
begin
  Result := nil;
  if P = nil then
    Exit;
  if P.CurrentPlanet <> nil then
    Result := P.CurrentPlanet
  else if P.DockedTo is TRuins then
    Result := P.DockedTo;
end;

function HumanShopLocation(Human: TObject): TObject;
var
  H: THuman;
begin
  H := HumanArg(Human);
  if H = nil then
    Result := nil
  else
    Result := PlayerShopLocation(H.Player);
end;

function FindShopStockItem(Location: TObject; Id: Integer): TItem;
var
  List: TList;
  I: Integer;
begin
  Result := nil;
  List := ShopStockOf(Location);
  if List = nil then
    Exit;
  for I := 0 to List.Count - 1 do
    if TItem(List[I]).Id = Id then
      Exit(TItem(List[I]));
end;

function ShopViewSlotOf(Human: TObject; Item: TItem): TShopStockSlot;
var
  H: THuman;
  I: Integer;
begin
  H := HumanArg(Human);
  Result := nil;
  if (Item = nil) or (H = nil) or (H.TemporaryShopSlots = nil) then
    Exit;
  for I := 0 to H.TemporaryShopSlots.Count - 1 do
    if TShopStockSlot(H.TemporaryShopSlots[I]).Item = Item then
      Exit(TShopStockSlot(H.TemporaryShopSlots[I]));
end;

// Native's grid order: by item type, hulls to custom weapons ahead of the rest, then by cost.
function ShopItemOrder(Item: TItem): Integer;
begin
  if Item.ItemType in [t_Hull..t_CustomWeapon] then
    Result := Ord(Item.ItemType) - 75
  else
    Result := Ord(Item.ItemType);
end;

// Native's exchange sort of the grid, applied to the list: the same order, ties included.
procedure SortShopStock(List: TList);
var
  I, J: Integer;
  Item, Other: TItem;
begin
  for I := 0 to List.Count - 2 do
    for J := I + 1 to List.Count - 1 do
    begin
      Item := TItem(List[I]);
      Other := TItem(List[J]);
      if (ShopItemOrder(Item) > ShopItemOrder(Other))
          or ((ShopItemOrder(Item) = ShopItemOrder(Other)) and (Item.Cost > Other.Cost)) then
        List.Exchange(I, J);
    end;
end;

// A new grid for H showing List in order, padded to the human's columns as native padded it.
procedure FillShopView(H: THuman; List: TList);
var
  X, Y, EmptyCount, I: Integer;
  Slot: TShopStockSlot;
begin
  for I := 0 to List.Count - 1 do
  begin
    Slot := ShopSlotClass.Create;
    H.TemporaryShopSlots.Add(Slot);
    Slot.Item := TItem(List[I]);
  end;
  EmptyCount := 0;
  if H.TemporaryShopSlots.Count < ShopColumnCount(H) * ShopGridRowCount then
    EmptyCount := ShopColumnCount(H) * ShopGridRowCount - H.TemporaryShopSlots.Count
  else if H.TemporaryShopSlots.Count mod ShopGridRowCount <> 0 then
    EmptyCount := ShopGridRowCount - H.TemporaryShopSlots.Count mod ShopGridRowCount;
  for I := 1 to EmptyCount do
  begin
    Slot := ShopSlotClass.Create;
    Slot.Item := nil;
    H.TemporaryShopSlots.Add(Slot);
  end;
  EmptyCount := 0;
  for Y := 0 to ShopGridRowCount - 1 do
    for X := 0 to H.TemporaryShopSlots.Count div ShopGridRowCount - 1 do
    begin
      Slot := H.TemporaryShopSlots[EmptyCount];
      Slot.GridPoint := Classes.Point(X, Y);
      Inc(EmptyCount);
    end;
end;

procedure BuildTemporaryShopSlotGrid(Human: TObject);
var
  H: THuman;
  Location: TObject;
  List: TList;
begin
  H := HumanArg(Human);
  TemporaryShopStockHook(nil);
  ClearTemporaryShopSlotGrid(H);
  H.TemporaryShopSlots := TList.Create;
  Location := HumanShopLocation(H);
  if Location = nil then
    Exit;
  if Location is TPlanet then
    H.TemporaryShopPlanet := TPlanet(Location)
  else
    H.TemporaryShopStation := TRuins(Location);
  List := ShopStockOf(Location);
  SortShopStock(List);
  FillShopView(H, List);
  // Sorting may have moved items the other grids there show.
  ShopStockChanged(Location, H);
end;

procedure RestoreTemporaryShopStock(Human: TObject);
var
  H: THuman;
begin
  H := HumanArg(Human);
  if H.TemporaryShopSlots = nil then
    Exit;
  ClearTemporaryShopSlotGrid(H);
end;

procedure ClearTemporaryShopSlotGrid(Human: TObject);
var
  H: THuman;
  I, Count: Integer;
  Slot: TShopStockSlot;
begin
  H := HumanArg(Human);
  if H.TemporaryShopSlots <> nil then
  begin
    Count := H.TemporaryShopSlots.Count;
    for I := 0 to Count - 1 do
    begin
      Slot := H.TemporaryShopSlots[I];
      Slot.Item := nil;
      Slot.Free;
    end;
    H.TemporaryShopSlots.Clear;
    H.TemporaryShopSlots.Free;
    H.TemporaryShopSlots := nil;
    H.TemporaryShopPlanet := nil;
    H.TemporaryShopStation := nil;
  end;
end;

procedure RefreshShopView(Human: TObject);
var
  H: THuman;
  Location: TObject;
begin
  H := HumanArg(Human);
  Location := ShopViewLocation(H);
  if Location = nil then
    Exit;
  ClearTemporaryShopSlotGrid(H);
  H.TemporaryShopSlots := TList.Create;
  if Location is TPlanet then
    H.TemporaryShopPlanet := TPlanet(Location)
  else
    H.TemporaryShopStation := TRuins(Location);
  FillShopView(H, ShopStockOf(Location));
end;

// Whether the human's grid shows exactly its location's list, in order; empty slots (what
// the human bought) do not count.
function ShopViewMatchesStock(H: THuman; List: TList): Boolean;
var
  I, Index: Integer;
  Slot: TShopStockSlot;
begin
  Result := False;
  Index := 0;
  for I := 0 to H.TemporaryShopSlots.Count - 1 do
  begin
    Slot := H.TemporaryShopSlots[I];
    if Slot.Item = nil then
      Continue;
    if (Index >= List.Count) or (List[Index] <> Pointer(Slot.Item)) then
      Exit;
    Inc(Index);
  end;
  Result := Index = List.Count;
end;

procedure ShopStockChanged(Location: TObject; Actor: TObject);
var
  Humans: TList;
  I: Integer;
  H: THuman;
  List: TList;
  LocalChanged: Boolean;
begin
  List := ShopStockOf(Location);
  if List = nil then
    Exit;
  LocalChanged := False;
  Humans := TList.Create;
  try
    CollectHumans(Humans);
    for I := 0 to Humans.Count - 1 do
    begin
      H := THuman(Humans[I]);
      if (H = Actor) or (ShopViewLocation(H) <> Location) then
        Continue;
      if ShopViewMatchesStock(H, List) then
        Continue;
      RefreshShopView(H);
      if H = LocalHuman then
        LocalChanged := True;
    end;
  finally
    Humans.Free;
  end;
  if LocalChanged then
    NotifyShopStockChanged;
end;

procedure TakeShopStockItem(Human: TObject; Location: TObject; Item: TItem);
var
  List: TList;
  Slot: TShopStockSlot;
  Index: Integer;
begin
  List := ShopStockOf(Location);
  if List <> nil then
  begin
    Index := List.IndexOf(Item);
    if Index >= 0 then
      List.Delete(Index);
  end;
  Slot := ShopViewSlotOf(Human, Item);
  if Slot <> nil then
    Slot.Item := nil;
  ShopStockChanged(Location, HumanArg(Human));
end;

procedure DropShopViewsAt(Location: TObject);
var
  Humans: TList;
  I: Integer;
begin
  Humans := TList.Create;
  try
    CollectHumans(Humans);
    for I := 0 to Humans.Count - 1 do
      if ShopViewLocation(Humans[I]) = Location then
        ClearTemporaryShopSlotGrid(Humans[I]);
  finally
    Humans.Free;
  end;
end;

procedure AdoptLoadedShopView(Human: TObject; Player: TObject);
var
  H: THuman;
  Location: TObject;
  List: TList;
  I, Position: Integer;
  Slot: TShopStockSlot;
begin
  H := HumanArg(Human);
  if H.TemporaryShopSlots = nil then
    Exit;
  H.TemporaryShopPlanet := nil;
  H.TemporaryShopStation := nil;
  if Player <> nil then
    Location := PlayerShopLocation(TPlayer(Player))
  else
    Location := HumanShopLocation(H);
  if Location = nil then
  begin
    for I := 0 to H.TemporaryShopSlots.Count - 1 do
    begin
      Slot := H.TemporaryShopSlots[I];
      if Slot.Item <> nil then
        Slot.Item.Free;
      Slot.Item := nil;
    end;
    ClearTemporaryShopSlotGrid(H);
    Exit;
  end;
  if Location is TPlanet then
    H.TemporaryShopPlanet := TPlanet(Location)
  else
    H.TemporaryShopStation := TRuins(Location);
  List := ShopStockOf(Location);
  Position := 0;
  for I := 0 to H.TemporaryShopSlots.Count - 1 do
  begin
    Slot := H.TemporaryShopSlots[I];
    if (Slot.Item <> nil) and (List.IndexOf(Slot.Item) < 0) then
    begin
      List.Insert(Position, Slot.Item);
      Inc(Position);
    end;
  end;
end;

// The grid at its location that writes the items there, when no earlier grid does: only a
// grid at the place its ranger is, since a load gives the items to that place.
procedure AddSaveOwner(H: THuman);
var
  Location: TObject;
  List: TList;
  I: Integer;
  Slot: TShopStockSlot;
begin
  Location := ShopViewLocation(H);
  if (Location = nil) or (Location <> HumanShopLocation(H)) then
    Exit;
  for I := 0 to SaveOwners.Count - 1 do
    if ShopViewLocation(SaveOwners[I]) = Location then
      Exit;
  SaveOwners.Add(H);
  List := ShopStockOf(Location);
  for I := 0 to H.TemporaryShopSlots.Count - 1 do
  begin
    Slot := H.TemporaryShopSlots[I];
    if (Slot.Item <> nil) and (List.IndexOf(Slot.Item) >= 0) then
      SaveItems.Add(Slot.Item);
  end;
end;

procedure BeginShopStockSave;
var
  Humans: TList;
  I: Integer;
begin
  Inc(SaveDepth);
  if SaveDepth > 1 then
    Exit;
  SaveOwners := TList.Create;
  SaveItems := TList.Create;
  Humans := TList.Create;
  try
    if LocalHuman <> nil then
      Humans.Add(LocalHuman);
    CollectHumans(Humans);
    for I := 0 to Humans.Count - 1 do
      if Humans.IndexOf(Humans[I]) = I then
        AddSaveOwner(THuman(Humans[I]));
  finally
    Humans.Free;
  end;
end;

procedure EndShopStockSave;
begin
  Dec(SaveDepth);
  if SaveDepth > 0 then
    Exit;
  SaveDepth := 0;
  FreeAndNil(SaveOwners);
  FreeAndNil(SaveItems);
end;

function ShopItemSavedByView(Item: TObject): Boolean;
begin
  Result := (SaveItems <> nil) and (SaveItems.IndexOf(Item) >= 0);
end;

function ShopViewSavesItems(Human: TObject): Boolean;
begin
  if SaveOwners = nil then
    Result := True
  else
    Result := SaveOwners.IndexOf(HumanArg(Human)) >= 0;
end;

constructor TShopStockSlot.Create;
begin
  inherited Create;
end;

destructor TShopStockSlot.Destroy;
begin
  Item := nil;
  inherited Destroy;
end;

procedure TShopStockSlot.SaveToBuffer(Buffer: TBufEC; WithItem: Boolean);
var
  Target: TObject;
begin
  Buffer.AddAnsiChar(AnsiChar(GridPoint.X));
  Buffer.AddAnsiChar(AnsiChar(GridPoint.Y));
  if (Item = nil) or not WithItem or ((SaveItems <> nil) and not ShopItemSavedByView(Item)) then
    Buffer.AddAnsiChar(#0)
  else
  begin
    Buffer.AddAnsiChar(#1);
    Buffer.AddAnsiChar(AnsiChar(Item.ItemType));
    // CHANGE: BUGFIX - Write shop weapons without a target, but leave the weapon unchanged.
    if Item is TWeapon then
    begin
      Target := (Item as TWeapon).Target;
      (Item as TWeapon).Target := nil;
      try
        Item.SaveToBuffer(Buffer);
      finally
        (Item as TWeapon).Target := Target;
      end;
    end
    else
      Item.SaveToBuffer(Buffer);
  end;
end;

procedure TShopStockSlot.LoadFromBuffer(Buffer: TBufEC; Galaxy: TGalaxy);
begin
  GridPoint.X := Buffer.GetByte;
  GridPoint.Y := Buffer.GetByte;
  if Buffer.GetByte = 1 then
  begin
    Item := TObject(CreateItemByType(MigrateSavedItemType(Buffer.GetByte))) as TEquipment;
    Item.LoadFromBuffer(Buffer, Galaxy);
  end;
end;
end.
