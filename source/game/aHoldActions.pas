{$EXCESSPRECISION OFF}
unit aHoldActions;

// CHANGE: ENHANCEMENT - What a human does on the ship screen (fShip2) and the rewards screen
// (fRewards), as commands (docs/commands.md). The code is moved from the screens; they keep
// their dialogs, sounds, cursors and images.
//
// Picking something up takes it out of the ship or the storage: the item is then in no
// galaxy list and is held in LocalHuman (SelectedHoldKind and the fields after it) until a
// command puts it down, sells, drops or uses it, or returns it (ReturnHeldEntry). Commands
// therefore name the held entry implicitly; they name equipment slots by item type and slot
// index, hold cells by their index in LocalHuman.PlayerHoldEntries (or display order in the
// expanded hold) and storage cells by slot, resolved the way the screen resolves them. The
// hold list is the human's, so every change to it, including the refresh the screen runs
// before drawing (RefreshHoldView), is a command too. The ship the screen edits is
// LocalHuman.PlayerHoldShip, which OpenShipScreen sets.
interface
uses
  aCommands,
  aHold,
  aItem,
  aPlayer,
  aShip;
const
  // Command kinds 200-299 (see TCommandKind).
  ckOpenShipScreen = 200;
  ckRefreshHoldView = 201;
  ckLeaveShipScreen = 202;
  ckReturnHeldEntry = 203;
  ckCloseShipScreen = 204;
  ckTakeEquipped = 205;
  ckTakeArtefact = 206;
  ckTakeHoldEntry = 207;
  ckTakeHull = 208;
  ckTakeStored = 209;
  ckTakeStoredHull = 210;
  ckEquipHeld = 211;
  ckEquipHeldArtefact = 212;
  ckPutHeldGoods = 213;
  ckPutHeldStack = 214;
  ckPutHeldEquipment = 215;
  ckPutHeldArtefact = 216;
  ckStoreHeld = 217;
  ckCloseVacantStorageSlot = 218;
  ckUseHeldGoodsOn = 219;
  ckUseHeldItemOn = 220;
  ckInstallHeldMicroModule = 221;
  ckTransferHeldFuel = 222;
  ckChangeHull = 223;
  ckDropHeld = 224;
  ckSellHeld = 225;
  ckRepairHeld = 226;
  ckRefuelHeld = 227;
  ckReloadHeld = 228;
  ckRepairAll = 229;
  ckBuyRockets = 230;
  ckUseItem = 231;
  ckShowTreasureMap = 232;
  ckSellHoldInventory = 233;
  ckSellHoldArtefact = 234;
  ckSellHoldGoods = 235;
  ckSellStoredItem = 236;
  ckTakeAllFromStorage = 237;
  ckPutAllIntoStorage = 238;
  ckSortStorage = 239;
  ckSortHold = 240;
  ckRemoveEmptyHoldSlots = 241;
  ckTrainSkill = 242;
  ckFinishSkillTraining = 243;
  ckRenameShip = 244;
  ckApplyChameleonChoice = 245;
  ckSaveEquipmentConfiguration = 246;
  ckChooseEquipmentConfiguration = 247;
  ckSetHoldAfterburner = 248;
  ckRunItemInfoScripts = 249;
  ckShowAwards = 250;
  ckExchangeAwards = 251;
  ckChangeAwardVisibleCount = 252;
  ckCheckHeldUsability = 253;
const
  // Where a held item is used or installed (UseHeldGoodsOn, UseHeldItemOn,
  // InstallHeldMicroModule, TransferHeldFuel). A and B name the target: an equipment slot's
  // item type and slot, an artefact slot, or a hold cell's index and whether the hold is
  // the expanded one.
  hsEquipmentSlot = 0;
  hsArtefactSlot = 1;
  hsHoldEquipment = 2;
  hsHull = 3;
  hsHoldArtefact = 4;
  // TransferHeldFuel modes: from the held item to the target.
  hfCisternToCistern = 0;
  hfFuelTanksToFuelTanks = 1;
  hfCisternToFuelTanks = 2;
  hfFuelTanksToCistern = 3;
type
  TPutOutcome = (
      // The held goods or items went into the hold cell.
      poPlaced,
      // An item script took them; HeldActionResult says how.
      poScript,
      // Nothing happened.
      poAborted,
      // They merged into the cell's stack and nothing is held.
      poMerged,
      // Part of them merged into the cell's stack and the rest went back.
      poMergedReturned
  );
  TDropBlock = (dbNone, dbRuins, dbTranclucator, dbFuelTanks, dbEngine, dbNoDrop);
  TEquipmentArray = array of TEquipment;
var
  // The item scripts' answer to the last UseHeldGoodsOn, UseHeldItemOn, PutHeldGoods or
  // PutHeldStack.
  HeldActionResult: Integer;
  // Set by the sale commands; the screen clears them before a sale.
  SaleChanged: Boolean;
  SalePlaySound: Boolean;
  // What the last RepairAll repaired, for the screen's animations.
  RepairedItems: TEquipmentArray;
  // What the last CheckHeldUsability found: whether each equipment slot (by the slot types
  // passed and slot index), and the hull, are highlighted for the held entry.
  HeldSlotHighlights: array[0..7] of array of Boolean;
  HeldHullHighlight: Boolean;

function CanUseLocalStorage: Boolean;
function GetLocalStorageOwner: TObject;
// Whether the edited ship (a station or the player's tranclucator) trains with the player's
// experience.
function CanUsePlayerExperience: Boolean;
function CompareStoredItems(Left: PStorageEntry; Right: PStorageEntry; Sort: TPlayerHoldSort): Integer;
// The hold cell the screen names: Index in the hold list, or the display order in the
// expanded hold.
function FindHoldEntry(Index: Integer; Expanded: Boolean): TPlayerHoldUnit;

procedure OpenShipScreen(Ship: TShip; Reentering: Boolean);
// Recomputes the edited ship's slots and stats and the hold list, as the screen does before
// it draws.
procedure RefreshHoldView;
procedure LeaveShipScreen(Ship: TShip; Reentering: Boolean);
// Puts the held entry back where it came from.
procedure ReturnHeldEntry;
procedure CloseShipScreen(Reentering: Boolean);

procedure TakeEquipped(ItemType: Byte; Slot: Integer);
procedure TakeArtefact(Slot: Integer);
procedure TakeHoldEntryAt(Index: Integer; Expanded: Boolean);
// Holds the hull, which stays on the ship.
procedure TakeHull;
procedure TakeStored(Slot: Integer);
// Holds the stored hull in Slot in place of the ship's, to swap them (ChangeHull).
procedure TakeStoredHull(Slot: Integer);
// Returns whether the screen warns that a tranclucator cannot aim missiles without a radar.
function EquipHeld(ItemType: Byte; Slot: Integer): Boolean;
procedure EquipHeldArtefact(Slot: Integer);
function PutHeldGoods(Index: Integer; Expanded: Boolean; Count: Integer): TPutOutcome;
function PutHeldStack(
    Index: Integer;
    Expanded: Boolean;
    Count: Integer;
    RunScripts: Boolean
): TPutOutcome;
procedure PutHeldEquipment(Index: Integer; Expanded: Boolean);
procedure PutHeldArtefact(Index: Integer; Expanded: Boolean);
procedure StoreHeld(Slot: Integer; Count: Integer);
procedure CloseVacantStorageSlot(Slot: Integer);
function UseHeldGoodsOn(Site: Integer; A: Integer; B: Integer): Integer;
function UseHeldItemOn(Site: Integer; A: Integer; B: Integer): Integer;
procedure InstallHeldMicroModule(Site: Integer; A: Integer; B: Integer);
procedure TransferHeldFuel(Site: Integer; A: Integer; B: Integer; Mode: Integer);
// Puts the held stored hull on the ship and its hull into the storage.
procedure ChangeHull;
function DropHeld(Quantity: Integer): TDropBlock;
// Returns the price.
function SellHeld(Count: Integer): Integer;
// Nodes is what a node-repaired weapon costs, else 0.
procedure RepairHeld(Nodes: Integer);
procedure RefuelHeld(Amount: Integer);
procedure ReloadHeld(Amount: Integer);
// Returns whether anything was paid for.
function RepairAll(Nodes: Integer): Boolean;
procedure BuyRockets(Equipped: Boolean);
function UseItem(Item: TItem): Integer;
procedure ShowTreasureMap(const Text: WideString);
procedure SellHoldInventory;
procedure SellHoldArtefact(Index: Integer);
procedure SellHoldGoods(Good: Byte);
procedure SellStoredItem(StorageIndex: Integer);
function TakeAllFromStorage: Boolean;
function PutAllIntoStorage: Boolean;
procedure SortStorageEntries(Sort: TPlayerHoldSort);
procedure SortHold(Sort: TPlayerHoldSort);
procedure RemoveEmptyHoldSlots;
procedure TrainHoldSkill(Skill: Integer);
procedure FinishSkillTraining;
procedure RenameShip(const Name: WideString);
// Choice is the chameleon dialog's: 1 switches it off, 2-4 a series.
procedure ApplyChameleonChoice(Choice: Integer);
procedure SaveEquipmentConfiguration(Index: Integer);
// Returns whether the configuration was applied.
function ChooseEquipmentConfiguration(Index: Integer; Apply: Boolean): Boolean;
procedure SetHoldAfterburner(Active: Boolean);
// The item scripts that run when the screen shows Item's description.
procedure RunItemInfoScripts(Item: TItem);
// Which equipment slots of the edited ship, and whether its hull, take the held entry, as
// the screen highlights them; SlotTypes are the item types of the screen's eight slot rows.
// The held entry's and the slot items' usability checks run item scripts, so with anything
// held this is a command. Results: HeldSlotHighlights, HeldHullHighlight.
procedure CheckHeldUsability(const SlotTypes: array of Byte; HighlightRepairable: Boolean);

procedure ShowAwards(Ship: TShip);
procedure ExchangeAwards(Ship: TShip; First: Integer; Second: Integer);
procedure ChangeAwardVisibleCount(Ship: TShip; Delta: Integer);
implementation
uses
  Classes,
  SysUtils,
  Math,
  EC_Str,
  GR_Main,
  Globals,
  SE_Space,
  SE_Weapon,
  aAsteroid,
  aConst,
  aCalc,
  aEFilmEnd,
  aGalaxy,
  aGalaxyEvent,
  aGalaxyStruct,
  aHuman,
  aMissile,
  aMyFunction,
  aNormalShip,
  aRuins,
  aScript,
  aSession,
  aShopStock,
  aTranclucator;

function Actor(const Command: TPlayerCommand): TPlayer;
begin
  Result := GetPlayer;
end;

// Moved from TfShip2.CanUseLocalStorage.
function CanUseLocalStorage: Boolean;
begin
  Result :=
      ((GetPlayer.IsOnPlanet and (GetPlayer.CurrentPlanet.OwnerId <> Byte(oiUninhabited)))
              or (GetPlayer.IsDockedToShip and (GetPlayer.RuinsMode = 0)))
          and (QueuedArcadeBattles.Count <= 0);
end;

// Moved from TfShip2.GetLocalStorageOwner.
function GetLocalStorageOwner: TObject;
begin
  if GetPlayer.IsOnPlanet then
    Result := GetPlayer.CurrentPlanet
  else if GetPlayer.IsDockedToShip then
    Result := GetPlayer.DockedTo
  else
    Result := nil;
end;

// Moved from TfShip2.CanUsePlayerExperience.
function CanUsePlayerExperience: Boolean;
begin
  Result := True;
  if not ((LocalHuman.PlayerHoldShip is TRuins) and (LocalHuman.PlayerHoldShip as TRuins).ModernizationSponsor)
      and not ((LocalHuman.PlayerHoldShip is TTranclucator)
          and ((LocalHuman.PlayerHoldShip as TTranclucator).OwnerShip = GetPlayer)) then
    Result := False;
end;

// Moved verbatim from fShip2.
function CompareStoredItems(Left, Right: PStorageEntry; Sort: TPlayerHoldSort): Integer;
var
  LeftValue, RightValue: Integer;
  LeftType, RightType: Byte;
  LeftClass, RightClass: Integer;
  LeftName, RightName: WideString;
  NameComparison: Integer;
  function Classify(
      ItemType: Byte
  ): Integer; // @addr $7129B4 @ida "int __usercall $name@<eax>(unsigned __int8 ItemType@<al>, void *ParentFrame@<^0>);" @stackpop 0 @calls "0x712A81,0x712A8E" Nested helper; does not read the parent frame.
  begin
    Result := 0;
    if ItemType in [Ord(t_Food)..Ord(t_Narcotics)] then
      Result := 1
    else if ItemType in [Ord(t_Artefact)..Ord(t_ArtFastRacks)] then
      Result := 3
    else if ItemType in [Ord(t_Hull)..Ord(t_CustomWeapon)] then
      Result := 2
    else if ItemType in [Ord(t_Protoplasm)..Ord(t_UselessCountableItem)] then
      Result := 4;
  end;
begin
  Result := 0;
  if Left.Item = nil then
  begin
    Result := -1;
    Exit
  end;
  if Right.Item = nil then
  begin
    Result := 1;
    Exit
  end;
  LeftType := Byte(Left.Item.ItemType);
  RightType := Byte(Right.Item.ItemType);
  LeftClass := Classify(LeftType);
  RightClass := Classify(RightType);
  if Sort = phsType then
  begin
    if LeftClass < RightClass then
    begin
      Result := -1;
      Exit
    end;
    if LeftClass > RightClass then
    begin
      Result := 1;
      Exit
    end;
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
    if (LeftClass = 4)
        and (RightClass = 4)
        and (Left.Item.ItemType = t_MicroModule)
        and (Right.Item.ItemType = t_MicroModule) then
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
  if Integer(Sort) <= Integer(phsSize) then
  begin
    if LeftClass = 1 then
      LeftValue := TGoods(Left.Item).Quantity
    else
      LeftValue := Left.Item.Weight;
    if RightClass = 1 then
      RightValue := TGoods(Right.Item).Quantity
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
  LeftValue := Left.Item.Cost;
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

// Moved from TfShip2.RemoteHoldItemMouseDown.
function FindHoldEntry(Index: Integer; Expanded: Boolean): TPlayerHoldUnit;
var
  J: Integer;
begin
  if not Expanded then
  begin
    if (Index < 0) or (LocalHuman.PlayerHoldEntries.Count <= Index) then
      Result := nil
    else
      Result := TPlayerHoldUnit(LocalHuman.PlayerHoldEntries[Index]);
  end
  else
  begin
    J := FindPlayerHoldIndexByOrder(Index);
    if J < 0 then
      Result := nil
    else
      Result := TPlayerHoldUnit(LocalHuman.PlayerHoldEntries[J]);
  end;
end;

function HoldEntryArg(const Command: TPlayerCommand; Index: Integer): TPlayerHoldUnit;
begin
  Result := FindHoldEntry(IntArg(Command, Index), IntArg(Command, Index + 1) <> 0);
end;

procedure AddHoldCell(var Command: TPlayerCommand; Index: Integer; Expanded: Boolean);
begin
  AddInt(Command, Index);
  AddInt(Command, Ord(Expanded));
end;

procedure RequireHeld(const Command: TPlayerCommand);
begin
  if LocalHuman.SelectedHoldKind = phkEmpty then
    raise Exception.Create(CommandKindName(Command.Kind) + ' needs a held entry');
end;

procedure RequireHeldItem(const Command: TPlayerCommand);
begin
  if not (LocalHuman.SelectedHoldKind in [phkEquipment, phkArtefact])
      or (LocalHuman.SelectedHoldItem = nil) then
    raise Exception.Create(CommandKindName(Command.Kind) + ' needs a held item');
end;

// An item the ship screen shows: in the edited ship or in the player's storage.
function FindShownItem(Id: Integer): TItem;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to LocalHuman.PlayerHoldShip.Inventory.Count - 1 do
    if TItem(LocalHuman.PlayerHoldShip.Inventory[I]).Id = Id then
      Exit(TItem(LocalHuman.PlayerHoldShip.Inventory[I]));
  for I := 0 to LocalHuman.PlayerHoldShip.Artefacts.Count - 1 do
    if TItem(LocalHuman.PlayerHoldShip.Artefacts[I]).Id = Id then
      Exit(TItem(LocalHuman.PlayerHoldShip.Artefacts[I]));
  for I := 0 to GetPlayer.StorageEntries.Count - 1 do
    if (PStorageEntry(GetPlayer.StorageEntries[I]).Item <> nil)
        and (PStorageEntry(GetPlayer.StorageEntries[I]).Item.Id = Id) then
      Exit(PStorageEntry(GetPlayer.StorageEntries[I]).Item);
end;

function ShownItemArg(const Command: TPlayerCommand; Index: Integer): TItem;
begin
  Result := FindShownItem(IntArg(Command, Index));
  if Result = nil then
    raise Exception.Create(CommandKindName(Command.Kind) + ' names a missing item');
end;

// Moved from TfShip2.RefreshShipView: what it recomputes before it draws.
procedure RefreshHoldViewState;
begin
  LocalHuman.PlayerHoldShip.RefreshAssignedItemSlots;
  LocalHuman.PlayerHoldShip.RefreshDerivedStats(True);
  RefreshPlayerHoldView(False);
end;

// Moved from TfShip2.TakeHoldEntry.
procedure TakeHoldEntry(Entry: TPlayerHoldUnit; Slot: Integer; UsesDisplayOrder: Boolean);
begin
  if Entry.Kind = phkEquipment then
  begin
    LocalHuman.SelectedHoldKind := phkEquipment;
    LocalHuman.SelectedHoldOrigin := 0;
    LocalHuman.SelectedHoldSlot := Slot;
    LocalHuman.SelectedHoldUsesDisplayOrder := UsesDisplayOrder;
    LocalHuman.SelectedHoldItem := Entry.Item;
    LocalHuman.PlayerHoldShip.Inventory.Delete(LocalHuman.PlayerHoldShip.Inventory.IndexOf(Entry.Item));
    Entry.Kind := phkEmpty;
    Entry.Item := nil;
  end
  else if Entry.Kind = phkGoods then
  begin
    LocalHuman.SelectedHoldKind := phkGoods;
    LocalHuman.SelectedHoldOrigin := 0;
    LocalHuman.SelectedHoldSlot := Slot;
    LocalHuman.SelectedHoldUsesDisplayOrder := UsesDisplayOrder;
    LocalHuman.SelectedGoodsIndex := Entry.GoodsIndex;
    LocalHuman.SelectedGoodsQuantity := LocalHuman.PlayerHoldShip.CargoGoods[LocalHuman.SelectedGoodsIndex].Count;
    LocalHuman.SelectedGoodsCost := LocalHuman.PlayerHoldShip.CargoGoods[LocalHuman.SelectedGoodsIndex].TotalCost;
    LocalHuman.PlayerHoldShip.CargoGoods[LocalHuman.SelectedGoodsIndex].Count := 0;
    LocalHuman.PlayerHoldShip.CargoGoods[LocalHuman.SelectedGoodsIndex].TotalCost := 0;
    Entry.Kind := phkEmpty;
    Entry.Item := nil;
  end
  else if Entry.Kind = phkArtefact then
  begin
    LocalHuman.SelectedHoldKind := phkArtefact;
    LocalHuman.SelectedHoldOrigin := 0;
    LocalHuman.SelectedHoldSlot := Slot;
    LocalHuman.SelectedHoldUsesDisplayOrder := UsesDisplayOrder;
    LocalHuman.SelectedHoldItem := Entry.Item;
    LocalHuman.PlayerHoldShip.Artefacts.Delete(LocalHuman.PlayerHoldShip.Artefacts.IndexOf(Entry.Item));
    Entry.Kind := phkEmpty;
    Entry.Item := nil;
  end
  else
    LocalHuman.SelectedHoldKind := phkEmpty;
