{$EXCESSPRECISION OFF}
unit aArcadeActions;
{$R-}
{$Q-}
{$B-}

// CHANGE: ENHANCEMENT - What an arcade battle (ab_MainForm, ab_Hit) does to the game, as
// commands (docs/commands.md).
//
// Granularity: the battle's real-time simulation (the arcade ships, their shots, bonuses and
// random streams) is not in the galaxy and is not replayed frame by frame. What the battle
// leaves in the galaxy at a point the player acts, or at its end, is one command whose
// arguments are the battle's result: the hull the ship came out with, the labelled ships
// that survived, the Keller encounter, the ranger's death.
//
// Not converted, and so caught by the command log's checkpoints: the goods the battle
// scatters (TGoods.Create takes galaxy item ids while the battle builds its spaces), the kill
// counts, rank points and loot of each kill (TabShipAI.ApplyDamage, which draws on the arcade
// ships' own random streams), cargo picked up in the battle (TfAB.PickUpItem) and the item
// scripts run on the arcade's own objects (the player's arcade ship on entry, an item's info).
// Those name objects that exist only in the battle.
//
// CHANGE: ENHANCEMENT - A client's black hole battle (docs/network.md, Black hole battles):
// on a client those direct changes would be lost with the host's next state, so the battle's
// loot goes as one command before its exit (ArcadeLoot, BeginArcadeLoot and SubmitArcadeLoot).
interface
uses
  aCommands,
  aPlayer;
const
  // Command kinds 625-649 (see TCommandKind).
  ckArcadeSetWeaponSlotData = 625;
  ckArcadeSetHull = 626;
  ckArcadeBattleExit = 627;
  ckArcadeDefeat = 628;
  ckArcadeKellerTalk = 629;
  ckArcadeKellerDestroyed = 630;
  ckArcadeNoShotsVictory = 631;
  ckArcadeLoot = 632;
type
  // A labelled ship alive at the end of a scripted battle.
  TArcadeSurvivor = record
    ScriptLabel: WideString;
    Health: Integer;
    MaxHealth: Integer;
  end;
  TArcadeSurvivors = array of TArcadeSurvivor;

// The weapon in the player's weapon slot Slot fires in the group SlotData names.
procedure SetArcadeWeaponSlotData(Slot: Integer; SlotData: Integer);
// The player's hull takes the arcade ship's health.
procedure SetArcadeHull(HullPoints: Integer);
// The battle ends with the arcade ship's health. ScriptedBattle: a script queued the battle;
// Survivors are then reported to it before it resumes.
procedure ExitArcadeBattle(
    HullPoints: Integer;
    ScriptedBattle: Boolean;
    const Survivors: TArcadeSurvivors
);
// The ranger died in the battle; the game ends.
procedure ApplyArcadeDefeat;
// Keller's reward goes to the hold and his conversation opens.
procedure BeginArcadeKellerTalk;
// Keller's ship broke up.
procedure DestroyKellerInArcade;
// The battle was won without a shot.
procedure CheckNoShotsArcadeVictory;
// CHANGE: ENHANCEMENT - Whether the local human's battle holds the host's day: a client plays
// it, and its result is the day's (THuman.ArcadeBattleHeld).
function LocalArcadeBattleHeld: Boolean;
// Notes the local ranger's hold, cargo and kill counts before such a battle.
procedure BeginArcadeLoot; overload;
// CHANGE: ENHANCEMENT - Notes every ranger of a co-op battle (Players).
procedure BeginArcadeLoot(const Players: array of TPlayer); overload;
// At the battle's end: what it added since BeginArcadeLoot (new items, grown stacks, cargo,
// kill counts) is taken back and submitted as ArcadeLoot, which adds it again here and on the
// host. Nothing without BeginArcadeLoot.
procedure SubmitArcadeLoot;
// After the exit of such a battle: the local human ends the day it held, continuing its jump.
procedure EndHeldArcadeBattleDay;
implementation
uses
  SysUtils,
  Classes,
  aConst,
  aGalaxy,
  aGalaxyEvent,
  aGalaxyStruct,
  aHold,
  aHoldActions,
  aHuman,
  aItem,
  aKling,
  aPlayerActions,
  aScript,
  aSession,
  aShip,
  aTranclucator,
  GR_Main;

