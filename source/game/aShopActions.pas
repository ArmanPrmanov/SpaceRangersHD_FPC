{$EXCESSPRECISION OFF}
unit aShopActions;

// CHANGE: ENHANCEMENT - What a human does in the shops, as commands (docs/commands.md): the
// equipment shop, the goods shop and the hangar. The code is moved from the screens; they
// keep their dialogs, sounds and images. Items in the open shop's grid are in no galaxy
// list, so a command names one by its slot in the human's TemporaryShopSlots and its id.
interface
uses
  aCommands,
  aHuman,
  aItem,
  aShip;
const
  // Command kinds 100-199 (see TCommandKind).
  ckEnterEquipmentShop = 100;
  ckShowShopItemInfo = 101;
  ckBuyEquipment = 102;
  ckFinishStoredHullPurchase = 103;
  ckTradeGoods = 110;
  ckRepairHull = 120;
  ckRefuel = 121;
  ckStoreTranclucator = 122;
  ckEndAutomaticControl = 123;
type
  TEquipmentPurchase = (
      // The item went to the hold, or the hull replaced the ship's.
      epDone,
      // The hull went to storage; FinishStoredHullPurchase runs the rest after the screen's
      // message.
      epHullStored
  );

// The equipment shop's script hook satOnEnteringForm, which runs with the shop grid put
// aside.
procedure EnterEquipmentShop;
// The item scripts that run when the shop shows Item's description.
procedure ShowShopItemInfo(Item: TItem);
// Buys the item in the shop grid's slot SlotIndex.
function BuyEquipment(SlotIndex: Integer; Item: TItem): TEquipmentPurchase;
procedure FinishStoredHullPurchase;

// The prices of Partner's cargo while Human trades with it in space (Human.TradeRows).
procedure RefreshTradeRows(Human: THuman; Partner: TShip);
// Buys Count of Good from the market, or sells them from the cargo.
procedure TradeGoods(Good: Byte; Count: Integer; Sell: Boolean);

// Repairs the hull as far as the money goes. With no money, only clears a debt.
procedure RepairHull;
procedure Refuel;
// Turns the player's tranclucator back into an artefact in storage.
procedure StoreTranclucator(Ship: TShip);
procedure EndAutomaticControl;
implementation
uses
  Classes,
  SysUtils,
  Math,
  SE_Space,
  aConst,
  aGalaxy,
  aGalaxyEvent,
  aGalaxyStruct,
  aPlayer,
  aScript,
  aShopStock,
  aTranclucator;

function ShopSlotIndex(Item: TItem): Integer;
var
  I: Integer;
begin
  Result := -1;
  if (Item = nil) or (LocalHuman.TemporaryShopSlots = nil) then
    Exit;
  for I := 0 to LocalHuman.TemporaryShopSlots.Count - 1 do
    if TShopStockSlot(LocalHuman.TemporaryShopSlots[I]).Item = Item then
      Exit(I);
end;

procedure AddShopItem(var Command: TPlayerCommand; SlotIndex: Integer; Item: TItem);
begin
  AddInt(Command, SlotIndex);
  AddInt(Command, Item.Id);
end;

// The slot the command names from Index on; its item must have the id the command names.
function ShopSlotArg(const Command: TPlayerCommand; Index: Integer): TShopStockSlot;
var
  H: THuman;
  SlotIndex: Integer;
begin
  H := ActorHuman(Command);
  SlotIndex := IntArg(Command, Index);
  if (H.TemporaryShopSlots = nil)
      or (SlotIndex < 0)
      or (SlotIndex >= H.TemporaryShopSlots.Count) then
    raise Exception.Create(CommandKindName(Command.Kind) + ' names a missing shop slot');
  Result := TShopStockSlot(H.TemporaryShopSlots[SlotIndex]);
  if (Result.Item = nil) or (Result.Item.Id <> IntArg(Command, Index + 1)) then
    raise Exception.Create(CommandKindName(Command.Kind) + ' names another shop item');
end;

// Moved from TfEquipmentShop.OnOpen.
procedure ExecuteEnterEquipmentShop(const Command: TPlayerCommand);
var
  H: THuman;
  SavedSlots: TList;