end;

// Moved from TfShip2.ReturnSelectedHoldEntry, without its cursor and redraw. Returns whether
// something was held.
function ReturnHeldEntryState: Boolean;
var
  I, Count: Integer;
  Entry: TPlayerHoldUnit;
begin
  Result := LocalHuman.SelectedHoldKind <> phkEmpty;
  if LocalHuman.SelectedHoldKind <> phkEmpty then
  begin
    if LocalHuman.SelectedHoldOrigin = 0 then
    begin
      if LocalHuman.SelectedHoldKind = phkGoods then
      begin
        LocalHuman.PlayerHoldShip.CargoGoods[LocalHuman.SelectedGoodsIndex].Count := LocalHuman.SelectedGoodsQuantity;
        LocalHuman.PlayerHoldShip.CargoGoods[LocalHuman.SelectedGoodsIndex].TotalCost := LocalHuman.SelectedGoodsCost;
      end
      else if LocalHuman.SelectedHoldKind = phkEquipment then
      begin
        if not (LocalHuman.SelectedHoldItem is THull) then
        begin
          if LocalHuman.SelectedHoldItem is TWeapon then
            (LocalHuman.SelectedHoldItem as TWeapon).Target := nil;
          LocalHuman.PlayerHoldShip.Inventory.Add(LocalHuman.SelectedHoldItem);
          (LocalHuman.SelectedHoldItem as TEquipment).EquippedFlag := 0;
        end;
      end
      else if LocalHuman.SelectedHoldKind = phkArtefact then
      begin
        LocalHuman.PlayerHoldShip.Artefacts.Add(LocalHuman.SelectedHoldItem);
        (LocalHuman.SelectedHoldItem as TEquipment).EquippedFlag := 0;
      end;
      if (LocalHuman.SelectedHoldKind = phkGoods)
          or (LocalHuman.SelectedHoldKind = phkEquipment)
          or (LocalHuman.SelectedHoldKind = phkArtefact) then
      begin
        if LocalHuman.SelectedHoldUsesDisplayOrder then
        begin
          if FindPlayerHoldIndexByOrder(LocalHuman.SelectedHoldSlot) < 0 then
          begin
            Entry := TPlayerHoldUnit.Create;
            LocalHuman.PlayerHoldEntries.Add(Entry);
            Entry.DisplayOrder := LocalHuman.SelectedHoldSlot;
          end
          else
          begin
            Entry := TPlayerHoldUnit.Create;
            Entry.DisplayOrder := FindFreePlayerHoldOrder;
            LocalHuman.PlayerHoldEntries.Add(Entry);
          end;
          Entry.Kind := LocalHuman.SelectedHoldKind;
          if LocalHuman.SelectedHoldKind = phkGoods then
            Entry.GoodsIndex := LocalHuman.SelectedGoodsIndex
          else
          begin
            Entry.ItemId := LocalHuman.SelectedHoldItem.Id;
            Entry.Item := LocalHuman.SelectedHoldItem;
          end;
          RestorePlayerHoldDisplayOrder;
        end
        else if LocalHuman.SelectedHoldSlot >= 0 then
        begin
          if IsPlayerHoldSlotEmpty(LocalHuman.SelectedHoldSlot) then
          begin
            if LocalHuman.PlayerHoldEntries.Count > LocalHuman.SelectedHoldSlot then
              Entry := LocalHuman.PlayerHoldEntries[LocalHuman.SelectedHoldSlot]
            else
            begin
              Count := LocalHuman.SelectedHoldSlot - LocalHuman.PlayerHoldEntries.Count + 1;
              for I := 0 to Count - 1 do
              begin
                Entry := TPlayerHoldUnit.Create;
                LocalHuman.PlayerHoldEntries.Add(Entry);
                Entry.Kind := phkEmpty;
              end;
              Entry := LocalHuman.PlayerHoldEntries[LocalHuman.PlayerHoldEntries.Count - 1];
            end;
          end
          else
          begin
            Entry := TPlayerHoldUnit.Create;
            LocalHuman.PlayerHoldEntries.Add(Entry);
          end;
          Entry.DisplayOrder := FindFreePlayerHoldOrder;
          Entry.Kind := LocalHuman.SelectedHoldKind;
          if LocalHuman.SelectedHoldKind = phkGoods then
            Entry.GoodsIndex := LocalHuman.SelectedGoodsIndex
          else
          begin
            Entry.ItemId := LocalHuman.SelectedHoldItem.Id;
            Entry.Item := LocalHuman.SelectedHoldItem;
          end;
        end
        else
        begin
          if ((LocalHuman.SelectedHoldKind = phkEquipment) or (LocalHuman.SelectedHoldKind = phkArtefact))
              and (LocalHuman.PlayerHoldShip.FindEquippedItemInSlot(
                      Byte(LocalHuman.SelectedHoldItem.ItemType),
                      -LocalHuman.SelectedHoldSlot - 1)
                  = nil) then
          begin
            (LocalHuman.SelectedHoldItem as TEquipment).EquippedFlag := 0;
            (LocalHuman.SelectedHoldItem as TEquipment).Equip;
          end;
        end
      end;
    end
    else
    begin
      if LocalHuman.SelectedHoldKind = phkGoods then
      begin
        if GetPlayer.FindStorageIndexByLocationAndSlot(GetLocalStorageOwner, LocalHuman.SelectedHoldSlot)
            < 0 then
          GetPlayer.AddGoodsToPlayerStorage(
              LocalHuman.SelectedGoodsIndex,
              LocalHuman.SelectedGoodsQuantity,
              LocalHuman.SelectedGoodsCost,
              GetLocalStorageOwner,
              LocalHuman.SelectedHoldSlot
          )
        else
          GetPlayer.AddGoodsToPlayerStorage(
              LocalHuman.SelectedGoodsIndex,
              LocalHuman.SelectedGoodsQuantity,
              LocalHuman.SelectedGoodsCost,
              GetLocalStorageOwner,
              -1
          );
      end
      else if (LocalHuman.SelectedHoldKind = phkEquipment) or (LocalHuman.SelectedHoldKind = phkArtefact) then
      begin
        if GetPlayer.FindStorageIndexByLocationAndSlot(GetLocalStorageOwner, LocalHuman.SelectedHoldSlot)
            < 0 then
          GetPlayer.AddItemToPlayerStorage(LocalHuman.SelectedHoldItem, GetLocalStorageOwner, LocalHuman.SelectedHoldSlot)
        else
          GetPlayer.AddItemToPlayerStorage(LocalHuman.SelectedHoldItem, GetLocalStorageOwner, -1);
      end;
    end;
    LocalHuman.SelectedHoldKind := phkEmpty;
    LocalHuman.SelectedHoldItem := nil;
    if not ExitScreenLoop then
      LocalHuman.PlayerHoldShip.RefreshDerivedStats(True);
  end;
end;

// TfShip2.ReturnSelectedHoldEntry called from inside another action: its redraw, which
// recomputes the hold, ran before the rest of the action.
procedure ReturnHeldEntryInside;
begin
  if ReturnHeldEntryState and not ExitScreenLoop then
    RefreshHoldViewState;
end;

// Moved from TfShip2.OnOpen: the scripts that react to the screen, and the checks it made
// on the ship and the storage.
procedure ExecuteOpenShipScreen(const Command: TPlayerCommand);
var
  P: TPlayer;
  Reentering: Boolean;
  I: Integer;
  Item: TItem;
begin
  P := Actor(Command);
  Reentering := IntArg(Command, 0) <> 0;
  LocalHuman.PlayerHoldShip := RefObject(Command, 0) as TShip;
  if Reentering then
  begin
    LocalHuman.PlayerHoldShip.ScriptItemsAct(satOnReEnteringForm, nil, nil, 0);
    if P <> LocalHuman.PlayerHoldShip then
      P.ScriptItemsAct(satOnReEnteringOtherShip, nil, nil, 0);
  end
  else
  begin
    LocalHuman.PlayerHoldShip.ScriptItemsAct(satOnEnteringForm, nil, nil, 0);
    if P <> LocalHuman.PlayerHoldShip then
      P.ScriptItemsAct(satOnEnteringOtherShip, nil, nil, 0);
  end;
  for I := 0 to LocalHuman.PlayerHoldShip.Inventory.Count - 1 do
  begin
    Item := TItem(LocalHuman.PlayerHoldShip.Inventory[I]);
    if (Item is TWeapon) and ((Item as TWeapon).Target <> nil) then
      if (Item as TWeapon).EquippedFlag = 0 then
        (Item as TWeapon).Target := nil
      else if (not ((Item as TWeapon).Target is TShip)
              or (Galaxy.IdToShip(((Item as TWeapon).Target as TShip).Id, False) = nil))
          and (not ((Item as TWeapon).Target is TItem)
              or (Galaxy.IdToItem(((Item as TWeapon).Target as TItem).Id, False) = nil))
          and (not ((Item as TWeapon).Target is TAsteroid)
              or (Galaxy.IdToAsteroid(((Item as TWeapon).Target as TAsteroid).Id) = nil))
          and (not ((Item as TWeapon).Target is TMissile)
              or (Galaxy.IdToMissile(((Item as TWeapon).Target as TMissile).Id) = nil)) then
        (Item as TWeapon).Target := nil;
  end;
  if not Reentering then
    RemoveEmptyPlayerHoldSlots;
  P.RepairDuplicateStorageSlots(GetLocalStorageOwner);
  if not Reentering then
  begin
    LocalHuman.SelectedHoldKind := phkEmpty;
    LocalHuman.SelectedHoldItem := nil;
  end;
  LocalHuman.SavedShipExperience := -1;
  if CanUsePlayerExperience then
  begin
    LocalHuman.SavedShipExperience := LocalHuman.PlayerHoldShip.FreeExperience;
    LocalHuman.PlayerHoldShip.FreeExperience := P.FreeExperience;
  end;
end;

procedure OpenShipScreen(Ship: TShip; Reentering: Boolean);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckOpenShipScreen);
  AddRef(Command, Ship);
  AddInt(Command, Ord(Reentering));
  SubmitCommand(Command);
end;

procedure ExecuteRefreshHoldView(const Command: TPlayerCommand);
begin
  RefreshHoldViewState;
end;

procedure RefreshHoldView;
begin
  SubmitCommand(NewCommand(ckRefreshHoldView));
end;

// Moved from TfShip2.OnClose.
procedure ExecuteLeaveShipScreen(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  LocalHuman.PlayerHoldShip := RefObject(Command, 0) as TShip;
  if IntArg(Command, 0) = 0 then
  begin
    LocalHuman.PlayerHoldShip.ScriptItemsAct($19, nil, nil, 0);
    if P <> LocalHuman.PlayerHoldShip then
      P.ScriptItemsAct($1C, nil, nil, 0);
  end;
end;

procedure LeaveShipScreen(Ship: TShip; Reentering: Boolean);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckLeaveShipScreen);
  AddRef(Command, Ship);
  AddInt(Command, Ord(Reentering));
  SubmitCommand(Command);
end;

procedure ExecuteReturnHeldEntry(const Command: TPlayerCommand);
begin
  ReturnHeldEntryState;
end;

procedure ReturnHeldEntry;
begin
  SubmitCommand(NewCommand(ckReturnHeldEntry));
end;

// Moved from TfShip2.OnClose.
procedure ExecuteCloseShipScreen(const Command: TPlayerCommand);
var
  P: TPlayer;
  I: Integer;
  Binding: TScriptShip;
begin
  P := Actor(Command);
  Session.ScriptUseItem := nil;
  if (LocalHuman.SavedShipExperience >= 0) and CanUsePlayerExperience then
  begin
    P.FreeExperience := LocalHuman.PlayerHoldShip.FreeExperience;
    LocalHuman.PlayerHoldShip.FreeExperience := LocalHuman.SavedShipExperience;
    LocalHuman.SavedShipExperience := -1;
  end;
  LocalHuman.PlayerHoldShip.RefreshDerivedStats(True);
  if LocalHuman.PlayerHoldShip.Order = soJump then
    if LocalHuman.PlayerHoldShip.JumpRange
        < System.Round(
            PointDistance(
                LocalHuman.PlayerHoldShip.CurrentStar.Position,
                TStar(LocalHuman.PlayerHoldShip.OrderTarget).Position
            )) then
      LocalHuman.PlayerHoldShip.OrderNone(False);
  if P.ScriptShipBindings <> nil then
  begin
    I := P.ScriptShipBindings.Count - 1;
    while I >= 0 do
    begin
      if I >= P.ScriptShipBindings.Count then
        I := P.ScriptShipBindings.Count - 1
      else
      begin
        Binding := P.ScriptShipBindings[I];
        if Binding.Script <> nil then
          Binding.Script.RunShipState(Binding);
        Dec(I);
      end;
    end;
  end;
  P.RefreshStorageBubbles;
  if IntArg(Command, 0) = 0 then
    LocalHuman.PlayerHoldShip := nil;
end;

procedure CloseShipScreen(Reentering: Boolean);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckCloseShipScreen);
  AddInt(Command, Ord(Reentering));
  SubmitCommand(Command);
end;

// Moved from TfShip2.EquipmentSlotMouseDown.
procedure ExecuteTakeEquipped(const Command: TPlayerCommand);
var
  Item: TEquipment;
  Slot: Integer;
begin
  Slot := IntArg(Command, 1);
  Item := LocalHuman.PlayerHoldShip.FindEquippedItemInSlot(IntArg(Command, 0), Slot);
  if Item = nil then
    raise Exception.Create('TakeEquipped names an empty slot');
  if Item.EquippedFlag <> 0 then
    LocalHuman.PlayerHoldShip.UnequipItem(Item);
  LocalHuman.PlayerHoldShip.Inventory.Delete(LocalHuman.PlayerHoldShip.Inventory.IndexOf(Item));
  LocalHuman.PlayerHoldShip.RebuildEquipmentCache;
  LocalHuman.PlayerHoldShip.RefreshDerivedStats(True);
  LocalHuman.SelectedHoldKind := phkEquipment;
  LocalHuman.SelectedHoldOrigin := 0;
  LocalHuman.SelectedHoldSlot := -(Slot + 1);
  LocalHuman.SelectedHoldUsesDisplayOrder := False;
  LocalHuman.SelectedHoldItem := Item;
  if Item is TWeapon then
    (Item as TWeapon).Target := nil;
end;

procedure TakeEquipped(ItemType: Byte; Slot: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckTakeEquipped);
  AddInt(Command, ItemType);
  AddInt(Command, Slot);
  SubmitCommand(Command);
end;

// Moved from TfShip2.ArtefactSlotMouseDown.
procedure ExecuteTakeArtefact(const Command: TPlayerCommand);
var
  Slot: Integer;
  Equipment: TEquipment;
  Item: TArtefact;
begin
  Slot := IntArg(Command, 0);
  Equipment := LocalHuman.PlayerHoldShip.FindEquippedItemInSlot(Ord(t_Artefact), Slot);
  if Equipment = nil then
    raise Exception.Create('TakeArtefact names an empty slot');
  Item := Equipment as TArtefact;
  Item.Unequip;
  LocalHuman.PlayerHoldShip.Artefacts.Delete(LocalHuman.PlayerHoldShip.Artefacts.IndexOf(Item));
  LocalHuman.PlayerHoldShip.RefreshDerivedStats(True);
  LocalHuman.SelectedHoldKind := phkArtefact;
  LocalHuman.SelectedHoldOrigin := 0;
  LocalHuman.SelectedHoldSlot := -(Slot + 1);
  LocalHuman.SelectedHoldUsesDisplayOrder := False;
  LocalHuman.SelectedHoldItem := Item;
end;

procedure TakeArtefact(Slot: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckTakeArtefact);
  AddInt(Command, Slot);
  SubmitCommand(Command);
end;

// Moved from TfShip2.RemoteHoldItemMouseDown.
procedure ExecuteTakeHoldEntry(const Command: TPlayerCommand);
var
  Entry: TPlayerHoldUnit;
begin
  Entry := HoldEntryArg(Command, 0);
  if Entry = nil then
    raise Exception.Create('TakeHoldEntry names an empty hold cell');
  TakeHoldEntry(Entry, IntArg(Command, 0), IntArg(Command, 1) <> 0);
  LocalHuman.PlayerHoldShip.RefreshDerivedStats(True);
end;

procedure TakeHoldEntryAt(Index: Integer; Expanded: Boolean);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckTakeHoldEntry);
  AddHoldCell(Command, Index, Expanded);
  SubmitCommand(Command);
end;

// Moved from TfShip2.HullMouseDown.
procedure ExecuteTakeHull(const Command: TPlayerCommand);
begin
  LocalHuman.SelectedHoldKind := phkEquipment;
  LocalHuman.SelectedHoldOrigin := 0;
  LocalHuman.SelectedHoldSlot := 0;
  LocalHuman.SelectedHoldUsesDisplayOrder := False;
  LocalHuman.SelectedHoldItem := TItem(LocalHuman.PlayerHoldShip.Inventory[0]);
  LocalHuman.PlayerHoldShip.RefreshDerivedStats(True);
end;

procedure TakeHull;
begin
  SubmitCommand(NewCommand(ckTakeHull));
end;

function StorageSlotIndex(const Command: TPlayerCommand; Slot: Integer): Integer;
begin
  Result := GetPlayer.FindStorageIndexByLocationAndSlot(GetLocalStorageOwner, Slot);
  if Result < 0 then
    raise Exception.Create(CommandKindName(Command.Kind) + ' names an empty storage cell');
end;

// Moved from TfShip2.StorageItemMouseUp.
procedure ExecuteTakeStored(const Command: TPlayerCommand);
var
  P: TPlayer;
  Entry: PStorageEntry;
  Slot, Index: Integer;
