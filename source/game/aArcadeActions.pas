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
interface
uses
  aCommands;
const
  // Command kinds 625-649 (see TCommandKind).
  ckArcadeSetWeaponSlotData = 625;
  ckArcadeSetHull = 626;
  ckArcadeBattleExit = 627;
  ckArcadeDefeat = 628;
  ckArcadeKellerTalk = 629;
  ckArcadeKellerDestroyed = 630;
  ckArcadeNoShotsVictory = 631;
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
implementation
uses
  SysUtils,
  aConst,
  aGalaxy,
  aGalaxyEvent,
  aGalaxyStruct,
  aHold,
  aHuman,
  aItem,
  aKling,
  aPlayer,
  aScript,
  aSession,
  aShip,
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
    CompleteQueuedArcadeBattle(2);
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

// Moved from TfAB.TimerTakt.
procedure ExecuteArcadeKellerTalk(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  if ArcadeKellerReward <> nil then
  begin
    ClearPlayerHoldEntries;
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
end.
