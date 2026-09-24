{$EXCESSPRECISION OFF}
unit aHold;
{$R-}
{$Q-}
{$B-}
{$A8}

// CHANGE: CLEANUP - The order in which the ship screen lists the player's hold, moved out of
// fShip2. The save writes it, and satellites are numbered by it. The list is
// LocalHuman.PlayerHoldEntries, for the ship LocalHuman.PlayerHoldShip.
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
procedure InitializePlayerHoldView;
procedure FinalizePlayerHoldView;
procedure RefreshPlayerHoldView(IncludeFilteredItems: Boolean);
procedure RemoveEmptyPlayerHoldSlot(Index: Integer);
procedure ClearPlayerHoldEntries;
procedure RemoveEmptyPlayerHoldSlots;
function IsPlayerHoldSlotEmpty(Index: Integer): Boolean;
function ComparePlayerHoldEntries(
    Left: TPlayerHoldUnit;
    Right: TPlayerHoldUnit;
    Sort: TPlayerHoldSort
): Integer;
procedure SortPlayerHoldEntries(Sort: TPlayerHoldSort);
procedure RestorePlayerHoldDisplayOrder;
function FindPlayerHoldIndexByOrder(DisplayOrder: Integer): Integer;
function FindFreePlayerHoldOrder: Integer;
implementation
uses
  Classes,
  EC_Str,
  aCalc,
  aConst,
  aHuman,
  aPlayer,
  aShip;

procedure InitializePlayerHoldView;
begin
  FinalizePlayerHoldView;
  LocalHuman.PlayerHoldEntries := TList.Create;
end;

procedure FinalizePlayerHoldView;
begin
  if LocalHuman.PlayerHoldEntries <> nil then
  begin
    ClearPlayerHoldEntries;
    LocalHuman.PlayerHoldEntries.Free;
    LocalHuman.PlayerHoldEntries := nil;
  end;
end;

procedure RefreshPlayerHoldView(IncludeFilteredItems: Boolean);
var
  Ship: TShip;
  Goods: Byte;
  Entry, Other: TPlayerHoldUnit;
  I, J, Order: Integer;
  Item: TEquipment;