begin
  P := Actor(Command);
  Slot := IntArg(Command, 0);
  Index := StorageSlotIndex(Command, Slot);
  Entry := P.StorageEntries[Index];
  P.StorageEntries.Delete(Index);
  if Entry.Item is TGoods then
  begin
    LocalHuman.SelectedHoldKind := phkGoods;
    LocalHuman.SelectedHoldOrigin := 1;
    LocalHuman.SelectedHoldSlot := Slot;
    LocalHuman.SelectedHoldUsesDisplayOrder := False;
    LocalHuman.SelectedGoodsIndex := Byte(Entry.Item.ItemType);
    LocalHuman.SelectedGoodsQuantity := (Entry.Item as TGoods).Quantity;
    LocalHuman.SelectedGoodsCost := (Entry.Item as TGoods).Cost;
    Entry.Item.Free;
  end
  else if Entry.Item is TArtefact then
  begin
    LocalHuman.SelectedHoldKind := phkArtefact;
    LocalHuman.SelectedHoldOrigin := 1;
    LocalHuman.SelectedHoldSlot := Slot;
    LocalHuman.SelectedHoldUsesDisplayOrder := False;
    LocalHuman.SelectedHoldItem := Entry.Item;
  end
  else
  begin
    LocalHuman.SelectedHoldKind := phkEquipment;
    LocalHuman.SelectedHoldOrigin := 1;
    LocalHuman.SelectedHoldSlot := Slot;
    LocalHuman.SelectedHoldUsesDisplayOrder := False;
    LocalHuman.SelectedHoldItem := Entry.Item;
  end;
  Entry.LocationOwner := nil;
  Entry.Item := nil;
  Dispose(Entry);
  LocalHuman.PlayerHoldShip.ScriptItemsAct(satOnReEnteringForm, nil, nil, 0);
end;

procedure TakeStored(Slot: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckTakeStored);
  AddInt(Command, Slot);
  SubmitCommand(Command);
end;

// Moved from TfShip2.StorageItemMouseUp.
procedure ExecuteTakeStoredHull(const Command: TPlayerCommand);
var
  P: TPlayer;
  Entry: PStorageEntry;
  Slot, Index: Integer;
begin
  P := Actor(Command);
  Slot := IntArg(Command, 0);
  Index := StorageSlotIndex(Command, Slot);
  Entry := P.StorageEntries[Index];
  if not (Entry.Item is THull) then
    raise Exception.Create('TakeStoredHull names another item');
  P.StorageEntries.Delete(Index);
  LocalHuman.SelectedHoldKind := phkEquipment;
  LocalHuman.SelectedHoldOrigin := 1;
  LocalHuman.SelectedHoldSlot := Slot;
  LocalHuman.SelectedHoldUsesDisplayOrder := False;
  LocalHuman.SelectedHoldItem := Entry.Item;
  Entry.LocationOwner := nil;
  Entry.Item := nil;
  Dispose(Entry);
end;

procedure TakeStoredHull(Slot: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckTakeStoredHull);
  AddInt(Command, Slot);
  SubmitCommand(Command);
end;

var
  MissileWarning: Boolean;

// Moved from TfShip2.EquipmentSlotMouseDown. The screen shows the missile warning after
// the swap instead of between the fitting and the swap.
procedure ExecuteEquipHeld(const Command: TPlayerCommand);
var
  Slot: Integer;
  Item: TEquipment;
begin
  RequireHeldItem(Command);
  Slot := IntArg(Command, 1);
  Item := LocalHuman.PlayerHoldShip.FindEquippedItemInSlot(IntArg(Command, 0), Slot);
  if (Item <> nil) and (Item.EquippedFlag <> 0) then
    LocalHuman.PlayerHoldShip.UnequipItem(Item);
  LocalHuman.PlayerHoldShip.Inventory.Add(LocalHuman.SelectedHoldItem);
  (LocalHuman.SelectedHoldItem as TEquipment).AssignedSlotData :=
      ((LocalHuman.SelectedHoldItem as TEquipment).AssignedSlotData and EquipmentSecondaryFireFlag)
          or Slot;
  (LocalHuman.SelectedHoldItem as TEquipment).Equip;
  if LocalHuman.SelectedHoldItem is TWeapon then
    (LocalHuman.SelectedHoldItem as TWeapon).Target := nil;
  MissileWarning :=
      (LocalHuman.PlayerHoldShip is TTranclucator)
          and (LocalHuman.SelectedHoldItem is TWeapon)
          and (Byte(TWeapon(LocalHuman.SelectedHoldItem).GetWeaponInfo.ShotType)
              in [Ord(wstTorpedo)..Ord(wstRocket)])
          and (LocalHuman.PlayerHoldShip.GetRadar = nil);
  LocalHuman.SelectedHoldKind := phkEmpty;
  LocalHuman.SelectedHoldItem := nil;
  if Item <> nil then
  begin
    LocalHuman.PlayerHoldShip.Inventory.Delete(LocalHuman.PlayerHoldShip.Inventory.IndexOf(Item));
    LocalHuman.SelectedHoldKind := phkEquipment;
    LocalHuman.SelectedHoldOrigin := 0;
    LocalHuman.SelectedHoldSlot := -(Slot + 1);
    LocalHuman.SelectedHoldUsesDisplayOrder := False;
    LocalHuman.SelectedHoldItem := Item;
  end;
end;

function EquipHeld(ItemType: Byte; Slot: Integer): Boolean;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckEquipHeld);
  AddInt(Command, ItemType);
  AddInt(Command, Slot);
  MissileWarning := False;
  SubmitCommand(Command);
  Result := MissileWarning;
end;

// Moved from TfShip2.ArtefactSlotMouseDown.
procedure ExecuteEquipHeldArtefact(const Command: TPlayerCommand);
var
  Slot: Integer;
  Equipment: TEquipment;
begin
  RequireHeldItem(Command);
  Slot := IntArg(Command, 0);
  Equipment := LocalHuman.PlayerHoldShip.FindEquippedItemInSlot(Ord(t_Artefact), Slot);
  if (Equipment <> nil) and (Equipment.EquippedFlag <> 0) then
    Equipment.Unequip;
  LocalHuman.PlayerHoldShip.Artefacts.Add(LocalHuman.SelectedHoldItem);
  (LocalHuman.SelectedHoldItem as TEquipment).AssignedSlotData := Slot;
  (LocalHuman.SelectedHoldItem as TEquipment).EquippedFlag := 0;
  (LocalHuman.SelectedHoldItem as TEquipment).Equip;
  LocalHuman.SelectedHoldKind := phkEmpty;
  LocalHuman.SelectedHoldItem := nil;
  if Equipment <> nil then
  begin
    LocalHuman.PlayerHoldShip.Artefacts.Delete(LocalHuman.PlayerHoldShip.Artefacts.IndexOf(Equipment));
    LocalHuman.SelectedHoldKind := phkArtefact;
    LocalHuman.SelectedHoldOrigin := 0;
    LocalHuman.SelectedHoldSlot := -(Slot + 1);
    LocalHuman.SelectedHoldUsesDisplayOrder := False;
    LocalHuman.SelectedHoldItem := Equipment;
  end;
end;

procedure EquipHeldArtefact(Slot: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckEquipHeldArtefact);
  AddInt(Command, Slot);
  SubmitCommand(Command);
end;

var
  PutOutcome: TPutOutcome;

// Moved from TfShip2.RemoteHoldItemMouseDown: held goods put into a hold cell, after the
// screen asked how many.
procedure ExecutePutHeldGoods(const Command: TPlayerCommand);
var
  Index, J, Count, Missing, ActionResult: Integer;
  Expanded: Boolean;
  Entry, Swap: TPlayerHoldUnit;
begin
  if LocalHuman.SelectedHoldKind <> phkGoods then
    raise Exception.Create('PutHeldGoods needs held goods');
  Index := IntArg(Command, 0);
  Expanded := IntArg(Command, 1) <> 0;
  Count := IntArg(Command, 2);
  Entry := FindHoldEntry(Index, Expanded);
  PutOutcome := poPlaced;
  if (Entry <> nil) and (Entry.Kind in [phkEquipment, phkArtefact]) then
  begin
    if Entry.Item.ScriptItem <> nil then
      ActionResult :=
          TScriptItem(Entry.Item.ScriptItem)
              .RunActionCode(
                  satOnAnotherGoods,
                  LocalHuman.PlayerHoldShip,
                  TObject(LocalHuman.SelectedGoodsIndex),
                  TObject(Count),
                  0)
    else
      ActionResult :=
          RunItemConfigActionCode(
              Entry.Item,
              satOnAnotherGoods,
              LocalHuman.PlayerHoldShip,
              TObject(LocalHuman.SelectedGoodsIndex),
              TObject(Count),
              0
          );
    if ActionResult <> 0 then
    begin
      Count := Min(Count, Abs(ActionResult));
      if Count < LocalHuman.SelectedGoodsQuantity then
      begin
        Dec(LocalHuman.SelectedGoodsCost, Round(Count / LocalHuman.SelectedGoodsQuantity * LocalHuman.SelectedGoodsCost));
        Dec(LocalHuman.SelectedGoodsQuantity, Count);
      end
      else
      begin
        LocalHuman.SelectedHoldKind := phkEmpty;
        LocalHuman.SelectedGoodsQuantity := 0;
        LocalHuman.SelectedGoodsCost := 0;
      end;
      LocalHuman.PlayerHoldShip.RefreshDerivedStats(True);
      PutOutcome := poScript;
      HeldActionResult := ActionResult;
      Exit;
    end;
  end;
  Inc(LocalHuman.PlayerHoldShip.CargoGoods[LocalHuman.SelectedGoodsIndex].Count, Count);
  Inc(
      LocalHuman.PlayerHoldShip.CargoGoods[LocalHuman.SelectedGoodsIndex].TotalCost,
      Round(Count / LocalHuman.SelectedGoodsQuantity * LocalHuman.SelectedGoodsCost)
  );
  if not Expanded then
  begin
    if Entry = nil then
    begin
      Missing := Index - LocalHuman.PlayerHoldEntries.Count + 1;
      for J := 0 to Missing - 1 do
      begin
        Entry := TPlayerHoldUnit.Create;
        LocalHuman.PlayerHoldEntries.Add(Entry);
        Entry.Kind := phkEmpty;
      end;
      Entry := TPlayerHoldUnit(LocalHuman.PlayerHoldEntries[LocalHuman.PlayerHoldEntries.Count - 1]);
    end
    else
    begin
      if Entry.Kind <> phkEmpty then
      begin
        Entry := TPlayerHoldUnit.Create;
        LocalHuman.PlayerHoldEntries.Insert(Index, Entry);
        Entry.Kind := phkEmpty;
      end;
    end;
    Entry.DisplayOrder := FindFreePlayerHoldOrder;
    Entry.Kind := phkGoods;
    Entry.GoodsIndex := LocalHuman.SelectedGoodsIndex;
    Dec(LocalHuman.SelectedGoodsCost, Round(Count / LocalHuman.SelectedGoodsQuantity * LocalHuman.SelectedGoodsCost));
    Dec(LocalHuman.SelectedGoodsQuantity, Count);
    RemoveEmptyPlayerHoldSlot(LocalHuman.PlayerHoldEntries.IndexOf(Entry) + 1);
    if LocalHuman.SelectedGoodsQuantity <= 0 then
      LocalHuman.SelectedHoldKind := phkEmpty
    else
      ReturnHeldEntryInside;
  end
  else
  begin
    Swap := nil;
    if Entry = nil then
    begin
      Entry := TPlayerHoldUnit.Create;
      LocalHuman.PlayerHoldEntries.Add(Entry);
    end
    else
    begin
      if Entry.Kind <> phkEmpty then
      begin
        Swap := Entry;
        Entry := TPlayerHoldUnit.Create;
        LocalHuman.PlayerHoldEntries.Add(Entry);
      end;
    end;
    Entry.DisplayOrder := Index;
    Entry.Kind := phkGoods;
    Entry.GoodsIndex := LocalHuman.SelectedGoodsIndex;
    Dec(LocalHuman.SelectedGoodsCost, Round(Count / LocalHuman.SelectedGoodsQuantity * LocalHuman.SelectedGoodsCost));
    Dec(LocalHuman.SelectedGoodsQuantity, Count);
    if Swap <> nil then
    begin
      if LocalHuman.SelectedGoodsQuantity > 0 then
        RaiseWideMessage('move goods');
      TakeHoldEntry(Swap, Index, Expanded);
    end
    else if LocalHuman.SelectedGoodsQuantity <= 0 then
    begin
      LocalHuman.SelectedHoldKind := phkEmpty;
      LocalHuman.SelectedHoldItem := nil;
    end
    else
      ReturnHeldEntryInside;
    RestorePlayerHoldDisplayOrder;
  end;
  for J := LocalHuman.PlayerHoldEntries.Count - 1 downto 0 do
  begin
    Swap := TPlayerHoldUnit(LocalHuman.PlayerHoldEntries[J]);
    if (Swap.Kind = phkGoods) and (LocalHuman.SelectedGoodsIndex = Swap.GoodsIndex) and (Entry <> Swap) then
    begin
      if not Expanded then
      begin
        Swap.Item := nil;
        Swap.Kind := phkEmpty;
      end
      else
      begin
        LocalHuman.PlayerHoldEntries.Delete(J);
        Swap.Free;
      end;
    end;
  end;
  LocalHuman.PlayerHoldShip.RefreshDerivedStats(True);
end;

function PutHeldGoods(Index: Integer; Expanded: Boolean; Count: Integer): TPutOutcome;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckPutHeldGoods);
  AddHoldCell(Command, Index, Expanded);
  AddInt(Command, Count);
  SubmitCommand(Command);
  Result := PutOutcome;
end;

// Moved from TfShip2.RemoteHoldItemMouseDown: part of a held stack put into a hold cell, or
// all of it into a cell whose stack it merges with. RunScripts is whether the screen shows
// the hold (not a quick action), where item scripts may take the stack first.
procedure ExecutePutHeldStack(const Command: TPlayerCommand);
var
  Index, J, Count, Missing, ActionResult: Integer;
  Expanded, RunScripts: Boolean;
  Entry, Swap: TPlayerHoldUnit;
  Stack: TCountableItem;
begin
  RequireHeldItem(Command);
  Index := IntArg(Command, 0);
  Expanded := IntArg(Command, 1) <> 0;
  Count := IntArg(Command, 2);
  RunScripts := IntArg(Command, 3) <> 0;
  Entry := FindHoldEntry(Index, Expanded);
  PutOutcome := poAborted;
  if RunScripts
      and (LocalHuman.SelectedHoldOrigin = 0)
      and (Entry <> nil)
      and (Entry.Item <> nil)
      and (Entry.Kind in [phkEquipment, phkArtefact])
      and not TCountableItem(LocalHuman.SelectedHoldItem).CanMerge(Entry.Item) then
  begin
    ActionResult := 0;
    if LocalHuman.SelectedHoldItem.ScriptItem <> nil then
      ActionResult :=
          TScriptItem(LocalHuman.SelectedHoldItem.ScriptItem)
              .RunActionCode(satOnAnotherItem, LocalHuman.PlayerHoldShip, Entry.Item, nil, ActionResult);
    if Entry.Item.ScriptItem <> nil then
      ActionResult :=
          TScriptItem(Entry.Item.ScriptItem)
              .RunActionCode(
                  satOnAnotherItem2,
                  LocalHuman.PlayerHoldShip,
                  LocalHuman.SelectedHoldItem,
                  nil,
                  ActionResult);
    if Entry.Item is TEquipmentWithActCode then
      ActionResult :=
          RunItemConfigActionCode(
              Entry.Item,
              satOnAnotherItem2,
              LocalHuman.PlayerHoldShip,
              LocalHuman.SelectedHoldItem,
              nil,
              ActionResult
          );
    if ActionResult in [1, 3] then
    begin
      LocalHuman.SelectedHoldItem.Free;
      LocalHuman.SelectedHoldKind := phkEmpty;
      LocalHuman.SelectedHoldItem := nil;
    end;
    if ActionResult in [1..3] then
    begin
      LocalHuman.PlayerHoldShip.RefreshDerivedStats(True);
      PutOutcome := poScript;
      HeldActionResult := ActionResult;
      Exit;
    end;
    Count := TCountableItem(LocalHuman.SelectedHoldItem).StackCount;
  end;
  if (Count < 1) or (TCountableItem(LocalHuman.SelectedHoldItem).StackCount < Count) then
    Exit;
  if Count < TCountableItem(LocalHuman.SelectedHoldItem).StackCount then
  begin
    Stack := TCountableItem(LocalHuman.SelectedHoldItem).Split(Count);
    if (Entry <> nil) and (Entry.Item <> nil) and Stack.CanMerge(Entry.Item) then
    begin
      TCountableItem(Entry.Item).Merge(Stack);
      Stack.Free;
      ReturnHeldEntryInside;
      PutOutcome := poMergedReturned;
      Exit;
    end;
    LocalHuman.PlayerHoldShip.Inventory.Add(Stack);
  end
  else
  begin
    Stack := TCountableItem(LocalHuman.SelectedHoldItem);
    LocalHuman.SelectedHoldKind := phkEmpty;
    LocalHuman.SelectedHoldItem := nil;
    if (Entry <> nil) and (Entry.Item <> nil) and Stack.CanMerge(Entry.Item) then
    begin
      TCountableItem(Entry.Item).Merge(Stack);
      Stack.Free;
      LocalHuman.SelectedHoldItem := nil;
      LocalHuman.SelectedHoldKind := phkEmpty;
      PutOutcome := poMerged;
      Exit;
    end;
    LocalHuman.PlayerHoldShip.Inventory.Add(Stack);
  end;
  PutOutcome := poPlaced;
  if not Expanded then
  begin
    if Entry = nil then
    begin
      Missing := Index - LocalHuman.PlayerHoldEntries.Count + 1;
      for J := 0 to Missing - 1 do
      begin
        Entry := TPlayerHoldUnit.Create;
        LocalHuman.PlayerHoldEntries.Add(Entry);
        Entry.Kind := phkEmpty;
      end;
      Entry := TPlayerHoldUnit(LocalHuman.PlayerHoldEntries[LocalHuman.PlayerHoldEntries.Count - 1]);
    end
    else
    begin
      if Entry.Kind <> phkEmpty then
      begin
        Entry := TPlayerHoldUnit.Create;
        LocalHuman.PlayerHoldEntries.Insert(Index, Entry);
        Entry.Kind := phkEmpty;
      end;
    end;
    Entry.DisplayOrder := FindFreePlayerHoldOrder;
    Entry.Kind := phkEquipment;
    Entry.ItemId := Stack.Id;
    Entry.Item := Stack;
    RemoveEmptyPlayerHoldSlot(LocalHuman.PlayerHoldEntries.IndexOf(Entry) + 1);
    if LocalHuman.SelectedHoldItem <> nil then
      ReturnHeldEntryInside;
  end
  else
  begin
    Swap := nil;
    if Entry = nil then
    begin
      Entry := TPlayerHoldUnit.Create;
      LocalHuman.PlayerHoldEntries.Add(Entry);
    end
    else
    begin
      if Entry.Kind <> phkEmpty then
      begin
        Swap := Entry;
        Entry := TPlayerHoldUnit.Create;
        LocalHuman.PlayerHoldEntries.Add(Entry);
      end;
    end;
    Entry.DisplayOrder := Index;
    Entry.Kind := phkEquipment;
    Entry.ItemId := Stack.Id;
    Entry.Item := Stack;
    if Swap <> nil then
    begin
      if TCountableItem(LocalHuman.SelectedHoldItem).StackCount > 0 then
        RaiseWideMessage('move protoplasm');
      TakeHoldEntry(Swap, Index, Expanded);
    end
    else if LocalHuman.SelectedHoldItem <> nil then
      ReturnHeldEntryInside;
    RestorePlayerHoldDisplayOrder;
  end;
  for J := 0 to LocalHuman.PlayerHoldEntries.Count - 1 do
  begin
    Swap := TPlayerHoldUnit(LocalHuman.PlayerHoldEntries[J]);
    if (Swap.Kind = phkEquipment) and (Entry.Item as TCountableItem).Merge(Swap.Item) then
    begin
      LocalHuman.PlayerHoldShip.Inventory.Delete(LocalHuman.PlayerHoldShip.Inventory.IndexOf(Swap.Item));
      Swap.Item.Free;
      Swap.Item := nil;
      Swap.Kind := phkEmpty;
    end;
  end;
  LocalHuman.PlayerHoldShip.RefreshDerivedStats(True);
