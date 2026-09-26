{$EXCESSPRECISION OFF}
unit aHold;
{$R-}
{$Q-}
{$B-}
{$A8}

// CHANGE: CLEANUP - The order in which the ship screen lists the player's hold, moved out of
// fShip2. The save writes it, and satellites are numbered by it. Each human has one: the
// list is Human.PlayerHoldEntries, for the ship Human.PlayerHoldShip (or the human's ranger
// when that is nil). Human is a THuman; it is a TObject because this interface cannot use
// aHuman without a unit cycle.
interface
uses
  aItem;
type
  {$Z4}
  TPlayerHoldKind = (phkEmpty = 0, phkGoods = 1, phkEquipment = 2, phkArtefact = 3);
  {$Z4}
  TPlayerHoldSort = (phsType = 0, phsSize = 1, phsPrice = 2);
  TPlayerHoldUnit = class(TObject)
    Kind: TPlayerHoldKind;
    GoodsIndex: Byte;
    Gap9: array[0..2] of Byte;
    ItemId: Integer;
    DisplayOrder: Integer;
    Item: TItem;
    Retained: Boolean;
    Gap19: array[0..2] of Byte;
  end;
procedure InitializePlayerHoldView(Human: TObject);
procedure FinalizePlayerHoldView(Human: TObject);
procedure RefreshPlayerHoldView(Human: TObject; IncludeFilteredItems: Boolean);
procedure RemoveEmptyPlayerHoldSlot(Human: TObject; Index: Integer);
procedure ClearPlayerHoldEntries(Human: TObject);
procedure RemoveEmptyPlayerHoldSlots(Human: TObject);
function IsPlayerHoldSlotEmpty(Human: TObject; Index: Integer): Boolean;
function ComparePlayerHoldEntries(
    Human: TObject;
    Left: TPlayerHoldUnit;
    Right: TPlayerHoldUnit;
    Sort: TPlayerHoldSort
): Integer;
procedure SortPlayerHoldEntries(Human: TObject; Sort: TPlayerHoldSort);
procedure RestorePlayerHoldDisplayOrder(Human: TObject);
function FindPlayerHoldIndexByOrder(Human: TObject; DisplayOrder: Integer): Integer;
function FindFreePlayerHoldOrder(Human: TObject): Integer;
implementation
uses
  Classes,
  EC_Str,
  aCalc,
  aConst,
  aHuman,
  aPlayer,
  aShip;

procedure InitializePlayerHoldView(Human: TObject);
var
  H: THuman;
begin
  H := THuman(Human);
  FinalizePlayerHoldView(Human);
  H.PlayerHoldEntries := TList.Create;
end;

procedure FinalizePlayerHoldView(Human: TObject);
var
  H: THuman;
begin
  H := THuman(Human);
  if H.PlayerHoldEntries <> nil then
  begin
    ClearPlayerHoldEntries(Human);
    H.PlayerHoldEntries.Free;
    H.PlayerHoldEntries := nil;
  end;
end;

procedure RefreshPlayerHoldView(Human: TObject; IncludeFilteredItems: Boolean);
var
  H: THuman;
  Ship: TShip;
  Goods: Byte;
  Entry, Other: TPlayerHoldUnit;
  I, J, Order: Integer;
  Item: TEquipment;