begin
  H := ActorHuman(Command);
  SavedSlots := H.TemporaryShopSlots;
  H.TemporaryShopSlots := nil;
  Actor(Command).ScriptItemsAct(satOnEnteringForm, nil, nil, 0);
  H.TemporaryShopSlots := SavedSlots;
end;

procedure EnterEquipmentShop;
begin
  SubmitCommand(NewCommand(ckEnterEquipmentShop));
end;

// Moved verbatim from TfEquipmentShop.RefreshItemInfo.
procedure RunShopItemInfoScripts(P: TPlayer; Item: TItem);
begin
  if P.CurrentPlanet <> nil then
  begin
    if Item.ScriptItem <> nil then
      TScriptItem(Item.ScriptItem)
          .RunActionCode(satOnShowingItemInfo, nil, P.CurrentPlanet, nil, 0);
    if Item is TEquipmentWithActCode then
      RunItemConfigActionCode(Item, satOnShowingItemInfo, nil, P.CurrentPlanet, nil, 0);
  end
  else
  begin
    if Item.ScriptItem <> nil then
      TScriptItem(Item.ScriptItem)
          .RunActionCode(satOnShowingItemInfo, nil, P.DockedTo, nil, 0);
    if Item is TEquipmentWithActCode then
      RunItemConfigActionCode(Item, satOnShowingItemInfo, nil, P.DockedTo, nil, 0);
  end;
end;

procedure ExecuteShowShopItemInfo(const Command: TPlayerCommand);
begin
  RunShopItemInfoScripts(Actor(Command), ShopSlotArg(Command, 0).Item);
end;

procedure ShowShopItemInfo(Item: TItem);
var
  Command: TPlayerCommand;
  SlotIndex: Integer;
begin
  SlotIndex := ShopSlotIndex(Item);
  // An item outside the grid cannot be named; its scripts run unrecorded, and the command
  // log then writes a checkpoint.
  if SlotIndex < 0 then
  begin
    RunShopItemInfoScripts(LocalPlayer, Item);
    Exit;
  end;
  Command := NewCommand(ckShowShopItemInfo);
  AddShopItem(Command, SlotIndex, Item);
  SubmitCommand(Command);
end;

var
  EquipmentPurchase: TEquipmentPurchase;
  PurchasedItem: TItem;

// Moved verbatim from TfEquipmentShop.ItemMouseUp. The price is the one the screen showed,
// computed the same way.
procedure ExecuteBuyEquipment(const Command: TPlayerCommand);
var
  P: TPlayer;
  Slot: TShopStockSlot;
  Price: Integer;
  Event: TGalaxyEvent;
  Destination: PtrInt;