end;

function PutHeldStack(
    Index: Integer;
    Expanded: Boolean;
    Count: Integer;
    RunScripts: Boolean
): TPutOutcome;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckPutHeldStack);
  AddHoldCell(Command, Index, Expanded);
  AddInt(Command, Count);
  AddInt(Command, Ord(RunScripts));
  SubmitCommand(Command);
  Result := PutOutcome;
end;

// Moved from TfShip2.RemoteHoldItemMouseDown.
procedure ExecutePutHeldEquipment(const Command: TPlayerCommand);
var
  Index, J, Count: Integer;
  Expanded: Boolean;
  Entry, Swap: TPlayerHoldUnit;
begin
  RequireHeldItem(Command);
  Index := IntArg(Command, 0);
  Expanded := IntArg(Command, 1) <> 0;
  Entry := FindHoldEntry(Index, Expanded);
  if LocalHuman.SelectedHoldItem is TWeapon then
    (LocalHuman.SelectedHoldItem as TWeapon).Target := nil;
  LocalHuman.PlayerHoldShip.Inventory.Add(LocalHuman.SelectedHoldItem);
  (LocalHuman.SelectedHoldItem as TEquipment).EquippedFlag := 0;
  if not Expanded then
  begin
    if Entry = nil then
    begin
      Count := Index - LocalHuman.PlayerHoldEntries.Count + 1;
      for J := 0 to Count - 1 do
      begin
        Entry := TPlayerHoldUnit.Create;
        LocalHuman.PlayerHoldEntries.Add(Entry);
        Entry.Kind := phkEmpty;
      end;
      Entry := TPlayerHoldUnit(LocalHuman.PlayerHoldEntries[LocalHuman.PlayerHoldEntries.Count - 1]);
    end
    else
    begin
      if Entry.Kind <> phkEmpty then
      begin
        Entry := TPlayerHoldUnit.Create;
        LocalHuman.PlayerHoldEntries.Insert(Index, Entry);
        Entry.Kind := phkEmpty;
      end;
    end;
    Entry.DisplayOrder := FindFreePlayerHoldOrder;
    Entry.Kind := phkEquipment;
    Entry.ItemId := LocalHuman.SelectedHoldItem.Id;
    Entry.Item := LocalHuman.SelectedHoldItem;
    RemoveEmptyPlayerHoldSlot(LocalHuman.PlayerHoldEntries.IndexOf(Entry) + 1);
    LocalHuman.SelectedHoldKind := phkEmpty;
    LocalHuman.SelectedHoldItem := nil;
  end
  else
  begin
    if (Entry <> nil) and (Entry.Item <> nil) and (Entry.Item.NoDropFlag > 0) then
      Entry := nil;
    Swap := nil;
    if Entry = nil then
    begin
      Entry := TPlayerHoldUnit.Create;
      LocalHuman.PlayerHoldEntries.Add(Entry);
    end
    else
    begin
      if Entry.Kind <> phkEmpty then
      begin
        Swap := Entry;
        Entry := TPlayerHoldUnit.Create;
        LocalHuman.PlayerHoldEntries.Add(Entry);
      end;
    end;
    Entry.DisplayOrder := Index;
    Entry.Kind := phkEquipment;
    Entry.ItemId := LocalHuman.SelectedHoldItem.Id;
    Entry.Item := LocalHuman.SelectedHoldItem;
    if Swap <> nil then
      TakeHoldEntry(Swap, Index, Expanded)
    else
    begin
      LocalHuman.SelectedHoldKind := phkEmpty;
      LocalHuman.SelectedHoldItem := nil;
    end;
    RestorePlayerHoldDisplayOrder;
  end;
  LocalHuman.PlayerHoldShip.RefreshDerivedStats(True);
end;

procedure PutHeldEquipment(Index: Integer; Expanded: Boolean);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckPutHeldEquipment);
  AddHoldCell(Command, Index, Expanded);
  SubmitCommand(Command);
end;

// Moved from TfShip2.RemoteHoldItemMouseDown.
procedure ExecutePutHeldArtefact(const Command: TPlayerCommand);
var
  Index, J, Count: Integer;
  Expanded: Boolean;
  Entry, Swap: TPlayerHoldUnit;
begin
  RequireHeldItem(Command);
  Index := IntArg(Command, 0);
  Expanded := IntArg(Command, 1) <> 0;
  Entry := FindHoldEntry(Index, Expanded);
  LocalHuman.PlayerHoldShip.Artefacts.Add(LocalHuman.SelectedHoldItem);
  (LocalHuman.SelectedHoldItem as TEquipment).EquippedFlag := 0;
  if LocalHuman.SelectedHoldItem is TArtefactTranclucator then
    (TObject((LocalHuman.SelectedHoldItem as TArtefactTranclucator).Ship) as TTranclucator).OwnerShip :=
        Actor(Command);
  if not Expanded then
  begin
    if Entry = nil then
    begin
      Count := Index - LocalHuman.PlayerHoldEntries.Count + 1;
      for J := 0 to Count - 1 do
      begin
        Entry := TPlayerHoldUnit.Create;
        LocalHuman.PlayerHoldEntries.Add(Entry);
        Entry.Kind := phkEmpty;
      end;
      Entry := TPlayerHoldUnit(LocalHuman.PlayerHoldEntries[LocalHuman.PlayerHoldEntries.Count - 1]);
    end
    else
    begin
      if Entry.Kind <> phkEmpty then
      begin
        Entry := TPlayerHoldUnit.Create;
        LocalHuman.PlayerHoldEntries.Insert(Index, Entry);
        Entry.Kind := phkEmpty;
      end;
    end;
    Entry.Kind := phkArtefact;
    Entry.ItemId := LocalHuman.SelectedHoldItem.Id;
    Entry.Item := LocalHuman.SelectedHoldItem;
    RemoveEmptyPlayerHoldSlot(LocalHuman.PlayerHoldEntries.IndexOf(Entry) + 1);
    LocalHuman.SelectedHoldKind := phkEmpty;
    LocalHuman.SelectedHoldItem := nil;
  end
  else
  begin
    if (Entry <> nil) and (Entry.Item <> nil) and (Entry.Item.NoDropFlag > 0) then
      Entry := nil;
    Swap := nil;
    if Entry = nil then
    begin
      Entry := TPlayerHoldUnit.Create;
      LocalHuman.PlayerHoldEntries.Add(Entry);
    end
    else
    begin
      if Entry.Kind <> phkEmpty then
      begin
        Swap := Entry;
        Entry := TPlayerHoldUnit.Create;
        LocalHuman.PlayerHoldEntries.Add(Entry);
      end;
    end;
    Entry.DisplayOrder := Index;
    Entry.Kind := phkArtefact;
    Entry.ItemId := LocalHuman.SelectedHoldItem.Id;
    Entry.Item := LocalHuman.SelectedHoldItem;
    if Swap <> nil then
      TakeHoldEntry(Swap, Index, Expanded)
    else
    begin
      LocalHuman.SelectedHoldKind := phkEmpty;
      LocalHuman.SelectedHoldItem := nil;
    end;
    RestorePlayerHoldDisplayOrder;
  end;
  LocalHuman.PlayerHoldShip.RefreshDerivedStats(True);
end;

procedure PutHeldArtefact(Index: Integer; Expanded: Boolean);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckPutHeldArtefact);
  AddHoldCell(Command, Index, Expanded);
  SubmitCommand(Command);
end;

// Moved from TfShip2.StorageItemMouseUp, after the screen asked how many.
procedure ExecuteStoreHeld(const Command: TPlayerCommand);
var
  P: TPlayer;
  Slot, Count: Integer;
  Item: TItem;
begin
  RequireHeld(Command);
  P := Actor(Command);
  Slot := IntArg(Command, 0);
  Count := IntArg(Command, 1);
  if (LocalHuman.SelectedHoldKind = phkEquipment)
      and (LocalHuman.SelectedHoldItem is TCountableItem)
      and (TCountableItem(LocalHuman.SelectedHoldItem).StackCount >= 1) then
  begin
    Item := (LocalHuman.SelectedHoldItem as TCountableItem).Split(Count);
    P.MergeItemIntoPlayerStorage(Item, GetLocalStorageOwner, Slot);
    if TCountableItem(LocalHuman.SelectedHoldItem).StackCount < 1 then
    begin
      LocalHuman.SelectedHoldItem.Free;
      LocalHuman.SelectedHoldItem := nil;
      LocalHuman.SelectedHoldKind := phkEmpty;
    end;
  end
  else if (LocalHuman.SelectedHoldKind = phkEquipment) or (LocalHuman.SelectedHoldKind = phkArtefact) then
  begin
    if LocalHuman.SelectedHoldItem is TArtefactTranclucator then
      (TObject((LocalHuman.SelectedHoldItem as TArtefactTranclucator).Ship) as TTranclucator).OwnerShip := nil;
    LocalHuman.SelectedHoldKind := phkEmpty;
    P.AddItemToPlayerStorage(LocalHuman.SelectedHoldItem, GetLocalStorageOwner, Slot);
  end
  else if LocalHuman.SelectedHoldKind = phkGoods then
  begin
    P.AddGoodsToPlayerStorage(
        LocalHuman.SelectedGoodsIndex,
        Count,
        Round(Count / LocalHuman.SelectedGoodsQuantity * LocalHuman.SelectedGoodsCost),
        GetLocalStorageOwner,
        Slot
    );
    Dec(LocalHuman.SelectedGoodsCost, Round(Count / LocalHuman.SelectedGoodsQuantity * LocalHuman.SelectedGoodsCost));
    Dec(LocalHuman.SelectedGoodsQuantity, Count);
    if LocalHuman.SelectedGoodsQuantity < 1 then
      LocalHuman.SelectedHoldKind := phkEmpty;
  end;
end;

procedure StoreHeld(Slot: Integer; Count: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckStoreHeld);
  AddInt(Command, Slot);
  AddInt(Command, Count);
  SubmitCommand(Command);
end;

procedure ExecuteCloseVacantStorageSlot(const Command: TPlayerCommand);
begin
  Actor(Command).CloseVacantStorageSlot(GetLocalStorageOwner, IntArg(Command, 0));
end;

procedure CloseVacantStorageSlot(Slot: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckCloseVacantStorageSlot);
  AddInt(Command, Slot);
  SubmitCommand(Command);
end;

// Moved from TfShip2.EquipmentSlotMouseDown, ArtefactSlotMouseDown (UseOnArtefactSlot) and
// HullMouseDown: item scripts that take held goods.
procedure ExecuteUseHeldGoodsOn(const Command: TPlayerCommand);
var
  Item: TItem;
  Quantity, ActionResult: Integer;
begin
  if LocalHuman.SelectedHoldKind <> phkGoods then
    raise Exception.Create('UseHeldGoodsOn needs held goods');
  ActionResult := 0;
  case IntArg(Command, 0) of
    hsEquipmentSlot:
    begin
      Item := LocalHuman.PlayerHoldShip.FindEquippedItemInSlot(IntArg(Command, 1), IntArg(Command, 2));
      if Item.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(Item.ScriptItem)
                .RunActionCode(
                    satOnAnotherGoods,
                    LocalHuman.PlayerHoldShip,
                    TObject(LocalHuman.SelectedGoodsIndex),
                    TObject(LocalHuman.SelectedGoodsQuantity),
                    0);
    end;
    hsArtefactSlot:
    begin
      Item := LocalHuman.PlayerHoldShip.FindEquippedItemInSlot(Ord(t_Artefact), IntArg(Command, 1));
      if Item.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(Item.ScriptItem)
                .RunActionCode(
                    satOnAnotherGoods,
                    LocalHuman.PlayerHoldShip,
                    TObject(LocalHuman.SelectedGoodsIndex),
                    TObject(LocalHuman.SelectedGoodsQuantity),
                    0)
      else
        ActionResult :=
            RunItemConfigActionCode(
                Item,
                satOnAnotherGoods,
                LocalHuman.PlayerHoldShip,
                TObject(LocalHuman.SelectedGoodsIndex),
                TObject(LocalHuman.SelectedGoodsQuantity),
                0
            );
    end;
    hsHull:
    begin
      if LocalHuman.PlayerHoldShip.GetHull.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(LocalHuman.PlayerHoldShip.GetHull.ScriptItem)
                .RunActionCode(
                    satOnAnotherGoods,
                    LocalHuman.PlayerHoldShip,
                    TObject(LocalHuman.SelectedGoodsIndex),
                    TObject(LocalHuman.SelectedGoodsQuantity),
                    0);
    end;
  else
    raise Exception.Create('UseHeldGoodsOn names an unknown target');
  end;
  if ActionResult <> 0 then
  begin
    Quantity := Abs(ActionResult);
    if Quantity < LocalHuman.SelectedGoodsQuantity then
    begin
      Dec(LocalHuman.SelectedGoodsCost, Round(Quantity / LocalHuman.SelectedGoodsQuantity * LocalHuman.SelectedGoodsCost));
      Dec(LocalHuman.SelectedGoodsQuantity, Quantity);
    end
    else
    begin
      LocalHuman.SelectedHoldKind := phkEmpty;
      LocalHuman.SelectedGoodsQuantity := 0;
      LocalHuman.SelectedGoodsCost := 0;
    end;
  end;
  LocalHuman.PlayerHoldShip.RefreshDerivedStats(True);
  HeldActionResult := ActionResult;
end;

function UseHeldGoodsOn(Site: Integer; A: Integer; B: Integer): Integer;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckUseHeldGoodsOn);
  AddInt(Command, Site);
  AddInt(Command, A);
  AddInt(Command, B);
  SubmitCommand(Command);
  Result := HeldActionResult;
end;

// Moved from TfShip2.EquipmentSlotMouseDown, UseOnArtefactSlot, RemoteHoldItemMouseDown and
// HullMouseDown: the scripts of the held item and of the item it is used on. Each place
// runs them slightly differently; the code keeps each one.
procedure ExecuteUseHeldItemOn(const Command: TPlayerCommand);
var
  Site, ActionResult: Integer;
  Item: TItem;
  Entry: TPlayerHoldUnit;