begin
  H := THuman(Human);
  if H.PlayerHoldEntries = nil then
    InitializePlayerHoldView(Human);
  if H.PlayerHoldShip <> nil then
    Ship := H.PlayerHoldShip
  else
    Ship := H.Player;
  for I := 0 to H.PlayerHoldEntries.Count - 1 do
  begin
    Entry := H.PlayerHoldEntries[I];
    Entry.Retained := Entry.Kind = phkEmpty;
  end;
  for Goods := 0 to 7 do
  begin
    if not IncludeFilteredItems then
      if not H.Player.CanAccessHoldGoods(Goods) then
        Continue;
    if Ship.CargoGoods[Goods].Count > 0 then
    begin
      I := 0;
      while I < H.PlayerHoldEntries.Count do
      begin
        Entry := H.PlayerHoldEntries[I];
        if not Entry.Retained and (Entry.Kind = phkGoods) and (Entry.GoodsIndex = Goods) then
        begin
          Entry.Retained := True;
          Break;
        end;
        Inc(I);
      end;
      if I >= H.PlayerHoldEntries.Count then
      begin
        Entry := TPlayerHoldUnit.Create;
        H.PlayerHoldEntries.Insert(0, Entry);
        Entry.Kind := phkGoods;
        Entry.GoodsIndex := Goods;
        Entry.Retained := True;
      end;
    end;
  end;
  for J := 0 to Ship.Inventory.Count - 1 do
  begin
    Item := TEquipment(Ship.Inventory[J]);
    if (Item.EquippedFlag = 0) and (Ship.GetHull <> Item) then
    begin
      if IncludeFilteredItems or H.Player.CanAccessStoredItem(Item) then
      begin
        I := 0;
        while I < H.PlayerHoldEntries.Count do
        begin
          Entry := H.PlayerHoldEntries[I];
          if not Entry.Retained and (Entry.Kind = phkEquipment) and (Item.Id = Entry.ItemId) then
          begin
            Entry.Retained := True;
            Entry.Item := Item;
            Break;
          end;
          Inc(I);
        end;
        if I >= H.PlayerHoldEntries.Count then
        begin
          Entry := TPlayerHoldUnit.Create;
          H.PlayerHoldEntries.Add(Entry);
          Entry.Kind := phkEquipment;
          Entry.ItemId := Item.Id;
          Entry.Item := Item;
          Entry.Retained := True;
        end;
      end;
    end;
  end;
  for J := 0 to Ship.Artefacts.Count - 1 do
  begin
    Item := TEquipment(Ship.Artefacts[J]);
    if Item.EquippedFlag = 0 then
    begin
      if IncludeFilteredItems or H.Player.CanAccessStoredItem(Item) then
      begin
        I := 0;
        while I < H.PlayerHoldEntries.Count do
        begin
          Entry := H.PlayerHoldEntries[I];
          if not Entry.Retained and (Entry.Kind = phkArtefact) and (Item.Id = Entry.ItemId) then
          begin
            Entry.Retained := True;
            Entry.Item := Item;
            Break;
          end;
          Inc(I);
        end;
        if I >= H.PlayerHoldEntries.Count then
        begin
          Entry := TPlayerHoldUnit.Create;
          H.PlayerHoldEntries.Add(Entry);
          Entry.Kind := phkArtefact;
          Entry.ItemId := Item.Id;
          Entry.Item := Item;
          Entry.Retained := True;
        end;
      end;
    end;
  end;
  I := H.PlayerHoldEntries.Count - 1;
  while I >= 0 do
  begin
    Entry := H.PlayerHoldEntries[I];
    if Entry.Kind <> phkEmpty then
      Break;
    Entry.Retained := False;
    Dec(I);
  end;
  I := 0;
  while I < H.PlayerHoldEntries.Count do
  begin
    Entry := H.PlayerHoldEntries[I];
    if not Entry.Retained then
    begin
      H.PlayerHoldEntries.Delete(I);
      Entry.Free;
    end
    else
      Inc(I);
  end;
  Order := 0;
  for I := 1 to H.PlayerHoldEntries.Count - 1 do
  begin
    Entry := H.PlayerHoldEntries[I];
    if Entry.Kind = phkEmpty then
      Continue;
    J := 0;
    while J < I do
    begin
      Other := H.PlayerHoldEntries[J];
      if (Other.Kind <> phkEmpty) and (Other.DisplayOrder = Entry.DisplayOrder) then
        Break;
      Inc(J);
    end;
    if J < I then
    begin
      while True do
      begin
        J := 0;
        while J < H.PlayerHoldEntries.Count do
        begin
          Other := H.PlayerHoldEntries[J];
          if Other.Kind <> phkEmpty then
            if Other.DisplayOrder = Order then
              Break;
          Inc(J);
        end;
        if J >= H.PlayerHoldEntries.Count then
          Break;
        Inc(Order);
      end;
      Entry.DisplayOrder := Order;
      Inc(Order);
    end;
  end;
end;

procedure RemoveEmptyPlayerHoldSlot(Human: TObject; Index: Integer);
var
  H: THuman;
  Entry: TPlayerHoldUnit;
