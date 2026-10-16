{$EXCESSPRECISION OFF}
unit aHoldActions;

// CHANGE: ENHANCEMENT - What a human does on the ship screen (fShip2) and the rewards screen
// (fRewards), as commands (docs/commands.md). The code is moved from the screens; they keep
// their dialogs, sounds, cursors and images.
//
// Picking something up takes it out of the ship or the storage: the item is then in no
// galaxy list and is held by the human (THuman.SelectedHoldKind and the fields after it)
// until a command puts it down, sells, drops or uses it, or returns it (ReturnHeldEntry).
// Commands therefore name the held entry implicitly; they name equipment slots by item type
// and slot index, hold cells by their index in the human's PlayerHoldEntries (or display
// order in the expanded hold) and storage cells by slot, resolved the way the screen resolves
// them. The hold list is the human's, so every change to it, including the refresh the
// screen runs before drawing (RefreshHoldView), is a command too. The ship the screen edits
// is the human's PlayerHoldShip, which OpenShipScreen sets. Executors act for the human who
// issued the command and the helpers they call for ActingHuman; the routines screens also
// call take the human.
interface
uses
  aCommands,
  aHold,
  aHuman,
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
  // CHANGE: ENHANCEMENT - The self-contained form of a sale a host relays (RelayedSaleOf);
  // relay only (aCommands.RegisterRelayCommand).
  ckRelayedSale = 254;
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

// Whether Human's ranger can reach its storage where it is, and the planet or station that
// storage is at.
function CanUseLocalStorage(Human: THuman): Boolean;
function GetLocalStorageOwner(Human: THuman): TObject;
// Whether the ship Human edits (a station or its ranger's tranclucator) trains with the
// ranger's experience.
function CanUsePlayerExperience(Human: THuman): Boolean;
function CompareStoredItems(Left: PStorageEntry; Right: PStorageEntry; Sort: TPlayerHoldSort): Integer;
// The hold cell the screen names: Index in the hold list, or the display order in the
// expanded hold.
function FindHoldEntry(Human: THuman; Index: Integer; Expanded: Boolean): TPlayerHoldUnit;

procedure OpenShipScreen(Ship: TShip; Reentering: Boolean);
// CHANGE: BUGFIX - Whether OpenShipScreen would refuse the local human Ship: another human
// has its screen open (rrInUse). The screens check it before they open the ship screen.
function ShipScreenInUse(Ship: TShip): Boolean;
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

// CHANGE: ENHANCEMENT - A sale on the ship screen (SellHeld, SellHoldInventory,
// SellHoldArtefact, SellHoldGoods, SellStoredItem) runs on what the actor holds, which the hold
// commands before it put there, and a host relays only the trade (docs/network.md, Trades). So
// a host relays the sale's effect instead: RelayedSaleOf, right after the sale ran, gives a
// RelayedSale of the same actor at Location (its shop location), with the actor's money after
// the sale, the ids of the items the sale put into Location's equipment shop and the goods it
// sold to Location's market; its Kind is ckNone when the sale put nothing there.
function IsShipScreenSale(Kind: TCommandKind): Boolean;
function RelayedSaleOf(const Command: TPlayerCommand; Location: TObject): TPlayerCommand;
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
  aMissile,
  aMyFunction,
  aNormalShip,
  aRuins,
  aScript,
  aSession,
  aShopStock,
  aTranclucator,
  SimEvents;

// Moved from TfShip2.CanUseLocalStorage.
function CanUseLocalStorage(Human: THuman): Boolean;
begin
  Result :=
      ((Human.Player.IsOnPlanet and (Human.Player.CurrentPlanet.OwnerId <> Byte(oiUninhabited)))
              or (Human.Player.IsDockedToShip and (Human.Player.RuinsMode = 0)))
          and (FirstScriptRequest(srqArcadeBattle, Human.Id) = nil);
end;

// Moved from TfShip2.GetLocalStorageOwner.
function GetLocalStorageOwner(Human: THuman): TObject;
begin
  if Human.Player.IsOnPlanet then
    Result := Human.Player.CurrentPlanet
  else if Human.Player.IsDockedToShip then
    Result := Human.Player.DockedTo
  else
    Result := nil;
end;

// Moved from TfShip2.CanUsePlayerExperience.
function CanUsePlayerExperience(Human: THuman): Boolean;
begin
  Result := True;
  if not ((Human.PlayerHoldShip is TRuins) and (Human.PlayerHoldShip as TRuins).ModernizationSponsor)
      and not ((Human.PlayerHoldShip is TTranclucator)
          and ((Human.PlayerHoldShip as TTranclucator).OwnerShip = Human.Player)) then
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
function FindHoldEntry(Human: THuman; Index: Integer; Expanded: Boolean): TPlayerHoldUnit;
var
  J: Integer;
begin
  if not Expanded then
  begin
    if (Index < 0) or (Human.PlayerHoldEntries.Count <= Index) then
      Result := nil
    else
      Result := TPlayerHoldUnit(Human.PlayerHoldEntries[Index]);
  end
  else
  begin
    J := FindPlayerHoldIndexByOrder(Human, Index);
    if J < 0 then
      Result := nil
    else
      Result := TPlayerHoldUnit(Human.PlayerHoldEntries[J]);
  end;
end;

// CHANGE: BUGFIX - A hold cell that shows an item must still have it in the edited ship. The
// cells are the human's view of the ship (aHold); between days another human may have taken
// the item from a shared ship (a sponsored station's), and a command from the stale cell held
// the item before it raised on a ship without it, or ran its scripts (docs/network.md,
// Commands). A cell without an item, or with goods, is not checked.
procedure RequireHoldCellItem(const Command: TPlayerCommand; Human: THuman; Entry: TPlayerHoldUnit);
var
  Present: Boolean;
begin
  if (Entry = nil) or not (Entry.Kind in [phkEquipment, phkArtefact]) then
    Exit;
  if Human.PlayerHoldShip = nil then
    raise Exception.Create(CommandKindName(Command.Kind) + ' needs an open ship screen');
  if Entry.Item = nil then
    Present := False
  else if Entry.Kind = phkEquipment then
    Present := Human.PlayerHoldShip.Inventory.IndexOf(Entry.Item) >= 0
  else
    Present := Human.PlayerHoldShip.Artefacts.IndexOf(Entry.Item) >= 0;
  if not Present then
    raise ECommandRefused.CreateReason(
        rrItemGone,
        CommandKindName(Command.Kind) + ' names a hold cell whose item is gone'
    );
end;

function HoldEntryArg(const Command: TPlayerCommand; Index: Integer): TPlayerHoldUnit;
var
  H: THuman;
begin
  H := ActorHuman(Command);
  Result := FindHoldEntry(H, IntArg(Command, Index), IntArg(Command, Index + 1) <> 0);
  RequireHoldCellItem(Command, H, Result);
end;

// CHANGE: BUGFIX - The other human who has Ship's screen open (THuman.EditedShip), or nil.
function OtherShipEditor(Human: THuman; Ship: TShip): THuman;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to Session.Humans.Count - 1 do
    if (Session.Humans[I] <> Human) and (Session.Humans[I].EditedShip = Ship) then
      Exit(Session.Humans[I]);
end;

procedure AddHoldCell(var Command: TPlayerCommand; Index: Integer; Expanded: Boolean);
begin
  AddInt(Command, Index);
  AddInt(Command, Ord(Expanded));
end;