begin
  RequireHeldItem(Command);
  Site := IntArg(Command, 0);
  ActionResult := 0;
  case Site of
    hsEquipmentSlot:
    begin
      Item := LocalHuman.PlayerHoldShip.FindEquippedItemInSlot(IntArg(Command, 1), IntArg(Command, 2));
      if LocalHuman.SelectedHoldItem.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(LocalHuman.SelectedHoldItem.ScriptItem)
                .RunActionCode(satOnAnotherItem, LocalHuman.PlayerHoldShip, Item, nil, ActionResult);
      if LocalHuman.SelectedHoldItem is TEquipmentWithActCode then
        ActionResult :=
            RunItemConfigActionCode(
                LocalHuman.SelectedHoldItem,
                satOnAnotherItem,
                LocalHuman.PlayerHoldShip,
                Item,
                nil,
                ActionResult
            );
      if Item.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(Item.ScriptItem)
                .RunActionCode(
                    satOnAnotherItem2,
                    LocalHuman.PlayerHoldShip,
                    LocalHuman.SelectedHoldItem,
                    nil,
                    ActionResult);
      if Item is TEquipmentWithActCode then
        ActionResult :=
            RunItemConfigActionCode(
                Item,
                satOnAnotherItem2,
                LocalHuman.PlayerHoldShip,
                LocalHuman.SelectedHoldItem,
                nil,
                ActionResult
            );
    end;
    hsArtefactSlot:
    begin
      Item := LocalHuman.PlayerHoldShip.FindEquippedItemInSlot(Ord(t_Artefact), IntArg(Command, 1));
      if LocalHuman.SelectedHoldItem.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(LocalHuman.SelectedHoldItem.ScriptItem)
                .RunActionCode(satOnAnotherItem, LocalHuman.PlayerHoldShip, Item, nil, ActionResult);
      if LocalHuman.SelectedHoldItem is TEquipmentWithActCode then
        ActionResult :=
            RunItemConfigActionCode(
                LocalHuman.SelectedHoldItem,
                satOnAnotherItem,
                LocalHuman.PlayerHoldShip,
                Item,
                nil,
                ActionResult
            );
      if Item.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(Item.ScriptItem)
                .RunActionCode(
                    satOnAnotherItem2,
                    LocalHuman.PlayerHoldShip,
                    LocalHuman.SelectedHoldItem,
                    nil,
                    ActionResult);
      ActionResult :=
          RunItemConfigActionCode(
              Item,
              satOnAnotherItem2,
              LocalHuman.PlayerHoldShip,
              LocalHuman.SelectedHoldItem,
              nil,
              ActionResult
          );
    end;
    hsHoldEquipment:
    begin
      Entry := HoldEntryArg(Command, 1);
      if LocalHuman.SelectedHoldItem.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(LocalHuman.SelectedHoldItem.ScriptItem)
                .RunActionCode(satOnAnotherItem, LocalHuman.PlayerHoldShip, Entry.Item, nil, ActionResult);
      if LocalHuman.SelectedHoldItem is TEquipmentWithActCode then
        ActionResult :=
            RunItemConfigActionCode(
                LocalHuman.SelectedHoldItem,
                satOnAnotherItem,
                LocalHuman.PlayerHoldShip,
                Entry.Item,
                nil,
                ActionResult
            );
      if Entry.Item.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(Entry.Item.ScriptItem)
                .RunActionCode(
                    satOnAnotherItem2,
                    LocalHuman.PlayerHoldShip,
                    LocalHuman.SelectedHoldItem,
                    nil,
                    ActionResult);
      if Entry.Item is TEquipmentWithActCode then
        ActionResult :=
            RunItemConfigActionCode(
                Entry.Item,
                satOnAnotherItem2,
                LocalHuman.PlayerHoldShip,
                LocalHuman.SelectedHoldItem,
                nil,
                ActionResult
            );
    end;
    hsHoldArtefact:
    begin
      Entry := HoldEntryArg(Command, 1);
      if LocalHuman.SelectedHoldItem.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(LocalHuman.SelectedHoldItem.ScriptItem)
                .RunActionCode(satOnAnotherItem, LocalHuman.PlayerHoldShip, Entry.Item, nil, ActionResult);
      ActionResult :=
          RunItemConfigActionCode(
              LocalHuman.SelectedHoldItem,
              satOnAnotherItem,
              LocalHuman.PlayerHoldShip,
              Entry.Item,
              nil,
              ActionResult
          );
      if Entry.Item.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(Entry.Item.ScriptItem)
                .RunActionCode(
                    satOnAnotherItem2,
                    LocalHuman.PlayerHoldShip,
                    LocalHuman.SelectedHoldItem,
                    nil,
                    ActionResult);
      if Entry.Item is TEquipmentWithActCode then
        ActionResult :=
            RunItemConfigActionCode(
                Entry.Item,
                satOnAnotherItem2,
                LocalHuman.PlayerHoldShip,
                LocalHuman.SelectedHoldItem,
                nil,
                ActionResult
            );
    end;
    hsHull:
    begin
      if LocalHuman.SelectedHoldItem.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(LocalHuman.SelectedHoldItem.ScriptItem)
                .RunActionCode(
                    satOnAnotherItem,
                    LocalHuman.PlayerHoldShip,
                    LocalHuman.PlayerHoldShip.GetHull,
                    nil,
                    ActionResult);
      if LocalHuman.SelectedHoldItem is TEquipmentWithActCode then
        ActionResult :=
            RunItemConfigActionCode(
                LocalHuman.SelectedHoldItem,
                satOnAnotherItem,
                LocalHuman.PlayerHoldShip,
                LocalHuman.PlayerHoldShip.GetHull,
                nil,
                ActionResult
            );
      if LocalHuman.PlayerHoldShip.GetHull.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(LocalHuman.PlayerHoldShip.GetHull.ScriptItem)
                .RunActionCode(
                    satOnAnotherItem2,
                    LocalHuman.PlayerHoldShip,
                    LocalHuman.SelectedHoldItem,
                    nil,
                    ActionResult);
    end;
  else
    raise Exception.Create('UseHeldItemOn names an unknown target');
  end;
  if ActionResult in [1, 3] then
  begin
    LocalHuman.SelectedHoldItem.Free;
    LocalHuman.SelectedHoldKind := phkEmpty;
    LocalHuman.SelectedHoldItem := nil;
  end;
  if (Site in [hsEquipmentSlot, hsArtefactSlot]) or (ActionResult in [1..3]) then
    LocalHuman.PlayerHoldShip.RefreshDerivedStats(True);
  HeldActionResult := ActionResult;
end;

function UseHeldItemOn(Site: Integer; A: Integer; B: Integer): Integer;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckUseHeldItemOn);
  AddInt(Command, Site);
  AddInt(Command, A);
  AddInt(Command, B);
  SubmitCommand(Command);
  Result := HeldActionResult;
end;

function TargetEquipment(const Command: TPlayerCommand; Index: Integer): TEquipment;
begin
  case IntArg(Command, Index) of
    hsEquipmentSlot:
      Result :=
          LocalHuman.PlayerHoldShip.FindEquippedItemInSlot(
              IntArg(Command, Index + 1),
              IntArg(Command, Index + 2)
          );
    hsHoldEquipment:
      Result := TEquipment(HoldEntryArg(Command, Index + 1).Item);
    hsHull:
      Result := LocalHuman.PlayerHoldShip.GetHull;
  else
    raise Exception.Create(CommandKindName(Command.Kind) + ' names an unknown target');
  end;
  if Result = nil then
    raise Exception.Create(CommandKindName(Command.Kind) + ' names a missing item');
end;

// Moved from TfShip2.EquipmentSlotMouseDown, RemoteHoldItemMouseDown and HullMouseDown,
// which run the same code on their item.
procedure ExecuteInstallHeldMicroModule(const Command: TPlayerCommand);
var
  Item: TEquipment;
begin
  RequireHeldItem(Command);
  Item := TargetEquipment(Command, 0);
  LocalHuman.PlayerHoldShip.ScriptItemsAct(satOnPlayerUseMM, Item, LocalHuman.SelectedHoldItem, 0);
  ApplyMicroModule((LocalHuman.SelectedHoldItem as TMicroModule).MicroModuleIndex - 1, Item);
  LocalHuman.SelectedHoldItem.Free;
  LocalHuman.SelectedHoldKind := phkEmpty;
  LocalHuman.SelectedHoldItem := nil;
  LocalHuman.PlayerHoldShip.RefreshDerivedStats(True);
end;

procedure InstallHeldMicroModule(Site: Integer; A: Integer; B: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckInstallHeldMicroModule);
  AddInt(Command, Site);
  AddInt(Command, A);
  AddInt(Command, B);
  SubmitCommand(Command);
end;

// Moved from TfShip2.EquipmentSlotMouseDown and RemoteHoldItemMouseDown.
procedure ExecuteTransferHeldFuel(const Command: TPlayerCommand);
var
  Item: TEquipment;
  Count: Integer;
  FuelFrom, FuelTo: TFuelTanks;
begin
  RequireHeldItem(Command);
  Item := TargetEquipment(Command, 0);
  case IntArg(Command, 3) of
    hfCisternToCistern:
    begin
      Count :=
          Min(
              (LocalHuman.SelectedHoldItem as TCistern).Fuel,
              (Item as TCistern).Capacity - (Item as TCistern).Fuel
          );
      Dec((LocalHuman.SelectedHoldItem as TCistern).Fuel, Count);
      Inc((Item as TCistern).Fuel, Count);
    end;
    hfFuelTanksToFuelTanks:
    begin
      FuelFrom := LocalHuman.SelectedHoldItem as TFuelTanks;
      FuelTo := Item as TFuelTanks;
      Count := Min(FuelFrom.Fuel, FuelTo.Capacity - FuelTo.Fuel);
      Dec(FuelFrom.Fuel, Count);
      Inc(FuelTo.Fuel, Count);
    end;
    hfCisternToFuelTanks:
    begin
      Count :=
          Min(
              (LocalHuman.SelectedHoldItem as TCistern).Fuel,
              (Item as TFuelTanks).Capacity - (Item as TFuelTanks).Fuel
          );
      Dec((LocalHuman.SelectedHoldItem as TCistern).Fuel, Count);
      Inc((Item as TFuelTanks).Fuel, Count);
    end;
    hfFuelTanksToCistern:
    begin
      Count :=
          Min(
              (LocalHuman.SelectedHoldItem as TFuelTanks).Fuel,
              (Item as TCistern).Capacity - (Item as TCistern).Fuel
          );
      Dec((LocalHuman.SelectedHoldItem as TFuelTanks).Fuel, Count);
      Inc((Item as TCistern).Fuel, Count);
    end;
  else
    raise Exception.Create('TransferHeldFuel names an unknown transfer');
  end;
  LocalHuman.PlayerHoldShip.RefreshDerivedStats(True);
end;

procedure TransferHeldFuel(Site: Integer; A: Integer; B: Integer; Mode: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckTransferHeldFuel);
  AddInt(Command, Site);
  AddInt(Command, A);
  AddInt(Command, B);
  AddInt(Command, Mode);
  SubmitCommand(Command);
end;

// Moved from TfShip2.HullMouseDown.
procedure ExecuteChangeHull(const Command: TPlayerCommand);
var
  P: TPlayer;
  OldHull: THull;
begin
  RequireHeldItem(Command);
  P := Actor(Command);
  LocalHuman.PlayerHoldShip
      .ScriptItemsAct(satOnPlayerChangeHull, LocalHuman.SelectedHoldItem, LocalHuman.PlayerHoldShip.GetHull, 0);
  OldHull := LocalHuman.PlayerHoldShip.GetHull;
  LocalHuman.PlayerHoldShip.Inventory.Insert(0, LocalHuman.SelectedHoldItem);
  LocalHuman.PlayerHoldShip.Hull := LocalHuman.SelectedHoldItem as THull;
  LocalHuman.PlayerHoldShip.GetHull.OwnerShip := LocalHuman.PlayerHoldShip;
  LocalHuman.PlayerHoldShip.GetHull.AssignedSlotData := 0;
  LocalHuman.PlayerHoldShip.GetHull.EquippedFlag := 1;
  LocalHuman.SelectedHoldKind := phkEmpty;
  LocalHuman.SelectedHoldItem := nil;
  if OldHull <> nil then
  begin
    OldHull.OwnerShip := nil;
    LocalHuman.PlayerHoldShip.Inventory.Delete(LocalHuman.PlayerHoldShip.Inventory.IndexOf(OldHull));
    P.AddItemToPlayerStorage(OldHull, GetLocalStorageOwner, -1);
  end;
  if LocalHuman.PlayerHoldShip.GetHull.ScriptItem <> nil then
    TScriptItem(LocalHuman.PlayerHoldShip.GetHull.ScriptItem)
        .RunActionCode(satOnPlayerChangeHull, LocalHuman.PlayerHoldShip, LocalHuman.PlayerHoldShip.GetHull, OldHull, 0);
  LocalHuman.PlayerHoldShip.RefreshAssignedItemSlots;
  LocalHuman.PlayerHoldShip.RebuildEquipmentCache;
  LocalHuman.PlayerHoldShip.RefreshDerivedStats(True);
  if not LocalHuman.PlayerHoldShip.ScriptChameleon then
  begin
    ReleaseSpaceObject(LocalHuman.PlayerHoldShip.Graphic);
    LocalHuman.PlayerHoldShip.RefreshGraphic;
  end;
end;

procedure ChangeHull;
begin
  SubmitCommand(NewCommand(ckChangeHull));
end;

var
  DropBlock: TDropBlock;

// Moved from TfShip2.DropSelectedOutside, after the screen asked how many. A tranclucator
// forgets its owner before the checks, as it did; the screen shows why a drop failed.
procedure ExecuteDropHeld(const Command: TPlayerCommand);
var
  P: TPlayer;
  Item: TItem;
  Goods: TGoods;
  Angle: Double;
  Effect: TWeaponSE;
  Entry: PEFilmEndEntry;
  Quantity, I, Index: Integer;
  ActionResult: Integer;
begin
  RequireHeld(Command);
  P := Actor(Command);
  Quantity := IntArg(Command, 0);
  DropBlock := dbNone;
  if (LocalHuman.SelectedHoldKind = phkEquipment)
      and (LocalHuman.SelectedHoldItem is TCountableItem)
      and (TCountableItem(LocalHuman.SelectedHoldItem).StackCount > 1) then
  begin
    Item := TCountableItem(LocalHuman.SelectedHoldItem).Split(Quantity);
    if (not LocalHuman.PlayerHoldShip.IsOnPlanet and not LocalHuman.PlayerHoldShip.IsDockedToShip)
        or ((P.RuinsMode > 0)
            and (P.RuinsSavedDockedTo = nil)
            and (P.RuinsSavedPlanet = nil)) then
    begin
      with LocalHuman.PlayerHoldShip.CurrentStar do
      begin
        Items.Add(Item);
        Angle :=
            SeededRandomIntRange(
                    0,
                    360,
                    LocalHuman.PlayerHoldShip.CurrentStar.GenerationSeed * Galaxy.CurrentTurn * Item.Id)
                * Pi
                / 180;
        Item.Position.X := Sin(Angle) * 100 + LocalHuman.PlayerHoldShip.Position.X;
        Item.Position.Y := LocalHuman.PlayerHoldShip.Position.Y - Cos(Angle) * 100;
        Item.GetGraphObject.SetPosition(Item.Position);
        if DamageRadius * DamageRadius > Sqr(Item.Position.X) + Sqr(Item.Position.Y) then
        begin
          Effect := TWeaponSE.Create('Weapon.NoGraph', Classes.Point(0, 0), 0, -1);
          Effect.SetEndpoints(nil, Item.GetGraphObject);
          Effect.SetHit(0, 0, True, True);
          if TrailingFilmEffects = nil then
            TrailingFilmEffects := TEFilmEnd.Create;
          Entry := TrailingFilmEffects.AppendEntry;
          RetainSpaceObject(Entry.SceneObject, Effect);
          RetainSpaceObject(Entry.RelatedObject1, Item.GetGraphObject);
          ReleaseSpaceObject(Item.GraphObject);
          Items.Delete(Items.IndexOf(Item));
          Item.Free;
        end;
      end;
    end
    else
      Item.Free;
    if TCountableItem(LocalHuman.SelectedHoldItem).StackCount < 1 then
    begin
      LocalHuman.SelectedHoldItem.Free;
      LocalHuman.SelectedHoldItem := nil;
      LocalHuman.SelectedHoldKind := phkEmpty;
    end;
  end
  else if (LocalHuman.SelectedHoldKind = phkEquipment) or (LocalHuman.SelectedHoldKind = phkArtefact) then
  begin
    if LocalHuman.SelectedHoldItem is TArtefactTranclucator then
      (TObject((LocalHuman.SelectedHoldItem as TArtefactTranclucator).Ship) as TTranclucator).OwnerShip := nil;
    if LocalHuman.PlayerHoldShip is TRuins then
    begin
      if LocalHuman.PlayerHoldShip.NeedsEquipmentType(LocalHuman.SelectedHoldItem.ItemType) then
      begin
        DropBlock := dbRuins;
        Exit;
      end;
    end
    else if LocalHuman.PlayerHoldShip is TTranclucator then
    begin
      if ((LocalHuman.SelectedHoldItem.ItemType = t_FuelTanks) or (LocalHuman.SelectedHoldItem.ItemType = t_Engine))
          and LocalHuman.PlayerHoldShip.NeedsEquipmentType(LocalHuman.SelectedHoldItem.ItemType) then
      begin
        DropBlock := dbTranclucator;
        Exit;
      end;
    end
    else if LocalHuman.SelectedHoldItem.ItemType = t_FuelTanks then
    begin
      if LocalHuman.PlayerHoldShip.GetFuelTanks = nil then
      begin
        DropBlock := dbFuelTanks;
        Exit;
      end;
    end
    else if LocalHuman.SelectedHoldItem.ItemType = t_Engine then
    begin
      if LocalHuman.PlayerHoldShip.GetEngine = nil then
      begin
        DropBlock := dbEngine;
        Exit;
      end;
    end
    else if LocalHuman.SelectedHoldItem.NoDropFlag > 0 then
    begin
      DropBlock := dbNoDrop;
      Exit;
    end;
    if LocalHuman.SelectedHoldItem is TWeapon then
      (LocalHuman.SelectedHoldItem as TWeapon).Target := nil;
    if LocalHuman.PlayerHoldShip.IsOnPlanet
        or (LocalHuman.PlayerHoldShip.IsDockedToShip and (P.RuinsMode = 0))
        or ((P.RuinsMode > 0)
            and ((P.RuinsSavedDockedTo <> nil) or (P.RuinsSavedPlanet <> nil))) then
    begin
      LocalHuman.SelectedHoldItem.Free;
      LocalHuman.SelectedHoldItem := nil;
    end
    else
      with LocalHuman.PlayerHoldShip.CurrentStar do
      begin
        Items.Add(LocalHuman.SelectedHoldItem);
        Angle :=
            SeededRandomIntRange(
                    0,
                    360,
                    LocalHuman.PlayerHoldShip.CurrentStar.GenerationSeed
                        * Galaxy.CurrentTurn
                        * LocalHuman.SelectedHoldItem.Id)
                * Pi
                / 180;
        LocalHuman.SelectedHoldItem.Position.X := Sin(Angle) * 100 + LocalHuman.PlayerHoldShip.Position.X;
        LocalHuman.SelectedHoldItem.Position.Y := LocalHuman.PlayerHoldShip.Position.Y - Cos(Angle) * 100;
        ActionResult := LocalHuman.PlayerHoldShip.ScriptItemsAct(satOnDropItemFixed, LocalHuman.SelectedHoldItem, nil, 0);
        if LocalHuman.SelectedHoldItem is TEquipmentWithActCode then
          ActionResult :=
              RunItemConfigActionCode(
                  LocalHuman.SelectedHoldItem,
                  satOnDropItemFixed,
                  LocalHuman.PlayerHoldShip,
                  LocalHuman.SelectedHoldItem,
                  nil,
                  ActionResult
              );
        if LocalHuman.SelectedHoldItem.ScriptItem <> nil then
          ActionResult :=
              TScriptItem(LocalHuman.SelectedHoldItem.ScriptItem)
                  .RunActionCode(
                      satOnDropItemFixed,
                      LocalHuman.PlayerHoldShip,
                      LocalHuman.SelectedHoldItem,
                      nil,
                      ActionResult);
        if ActionResult = 0 then
        begin
          LocalHuman.SelectedHoldItem.GetGraphObject.SetPosition(LocalHuman.SelectedHoldItem.Position);
          if DamageRadius * DamageRadius
              > Sqr(LocalHuman.SelectedHoldItem.Position.X) + Sqr(LocalHuman.SelectedHoldItem.Position.Y) then
          begin
            Effect := TWeaponSE.Create('Weapon.NoGraph', Classes.Point(0, 0), 0, -1);
            Effect.SetEndpoints(nil, LocalHuman.SelectedHoldItem.GetGraphObject);
            Effect.SetHit(0, 0, True, True);
            if TrailingFilmEffects = nil then
              TrailingFilmEffects := TEFilmEnd.Create;
            Entry := TrailingFilmEffects.AppendEntry;
            RetainSpaceObject(Entry.SceneObject, Effect);
            RetainSpaceObject(Entry.RelatedObject1, LocalHuman.SelectedHoldItem.GetGraphObject);
            Items.Delete(Items.IndexOf(LocalHuman.SelectedHoldItem));
            LocalHuman.SelectedHoldItem.Free;
          end;
        end
        else
        begin
          Items.Delete(Items.IndexOf(LocalHuman.SelectedHoldItem));
          if ActionResult < 0 then
            LocalHuman.SelectedHoldItem.Free;
        end;
      end;
    LocalHuman.SelectedHoldKind := phkEmpty;
    LocalHuman.SelectedHoldItem := nil;
  end
  else if LocalHuman.SelectedHoldKind = phkGoods then
  begin
    if (not LocalHuman.PlayerHoldShip.IsOnPlanet and not LocalHuman.PlayerHoldShip.IsDockedToShip)
        or ((P.RuinsMode > 0)
            and (P.RuinsSavedDockedTo = nil)
            and (P.RuinsSavedPlanet = nil)) then
      with LocalHuman.PlayerHoldShip.CurrentStar do
      begin
        Goods := TGoods.Create;
        Goods.Init(TItemType(LocalHuman.SelectedGoodsIndex), Quantity);
        Goods.Cost := Round(Quantity / LocalHuman.SelectedGoodsQuantity * LocalHuman.SelectedGoodsCost);
        for I := 0 to 20 do
        begin
          Angle :=
              SeededRandomIntRange(
                      0,
                      360,
                      LocalHuman.PlayerHoldShip.CurrentStar.GenerationSeed
                          * Galaxy.CurrentTurn
                          * (LocalHuman.SelectedGoodsIndex + I))
                  * Pi
                  / 180;
          Goods.Position.X := Sin(Angle) * 100 + LocalHuman.PlayerHoldShip.Position.X;
          Goods.Position.Y := LocalHuman.PlayerHoldShip.Position.Y - Cos(Angle) * 100;
          Index := 0;
          while Items.Count > Index do
          begin
            Item := Items[Index];
            if PointDistanceSquared(Item.Position, Goods.Position) < 100 then
              Break;
            Inc(Index);
          end;
          if Items.Count <= Index then
            Break;
        end;
        Items.Add(Goods);
        Goods.GetGraphObject.SetPosition(Goods.Position);
      end;
    Dec(LocalHuman.SelectedGoodsCost, Round(Quantity / LocalHuman.SelectedGoodsQuantity * LocalHuman.SelectedGoodsCost));
    Dec(LocalHuman.SelectedGoodsQuantity, Quantity);
    if LocalHuman.SelectedGoodsQuantity < 1 then
      LocalHuman.SelectedHoldKind := phkEmpty;
  end;