begin
  H := THuman(Human);
  if (Index < 0) or (Index >= H.PlayerHoldEntries.Count) then
    Exit;
  Entry := H.PlayerHoldEntries[Index];
  if Entry.Kind = phkEmpty then
  begin
    H.PlayerHoldEntries.Delete(Index);
    Entry.Free;
  end;
end;

procedure ClearPlayerHoldEntries(Human: TObject);
var
  H: THuman;
  I: Integer;
  Entry: TPlayerHoldUnit;
begin
  H := THuman(Human);
  if H.PlayerHoldEntries = nil then
    Exit;
  for I := H.PlayerHoldEntries.Count - 1 downto 0 do
  begin
    Entry := H.PlayerHoldEntries[I];
    begin
      H.PlayerHoldEntries.Delete(I);
      Entry.Free;
    end;
  end;
end;

procedure RemoveEmptyPlayerHoldSlots(Human: TObject);
var
  H: THuman;
  I: Integer;
  Entry: TPlayerHoldUnit;
begin
  H := THuman(Human);
  if H.PlayerHoldEntries = nil then
    Exit;
  for I := H.PlayerHoldEntries.Count - 1 downto 0 do
  begin
    Entry := H.PlayerHoldEntries[I];
    if Entry.Kind = phkEmpty then
    begin
      H.PlayerHoldEntries.Delete(I);
      Entry.Free;
    end;
  end;
end;

function IsPlayerHoldSlotEmpty(Human: TObject; Index: Integer): Boolean;
var
  H: THuman;
  Entry: TPlayerHoldUnit;
begin
  H := THuman(Human);
  Result := True;
  if (Index < 0) or (Index >= H.PlayerHoldEntries.Count) then
    Exit;
  Entry := H.PlayerHoldEntries[Index];
  Result := Entry.Kind = phkEmpty;
end;

function ComparePlayerHoldEntries(
    Human: TObject;
    Left, Right: TPlayerHoldUnit;
    Sort: TPlayerHoldSort
): Integer;
var
  H: THuman;
  LeftValue, RightValue: Integer;
  LeftType, RightType: Byte;
  LeftName, RightName: WideString;
  NameComparison: Integer;
begin
  H := THuman(Human);
  Result := 0;
  if Sort = phsType then
  begin
    if Integer(Left.Kind) < Integer(Right.Kind) then
    begin
      Result := -1;
      Exit
    end;
    if Integer(Left.Kind) > Integer(Right.Kind) then
    begin
      Result := 1;
      Exit
    end;
    if Left.Kind = phkGoods then
      LeftType := Left.GoodsIndex
    else
      LeftType := Byte(Left.Item.ItemType);
    if Right.Kind = phkGoods then
      RightType := Right.GoodsIndex
    else
      RightType := Byte(Right.Item.ItemType);
    if Integer(LeftType) < Integer(RightType) then
    begin
      Result := -1;
      Exit
    end;
    if Integer(LeftType) > Integer(RightType) then
    begin
      Result := 1;
      Exit
    end;
    if (Left.Kind in [phkEquipment, phkArtefact])
        and (Right.Kind in [phkEquipment, phkArtefact])
        and (Left.Item <> nil)
        and (Right.Item <> nil) then
    begin
      if (Left.Item.ItemType = t_MicroModule) and (Right.Item.ItemType = t_MicroModule) then
      begin
        LeftValue :=
            GetMicroModulePriorityColorTier((Left.Item as TMicroModule).MicroModuleIndex - 1);
        RightValue :=
            GetMicroModulePriorityColorTier((Right.Item as TMicroModule).MicroModuleIndex - 1);
        if LeftValue < RightValue then
        begin
          Result := -1;
          Exit
        end;
        if LeftValue > RightValue then
        begin
          Result := 1;
          Exit
        end;
      end;
      LeftName := Left.Item.GetDisplayName;
      RightName := Right.Item.GetDisplayName;
      NameComparison := CompareWideChars(PWideChar(LeftName), PWideChar(RightName));
      if NameComparison <> 0 then
      begin
        Result := NameComparison;
        Exit
      end;
    end;
  end;
  if Integer(Sort) <= Integer(phsSize) then
  begin
    if Left.Kind = phkGoods then
      LeftValue := H.PlayerHoldShip.CargoGoods[Left.GoodsIndex].Count
    else
      LeftValue := Left.Item.Weight;
    if Right.Kind = phkGoods then
      RightValue := H.PlayerHoldShip.CargoGoods[Right.GoodsIndex].Count
    else
      RightValue := Right.Item.Weight;
    if LeftValue < RightValue then
    begin
      Result := -1;
      Exit
    end;
    if LeftValue > RightValue then
    begin
      Result := 1;
      Exit
    end;
  end;
  if Left.Kind = phkGoods then
    LeftValue := H.PlayerHoldShip.CargoGoods[Left.GoodsIndex].TotalCost
  else
    LeftValue := Left.Item.Cost;
  if Right.Kind = phkGoods then
    RightValue := H.PlayerHoldShip.CargoGoods[Right.GoodsIndex].TotalCost
  else
    RightValue := Right.Item.Cost;
  if LeftValue < RightValue then
  begin
    Result := -1;
    Exit
  end;
  if LeftValue > RightValue then
  begin
    Result := 1;
    Exit
  end;