begin
  P := Actor(Command);
  Slot := ShopSlotArg(Command, 0);
  Price := Slot.Item.GetConditionAdjustedCost;
  P.GetCargoFreeSpace;
  if (Slot.Item is THull)
      and (P.Money < Price)
      and (P.GetHull.ScriptItem = nil)
      and (P.GetHull.NoDropFlag = 0) then
    Price :=
        Max(
            1,
            Price
                - P.GetHull.CalculateResaleValue(
                    P.GetEffectiveSkillLevel(psTrading))
        );
  if P.Money < Price then
    raise Exception.Create('BuyEquipment: not enough money');
  if not (Slot.Item is THull) and (P.CargoFreeSpace < Slot.Item.Weight) then
    raise Exception.Create('BuyEquipment: not enough cargo space');
  EquipmentPurchase := epDone;
  PurchasedItem := Slot.Item;
  Event := AddGalaxyEvent('PlayerBuysEquipment');
  Event.AddData(Ord(Slot.Item.ItemType));
  Event.AddData(Slot.Item.GetConditionAdjustedCost);
  Event.AddData(Slot.Item.Weight);
  Event.AddData(Slot.Item.Id);
  if P.CurrentPlanet <> nil then
  begin
    Event.AddData(0);
    Event.AddData(P.CurrentPlanet.Id);
  end
  else if P.DockedTo <> nil then
  begin
    Event.AddData(1);
    Event.AddData(P.DockedTo.Id);
  end
  else
  begin
    Event.AddData(2);
    Event.AddData(0);
  end;
  Event.AddTextData(Slot.Item.GetDisplayName);
  Event.AddTextData(Slot.Item.GetCategoryConfigName);
  if Slot.Item is THull then
  begin
    if Slot.Item.GetConditionAdjustedCost > P.Money then
    begin
      Event := AddGalaxyEvent('PlayerSellsEquipment');
      Event.AddData(Ord(P.GetHull.ItemType));
      Event.AddData(
          P.GetHull.CalculateResaleValue(P.GetEffectiveSkillLevel(psTrading))
      );
      Event.AddData(P.GetHull.Weight);
      Event.AddData(P.GetHull.Id);
      if P.CurrentPlanet <> nil then
      begin
        Event.AddData(0);
        Event.AddData(P.CurrentPlanet.Id);
      end
      else if P.DockedTo <> nil then
      begin
        Event.AddData(1);
        Event.AddData(P.DockedTo.Id);
      end
      else
      begin
        Event.AddData(2);
        Event.AddData(0);
      end;
      Event.AddTextData(P.GetHull.GetDisplayName);
      Event.AddTextData(P.GetHull.GetCategoryConfigName);
      P.SetMoney(P.Money - Price);
      P.ScriptItemsAct(satOnPlayerChangeHull, Slot.Item, P.GetHull, 0);
      P.Inventory.Delete(P.Inventory.IndexOf(P.GetHull));
      P.GetHull.Free;
      P.Inventory.Insert(0, Slot.Item);
      P.Hull := Slot.Item as THull;
      P.GetHull.OwnerShip := P;
      P.GetHull.AssignedSlotData := 0;
      if Slot.Item.ScriptItem <> nil then
        TScriptItem(Slot.Item.ScriptItem)
            .RunActionCode(satOnPlayerChangeHull, P, Slot.Item, nil, 0);
      Slot.Item := nil;
      P.RefreshAssignedItemSlots;
      P.RebuildEquipmentCache;
      P.RefreshDerivedStats(True);
      if not P.ScriptChameleon then
      begin
        ReleaseSpaceObject(P.Graphic);
        P.RefreshGraphic;
      end;
      Destination := PtrInt(P);
    end
    else
    begin
      P.SetMoney(P.Money - Slot.Item.GetConditionAdjustedCost);
      if P.IsOnPlanet then
        P.AddItemToPlayerStorage(Slot.Item, P.CurrentPlanet, -1)
      else
        P.AddItemToPlayerStorage(Slot.Item, P.DockedTo, -1);
      Slot.Item := nil;
      // The screen tells the player where the hull went before the rest runs.
      EquipmentPurchase := epHullStored;
      Exit;
    end;
  end
  else
  begin
    P.SetMoney(P.Money - Price);
    TEquipment(Slot.Item).EquippedFlag := 0;
    if Slot.Item is TArtefact then
      P.Artefacts.Add(Slot.Item)
    else
      P.Inventory.Add(Slot.Item);
    Slot.Item := nil;
    Destination := PtrInt(P);
  end;
  P.ScriptItemsAct(satOnPlayerBuyEq, PurchasedItem, nil, Destination);
  P.RefreshDerivedStats(True);
end;

function BuyEquipment(SlotIndex: Integer; Item: TItem): TEquipmentPurchase;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckBuyEquipment);
  AddShopItem(Command, SlotIndex, Item);
  SubmitCommand(Command);
  Result := EquipmentPurchase;
end;

function StorageIndex(P: TPlayer; Item: TItem): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to P.StorageEntries.Count - 1 do
    if PStorageEntry(P.StorageEntries[I]).Item = Item then
      Exit(I);
end;

// The end of ExecuteBuyEquipment for a hull that went to storage.
procedure FinishHullPurchase(P: TPlayer; Item: TItem);
var
  Destination: PtrInt;
begin
  if P.CurrentPlanet <> nil then
    Destination := PtrInt(P.CurrentPlanet)
  else
    Destination := PtrInt(P.DockedTo);
  P.ScriptItemsAct(satOnPlayerBuyEq, Item, nil, Destination);
  P.RefreshDerivedStats(True);