end;

function DropHeld(Quantity: Integer): TDropBlock;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckDropHeld);
  AddInt(Command, Quantity);
  SubmitCommand(Command);
  Result := DropBlock;
end;

// Moved from TfShip2.SellAllItems' SellItem, with the shop grid built again the way
// OpenShopStock builds it. The screen sounds the sale.
function SellItem(
    P: TPlayer;
    Item: TItem;
    IgnoreRequiredEquipment: Boolean;
    Columns: Integer
): Boolean;
var
  Count, Cost, Price: Integer;
  Event: TGalaxyEvent;
begin
  Result := False;
  if Item = nil then
    Exit;
  if not IgnoreRequiredEquipment then
  begin
    if LocalHuman.PlayerHoldShip is TRuins then
    begin
      if LocalHuman.PlayerHoldShip.NeedsEquipmentType(Item.ItemType) then
        Exit;
    end
    else if ((Item.ItemType = t_FuelTanks) or (Item.ItemType = t_Engine))
        and LocalHuman.PlayerHoldShip.NeedsEquipmentType(Item.ItemType) then
      Exit;
  end;
  if Item.ItemType in [t_Food..t_Narcotics] then
  begin
    Count := P.CargoGoods[Ord(Item.ItemType)].Count;
    Cost := P.CargoGoods[Ord(Item.ItemType)].TotalCost;
    P.CargoGoods[Ord(Item.ItemType)].Count := (Item as TGoods).Quantity;
    P.CargoGoods[Ord(Item.ItemType)].TotalCost := (Item as TGoods).Cost;
    P.SellGoodsToLocation(Byte(Item.ItemType), (Item as TGoods).Quantity);
    SalePlaySound := True;
    P.CargoGoods[Ord(Item.ItemType)].Count := Count;
    P.CargoGoods[Ord(Item.ItemType)].TotalCost := Cost;
    Item.Free;
  end
  else
  begin
    if not (Item is TCountableItem) then
    begin
      Event := AddGalaxyEvent('PlayerSellsEquipment');
      Event.AddData(Ord(Item.ItemType));
      Event.AddData(Item.CalculateResaleValue(P.GetEffectiveSkillLevel(psTrading)));
      Event.AddData(Item.Weight);
      Event.AddData(Item.Id);
      Event.AddTextData(Item.GetDisplayName);
      Event.AddTextData(Item.GetCategoryConfigName);
    end;
    Price := Item.CalculateResaleValue(P.GetEffectiveSkillLevel(psTrading));
    P.SetMoney(P.Money + Price);
    if Price <> 0 then
      SalePlaySound := True;
    if Item is TWeapon then
      (Item as TWeapon).Target := nil;
    if (Item.ItemType = t_Hull) and ((Item as THull).HullType = htSpecial) then
      Item.Free
    else if (Item.OwnerId in [Ord(oiMaloc)..Ord(oiGaal), Ord(oiPirate)])
        and (Item.ItemType in [t_Hull..t_CustomWeapon])
        and (not (Item is TWeapon)
            or (TWeapon(Item).GetWeaponInfo.Availability <> waNotSoldAndNodeRepair)) then
    begin
      RestoreTemporaryShopStock;
      if P.CurrentPlanet <> nil then
        P.CurrentPlanet.EquipmentShop.Add(Item)
      else
        (P.DockedTo as TRuins).EquipmentShop.Add(Item);
      ShopVisibleColumnCount := Columns;
      BuildTemporaryShopSlotGrid;
    end
    else
      Item.Free;
  end;
  Result := True;
  SaleChanged := True;
end;

var
  SalePrice: Integer;

// Moved from TfShip2.SpecialSlot2Clicked, after the screen asked how many. Returning the
// item to the shop builds the shop grid again the way OpenShopStock does.
procedure ExecuteSellHeld(const Command: TPlayerCommand);
var
  P: TPlayer;
  Count, Price, Columns: Integer;
  Item: TItem;
  Event: TGalaxyEvent;
begin
  RequireHeld(Command);
  P := Actor(Command);
  Count := IntArg(Command, 0);
  Columns := IntArg(Command, 1);
  Price := 0;
  if (LocalHuman.SelectedHoldKind = phkEquipment) or (LocalHuman.SelectedHoldKind = phkArtefact) then
  begin
    if (LocalHuman.SelectedHoldItem is TCountableItem)
        and ((LocalHuman.SelectedHoldItem as TCountableItem).StackCount > 1) then
    begin
      Item := (LocalHuman.SelectedHoldItem as TCountableItem).Split(Count);
      Price := Item.CalculateResaleValue(P.GetEffectiveSkillLevel(psTrading));
      P.SetMoney(P.Money + Price);
      Item.Free;
    end
    else
    begin
      Price := LocalHuman.SelectedHoldItem.CalculateResaleValue(P.GetEffectiveSkillLevel(psTrading));
      P.SetMoney(P.Money + Price);
      if LocalHuman.SelectedHoldItem is TCountableItem then
        (LocalHuman.SelectedHoldItem as TCountableItem).StackCount := 0;
    end;
    if not (LocalHuman.SelectedHoldItem is TCountableItem) then
    begin
      Event := AddGalaxyEvent('PlayerSellsEquipment');
      Event.AddData(Ord(LocalHuman.SelectedHoldItem.ItemType));
      Event.AddData(
          LocalHuman.SelectedHoldItem.CalculateResaleValue(P.GetEffectiveSkillLevel(psTrading))
      );
      Event.AddData(LocalHuman.SelectedHoldItem.Weight);
      Event.AddData(LocalHuman.SelectedHoldItem.Id);
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
      Event.AddTextData(LocalHuman.SelectedHoldItem.GetDisplayName);
      Event.AddTextData(LocalHuman.SelectedHoldItem.GetCategoryConfigName);
    end;
    if LocalHuman.SelectedHoldItem is TWeapon then
      (LocalHuman.SelectedHoldItem as TWeapon).Target := nil;
    if (LocalHuman.SelectedHoldKind = phkEquipment)
        and (LocalHuman.SelectedHoldItem.ItemType = t_Hull)
        and ((LocalHuman.SelectedHoldItem as THull).HullType = htSpecial) then
    begin
      LocalHuman.SelectedHoldItem.Free;
      LocalHuman.SelectedHoldItem := nil;
    end
    else if (LocalHuman.SelectedHoldItem.OwnerId in [Ord(oiMaloc)..Ord(oiGaal), Ord(oiPirate)])
        and (LocalHuman.SelectedHoldKind = phkEquipment)
        and (LocalHuman.SelectedHoldItem.ItemType in [t_Hull..t_CustomWeapon])
        and (not (LocalHuman.SelectedHoldItem is TWeapon)
            or (TWeapon(LocalHuman.SelectedHoldItem).GetWeaponInfo.Availability
                <> waNotSoldAndNodeRepair)) then
    begin
      RestoreTemporaryShopStock;
      if P.CurrentPlanet <> nil then
        P.CurrentPlanet.EquipmentShop.Add(LocalHuman.SelectedHoldItem)
      else
        (P.DockedTo as TRuins).EquipmentShop.Add(LocalHuman.SelectedHoldItem);
      ShopVisibleColumnCount := Columns;
      BuildTemporaryShopSlotGrid;
    end
    else if not (LocalHuman.SelectedHoldItem is TCountableItem)
        or ((LocalHuman.SelectedHoldItem as TCountableItem).StackCount = 0) then
    begin
      LocalHuman.SelectedHoldItem.Free;
      LocalHuman.SelectedHoldItem := nil;
    end;
    if (LocalHuman.SelectedHoldItem = nil)
        or not (LocalHuman.SelectedHoldItem is TCountableItem)
        or ((LocalHuman.SelectedHoldItem as TCountableItem).StackCount = 0) then
    begin
      LocalHuman.SelectedHoldItem := nil;
      LocalHuman.SelectedHoldKind := phkEmpty;
    end;
  end
  else if LocalHuman.SelectedHoldKind = phkGoods then
  begin
    Inc(P.CargoGoods[LocalHuman.SelectedGoodsIndex].Count, LocalHuman.SelectedGoodsQuantity);
    Inc(P.CargoGoods[LocalHuman.SelectedGoodsIndex].TotalCost, LocalHuman.SelectedGoodsCost);
    P.SellGoodsToLocation(LocalHuman.SelectedGoodsIndex, Count);
    LocalHuman.SelectedHoldKind := phkEmpty;
  end;
  SalePrice := Price;
end;

function SellHeld(Count: Integer): Integer;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckSellHeld);
  AddInt(Command, Count);
  AddInt(Command, ShopVisibleColumnCount);
  SubmitCommand(Command);
  Result := SalePrice;
end;

// Puts the held item into a free slot of its kind, as the services do after they repaired
// or reloaded it. Moved from TfShip2.SpecialSlot3Clicked and LoadRockets.
procedure EquipHeldInFreeSlot;
var
  I: Integer;
begin
  I := 0;
  while I < LocalHuman.PlayerHoldShip.GetSlotCountForItemType(Byte(LocalHuman.SelectedHoldItem.ItemType)) do
  begin
    if LocalHuman.PlayerHoldShip.FindEquippedItemInSlot(Byte(LocalHuman.SelectedHoldItem.ItemType), I) = nil then
      Break;
    Inc(I);
  end;
  if I < LocalHuman.PlayerHoldShip.GetSlotCountForItemType(Byte(LocalHuman.SelectedHoldItem.ItemType)) then
  begin
    if LocalHuman.SelectedHoldItem is TWeapon then
      (LocalHuman.SelectedHoldItem as TWeapon).Target := nil;
    LocalHuman.PlayerHoldShip.Inventory.Add(LocalHuman.SelectedHoldItem);
    (LocalHuman.SelectedHoldItem as TEquipment).AssignedSlotData :=
        ((LocalHuman.SelectedHoldItem as TEquipment).AssignedSlotData and EquipmentSecondaryFireFlag)
            or I;
    (LocalHuman.SelectedHoldItem as TEquipment).EquippedFlag := 0;
    (LocalHuman.SelectedHoldItem as TEquipment).Equip;
    LocalHuman.SelectedHoldKind := phkEmpty;
    LocalHuman.SelectedHoldItem := nil;
  end;
end;

// Moved from TfShip2.SpecialSlot1Clicked, after the screen checked the money and asked for
// the nodes.
procedure ExecuteRepairHeld(const Command: TPlayerCommand);
var
  P: TPlayer;
  I, Nodes: Integer;
begin
  RequireHeldItem(Command);
  P := Actor(Command);
  Nodes := IntArg(Command, 0);
  if Nodes > 0 then
    P.ConsumeAvailableNodes(Nodes, LocalHuman.PlayerHoldShip);
  P.SetMoney(P.Money - (LocalHuman.SelectedHoldItem as TEquipment).CalculateRepairCost);
  (LocalHuman.SelectedHoldItem as TEquipment).Repair;
  if LocalHuman.SelectedHoldKind = phkEquipment then
    EquipHeldInFreeSlot
  else if (LocalHuman.SelectedHoldKind = phkArtefact)
      and (not LocalHuman.PlayerHoldShip.HasEquippedArtefactOfSameUseGroup(LocalHuman.SelectedHoldItem)
          or Galaxy.AreDuplicateArtefactsEnabled) then
  begin
    I := 0;
    while I < LocalHuman.PlayerHoldShip.GetSlotCountForItemType(Byte(LocalHuman.SelectedHoldItem.ItemType)) do
    begin
      if LocalHuman.PlayerHoldShip.FindEquippedItemInSlot(Byte(LocalHuman.SelectedHoldItem.ItemType), I) = nil then
        Break;
      Inc(I);
    end;
    if I < LocalHuman.PlayerHoldShip.GetSlotCountForItemType(Byte(LocalHuman.SelectedHoldItem.ItemType)) then
    begin
      LocalHuman.PlayerHoldShip.Artefacts.Add(LocalHuman.SelectedHoldItem);
      if (LocalHuman.PlayerHoldShip.GetSlotCountForItemType(Byte(LocalHuman.SelectedHoldItem.ItemType))
              <= Integer((LocalHuman.SelectedHoldItem as TEquipment).AssignedSlotData))
          or (LocalHuman.PlayerHoldShip.FindEquippedItemInSlot(
                  Byte(LocalHuman.SelectedHoldItem.ItemType),
                  Integer((LocalHuman.SelectedHoldItem as TEquipment).AssignedSlotData))
              <> nil) then
        (LocalHuman.SelectedHoldItem as TEquipment).AssignedSlotData := I;
      (LocalHuman.SelectedHoldItem as TEquipment).EquippedFlag := 0;
      (LocalHuman.SelectedHoldItem as TEquipment).Equip;
      LocalHuman.SelectedHoldKind := phkEmpty;
      LocalHuman.SelectedHoldItem := nil;
    end;
  end;
end;

procedure RepairHeld(Nodes: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckRepairHeld);
  AddInt(Command, Nodes);
  SubmitCommand(Command);
end;

// Moved from TfShip2.SpecialSlot3Clicked, after the screen checked the money and asked how
// much.
procedure ExecuteRefuelHeld(const Command: TPlayerCommand);
var
  P: TPlayer;
  Amount, Cost: Integer;
begin
  RequireHeldItem(Command);
  P := Actor(Command);
  Amount := IntArg(Command, 0);
  if P.IsOnPlanet then
    Cost := CalculateRoundedFuelCost(Amount, P.CurrentPlanet.OwnerId)
  else
    Cost := CalculateRoundedFuelCost(Amount, 6);
  if P.Money < Cost then
    raise Exception.Create('RefuelHeld: not enough money');
  P.SetMoney(P.Money - Cost);
  if LocalHuman.SelectedHoldItem is TCistern then
    Inc((LocalHuman.SelectedHoldItem as TCistern).Fuel, Amount)
  else
    Inc((LocalHuman.SelectedHoldItem as TFuelTanks).Fuel, Amount);
end;

procedure RefuelHeld(Amount: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckRefuelHeld);
  AddInt(Command, Amount);
  SubmitCommand(Command);
end;

// Moved from TfShip2.SpecialSlot3Clicked, after the screen checked the money and asked how
// much.
procedure ExecuteReloadHeld(const Command: TPlayerCommand);
var
  P: TPlayer;
  Amount, Cost: Integer;
  UnitPrice: Single;
  Weapon: TWeapon;
begin
  RequireHeldItem(Command);
  P := Actor(Command);
  Amount := IntArg(Command, 0);
  Weapon := LocalHuman.SelectedHoldItem as TWeapon;
  UnitPrice := Galaxy.ScaleIntByTechLevel(10, 100);
  Cost := Round(Amount * UnitPrice);
  if P.Money < Cost then
    raise Exception.Create('ReloadHeld: not enough money');
  P.SetMoney(P.Money - Cost);
  Inc(Weapon.Ammo, Amount);
  EquipHeldInFreeSlot;
end;

procedure ReloadHeld(Amount: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckReloadHeld);
  AddInt(Command, Amount);
  SubmitCommand(Command);
end;

var
  RepairAllPaid: Boolean;

// Moved from TfShip2.RepairAllClicked, after the screen checked the money and asked for the
// nodes; Nodes is 0 when it did not take them. The costs are computed again the same way.
procedure ExecuteRepairAll(const Command: TPlayerCommand);
var
  P: TPlayer;
  I, Cost, NodeCost, Nodes: Integer;
  Item: TEquipment;