end;

procedure SortPlayerHoldEntries(Human: TObject; Sort: TPlayerHoldSort);
var
  H: THuman;
  I, J: Integer;
  Entry: TPlayerHoldUnit;
begin
  H := THuman(Human);
  aCalc.WaitForTurnCalculationUI;
  RemoveEmptyPlayerHoldSlots(Human);
  for I := 0 to H.PlayerHoldEntries.Count - 2 do
    for J := I + 1 to H.PlayerHoldEntries.Count - 1 do
      if ComparePlayerHoldEntries(Human, H.PlayerHoldEntries[I], H.PlayerHoldEntries[J], Sort) > 0 then
      begin
        Entry := H.PlayerHoldEntries[I];
        H.PlayerHoldEntries[I] := H.PlayerHoldEntries[J];
        H.PlayerHoldEntries[J] := Entry;
      end;
  J := 0;
  for I := 0 to H.PlayerHoldEntries.Count - 1 do
  begin
    Entry := H.PlayerHoldEntries[I];
    if Entry.Kind <> phkEmpty then
    begin
      Entry.DisplayOrder := J;
      Inc(J);
    end;
  end;
  aCalc.WaitForTurnCalculationUI;
end;

procedure RestorePlayerHoldDisplayOrder(Human: TObject);
var
  H: THuman;
  I, J: Integer;
  Entry: TPlayerHoldUnit;
begin
  H := THuman(Human);
  for I := H.PlayerHoldEntries.Count - 1 downto 0 do
    RemoveEmptyPlayerHoldSlot(Human, I);
  for I := 0 to H.PlayerHoldEntries.Count - 2 do
    for J := I + 1 to H.PlayerHoldEntries.Count - 1 do
      if TPlayerHoldUnit(H.PlayerHoldEntries[I]).DisplayOrder
          > TPlayerHoldUnit(H.PlayerHoldEntries[J]).DisplayOrder then
      begin
        Entry := H.PlayerHoldEntries[I];
        H.PlayerHoldEntries[I] := H.PlayerHoldEntries[J];
        H.PlayerHoldEntries[J] := Entry;
      end;
end;

function FindPlayerHoldIndexByOrder(Human: TObject; DisplayOrder: Integer): Integer;
var
  H: THuman;
  I: Integer;
  Entry: TPlayerHoldUnit;
begin
  H := THuman(Human);
  for I := 0 to H.PlayerHoldEntries.Count - 1 do
  begin
    Entry := H.PlayerHoldEntries[I];
    if Entry.Kind <> phkEmpty then
      if Entry.DisplayOrder = DisplayOrder then
      begin
        Result := I;
        Exit;
      end;
  end;
  Result := -1;
end;

function FindFreePlayerHoldOrder(Human: TObject): Integer;
var
  H: THuman;
  Order, I: Integer;
  Entry: TPlayerHoldUnit;
begin
  H := THuman(Human);
  Order := 0;
  while True do
  begin
    I := 0;
    while I < H.PlayerHoldEntries.Count do
    begin
      Entry := H.PlayerHoldEntries[I];
      if Entry.Kind <> phkEmpty then
        if Entry.DisplayOrder = Order then
          Break;
      Inc(I);
    end;
    if I >= H.PlayerHoldEntries.Count then
    begin
      Result := Order;
      Exit;
    end;
    Inc(Order);
  end;
end;

end.