end;

// The hull is named by its place in the player's storage and its id.
procedure ExecuteFinishStoredHullPurchase(const Command: TPlayerCommand);
var
  P: TPlayer;
  Index: Integer;
  Item: TItem;
begin
  P := Actor(Command);
  Index := IntArg(Command, 0);
  if (Index < 0) or (Index >= P.StorageEntries.Count) then
    raise Exception.Create('FinishStoredHullPurchase names a missing storage entry');
  Item := PStorageEntry(P.StorageEntries[Index]).Item;
  if Item.Id <> IntArg(Command, 1) then
    raise Exception.Create('FinishStoredHullPurchase names another item');
  FinishHullPurchase(P, Item);
end;

procedure FinishStoredHullPurchase;
var
  Command: TPlayerCommand;
  Index: Integer;
begin
  Index := StorageIndex(LocalPlayer, PurchasedItem);
  // A storage script that moved the hull away leaves nothing to name; the rest then runs
  // unrecorded, and the command log writes a checkpoint.
  if Index < 0 then
  begin
    FinishHullPurchase(LocalPlayer, PurchasedItem);
    Exit;
  end;
  Command := NewCommand(ckFinishStoredHullPurchase);
  AddInt(Command, Index);
  AddInt(Command, PurchasedItem.Id);
  SubmitCommand(Command);
end;

// Moved verbatim from TfGoodsShop2.RefreshGoodsDisplay.
procedure RefreshTradeRows(Human: THuman; Partner: TShip);
var
  Good: Byte;
begin
  for Good := 0 to 7 do
  begin
    Human.TradeRows[Good].Count := Partner.CargoGoods[Good].Count;
    Human.TradeRows[Good].MaximumPrice := GoodsMarket[Good].MaxPrice;
    if Partner.CargoGoods[Good].Count <= 0 then
    begin
      Human.TradeRows[Good].PurchasePrice := Round(Max(GoodsMarket[Good].AveragePrice * 1.1, 0));
      Human.TradeRows[Good].BaseSalePrice := Round(Max(GoodsMarket[Good].MinPrice, 0));
    end
    else
    begin
      Human.TradeRows[Good].PurchasePrice :=
          Round(
              Max(
                  GoodsMarket[Good].AveragePrice * 1.1,
                  Partner.CargoGoods[Good].TotalCost / Partner.CargoGoods[Good].Count * 1.3
              )
          );
      Human.TradeRows[Good].BaseSalePrice :=
          Round(
              Max(
                  GoodsMarket[Good].MinPrice,
                  Partner.CargoGoods[Good].TotalCost / Partner.CargoGoods[Good].Count * 0.7
              )
          );
    end;
  end;
end;

// Moved verbatim from TfGoodsShop2.GoodsMouseUp. In space the partner is the ship the player
// talks to; its prices (TradeRows) are computed again from its cargo, as the screen showed
// them.
procedure ExecuteTradeGoods(const Command: TPlayerCommand);
var
  P: TPlayer;
  Partner: TShip;
  Good: Byte;
  Count: Integer;
  Sell: Boolean;
begin
  P := Actor(Command);
  Good := IntArg(Command, 0);
  Count := IntArg(Command, 1);
  Sell := IntArg(Command, 2) <> 0;
  if P.InNormalSpace then
  begin
    Partner := ActorHuman(Command).TalkShip;
    if RefObject(Command, 0) <> Partner then
      raise Exception.Create('TradeGoods names another partner');
    RefreshTradeRows(ActorHuman(Command), Partner);
    if not Sell then
    begin
      Partner.SetMoney(
          Partner.Money
              + Count
                  * P.ShopGoodsPurchasePrice(Good, nil)
      );
      Dec(
          Partner.CargoGoods[Good].TotalCost,
          Count * P.ShopGoodsPurchasePrice(Good, nil)
      );
      Dec(Partner.CargoGoods[Good].Count, Count);
    end
    else
    begin
      Partner.SetMoney(
          Partner.Money
              - Count
                  * P.ShopGoodsSellPrice(Good, nil)
      );
      Inc(
          Partner.CargoGoods[Good].TotalCost,
          Count * P.ShopGoodsSellPrice(Good, nil)
      );
      Inc(Partner.CargoGoods[Good].Count, Count);
    end;
    Partner.RefreshDerivedStats(True);
  end;
  if not Sell then
    P.BuyGoodsFromLocation(Good, Count)
  else
    P.SellGoodsToLocation(Good, Count);
