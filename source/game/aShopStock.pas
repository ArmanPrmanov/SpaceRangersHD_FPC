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
  ShopVisibleColumnCount: Integer = 6;
procedure TemporaryShopStockHook(Argument: Pointer);
procedure BuildTemporaryShopSlotGrid;
procedure RestoreTemporaryShopStock;
procedure ClearTemporaryShopSlotGrid;
implementation
uses
  aHuman,
  aConst,
  aPlayer;

procedure TemporaryShopStockHook(Argument: Pointer);
begin
end;

procedure BuildTemporaryShopSlotGrid;
var
  X, Y, EmptyCount, I, J: Integer;
  Slot, Other: TShopStockSlot;
  Item: TItem;
  ItemOrder, OtherOrder: Integer;
  Station: TRuins;
begin
  TemporaryShopStockHook(nil);
  ClearTemporaryShopSlotGrid;
  LocalHuman.TemporaryShopSlots := TList.Create;
  if GetPlayer.CurrentPlanet <> nil then
  begin
    for I := 0 to GetPlayer.CurrentPlanet.EquipmentShop.Count - 1 do
    begin
      Item := TItem(GetPlayer.CurrentPlanet.EquipmentShop[I]);
      Slot := ShopSlotClass.Create;
      LocalHuman.TemporaryShopSlots.Add(Slot);
      Slot.Item := Item;
    end;
    GetPlayer.CurrentPlanet.EquipmentShop.Clear;
    LocalHuman.TemporaryShopPlanet := GetPlayer.CurrentPlanet;
  end
  else
  begin
    if GetPlayer.DockedTo = nil then
      Exit;
    if not (GetPlayer.DockedTo is TRuins) then
      Exit;
    Station := GetPlayer.DockedTo as TRuins;
    for I := 0 to Station.EquipmentShop.Count - 1 do
    begin
      Item := TItem(Station.EquipmentShop[I]);
      Slot := ShopSlotClass.Create;
      LocalHuman.TemporaryShopSlots.Add(Slot);
      Slot.Item := Item;
    end;
    Station.EquipmentShop.Clear;
    LocalHuman.TemporaryShopStation := Station;
  end;
  for I := 0 to LocalHuman.TemporaryShopSlots.Count - 2 do
  begin
    Slot := LocalHuman.TemporaryShopSlots[I];
    if Slot.Item = nil then
      Continue;
    for J := I + 1 to LocalHuman.TemporaryShopSlots.Count - 1 do
    begin
      Other := LocalHuman.TemporaryShopSlots[J];
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
  if LocalHuman.TemporaryShopSlots.Count < ShopVisibleColumnCount * ShopGridRowCount then
    EmptyCount := ShopVisibleColumnCount * ShopGridRowCount - LocalHuman.TemporaryShopSlots.Count
  else if LocalHuman.TemporaryShopSlots.Count mod ShopGridRowCount <> 0 then
    EmptyCount := ShopGridRowCount - LocalHuman.TemporaryShopSlots.Count mod ShopGridRowCount;
  for I := 1 to EmptyCount do
  begin
    Slot := ShopSlotClass.Create;
    Slot.Item := nil;
    LocalHuman.TemporaryShopSlots.Add(Slot);
  end;
  EmptyCount := 0;
  for Y := 0 to ShopGridRowCount - 1 do
    for X := 0 to LocalHuman.TemporaryShopSlots.Count div ShopGridRowCount - 1 do
    begin
      Slot := LocalHuman.TemporaryShopSlots[EmptyCount];
      Slot.GridPoint := Classes.Point(X, Y);
      Inc(EmptyCount);
    end;
end;

procedure RestoreTemporaryShopStock;
var
  I, Count: Integer;
  Slot: TShopStockSlot;
begin
  if LocalHuman.TemporaryShopSlots = nil then
    Exit;
  if LocalHuman.TemporaryShopPlanet <> nil then
  begin
    Count := LocalHuman.TemporaryShopSlots.Count;
    for I := 0 to Count - 1 do
    begin
      Slot := LocalHuman.TemporaryShopSlots[I];
      if Slot.Item <> nil then
        LocalHuman.TemporaryShopPlanet.EquipmentShop.Add(Slot.Item);
      Slot.Item := nil;
    end;
  end
  else if LocalHuman.TemporaryShopStation <> nil then
  begin
    Count := LocalHuman.TemporaryShopSlots.Count;
    for I := 0 to Count - 1 do
    begin
      Slot := LocalHuman.TemporaryShopSlots[I];
      if Slot.Item <> nil then
        LocalHuman.TemporaryShopStation.EquipmentShop.Add(Slot.Item);
      Slot.Item := nil;
    end;
  end;
  ClearTemporaryShopSlotGrid;
end;

procedure ClearTemporaryShopSlotGrid;
var
  I, Count: Integer;
  Slot: TShopStockSlot;
begin
  if LocalHuman.TemporaryShopSlots <> nil then
  begin
    Count := LocalHuman.TemporaryShopSlots.Count;
    for I := 0 to Count - 1 do
    begin
      Slot := LocalHuman.TemporaryShopSlots[I];
      Slot.Free;
    end;
    LocalHuman.TemporaryShopSlots.Clear;
    LocalHuman.TemporaryShopSlots.Free;
    LocalHuman.TemporaryShopSlots := nil;
    LocalHuman.TemporaryShopPlanet := nil;
    LocalHuman.TemporaryShopStation := nil;
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