// Moved from TfAB.ToggleWeaponGroup.
procedure ExecuteArcadeSetWeaponSlotData(const Command: TPlayerCommand);
begin
  with Actor(Command).FindEquippedItemInSlot(Ord(t_Weapon1), IntArg(Command, 0)) as TWeapon do
    AssignedSlotData := IntArg(Command, 1);
end;

procedure SetArcadeWeaponSlotData(Slot: Integer; SlotData: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckArcadeSetWeaponSlotData);
  AddInt(Command, Slot);
  AddInt(Command, SlotData);
  SubmitCommand(Command);
end;

// Moved from TfAB.OpenShipEquipment.
procedure ExecuteArcadeSetHull(const Command: TPlayerCommand);
begin
  Actor(Command).GetHull.HullPoints := IntArg(Command, 0);
end;

procedure SetArcadeHull(HullPoints: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckArcadeSetHull);
  AddInt(Command, HullPoints);
  SubmitCommand(Command);
end;

// Moved from TfAB.BeginBattleExit and TfAB.ReportSurvivingShips. Ints: flags (bit 0 the player
// is alive, bit 1 a scripted battle), the hull, the survivor count, then each survivor's health
// and maximum health. Text: the survivors' labels, one per line.
procedure ExecuteArcadeBattleExit(const Command: TPlayerCommand);
var
  P: TPlayer;
  Flags, Count, I, Position: Integer;
  Labels, ScriptLabel: WideString;
  Event: TGalaxyEvent;