begin
  if LocalHuman.PlayerHoldEntries = nil then
    InitializePlayerHoldView;
  if LocalHuman.PlayerHoldShip <> nil then
    Ship := LocalHuman.PlayerHoldShip
  else
    Ship := GetPlayer;
  for I := 0 to LocalHuman.PlayerHoldEntries.Count - 1 do
  begin
    Entry := LocalHuman.PlayerHoldEntries[I];
    Entry.Retained := Entry.Kind = phkEmpty;
  end;
  for Goods := 0 to 7 do
  begin
    if not IncludeFilteredItems then
      if not GetPlayer.CanAccessHoldGoods(Goods) then
        Continue;
    if Ship.CargoGoods[Goods].Count > 0 then
    begin
      I := 0;
      while I < LocalHuman.PlayerHoldEntries.Count do
      begin
        Entry := LocalHuman.PlayerHoldEntries[I];
        if not Entry.Retained and (Entry.Kind = phkGoods) and (Entry.GoodsIndex = Goods) then
        begin
          Entry.Retained := True;
          Break;
        end;
        Inc(I);
      end;
      if I >= LocalHuman.PlayerHoldEntries.Count then
      begin
        Entry := TPlayerHoldUnit.Create;
        LocalHuman.PlayerHoldEntries.Insert(0, Entry);
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
      if IncludeFilteredItems or GetPlayer.CanAccessStoredItem(Item) then
      begin
        I := 0;
        while I < LocalHuman.PlayerHoldEntries.Count do
        begin
          Entry := LocalHuman.PlayerHoldEntries[I];
          if not Entry.Retained and (Entry.Kind = phkEquipment) and (Item.Id = Entry.ItemId) then
          begin
            Entry.Retained := True;
            Entry.Item := Item;
            Break;
          end;
          Inc(I);
        end;
        if I >= LocalHuman.PlayerHoldEntries.Count then
        begin
          Entry := TPlayerHoldUnit.Create;
          LocalHuman.PlayerHoldEntries.Add(Entry);
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
      if IncludeFilteredItems or GetPlayer.CanAccessStoredItem(Item) then
      begin
        I := 0;
        while I < LocalHuman.PlayerHoldEntries.Count do
        begin
          Entry := LocalHuman.PlayerHoldEntries[I];
          if not Entry.Retained and (Entry.Kind = phkArtefact) and (Item.Id = Entry.ItemId) then
          begin
            Entry.Retained := True;
            Entry.Item := Item;
            Break;
          end;
          Inc(I);
        end;
        if I >= LocalHuman.PlayerHoldEntries.Count then
        begin
          Entry := TPlayerHoldUnit.Create;
          LocalHuman.PlayerHoldEntries.Add(Entry);
          Entry.Kind := phkArtefact;
          Entry.ItemId := Item.Id;
          Entry.Item := Item;
          Entry.Retained := True;
        end;
      end;
    end;
  end;
  I := LocalHuman.PlayerHoldEntries.Count - 1;
  while I >= 0 do
  begin
    Entry := LocalHuman.PlayerHoldEntries[I];
    if Entry.Kind <> phkEmpty then
      Break;
    Entry.Retained := False;
    Dec(I);
  end;
  I := 0;
  while I < LocalHuman.PlayerHoldEntries.Count do
  begin
    Entry := LocalHuman.PlayerHoldEntries[I];
    if not Entry.Retained then
    begin
      LocalHuman.PlayerHoldEntries.Delete(I);
      Entry.Free;
    end
    else
      Inc(I);
  end;
  Order := 0;
  for I := 1 to LocalHuman.PlayerHoldEntries.Count - 1 do
  begin
    Entry := LocalHuman.PlayerHoldEntries[I];
    if Entry.Kind = phkEmpty then
      Continue;
    J := 0;
    while J < I do
    begin
      Other := LocalHuman.PlayerHoldEntries[J];
      if (Other.Kind <> phkEmpty) and (Other.DisplayOrder = Entry.DisplayOrder) then
        Break;
      Inc(J);
    end;
    if J < I then
    begin
      while True do
      begin
        J := 0;
        while J < LocalHuman.PlayerHoldEntries.Count do
        begin
          Other := LocalHuman.PlayerHoldEntries[J];
          if Other.Kind <> phkEmpty then
            if Other.DisplayOrder = Order then
              Break;
          Inc(J);
        end;
        if J >= LocalHuman.PlayerHoldEntries.Count then
          Break;
        Inc(Order);
      end;
      Entry.DisplayOrder := Order;
      Inc(Order);
    end;
  end;
end;

procedure RemoveEmptyPlayerHoldSlot(Index: Integer);
var
  Entry: TPlayerHoldUnit;
begin
  if (Index < 0) or (Index >= LocalHuman.PlayerHoldEntries.Count) then
    Exit;
  Entry := LocalHuman.PlayerHoldEntries[Index];
  if Entry.Kind = phkEmpty then
  begin
    LocalHuman.PlayerHoldEntries.Delete(Index);
    Entry.Free;
  end;
end;

procedure ClearPlayerHoldEntries;
var
  I: Integer;
  Entry: TPlayerHoldUnit;
begin
  if LocalHuman.PlayerHoldEntries = nil then
    Exit;
  for I := LocalHuman.PlayerHoldEntries.Count - 1 downto 0 do
  begin
    Entry := LocalHuman.PlayerHoldEntries[I];
    begin
      LocalHuman.PlayerHoldEntries.Delete(I);
      Entry.Free;
    end;
  end;
end;

procedure RemoveEmptyPlayerHoldSlots;
var
  I: Integer;
  Entry: TPlayerHoldUnit;
begin
  if LocalHuman.PlayerHoldEntries = nil then
    Exit;
  for I := LocalHuman.PlayerHoldEntries.Count - 1 downto 0 do
  begin
    Entry := LocalHuman.PlayerHoldEntries[I];
    if Entry.Kind = phkEmpty then
    begin
      LocalHuman.PlayerHoldEntries.Delete(I);
      Entry.Free;
    end;
  end;
end;

function IsPlayerHoldSlotEmpty(Index: Integer): Boolean;
var
  Entry: TPlayerHoldUnit;
begin
  Result := True;
  if (Index < 0) or (Index >= LocalHuman.PlayerHoldEntries.Count) then
    Exit;
  Entry := LocalHuman.PlayerHoldEntries[Index];
  Result := Entry.Kind = phkEmpty;
end;