end;

procedure TradeGoods(Good: Byte; Count: Integer; Sell: Boolean);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckTradeGoods);
  if LocalPlayer.InNormalSpace then
    AddRef(Command, LocalHuman.TalkShip)
  else
    AddRef(Command, nil);
  AddInt(Command, Good);
  AddInt(Command, Count);
  AddInt(Command, Ord(Sell));
  SubmitCommand(Command);
end;

// Moved verbatim from TfHangar.RepairHullClicked.
procedure ExecuteRepairHull(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  if P.Money <= 0 then
  begin
    P.SetMoney(0);
    Exit;
  end;
  if P.GetHull.CalculateRepairCost > P.Money then
  begin
    Inc(
        P.GetHull.HullPoints,
        Round(
            P.Money
                / P.GetHull.CalculateRepairCost
                * (P.GetHull.Weight - P.GetHull.HullPoints)
        )
    );
    P.SetMoney(0);
  end
  else
  begin
    P.SetMoney(P.Money - P.GetHull.CalculateRepairCost);
    P.GetHull.HullPoints := P.GetHull.Weight;
  end;
end;

procedure RepairHull;
begin
  SubmitCommand(NewCommand(ckRepairHull));
end;

// Moved verbatim from TfHangar.RefuelClicked.
procedure ExecuteRefuel(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  if P.GetFullRefuelCost > P.Money then
    Exit;
  P.SetMoney(P.Money - P.GetFullRefuelCost);
  P.GetFuelTanks.Fuel := P.GetFuelTanks.Capacity;
  P.RefreshDerivedStats(True);
end;

procedure Refuel;
begin
  SubmitCommand(NewCommand(ckRefuel));
end;

// Moved from TfHangar.MainRightButtonDown.
procedure ExecuteStoreTranclucator(const Command: TPlayerCommand);
var
  Ship: TTranclucator;
begin
  Ship := RefObject(Command, 0) as TTranclucator;
  if Ship.OwnerShip <> Actor(Command) then
    raise Exception.Create('StoreTranclucator names a tranclucator of another ship');
  Ship.ConvertToStoredArtefact;
end;

procedure StoreTranclucator(Ship: TShip);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckStoreTranclucator);
  AddRef(Command, Ship);
  SubmitCommand(Command);
end;

// Moved from TfHangar.TakeOffClicked.
procedure ExecuteEndAutomaticControl(const Command: TPlayerCommand);
begin
  ActorHuman(Command).PlayerAutomaticControl := False;
end;

procedure EndAutomaticControl;
begin
  SubmitCommand(NewCommand(ckEndAutomaticControl));
end;

initialization
  RegisterCommand(ckEnterEquipmentShop, 'EnterEquipmentShop', @ExecuteEnterEquipmentShop);
  RegisterCommand(ckShowShopItemInfo, 'ShowShopItemInfo', @ExecuteShowShopItemInfo);
  RegisterCommand(ckBuyEquipment, 'BuyEquipment', @ExecuteBuyEquipment);
  RegisterCommand(ckFinishStoredHullPurchase, 'FinishStoredHullPurchase', @ExecuteFinishStoredHullPurchase);
  RegisterCommand(ckTradeGoods, 'TradeGoods', @ExecuteTradeGoods);
  RegisterCommand(ckRepairHull, 'RepairHull', @ExecuteRepairHull);
  RegisterCommand(ckRefuel, 'Refuel', @ExecuteRefuel);
  RegisterCommand(ckStoreTranclucator, 'StoreTranclucator', @ExecuteStoreTranclucator);
  RegisterCommand(ckEndAutomaticControl, 'EndAutomaticControl', @ExecuteEndAutomaticControl);
end.