begin
  P := Actor(Command);
  ActorHuman(Command).ArcadeBattleHeld := False;
  ActorHuman(Command).ArcadePartnerId := 0;
  Flags := IntArg(Command, 0);
  if (Flags and 1) <> 0 then
  begin
    P.GetHull.HullPoints := IntArg(Command, 1);
    if not (P.Order in [soJump, soJumpHole]) then
      P.InHyperspace := False;
  end;
  if (Flags and 2) <> 0 then
  begin
    Count := IntArg(Command, 2);
    Labels := Command.Text;
    for I := 0 to Count - 1 do
    begin
      Position := Pos(WideString(#10), Labels);
      if Position = 0 then
      begin
        ScriptLabel := Labels;
        Labels := '';
      end
      else
      begin
        ScriptLabel := Copy(Labels, 1, Position - 1);
        Labels := Copy(Labels, Position + 1, Length(Labels) - Position);
      end;
      Event := AddGalaxyEvent('LabeledShipSurvivedInAB');
      Event.AddTextData(ScriptLabel);
      Event.AddData(IntArg(Command, 3 + I * 2));
      Event.AddData(IntArg(Command, 4 + I * 2));
    end;
    CompleteQueuedArcadeBattle(2, Integer(Command.Actor));
  end;
  ArcadeKellerDefeats := 0;
  if ArcadeKellerReward <> nil then
  begin
    ArcadeKellerReward.Free;
    ArcadeKellerReward := nil;
  end;
end;

procedure ExitArcadeBattle(
    HullPoints: Integer;
    ScriptedBattle: Boolean;
    const Survivors: TArcadeSurvivors
);
var
  Command: TPlayerCommand;
  Flags, I: Integer;
begin
  Command := NewCommand(ckArcadeBattleExit);
  Flags := 0;
  if LocalPlayer <> nil then
    Flags := Flags or 1;
  if ScriptedBattle then
    Flags := Flags or 2;
  AddInt(Command, Flags);
  AddInt(Command, HullPoints);
  AddInt(Command, Length(Survivors));
  for I := 0 to High(Survivors) do
  begin
    if I > 0 then
      Command.Text := Command.Text + #10;
    Command.Text := Command.Text + Survivors[I].ScriptLabel;
    AddInt(Command, Survivors[I].Health);
    AddInt(Command, Survivors[I].MaxHealth);
  end;
  SubmitCommand(Command);
end;

// Moved from TfAB.TimerTakt.
procedure ExecuteArcadeDefeat(const Command: TPlayerCommand);
begin
  Actor(Command).Free;
  Session.GameEndReason := 3;
  ArcadeKellerDefeats := 0;
  if ArcadeKellerReward <> nil then
  begin
    ArcadeKellerReward.Free;
    ArcadeKellerReward := nil;
  end;
end;

procedure ApplyArcadeDefeat;
begin
  SubmitCommand(NewCommand(ckArcadeDefeat));
end;

type
  TArcadeLootStack = record
    Item: TCountableItem;
    StackCount: Integer;
    Cost: Integer;
  end;

  // What BeginArcadeLoot noted of one ranger.
  TArcadeLootNote = class
    Player: TPlayer;
    Items: TList;
    Stacks: array of TArcadeLootStack;
    Goods: array[0..7] of TCargoGoodsEntry;
    BlackHoleKills, HyperspaceKills: Integer;
    constructor Create(P: TPlayer);
    destructor Destroy; override;
  end;

var
  // CHANGE: ENHANCEMENT - One note per ranger of the battle: in a co-op battle every
  // participant's (each machine's battle changes them all), else the local one's.
  ArcadeLootNotes: TList;

function LocalArcadeBattleHeld: Boolean;
begin
  Result := (LocalHuman <> nil) and LocalHuman.ArcadeBattleHeld;
end;

constructor TArcadeLootNote.Create(P: TPlayer);
var
  I: Integer;
begin
  inherited Create;
  Player := P;
  Items := TList.Create;
  for I := 0 to P.Inventory.Count - 1 do
  begin
    Items.Add(P.Inventory[I]);
    if TObject(P.Inventory[I]) is TCountableItem then
    begin
      SetLength(Stacks, Length(Stacks) + 1);
      with Stacks[High(Stacks)] do
      begin
        Item := TCountableItem(P.Inventory[I]);
        StackCount := Item.StackCount;
        Cost := Item.Cost;
      end;
    end;
  end;
  for I := 0 to P.Artefacts.Count - 1 do
    Items.Add(P.Artefacts[I]);
  for I := 0 to High(Goods) do
    Goods[I] := P.CargoGoods[I];
  BlackHoleKills := P.BlackHoleKillCount;
  HyperspaceKills := P.HyperspaceKillCount;
end;

destructor TArcadeLootNote.Destroy;
begin
  Items.Free;
  inherited Destroy;
end;

procedure ClearArcadeLootNotes;
var
  I: Integer;
begin
  if ArcadeLootNotes = nil then
    Exit;
  for I := 0 to ArcadeLootNotes.Count - 1 do
    TArcadeLootNote(ArcadeLootNotes[I]).Free;
  ArcadeLootNotes.Clear;
end;

procedure BeginArcadeLoot(const Players: array of TPlayer);
var
  I: Integer;
begin
  if ArcadeLootNotes = nil then
    ArcadeLootNotes := TList.Create;
  ClearArcadeLootNotes;
  for I := 0 to High(Players) do
    if Players[I] <> nil then
      ArcadeLootNotes.Add(TArcadeLootNote.Create(Players[I]));
end;

procedure BeginArcadeLoot;
begin
  if LocalPlayer <> nil then
    BeginArcadeLoot([LocalPlayer]);
end;

// An item's bytes (aHoldActions.StoredItemBytes), as its length and then four to an integer,
// low byte first.
procedure AddItemBytes(var Command: TPlayerCommand; Item: TItem);
var
  Bytes: TStoredBytes;
  J, Quad: Integer;
begin
  Bytes := StoredItemBytes(Item);
  AddInt(Command, Length(Bytes));
  J := 0;
  while J < Length(Bytes) do
  begin
    Quad := Bytes[J];
    if J + 1 < Length(Bytes) then
      Quad := Quad or (Integer(Bytes[J + 1]) shl 8);
    if J + 2 < Length(Bytes) then
      Quad := Quad or (Integer(Bytes[J + 2]) shl 16);
    if J + 3 < Length(Bytes) then
      Quad := Quad or Integer(Cardinal(Bytes[J + 3]) shl 24);
    AddInt(Command, Quad);
    Inc(J, 4);
  end;
end;

// The item AddItemBytes wrote at Position, with a new id; Position moves past it.
function ReadItemBytes(const Command: TPlayerCommand; var Position: Integer): TItem;
var
  Bytes: TStoredBytes;
  ByteCount, J, Quad: Integer;
  NewId: Cardinal;
begin
  ByteCount := IntArg(Command, Position);
  Inc(Position);
  SetLength(Bytes, ByteCount);
  J := 0;
  while J < ByteCount do
  begin
    Quad := IntArg(Command, Position);
    Inc(Position);
    Bytes[J] := Byte(Quad);
    if J + 1 < ByteCount then
      Bytes[J + 1] := Byte(Quad shr 8);
    if J + 2 < ByteCount then
      Bytes[J + 2] := Byte(Quad shr 16);
    if J + 3 < ByteCount then
      Bytes[J + 3] := Byte(Cardinal(Quad) shr 24);
    Inc(J, 4);
  end;
  // As TEquipment.Clone: the battle's machine gave the item an id of its own copy.
  NewId := Galaxy.NextItemId;
  Session.LoadedSaveVersion := CurrentSaveVersion;
  Result := LoadStoredItem(Bytes);
  Result.Id := NewId;
  Galaxy.NextItemId := NewId + 1;
end;

// Ints: the black hole and hyperspace kills, the count and total cost of each of the 8 cargo
// goods, all added; the count of grown stacks, then for each its index in the inventory, the
// units and the cost added; the count of new items, then for each 1 for an artefact (0 for
// the inventory) and its bytes (AddItemBytes).
procedure ExecuteArcadeLoot(const Command: TPlayerCommand);
var
  P: TPlayer;
  I, Count, Index, Position, Flags: Integer;
  Stack: TCountableItem;
  Item: TItem;
begin
  P := Actor(Command);
  ClearPlayerHoldEntries(ActorHuman(Command));
  Inc(P.BlackHoleKillCount, IntArg(Command, 0));
  Inc(P.HyperspaceKillCount, IntArg(Command, 1));
  Position := 2;
  for I := 0 to High(P.CargoGoods) do
  begin
    Inc(P.CargoGoods[I].Count, IntArg(Command, Position));
    Inc(P.CargoGoods[I].TotalCost, IntArg(Command, Position + 1));
    Inc(Position, 2);
  end;
  Count := IntArg(Command, Position);
  Inc(Position);
  for I := 0 to Count - 1 do
  begin
    Index := IntArg(Command, Position);
    if (Index >= 0)
        and (Index < P.Inventory.Count)
        and (TObject(P.Inventory[Index]) is TCountableItem) then
    begin
      Stack := TCountableItem(P.Inventory[Index]);
      Inc(Stack.StackCount, IntArg(Command, Position + 1));
      Stack.Weight := Stack.GetUnitSize * Stack.StackCount;
      Inc(Stack.Cost, IntArg(Command, Position + 2));
    end;
    Inc(Position, 3);
  end;
  Count := IntArg(Command, Position);
  Inc(Position);
  for I := 0 to Count - 1 do
  begin
    Flags := IntArg(Command, Position);
    Inc(Position);
    Item := ReadItemBytes(Command, Position);
    if (Flags and 1) <> 0 then
      P.Artefacts.Add(Item)
    else
      P.Inventory.Add(Item);
    if Item is TArtefactTranclucator then
      (TObject((Item as TArtefactTranclucator).Ship) as TTranclucator).OwnerShip := P;
  end;
  P.RefreshDerivedStats(True);
end;

// What the battle added to Note's ranger, as an ArcadeLoot command, taken back from the ranger.
function TakeBackArcadeLoot(Note: TArcadeLootNote): TPlayerCommand;
var
  P: TPlayer;
  Command: TPlayerCommand;
  I, Count, CountAt: Integer;
  Item: TItem;
  NewItems: TList;
  Artefact: array of Boolean;
begin
  P := Note.Player;
  ClearPlayerHoldEntries(HumanOf(P));
  Command := NewCommand(ckArcadeLoot);
  AddInt(Command, P.BlackHoleKillCount - Note.BlackHoleKills);
  AddInt(Command, P.HyperspaceKillCount - Note.HyperspaceKills);
  P.BlackHoleKillCount := Note.BlackHoleKills;
  P.HyperspaceKillCount := Note.HyperspaceKills;
  for I := 0 to High(Note.Goods) do
  begin
    AddInt(Command, P.CargoGoods[I].Count - Note.Goods[I].Count);
    AddInt(Command, P.CargoGoods[I].TotalCost - Note.Goods[I].TotalCost);
    P.CargoGoods[I] := Note.Goods[I];
  end;
  NewItems := TList.Create;
  try
    // The stacks that grew, by their index in the inventory without the new items, which
    // come after the noted ones in Note.Items.
    CountAt := Length(Command.Ints);
    AddInt(Command, 0);
    Count := 0;
    for I := 0 to High(Note.Stacks) do
      with Note.Stacks[I] do
        if (P.Inventory.IndexOf(Item) >= 0)
            and ((Item.StackCount <> StackCount) or (Item.Cost <> Cost)) then
        begin
          AddInt(Command, Note.Items.IndexOf(Item));
          AddInt(Command, Item.StackCount - StackCount);
          AddInt(Command, Item.Cost - Cost);
          Item.StackCount := StackCount;
          Item.Weight := Item.GetUnitSize * StackCount;
          Item.Cost := Cost;
          Inc(Count);
        end;
    Command.Ints[CountAt] := Count;
    Artefact := nil;
    for I := 0 to P.Inventory.Count - 1 do
      if Note.Items.IndexOf(P.Inventory[I]) < 0 then
      begin
        NewItems.Add(P.Inventory[I]);
        SetLength(Artefact, Length(Artefact) + 1);
        Artefact[High(Artefact)] := False;
      end;
    for I := 0 to P.Artefacts.Count - 1 do
      if Note.Items.IndexOf(P.Artefacts[I]) < 0 then
      begin
        NewItems.Add(P.Artefacts[I]);
        SetLength(Artefact, Length(Artefact) + 1);
        Artefact[High(Artefact)] := True;
      end;
    AddInt(Command, NewItems.Count);
    for I := 0 to NewItems.Count - 1 do
    begin
      Item := TItem(NewItems[I]);
      AddInt(Command, Ord(Artefact[I]));
      AddItemBytes(Command, Item);
      P.Inventory.Remove(Item);
      P.Artefacts.Remove(Item);
      Item.Free;
    end;
  finally
    NewItems.Free;
  end;
  P.RefreshDerivedStats(True);
  Result := Command;
end;

procedure SubmitArcadeLoot;
var
  I: Integer;
  Note: TArcadeLootNote;
  Command: TPlayerCommand;
  Local: Boolean;
begin
  if (ArcadeLootNotes = nil) or (ArcadeLootNotes.Count = 0) then
    Exit;
  // CHANGE: ENHANCEMENT - Every noted ranger's changes are taken back; only the local one's
  // go, as its own command: each participant's machine sends its own (docs/network.md,
  // Co-op black hole battles).
  for I := 0 to ArcadeLootNotes.Count - 1 do
  begin
    Note := ArcadeLootNotes[I];
    Command := TakeBackArcadeLoot(Note);
    Local := Note.Player = LocalPlayer;
    if Local then
      SubmitCommand(Command);
  end;
  ClearArcadeLootNotes;
end;

procedure EndHeldArcadeBattleDay;
var
  Command: TPlayerCommand;
begin
  // Not EndTurn: the exit's prediction has cleared the flag here, so the human no longer holds
  // the day on this copy, but it does on the host's until the exit is applied there.
  Command := NewCommand(ckEndTurn);
  AddInt(Command, 1);
  SubmitCommand(Command);
end;

// Moved from TfAB.TimerTakt.
procedure ExecuteArcadeKellerTalk(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  if ArcadeKellerReward <> nil then
  begin
    ClearPlayerHoldEntries(ActorHuman(Command));
    if ArcadeKellerReward is TArtefact then
      P.Artefacts.Insert(0, ArcadeKellerReward)
    else
      P.Inventory.Add(ArcadeKellerReward);
    ArcadeKellerReward := nil;
  end;
  Session.ScriptDialogIndex := -1;
  TScriptShip(KellerShip.ScriptShip)
      .Script
      .PublishShipContext(KellerShip.ScriptShip as TScriptShip);
  CurrentScript.CallDialogByVariable(TScriptShip(KellerShip.ScriptShip).State.AuxiliaryText);
  if Session.ScriptDialogIndex < 0 then
    RaiseWideMessage('Not found dialog');
  ActorHuman(Command).TalkShip := KellerShip;
  ActorHuman(Command).TalkPlanet := nil;
  ActorHuman(Command).TalkScripted := True;
end;

procedure BeginArcadeKellerTalk;
begin
  SubmitCommand(NewCommand(ckArcadeKellerTalk));
end;

// Moved from TabHit.Advance.
procedure ExecuteArcadeKellerDestroyed(const Command: TPlayerCommand);
begin
  Inc(Actor(Command).DominatorKillsByType[0]);
  KellerShip.ScriptItemsAct(61, nil, nil, 0);
  KellerShip.Free;
end;

procedure DestroyKellerInArcade;
begin
  SubmitCommand(NewCommand(ckArcadeKellerDestroyed));
end;

// Moved from TfAB.ShowVictory.
procedure ExecuteArcadeNoShotsVictory(const Command: TPlayerCommand);
begin
  Actor(Command).AchievementStats.CheckNoShotsArcadeVictoryAchievement;
end;

procedure CheckNoShotsArcadeVictory;
begin
  SubmitCommand(NewCommand(ckArcadeNoShotsVictory));
end;

initialization
  RegisterCommand(ckArcadeSetWeaponSlotData, 'ArcadeSetWeaponSlotData', @ExecuteArcadeSetWeaponSlotData);
  RegisterCommand(ckArcadeSetHull, 'ArcadeSetHull', @ExecuteArcadeSetHull);
  RegisterCommand(ckArcadeBattleExit, 'ArcadeBattleExit', @ExecuteArcadeBattleExit);
  RegisterCommand(ckArcadeDefeat, 'ArcadeDefeat', @ExecuteArcadeDefeat);
  RegisterCommand(ckArcadeKellerTalk, 'ArcadeKellerTalk', @ExecuteArcadeKellerTalk);
  RegisterCommand(ckArcadeKellerDestroyed, 'ArcadeKellerDestroyed', @ExecuteArcadeKellerDestroyed);
  RegisterCommand(ckArcadeNoShotsVictory, 'ArcadeNoShotsVictory', @ExecuteArcadeNoShotsVictory);
  RegisterCommand(ckArcadeLoot, 'ArcadeLoot', @ExecuteArcadeLoot);
finalization
  ClearArcadeLootNotes;
  ArcadeLootNotes.Free;
end.