procedure RequireHeld(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  if H.SelectedHoldKind = phkEmpty then
    raise Exception.Create(CommandKindName(Command.Kind) + ' needs a held entry');
end;

procedure RequireHeldItem(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  if not (H.SelectedHoldKind in [phkEquipment, phkArtefact])
      or (H.SelectedHoldItem = nil) then
    raise Exception.Create(CommandKindName(Command.Kind) + ' needs a held item');
end;

// An item the ship screen shows: in the edited ship or in the player's storage.
function FindShownItem(Human: THuman; Id: Integer): TItem;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to Human.PlayerHoldShip.Inventory.Count - 1 do
    if TItem(Human.PlayerHoldShip.Inventory[I]).Id = Id then
      Exit(TItem(Human.PlayerHoldShip.Inventory[I]));
  for I := 0 to Human.PlayerHoldShip.Artefacts.Count - 1 do
    if TItem(Human.PlayerHoldShip.Artefacts[I]).Id = Id then
      Exit(TItem(Human.PlayerHoldShip.Artefacts[I]));
  for I := 0 to Human.Player.StorageEntries.Count - 1 do
    if (PStorageEntry(Human.Player.StorageEntries[I]).Item <> nil)
        and (PStorageEntry(Human.Player.StorageEntries[I]).Item.Id = Id) then
      Exit(PStorageEntry(Human.Player.StorageEntries[I]).Item);
end;

function ShownItemArg(const Command: TPlayerCommand; Index: Integer): TItem;
var
  H: THuman;
begin
  H := ActorHuman(Command);
  Result := FindShownItem(H, IntArg(Command, Index));
  if Result = nil then
    raise Exception.Create(CommandKindName(Command.Kind) + ' names a missing item');
end;

// Moved from TfShip2.RefreshShipView: what it recomputes before it draws.
procedure RefreshHoldViewState;
var
  H: THuman;
begin
  H := ActingHuman;
  H.PlayerHoldShip.RefreshAssignedItemSlots;
  H.PlayerHoldShip.RefreshDerivedStats(True);
  RefreshPlayerHoldView(H, False);
end;

// Moved from TfShip2.TakeHoldEntry.
procedure TakeHoldEntry(Entry: TPlayerHoldUnit; Slot: Integer; UsesDisplayOrder: Boolean);
var
  H: THuman;
begin
  H := ActingHuman;
  if Entry.Kind = phkEquipment then
  begin
    H.SelectedHoldKind := phkEquipment;
    H.SelectedHoldOrigin := 0;
    H.SelectedHoldSlot := Slot;
    H.SelectedHoldUsesDisplayOrder := UsesDisplayOrder;
    H.SelectedHoldItem := Entry.Item;
    H.PlayerHoldShip.Inventory.Delete(H.PlayerHoldShip.Inventory.IndexOf(Entry.Item));
    Entry.Kind := phkEmpty;
    Entry.Item := nil;
  end
  else if Entry.Kind = phkGoods then
  begin
    H.SelectedHoldKind := phkGoods;
    H.SelectedHoldOrigin := 0;
    H.SelectedHoldSlot := Slot;
    H.SelectedHoldUsesDisplayOrder := UsesDisplayOrder;
    H.SelectedGoodsIndex := Entry.GoodsIndex;
    H.SelectedGoodsQuantity := H.PlayerHoldShip.CargoGoods[H.SelectedGoodsIndex].Count;
    H.SelectedGoodsCost := H.PlayerHoldShip.CargoGoods[H.SelectedGoodsIndex].TotalCost;
    H.PlayerHoldShip.CargoGoods[H.SelectedGoodsIndex].Count := 0;
    H.PlayerHoldShip.CargoGoods[H.SelectedGoodsIndex].TotalCost := 0;
    Entry.Kind := phkEmpty;
    Entry.Item := nil;
  end
  else if Entry.Kind = phkArtefact then
  begin
    H.SelectedHoldKind := phkArtefact;
    H.SelectedHoldOrigin := 0;
    H.SelectedHoldSlot := Slot;
    H.SelectedHoldUsesDisplayOrder := UsesDisplayOrder;
    H.SelectedHoldItem := Entry.Item;
    H.PlayerHoldShip.Artefacts.Delete(H.PlayerHoldShip.Artefacts.IndexOf(Entry.Item));
    Entry.Kind := phkEmpty;
    Entry.Item := nil;
  end
  else
    H.SelectedHoldKind := phkEmpty;
end;

// Moved from TfShip2.ReturnSelectedHoldEntry, without its cursor and redraw. Returns whether
// something was held.
function ReturnHeldEntryState: Boolean;
var
  H: THuman;
  I, Count: Integer;
  Entry: TPlayerHoldUnit;
begin
  H := ActingHuman;
  Result := H.SelectedHoldKind <> phkEmpty;
  if H.SelectedHoldKind <> phkEmpty then
  begin
    if H.SelectedHoldOrigin = 0 then
    begin
      if H.SelectedHoldKind = phkGoods then
      begin
        H.PlayerHoldShip.CargoGoods[H.SelectedGoodsIndex].Count := H.SelectedGoodsQuantity;
        H.PlayerHoldShip.CargoGoods[H.SelectedGoodsIndex].TotalCost := H.SelectedGoodsCost;
      end
      else if H.SelectedHoldKind = phkEquipment then
      begin
        if not (H.SelectedHoldItem is THull) then
        begin
          if H.SelectedHoldItem is TWeapon then
            (H.SelectedHoldItem as TWeapon).Target := nil;
          H.PlayerHoldShip.Inventory.Add(H.SelectedHoldItem);
          (H.SelectedHoldItem as TEquipment).EquippedFlag := 0;
        end;
      end
      else if H.SelectedHoldKind = phkArtefact then
      begin
        H.PlayerHoldShip.Artefacts.Add(H.SelectedHoldItem);
        (H.SelectedHoldItem as TEquipment).EquippedFlag := 0;
      end;
      if (H.SelectedHoldKind = phkGoods)
          or (H.SelectedHoldKind = phkEquipment)
          or (H.SelectedHoldKind = phkArtefact) then
      begin
        if H.SelectedHoldUsesDisplayOrder then
        begin
          if FindPlayerHoldIndexByOrder(H, H.SelectedHoldSlot) < 0 then
          begin
            Entry := TPlayerHoldUnit.Create;
            H.PlayerHoldEntries.Add(Entry);
            Entry.DisplayOrder := H.SelectedHoldSlot;
          end
          else
          begin
            Entry := TPlayerHoldUnit.Create;
            Entry.DisplayOrder := FindFreePlayerHoldOrder(H);
            H.PlayerHoldEntries.Add(Entry);
          end;
          Entry.Kind := H.SelectedHoldKind;
          if H.SelectedHoldKind = phkGoods then
            Entry.GoodsIndex := H.SelectedGoodsIndex
          else
          begin
            Entry.ItemId := H.SelectedHoldItem.Id;
            Entry.Item := H.SelectedHoldItem;
          end;
          RestorePlayerHoldDisplayOrder(H);
        end
        else if H.SelectedHoldSlot >= 0 then
        begin
          if IsPlayerHoldSlotEmpty(H, H.SelectedHoldSlot) then
          begin
            if H.PlayerHoldEntries.Count > H.SelectedHoldSlot then
              Entry := H.PlayerHoldEntries[H.SelectedHoldSlot]
            else
            begin
              Count := H.SelectedHoldSlot - H.PlayerHoldEntries.Count + 1;
              for I := 0 to Count - 1 do
              begin
                Entry := TPlayerHoldUnit.Create;
                H.PlayerHoldEntries.Add(Entry);
                Entry.Kind := phkEmpty;
              end;
              Entry := H.PlayerHoldEntries[H.PlayerHoldEntries.Count - 1];
            end;
          end
          else
          begin
            Entry := TPlayerHoldUnit.Create;
            H.PlayerHoldEntries.Add(Entry);
          end;
          Entry.DisplayOrder := FindFreePlayerHoldOrder(H);
          Entry.Kind := H.SelectedHoldKind;
          if H.SelectedHoldKind = phkGoods then
            Entry.GoodsIndex := H.SelectedGoodsIndex
          else
          begin
            Entry.ItemId := H.SelectedHoldItem.Id;
            Entry.Item := H.SelectedHoldItem;
          end;
        end
        else
        begin
          if ((H.SelectedHoldKind = phkEquipment) or (H.SelectedHoldKind = phkArtefact))
              and (H.PlayerHoldShip.FindEquippedItemInSlot(
                      Byte(H.SelectedHoldItem.ItemType),
                      -H.SelectedHoldSlot - 1)
                  = nil) then
          begin
            (H.SelectedHoldItem as TEquipment).EquippedFlag := 0;
            (H.SelectedHoldItem as TEquipment).Equip;
          end;
        end
      end;
    end
    else
    begin
      if H.SelectedHoldKind = phkGoods then
      begin
        if H.Player.FindStorageIndexByLocationAndSlot(GetLocalStorageOwner(H), H.SelectedHoldSlot)
            < 0 then
          H.Player.AddGoodsToPlayerStorage(
              H.SelectedGoodsIndex,
              H.SelectedGoodsQuantity,
              H.SelectedGoodsCost,
              GetLocalStorageOwner(H),
              H.SelectedHoldSlot
          )
        else
          H.Player.AddGoodsToPlayerStorage(
              H.SelectedGoodsIndex,
              H.SelectedGoodsQuantity,
              H.SelectedGoodsCost,
              GetLocalStorageOwner(H),
              -1
          );
      end
      else if (H.SelectedHoldKind = phkEquipment) or (H.SelectedHoldKind = phkArtefact) then
      begin
        if H.Player.FindStorageIndexByLocationAndSlot(GetLocalStorageOwner(H), H.SelectedHoldSlot)
            < 0 then
          H.Player.AddItemToPlayerStorage(H.SelectedHoldItem, GetLocalStorageOwner(H), H.SelectedHoldSlot)
        else
          H.Player.AddItemToPlayerStorage(H.SelectedHoldItem, GetLocalStorageOwner(H), -1);
      end;
    end;
    H.SelectedHoldKind := phkEmpty;
    H.SelectedHoldItem := nil;
    if not ExitScreenLoop then
      H.PlayerHoldShip.RefreshDerivedStats(True);
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
  H, Editor: THuman;
  P: TPlayer;
  Ship: TShip;
  Reentering: Boolean;
  I: Integer;
  Item: TItem;
begin
  H := ActorHuman(Command);
  P := Actor(Command);
  Reentering := IntArg(Command, 0) <> 0;
  Ship := RefObject(Command, 0) as TShip;
  // CHANGE: BUGFIX - One human at a time edits a ship that is not its own ranger (a sponsored
  // station's): the screen lends the ship the human's experience until it closes, and takes
  // hold cells by the human's view of the hold. Two humans interleaving between days swapped
  // their experience (docs/network.md, Commands). A human always opens its own ranger.
  if (Ship <> P) and (H.EditedShip <> Ship) then
  begin
    Editor := OtherShipEditor(H, Ship);
    if Editor <> nil then
      raise ECommandRefused.CreateReason(
          rrInUse,
          Format('OpenShipScreen: human %d has ship %d open', [Editor.Id, Ship.Id])
      );
  end;
  H.PlayerHoldShip := Ship;
  H.EditedShip := Ship;
  H.ShipScreenShown := True;
  if Reentering then
  begin
    H.PlayerHoldShip.ScriptItemsAct(satOnReEnteringForm, nil, nil, 0);
    if P <> H.PlayerHoldShip then
      P.ScriptItemsAct(satOnReEnteringOtherShip, nil, nil, 0);
  end
  else
  begin
    H.PlayerHoldShip.ScriptItemsAct(satOnEnteringForm, nil, nil, 0);
    if P <> H.PlayerHoldShip then
      P.ScriptItemsAct(satOnEnteringOtherShip, nil, nil, 0);
  end;
  for I := 0 to H.PlayerHoldShip.Inventory.Count - 1 do
  begin
    Item := TItem(H.PlayerHoldShip.Inventory[I]);
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
    RemoveEmptyPlayerHoldSlots(H);
  P.RepairDuplicateStorageSlots(GetLocalStorageOwner(H));
  if not Reentering then
  begin
    H.SelectedHoldKind := phkEmpty;
    H.SelectedHoldItem := nil;
  end;
  H.SavedShipExperience := -1;
  if CanUsePlayerExperience(H) then
  begin
    H.SavedShipExperience := H.PlayerHoldShip.FreeExperience;
    H.PlayerHoldShip.FreeExperience := P.FreeExperience;
  end;
end;

function ShipScreenInUse(Ship: TShip): Boolean;
begin
  Result :=
      (Ship <> nil)
          and (Ship <> LocalPlayer)
          and (LocalHuman.EditedShip <> Ship)
          and (OtherShipEditor(LocalHuman, Ship) <> nil);
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
  H: THuman;
  P: TPlayer;
begin
  H := ActorHuman(Command);
  P := Actor(Command);
  H.PlayerHoldShip := RefObject(Command, 0) as TShip;
  if IntArg(Command, 0) = 0 then
  begin
    H.PlayerHoldShip.ScriptItemsAct($19, nil, nil, 0);
    if P <> H.PlayerHoldShip then
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
  H: THuman;
  P: TPlayer;
  I: Integer;
  Binding: TScriptShip;
begin
  H := ActorHuman(Command);
  P := Actor(Command);
  Session.ScriptUseItem := nil;
  if (H.SavedShipExperience >= 0) and CanUsePlayerExperience(H) then
  begin
    P.FreeExperience := H.PlayerHoldShip.FreeExperience;
    H.PlayerHoldShip.FreeExperience := H.SavedShipExperience;
    H.SavedShipExperience := -1;
  end;
  H.PlayerHoldShip.RefreshDerivedStats(True);
  if H.PlayerHoldShip.Order = soJump then
    if H.PlayerHoldShip.JumpRange
        < System.Round(
            PointDistance(
                H.PlayerHoldShip.CurrentStar.Position,
                TStar(H.PlayerHoldShip.OrderTarget).Position
            )) then
      H.PlayerHoldShip.OrderNone(False);
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
  // CHANGE: BUGFIX - The ship screen no longer shows; leaving it (not to come back) frees the
  // ship for the other humans (ExecuteOpenShipScreen).
  H.ShipScreenShown := False;
  if IntArg(Command, 0) = 0 then
  begin
    H.PlayerHoldShip := nil;
    H.EditedShip := nil;
  end;
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
  H: THuman;
  Item: TEquipment;
  Slot: Integer;
begin
  H := ActorHuman(Command);
  Slot := IntArg(Command, 1);
  Item := H.PlayerHoldShip.FindEquippedItemInSlot(IntArg(Command, 0), Slot);
  if Item = nil then
    raise Exception.Create('TakeEquipped names an empty slot');
  if Item.EquippedFlag <> 0 then
    H.PlayerHoldShip.UnequipItem(Item);
  H.PlayerHoldShip.Inventory.Delete(H.PlayerHoldShip.Inventory.IndexOf(Item));
  H.PlayerHoldShip.RebuildEquipmentCache;
  H.PlayerHoldShip.RefreshDerivedStats(True);
  H.SelectedHoldKind := phkEquipment;
  H.SelectedHoldOrigin := 0;
  H.SelectedHoldSlot := -(Slot + 1);
  H.SelectedHoldUsesDisplayOrder := False;
  H.SelectedHoldItem := Item;
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
  H: THuman;
  Slot: Integer;
  Equipment: TEquipment;
  Item: TArtefact;
begin
  H := ActorHuman(Command);
  Slot := IntArg(Command, 0);
  Equipment := H.PlayerHoldShip.FindEquippedItemInSlot(Ord(t_Artefact), Slot);
  if Equipment = nil then
    raise Exception.Create('TakeArtefact names an empty slot');
  Item := Equipment as TArtefact;
  Item.Unequip;
  H.PlayerHoldShip.Artefacts.Delete(H.PlayerHoldShip.Artefacts.IndexOf(Item));
  H.PlayerHoldShip.RefreshDerivedStats(True);
  H.SelectedHoldKind := phkArtefact;
  H.SelectedHoldOrigin := 0;
  H.SelectedHoldSlot := -(Slot + 1);
  H.SelectedHoldUsesDisplayOrder := False;
  H.SelectedHoldItem := Item;
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
  H: THuman;
  Entry: TPlayerHoldUnit;
begin
  H := ActorHuman(Command);
  Entry := HoldEntryArg(Command, 0);
  // CHANGE: BUGFIX - The command names the item the sender's cell showed (a log from before
  // names none, and 0 is a cell of goods): the cell must still show it. Between days another
  // human may have taken it from a shared ship, and this human's view then shows another item
  // in the cell, or none (docs/network.md, Commands).
  if (Length(Command.Ints) >= 3) and (IntArg(Command, 2) <> 0) then
    if (Entry = nil)
        or not (Entry.Kind in [phkEquipment, phkArtefact])
        or (Entry.Item = nil)
        or (Integer(Entry.Item.Id) <> IntArg(Command, 2)) then
      raise ECommandRefused.CreateReason(
          rrItemGone,
          Format('TakeHoldEntry: item %d is no longer in the hold cell', [IntArg(Command, 2)])
      );
  if Entry = nil then
    raise Exception.Create('TakeHoldEntry names an empty hold cell');
  TakeHoldEntry(Entry, IntArg(Command, 0), IntArg(Command, 1) <> 0);
  H.PlayerHoldShip.RefreshDerivedStats(True);
end;

procedure TakeHoldEntryAt(Index: Integer; Expanded: Boolean);
var
  Command: TPlayerCommand;
  Entry: TPlayerHoldUnit;
begin
  Command := NewCommand(ckTakeHoldEntry);
  AddHoldCell(Command, Index, Expanded);
  // The item the cell shows, which the executor checks (0: goods or none).
  Entry := FindHoldEntry(ActorHuman(Command), Index, Expanded);
  if (Entry <> nil) and (Entry.Kind in [phkEquipment, phkArtefact]) and (Entry.Item <> nil) then
    AddInt(Command, Integer(Entry.Item.Id))
  else
    AddInt(Command, 0);
  SubmitCommand(Command);
end;

// Moved from TfShip2.HullMouseDown.
procedure ExecuteTakeHull(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  H.SelectedHoldKind := phkEquipment;
  H.SelectedHoldOrigin := 0;
  H.SelectedHoldSlot := 0;
  H.SelectedHoldUsesDisplayOrder := False;
  H.SelectedHoldItem := TItem(H.PlayerHoldShip.Inventory[0]);
  H.PlayerHoldShip.RefreshDerivedStats(True);
end;

procedure TakeHull;
begin
  SubmitCommand(NewCommand(ckTakeHull));
end;

function StorageSlotIndex(const Command: TPlayerCommand; Slot: Integer): Integer;
var
  H: THuman;
begin
  H := ActorHuman(Command);
  Result := H.Player.FindStorageIndexByLocationAndSlot(GetLocalStorageOwner(H), Slot);
  if Result < 0 then
    raise Exception.Create(CommandKindName(Command.Kind) + ' names an empty storage cell');
end;

// Moved from TfShip2.StorageItemMouseUp.
procedure ExecuteTakeStored(const Command: TPlayerCommand);
var
  H: THuman;
  P: TPlayer;
  Entry: PStorageEntry;
  Slot, Index: Integer;
begin
  H := ActorHuman(Command);
  P := Actor(Command);
  Slot := IntArg(Command, 0);
  Index := StorageSlotIndex(Command, Slot);
  Entry := P.StorageEntries[Index];
  P.StorageEntries.Delete(Index);
  if Entry.Item is TGoods then
  begin
    H.SelectedHoldKind := phkGoods;
    H.SelectedHoldOrigin := 1;
    H.SelectedHoldSlot := Slot;
    H.SelectedHoldUsesDisplayOrder := False;
    H.SelectedGoodsIndex := Byte(Entry.Item.ItemType);
    H.SelectedGoodsQuantity := (Entry.Item as TGoods).Quantity;
    H.SelectedGoodsCost := (Entry.Item as TGoods).Cost;
    Entry.Item.Free;
  end
  else if Entry.Item is TArtefact then
  begin
    H.SelectedHoldKind := phkArtefact;
    H.SelectedHoldOrigin := 1;
    H.SelectedHoldSlot := Slot;
    H.SelectedHoldUsesDisplayOrder := False;
    H.SelectedHoldItem := Entry.Item;
  end
  else
  begin
    H.SelectedHoldKind := phkEquipment;
    H.SelectedHoldOrigin := 1;
    H.SelectedHoldSlot := Slot;
    H.SelectedHoldUsesDisplayOrder := False;
    H.SelectedHoldItem := Entry.Item;
  end;
  Entry.LocationOwner := nil;
  Entry.Item := nil;
  Dispose(Entry);
  H.PlayerHoldShip.ScriptItemsAct(satOnReEnteringForm, nil, nil, 0);
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
  H: THuman;
  P: TPlayer;
  Entry: PStorageEntry;
  Slot, Index: Integer;
begin
  H := ActorHuman(Command);
  P := Actor(Command);
  Slot := IntArg(Command, 0);
  Index := StorageSlotIndex(Command, Slot);
  Entry := P.StorageEntries[Index];
  if not (Entry.Item is THull) then
    raise Exception.Create('TakeStoredHull names another item');
  P.StorageEntries.Delete(Index);
  H.SelectedHoldKind := phkEquipment;
  H.SelectedHoldOrigin := 1;
  H.SelectedHoldSlot := Slot;
  H.SelectedHoldUsesDisplayOrder := False;
  H.SelectedHoldItem := Entry.Item;
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
  H: THuman;
  Slot: Integer;
  Item: TEquipment;
begin
  H := ActorHuman(Command);
  RequireHeldItem(Command);
  Slot := IntArg(Command, 1);
  Item := H.PlayerHoldShip.FindEquippedItemInSlot(IntArg(Command, 0), Slot);
  if (Item <> nil) and (Item.EquippedFlag <> 0) then
    H.PlayerHoldShip.UnequipItem(Item);
  H.PlayerHoldShip.Inventory.Add(H.SelectedHoldItem);
  (H.SelectedHoldItem as TEquipment).AssignedSlotData :=
      ((H.SelectedHoldItem as TEquipment).AssignedSlotData and EquipmentSecondaryFireFlag)
          or Slot;
  (H.SelectedHoldItem as TEquipment).Equip;
  if H.SelectedHoldItem is TWeapon then
    (H.SelectedHoldItem as TWeapon).Target := nil;
  MissileWarning :=
      (H.PlayerHoldShip is TTranclucator)
          and (H.SelectedHoldItem is TWeapon)
          and (Byte(TWeapon(H.SelectedHoldItem).GetWeaponInfo.ShotType)
              in [Ord(wstTorpedo)..Ord(wstRocket)])
          and (H.PlayerHoldShip.GetRadar = nil);
  H.SelectedHoldKind := phkEmpty;
  H.SelectedHoldItem := nil;
  if Item <> nil then
  begin
    H.PlayerHoldShip.Inventory.Delete(H.PlayerHoldShip.Inventory.IndexOf(Item));
    H.SelectedHoldKind := phkEquipment;
    H.SelectedHoldOrigin := 0;
    H.SelectedHoldSlot := -(Slot + 1);
    H.SelectedHoldUsesDisplayOrder := False;
    H.SelectedHoldItem := Item;
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
  H: THuman;
  Slot: Integer;
  Equipment: TEquipment;
begin
  H := ActorHuman(Command);
  RequireHeldItem(Command);
  Slot := IntArg(Command, 0);
  Equipment := H.PlayerHoldShip.FindEquippedItemInSlot(Ord(t_Artefact), Slot);
  if (Equipment <> nil) and (Equipment.EquippedFlag <> 0) then
    Equipment.Unequip;
  H.PlayerHoldShip.Artefacts.Add(H.SelectedHoldItem);
  (H.SelectedHoldItem as TEquipment).AssignedSlotData := Slot;
  (H.SelectedHoldItem as TEquipment).EquippedFlag := 0;
  (H.SelectedHoldItem as TEquipment).Equip;
  H.SelectedHoldKind := phkEmpty;
  H.SelectedHoldItem := nil;
  if Equipment <> nil then
  begin
    H.PlayerHoldShip.Artefacts.Delete(H.PlayerHoldShip.Artefacts.IndexOf(Equipment));
    H.SelectedHoldKind := phkArtefact;
    H.SelectedHoldOrigin := 0;
    H.SelectedHoldSlot := -(Slot + 1);
    H.SelectedHoldUsesDisplayOrder := False;
    H.SelectedHoldItem := Equipment;
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
  H: THuman;
  Index, J, Count, Missing, ActionResult: Integer;
  Expanded: Boolean;
  Entry, Swap: TPlayerHoldUnit;
begin
  H := ActorHuman(Command);
  if H.SelectedHoldKind <> phkGoods then
    raise Exception.Create('PutHeldGoods needs held goods');
  Index := IntArg(Command, 0);
  Expanded := IntArg(Command, 1) <> 0;
  Count := IntArg(Command, 2);
  Entry := FindHoldEntry(H, Index, Expanded);
  RequireHoldCellItem(Command, H, Entry);
  PutOutcome := poPlaced;
  if (Entry <> nil) and (Entry.Kind in [phkEquipment, phkArtefact]) then
  begin
    if Entry.Item.ScriptItem <> nil then
      ActionResult :=
          TScriptItem(Entry.Item.ScriptItem)
              .RunActionCode(
                  satOnAnotherGoods,
                  H.PlayerHoldShip,
                  TObject(H.SelectedGoodsIndex),
                  TObject(Count),
                  0)
    else
      ActionResult :=
          RunItemConfigActionCode(
              Entry.Item,
              satOnAnotherGoods,
              H.PlayerHoldShip,
              TObject(H.SelectedGoodsIndex),
              TObject(Count),
              0
          );
    if ActionResult <> 0 then
    begin
      Count := Min(Count, Abs(ActionResult));
      if Count < H.SelectedGoodsQuantity then
      begin
        Dec(H.SelectedGoodsCost, Round(Count / H.SelectedGoodsQuantity * H.SelectedGoodsCost));
        Dec(H.SelectedGoodsQuantity, Count);
      end
      else
      begin
        H.SelectedHoldKind := phkEmpty;
        H.SelectedGoodsQuantity := 0;
        H.SelectedGoodsCost := 0;
      end;
      H.PlayerHoldShip.RefreshDerivedStats(True);
      PutOutcome := poScript;
      HeldActionResult := ActionResult;
      Exit;
    end;
  end;
  Inc(H.PlayerHoldShip.CargoGoods[H.SelectedGoodsIndex].Count, Count);
  Inc(
      H.PlayerHoldShip.CargoGoods[H.SelectedGoodsIndex].TotalCost,
      Round(Count / H.SelectedGoodsQuantity * H.SelectedGoodsCost)
  );
  if not Expanded then
  begin
    if Entry = nil then
    begin
      Missing := Index - H.PlayerHoldEntries.Count + 1;
      for J := 0 to Missing - 1 do
      begin
        Entry := TPlayerHoldUnit.Create;
        H.PlayerHoldEntries.Add(Entry);
        Entry.Kind := phkEmpty;
      end;
      Entry := TPlayerHoldUnit(H.PlayerHoldEntries[H.PlayerHoldEntries.Count - 1]);
    end
    else
    begin
      if Entry.Kind <> phkEmpty then
      begin
        Entry := TPlayerHoldUnit.Create;
        H.PlayerHoldEntries.Insert(Index, Entry);
        Entry.Kind := phkEmpty;
      end;
    end;
    Entry.DisplayOrder := FindFreePlayerHoldOrder(H);
    Entry.Kind := phkGoods;
    Entry.GoodsIndex := H.SelectedGoodsIndex;
    Dec(H.SelectedGoodsCost, Round(Count / H.SelectedGoodsQuantity * H.SelectedGoodsCost));
    Dec(H.SelectedGoodsQuantity, Count);
    RemoveEmptyPlayerHoldSlot(H, H.PlayerHoldEntries.IndexOf(Entry) + 1);
    if H.SelectedGoodsQuantity <= 0 then
      H.SelectedHoldKind := phkEmpty
    else
      ReturnHeldEntryInside;
  end
  else
  begin
    Swap := nil;
    if Entry = nil then
    begin
      Entry := TPlayerHoldUnit.Create;
      H.PlayerHoldEntries.Add(Entry);
    end
    else
    begin
      if Entry.Kind <> phkEmpty then
      begin
        Swap := Entry;
        Entry := TPlayerHoldUnit.Create;
        H.PlayerHoldEntries.Add(Entry);
      end;
    end;
    Entry.DisplayOrder := Index;
    Entry.Kind := phkGoods;
    Entry.GoodsIndex := H.SelectedGoodsIndex;
    Dec(H.SelectedGoodsCost, Round(Count / H.SelectedGoodsQuantity * H.SelectedGoodsCost));
    Dec(H.SelectedGoodsQuantity, Count);
    if Swap <> nil then
    begin
      if H.SelectedGoodsQuantity > 0 then
        RaiseWideMessage('move goods');
      TakeHoldEntry(Swap, Index, Expanded);
    end
    else if H.SelectedGoodsQuantity <= 0 then
    begin
      H.SelectedHoldKind := phkEmpty;
      H.SelectedHoldItem := nil;
    end
    else
      ReturnHeldEntryInside;
    RestorePlayerHoldDisplayOrder(H);
  end;
  for J := H.PlayerHoldEntries.Count - 1 downto 0 do
  begin
    Swap := TPlayerHoldUnit(H.PlayerHoldEntries[J]);
    if (Swap.Kind = phkGoods) and (H.SelectedGoodsIndex = Swap.GoodsIndex) and (Entry <> Swap) then
    begin
      if not Expanded then
      begin
        Swap.Item := nil;
        Swap.Kind := phkEmpty;
      end
      else
      begin
        H.PlayerHoldEntries.Delete(J);
        Swap.Free;
      end;
    end;
  end;
  H.PlayerHoldShip.RefreshDerivedStats(True);
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
  H: THuman;
  Index, J, Count, Missing, ActionResult: Integer;
  Expanded, RunScripts: Boolean;
  Entry, Swap: TPlayerHoldUnit;
  Stack: TCountableItem;
begin
  H := ActorHuman(Command);
  RequireHeldItem(Command);
  Index := IntArg(Command, 0);
  Expanded := IntArg(Command, 1) <> 0;
  Count := IntArg(Command, 2);
  RunScripts := IntArg(Command, 3) <> 0;
  Entry := FindHoldEntry(H, Index, Expanded);
  RequireHoldCellItem(Command, H, Entry);
  PutOutcome := poAborted;
  if RunScripts
      and (H.SelectedHoldOrigin = 0)
      and (Entry <> nil)
      and (Entry.Item <> nil)
      and (Entry.Kind in [phkEquipment, phkArtefact])
      and not TCountableItem(H.SelectedHoldItem).CanMerge(Entry.Item) then
  begin
    ActionResult := 0;
    if H.SelectedHoldItem.ScriptItem <> nil then
      ActionResult :=
          TScriptItem(H.SelectedHoldItem.ScriptItem)
              .RunActionCode(satOnAnotherItem, H.PlayerHoldShip, Entry.Item, nil, ActionResult);
    if Entry.Item.ScriptItem <> nil then
      ActionResult :=
          TScriptItem(Entry.Item.ScriptItem)
              .RunActionCode(
                  satOnAnotherItem2,
                  H.PlayerHoldShip,
                  H.SelectedHoldItem,
                  nil,
                  ActionResult);
    if Entry.Item is TEquipmentWithActCode then
      ActionResult :=
          RunItemConfigActionCode(
              Entry.Item,
              satOnAnotherItem2,
              H.PlayerHoldShip,
              H.SelectedHoldItem,
              nil,
              ActionResult
          );
    if ActionResult in [1, 3] then
    begin
      H.SelectedHoldItem.Free;
      H.SelectedHoldKind := phkEmpty;
      H.SelectedHoldItem := nil;
    end;
    if ActionResult in [1..3] then
    begin
      H.PlayerHoldShip.RefreshDerivedStats(True);
      PutOutcome := poScript;
      HeldActionResult := ActionResult;
      Exit;
    end;
    Count := TCountableItem(H.SelectedHoldItem).StackCount;
  end;
  if (Count < 1) or (TCountableItem(H.SelectedHoldItem).StackCount < Count) then
    Exit;
  if Count < TCountableItem(H.SelectedHoldItem).StackCount then
  begin
    Stack := TCountableItem(H.SelectedHoldItem).Split(Count);
    if (Entry <> nil) and (Entry.Item <> nil) and Stack.CanMerge(Entry.Item) then
    begin
      TCountableItem(Entry.Item).Merge(Stack);
      Stack.Free;
      ReturnHeldEntryInside;
      PutOutcome := poMergedReturned;
      Exit;
    end;
    H.PlayerHoldShip.Inventory.Add(Stack);
  end
  else
  begin
    Stack := TCountableItem(H.SelectedHoldItem);
    H.SelectedHoldKind := phkEmpty;
    H.SelectedHoldItem := nil;
    if (Entry <> nil) and (Entry.Item <> nil) and Stack.CanMerge(Entry.Item) then
    begin
      TCountableItem(Entry.Item).Merge(Stack);
      Stack.Free;
      H.SelectedHoldItem := nil;
      H.SelectedHoldKind := phkEmpty;
      PutOutcome := poMerged;
      Exit;
    end;
    H.PlayerHoldShip.Inventory.Add(Stack);
  end;
  PutOutcome := poPlaced;
  if not Expanded then
  begin
    if Entry = nil then
    begin
      Missing := Index - H.PlayerHoldEntries.Count + 1;
      for J := 0 to Missing - 1 do
      begin
        Entry := TPlayerHoldUnit.Create;
        H.PlayerHoldEntries.Add(Entry);
        Entry.Kind := phkEmpty;
      end;
      Entry := TPlayerHoldUnit(H.PlayerHoldEntries[H.PlayerHoldEntries.Count - 1]);
    end
    else
    begin
      if Entry.Kind <> phkEmpty then
      begin
        Entry := TPlayerHoldUnit.Create;
        H.PlayerHoldEntries.Insert(Index, Entry);
        Entry.Kind := phkEmpty;
      end;
    end;
    Entry.DisplayOrder := FindFreePlayerHoldOrder(H);
    Entry.Kind := phkEquipment;
    Entry.ItemId := Stack.Id;
    Entry.Item := Stack;
    RemoveEmptyPlayerHoldSlot(H, H.PlayerHoldEntries.IndexOf(Entry) + 1);
    if H.SelectedHoldItem <> nil then
      ReturnHeldEntryInside;
  end
  else
  begin
    Swap := nil;
    if Entry = nil then
    begin
      Entry := TPlayerHoldUnit.Create;
      H.PlayerHoldEntries.Add(Entry);
    end
    else
    begin
      if Entry.Kind <> phkEmpty then
      begin
        Swap := Entry;
        Entry := TPlayerHoldUnit.Create;
        H.PlayerHoldEntries.Add(Entry);
      end;
    end;
    Entry.DisplayOrder := Index;
    Entry.Kind := phkEquipment;
    Entry.ItemId := Stack.Id;
    Entry.Item := Stack;
    if Swap <> nil then
    begin
      if TCountableItem(H.SelectedHoldItem).StackCount > 0 then
        RaiseWideMessage('move protoplasm');
      TakeHoldEntry(Swap, Index, Expanded);
    end
    else if H.SelectedHoldItem <> nil then
      ReturnHeldEntryInside;
    RestorePlayerHoldDisplayOrder(H);
  end;
  for J := 0 to H.PlayerHoldEntries.Count - 1 do
  begin
    Swap := TPlayerHoldUnit(H.PlayerHoldEntries[J]);
    if (Swap.Kind = phkEquipment) and (Entry.Item as TCountableItem).Merge(Swap.Item) then
    begin
      H.PlayerHoldShip.Inventory.Delete(H.PlayerHoldShip.Inventory.IndexOf(Swap.Item));
      Swap.Item.Free;
      Swap.Item := nil;
      Swap.Kind := phkEmpty;
    end;
  end;
  H.PlayerHoldShip.RefreshDerivedStats(True);
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
  H: THuman;
  Index, J, Count: Integer;
  Expanded: Boolean;
  Entry, Swap: TPlayerHoldUnit;
begin
  H := ActorHuman(Command);
  RequireHeldItem(Command);
  Index := IntArg(Command, 0);
  Expanded := IntArg(Command, 1) <> 0;
  Entry := FindHoldEntry(H, Index, Expanded);
  RequireHoldCellItem(Command, H, Entry);
  if H.SelectedHoldItem is TWeapon then
    (H.SelectedHoldItem as TWeapon).Target := nil;
  H.PlayerHoldShip.Inventory.Add(H.SelectedHoldItem);
  (H.SelectedHoldItem as TEquipment).EquippedFlag := 0;
  if not Expanded then
  begin
    if Entry = nil then
    begin
      Count := Index - H.PlayerHoldEntries.Count + 1;
      for J := 0 to Count - 1 do
      begin
        Entry := TPlayerHoldUnit.Create;
        H.PlayerHoldEntries.Add(Entry);
        Entry.Kind := phkEmpty;
      end;
      Entry := TPlayerHoldUnit(H.PlayerHoldEntries[H.PlayerHoldEntries.Count - 1]);
    end
    else
    begin
      if Entry.Kind <> phkEmpty then
      begin
        Entry := TPlayerHoldUnit.Create;
        H.PlayerHoldEntries.Insert(Index, Entry);
        Entry.Kind := phkEmpty;
      end;
    end;
    Entry.DisplayOrder := FindFreePlayerHoldOrder(H);
    Entry.Kind := phkEquipment;
    Entry.ItemId := H.SelectedHoldItem.Id;
    Entry.Item := H.SelectedHoldItem;
    RemoveEmptyPlayerHoldSlot(H, H.PlayerHoldEntries.IndexOf(Entry) + 1);
    H.SelectedHoldKind := phkEmpty;
    H.SelectedHoldItem := nil;
  end
  else
  begin
    if (Entry <> nil) and (Entry.Item <> nil) and (Entry.Item.NoDropFlag > 0) then
      Entry := nil;
    Swap := nil;
    if Entry = nil then
    begin
      Entry := TPlayerHoldUnit.Create;
      H.PlayerHoldEntries.Add(Entry);
    end
    else
    begin
      if Entry.Kind <> phkEmpty then
      begin
        Swap := Entry;
        Entry := TPlayerHoldUnit.Create;
        H.PlayerHoldEntries.Add(Entry);
      end;
    end;
    Entry.DisplayOrder := Index;
    Entry.Kind := phkEquipment;
    Entry.ItemId := H.SelectedHoldItem.Id;
    Entry.Item := H.SelectedHoldItem;
    if Swap <> nil then
      TakeHoldEntry(Swap, Index, Expanded)
    else
    begin
      H.SelectedHoldKind := phkEmpty;
      H.SelectedHoldItem := nil;
    end;
    RestorePlayerHoldDisplayOrder(H);
  end;
  H.PlayerHoldShip.RefreshDerivedStats(True);
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
  H: THuman;
  Index, J, Count: Integer;
  Expanded: Boolean;
  Entry, Swap: TPlayerHoldUnit;
begin
  H := ActorHuman(Command);
  RequireHeldItem(Command);
  Index := IntArg(Command, 0);
  Expanded := IntArg(Command, 1) <> 0;
  Entry := FindHoldEntry(H, Index, Expanded);
  RequireHoldCellItem(Command, H, Entry);
  H.PlayerHoldShip.Artefacts.Add(H.SelectedHoldItem);
  (H.SelectedHoldItem as TEquipment).EquippedFlag := 0;
  if H.SelectedHoldItem is TArtefactTranclucator then
    (TObject((H.SelectedHoldItem as TArtefactTranclucator).Ship) as TTranclucator).OwnerShip :=
        Actor(Command);
  if not Expanded then
  begin
    if Entry = nil then
    begin
      Count := Index - H.PlayerHoldEntries.Count + 1;
      for J := 0 to Count - 1 do
      begin
        Entry := TPlayerHoldUnit.Create;
        H.PlayerHoldEntries.Add(Entry);
        Entry.Kind := phkEmpty;
      end;
      Entry := TPlayerHoldUnit(H.PlayerHoldEntries[H.PlayerHoldEntries.Count - 1]);
    end
    else
    begin
      if Entry.Kind <> phkEmpty then
      begin
        Entry := TPlayerHoldUnit.Create;
        H.PlayerHoldEntries.Insert(Index, Entry);
        Entry.Kind := phkEmpty;
      end;
    end;
    Entry.Kind := phkArtefact;
    Entry.ItemId := H.SelectedHoldItem.Id;
    Entry.Item := H.SelectedHoldItem;
    RemoveEmptyPlayerHoldSlot(H, H.PlayerHoldEntries.IndexOf(Entry) + 1);
    H.SelectedHoldKind := phkEmpty;
    H.SelectedHoldItem := nil;
  end
  else
  begin
    if (Entry <> nil) and (Entry.Item <> nil) and (Entry.Item.NoDropFlag > 0) then
      Entry := nil;
    Swap := nil;
    if Entry = nil then
    begin
      Entry := TPlayerHoldUnit.Create;
      H.PlayerHoldEntries.Add(Entry);
    end
    else
    begin
      if Entry.Kind <> phkEmpty then
      begin
        Swap := Entry;
        Entry := TPlayerHoldUnit.Create;
        H.PlayerHoldEntries.Add(Entry);
      end;
    end;
    Entry.DisplayOrder := Index;
    Entry.Kind := phkArtefact;
    Entry.ItemId := H.SelectedHoldItem.Id;
    Entry.Item := H.SelectedHoldItem;
    if Swap <> nil then
      TakeHoldEntry(Swap, Index, Expanded)
    else
    begin
      H.SelectedHoldKind := phkEmpty;
      H.SelectedHoldItem := nil;
    end;
    RestorePlayerHoldDisplayOrder(H);
  end;
  H.PlayerHoldShip.RefreshDerivedStats(True);
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
  H: THuman;
  P: TPlayer;
  Slot, Count: Integer;
  Item: TItem;
begin
  H := ActorHuman(Command);
  RequireHeld(Command);
  P := Actor(Command);
  Slot := IntArg(Command, 0);
  Count := IntArg(Command, 1);
  if (H.SelectedHoldKind = phkEquipment)
      and (H.SelectedHoldItem is TCountableItem)
      and (TCountableItem(H.SelectedHoldItem).StackCount >= 1) then
  begin
    Item := (H.SelectedHoldItem as TCountableItem).Split(Count);
    P.MergeItemIntoPlayerStorage(Item, GetLocalStorageOwner(H), Slot);
    if TCountableItem(H.SelectedHoldItem).StackCount < 1 then
    begin
      H.SelectedHoldItem.Free;
      H.SelectedHoldItem := nil;
      H.SelectedHoldKind := phkEmpty;
    end;
  end
  else if (H.SelectedHoldKind = phkEquipment) or (H.SelectedHoldKind = phkArtefact) then
  begin
    if H.SelectedHoldItem is TArtefactTranclucator then
      (TObject((H.SelectedHoldItem as TArtefactTranclucator).Ship) as TTranclucator).OwnerShip := nil;
    H.SelectedHoldKind := phkEmpty;
    P.AddItemToPlayerStorage(H.SelectedHoldItem, GetLocalStorageOwner(H), Slot);
  end
  else if H.SelectedHoldKind = phkGoods then
  begin
    P.AddGoodsToPlayerStorage(
        H.SelectedGoodsIndex,
        Count,
        Round(Count / H.SelectedGoodsQuantity * H.SelectedGoodsCost),
        GetLocalStorageOwner(H),
        Slot
    );
    Dec(H.SelectedGoodsCost, Round(Count / H.SelectedGoodsQuantity * H.SelectedGoodsCost));
    Dec(H.SelectedGoodsQuantity, Count);
    if H.SelectedGoodsQuantity < 1 then
      H.SelectedHoldKind := phkEmpty;
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
var
  H: THuman;
begin
  H := ActorHuman(Command);
  Actor(Command).CloseVacantStorageSlot(GetLocalStorageOwner(H), IntArg(Command, 0));
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
  H: THuman;
  Item: TItem;
  Quantity, ActionResult: Integer;
begin
  H := ActorHuman(Command);
  if H.SelectedHoldKind <> phkGoods then
    raise Exception.Create('UseHeldGoodsOn needs held goods');
  ActionResult := 0;
  case IntArg(Command, 0) of
    hsEquipmentSlot:
    begin
      Item := H.PlayerHoldShip.FindEquippedItemInSlot(IntArg(Command, 1), IntArg(Command, 2));
      if Item.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(Item.ScriptItem)
                .RunActionCode(
                    satOnAnotherGoods,
                    H.PlayerHoldShip,
                    TObject(H.SelectedGoodsIndex),
                    TObject(H.SelectedGoodsQuantity),
                    0);
    end;
    hsArtefactSlot:
    begin
      Item := H.PlayerHoldShip.FindEquippedItemInSlot(Ord(t_Artefact), IntArg(Command, 1));
      if Item.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(Item.ScriptItem)
                .RunActionCode(
                    satOnAnotherGoods,
                    H.PlayerHoldShip,
                    TObject(H.SelectedGoodsIndex),
                    TObject(H.SelectedGoodsQuantity),
                    0)
      else
        ActionResult :=
            RunItemConfigActionCode(
                Item,
                satOnAnotherGoods,
                H.PlayerHoldShip,
                TObject(H.SelectedGoodsIndex),
                TObject(H.SelectedGoodsQuantity),
                0
            );
    end;
    hsHull:
    begin
      if H.PlayerHoldShip.GetHull.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(H.PlayerHoldShip.GetHull.ScriptItem)
                .RunActionCode(
                    satOnAnotherGoods,
                    H.PlayerHoldShip,
                    TObject(H.SelectedGoodsIndex),
                    TObject(H.SelectedGoodsQuantity),
                    0);
    end;
  else
    raise Exception.Create('UseHeldGoodsOn names an unknown target');
  end;
  if ActionResult <> 0 then
  begin
    Quantity := Abs(ActionResult);
    if Quantity < H.SelectedGoodsQuantity then
    begin
      Dec(H.SelectedGoodsCost, Round(Quantity / H.SelectedGoodsQuantity * H.SelectedGoodsCost));
      Dec(H.SelectedGoodsQuantity, Quantity);
    end
    else
    begin
      H.SelectedHoldKind := phkEmpty;
      H.SelectedGoodsQuantity := 0;
      H.SelectedGoodsCost := 0;
    end;
  end;
  H.PlayerHoldShip.RefreshDerivedStats(True);
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
  H: THuman;
  Site, ActionResult: Integer;
  Item: TItem;
  Entry: TPlayerHoldUnit;
begin
  H := ActorHuman(Command);
  RequireHeldItem(Command);
  Site := IntArg(Command, 0);
  ActionResult := 0;
  case Site of
    hsEquipmentSlot:
    begin
      Item := H.PlayerHoldShip.FindEquippedItemInSlot(IntArg(Command, 1), IntArg(Command, 2));
      if H.SelectedHoldItem.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(H.SelectedHoldItem.ScriptItem)
                .RunActionCode(satOnAnotherItem, H.PlayerHoldShip, Item, nil, ActionResult);
      if H.SelectedHoldItem is TEquipmentWithActCode then
        ActionResult :=
            RunItemConfigActionCode(
                H.SelectedHoldItem,
                satOnAnotherItem,
                H.PlayerHoldShip,
                Item,
                nil,
                ActionResult
            );
      if Item.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(Item.ScriptItem)
                .RunActionCode(
                    satOnAnotherItem2,
                    H.PlayerHoldShip,
                    H.SelectedHoldItem,
                    nil,
                    ActionResult);
      if Item is TEquipmentWithActCode then
        ActionResult :=
            RunItemConfigActionCode(
                Item,
                satOnAnotherItem2,
                H.PlayerHoldShip,
                H.SelectedHoldItem,
                nil,
                ActionResult
            );
    end;
    hsArtefactSlot:
    begin
      Item := H.PlayerHoldShip.FindEquippedItemInSlot(Ord(t_Artefact), IntArg(Command, 1));
      if H.SelectedHoldItem.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(H.SelectedHoldItem.ScriptItem)
                .RunActionCode(satOnAnotherItem, H.PlayerHoldShip, Item, nil, ActionResult);
      if H.SelectedHoldItem is TEquipmentWithActCode then
        ActionResult :=
            RunItemConfigActionCode(
                H.SelectedHoldItem,
                satOnAnotherItem,
                H.PlayerHoldShip,
                Item,
                nil,
                ActionResult
            );
      if Item.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(Item.ScriptItem)
                .RunActionCode(
                    satOnAnotherItem2,
                    H.PlayerHoldShip,
                    H.SelectedHoldItem,
                    nil,
                    ActionResult);
      ActionResult :=
          RunItemConfigActionCode(
              Item,
              satOnAnotherItem2,
              H.PlayerHoldShip,
              H.SelectedHoldItem,
              nil,
              ActionResult
          );
    end;
    hsHoldEquipment:
    begin
      Entry := HoldEntryArg(Command, 1);
      if H.SelectedHoldItem.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(H.SelectedHoldItem.ScriptItem)
                .RunActionCode(satOnAnotherItem, H.PlayerHoldShip, Entry.Item, nil, ActionResult);
      if H.SelectedHoldItem is TEquipmentWithActCode then
        ActionResult :=
            RunItemConfigActionCode(
                H.SelectedHoldItem,
                satOnAnotherItem,
                H.PlayerHoldShip,
                Entry.Item,
                nil,
                ActionResult
            );
      if Entry.Item.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(Entry.Item.ScriptItem)
                .RunActionCode(
                    satOnAnotherItem2,
                    H.PlayerHoldShip,
                    H.SelectedHoldItem,
                    nil,
                    ActionResult);
      if Entry.Item is TEquipmentWithActCode then
        ActionResult :=
            RunItemConfigActionCode(
                Entry.Item,
                satOnAnotherItem2,
                H.PlayerHoldShip,
                H.SelectedHoldItem,
                nil,
                ActionResult
            );
    end;
    hsHoldArtefact:
    begin
      Entry := HoldEntryArg(Command, 1);
      if H.SelectedHoldItem.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(H.SelectedHoldItem.ScriptItem)
                .RunActionCode(satOnAnotherItem, H.PlayerHoldShip, Entry.Item, nil, ActionResult);
      ActionResult :=
          RunItemConfigActionCode(
              H.SelectedHoldItem,
              satOnAnotherItem,
              H.PlayerHoldShip,
              Entry.Item,
              nil,
              ActionResult
          );
      if Entry.Item.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(Entry.Item.ScriptItem)
                .RunActionCode(
                    satOnAnotherItem2,
                    H.PlayerHoldShip,
                    H.SelectedHoldItem,
                    nil,
                    ActionResult);
      if Entry.Item is TEquipmentWithActCode then
        ActionResult :=
            RunItemConfigActionCode(
                Entry.Item,
                satOnAnotherItem2,
                H.PlayerHoldShip,
                H.SelectedHoldItem,
                nil,
                ActionResult
            );
    end;
    hsHull:
    begin
      if H.SelectedHoldItem.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(H.SelectedHoldItem.ScriptItem)
                .RunActionCode(
                    satOnAnotherItem,
                    H.PlayerHoldShip,
                    H.PlayerHoldShip.GetHull,
                    nil,
                    ActionResult);
      if H.SelectedHoldItem is TEquipmentWithActCode then
        ActionResult :=
            RunItemConfigActionCode(
                H.SelectedHoldItem,
                satOnAnotherItem,
                H.PlayerHoldShip,
                H.PlayerHoldShip.GetHull,
                nil,
                ActionResult
            );
      if H.PlayerHoldShip.GetHull.ScriptItem <> nil then
        ActionResult :=
            TScriptItem(H.PlayerHoldShip.GetHull.ScriptItem)
                .RunActionCode(
                    satOnAnotherItem2,
                    H.PlayerHoldShip,
                    H.SelectedHoldItem,
                    nil,
                    ActionResult);
    end;
  else
    raise Exception.Create('UseHeldItemOn names an unknown target');
  end;
  if ActionResult in [1, 3] then
  begin
    H.SelectedHoldItem.Free;
    H.SelectedHoldKind := phkEmpty;
    H.SelectedHoldItem := nil;
  end;
  if (Site in [hsEquipmentSlot, hsArtefactSlot]) or (ActionResult in [1..3]) then
    H.PlayerHoldShip.RefreshDerivedStats(True);
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
var
  H: THuman;
begin
  H := ActorHuman(Command);
  case IntArg(Command, Index) of
    hsEquipmentSlot:
      Result :=
          H.PlayerHoldShip.FindEquippedItemInSlot(
              IntArg(Command, Index + 1),
              IntArg(Command, Index + 2)
          );
    hsHoldEquipment:
      Result := TEquipment(HoldEntryArg(Command, Index + 1).Item);
    hsHull:
      Result := H.PlayerHoldShip.GetHull;
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
  H: THuman;
  Item: TEquipment;
begin
  H := ActorHuman(Command);
  RequireHeldItem(Command);
  Item := TargetEquipment(Command, 0);
  H.PlayerHoldShip.ScriptItemsAct(satOnPlayerUseMM, Item, H.SelectedHoldItem, 0);
  ApplyMicroModule((H.SelectedHoldItem as TMicroModule).MicroModuleIndex - 1, Item);
  H.SelectedHoldItem.Free;
  H.SelectedHoldKind := phkEmpty;
  H.SelectedHoldItem := nil;
  H.PlayerHoldShip.RefreshDerivedStats(True);
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
  H: THuman;
  Item: TEquipment;
  Count: Integer;
  FuelFrom, FuelTo: TFuelTanks;
begin
  H := ActorHuman(Command);
  RequireHeldItem(Command);
  Item := TargetEquipment(Command, 0);
  case IntArg(Command, 3) of
    hfCisternToCistern:
    begin
      Count :=
          Min(
              (H.SelectedHoldItem as TCistern).Fuel,
              (Item as TCistern).Capacity - (Item as TCistern).Fuel
          );
      Dec((H.SelectedHoldItem as TCistern).Fuel, Count);
      Inc((Item as TCistern).Fuel, Count);
    end;
    hfFuelTanksToFuelTanks:
    begin
      FuelFrom := H.SelectedHoldItem as TFuelTanks;
      FuelTo := Item as TFuelTanks;
      Count := Min(FuelFrom.Fuel, FuelTo.Capacity - FuelTo.Fuel);
      Dec(FuelFrom.Fuel, Count);
      Inc(FuelTo.Fuel, Count);
    end;
    hfCisternToFuelTanks:
    begin
      Count :=
          Min(
              (H.SelectedHoldItem as TCistern).Fuel,
              (Item as TFuelTanks).Capacity - (Item as TFuelTanks).Fuel
          );
      Dec((H.SelectedHoldItem as TCistern).Fuel, Count);
      Inc((Item as TFuelTanks).Fuel, Count);
    end;
    hfFuelTanksToCistern:
    begin
      Count :=
          Min(
              (H.SelectedHoldItem as TFuelTanks).Fuel,
              (Item as TCistern).Capacity - (Item as TCistern).Fuel
          );
      Dec((H.SelectedHoldItem as TFuelTanks).Fuel, Count);
      Inc((Item as TCistern).Fuel, Count);
    end;
  else
    raise Exception.Create('TransferHeldFuel names an unknown transfer');
  end;
  H.PlayerHoldShip.RefreshDerivedStats(True);
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
  H: THuman;
  P: TPlayer;
  OldHull: THull;
begin
  H := ActorHuman(Command);
  RequireHeldItem(Command);
  P := Actor(Command);
  H.PlayerHoldShip
      .ScriptItemsAct(satOnPlayerChangeHull, H.SelectedHoldItem, H.PlayerHoldShip.GetHull, 0);
  OldHull := H.PlayerHoldShip.GetHull;
  H.PlayerHoldShip.Inventory.Insert(0, H.SelectedHoldItem);
  H.PlayerHoldShip.Hull := H.SelectedHoldItem as THull;
  H.PlayerHoldShip.GetHull.OwnerShip := H.PlayerHoldShip;
  H.PlayerHoldShip.GetHull.AssignedSlotData := 0;
  H.PlayerHoldShip.GetHull.EquippedFlag := 1;
  H.SelectedHoldKind := phkEmpty;
  H.SelectedHoldItem := nil;
  if OldHull <> nil then
  begin
    OldHull.OwnerShip := nil;
    H.PlayerHoldShip.Inventory.Delete(H.PlayerHoldShip.Inventory.IndexOf(OldHull));
    P.AddItemToPlayerStorage(OldHull, GetLocalStorageOwner(H), -1);
  end;
  if H.PlayerHoldShip.GetHull.ScriptItem <> nil then
    TScriptItem(H.PlayerHoldShip.GetHull.ScriptItem)
        .RunActionCode(satOnPlayerChangeHull, H.PlayerHoldShip, H.PlayerHoldShip.GetHull, OldHull, 0);
  H.PlayerHoldShip.RefreshAssignedItemSlots;
  H.PlayerHoldShip.RebuildEquipmentCache;
  H.PlayerHoldShip.RefreshDerivedStats(True);
  if not H.PlayerHoldShip.ScriptChameleon then
  begin
    ReleaseSpaceObject(H.PlayerHoldShip.Graphic);
    H.PlayerHoldShip.RefreshGraphic;
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
  H: THuman;
  P: TPlayer;
  Item: TItem;
  Goods: TGoods;
  Angle: Double;
  Effect: TWeaponSE;
  Entry: PEFilmEndEntry;
  Quantity, I, Index: Integer;
  ActionResult: Integer;
begin
  H := ActorHuman(Command);
  RequireHeld(Command);
  P := Actor(Command);
  Quantity := IntArg(Command, 0);
  DropBlock := dbNone;
  if (H.SelectedHoldKind = phkEquipment)
      and (H.SelectedHoldItem is TCountableItem)
      and (TCountableItem(H.SelectedHoldItem).StackCount > 1) then
  begin
    Item := TCountableItem(H.SelectedHoldItem).Split(Quantity);
    if (not H.PlayerHoldShip.IsOnPlanet and not H.PlayerHoldShip.IsDockedToShip)
        or ((P.RuinsMode > 0)
            and (P.RuinsSavedDockedTo = nil)
            and (P.RuinsSavedPlanet = nil)) then
    begin
      with H.PlayerHoldShip.CurrentStar do
      begin
        Items.Add(Item);
        Angle :=
            SeededRandomIntRange(
                    0,
                    360,
                    H.PlayerHoldShip.CurrentStar.GenerationSeed * Galaxy.CurrentTurn * Item.Id)
                * Pi
                / 180;
        Item.Position.X := Sin(Angle) * 100 + H.PlayerHoldShip.Position.X;
        Item.Position.Y := H.PlayerHoldShip.Position.Y - Cos(Angle) * 100;
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
    if TCountableItem(H.SelectedHoldItem).StackCount < 1 then
    begin
      H.SelectedHoldItem.Free;
      H.SelectedHoldItem := nil;
      H.SelectedHoldKind := phkEmpty;
    end;
  end
  else if (H.SelectedHoldKind = phkEquipment) or (H.SelectedHoldKind = phkArtefact) then
  begin
    if H.SelectedHoldItem is TArtefactTranclucator then
      (TObject((H.SelectedHoldItem as TArtefactTranclucator).Ship) as TTranclucator).OwnerShip := nil;
    if H.PlayerHoldShip is TRuins then
    begin
      if H.PlayerHoldShip.NeedsEquipmentType(H.SelectedHoldItem.ItemType) then
      begin
        DropBlock := dbRuins;
        Exit;
      end;
    end
    else if H.PlayerHoldShip is TTranclucator then
    begin
      if ((H.SelectedHoldItem.ItemType = t_FuelTanks) or (H.SelectedHoldItem.ItemType = t_Engine))
          and H.PlayerHoldShip.NeedsEquipmentType(H.SelectedHoldItem.ItemType) then
      begin
        DropBlock := dbTranclucator;
        Exit;
      end;
    end
    else if H.SelectedHoldItem.ItemType = t_FuelTanks then
    begin
      if H.PlayerHoldShip.GetFuelTanks = nil then
      begin
        DropBlock := dbFuelTanks;
        Exit;
      end;
    end
    else if H.SelectedHoldItem.ItemType = t_Engine then
    begin
      if H.PlayerHoldShip.GetEngine = nil then
      begin
        DropBlock := dbEngine;
        Exit;
      end;
    end
    else if H.SelectedHoldItem.NoDropFlag > 0 then
    begin
      DropBlock := dbNoDrop;
      Exit;
    end;
    if H.SelectedHoldItem is TWeapon then
      (H.SelectedHoldItem as TWeapon).Target := nil;
    if H.PlayerHoldShip.IsOnPlanet
        or (H.PlayerHoldShip.IsDockedToShip and (P.RuinsMode = 0))
        or ((P.RuinsMode > 0)
            and ((P.RuinsSavedDockedTo <> nil) or (P.RuinsSavedPlanet <> nil))) then
    begin
      H.SelectedHoldItem.Free;
      H.SelectedHoldItem := nil;
    end
    else
      with H.PlayerHoldShip.CurrentStar do
      begin
        Items.Add(H.SelectedHoldItem);
        Angle :=
            SeededRandomIntRange(
                    0,
                    360,
                    H.PlayerHoldShip.CurrentStar.GenerationSeed
                        * Galaxy.CurrentTurn
                        * H.SelectedHoldItem.Id)
                * Pi
                / 180;
        H.SelectedHoldItem.Position.X := Sin(Angle) * 100 + H.PlayerHoldShip.Position.X;
        H.SelectedHoldItem.Position.Y := H.PlayerHoldShip.Position.Y - Cos(Angle) * 100;
        ActionResult := H.PlayerHoldShip.ScriptItemsAct(satOnDropItemFixed, H.SelectedHoldItem, nil, 0);
        if H.SelectedHoldItem is TEquipmentWithActCode then
          ActionResult :=
              RunItemConfigActionCode(
                  H.SelectedHoldItem,
                  satOnDropItemFixed,
                  H.PlayerHoldShip,
                  H.SelectedHoldItem,
                  nil,
                  ActionResult
              );
        if H.SelectedHoldItem.ScriptItem <> nil then
          ActionResult :=
              TScriptItem(H.SelectedHoldItem.ScriptItem)
                  .RunActionCode(
                      satOnDropItemFixed,
                      H.PlayerHoldShip,
                      H.SelectedHoldItem,
                      nil,
                      ActionResult);
        if ActionResult = 0 then
        begin
          H.SelectedHoldItem.GetGraphObject.SetPosition(H.SelectedHoldItem.Position);
          if DamageRadius * DamageRadius
              > Sqr(H.SelectedHoldItem.Position.X) + Sqr(H.SelectedHoldItem.Position.Y) then
          begin
            Effect := TWeaponSE.Create('Weapon.NoGraph', Classes.Point(0, 0), 0, -1);
            Effect.SetEndpoints(nil, H.SelectedHoldItem.GetGraphObject);
            Effect.SetHit(0, 0, True, True);
            if TrailingFilmEffects = nil then
              TrailingFilmEffects := TEFilmEnd.Create;
            Entry := TrailingFilmEffects.AppendEntry;
            RetainSpaceObject(Entry.SceneObject, Effect);
            RetainSpaceObject(Entry.RelatedObject1, H.SelectedHoldItem.GetGraphObject);
            Items.Delete(Items.IndexOf(H.SelectedHoldItem));
            H.SelectedHoldItem.Free;
          end;
        end
        else
        begin
          Items.Delete(Items.IndexOf(H.SelectedHoldItem));
          if ActionResult < 0 then
            H.SelectedHoldItem.Free;
        end;
      end;
    H.SelectedHoldKind := phkEmpty;
    H.SelectedHoldItem := nil;
  end
  else if H.SelectedHoldKind = phkGoods then
  begin
    if (not H.PlayerHoldShip.IsOnPlanet and not H.PlayerHoldShip.IsDockedToShip)
        or ((P.RuinsMode > 0)
            and (P.RuinsSavedDockedTo = nil)
            and (P.RuinsSavedPlanet = nil)) then
      with H.PlayerHoldShip.CurrentStar do
      begin
        Goods := TGoods.Create;
        Goods.Init(TItemType(H.SelectedGoodsIndex), Quantity);
        Goods.Cost := Round(Quantity / H.SelectedGoodsQuantity * H.SelectedGoodsCost);
        for I := 0 to 20 do
        begin
          Angle :=
              SeededRandomIntRange(
                      0,
                      360,
                      H.PlayerHoldShip.CurrentStar.GenerationSeed
                          * Galaxy.CurrentTurn
                          * (H.SelectedGoodsIndex + I))
                  * Pi
                  / 180;
          Goods.Position.X := Sin(Angle) * 100 + H.PlayerHoldShip.Position.X;
          Goods.Position.Y := H.PlayerHoldShip.Position.Y - Cos(Angle) * 100;
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
    Dec(H.SelectedGoodsCost, Round(Quantity / H.SelectedGoodsQuantity * H.SelectedGoodsCost));
    Dec(H.SelectedGoodsQuantity, Quantity);
    if H.SelectedGoodsQuantity < 1 then
      H.SelectedHoldKind := phkEmpty;
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

var
  // CHANGE: ENHANCEMENT - What the last ship screen sale put into its location (RelayedSaleOf):
  // the items' ids, and the goods as pairs of the good and the count. Each sale's executor
  // starts it empty.
  SaleShopItemIds: array of Integer;
  SaleGoods: array of Integer;

procedure BeginSaleRecord;
begin
  SaleShopItemIds := nil;
  SaleGoods := nil;
end;

procedure NoteSoldIntoShop(Item: TItem);
begin
  Insert(Integer(Item.Id), SaleShopItemIds, Length(SaleShopItemIds));
end;

procedure NoteSoldGoods(Good: Byte; Count: Integer);
begin
  if Count <= 0 then
    Exit;
  Insert(Good, SaleGoods, Length(SaleGoods));
  Insert(Count, SaleGoods, Length(SaleGoods));
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
  H: THuman;
  Count, Cost, Price: Integer;
  Event: TGalaxyEvent;
begin
  H := ActingHuman;
  Result := False;
  if Item = nil then
    Exit;
  if not IgnoreRequiredEquipment then
  begin
    if H.PlayerHoldShip is TRuins then
    begin
      if H.PlayerHoldShip.NeedsEquipmentType(Item.ItemType) then
        Exit;
    end
    else if ((Item.ItemType = t_FuelTanks) or (Item.ItemType = t_Engine))
        and H.PlayerHoldShip.NeedsEquipmentType(Item.ItemType) then
      Exit;
  end;
  if Item.ItemType in [t_Food..t_Narcotics] then
  begin
    Count := P.CargoGoods[Ord(Item.ItemType)].Count;
    Cost := P.CargoGoods[Ord(Item.ItemType)].TotalCost;
    P.CargoGoods[Ord(Item.ItemType)].Count := (Item as TGoods).Quantity;
    P.CargoGoods[Ord(Item.ItemType)].TotalCost := (Item as TGoods).Cost;
    P.SellGoodsToLocation(Byte(Item.ItemType), (Item as TGoods).Quantity);
    NoteSoldGoods(Byte(Item.ItemType), (Item as TGoods).Quantity);
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
      RestoreTemporaryShopStock(H);
      if P.CurrentPlanet <> nil then
        P.CurrentPlanet.EquipmentShop.Add(Item)
      else
        (P.DockedTo as TRuins).EquipmentShop.Add(Item);
      NoteSoldIntoShop(Item);
      // CHANGE: BUGFIX - The actor's columns, not this machine's (THuman.ShopColumnCount).
      H.ShopColumnCount := Columns;
      BuildTemporaryShopSlotGrid(H);
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
  H: THuman;
  P: TPlayer;
  Count, Price, Columns: Integer;
  Item: TItem;
  Event: TGalaxyEvent;
begin
  H := ActorHuman(Command);
  RequireHeld(Command);
  P := Actor(Command);
  Count := IntArg(Command, 0);
  Columns := IntArg(Command, 1);
  Price := 0;
  BeginSaleRecord;
  if (H.SelectedHoldKind = phkEquipment) or (H.SelectedHoldKind = phkArtefact) then
  begin
    if (H.SelectedHoldItem is TCountableItem)
        and ((H.SelectedHoldItem as TCountableItem).StackCount > 1) then
    begin
      Item := (H.SelectedHoldItem as TCountableItem).Split(Count);
      Price := Item.CalculateResaleValue(P.GetEffectiveSkillLevel(psTrading));
      P.SetMoney(P.Money + Price);
      Item.Free;
    end
    else
    begin
      Price := H.SelectedHoldItem.CalculateResaleValue(P.GetEffectiveSkillLevel(psTrading));
      P.SetMoney(P.Money + Price);
      if H.SelectedHoldItem is TCountableItem then
        (H.SelectedHoldItem as TCountableItem).StackCount := 0;
    end;
    if not (H.SelectedHoldItem is TCountableItem) then
    begin
      Event := AddGalaxyEvent('PlayerSellsEquipment');
      Event.AddData(Ord(H.SelectedHoldItem.ItemType));
      Event.AddData(
          H.SelectedHoldItem.CalculateResaleValue(P.GetEffectiveSkillLevel(psTrading))
      );
      Event.AddData(H.SelectedHoldItem.Weight);
      Event.AddData(H.SelectedHoldItem.Id);
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
      Event.AddTextData(H.SelectedHoldItem.GetDisplayName);
      Event.AddTextData(H.SelectedHoldItem.GetCategoryConfigName);
    end;
    if H.SelectedHoldItem is TWeapon then
      (H.SelectedHoldItem as TWeapon).Target := nil;
    if (H.SelectedHoldKind = phkEquipment)
        and (H.SelectedHoldItem.ItemType = t_Hull)
        and ((H.SelectedHoldItem as THull).HullType = htSpecial) then
    begin
      H.SelectedHoldItem.Free;
      H.SelectedHoldItem := nil;
    end
    else if (H.SelectedHoldItem.OwnerId in [Ord(oiMaloc)..Ord(oiGaal), Ord(oiPirate)])
        and (H.SelectedHoldKind = phkEquipment)
        and (H.SelectedHoldItem.ItemType in [t_Hull..t_CustomWeapon])
        and (not (H.SelectedHoldItem is TWeapon)
            or (TWeapon(H.SelectedHoldItem).GetWeaponInfo.Availability
                <> waNotSoldAndNodeRepair)) then
    begin
      RestoreTemporaryShopStock(H);
      if P.CurrentPlanet <> nil then
        P.CurrentPlanet.EquipmentShop.Add(H.SelectedHoldItem)
      else
        (P.DockedTo as TRuins).EquipmentShop.Add(H.SelectedHoldItem);
      NoteSoldIntoShop(H.SelectedHoldItem);
      // CHANGE: BUGFIX - The actor's columns, not this machine's (THuman.ShopColumnCount).
      H.ShopColumnCount := Columns;
      BuildTemporaryShopSlotGrid(H);
    end
    else if not (H.SelectedHoldItem is TCountableItem)
        or ((H.SelectedHoldItem as TCountableItem).StackCount = 0) then
    begin
      H.SelectedHoldItem.Free;
      H.SelectedHoldItem := nil;
    end;
    if (H.SelectedHoldItem = nil)
        or not (H.SelectedHoldItem is TCountableItem)
        or ((H.SelectedHoldItem as TCountableItem).StackCount = 0) then
    begin
      H.SelectedHoldItem := nil;
      H.SelectedHoldKind := phkEmpty;
    end;
  end
  else if H.SelectedHoldKind = phkGoods then
  begin
    Inc(P.CargoGoods[H.SelectedGoodsIndex].Count, H.SelectedGoodsQuantity);
    Inc(P.CargoGoods[H.SelectedGoodsIndex].TotalCost, H.SelectedGoodsCost);
    P.SellGoodsToLocation(H.SelectedGoodsIndex, Count);
    NoteSoldGoods(H.SelectedGoodsIndex, Count);
    H.SelectedHoldKind := phkEmpty;
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
  SubmitTrade(Command);
  Result := SalePrice;
end;

// Puts the held item into a free slot of its kind, as the services do after they repaired
// or reloaded it. Moved from TfShip2.SpecialSlot3Clicked and LoadRockets.
procedure EquipHeldInFreeSlot;
var
  H: THuman;
  I: Integer;
begin
  H := ActingHuman;
  I := 0;
  while I < H.PlayerHoldShip.GetSlotCountForItemType(Byte(H.SelectedHoldItem.ItemType)) do
  begin
    if H.PlayerHoldShip.FindEquippedItemInSlot(Byte(H.SelectedHoldItem.ItemType), I) = nil then
      Break;
    Inc(I);
  end;
  if I < H.PlayerHoldShip.GetSlotCountForItemType(Byte(H.SelectedHoldItem.ItemType)) then
  begin
    if H.SelectedHoldItem is TWeapon then
      (H.SelectedHoldItem as TWeapon).Target := nil;
    H.PlayerHoldShip.Inventory.Add(H.SelectedHoldItem);
    (H.SelectedHoldItem as TEquipment).AssignedSlotData :=
        ((H.SelectedHoldItem as TEquipment).AssignedSlotData and EquipmentSecondaryFireFlag)
            or I;
    (H.SelectedHoldItem as TEquipment).EquippedFlag := 0;
    (H.SelectedHoldItem as TEquipment).Equip;
    H.SelectedHoldKind := phkEmpty;
    H.SelectedHoldItem := nil;
  end;
end;

// Moved from TfShip2.SpecialSlot1Clicked, after the screen checked the money and asked for
// the nodes.
procedure ExecuteRepairHeld(const Command: TPlayerCommand);
var
  H: THuman;
  P: TPlayer;
  I, Nodes: Integer;
begin
  H := ActorHuman(Command);
  RequireHeldItem(Command);
  P := Actor(Command);
  Nodes := IntArg(Command, 0);
  // CHANGE: BUGFIX - As the screen checks before it repairs (TfShip2.SpecialSlot1Clicked): a
  // command from a client the money does not cover stopped the money at 0 and repaired the
  // item all the same (docs/network.md, Commands).
  if (H.SelectedHoldItem as TEquipment).CalculateRepairCost > P.Money then
    raise ECommandRefused.CreateReason(rrNoMoney, 'RepairHeld: not enough money');
  if Nodes > 0 then
    P.ConsumeAvailableNodes(Nodes, H.PlayerHoldShip);
  P.SetMoney(P.Money - (H.SelectedHoldItem as TEquipment).CalculateRepairCost);
  (H.SelectedHoldItem as TEquipment).Repair;
  if H.SelectedHoldKind = phkEquipment then
    EquipHeldInFreeSlot
  else if (H.SelectedHoldKind = phkArtefact)
      and (not H.PlayerHoldShip.HasEquippedArtefactOfSameUseGroup(H.SelectedHoldItem)
          or Galaxy.AreDuplicateArtefactsEnabled) then
  begin
    I := 0;
    while I < H.PlayerHoldShip.GetSlotCountForItemType(Byte(H.SelectedHoldItem.ItemType)) do
    begin
      if H.PlayerHoldShip.FindEquippedItemInSlot(Byte(H.SelectedHoldItem.ItemType), I) = nil then
        Break;
      Inc(I);
    end;
    if I < H.PlayerHoldShip.GetSlotCountForItemType(Byte(H.SelectedHoldItem.ItemType)) then
    begin
      H.PlayerHoldShip.Artefacts.Add(H.SelectedHoldItem);
      if (H.PlayerHoldShip.GetSlotCountForItemType(Byte(H.SelectedHoldItem.ItemType))
              <= Integer((H.SelectedHoldItem as TEquipment).AssignedSlotData))
          or (H.PlayerHoldShip.FindEquippedItemInSlot(
                  Byte(H.SelectedHoldItem.ItemType),
                  Integer((H.SelectedHoldItem as TEquipment).AssignedSlotData))
              <> nil) then
        (H.SelectedHoldItem as TEquipment).AssignedSlotData := I;
      (H.SelectedHoldItem as TEquipment).EquippedFlag := 0;
      (H.SelectedHoldItem as TEquipment).Equip;
      H.SelectedHoldKind := phkEmpty;
      H.SelectedHoldItem := nil;
    end;
  end;
end;

procedure RepairHeld(Nodes: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckRepairHeld);
  AddInt(Command, Nodes);
  SubmitTrade(Command);
end;

// Moved from TfShip2.SpecialSlot3Clicked, after the screen checked the money and asked how
// much.
procedure ExecuteRefuelHeld(const Command: TPlayerCommand);
var
  H: THuman;
  P: TPlayer;
  Amount, Cost: Integer;
begin
  H := ActorHuman(Command);
  RequireHeldItem(Command);
  P := Actor(Command);
  Amount := IntArg(Command, 0);
  if P.IsOnPlanet then
    Cost := CalculateRoundedFuelCost(Amount, P.CurrentPlanet.OwnerId)
  else
    Cost := CalculateRoundedFuelCost(Amount, 6);
  if P.Money < Cost then
    raise ECommandRefused.CreateReason(rrNoMoney, 'RefuelHeld: not enough money');
  P.SetMoney(P.Money - Cost);
  if H.SelectedHoldItem is TCistern then
    Inc((H.SelectedHoldItem as TCistern).Fuel, Amount)
  else
    Inc((H.SelectedHoldItem as TFuelTanks).Fuel, Amount);
end;

procedure RefuelHeld(Amount: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckRefuelHeld);
  AddInt(Command, Amount);
  SubmitTrade(Command);
end;

// Moved from TfShip2.SpecialSlot3Clicked, after the screen checked the money and asked how
// much.
procedure ExecuteReloadHeld(const Command: TPlayerCommand);
var
  H: THuman;
  P: TPlayer;
  Amount, Cost: Integer;
  UnitPrice: Single;
  Weapon: TWeapon;
begin
  H := ActorHuman(Command);
  RequireHeldItem(Command);
  P := Actor(Command);
  Amount := IntArg(Command, 0);
  Weapon := H.SelectedHoldItem as TWeapon;
  UnitPrice := Galaxy.ScaleIntByTechLevel(10, 100);
  Cost := Round(Amount * UnitPrice);
  if P.Money < Cost then
    raise ECommandRefused.CreateReason(rrNoMoney, 'ReloadHeld: not enough money');
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
  SubmitTrade(Command);
end;

var
  RepairAllPaid: Boolean;

// Moved from TfShip2.RepairAllClicked, after the screen checked the money and asked for the
// nodes; Nodes is 0 when it did not take them. The costs are computed again the same way.
procedure ExecuteRepairAll(const Command: TPlayerCommand);
var
  H: THuman;
  P: TPlayer;
  I, Cost, NodeCost, Nodes: Integer;
  Item: TEquipment;
begin
  H := ActorHuman(Command);
  P := Actor(Command);
  Nodes := IntArg(Command, 0);
  RepairedItems := nil;
  RepairAllPaid := False;
  Cost := 0;
  NodeCost := 0;
  for I := 0 to H.PlayerHoldShip.Inventory.Count - 1 do
  begin
    Item := H.PlayerHoldShip.Inventory[I];
    if H.PlayerHoldShip.CanRepairEquipmentTech(Item)
        and (Item <> H.SelectedHoldItem)
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
  // CHANGE: BUGFIX - As the screen checks before it asks for the nodes (TfShip2.RepairAllClicked):
  // the money stopped at 0 and everything was repaired all the same (docs/network.md, Commands).
  if (Cost + NodeCost > 0) and (P.Money < Cost + NodeCost) then
    raise ECommandRefused.CreateReason(rrNoMoney, 'RepairAll: not enough money');
  if (NodeCost > 0) and (Nodes <> 0) then
    P.ConsumeAvailableNodes(Nodes, H.PlayerHoldShip);
  if Nodes <> 0 then
    Inc(Cost, NodeCost);
  if Cost > 0 then
  begin
    RepairAllPaid := True;
    P.SetMoney(P.Money - Cost);
    for I := 0 to H.PlayerHoldShip.Inventory.Count - 1 do
    begin
      Item := H.PlayerHoldShip.Inventory[I];
      if H.PlayerHoldShip.CanRepairEquipmentTech(Item)
          and (not (Item is TWeapon)
              or (TWeapon(Item).GetWeaponInfo.Availability <> waNotSoldAndNodeRepair)
              or (Nodes <> 0))
          and (Item <> H.SelectedHoldItem)
          and ((Item.EquippedFlag <> 0) or (Item is THull))
          and Item.NeedsRepair then
      begin
        Item.Repair;
        SetLength(RepairedItems, Length(RepairedItems) + 1);
        RepairedItems[High(RepairedItems)] := Item;
      end;
    end;
    if H.SelectedHoldKind = phkEquipment then
      EquipHeldInFreeSlot
    else if (H.SelectedHoldKind = phkArtefact)
        and (not H.PlayerHoldShip.HasEquippedArtefactOfSameUseGroup(H.SelectedHoldItem)
            or Galaxy.AreDuplicateArtefactsEnabled) then
    begin
      H.PlayerHoldShip.Artefacts.Add(H.SelectedHoldItem);
      (H.SelectedHoldItem as TEquipment).AssignedSlotData := 0;
      (H.SelectedHoldItem as TEquipment).EquippedFlag := 0;
      (H.SelectedHoldItem as TEquipment).Equip;
      H.SelectedHoldKind := phkEmpty;
      H.SelectedHoldItem := nil;
    end;
  end;
end;

function RepairAll(Nodes: Integer): Boolean;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckRepairAll);
  AddInt(Command, Nodes);
  SubmitTrade(Command);
  Result := RepairAllPaid;
end;

// Moved from TfShip2.LoadRockets, after the screen checked the money and asked; the cost is
// computed again the same way.
procedure ExecuteBuyRockets(const Command: TPlayerCommand);
var
  H: THuman;
  P: TPlayer;
  I, Cost, Quantity: Integer;
  Item: TEquipment;
  Equipped: Boolean;
  Event: TGalaxyEvent;
begin
  H := ActorHuman(Command);
  P := Actor(Command);
  Equipped := IntArg(Command, 0) <> 0;
  Cost := 0;
  for I := 0 to H.PlayerHoldShip.Inventory.Count - 1 do
  begin
    Item := H.PlayerHoldShip.Inventory[I];
    if (Equipped = Boolean(Item.EquippedFlag))
        and (Item <> H.SelectedHoldItem)
        and (Item is TWeapon)
        and (Item as TWeapon).NeedsAmmo then
      Inc(Cost, (Item as TWeapon).CalculateAmmoRefillCost);
  end;
  if P.Money < Cost then
    raise ECommandRefused.CreateReason(rrNoMoney, 'BuyRockets: not enough money');
  P.SetMoney(P.Money - Cost);
  Quantity := 0;
  for I := 0 to H.PlayerHoldShip.Inventory.Count - 1 do
  begin
    Item := H.PlayerHoldShip.Inventory[I];
    if (Equipped = Boolean(Item.EquippedFlag))
        and (Item <> H.SelectedHoldItem)
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
  if H.SelectedHoldKind = phkEquipment then
    EquipHeldInFreeSlot
  else if (H.SelectedHoldKind = phkArtefact)
      and (not H.PlayerHoldShip.HasEquippedArtefactOfSameUseGroup(H.SelectedHoldItem)
          or Galaxy.AreDuplicateArtefactsEnabled) then
  begin
    H.PlayerHoldShip.Artefacts.Add(H.SelectedHoldItem);
    (H.SelectedHoldItem as TEquipment).AssignedSlotData := 0;
    (H.SelectedHoldItem as TEquipment).EquippedFlag := 0;
    (H.SelectedHoldItem as TEquipment).Equip;
    H.SelectedHoldKind := phkEmpty;
    H.SelectedHoldItem := nil;
  end;
end;

procedure BuyRockets(Equipped: Boolean);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckBuyRockets);
  AddInt(Command, Ord(Equipped));
  SubmitTrade(Command);
end;

var
  UseItemResult: Integer;

// Moved from TfShip2.UseMouseUp: the item was held and went back first (ReturnHeldEntry).
procedure ExecuteUseItem(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  UseItemResult := RunItemUseCode(ShownItemArg(Command, 0), H.PlayerHoldShip);
end;

function UseItem(Item: TItem): Integer;
var
  Command: TPlayerCommand;
begin
  // An item that did not go back to the ship or the storage cannot be named; its script runs
  // unrecorded, and the command log then writes a checkpoint.
  if FindShownItem(LocalHuman, Item.Id) <> Item then
    Exit(RunItemUseCode(Item, LocalHuman.PlayerHoldShip));
  Command := NewCommand(ckUseItem);
  AddInt(Command, Item.Id);
  SubmitCommand(Command);
  Result := UseItemResult;
end;

// Moved from TfShip2.UseMouseUp. The text is the page the screen's resources show.
procedure ExecuteShowTreasureMap(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  if not (H.SelectedHoldItem is TTreasureMap) then
    raise Exception.Create('ShowTreasureMap needs a held treasure map');
  H.AddOrUpdateBubble(
      7,
      Galaxy.CurrentTurn,
      Command.Text,
      (H.SelectedHoldItem as TTreasureMap).GetTargetPlanetName
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
  H: THuman;
  P: TPlayer;
  I: Integer;
  Item: TItem;
begin
  H := ActorHuman(Command);
  P := Actor(Command);
  BeginSaleRecord;
  I := H.PlayerHoldShip.Inventory.Count - 1;
  while I >= 0 do
  begin
    Item := H.PlayerHoldShip.Inventory[I];
    if (Item.NoDropFlag = 0)
        and (Item.ItemType <> t_Hull)
        and (TEquipment(Item).EquippedFlag = 0)
        and ((Item.ScriptItem = nil) or TScriptItem(Item.ScriptItem).CanSell)
        and P.CanAccessStoredItem(Item) then
      if SellItem(P, Item, False, IntArg(Command, 0)) then
        H.PlayerHoldShip.Inventory.Delete(I);
    Dec(I);
  end;
end;

procedure SellHoldInventory;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckSellHoldInventory);
  AddInt(Command, ShopVisibleColumnCount);
  SubmitTrade(Command);
end;

// Moved from TfShip2.SellAllItems: one loose artefact, after the screen asked about a
// tranclucator.
procedure ExecuteSellHoldArtefact(const Command: TPlayerCommand);
var
  H: THuman;
  Index: Integer;
  Item: TItem;
begin
  H := ActorHuman(Command);
  BeginSaleRecord;
  Index := IntArg(Command, 0);
  if (Index < 0) or (Index >= H.PlayerHoldShip.Artefacts.Count) then
    raise Exception.Create('SellHoldArtefact names a missing artefact');
  Item := H.PlayerHoldShip.Artefacts[Index];
  if Item.Id <> IntArg(Command, 1) then
    raise Exception.Create('SellHoldArtefact names another artefact');
  H.PlayerHoldShip.Artefacts.Delete(Index);
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
  SubmitTrade(Command);
end;

// Moved from TfShip2.SellAllItems: the goods of one kind in the hold, after the screen asked
// about illegal goods.
procedure ExecuteSellHoldGoods(const Command: TPlayerCommand);
var
  H: THuman;
  P: TPlayer;
  Good: Byte;
  SavedCount, SavedCost, Sold: Integer;
begin
  H := ActorHuman(Command);
  P := Actor(Command);
  Good := IntArg(Command, 0);
  BeginSaleRecord;
  SaleChanged := True;
  SalePlaySound := True;
  if P = H.PlayerHoldShip then
  begin
    SavedCount := P.CargoGoods[Good].Count;
    P.SellGoodsToLocation(Good, SavedCount);
    NoteSoldGoods(Good, SavedCount);
  end
  else
  begin
    SavedCount := P.CargoGoods[Good].Count;
    SavedCost := P.CargoGoods[Good].TotalCost;
    P.CargoGoods[Good].Count := H.PlayerHoldShip.CargoGoods[Good].Count;
    P.CargoGoods[Good].TotalCost := H.PlayerHoldShip.CargoGoods[Good].TotalCost;
    H.PlayerHoldShip.CargoGoods[Good].Count := 0;
    H.PlayerHoldShip.CargoGoods[Good].TotalCost := 0;
    Sold := P.CargoGoods[Good].Count;
    P.SellGoodsToLocation(Good, Sold);
    NoteSoldGoods(Good, Sold);
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
  SubmitTrade(Command);
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
  BeginSaleRecord;
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
  AddInt(Command, PStorageEntry(LocalPlayer.StorageEntries[StorageIndex]).Item.Id);
  AddInt(Command, ShopVisibleColumnCount);
  SubmitTrade(Command);
end;

function IsShipScreenSale(Kind: TCommandKind): Boolean;
begin
  Result := (Kind = ckSellHeld)
      or (Kind = ckSellHoldInventory)
      or (Kind = ckSellHoldArtefact)
      or (Kind = ckSellHoldGoods)
      or (Kind = ckSellStoredItem);
end;

// RelayedSale: the location; the actor's money, the count of items and their ids, the count of
// goods and the goods as pairs of the good and the count.
function RelayedSaleOf(const Command: TPlayerCommand; Location: TObject): TPlayerCommand;
var
  I: Integer;
begin
  Result := Default(TPlayerCommand);
  if not IsShipScreenSale(Command.Kind)
      or (Location = nil)
      or ((Length(SaleShopItemIds) = 0) and (Length(SaleGoods) = 0)) then
    Exit;
  Result.Kind := ckRelayedSale;
  Result.Actor := Command.Actor;
  AddRef(Result, Location);
  AddInt(Result, Actor(Command).Money);
  AddInt(Result, Length(SaleShopItemIds));
  for I := 0 to High(SaleShopItemIds) do
    AddInt(Result, SaleShopItemIds[I]);
  AddInt(Result, Length(SaleGoods) div 2);
  for I := 0 to High(SaleGoods) do
    AddInt(Result, SaleGoods[I]);
end;

// The item with that id on Ship, as equipment (not its hull) or an artefact. Take: it leaves
// the ship, unequipped first, as the ship screen's Take commands take it.
function ShipSaleItem(Ship: TShip; Id: Integer; Take: Boolean): TItem;
var
  I: Integer;
  Item: TItem;
begin
  Result := nil;
  if Ship = nil then
    Exit;
  for I := 0 to Ship.Inventory.Count - 1 do
  begin
    Item := TItem(Ship.Inventory[I]);
    if (Integer(Item.Id) <> Id) or (Item.ItemType = t_Hull) then
      Continue;
    if Take then
    begin
      if (Item is TEquipment) and (TEquipment(Item).EquippedFlag <> 0) then
        Ship.UnequipItem(TEquipment(Item));
      Ship.Inventory.Delete(Ship.Inventory.IndexOf(Item));
      Ship.RebuildEquipmentCache;
      Ship.RefreshDerivedStats(True);
    end;
    Exit(Item);
  end;
  for I := 0 to Ship.Artefacts.Count - 1 do
  begin
    Item := TItem(Ship.Artefacts[I]);
    if Integer(Item.Id) <> Id then
      Continue;
    if Take then
    begin
      if (Item is TEquipment) and (TEquipment(Item).EquippedFlag <> 0) then
        TEquipment(Item).Unequip;
      Ship.Artefacts.Delete(Ship.Artefacts.IndexOf(Item));
      Ship.RefreshDerivedStats(True);
    end;
    Exit(Item);
  end;
end;

// The item with that id among what the human has: its ranger's equipment and artefacts, the
// ship its screen edits, its storage, and the item it holds on the ship screen. Take: it is
// taken from there.
function HumanSaleItem(H: THuman; P: TPlayer; Id: Integer; Take: Boolean): TItem;
var
  I: Integer;
  Entry: PStorageEntry;
begin
  Result := ShipSaleItem(P, Id, Take);
  if (Result = nil) and (H.PlayerHoldShip <> P) then
    Result := ShipSaleItem(H.PlayerHoldShip, Id, Take);
  if Result <> nil then
    Exit;
  for I := 0 to P.StorageEntries.Count - 1 do
  begin
    Entry := P.StorageEntries[I];
    if (Entry.Item = nil) or (Integer(Entry.Item.Id) <> Id) then
      Continue;
    Result := Entry.Item;
    if Take then
    begin
      P.StorageEntries.Delete(I);
      Entry.LocationOwner := nil;
      Entry.Item := nil;
      Dispose(Entry);
    end;
    Exit;
  end;
  if (H.SelectedHoldKind in [phkEquipment, phkArtefact])
      and (H.SelectedHoldItem <> nil)
      and (Integer(H.SelectedHoldItem.Id) = Id) then
  begin
    Result := H.SelectedHoldItem;
    if Take then
    begin
      H.SelectedHoldItem := nil;
      H.SelectedHoldKind := phkEmpty;
    end;
  end;
end;

// CHANGE: ENHANCEMENT - Runs a host's relay of another human's ship screen sale (RelayedSaleOf,
// docs/network.md, Trades) on this copy: the items go from wherever the actor has them here
// into the location's equipment shop, the goods to its market, and the actor's money is the
// host's. A copy where the actor is not at the location, or lacks an item, changes nothing:
// the relay raises, the client logs it and drops it, and the next state fixes the copy.
procedure ExecuteRelayedSale(const Command: TPlayerCommand);
var
  H: THuman;
  P: TPlayer;
  Location: TObject;
  Shop: TList;
  I, Count, GoodsAt, GoodsCount: Integer;
  Item: TItem;
begin
  H := ActorHuman(Command);
  P := Actor(Command);
  Location := RefObject(Command, 0);
  Shop := ShopStockOf(Location);
  if (Shop = nil) or (HumanShopLocation(H) <> Location) then
    raise Exception.Create('RelayedSale: the actor is not at the location here');
  Count := IntArg(Command, 1);
  for I := 0 to Count - 1 do
    if HumanSaleItem(H, P, IntArg(Command, 2 + I), False) = nil then
      raise Exception.Create(
          Format('RelayedSale: item %d is not the actor''s here', [IntArg(Command, 2 + I)])
      );
  for I := 0 to Count - 1 do
  begin
    Item := HumanSaleItem(H, P, IntArg(Command, 2 + I), True);
    if Item is TWeapon then
      TWeapon(Item).Target := nil;
    Shop.Add(Item);
  end;
  GoodsAt := 2 + Count;
  GoodsCount := IntArg(Command, GoodsAt);
  for I := 0 to GoodsCount - 1 do
    Inc(
        P.GetLocationGoodsEntry(IntArg(Command, GoodsAt + 1 + 2 * I)).Count,
        IntArg(Command, GoodsAt + 2 + 2 * I)
    );
  P.SetMoney(IntArg(Command, 0));
  // Every grid there that no longer shows the list is rebuilt, the actor's too, and the local
  // screen is told; it is told of the goods as well.
  ShopStockChanged(Location);
  if (GoodsCount > 0) and (LocalHuman <> nil) and (HumanShopLocation(LocalHuman) = Location) then
    NotifyShopStockChanged;
end;

var
  StorageMoved: Boolean;

// Moved from TfShip2.StorageToShipClicked.
procedure ExecuteTakeAllFromStorage(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  StorageMoved := H.PlayerHoldShip.RetrieveStoredItems(GetLocalStorageOwner(H), Actor(Command));
end;

function TakeAllFromStorage: Boolean;
begin
  SubmitCommand(NewCommand(ckTakeAllFromStorage));
  Result := StorageMoved;
end;

// Moved from TfShip2.ShipToStorageClicked.
procedure ExecutePutAllIntoStorage(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  StorageMoved := H.PlayerHoldShip.StoreLooseInventoryAt(GetLocalStorageOwner(H), Actor(Command));
end;

function PutAllIntoStorage: Boolean;
begin
  SubmitCommand(NewCommand(ckPutAllIntoStorage));
  Result := StorageMoved;
end;

// Moved from TfShip2.SortStorage.
procedure ExecuteSortStorage(const Command: TPlayerCommand);
var
  H: THuman;
  P: TPlayer;
  Sort: TPlayerHoldSort;
  I, J, Count: Integer;
  Entry: PStorageEntry;
  LeftIndex, RightIndex: Integer;
begin
  H := ActorHuman(Command);
  P := Actor(Command);
  Sort := TPlayerHoldSort(IntArg(Command, 0));
  Count := P.StorageEntries.Count;
  I := 0;
  J := 0;
  while I < Count do
  begin
    Entry := P.StorageEntries[I];
    if GetLocalStorageOwner(H) = Entry.LocationOwner then
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
  Count := P.GetStorageSlotExtent(GetLocalStorageOwner(H));
  for I := 0 to Count - 2 do
    for J := I + 1 to Count - 1 do
    begin
      LeftIndex := P.FindStorageIndexByLocationAndSlot(GetLocalStorageOwner(H), I);
      RightIndex := P.FindStorageIndexByLocationAndSlot(GetLocalStorageOwner(H), J);
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
var
  H: THuman;
begin
  H := ActorHuman(Command);
  SortPlayerHoldEntries(H, TPlayerHoldSort(IntArg(Command, 0)));
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
var
  H: THuman;
begin
  H := ActorHuman(Command);
  RemoveEmptyPlayerHoldSlots(H);
end;

procedure RemoveEmptyHoldSlots;
begin
  SubmitCommand(NewCommand(ckRemoveEmptyHoldSlots));
end;

// Moved from TfShip2.TrainSkillClicked.
procedure ExecuteTrainSkill(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  H.PlayerHoldShip.TrainSkill(TPilotSkill(IntArg(Command, 0)));
  if CanUsePlayerExperience(H) then
    Actor(Command).FreeExperience := H.PlayerHoldShip.FreeExperience;
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
  H: THuman;
  P: TPlayer;
begin
  H := ActorHuman(Command);
  P := Actor(Command);
  if P = H.PlayerHoldShip then
    P.AchievementStats.CheckAllSkillsAchievement;
  H.PlayerHoldShip.ScriptItemsAct(satOnPlayerSkillIncrease, nil, nil, 0);
end;

procedure FinishSkillTraining;
begin
  SubmitCommand(NewCommand(ckFinishSkillTraining));
end;

// Moved from TfShip2.ShipNameMouseDown.
procedure ExecuteRenameShip(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  H.PlayerHoldShip.Name := Command.Text;
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
  H: THuman;
  Choice, ExpectedCharges, I: Integer;
  Series: TDominatorSeries;
  Ship: TShip;
begin
  H := ActorHuman(Command);
  Choice := IntArg(Command, 0);
  if Choice = 1 then
  begin
    H.PlayerHoldShip.ChameleonActive := False;
    for I := 0 to H.PlayerHoldShip.CurrentStar.Ships.Count - 1 do
    begin
      Ship := TShip(H.PlayerHoldShip.CurrentStar.Ships[I]);
      if (Ship <> H.PlayerHoldShip)
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
    ExpectedCharges := Max(0, H.PlayerHoldShip.ChameleonCharges[Ord(Series)] - 1);
    H.PlayerHoldShip.ChameleonCharges[Ord(Series)] := ExpectedCharges;
    H.PlayerHoldShip.ChameleonSeries := Series;
    H.PlayerHoldShip.ChameleonActive := True;
  end;
  ReleaseSpaceObject(H.PlayerHoldShip.Graphic);
  H.PlayerHoldShip.RefreshGraphic;
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
// CHANGE: BUGFIX - The screen offers the ten configurations (TPlayer.EquipmentConfigurations);
// an index from a client was used unchecked, and range checks are off.
procedure RequireEquipmentConfigurationIndex(const Command: TPlayerCommand; Index: Integer);
begin
  // array[0..9]
  if (Index < 0) or (Index > 9) then
    raise ECommandRefused.CreateReason(
        rrOther,
        Format('%s: no equipment configuration %d', [CommandKindName(Command.Kind), Index])
    );
end;

procedure ExecuteSaveEquipmentConfiguration(const Command: TPlayerCommand);
begin
  RequireEquipmentConfigurationIndex(Command, IntArg(Command, 0));
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
  RequireEquipmentConfigurationIndex(Command, Index);
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
var
  H: THuman;
begin
  H := ActorHuman(Command);
  H.PlayerHoldShip.AfterburnerActive := IntArg(Command, 0) <> 0;
  H.PlayerHoldShip.RefreshDerivedStats(True);
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
procedure RunItemInfoScriptsNow(Human: THuman; Item: TItem);
begin
  if Item.ScriptItem <> nil then
    TScriptItem(Item.ScriptItem)
        .RunActionCode(satOnShowingItemInfo, Human.PlayerHoldShip, nil, nil, 0);
  if Item is TEquipmentWithActCode then
    RunItemConfigActionCode(Item, satOnShowingItemInfo, Human.PlayerHoldShip, nil, nil, 0);
end;

procedure ExecuteRunItemInfoScripts(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  RunItemInfoScriptsNow(H, ShownItemArg(Command, 0));
end;

procedure RunItemInfoScripts(Item: TItem);
var
  Command: TPlayerCommand;
begin
  // An item the screen shows from elsewhere cannot be named; its scripts run unrecorded,
  // and the command log then writes a checkpoint.
  if FindShownItem(LocalHuman, Item.Id) <> Item then
  begin
    RunItemInfoScriptsNow(LocalHuman, Item);
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
procedure CheckHeldUsabilityNow(
    Human: THuman;
    const SlotTypes: array of Byte;
    HighlightRepairable: Boolean
);
var
  I, Slot, SlotCount: Integer;
  Item: TEquipment;
  Highlight: Boolean;
begin
  for I := 0 to 7 do
  begin
    SlotCount := Human.PlayerHoldShip.GetSlotCountForItemType(SlotTypes[I]);
    SetLength(HeldSlotHighlights[I], SlotCount);
    for Slot := 0 to SlotCount - 1 do
    begin
      Item := Human.PlayerHoldShip.FindEquippedItemInSlot(SlotTypes[I], Slot);
      if HighlightRepairable
          and (Item <> nil)
          and ((Item.EquippedFlag <> 0) or (Item is THull))
          and Item.NeedsRepair then
        Highlight := True
      else if (Human.SelectedHoldKind = phkEquipment)
          and (Human.SelectedHoldItem.ItemType = t_MicroModule)
          and (Item <> nil)
          and (Item.MicroModuleIndex = 0)
          and (Human.SelectedHoldItem as TMicroModule).CanInstallOn(Item) then
        Highlight := True
      else if (Human.SelectedHoldKind in [phkEquipment, phkArtefact])
          and (Human.SelectedHoldItem is TEquipmentWithActCode)
          and (Item <> nil)
          and (RunItemConfigActionCode(
                  Human.SelectedHoldItem,
                  satOnCheckingUsability,
                  Human.PlayerHoldShip,
                  Item,
                  nil,
                  0)
              > 0) then
        Highlight := True
      else if (Human.SelectedHoldKind in [phkEquipment, phkArtefact])
          and (Human.SelectedHoldItem.ScriptItem <> nil)
          and (Item <> nil)
          and (TScriptItem(Human.SelectedHoldItem.ScriptItem)
                  .RunActionCode(satOnCheckingUsability, Human.PlayerHoldShip, Item, nil, 0)
              > 0) then
        Highlight := True
      else if (Human.SelectedHoldKind in [phkEquipment, phkArtefact])
          and (Item <> nil)
          and (Item is TEquipmentWithActCode)
          and (RunItemConfigActionCode(
                  Item,
                  satOnCheckingUsability2,
                  Human.PlayerHoldShip,
                  Human.SelectedHoldItem,
                  nil,
                  0)
              > 0) then
        Highlight := True
      else if (Human.SelectedHoldKind in [phkEquipment, phkArtefact])
          and (Item <> nil)
          and (Item.ScriptItem <> nil)
          and (TScriptItem(Item.ScriptItem)
                  .RunActionCode(satOnCheckingUsability2, Human.PlayerHoldShip, Human.SelectedHoldItem, nil, 0)
              > 0) then
        Highlight := True
      else if (Human.SelectedHoldKind = phkGoods)
          and (Item <> nil)
          and (Item.ScriptItem <> nil)
          and (TScriptItem(Item.ScriptItem)
                  .RunActionCode(
                      satOnCheckingUsabilityGoods,
                      Human.PlayerHoldShip,
                      TObject(Human.SelectedGoodsIndex),
                      TObject(Human.SelectedGoodsQuantity),
                      0)
              > 0) then
        Highlight := True
      else if (Human.SelectedHoldKind = phkEquipment)
          and (Human.SelectedHoldItem.ItemType = t_Cistern)
          and (Item <> nil)
          and (Item.ItemType = t_FuelTanks)
          and ((Human.SelectedHoldItem as TCistern).Fuel > 0)
          and ((Item as TFuelTanks).Fuel < (Item as TFuelTanks).Capacity) then
        Highlight := True
      else
        Highlight :=
            (Human.SelectedHoldKind = phkEquipment)
                and IsCompatibleSlot(Human.SelectedHoldItem.ItemType, TItemType(SlotTypes[I]));
      HeldSlotHighlights[I][Slot] := Highlight;
    end;
  end;
  if (HighlightRepairable and Human.PlayerHoldShip.GetHull.NeedsRepair) then
    HeldHullHighlight := True
  else if ((Human.SelectedHoldKind = phkEquipment)
      and (Human.SelectedHoldItem.ItemType = t_MicroModule)
      and (Human.PlayerHoldShip.GetHull.MicroModuleIndex = 0)
      and (Human.SelectedHoldItem as TMicroModule).CanInstallOn(Human.PlayerHoldShip.GetHull)) then
    HeldHullHighlight := True
  else if ((Human.SelectedHoldKind in [phkEquipment, phkArtefact])
      and (Human.SelectedHoldItem is TEquipmentWithActCode)
      and (RunItemConfigActionCode(
              Human.SelectedHoldItem,
              satOnCheckingUsability,
              Human.PlayerHoldShip,
              Human.PlayerHoldShip.GetHull,
              nil,
              0)
          > 0)) then
    HeldHullHighlight := True
  else if ((Human.SelectedHoldKind in [phkEquipment, phkArtefact])
      and (Human.SelectedHoldItem.ScriptItem <> nil)
      and (TScriptItem(Human.SelectedHoldItem.ScriptItem)
              .RunActionCode(satOnCheckingUsability, Human.PlayerHoldShip, Human.PlayerHoldShip.GetHull, nil, 0)
          > 0)) then
    HeldHullHighlight := True
  else if ((Human.SelectedHoldKind in [phkEquipment, phkArtefact])
      and (Human.PlayerHoldShip.GetHull.ScriptItem <> nil)
      and (TScriptItem(Human.PlayerHoldShip.GetHull.ScriptItem)
              .RunActionCode(satOnCheckingUsability2, Human.PlayerHoldShip, Human.SelectedHoldItem, nil, 0)
          > 0)) then
    HeldHullHighlight := True
  else if ((Human.SelectedHoldKind = phkGoods)
      and (Human.PlayerHoldShip.GetHull.ScriptItem <> nil)
      and (TScriptItem(Human.PlayerHoldShip.GetHull.ScriptItem)
              .RunActionCode(
                  satOnCheckingUsabilityGoods,
                  Human.PlayerHoldShip,
                  TObject(Human.SelectedGoodsIndex),
                  TObject(Human.SelectedGoodsQuantity),
                  0)
          > 0)) then
    HeldHullHighlight := True
  else
    HeldHullHighlight :=
        (Human.SelectedHoldKind = phkEquipment)
            and (Human.SelectedHoldItem.ItemType = t_Hull)
            and (Human.PlayerHoldShip is TNormalShip)
            and (TItem(Human.PlayerHoldShip.Inventory[0]).NoDropFlag = 0);
end;

// Ints: the flag to highlight repairable equipment, then the eight slot types.
procedure ExecuteCheckHeldUsability(const Command: TPlayerCommand);
var
  H: THuman;
  SlotTypes: array[0..7] of Byte;
  I: Integer;
begin
  H := ActorHuman(Command);
  for I := 0 to 7 do
    SlotTypes[I] := Byte(IntArg(Command, 1 + I));
  CheckHeldUsabilityNow(H, SlotTypes, IntArg(Command, 0) <> 0);
end;

procedure CheckHeldUsability(const SlotTypes: array of Byte; HighlightRepairable: Boolean);
var
  Command: TPlayerCommand;
  I: Integer;
begin
  // With nothing held no script runs, and nothing changes.
  if not (LocalHuman.SelectedHoldKind in [phkEquipment, phkArtefact, phkGoods]) then
  begin
    CheckHeldUsabilityNow(LocalHuman, SlotTypes, HighlightRepairable);
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
// CHANGE: BUGFIX - The awards screen lets a human change only its own ranger's medals
// (TfRewards: LocalPlayer = Ship); a client's command named any ship, and indices unchecked.
procedure RequireOwnAwards(const Command: TPlayerCommand; Ship: TShip);
begin
  if Ship <> Actor(Command) then
    raise ECommandRefused.CreateReason(
        rrOther,
        CommandKindName(Command.Kind) + ': the medals are not the human''s'
    );
end;

procedure ExecuteExchangeAwards(const Command: TPlayerCommand);
var
  Ship: TShip;
begin
  Ship := RefObject(Command, 0) as TShip;
  RequireOwnAwards(Command, Ship);
  if (IntArg(Command, 0) < 0)
      or (IntArg(Command, 0) >= Ship.AwardIds.Count)
      or (IntArg(Command, 1) < 0)
      or (IntArg(Command, 1) >= Ship.AwardIds.Count) then
    raise ECommandRefused.CreateReason(rrOther, 'ExchangeAwards: no such medal');
  Ship.AwardIds.Exchange(IntArg(Command, 0), IntArg(Command, 1));
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
  RequireOwnAwards(Command, Ship);
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
  // CHANGE: ENHANCEMENT - The trades (True) apply on a host as they arrive (docs/commands.md,
  // Trades).
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
  RegisterCommand(ckSellHeld, 'SellHeld', @ExecuteSellHeld, True);
  RegisterCommand(ckRepairHeld, 'RepairHeld', @ExecuteRepairHeld, True);
  RegisterCommand(ckRefuelHeld, 'RefuelHeld', @ExecuteRefuelHeld, True);
  RegisterCommand(ckReloadHeld, 'ReloadHeld', @ExecuteReloadHeld, True);
  RegisterCommand(ckRepairAll, 'RepairAll', @ExecuteRepairAll, True);
  RegisterCommand(ckBuyRockets, 'BuyRockets', @ExecuteBuyRockets, True);
  RegisterCommand(ckUseItem, 'UseItem', @ExecuteUseItem);
  RegisterCommand(ckShowTreasureMap, 'ShowTreasureMap', @ExecuteShowTreasureMap);
  RegisterCommand(ckSellHoldInventory, 'SellHoldInventory', @ExecuteSellHoldInventory, True);
  RegisterCommand(ckSellHoldArtefact, 'SellHoldArtefact', @ExecuteSellHoldArtefact, True);
  RegisterCommand(ckSellHoldGoods, 'SellHoldGoods', @ExecuteSellHoldGoods, True);
  RegisterCommand(ckSellStoredItem, 'SellStoredItem', @ExecuteSellStoredItem, True);
  RegisterRelayCommand(ckRelayedSale, 'RelayedSale', @ExecuteRelayedSale);
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