function ComparePlayerHoldEntries(Left, Right: TPlayerHoldUnit; Sort: TPlayerHoldSort): Integer;
var
  LeftValue, RightValue: Integer;
  LeftType, RightType: Byte;
  LeftName, RightName: WideString;
  NameComparison: Integer;
begin
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
      LeftValue := LocalHuman.PlayerHoldShip.CargoGoods[Left.GoodsIndex].Count
    else
      LeftValue := Left.Item.Weight;
    if Right.Kind = phkGoods then
      RightValue := LocalHuman.PlayerHoldShip.CargoGoods[Right.GoodsIndex].Count
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
    LeftValue := LocalHuman.PlayerHoldShip.CargoGoods[Left.GoodsIndex].TotalCost
  else
    LeftValue := Left.Item.Cost;
  if Right.Kind = phkGoods then
    RightValue := LocalHuman.PlayerHoldShip.CargoGoods[Right.GoodsIndex].TotalCost
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

procedure SortPlayerHoldEntries(Sort: TPlayerHoldSort);
var
  I, J: Integer;
  Entry: TPlayerHoldUnit;
begin
  aCalc.WaitForTurnCalculationUI;
  RemoveEmptyPlayerHoldSlots;
  for I := 0 to LocalHuman.PlayerHoldEntries.Count - 2 do
    for J := I + 1 to LocalHuman.PlayerHoldEntries.Count - 1 do
      if ComparePlayerHoldEntries(LocalHuman.PlayerHoldEntries[I], LocalHuman.PlayerHoldEntries[J], Sort) > 0 then
      begin
        Entry := LocalHuman.PlayerHoldEntries[I];
        LocalHuman.PlayerHoldEntries[I] := LocalHuman.PlayerHoldEntries[J];
        LocalHuman.PlayerHoldEntries[J] := Entry;
      end;
  J := 0;
  for I := 0 to LocalHuman.PlayerHoldEntries.Count - 1 do
  begin
    Entry := LocalHuman.PlayerHoldEntries[I];
    if Entry.Kind <> phkEmpty then
    begin
      Entry.DisplayOrder := J;
      Inc(J);
    end;
  end;
  aCalc.WaitForTurnCalculationUI;
end;

procedure RestorePlayerHoldDisplayOrder;
var
  I, J: Integer;
  Entry: TPlayerHoldUnit;
begin
  for I := LocalHuman.PlayerHoldEntries.Count - 1 downto 0 do
    RemoveEmptyPlayerHoldSlot(I);
  for I := 0 to LocalHuman.PlayerHoldEntries.Count - 2 do
    for J := I + 1 to LocalHuman.PlayerHoldEntries.Count - 1 do
      if TPlayerHoldUnit(LocalHuman.PlayerHoldEntries[I]).DisplayOrder
          > TPlayerHoldUnit(LocalHuman.PlayerHoldEntries[J]).DisplayOrder then
      begin
        Entry := LocalHuman.PlayerHoldEntries[I];
        LocalHuman.PlayerHoldEntries[I] := LocalHuman.PlayerHoldEntries[J];
        LocalHuman.PlayerHoldEntries[J] := Entry;
      end;
end;

function FindPlayerHoldIndexByOrder(DisplayOrder: Integer): Integer;
var
  I: Integer;
  Entry: TPlayerHoldUnit;
begin
  for I := 0 to LocalHuman.PlayerHoldEntries.Count - 1 do
  begin
    Entry := LocalHuman.PlayerHoldEntries[I];
    if Entry.Kind <> phkEmpty then
      if Entry.DisplayOrder = DisplayOrder then
      begin
        Result := I;
        Exit;
      end;
  end;
  Result := -1;
end;

function FindFreePlayerHoldOrder: Integer;
var
  Order, I: Integer;
  Entry: TPlayerHoldUnit;
begin
  Order := 0;
  while True do
  begin
    I := 0;
    while I < LocalHuman.PlayerHoldEntries.Count do
    begin
      Entry := LocalHuman.PlayerHoldEntries[I];
      if Entry.Kind <> phkEmpty then
        if Entry.DisplayOrder = Order then
          Break;
      Inc(I);
    end;
    if I >= LocalHuman.PlayerHoldEntries.Count then
    begin
      Result := Order;
      Exit;
    end;
    Inc(Order);
  end;
end;

end.