begin
  P := Actor(Command);
  Nodes := IntArg(Command, 0);
  RepairedItems := nil;
  RepairAllPaid := False;
  Cost := 0;
  NodeCost := 0;
  for I := 0 to LocalHuman.PlayerHoldShip.Inventory.Count - 1 do
  begin
    Item := LocalHuman.PlayerHoldShip.Inventory[I];
    if LocalHuman.PlayerHoldShip.CanRepairEquipmentTech(Item)
        and (Item <> LocalHuman.SelectedHoldItem)
        and ((Item.EquippedFlag <> 0) or (Item is THull))
        and Item.NeedsRepair then
      if (Item is TWeapon)
          and (TWeapon(Item).GetWeaponInfo.Availability = waNotSoldAndNodeRepair) then
        Inc(NodeCost, Item.CalculateRepairCost)
      else
        Inc(Cost, Item.CalculateRepairCost);
  end;
  if not P.CanRepairArtefactsAtLocation then
    NodeCost := 0;
  if (NodeCost > 0) and (Nodes <> 0) then
    P.ConsumeAvailableNodes(Nodes, LocalHuman.PlayerHoldShip);
  if Nodes <> 0 then
    Inc(Cost, NodeCost);
  if Cost > 0 then
  begin
    RepairAllPaid := True;
    P.SetMoney(P.Money - Cost);
    for I := 0 to LocalHuman.PlayerHoldShip.Inventory.Count - 1 do
    begin
      Item := LocalHuman.PlayerHoldShip.Inventory[I];
      if LocalHuman.PlayerHoldShip.CanRepairEquipmentTech(Item)
          and (not (Item is TWeapon)
              or (TWeapon(Item).GetWeaponInfo.Availability <> waNotSoldAndNodeRepair)
              or (Nodes <> 0))
          and (Item <> LocalHuman.SelectedHoldItem)
          and ((Item.EquippedFlag <> 0) or (Item is THull))
          and Item.NeedsRepair then
      begin
        Item.Repair;
        SetLength(RepairedItems, Length(RepairedItems) + 1);
        RepairedItems[High(RepairedItems)] := Item;
      end;
    end;
    if LocalHuman.SelectedHoldKind = phkEquipment then
      EquipHeldInFreeSlot
    else if (LocalHuman.SelectedHoldKind = phkArtefact)
        and (not LocalHuman.PlayerHoldShip.HasEquippedArtefactOfSameUseGroup(LocalHuman.SelectedHoldItem)
            or Galaxy.AreDuplicateArtefactsEnabled) then
    begin
      LocalHuman.PlayerHoldShip.Artefacts.Add(LocalHuman.SelectedHoldItem);
      (LocalHuman.SelectedHoldItem as TEquipment).AssignedSlotData := 0;
      (LocalHuman.SelectedHoldItem as TEquipment).EquippedFlag := 0;
      (LocalHuman.SelectedHoldItem as TEquipment).Equip;
      LocalHuman.SelectedHoldKind := phkEmpty;
      LocalHuman.SelectedHoldItem := nil;
    end;
  end;
end;

function RepairAll(Nodes: Integer): Boolean;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckRepairAll);
  AddInt(Command, Nodes);
  SubmitCommand(Command);
  Result := RepairAllPaid;
end;

// Moved from TfShip2.LoadRockets, after the screen checked the money and asked; the cost is
// computed again the same way.
procedure ExecuteBuyRockets(const Command: TPlayerCommand);
var
  P: TPlayer;
  I, Cost, Quantity: Integer;
  Item: TEquipment;
  Equipped: Boolean;
  Event: TGalaxyEvent;
begin
  P := Actor(Command);
  Equipped := IntArg(Command, 0) <> 0;
  Cost := 0;
  for I := 0 to LocalHuman.PlayerHoldShip.Inventory.Count - 1 do
  begin
    Item := LocalHuman.PlayerHoldShip.Inventory[I];
    if (Equipped = Boolean(Item.EquippedFlag))
        and (Item <> LocalHuman.SelectedHoldItem)
        and (Item is TWeapon)
        and (Item as TWeapon).NeedsAmmo then
      Inc(Cost, (Item as TWeapon).CalculateAmmoRefillCost);
  end;
  if P.Money < Cost then
    raise Exception.Create('BuyRockets: not enough money');
  P.SetMoney(P.Money - Cost);
  Quantity := 0;
  for I := 0 to LocalHuman.PlayerHoldShip.Inventory.Count - 1 do
  begin
    Item := LocalHuman.PlayerHoldShip.Inventory[I];
    if (Equipped = Boolean(Item.EquippedFlag))
        and (Item <> LocalHuman.SelectedHoldItem)
        and (Item is TWeapon)
        and (Item as TWeapon).NeedsAmmo then
    begin
      Quantity := Quantity + (Item as TWeapon).AmmoCapacity - (Item as TWeapon).Ammo;
      (Item as TWeapon).Ammo := (Item as TWeapon).AmmoCapacity;
    end;
  end;
  Event := AddGalaxyEvent('PlayerBuysMissiles');
  Event.AddData(Cost);
  Event.AddData(Quantity);
  if LocalHuman.SelectedHoldKind = phkEquipment then
    EquipHeldInFreeSlot
  else if (LocalHuman.SelectedHoldKind = phkArtefact)
      and (not LocalHuman.PlayerHoldShip.HasEquippedArtefactOfSameUseGroup(LocalHuman.SelectedHoldItem)
          or Galaxy.AreDuplicateArtefactsEnabled) then
  begin
    LocalHuman.PlayerHoldShip.Artefacts.Add(LocalHuman.SelectedHoldItem);
    (LocalHuman.SelectedHoldItem as TEquipment).AssignedSlotData := 0;
    (LocalHuman.SelectedHoldItem as TEquipment).EquippedFlag := 0;
    (LocalHuman.SelectedHoldItem as TEquipment).Equip;
    LocalHuman.SelectedHoldKind := phkEmpty;
    LocalHuman.SelectedHoldItem := nil;
  end;
end;

procedure BuyRockets(Equipped: Boolean);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckBuyRockets);
  AddInt(Command, Ord(Equipped));
  SubmitCommand(Command);
end;

var
  UseItemResult: Integer;

// Moved from TfShip2.UseMouseUp: the item was held and went back first (ReturnHeldEntry).
procedure ExecuteUseItem(const Command: TPlayerCommand);
begin
  UseItemResult := RunItemUseCode(ShownItemArg(Command, 0), LocalHuman.PlayerHoldShip);
end;

function UseItem(Item: TItem): Integer;
var
  Command: TPlayerCommand;
begin
  // An item that did not go back to the ship or the storage cannot be named; its script runs
  // unrecorded, and the command log then writes a checkpoint.
  if FindShownItem(Item.Id) <> Item then
    Exit(RunItemUseCode(Item, LocalHuman.PlayerHoldShip));
  Command := NewCommand(ckUseItem);
  AddInt(Command, Item.Id);
  SubmitCommand(Command);
  Result := UseItemResult;
end;

// Moved from TfShip2.UseMouseUp. The text is the page the screen's resources show.
procedure ExecuteShowTreasureMap(const Command: TPlayerCommand);
begin
  if not (LocalHuman.SelectedHoldItem is TTreasureMap) then
    raise Exception.Create('ShowTreasureMap needs a held treasure map');
  AddOrUpdatePlayerBubble(
      7,
      Galaxy.CurrentTurn,
      Command.Text,
      (LocalHuman.SelectedHoldItem as TTreasureMap).GetTargetPlanetName
  );
end;

procedure ShowTreasureMap(const Text: WideString);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckShowTreasureMap);
  Command.Text := Text;
  SubmitCommand(Command);
end;

// Moved from TfShip2.SellAllItems: the loose equipment in the hold.
procedure ExecuteSellHoldInventory(const Command: TPlayerCommand);
var
  P: TPlayer;
  I: Integer;
  Item: TItem;
begin
  P := Actor(Command);
  I := LocalHuman.PlayerHoldShip.Inventory.Count - 1;
  while I >= 0 do
  begin
    Item := LocalHuman.PlayerHoldShip.Inventory[I];
    if (Item.NoDropFlag = 0)
        and (Item.ItemType <> t_Hull)
        and (TEquipment(Item).EquippedFlag = 0)
        and ((Item.ScriptItem = nil) or TScriptItem(Item.ScriptItem).CanSell)
        and P.CanAccessStoredItem(Item) then
      if SellItem(P, Item, False, IntArg(Command, 0)) then
        LocalHuman.PlayerHoldShip.Inventory.Delete(I);
    Dec(I);
  end;
end;

procedure SellHoldInventory;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckSellHoldInventory);
  AddInt(Command, ShopVisibleColumnCount);
  SubmitCommand(Command);
end;

// Moved from TfShip2.SellAllItems: one loose artefact, after the screen asked about a
// tranclucator.
procedure ExecuteSellHoldArtefact(const Command: TPlayerCommand);
var
  Index: Integer;
  Item: TItem;
begin
  Index := IntArg(Command, 0);
  if (Index < 0) or (Index >= LocalHuman.PlayerHoldShip.Artefacts.Count) then
    raise Exception.Create('SellHoldArtefact names a missing artefact');
  Item := LocalHuman.PlayerHoldShip.Artefacts[Index];
  if Item.Id <> IntArg(Command, 1) then
    raise Exception.Create('SellHoldArtefact names another artefact');
  LocalHuman.PlayerHoldShip.Artefacts.Delete(Index);
  SellItem(Actor(Command), Item, True, IntArg(Command, 2));
end;

procedure SellHoldArtefact(Index: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckSellHoldArtefact);
  AddInt(Command, Index);
  AddInt(Command, TItem(LocalHuman.PlayerHoldShip.Artefacts[Index]).Id);
  AddInt(Command, ShopVisibleColumnCount);
  SubmitCommand(Command);
end;

// Moved from TfShip2.SellAllItems: the goods of one kind in the hold, after the screen asked
// about illegal goods.
procedure ExecuteSellHoldGoods(const Command: TPlayerCommand);
var
  P: TPlayer;
  Good: Byte;
  SavedCount, SavedCost: Integer;
begin
  P := Actor(Command);
  Good := IntArg(Command, 0);
  SaleChanged := True;
  SalePlaySound := True;
  if P = LocalHuman.PlayerHoldShip then
    P.SellGoodsToLocation(Good, P.CargoGoods[Good].Count)
  else
  begin
    SavedCount := P.CargoGoods[Good].Count;
    SavedCost := P.CargoGoods[Good].TotalCost;
    P.CargoGoods[Good].Count := LocalHuman.PlayerHoldShip.CargoGoods[Good].Count;
    P.CargoGoods[Good].TotalCost := LocalHuman.PlayerHoldShip.CargoGoods[Good].TotalCost;
    LocalHuman.PlayerHoldShip.CargoGoods[Good].Count := 0;
    LocalHuman.PlayerHoldShip.CargoGoods[Good].TotalCost := 0;
    P.SellGoodsToLocation(Good, P.CargoGoods[Good].Count);
    P.CargoGoods[Good].Count := SavedCount;
    P.CargoGoods[Good].TotalCost := SavedCost;
  end;
end;

procedure SellHoldGoods(Good: Byte);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckSellHoldGoods);
  AddInt(Command, Good);
  SubmitCommand(Command);
end;

// Moved from TfShip2.SellAllItems: one stored item, after the screen asked.
procedure ExecuteSellStoredItem(const Command: TPlayerCommand);
var
  P: TPlayer;
  Index: Integer;
  Entry: PStorageEntry;
  Item: TItem;
begin
  P := Actor(Command);
  Index := IntArg(Command, 0);
  if (Index < 0) or (Index >= P.StorageEntries.Count) then
    raise Exception.Create('SellStoredItem names a missing storage entry');
  Entry := P.StorageEntries[Index];
  Item := Entry.Item;
  if (Item = nil) or (Item.Id <> IntArg(Command, 1)) then
    raise Exception.Create('SellStoredItem names another item');
  Entry.Item := nil;
  P.StorageEntries.Delete(Index);
  Dispose(Entry);
  SellItem(P, Item, True, IntArg(Command, 2));
end;

procedure SellStoredItem(StorageIndex: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckSellStoredItem);
  AddInt(Command, StorageIndex);
  AddInt(Command, PStorageEntry(GetPlayer.StorageEntries[StorageIndex]).Item.Id);
  AddInt(Command, ShopVisibleColumnCount);
  SubmitCommand(Command);
end;

var
  StorageMoved: Boolean;

// Moved from TfShip2.StorageToShipClicked.
procedure ExecuteTakeAllFromStorage(const Command: TPlayerCommand);
begin
  StorageMoved := LocalHuman.PlayerHoldShip.RetrieveStoredItems(GetLocalStorageOwner);
end;

function TakeAllFromStorage: Boolean;
begin
  SubmitCommand(NewCommand(ckTakeAllFromStorage));
  Result := StorageMoved;
end;

// Moved from TfShip2.ShipToStorageClicked.
procedure ExecutePutAllIntoStorage(const Command: TPlayerCommand);
begin
  StorageMoved := LocalHuman.PlayerHoldShip.StoreLooseInventoryAt(GetLocalStorageOwner);
end;

function PutAllIntoStorage: Boolean;
begin
  SubmitCommand(NewCommand(ckPutAllIntoStorage));
  Result := StorageMoved;
end;

// Moved from TfShip2.SortStorage.
procedure ExecuteSortStorage(const Command: TPlayerCommand);
var
  P: TPlayer;
  Sort: TPlayerHoldSort;
  I, J, Count: Integer;
  Entry: PStorageEntry;
  LeftIndex, RightIndex: Integer;
begin
  P := Actor(Command);
  Sort := TPlayerHoldSort(IntArg(Command, 0));
  Count := P.StorageEntries.Count;
  I := 0;
  J := 0;
  while I < Count do
  begin
    Entry := P.StorageEntries[I];
    if GetLocalStorageOwner = Entry.LocationOwner then
    begin
      if Entry.Item = nil then
      begin
        P.StorageEntries.Delete(I);
        Dispose(Entry);
        Dec(Count);
        Continue;
      end;
      Entry.SlotIndex := J;
      Inc(J);
    end;
    Inc(I);
  end;
  Count := P.GetStorageSlotExtent(GetLocalStorageOwner);
  for I := 0 to Count - 2 do
    for J := I + 1 to Count - 1 do
    begin
      LeftIndex := P.FindStorageIndexByLocationAndSlot(GetLocalStorageOwner, I);
      RightIndex := P.FindStorageIndexByLocationAndSlot(GetLocalStorageOwner, J);
      if (LeftIndex >= 0) and (RightIndex >= 0) then
        if CompareStoredItems(
                P.StorageEntries[LeftIndex],
                P.StorageEntries[RightIndex],
                Sort)
            > 0 then
        begin
          Entry := P.StorageEntries[LeftIndex];
          Entry.SlotIndex := J;
          Entry := P.StorageEntries[RightIndex];
          Entry.SlotIndex := I;
        end;
    end;
end;

procedure SortStorageEntries(Sort: TPlayerHoldSort);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckSortStorage);
  AddInt(Command, Ord(Sort));
  SubmitCommand(Command);
end;

procedure ExecuteSortHold(const Command: TPlayerCommand);
begin
  SortPlayerHoldEntries(TPlayerHoldSort(IntArg(Command, 0)));
end;

procedure SortHold(Sort: TPlayerHoldSort);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckSortHold);
  AddInt(Command, Ord(Sort));
  SubmitCommand(Command);
end;

procedure ExecuteRemoveEmptyHoldSlots(const Command: TPlayerCommand);
begin
  RemoveEmptyPlayerHoldSlots;
end;

procedure RemoveEmptyHoldSlots;
begin
  SubmitCommand(NewCommand(ckRemoveEmptyHoldSlots));
end;

// Moved from TfShip2.TrainSkillClicked.
procedure ExecuteTrainSkill(const Command: TPlayerCommand);
begin
  LocalHuman.PlayerHoldShip.TrainSkill(TPilotSkill(IntArg(Command, 0)));
  if CanUsePlayerExperience then
    Actor(Command).FreeExperience := LocalHuman.PlayerHoldShip.FreeExperience;
end;

procedure TrainHoldSkill(Skill: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckTrainSkill);
  AddInt(Command, Skill);
  SubmitCommand(Command);
end;

// Moved from TfShip2.TrainSkillClicked: what it ran after it showed the skill.
procedure ExecuteFinishSkillTraining(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  if P = LocalHuman.PlayerHoldShip then
    P.AchievementStats.CheckAllSkillsAchievement;
  LocalHuman.PlayerHoldShip.ScriptItemsAct(satOnPlayerSkillIncrease, nil, nil, 0);
end;

procedure FinishSkillTraining;
begin
  SubmitCommand(NewCommand(ckFinishSkillTraining));
end;

// Moved from TfShip2.ShipNameMouseDown.
procedure ExecuteRenameShip(const Command: TPlayerCommand);
begin
  LocalHuman.PlayerHoldShip.Name := Command.Text;
end;

procedure RenameShip(const Name: WideString);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckRenameShip);
  Command.Text := Name;
  SubmitCommand(Command);
end;

// Moved from TfShip2.ConfigureChameleon.
function ChameleonDialogChoiceToSeries(
    Choice: Integer
): TDominatorSeries; // @addr $700FFC @ida "unsigned __int8 __usercall $name@<al>(int Choice@<eax>, void *ParentFrame@<^0>);" @stackpop 0 @calls "0x7011A4" Nested helper; does not access its parent frame.
begin
  Result := dsBlazer;
  case Choice of
    2: Result := dsBlazer;
    3: Result := dsKeller;
    4: Result := dsTerron;
  end;
end;

// Moved from TfShip2.ConfigureChameleon, after its dialog.
procedure ExecuteApplyChameleonChoice(const Command: TPlayerCommand);
var
  Choice, ExpectedCharges, I: Integer;
  Series: TDominatorSeries;
  Ship: TShip;
begin
  Choice := IntArg(Command, 0);
  if Choice = 1 then
  begin
    LocalHuman.PlayerHoldShip.ChameleonActive := False;
    for I := 0 to LocalHuman.PlayerHoldShip.CurrentStar.Ships.Count - 1 do
    begin
      Ship := TShip(LocalHuman.PlayerHoldShip.CurrentStar.Ships[I]);
      if (Ship <> LocalHuman.PlayerHoldShip)
          and Ship.InNormalSpace
          and not Ship.HasScriptControl
          and (Ship is TNormalShip)
          and (Ship.TypeId <> stPirate) then
        Ship.AssignWeaponTargetsInStar;
    end;
  end
  else
  begin
    Series := ChameleonDialogChoiceToSeries(Choice);
    ExpectedCharges := Max(0, LocalHuman.PlayerHoldShip.ChameleonCharges[Ord(Series)] - 1);
    LocalHuman.PlayerHoldShip.ChameleonCharges[Ord(Series)] := ExpectedCharges;
    LocalHuman.PlayerHoldShip.ChameleonSeries := Series;
    LocalHuman.PlayerHoldShip.ChameleonActive := True;
  end;
  ReleaseSpaceObject(LocalHuman.PlayerHoldShip.Graphic);
  LocalHuman.PlayerHoldShip.RefreshGraphic;
end;

procedure ApplyChameleonChoice(Choice: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckApplyChameleonChoice);
  AddInt(Command, Choice);
  SubmitCommand(Command);
end;

// Moved from TfShip2.MainKeyDown.
procedure ExecuteSaveEquipmentConfiguration(const Command: TPlayerCommand);
begin
  Actor(Command).SaveEquipmentConfiguration(IntArg(Command, 0));
end;

procedure SaveEquipmentConfiguration(Index: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckSaveEquipmentConfiguration);
  AddInt(Command, Index);
  SubmitCommand(Command);
end;

var
  ConfigurationApplied: Boolean;

// Moved from TfShip2.SelectEquipmentConfiguration. Apply is false while Ctrl is down.
procedure ExecuteChooseEquipmentConfiguration(const Command: TPlayerCommand);
var
  P: TPlayer;
  Index: Integer;
