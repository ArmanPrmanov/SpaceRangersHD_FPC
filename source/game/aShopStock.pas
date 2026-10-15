{$EXCESSPRECISION OFF}
unit aShopStock;
{$R-}
{$Q-}
{$B-}
{$A8}

// CHANGE: CLEANUP - The equipment stock the player has open in a shop, moved out of
// fEquipmentShop. While the shop is open, its items live in a slot grid
// (LocalHuman.TemporaryShopSlots) instead of the planet's or station's EquipmentShop list,
// and the galaxy save writes the grid. The screen adds its images in a subclass of
// TShopStockSlot and sets ShopSlotClass.
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
    Item: TItem;
    constructor Create; virtual;
    destructor Destroy; override;
    procedure SaveToBuffer(Buffer: TBufEC);
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
procedure BuildTemporaryShopSlotGrid(Human: TObject = nil);
procedure RestoreTemporaryShopStock(Human: TObject = nil);
procedure ClearTemporaryShopSlotGrid(Human: TObject = nil);
implementation
uses
  aHuman,
  aConst,
  aPlayer;

procedure TemporaryShopStockHook(Argument: Pointer);
begin
end;

function ShopColumnCount(Human: TObject): Integer;
var
  H: THuman;
begin
  H := THuman(Human);
  if H = nil then
    H := LocalHuman;
  if (H <> nil) and (H.ShopColumnCount > 0) then
    Result := H.ShopColumnCount
  else
    Result := ShopVisibleColumnCount;
end;

procedure BuildTemporaryShopSlotGrid(Human: TObject);
var
  H: THuman;
  Player: TPlayer;
  X, Y, EmptyCount, I, J: Integer;
  Slot, Other: TShopStockSlot;
  Item: TItem;
  ItemOrder, OtherOrder: Integer;
  Station: TRuins;
begin
  H := THuman(Human);
  if H = nil then
    H := LocalHuman;
  Player := H.Player;
  TemporaryShopStockHook(nil);
  ClearTemporaryShopSlotGrid(H);
  H.TemporaryShopSlots := TList.Create;
  if Player.CurrentPlanet <> nil then
  begin
    for I := 0 to Player.CurrentPlanet.EquipmentShop.Count - 1 do
    begin
      Item := TItem(Player.CurrentPlanet.EquipmentShop[I]);
      Slot := ShopSlotClass.Create;
      H.TemporaryShopSlots.Add(Slot);
      Slot.Item := Item;
    end;
    Player.CurrentPlanet.EquipmentShop.Clear;
    H.TemporaryShopPlanet := Player.CurrentPlanet;
  end
  else
  begin
    if Player.DockedTo = nil then
      Exit;
    if not (Player.DockedTo is TRuins) then
      Exit;
    Station := Player.DockedTo as TRuins;
    for I := 0 to Station.EquipmentShop.Count - 1 do
    begin
      Item := TItem(Station.EquipmentShop[I]);
      Slot := ShopSlotClass.Create;
      H.TemporaryShopSlots.Add(Slot);
      Slot.Item := Item;
    end;
    Station.EquipmentShop.Clear;
    H.TemporaryShopStation := Station;
  end;
  for I := 0 to H.TemporaryShopSlots.Count - 2 do
  begin
    Slot := H.TemporaryShopSlots[I];
    if Slot.Item = nil then
      Continue;
    for J := I + 1 to H.TemporaryShopSlots.Count - 1 do
    begin
      Other := H.TemporaryShopSlots[J];
      if Other.Item = nil then
        Continue;
      if Slot.Item.ItemType in [t_Hull..t_CustomWeapon] then
        ItemOrder := Ord(Slot.Item.ItemType) - 75
      else
        ItemOrder := Ord(Slot.Item.ItemType);
      if Other.Item.ItemType in [t_Hull..t_CustomWeapon] then
        OtherOrder := Ord(Other.Item.ItemType) - 75
      else
        OtherOrder := Ord(Other.Item.ItemType);
      if (ItemOrder > OtherOrder)
          or ((ItemOrder = OtherOrder) and (Slot.Item.Cost > Other.Item.Cost)) then
      begin
        Item := Slot.Item;
        Slot.Item := Other.Item;
        Other.Item := Item;
      end;
    end;
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

procedure RestoreTemporaryShopStock(Human: TObject);
var
  H: THuman;
  I, Count: Integer;
  Slot: TShopStockSlot;
begin
  H := THuman(Human);
  if H = nil then
    H := LocalHuman;
  if H.TemporaryShopSlots = nil then
    Exit;
  if H.TemporaryShopPlanet <> nil then
  begin
    Count := H.TemporaryShopSlots.Count;
    for I := 0 to Count - 1 do
    begin
      Slot := H.TemporaryShopSlots[I];
      if Slot.Item <> nil then
        H.TemporaryShopPlanet.EquipmentShop.Add(Slot.Item);
      Slot.Item := nil;
    end;
  end
  else if H.TemporaryShopStation <> nil then
  begin
    Count := H.TemporaryShopSlots.Count;
    for I := 0 to Count - 1 do
    begin
      Slot := H.TemporaryShopSlots[I];
      if Slot.Item <> nil then
        H.TemporaryShopStation.EquipmentShop.Add(Slot.Item);
      Slot.Item := nil;
    end;
  end;
  ClearTemporaryShopSlotGrid(H);
end;

procedure ClearTemporaryShopSlotGrid(Human: TObject);
var
  H: THuman;
  I, Count: Integer;
  Slot: TShopStockSlot;
begin
  H := THuman(Human);
  if H = nil then
    H := LocalHuman;
  if H.TemporaryShopSlots <> nil then
  begin
    Count := H.TemporaryShopSlots.Count;
    for I := 0 to Count - 1 do
    begin
      Slot := H.TemporaryShopSlots[I];
      Slot.Free;
    end;
    H.TemporaryShopSlots.Clear;
    H.TemporaryShopSlots.Free;
    H.TemporaryShopSlots := nil;
    H.TemporaryShopPlanet := nil;
    H.TemporaryShopStation := nil;
  end;
end;

constructor TShopStockSlot.Create;
begin
  inherited Create;
end;

destructor TShopStockSlot.Destroy;
begin
  if Item <> nil then
  begin
    Item.Free;
    Item := nil;
  end;
  inherited Destroy;
end;

procedure TShopStockSlot.SaveToBuffer(Buffer: TBufEC);
var
  Target: TObject;
begin
  Buffer.AddAnsiChar(AnsiChar(GridPoint.X));
  Buffer.AddAnsiChar(AnsiChar(GridPoint.Y));
  if Item = nil then
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