begin
  P := Actor(Command);
  Index := IntArg(Command, 0);
  P.SaveEquipmentConfiguration(P.SelectedEquipmentConfiguration);
  P.SelectedEquipmentConfiguration := Index;
  ConfigurationApplied := P.HasEquipmentConfiguration(Index) and (IntArg(Command, 1) <> 0);
  if ConfigurationApplied then
    P.ApplyEquipmentConfiguration(Index);
end;

function ChooseEquipmentConfiguration(Index: Integer; Apply: Boolean): Boolean;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckChooseEquipmentConfiguration);
  AddInt(Command, Index);
  AddInt(Command, Ord(Apply));
  SubmitCommand(Command);
  Result := ConfigurationApplied;
end;

// Moved from TfShip2.ToggleAfterburner and MainKeyDown.
procedure ExecuteSetHoldAfterburner(const Command: TPlayerCommand);
begin
  LocalHuman.PlayerHoldShip.AfterburnerActive := IntArg(Command, 0) <> 0;
  LocalHuman.PlayerHoldShip.RefreshDerivedStats(True);
end;

procedure SetHoldAfterburner(Active: Boolean);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckSetHoldAfterburner);
  AddInt(Command, Ord(Active));
  SubmitCommand(Command);
end;

// Moved verbatim from TfShip2.ShowEquipmentInfo.
procedure RunItemInfoScriptsNow(Item: TItem);
begin
  if Item.ScriptItem <> nil then
    TScriptItem(Item.ScriptItem)
        .RunActionCode(satOnShowingItemInfo, LocalHuman.PlayerHoldShip, nil, nil, 0);
  if Item is TEquipmentWithActCode then
    RunItemConfigActionCode(Item, satOnShowingItemInfo, LocalHuman.PlayerHoldShip, nil, nil, 0);
end;

procedure ExecuteRunItemInfoScripts(const Command: TPlayerCommand);
begin
  RunItemInfoScriptsNow(ShownItemArg(Command, 0));
end;

procedure RunItemInfoScripts(Item: TItem);
var
  Command: TPlayerCommand;
begin
  // An item the screen shows from elsewhere cannot be named; its scripts run unrecorded,
  // and the command log then writes a checkpoint.
  if FindShownItem(Item.Id) <> Item then
  begin
    RunItemInfoScriptsNow(Item);
    Exit;
  end;
  Command := NewCommand(ckRunItemInfoScripts);
  AddInt(Command, Item.Id);
  SubmitCommand(Command);
end;

// Moved from TfShip2.IsCompatibleSlot.
function IsCompatibleSlot(ItemType, SlotType: TItemType): Boolean;
begin
  Result :=
      (ItemType = SlotType)
          or ((ItemType in [t_Weapon1..t_CustomWeapon])
              and (SlotType in [t_Weapon1..t_CustomWeapon]));
end;

// Moved from TfShip2.RefreshShipView: the highlight of each equipment slot, then the hull's.
procedure CheckHeldUsabilityNow(const SlotTypes: array of Byte; HighlightRepairable: Boolean);
var
  I, Slot, SlotCount: Integer;
  Item: TEquipment;
  Highlight: Boolean;
begin
  for I := 0 to 7 do
  begin
    SlotCount := LocalHuman.PlayerHoldShip.GetSlotCountForItemType(SlotTypes[I]);
    SetLength(HeldSlotHighlights[I], SlotCount);
    for Slot := 0 to SlotCount - 1 do
    begin
      Item := LocalHuman.PlayerHoldShip.FindEquippedItemInSlot(SlotTypes[I], Slot);
      if HighlightRepairable
          and (Item <> nil)
          and ((Item.EquippedFlag <> 0) or (Item is THull))
          and Item.NeedsRepair then
        Highlight := True
      else if (LocalHuman.SelectedHoldKind = phkEquipment)
          and (LocalHuman.SelectedHoldItem.ItemType = t_MicroModule)
          and (Item <> nil)
          and (Item.MicroModuleIndex = 0)
          and (LocalHuman.SelectedHoldItem as TMicroModule).CanInstallOn(Item) then
        Highlight := True
      else if (LocalHuman.SelectedHoldKind in [phkEquipment, phkArtefact])
          and (LocalHuman.SelectedHoldItem is TEquipmentWithActCode)
          and (Item <> nil)
          and (RunItemConfigActionCode(
                  LocalHuman.SelectedHoldItem,
                  satOnCheckingUsability,
                  LocalHuman.PlayerHoldShip,
                  Item,
                  nil,
                  0)
              > 0) then
        Highlight := True
      else if (LocalHuman.SelectedHoldKind in [phkEquipment, phkArtefact])
          and (LocalHuman.SelectedHoldItem.ScriptItem <> nil)
          and (Item <> nil)
          and (TScriptItem(LocalHuman.SelectedHoldItem.ScriptItem)
                  .RunActionCode(satOnCheckingUsability, LocalHuman.PlayerHoldShip, Item, nil, 0)
              > 0) then
        Highlight := True
      else if (LocalHuman.SelectedHoldKind in [phkEquipment, phkArtefact])
          and (Item <> nil)
          and (Item is TEquipmentWithActCode)
          and (RunItemConfigActionCode(
                  Item,
                  satOnCheckingUsability2,
                  LocalHuman.PlayerHoldShip,
                  LocalHuman.SelectedHoldItem,
                  nil,
                  0)
              > 0) then
        Highlight := True
      else if (LocalHuman.SelectedHoldKind in [phkEquipment, phkArtefact])
          and (Item <> nil)
          and (Item.ScriptItem <> nil)
          and (TScriptItem(Item.ScriptItem)
                  .RunActionCode(satOnCheckingUsability2, LocalHuman.PlayerHoldShip, LocalHuman.SelectedHoldItem, nil, 0)
              > 0) then
        Highlight := True
      else if (LocalHuman.SelectedHoldKind = phkGoods)
          and (Item <> nil)
          and (Item.ScriptItem <> nil)
          and (TScriptItem(Item.ScriptItem)
                  .RunActionCode(
                      satOnCheckingUsabilityGoods,
                      LocalHuman.PlayerHoldShip,
                      TObject(LocalHuman.SelectedGoodsIndex),
                      TObject(LocalHuman.SelectedGoodsQuantity),
                      0)
              > 0) then
        Highlight := True
      else if (LocalHuman.SelectedHoldKind = phkEquipment)
          and (LocalHuman.SelectedHoldItem.ItemType = t_Cistern)
          and (Item <> nil)
          and (Item.ItemType = t_FuelTanks)
          and ((LocalHuman.SelectedHoldItem as TCistern).Fuel > 0)
          and ((Item as TFuelTanks).Fuel < (Item as TFuelTanks).Capacity) then
        Highlight := True
      else
        Highlight :=
            (LocalHuman.SelectedHoldKind = phkEquipment)
                and IsCompatibleSlot(LocalHuman.SelectedHoldItem.ItemType, TItemType(SlotTypes[I]));
      HeldSlotHighlights[I][Slot] := Highlight;
    end;
  end;
  if (HighlightRepairable and LocalHuman.PlayerHoldShip.GetHull.NeedsRepair) then
    HeldHullHighlight := True
  else if ((LocalHuman.SelectedHoldKind = phkEquipment)
      and (LocalHuman.SelectedHoldItem.ItemType = t_MicroModule)
      and (LocalHuman.PlayerHoldShip.GetHull.MicroModuleIndex = 0)
      and (LocalHuman.SelectedHoldItem as TMicroModule).CanInstallOn(LocalHuman.PlayerHoldShip.GetHull)) then
    HeldHullHighlight := True
  else if ((LocalHuman.SelectedHoldKind in [phkEquipment, phkArtefact])
      and (LocalHuman.SelectedHoldItem is TEquipmentWithActCode)
      and (RunItemConfigActionCode(
              LocalHuman.SelectedHoldItem,
              satOnCheckingUsability,
              LocalHuman.PlayerHoldShip,
              LocalHuman.PlayerHoldShip.GetHull,
              nil,
              0)
          > 0)) then
    HeldHullHighlight := True
  else if ((LocalHuman.SelectedHoldKind in [phkEquipment, phkArtefact])
      and (LocalHuman.SelectedHoldItem.ScriptItem <> nil)
      and (TScriptItem(LocalHuman.SelectedHoldItem.ScriptItem)
              .RunActionCode(satOnCheckingUsability, LocalHuman.PlayerHoldShip, LocalHuman.PlayerHoldShip.GetHull, nil, 0)
          > 0)) then
    HeldHullHighlight := True
  else if ((LocalHuman.SelectedHoldKind in [phkEquipment, phkArtefact])
      and (LocalHuman.PlayerHoldShip.GetHull.ScriptItem <> nil)
      and (TScriptItem(LocalHuman.PlayerHoldShip.GetHull.ScriptItem)
              .RunActionCode(satOnCheckingUsability2, LocalHuman.PlayerHoldShip, LocalHuman.SelectedHoldItem, nil, 0)
          > 0)) then
    HeldHullHighlight := True
  else if ((LocalHuman.SelectedHoldKind = phkGoods)
      and (LocalHuman.PlayerHoldShip.GetHull.ScriptItem <> nil)
      and (TScriptItem(LocalHuman.PlayerHoldShip.GetHull.ScriptItem)
              .RunActionCode(
                  satOnCheckingUsabilityGoods,
                  LocalHuman.PlayerHoldShip,
                  TObject(LocalHuman.SelectedGoodsIndex),
                  TObject(LocalHuman.SelectedGoodsQuantity),
                  0)
          > 0)) then
    HeldHullHighlight := True
  else
    HeldHullHighlight :=
        (LocalHuman.SelectedHoldKind = phkEquipment)
            and (LocalHuman.SelectedHoldItem.ItemType = t_Hull)
            and (LocalHuman.PlayerHoldShip is TNormalShip)
            and (TItem(LocalHuman.PlayerHoldShip.Inventory[0]).NoDropFlag = 0);
end;

// Ints: the flag to highlight repairable equipment, then the eight slot types.
procedure ExecuteCheckHeldUsability(const Command: TPlayerCommand);
var
  SlotTypes: array[0..7] of Byte;
  I: Integer;
begin
  for I := 0 to 7 do
    SlotTypes[I] := Byte(IntArg(Command, 1 + I));
  CheckHeldUsabilityNow(SlotTypes, IntArg(Command, 0) <> 0);
end;

procedure CheckHeldUsability(const SlotTypes: array of Byte; HighlightRepairable: Boolean);
var
  Command: TPlayerCommand;
  I: Integer;
begin
  // With nothing held no script runs, and nothing changes.
  if not (LocalHuman.SelectedHoldKind in [phkEquipment, phkArtefact, phkGoods]) then
  begin
    CheckHeldUsabilityNow(SlotTypes, HighlightRepairable);
    Exit;
  end;
  Command := NewCommand(ckCheckHeldUsability);
  AddInt(Command, Ord(HighlightRepairable));
  for I := 0 to 7 do
    AddInt(Command, SlotTypes[I]);
  SubmitCommand(Command);
end;

// Moved from TfRewards.OnOpen.
procedure ExecuteShowAwards(const Command: TPlayerCommand);
var
  Ship: TShip;
begin
  Ship := RefObject(Command, 0) as TShip;
  if Ship.AwardVisibleCount = 0 then
    Ship.AwardVisibleCount := Ship.AwardIds.Count;
end;

procedure ShowAwards(Ship: TShip);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckShowAwards);
  AddRef(Command, Ship);
  SubmitCommand(Command);
end;

// Moved from TfRewards.AwardMouseDown.
procedure ExecuteExchangeAwards(const Command: TPlayerCommand);
begin
  (RefObject(Command, 0) as TShip).AwardIds.Exchange(IntArg(Command, 0), IntArg(Command, 1));
end;

procedure ExchangeAwards(Ship: TShip; First: Integer; Second: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckExchangeAwards);
  AddRef(Command, Ship);
  AddInt(Command, First);
  AddInt(Command, Second);
  SubmitCommand(Command);
end;

// Moved from TfRewards.IncreaseVisibleCount and DecreaseVisibleCount.
procedure ExecuteChangeAwardVisibleCount(const Command: TPlayerCommand);
var
  Ship: TShip;
begin
  Ship := RefObject(Command, 0) as TShip;
  if IntArg(Command, 0) > 0 then
  begin
    if Ship.AwardVisibleCount < Ship.AwardIds.Count then
      Inc(Ship.AwardVisibleCount);
  end
  else
  begin
    if Ship.AwardVisibleCount > 0 then
      Dec(Ship.AwardVisibleCount);
  end;
end;

procedure ChangeAwardVisibleCount(Ship: TShip; Delta: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckChangeAwardVisibleCount);
  AddRef(Command, Ship);
  AddInt(Command, Delta);
  SubmitCommand(Command);
end;

initialization
  RegisterCommand(ckOpenShipScreen, 'OpenShipScreen', @ExecuteOpenShipScreen);
  RegisterCommand(ckRefreshHoldView, 'RefreshHoldView', @ExecuteRefreshHoldView);
  RegisterCommand(ckLeaveShipScreen, 'LeaveShipScreen', @ExecuteLeaveShipScreen);
  RegisterCommand(ckReturnHeldEntry, 'ReturnHeldEntry', @ExecuteReturnHeldEntry);
  RegisterCommand(ckCloseShipScreen, 'CloseShipScreen', @ExecuteCloseShipScreen);
  RegisterCommand(ckTakeEquipped, 'TakeEquipped', @ExecuteTakeEquipped);
  RegisterCommand(ckTakeArtefact, 'TakeArtefact', @ExecuteTakeArtefact);
  RegisterCommand(ckTakeHoldEntry, 'TakeHoldEntry', @ExecuteTakeHoldEntry);
  RegisterCommand(ckTakeHull, 'TakeHull', @ExecuteTakeHull);
  RegisterCommand(ckTakeStored, 'TakeStored', @ExecuteTakeStored);
  RegisterCommand(ckTakeStoredHull, 'TakeStoredHull', @ExecuteTakeStoredHull);
  RegisterCommand(ckEquipHeld, 'EquipHeld', @ExecuteEquipHeld);
  RegisterCommand(ckEquipHeldArtefact, 'EquipHeldArtefact', @ExecuteEquipHeldArtefact);
  RegisterCommand(ckPutHeldGoods, 'PutHeldGoods', @ExecutePutHeldGoods);
  RegisterCommand(ckPutHeldStack, 'PutHeldStack', @ExecutePutHeldStack);
  RegisterCommand(ckPutHeldEquipment, 'PutHeldEquipment', @ExecutePutHeldEquipment);
  RegisterCommand(ckPutHeldArtefact, 'PutHeldArtefact', @ExecutePutHeldArtefact);
  RegisterCommand(ckStoreHeld, 'StoreHeld', @ExecuteStoreHeld);
  RegisterCommand(ckCloseVacantStorageSlot, 'CloseVacantStorageSlot', @ExecuteCloseVacantStorageSlot);
  RegisterCommand(ckUseHeldGoodsOn, 'UseHeldGoodsOn', @ExecuteUseHeldGoodsOn);
  RegisterCommand(ckUseHeldItemOn, 'UseHeldItemOn', @ExecuteUseHeldItemOn);
  RegisterCommand(ckInstallHeldMicroModule, 'InstallHeldMicroModule', @ExecuteInstallHeldMicroModule);
  RegisterCommand(ckTransferHeldFuel, 'TransferHeldFuel', @ExecuteTransferHeldFuel);
  RegisterCommand(ckChangeHull, 'ChangeHull', @ExecuteChangeHull);
  RegisterCommand(ckDropHeld, 'DropHeld', @ExecuteDropHeld);
  RegisterCommand(ckSellHeld, 'SellHeld', @ExecuteSellHeld);
  RegisterCommand(ckRepairHeld, 'RepairHeld', @ExecuteRepairHeld);
  RegisterCommand(ckRefuelHeld, 'RefuelHeld', @ExecuteRefuelHeld);
  RegisterCommand(ckReloadHeld, 'ReloadHeld', @ExecuteReloadHeld);
  RegisterCommand(ckRepairAll, 'RepairAll', @ExecuteRepairAll);
  RegisterCommand(ckBuyRockets, 'BuyRockets', @ExecuteBuyRockets);
  RegisterCommand(ckUseItem, 'UseItem', @ExecuteUseItem);
  RegisterCommand(ckShowTreasureMap, 'ShowTreasureMap', @ExecuteShowTreasureMap);
  RegisterCommand(ckSellHoldInventory, 'SellHoldInventory', @ExecuteSellHoldInventory);
  RegisterCommand(ckSellHoldArtefact, 'SellHoldArtefact', @ExecuteSellHoldArtefact);
  RegisterCommand(ckSellHoldGoods, 'SellHoldGoods', @ExecuteSellHoldGoods);
  RegisterCommand(ckSellStoredItem, 'SellStoredItem', @ExecuteSellStoredItem);
  RegisterCommand(ckTakeAllFromStorage, 'TakeAllFromStorage', @ExecuteTakeAllFromStorage);
  RegisterCommand(ckPutAllIntoStorage, 'PutAllIntoStorage', @ExecutePutAllIntoStorage);
  RegisterCommand(ckSortStorage, 'SortStorage', @ExecuteSortStorage);
  RegisterCommand(ckSortHold, 'SortHold', @ExecuteSortHold);
  RegisterCommand(ckRemoveEmptyHoldSlots, 'RemoveEmptyHoldSlots', @ExecuteRemoveEmptyHoldSlots);
  RegisterCommand(ckTrainSkill, 'TrainSkill', @ExecuteTrainSkill);
  RegisterCommand(ckFinishSkillTraining, 'FinishSkillTraining', @ExecuteFinishSkillTraining);
  RegisterCommand(ckRenameShip, 'RenameShip', @ExecuteRenameShip);
  RegisterCommand(ckApplyChameleonChoice, 'ApplyChameleonChoice', @ExecuteApplyChameleonChoice);
  RegisterCommand(ckSaveEquipmentConfiguration, 'SaveEquipmentConfiguration', @ExecuteSaveEquipmentConfiguration);
  RegisterCommand(ckChooseEquipmentConfiguration, 'ChooseEquipmentConfiguration', @ExecuteChooseEquipmentConfiguration);
  RegisterCommand(ckSetHoldAfterburner, 'SetHoldAfterburner', @ExecuteSetHoldAfterburner);
  RegisterCommand(ckRunItemInfoScripts, 'RunItemInfoScripts', @ExecuteRunItemInfoScripts);
  RegisterCommand(ckShowAwards, 'ShowAwards', @ExecuteShowAwards);
  RegisterCommand(ckExchangeAwards, 'ExchangeAwards', @ExecuteExchangeAwards);
  RegisterCommand(ckChangeAwardVisibleCount, 'ChangeAwardVisibleCount', @ExecuteChangeAwardVisibleCount);
  RegisterCommand(ckCheckHeldUsability, 'CheckHeldUsability', @ExecuteCheckHeldUsability);
end.
