{$EXCESSPRECISION OFF}
unit aTalkActions;

// CHANGE: ENHANCEMENT - What a human does in a conversation with a ship or a planet (fTalk),
// as commands (docs/commands.md). The code is moved from the screen; it keeps its text,
// choices, sounds, achievements and images. The screen still decides which command to send
// from what it shows; a command that decides for itself returns its branch in TalkOutcome
// and the dialog text it builds in TalkText.
//
// A conversation the UI starts (a click on a ship) begins with BeginTalk. One the turn thread
// asks for (TShip.OpenPlayerConversation, TPlanet.RequestDialog) is set up by the turn thread,
// and the commands the UI then submits are recorded in that wait. Either way the conversation
// ends with EndTalk when the screen closes for good. The ship talked to is the human's
// TalkShip (THuman). Script dialog code adds its answers to the open screen, as before;
// injected answers (ScriptDialogInjections) are named by their index in that list.
interface
uses
  aCommands,
  aGalaxyStruct,
  aHuman,
  aItem,
  aPlayer,
  aScript,
  aShip;
const
  // Command kinds 320-399 (see TCommandKind).
  ckBeginTalk = 320;
  ckResetScriptDialog = 321;
  ckEnterTalk = 322;
  ckLeaveTalk = 323;
  ckEndTalk = 324;
  ckAcceptScriptedTalk = 325;
  ckClearTalkDialogRules = 326;
  ckTalkScriptMessage = 327;
  ckTalkShipDialog = 328;
  ckTalkDialogOverride = 329;
  ckSortTalkDialogInjections = 330;
  ckCheckTalkCamouflage = 331;
  ckPublishTalkShipContext = 332;
  ckTalkShipAuxiliaryCode = 333;
  ckTalkRecognizesPlayer = 334;
  ckRunInjectedAnswerAction = 335;
  ckCallInjectedDialog = 336;
  ckShowMoneyDemand = 340;
  ckDemandMoney = 341;
  ckDemandCargo = 342;
  ckShowTruceOffer = 343;
  ckAcceptTruceOffer = 344;
  ckShowAttackTargets = 345;
  ckRequestAttackTarget = 346;
  ckAcceptJointAttack = 347;
  ckRequestProtection = 348;
  ckRequestPreserveItems = 349;
  ckAcceptPartnerOffer = 350;
  ckAcceptPiratePartnerOffer = 351;
  ckOrderTalkShipFollow = 352;
  ckOrderTalkShipLand = 353;
  ckOrderTalkShipJump = 354;
  ckOrderPartnerDropCargo = 355;
  ckGivePartnerGift = 356;
  ckGivePiratePartnerGift = 357;
  ckApplyOrderToAllPartners = 358;
  ckOrderPiratePartnerAttack = 359;
  ckDismissPartner = 360;
  ckOffendOverOldHull = 361;
  ckOrderTranclucatorFollow = 365;
  ckOrderTranclucatorReturn = 366;
  ckOrderTranclucatorSeekItems = 367;
  ckCancelTranclucatorSeekItems = 368;
  ckSetTranclucatorOptions = 369;
  ckOrderTranclucatorDropCargo = 370;
  ckOrderTranclucatorLand = 371;
  ckOrderTranclucatorStoreCargo = 372;
  ckApplyOrderToAllTranclucators = 373;
  ckRunDominatorProgram = 375;
  ckMilitaryHullRepair = 380;
  ckMilitaryEquipmentRepair = 381;
  ckSellAllMilitaryRemains = 382;
  ckSellMilitaryRemains = 383;
  ckMilitaryBuff = 384;
const
  // ShowMoneyDemand outcomes.
  moRefused = 0;
  moAsk = 1;
  // ShowTruceOffer outcomes.
  toHavePact = 0;
  toRefused = 1;
  toAcceptedFree = 2;
  toAsk = 3;
  // ShowAttackTargets outcome bits.
  aoAllowTargets = 1;
  aoReadyAttack = 2;
  // RequestAttackTarget outcomes.
  raInFear = 0;
  raRefused = 1;
  raAccepted = 2;
  // RequestProtection outcomes.
  rpNotFearAndWar = 0;
  rpRefusedTarget = 1;
  rpAccepted = 2;
  rpRefused = 3;
var
  // What the last command decided and the dialog text it built.
  TalkOutcome: Integer;
  TalkText: WideString;
  // ShowAttackTargets: the ship the talk ship is ready to attack. TalkDialogOverride: the
  // script of the selected override.
  TalkTarget: TShip;
  TalkScript: TScript;

// Starts a conversation with Ship from the UI. ClearScript also forgets the current script.
procedure BeginTalk(Ship: TShip; ClearScript: Boolean);
procedure ResetScriptDialog;
// The item scripts that run before the conversation screen opens and after it closes.
procedure EnterTalk(OtherShip: TShip);
procedure LeaveTalk(OtherShip: TShip);
// Ends the conversation: the intercom, the talk scripts and the star's ship scripts.
procedure EndTalk(SkipShipScriptAdvance: Boolean);
// The player agrees to what the turn thread's conversation asked for.
procedure AcceptScriptedTalk;

// Script dialogs.
procedure ClearTalkDialogRules;
// Runs Script's current dialog message; Publish first names the talk ship as its ship.
procedure TalkScriptMessage(Script: TScript; Publish: Boolean);
// Opens the talk ship's script dialog again; returns whether it has a message to show.
function RunTalkShipDialog: Boolean;
// Applies the script dialog override with the highest priority; returns its script.
function ApplyTalkDialogOverride: TScript;
procedure SortTalkDialogInjections;
// Whether a dominator boss takes the player for one of its own.
function CheckTalkCamouflage: Boolean;
procedure PublishTalkShipContext;
procedure RunTalkShipAuxiliaryCode;
// Whether the talk ship sees through the player's chameleon (item scripts may say).
function TalkRecognizesPlayer: Boolean;
procedure RunInjectedAnswerAction(Injection: PScriptDialogInjection);
procedure CallInjectedDialog(Injection: PScriptDialogInjection);

// Extortion and truce. Text is the dialog text the game's answer starts from.
procedure ShowMoneyDemand;
function DemandMoney(Amount: Integer; const Text: WideString): Boolean;
function DemandCargo(const Text: WideString): Boolean;
procedure ShowTruceOffer;
function AcceptTruceOffer(Amount: Integer; const Text: WideString): Boolean;

// Attacks and protection.
procedure ShowAttackTargets;
procedure RequestAttackTarget(Target: TShip; const Text: WideString);
procedure AcceptJointAttack(Target: TShip);
procedure RequestProtection;
procedure RequestPreserveItems;

// Partners.
function AcceptPartnerOffer(Amount: Integer; const Text: WideString): Boolean;
function AcceptPiratePartnerOffer(Amount: Integer; const Text: WideString): Boolean;
procedure OrderTalkShipFollow;
procedure OrderTalkShipLand;
procedure OrderTalkShipJump;
// Returns whether the partner drops its cargo.
function OrderPartnerDropCargo: Boolean;
procedure GivePartnerGift(Amount: Integer);
procedure GivePiratePartnerGift(Amount: Integer);
procedure ApplyOrderToAllPartners;
procedure OrderPiratePartnerAttack(Target: TShip);
// Action: 1 keeps the partner, 2 parts on good terms, 3 on bad terms.
procedure DismissPartner(Action: Integer);
procedure OffendOverOldHull;

// The player's tranclucators.
procedure OrderTranclucatorFollow;
procedure OrderTranclucatorReturn;
procedure OrderTranclucatorSeekItems;
procedure CancelTranclucatorSeekItems;
// Action packs the option to change as decimal digits (TfTalk.ShowTranclucatorOptions).
procedure SetTranclucatorOptions(Action: Integer);
procedure OrderTranclucatorDropCargo;
procedure OrderTranclucatorLand;
procedure OrderTranclucatorStoreCargo;
procedure ApplyOrderToAllTranclucators;

// Returns whether the program works on the talk ship.
function RunDominatorProgram(ProgramIndex: Integer): Boolean;

// Military support from a coalition flagship.
// What Player pays in nodes for a full hull repair.
function GetMilitaryHullRepairCost(Player: TPlayer): Integer;
// What Human pays in nodes to repair the equipment its talk ship can repair.
function GetMilitaryEquipmentRepairCost(Human: THuman): Integer;
// Whether Item is a letter one of Player's quests delivers.
function IsMilitaryProtectedQuestItem(Player: TPlayer; Item: TItem): Boolean;
procedure DonateMilitaryResearchMaterial(Series: TDominatorSeries; Amount: Integer);
// Returns the hull points repaired.
function MilitaryHullRepair(Nodes: Integer): Integer;
procedure MilitaryEquipmentRepair(Nodes: Integer);
procedure SellAllMilitaryRemains;
// Returns whether the item was sold.
function SellMilitaryRemains(Item: TItem): Boolean;
// Returns whether a buff was already active.
function MilitaryBuff(Nodes: Integer): Boolean;
implementation
uses
  SysUtils,
  Classes,
  Math,
  aMyFunction,
  aConst,
  aGalaxy,
  aGalaxyEvent,
  aSession,
  aKling,
  aNormalShip,
  aPirate,
  aRanger,
  aRuins,
  aTranclucator,
  GR_Main;

procedure AddScript(var Command: TPlayerCommand; Script: TScript);
begin
  if Script = nil then
    AddInt(Command, -1)
  else
    AddInt(Command, Galaxy.Scripts.IndexOf(Script));
end;

function ScriptArg(const Command: TPlayerCommand; Index: Integer): TScript;
var
  ScriptIndex: Integer;
begin
  ScriptIndex := IntArg(Command, Index);
  if (ScriptIndex < 0) or (ScriptIndex >= Galaxy.Scripts.Count) then
    raise Exception.Create(CommandKindName(Command.Kind) + ' names no script');
  Result := TScript(Galaxy.Scripts[ScriptIndex]);
end;

procedure AddInjection(var Command: TPlayerCommand; Injection: PScriptDialogInjection);
begin
  AddInt(Command, ScriptDialogInjections.IndexOf(Injection));
end;

function InjectionArg(const Command: TPlayerCommand; Index: Integer): PScriptDialogInjection;
var
  InjectionIndex: Integer;
begin
  InjectionIndex := IntArg(Command, Index);
  if (ScriptDialogInjections = nil)
      or (InjectionIndex < 0)
      or (InjectionIndex >= ScriptDialogInjections.Count) then
    raise Exception.Create(CommandKindName(Command.Kind) + ' names a missing dialog injection');
  Result := PScriptDialogInjection(ScriptDialogInjections[InjectionIndex]);
end;

function ShipArg(const Command: TPlayerCommand; Index: Integer): TShip;
begin
  Result := TShip(RefObject(Command, Index));
end;

procedure SubmitSimple(Kind: TCommandKind);
begin
  SubmitCommand(NewCommand(Kind));
end;

procedure SubmitInt(Kind: TCommandKind; Value: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(Kind);
  AddInt(Command, Value);
  SubmitCommand(Command);
end;

procedure SubmitShip(Kind: TCommandKind; Ship: TShip);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(Kind);
  AddRef(Command, Ship);
  SubmitCommand(Command);
end;

// A command with an amount and the dialog text a game answer starts from; returns whether
// the game said yes.
function SubmitAmountText(Kind: TCommandKind; Amount: Integer; const Text: WideString): Boolean;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(Kind);
  AddInt(Command, Amount);
  Command.Text := Text;
  SubmitCommand(Command);
  Result := TalkOutcome <> 0;
end;

{ Starting and ending }

// Moved from the places in TfStarMap that start a conversation.
procedure ExecuteBeginTalk(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  if IntArg(Command, 0) <> 0 then
    CurrentScript := nil;
  Session.ScriptDialogIndex := -1;
  H.TalkShip := ShipArg(Command, 0);
  H.TalkScripted := False;
end;

procedure BeginTalk(Ship: TShip; ClearScript: Boolean);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckBeginTalk);
  AddRef(Command, Ship);
  AddInt(Command, Ord(ClearScript));
  SubmitCommand(Command);
end;

procedure ExecuteResetScriptDialog(const Command: TPlayerCommand);
begin
  Session.ScriptDialogIndex := -1;
end;

procedure ResetScriptDialog;
begin
  SubmitSimple(ckResetScriptDialog);
end;

// Moved from fTalk.RunTalk.
procedure ExecuteEnterTalk(const Command: TPlayerCommand);
var
  OtherShip: TShip;
begin
  OtherShip := ShipArg(Command, 0);
  if Actor(Command) <> nil then
    Actor(Command).ScriptItemsAct($18, OtherShip, nil, 0);
  if OtherShip <> nil then
    OtherShip.ScriptItemsAct($18, nil, nil, 0);
end;

procedure EnterTalk(OtherShip: TShip);
begin
  SubmitShip(ckEnterTalk, OtherShip);
end;

procedure ExecuteLeaveTalk(const Command: TPlayerCommand);
var
  OtherShip: TShip;
begin
  OtherShip := ShipArg(Command, 0);
  if Actor(Command) <> nil then
    Actor(Command).ScriptItemsAct($19, OtherShip, nil, 0);
  if OtherShip <> nil then
    OtherShip.ScriptItemsAct($19, nil, nil, 0);
end;

procedure LeaveTalk(OtherShip: TShip);
begin
  SubmitShip(ckLeaveTalk, OtherShip);
end;

// Moved from TfTalk.OnClose.
procedure ExecuteEndTalk(const Command: TPlayerCommand);
var
  H: THuman;
  I, Count: Integer;
  Ship: TShip;
  Star: TStar;
  Player: TPlayer;
  SkipShipScriptAdvance: Boolean;
begin
  H := ActorHuman(Command);
  Player := Actor(Command);
  SkipShipScriptAdvance := IntArg(Command, 0) <> 0;
  Count := Player.ProgramCounts[prgIntercom];
  if (H.TalkShip <> nil)
      and (H.TalkShip.TypeId = stKling)
      and (Count > 0)
      and Player.CanResolveObjectWithScanner(H.TalkShip) then
  begin
    Dec(Count);
    Player.ProgramCounts[prgIntercom] := Count;
  end;
  if (Player <> nil) and (H.TalkShip <> nil) and not H.TalkScripted then
    Player.ScriptItemsAct(satOnPlayerTalkedWithShip, H.TalkShip, nil, 0);
  H.TalkShip := nil;
  H.TalkPlanet := nil;
  if not H.TalkScripted and not SkipShipScriptAdvance then
  begin
    I := 0;
    Star := Player.CurrentStar;
    while I < Star.Ships.Count do
    begin
      Ship := Star.Ships[I];
      if Ship = KellerShip then
        Inc(I)
      else if Ship = BlazerShip then
        Inc(I)
      else
      begin
        if Ship.ScriptShip <> nil then
          Ship.ScriptNextDay;
        Inc(I);
      end;
    end;
  end;
end;

procedure EndTalk(SkipShipScriptAdvance: Boolean);
begin
  SubmitInt(ckEndTalk, Ord(SkipShipScriptAdvance));
end;

// Moved from TfTalk.AcceptScriptedConversation.
procedure ExecuteAcceptScriptedTalk(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  H.TalkResponse := 1;
  Session.ScriptDialogIndex := -1;
end;

procedure AcceptScriptedTalk;
begin
  SubmitSimple(ckAcceptScriptedTalk);
end;

{ Script dialogs }

procedure ExecuteClearTalkDialogRules(const Command: TPlayerCommand);
begin
  ClearScriptDialogRules;
end;

procedure ClearTalkDialogRules;
begin
  SubmitSimple(ckClearTalkDialogRules);
end;

// Moved from TfTalk.BuildStandardChoices, CodeMsgOut, RunInjectedAnswer and
// StartScriptMessage.
procedure ExecuteTalkScriptMessage(const Command: TPlayerCommand);
var
  H: THuman;
  Script: TScript;
begin
  H := ActorHuman(Command);
  Script := ScriptArg(Command, 0);
  CurrentScript := Script;
  if IntArg(Command, 1) <> 0 then
    Script.PublishCurrentShip(H.TalkShip);
  Script.CallDialogMessage(Session.ScriptDialogIndex);
end;

procedure TalkScriptMessage(Script: TScript; Publish: Boolean);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckTalkScriptMessage);
  AddScript(Command, Script);
  AddInt(Command, Ord(Publish));
  SubmitCommand(Command);
end;

// Moved from TfTalk.BuildStandardChoices.
procedure ExecuteTalkShipDialog(const Command: TPlayerCommand);
var
  H: THuman;
  Binding: TScriptShip;
begin
  H := ActorHuman(Command);
  TalkOutcome := 0;
  Binding := TScriptShip(H.TalkShip.ScriptShip);
  Binding.Script.PublishShipContext(Binding);
  Binding.Script.CallDialog(Binding.Script.CurrentDialog);
  if Session.ScriptDialogIndex >= 0 then
  begin
    Binding.Script.CallDialogMessage(Session.ScriptDialogIndex);
    TalkOutcome := 1;
  end;
end;

function RunTalkShipDialog: Boolean;
begin
  SubmitSimple(ckTalkShipDialog);
  Result := TalkOutcome <> 0;
end;

// Moved from TfTalk.BuildStandardChoices.
procedure ExecuteTalkDialogOverride(const Command: TPlayerCommand);
var
  H: THuman;
  Script: TScript;
  Text: WideString;
  I, Selected, Priority: Integer;
begin
  H := ActorHuman(Command);
  Selected := 0;
  Priority := PScriptDialogOverride(ScriptDialogOverrides[0]).Priority;
  for I := 0 to ScriptDialogOverrides.Count - 1 do
    if PScriptDialogOverride(ScriptDialogOverrides[I]).Priority > Priority then
    begin
      Selected := I;
      Priority := PScriptDialogOverride(ScriptDialogOverrides[I]).Priority;
    end;
  Script := PScriptDialogOverride(ScriptDialogOverrides[Selected]).Script;
  Script
      .InitCode
      .LocalVar
      .GetVar('GAnswerData')
      .SetDword(PScriptDialogOverride(ScriptDialogOverrides[Selected]).AnswerData);
  Text := PScriptDialogOverride(ScriptDialogOverrides[Selected]).DialogName;
  if Text <> '' then
  begin
    Script.PublishCurrentShip(H.TalkShip);
    Script.CallDialogByVariable(Text);
    if Session.ScriptDialogIndex < 0 then
      AppendLogLineThreadSafe(
          AnsiString(
              Script.ScriptFileName
                  + ' has overriden dialog with '
                  + Text
                  + ' but it failed to start'
          )
      );
  end;
  TalkScript := Script;
end;

function ApplyTalkDialogOverride: TScript;
begin
  SubmitSimple(ckTalkDialogOverride);
  Result := TalkScript;
end;

// Moved from TfTalk.BuildStandardChoices: injected answers by priority, highest first.
procedure ExecuteSortTalkDialogInjections(const Command: TPlayerCommand);
var
  I, J: Integer;
  Swapped: Pointer;
begin
  for I := 1 to ScriptDialogInjections.Count - 1 do
    for J := ScriptDialogInjections.Count - 1 downto I do
      if PScriptDialogInjection(ScriptDialogInjections[J]).Priority
          > PScriptDialogInjection(ScriptDialogInjections[J - 1]).Priority then
      begin
        Swapped := ScriptDialogInjections[J];
        ScriptDialogInjections[J] := ScriptDialogInjections[J - 1];
        ScriptDialogInjections[J - 1] := Swapped;
      end;
end;

procedure SortTalkDialogInjections;
begin
  SubmitSimple(ckSortTalkDialogInjections);
end;

// Moved from TfTalk.CodeMsgOut. The check marks the chameleon as detected when it fails.
procedure ExecuteCheckTalkCamouflage(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  TalkOutcome := Ord((H.TalkShip as TKling).IsPlayerCamouflageEffective(Actor(Command)));
end;

function CheckTalkCamouflage: Boolean;
begin
  SubmitSimple(ckCheckTalkCamouflage);
  Result := TalkOutcome <> 0;
end;

// Moved from TfTalk.CodeMsgOut.
procedure ExecutePublishTalkShipContext(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  TScriptShip(H.TalkShip.ScriptShip).Script.PublishShipContext(H.TalkShip.ScriptShip as TScriptShip);
end;

procedure PublishTalkShipContext;
begin
  SubmitSimple(ckPublishTalkShipContext);
end;

// Moved from TfTalk.CodeMsgOut.
procedure ExecuteTalkShipAuxiliaryCode(const Command: TPlayerCommand);
var
  H, SavedHuman: THuman;
  Binding: TScriptShip;
begin
  H := ActorHuman(Command);
  Binding := TScriptShip(H.TalkShip.ScriptShip);
  // CHANGE: ENHANCEMENT - The code runs for its script's human (docs/humans.md, Scripts).
  SavedHuman := ScriptHuman;
  ScriptHuman := BoundHuman(Binding.Script.HumanId);
  try
    try
      Binding.State.AuxiliaryCode.Run(ScriptProcess);
    except
      on E: Exception do
        // A UI break (EBreakMessageGI, a UI unit's class) only stops the code.
        if not E.ClassNameIs('EBreakMessageGI') then
        begin
          AppendLogLineThreadSafe(E.ClassName + ' ' + E.Message);
          LogScriptCallHistory;
          raise Exception.Create(
              AnsiString(
                  'Error in CodeMsgOut code of script '
                      + CurrentScript.ScriptFileName
                      + ' (state #'
                      + Binding.Ship.GetFullName(' ')
                      + ' '
                      + Binding.State.Name
                      + ')'
              ));
        end;
    end;
  finally
    ScriptHuman := SavedHuman;
  end;
end;

procedure RunTalkShipAuxiliaryCode;
begin
  SubmitSimple(ckTalkShipAuxiliaryCode);
end;

// Moved from TfTalk.BuildBuiltinChoices.
procedure ExecuteTalkRecognizesPlayer(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  TalkOutcome := Ord(not H.TalkShip.IsChameleonEffectiveAgainstSelf(Actor(Command)));
end;

function TalkRecognizesPlayer: Boolean;
begin
  SubmitSimple(ckTalkRecognizesPlayer);
  Result := TalkOutcome <> 0;
end;

// Moved from TfTalk.RunInjectedAnswer.
procedure ExecuteRunInjectedAnswerAction(const Command: TPlayerCommand);
var
  Injection: PScriptDialogInjection;
  SavedHuman: THuman;
begin
  Injection := InjectionArg(Command, 0);
  if Injection.ActionCode <> '' then
  begin
    CurrentScript := Injection.ActionScript;
    // CHANGE: ENHANCEMENT - The code runs for its script's human (docs/humans.md, Scripts).
    SavedHuman := ScriptHuman;
    ScriptHuman := BoundHuman(CurrentScript.HumanId);
    try
      ExecuteScriptText(Injection.ActionCode, CurrentScript.InitCode.LocalVar);
    finally
      ScriptHuman := SavedHuman;
    end;
  end;
end;

procedure RunInjectedAnswerAction(Injection: PScriptDialogInjection);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckRunInjectedAnswerAction);
  AddInjection(Command, Injection);
  SubmitCommand(Command);
end;

// Moved from TfTalk.RunInjectedAnswer.
procedure ExecuteCallInjectedDialog(const Command: TPlayerCommand);
var
  H: THuman;
  Injection: PScriptDialogInjection;
begin
  H := ActorHuman(Command);
  Injection := InjectionArg(Command, 0);
  Injection.Script.PublishCurrentShip(H.TalkShip);
  CurrentScript.InitCode.LocalVar.GetVar('GAnswerData').SetDword(Injection.AnswerData);
  CurrentScript.CallDialogByVariable(Injection.DialogName);
end;

procedure CallInjectedDialog(Injection: PScriptDialogInjection);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckCallInjectedDialog);
  AddInjection(Command, Injection);
  SubmitCommand(Command);
end;

{ Extortion and truce }

// Moved from TfTalk.ShowMoneyDemand.
procedure ExecuteShowMoneyDemand(const Command: TPlayerCommand);
var
  H: THuman;
  I: Integer;
  Partner: TShip;
  PartnerCanDemand: Boolean;
  Player: TPlayer;
begin
  H := ActorHuman(Command);
  Player := Actor(Command);
  TalkText := '';
  if (Player.TruceShip = H.TalkShip)
      or ((H.TalkShip is TNormalShip)
          and ((H.TalkShip as TNormalShip).LastPlayerExtortionTurn + 30 > Galaxy.CurrentTurn)) then
  begin
    TalkText := H.TalkShip.LookupTalkText('Talk.Money.WeAlreadyHavePact');
    H.TalkShip.ReactToExtortionDemand(Player);
    TalkOutcome := moRefused;
  end
  else
  begin
    PartnerCanDemand := False;
    for I := 0 to Player.PiratePartners.Count - 1 do
    begin
      Partner := Player.PiratePartners[I];
      if H.TalkShip.AcceptsRansomDemandFrom(Partner) then
      begin
        PartnerCanDemand := True;
        Break;
      end;
    end;
    if not H.TalkShip.AcceptsRansomDemandFrom(Player) and not PartnerCanDemand then
    begin
      TalkText := H.TalkShip.LookupTalkText('Talk.Money.' + H.TalkShip.GetTypeNameKey + 'No');
      H.TalkShip.ReactToExtortionDemand(Player);
      TalkOutcome := moRefused;
    end
    else if (H.TalkShip.TypeId <> stWarrior) and H.TalkShip.CanEscapePursuer(Player) then
    begin
      TalkText :=
          H.TalkShip.LookupTalkText('Talk.Money.' + H.TalkShip.GetTypeNameKey + 'LongDistance');
      H.TalkShip.ReactToExtortionDemand(Player);
      TalkOutcome := moRefused;
    end
    else
    begin
      TalkText := H.TalkShip.LookupTalkText('Talk.Money.ComputerAsk');
      TalkOutcome := moAsk;
    end;
  end;
end;

procedure ShowMoneyDemand;
begin
  SubmitSimple(ckShowMoneyDemand);
end;

// Moved from TfTalk.DemandMoney.
procedure ExecuteDemandMoney(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  TalkText := Command.Text;
  TalkOutcome :=
      Ord(H.TalkShip.BuildMoneyExtortionResponse(Actor(Command), TalkText, IntArg(Command, 0)));
end;

function DemandMoney(Amount: Integer; const Text: WideString): Boolean;
begin
  Result := SubmitAmountText(ckDemandMoney, Amount, Text);
end;

// Moved from TfTalk.DemandCargo.
procedure ExecuteDemandCargo(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  TalkText := Command.Text;
  TalkOutcome := Ord(H.TalkShip.BuildCargoExtortionResponse(Actor(Command), TalkText));
end;

function DemandCargo(const Text: WideString): Boolean;
begin
  Result := SubmitAmountText(ckDemandCargo, 0, Text);
end;

// Moved from TfTalk.ShowTruceOffer. The refusal's text is the screen's, after its choices.
procedure ExecuteShowTruceOffer(const Command: TPlayerCommand);
var
  H: THuman;
  Response: WideString;
  Player: TPlayer;
begin
  H := ActorHuman(Command);
  Player := Actor(Command);
  TalkText := '';
  if Player.TruceShip = H.TalkShip then
  begin
    TalkText := H.TalkShip.LookupTalkText('Talk.Truce.WeAlreadyHavePact');
    TalkOutcome := toHavePact;
  end
  else if H.TalkShip.UnknownVirtualC0(Player) then
    TalkOutcome := toRefused
  else if H.TalkShip.BuildTrucePaymentResponse(Player, Response, 0) then
  begin
    TalkText := H.TalkShip.LookupTalkText('Talk.Truce.ComputerOkWithoutMoney');
    TalkOutcome := toAcceptedFree;
  end
  else
  begin
    TalkText := H.TalkShip.LookupTalkText('Talk.Truce.ComputerAsk');
    TalkOutcome := toAsk;
  end;
end;

procedure ShowTruceOffer;
begin
  SubmitSimple(ckShowTruceOffer);
end;

// Moved from TfTalk.AcceptTruceOffer.
procedure ExecuteAcceptTruceOffer(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  TalkText := Command.Text;
  TalkOutcome :=
      Ord(H.TalkShip.BuildTrucePaymentResponse(Actor(Command), TalkText, IntArg(Command, 0)));
end;

function AcceptTruceOffer(Amount: Integer; const Text: WideString): Boolean;
begin
  Result := SubmitAmountText(ckAcceptTruceOffer, Amount, Text);
end;

{ Attacks and protection }

// Moved from TfTalk.ShowAttackTargets; the choices stay in the screen.
procedure ExecuteShowAttackTargets(const Command: TPlayerCommand);
var
  H: THuman;
  Ship: TShip;
  AllowTargets, ReadyAttack: Boolean;
  Player: TPlayer;
begin
  H := ActorHuman(Command);
  Player := Actor(Command);
  TalkText := '';
  TalkTarget := nil;
  AllowTargets := True;
  ReadyAttack := False;
  if H.TalkShip.RecomputeFearState and (Player <> H.TalkShip.PartnerShip) then
  begin
    TalkText := H.TalkShip.LookupTalkText('Talk.Attack.ComputerInFear');
    AllowTargets := False;
  end
  else if H.TalkShip is TTranclucator then
    TalkText := H.TalkShip.LookupTalkText('Talk.Tranclucator.Attack.Ask')
  else if not H.TalkShip.TrustsAttackRequester(Player) then
  begin
    TalkText := H.TalkShip.LookupTalkText('Talk.Attack.' + H.TalkShip.GetTypeNameKey + 'Suspect');
    AllowTargets := False;
  end
  else if H.TalkShip.HasLockedOrFollowOrder
      and (Player <> H.TalkShip.PartnerShip)
      and (H.TalkShip.TypeId <> stWarrior) then
  begin
    TalkText :=
        H.TalkShip.LookupTalkText('Talk.Attack.' + H.TalkShip.GetTypeNameKey + 'HaveBusiness');
    AllowTargets := False;
  end
  else if H.TalkShip.OrderTarget is TShip then
  begin
    Ship := H.TalkShip.OrderTarget as TShip;
    if (H.TalkShip.GetRelationLevelToShip(Ship) = rlHostile)
        and Player.CanSelectShipTarget(Ship)
        and not (Ship.TargetingRestriction in [1, 2]) then
    begin
      TalkText :=
          FormatText1(
              H.TalkShip.LookupTalkText('Talk.Attack.ComputerReadyAttack'),
              '<color=255,240,100>',
              '<Target>',
              Ship.GetFullName(' ') + GetLocalObjectLink(Ship, False)
          );
      ReadyAttack := True;
      TalkTarget := Ship;
      AllowTargets := True;
    end
    else
    begin
      TalkText :=
          H.TalkShip.LookupTalkText('Talk.Attack.' + H.TalkShip.GetTypeNameKey + 'HaveBusiness');
      AllowTargets := False;
    end;
  end
  else
    TalkText := H.TalkShip.LookupTalkText('Talk.Attack.ComputerAsk');
  TalkOutcome := 0;
  if AllowTargets then
    TalkOutcome := TalkOutcome or aoAllowTargets;
  if ReadyAttack then
    TalkOutcome := TalkOutcome or aoReadyAttack;
end;

procedure ShowAttackTargets;
begin
  SubmitSimple(ckShowAttackTargets);
end;

// Moved from TfTalk.RequestAttackTarget.
procedure ExecuteRequestAttackTarget(const Command: TPlayerCommand);
var
  H: THuman;
  Target: TShip;
  Event: TGalaxyEvent;
  Accepted: Boolean;
  Player: TPlayer;
begin
  H := ActorHuman(Command);
  Player := Actor(Command);
  Target := ShipArg(Command, 0);
  if H.TalkShip.RecomputeFearState
      and (H.TalkShip.OrderTarget <> Target)
      and (Player <> H.TalkShip.PartnerShip) then
  begin
    TalkText := H.TalkShip.LookupTalkText('Talk.Attack.ComputerInFear');
    TalkOutcome := raInFear;
    Exit;
  end;
  TalkText := Command.Text;
  Accepted := H.TalkShip.BuildAttackRequestResponse(Player, TalkText, Target);
  if Accepted then
  begin
    Event := AddGalaxyEvent('PlayerTalkedShipIntoAttacking');
    Event.AddData(H.TalkShip.Id);
    Event.AddData(Target.Id);
    TalkOutcome := raAccepted;
  end
  else
    TalkOutcome := raRefused;
end;

procedure RequestAttackTarget(Target: TShip; const Text: WideString);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckRequestAttackTarget);
  AddRef(Command, Target);
  Command.Text := Text;
  SubmitCommand(Command);
end;

// Moved from TfTalk.AcceptJointAttack.
procedure ExecuteAcceptJointAttack(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  H.TalkShip.SetJointAttackTarget(Actor(Command), ShipArg(Command, 0));
end;

procedure AcceptJointAttack(Target: TShip);
begin
  SubmitShip(ckAcceptJointAttack, Target);
end;

// Moved from TfTalk.RequestProtection.
procedure ExecuteRequestProtection(const Command: TPlayerCommand);
var
  H: THuman;
  Target: TShip;
  I, Reward: Integer;
  Weapon: TWeapon;
  CanEscape, FearsAttacker, RecognizesPlayer: Boolean;
  Player: TPlayer;
begin
  H := ActorHuman(Command);
  Player := Actor(Command);
  if (not H.TalkShip.RecomputeFearState)
      and (H.TalkShip.GetRelationLevelToShip(Player) = rlHostile) then
  begin
    TalkText := H.TalkShip.LookupTalkText('Talk.Protect.ComputerNotFearAndWar');
    TalkOutcome := rpNotFearAndWar;
    Exit;
  end;
  Target := TShip(H.TalkShip.OrderTarget);
  if H.TalkShip.UnknownVirtualC0(Target) then
  begin
    if H.TalkShip.GetRelationLevelToShip(Player) = rlHostile then
      TalkText := H.TalkShip.LookupTalkText('Talk.Protect.ComputerNotFearAndWar')
    else
      TalkText :=
          FormatText1(
              H.TalkShip.LookupTalkText('Talk.Protect.' + H.TalkShip.GetTypeNameKey + 'No'),
              '<color=255,240,100>',
              '<Target>',
              Target.GetFullName(' ') + GetLocalObjectLink(Target, False)
          );
    TalkOutcome := rpRefusedTarget;
    Exit;
  end;
  if H.TalkShip.EvaluateAllyRelationAndStrength(Player) then
  begin
    CanEscape := Target.CanEscapePursuer(H.TalkShip);
    FearsAttacker := Target.AcceptsRansomDemandFrom(H.TalkShip);
    Reward :=
        Round(
            RemapClamped(
                Target.ChanceToWin(H.TalkShip),
                0.1,
                1,
                Galaxy.ComputeScaledSmallMoney(Target.OwnerId) * 0.5,
                Galaxy.ComputeScaledMiniMoney(Target.OwnerId) * 0.5
            )
        );
    if H.TalkShip.EnemyShip = Target then
      H.TalkShip.EnemyShip := nil;
    if H.TalkShip.TypeId = stRanger then
      Target.ChangeRelationToRanger(H.TalkShip, 15);
    if H.TalkShip = Target.EnemyShip then
      Target.EnemyShip := nil;
    if Target.TypeId = stRanger then
      H.TalkShip.ChangeRelationToRanger(Target, 15);
    H.TalkShip.TruceShip := Target;
    H.TalkShip.NextDay;
    if H.TalkShip.OrderTarget = Target then
      H.TalkShip.OrderNone(False);
    if (H.TalkShip.Order = soFollowShip)
        and ((H.TalkShip.OrderTarget as TShip).TypeId in [stRanger..stPirate]) then
    begin
      H.TalkShip.NavigateToQueuedPlanet(False);
      if H.TalkShip.Order = soFollowShip then
        H.TalkShip.OrderNone(False);
    end;
    for I := 1 to Target.WeaponCount do
    begin
      Weapon := Target.Weapons[I];
      if H.TalkShip = Weapon.Target then
        Weapon.Target := nil;
    end;
    for I := 1 to H.TalkShip.WeaponCount do
    begin
      Weapon := H.TalkShip.Weapons[I];
      if Weapon.Target = Target then
        Weapon.Target := nil;
    end;
    H.TalkShip.TruceWithShip(Target);
    Target.ChangeRelationToRanger(Player, 50);
    if H.TalkShip.TypeId = stPirate then
      Player.AddWarriorCareerActivity(4);
    if Target.TypeId = stPirate then
      Player.AddPirateCareerActivity(8);
    TalkText :=
        FormatText1(
            H.TalkShip.LookupTalkText('Talk.Protect.' + H.TalkShip.GetTypeNameKey + 'Ok'),
            '<color=255,240,100>',
            '<Target>',
            Target.GetFullName(' ') + GetLocalObjectLink(Target, False)
        );
    RecognizesPlayer := not Target.IsChameleonEffectiveAgainstSelf(Actor(Command));
    if RecognizesPlayer and (Target.TypeId in [stRanger..stPirate]) then
    begin
      if not FearsAttacker then
        Target.ShowMessageToPlayer(Target.LookupTalkText('Talk.Protect.TargetNotFearShip'), Player)
      else if CanEscape and (Target.GetHullIntegrityPercent > 30) then
        Target.ShowMessageToPlayer(Target.LookupTalkText('Talk.Protect.TargetMayRunAway'), Player)
      else if Target.HasCargoGoods then
      begin
        Target.JettisonCargoGoodsTowardTargetValue(Reward);
        Target.ShowMessageToPlayer(Target.LookupTalkText('Talk.Protect.TargetGiveGoods'), Player);
      end
      else if Target.Money >= Reward then
      begin
        Target.SetMoney(Target.Money - Reward);
        Player.SetMoney(Player.Money + Reward);
        Target.ShowMessageToPlayer(
            FormatText1(
                Target.LookupTalkText('Talk.Protect.TargetGiveMoney'),
                '<color=255,240,100>',
                '<Money>',
                WideString(IntToStr(Reward))
            ),
            Player
        );
      end
      else
        Target.ShowMessageToPlayer(Target.LookupTalkText('Talk.Protect.TargetThanks'), Player);
    end;
    TalkOutcome := rpAccepted;
  end
  else
  begin
    TalkText :=
        FormatText1(
            H.TalkShip.LookupTalkText('Talk.Protect.' + H.TalkShip.GetTypeNameKey + 'No'),
            '<color=255,240,100>',
            '<Target>',
            Target.GetFullName(' ') + GetLocalObjectLink(Target, False)
        );
    TalkOutcome := rpRefused;
  end;
end;

procedure RequestProtection;
begin
  SubmitSimple(ckRequestProtection);
end;

// Moved from TfTalk.RequestPreserveItems.
procedure ExecuteRequestPreserveItems(const Command: TPlayerCommand);
var
  H: THuman;
  I: Integer;
  Player: TPlayer;
begin
  H := ActorHuman(Command);
  Player := Actor(Command);
  if (H.TalkShip.GetRelationLevelToShip(Player) = rlHostile)
      and not H.TalkShip.RecomputeFearState then
    TalkText := H.TalkShip.LookupTalkText('Talk.PreserveItems.ComputerNotFearAndWar')
  else if (H.TalkShip.GetRelationLevelToShip(Player) >= rlGood)
      or H.TalkShip.EvaluateAllyRelationAndStrength(Player) then
  begin
    TalkText := H.TalkShip.LookupTalkText('Talk.PreserveItems.' + H.TalkShip.GetTypeNameKey + 'Ok');
    if Player.PickupTargets <> nil then
      for I := 1 to H.TalkShip.WeaponCount do
        if (H.TalkShip.Weapons[I].Target <> nil)
            and (Player.PickupTargets.IndexOf(H.TalkShip.Weapons[I].Target) >= 0) then
          H.TalkShip.Weapons[I].Target := nil;
  end
  else
    TalkText := H.TalkShip.LookupTalkText('Talk.PreserveItems.' + H.TalkShip.GetTypeNameKey + 'No');
end;

procedure RequestPreserveItems;
begin
  SubmitSimple(ckRequestPreserveItems);
end;

{ Partners }

// Moved from TfTalk.AcceptPartnerOffer.
procedure ExecuteAcceptPartnerOffer(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  TalkText := Command.Text;
  TalkOutcome :=
      Ord(H.TalkShip.AcceptPartnershipOffer(Actor(Command), TalkText, IntArg(Command, 0)));
end;

function AcceptPartnerOffer(Amount: Integer; const Text: WideString): Boolean;
begin
  Result := SubmitAmountText(ckAcceptPartnerOffer, Amount, Text);
end;

// Moved from TfTalk.AcceptPiratePartnerOffer.
procedure ExecuteAcceptPiratePartnerOffer(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  TalkText := Command.Text;
  TalkOutcome := 0;
  if H.TalkShip.AcceptPartnershipOffer(Actor(Command), TalkText, IntArg(Command, 0)) then
  begin
    TalkOutcome := 1;
    Actor(Command).PiratePartners.Add(H.TalkShip);
  end;
end;

function AcceptPiratePartnerOffer(Amount: Integer; const Text: WideString): Boolean;
begin
  Result := SubmitAmountText(ckAcceptPiratePartnerOffer, Amount, Text);
end;

// Moved from TfTalk.OrderPartnerFollow and OrderPiratePartnerFollow.
procedure ExecuteOrderTalkShipFollow(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  H.TalkShip.OrderFollowShip(Actor(Command), 0, True);
end;

procedure OrderTalkShipFollow;
begin
  SubmitSimple(ckOrderTalkShipFollow);
end;

// Moved from TfTalk.OrderPartnerLand and OrderPiratePartnerLand.
procedure ExecuteOrderTalkShipLand(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  H.TalkShip.OrderLanding(Actor(Command).OrderTarget, True);
end;

procedure OrderTalkShipLand;
begin
  SubmitSimple(ckOrderTalkShipLand);
end;

// Moved from TfTalk.OrderPartnerJump and OrderPiratePartnerJump.
procedure ExecuteOrderTalkShipJump(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  H.TalkShip.OrderJump(Actor(Command).OrderTarget as TStar, True);
end;

procedure OrderTalkShipJump;
begin
  SubmitSimple(ckOrderTalkShipJump);
end;

// Moved from TfTalk.OrderPartnerDropCargo.
procedure ExecuteOrderPartnerDropCargo(const Command: TPlayerCommand);
var
  H: THuman;
  Player: TPlayer;
begin
  H := ActorHuman(Command);
  Player := Actor(Command);
  H.TalkShip.ChangeRelationToRanger(
      Player,
      -Round(
          H.TalkShip.NextRandomInteger(5, 15)
              / PlanetRaceMarket[H.TalkShip.PilotRace].PirateRelationFactor
      )
  );
  if H.TalkShip.GetRelationLevelToShip(Player) = rlHostile then
    H.TalkShip.ChangeRelationToRanger(Player, 10);
  if not Player.CanResolveObjectWithScanner(H.TalkShip) then
    TalkOutcome := 0
  else
  begin
    TalkOutcome := 1;
    H.TalkShip.DropUnequippedItemsAndGoods;
  end;
end;

function OrderPartnerDropCargo: Boolean;
begin
  SubmitSimple(ckOrderPartnerDropCargo);
  Result := TalkOutcome <> 0;
end;

// Moved from TfTalk.GivePartnerGift and PayPartnerGiftMoney.
procedure ExecuteGivePartnerGift(const Command: TPlayerCommand);
var
  H: THuman;
  Change, Amount, Remaining, Payment: Integer;
  Player: TPlayer;
begin
  H := ActorHuman(Command);
  Player := Actor(Command);
  Amount := IntArg(Command, 0);
  Change :=
      Round(
          (150 * Amount)
              / Max(1, H.TalkShip.Wealth + Player.Wealth)
              * PlanetRaceMarket[H.TalkShip.PilotRace].FriendlyRelationScale
      );
  Change := Max(0, Min(100, Change));
  H.TalkShip.ChangeRelationToRanger(Player, Change);
  Remaining := Player.Money - Amount;
  if Remaining < 0 then
    Payment := 0
  else
    Payment := Remaining;
  Player.SetMoney(Payment);
  H.TalkShip.SetMoney(H.TalkShip.Money + Amount);
end;

procedure GivePartnerGift(Amount: Integer);
begin
  SubmitInt(ckGivePartnerGift, Amount);
end;

// Moved from TfTalk.GivePiratePartnerGift and PayPiratePartnerGiftMoney.
procedure ExecuteGivePiratePartnerGift(const Command: TPlayerCommand);
var
  H: THuman;
  Change, Amount, Remaining, Payment: Integer;
  Player: TPlayer;
begin
  H := ActorHuman(Command);
  Player := Actor(Command);
  Amount := IntArg(Command, 0);
  if H.TalkShip is TNormalShip then
    Change :=
        Round(
            (150 * Amount)
                / Max(1, H.TalkShip.Wealth + Player.Wealth)
                * PlanetRaceMarket[H.TalkShip.PilotRace].FriendlyRelationScale
        )
  else
    Change := Round((150 * Amount) / Max(1, H.TalkShip.Wealth + Player.Wealth));
  Change := Max(0, Min(100, Change));
  H.TalkShip.ChangeRelationToRanger(Player, Change);
  Remaining := Player.Money - Amount;
  if Remaining < 0 then
    Payment := 0
  else
    Payment := Remaining;
  Player.SetMoney(Payment);
  H.TalkShip.SetMoney(H.TalkShip.Money + Amount);
end;

procedure GivePiratePartnerGift(Amount: Integer);
begin
  SubmitInt(ckGivePiratePartnerGift, Amount);
end;

// Moved from TfTalk.ApplyOrderToAllPartners.
procedure ExecuteApplyOrderToAllPartners(const Command: TPlayerCommand);
var
  H: THuman;
  I: Integer;
  Ship: TShip;
  Player: TPlayer;
begin
  H := ActorHuman(Command);
  Player := Actor(Command);
  for I := 0 to Player.CurrentStar.Ships.Count - 1 do
  begin
    Ship := Player.CurrentStar.Ships[I];
    if (Player = Ship.PartnerShip)
        and Ship.InNormalSpace
        and (Player <> Ship)
        and (H.TalkShip <> Ship) then
    begin
      if Player = H.TalkShip.OrderTarget then
        Ship.OrderFollowShip(Player, 0, True)
      else if H.TalkShip.Order = soFollowShip then
        Ship.SetJointAttackTarget(Ship, H.TalkShip.OrderTarget as TShip)
      else if H.TalkShip.Order = soLand then
        Ship.OrderLanding(Player.OrderTarget, True)
      else if H.TalkShip.Order = soJump then
        Ship.OrderJump(Player.OrderTarget as TStar, True);
    end;
  end;
end;

procedure ApplyOrderToAllPartners;
begin
  SubmitSimple(ckApplyOrderToAllPartners);
end;

// Moved from TfTalk.OrderPiratePartnerAttack.
procedure ExecuteOrderPiratePartnerAttack(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  H.TalkShip.SetJointAttackTarget(H.TalkShip, ShipArg(Command, 0));
end;

procedure OrderPiratePartnerAttack(Target: TShip);
begin
  SubmitShip(ckOrderPiratePartnerAttack, Target);
end;

// Moved from TfTalk.ShipDismissAct.
procedure ExecuteDismissPartner(const Command: TPlayerCommand);
var
  H: THuman;
  Action: Integer;
begin
  H := ActorHuman(Command);
  Action := IntArg(Command, 0);
  case Action of
    1: ;
    2:
    begin
      if (H.TalkShip.Order = soFollowShip) and (H.TalkShip.OrderTarget = H.TalkShip.PartnerShip) then
        H.TalkShip.OrderNone(False);
      H.TalkShip.PartnerShip := nil;
    end;
    3:
    begin
      H.TalkShip.PartnerShip := nil;
      H.TalkShip.ChangeRelationToRanger(Actor(Command), 10);
      H.TalkShip.EnemyShip := Actor(Command);
      H.TalkShip.EngageEnemyShip;
    end;
  else
    RaiseWideMessage(
        WideString('ShipDismissAct: invalid data = ' + IntToStr(Int64(Cardinal(Action))))
    );
  end;
end;

procedure DismissPartner(Action: Integer);
begin
  SubmitInt(ckDismissPartner, Action);
end;

// Moved from TfTalk.DiscussOldHull.
procedure ExecuteOffendOverOldHull(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  H.TalkShip.ChangeRelationToRanger(Actor(Command), -15);
end;

procedure OffendOverOldHull;
begin
  SubmitSimple(ckOffendOverOldHull);
end;

{ Tranclucators }

// Moved from TfTalk.OrderTranclucatorFollow.
procedure ExecuteOrderTranclucatorFollow(const Command: TPlayerCommand);
var
  H: THuman;
  Ship: TTranclucator;
begin
  H := ActorHuman(Command);
  Ship := H.TalkShip as TTranclucator;
  Ship.OrderFollowShip(Actor(Command), 0, True);
  Ship.FollowOwner := False;
  Ship.SeekItems := False;
end;

procedure OrderTranclucatorFollow;
begin
  SubmitSimple(ckOrderTranclucatorFollow);
end;

// Moved from TfTalk.OrderTranclucatorReturn.
procedure ExecuteOrderTranclucatorReturn(const Command: TPlayerCommand);
var
  H: THuman;
  Ship: TTranclucator;
begin
  H := ActorHuman(Command);
  Ship := H.TalkShip as TTranclucator;
  Ship.OrderFollowShip(Ship.OwnerShip, 1, False);
  Ship.FollowOwner := True;
  Ship.SeekItems := False;
end;

procedure OrderTranclucatorReturn;
begin
  SubmitSimple(ckOrderTranclucatorReturn);
end;

// Moved from TfTalk.OrderTranclucatorSeekItems.
procedure ExecuteOrderTranclucatorSeekItems(const Command: TPlayerCommand);
var
  H: THuman;
  Ship: TTranclucator;
begin
  H := ActorHuman(Command);
  Ship := H.TalkShip as TTranclucator;
  Ship.FollowOwner := False;
  Ship.SeekItems := True;
  if Ship.CargoFreeSpace > 0 then
    Ship.TryCollectPreferredFloatingLoot(50);
end;

procedure OrderTranclucatorSeekItems;
begin
  SubmitSimple(ckOrderTranclucatorSeekItems);
end;

// Moved from TfTalk.CancelTranclucatorSeekItems.
procedure ExecuteCancelTranclucatorSeekItems(const Command: TPlayerCommand);
var
  H: THuman;
  Ship: TTranclucator;
begin
  H := ActorHuman(Command);
  Ship := H.TalkShip as TTranclucator;
  Ship.FollowOwner := False;
  Ship.SeekItems := False;
  Ship.UpdateFreeFlightOrder;
end;

procedure CancelTranclucatorSeekItems;
begin
  SubmitSimple(ckCancelTranclucatorSeekItems);
end;

// Moved from TfTalk.ShowTranclucatorOptions.
procedure ExecuteSetTranclucatorOptions(const Command: TPlayerCommand);
var
  H: THuman;
  Ship: TTranclucator;
  Digit: Cardinal;
  Action: PtrInt;
  Enabled: Boolean;
  procedure PopTranclucatorOptionDigit;
  begin
    Digit := Cardinal(Action) mod 10;
    Action := Cardinal(Action) div 10;
  end;
begin
  H := ActorHuman(Command);
  Action := IntArg(Command, 0);
  Ship := H.TalkShip as TTranclucator;
  PopTranclucatorOptionDigit;
  Enabled := Digit = 1;
  PopTranclucatorOptionDigit;
  Ship.SetCollectionPermission(TTranclucatorCollectionKind(Digit), Enabled);
  PopTranclucatorOptionDigit;
  Enabled := Digit = 1;
  PopTranclucatorOptionDigit;
  Ship.SetStoragePermission(TTranclucatorStorageKind(Digit), Enabled);
  PopTranclucatorOptionDigit;
  if Digit = 2 then
    Ship.AutoArrange := True
  else if Digit = 1 then
    Ship.AutoArrange := False;
end;

procedure SetTranclucatorOptions(Action: Integer);
begin
  SubmitInt(ckSetTranclucatorOptions, Action);
end;

// Moved from TfTalk.OrderTranclucatorDropCargo.
procedure ExecuteOrderTranclucatorDropCargo(const Command: TPlayerCommand);
var
  H: THuman;
  Ship: TTranclucator;
begin
  H := ActorHuman(Command);
  Ship := H.TalkShip as TTranclucator;
  Ship.FollowOwner := False;
  Ship.SeekItems := False;
  Ship.DropUnequippedItemsAndGoods;
  Ship.UpdateFreeFlightOrder;
end;

procedure OrderTranclucatorDropCargo;
begin
  SubmitSimple(ckOrderTranclucatorDropCargo);
end;

// Moved from TfTalk.OrderTranclucatorLand.
procedure ExecuteOrderTranclucatorLand(const Command: TPlayerCommand);
var
  H: THuman;
  Ship: TTranclucator;
begin
  H := ActorHuman(Command);
  Ship := H.TalkShip as TTranclucator;
  Ship.FollowOwner := False;
  Ship.SeekItems := False;
  Ship.StoreOnLanding := False;
  Ship.OrderLanding(Actor(Command).OrderTarget, True);
end;

procedure OrderTranclucatorLand;
begin
  SubmitSimple(ckOrderTranclucatorLand);
end;

// Moved from TfTalk.OrderTranclucatorStoreCargo.
procedure ExecuteOrderTranclucatorStoreCargo(const Command: TPlayerCommand);
var
  H: THuman;
  Ship: TTranclucator;
begin
  H := ActorHuman(Command);
  Ship := H.TalkShip as TTranclucator;
  Ship.FollowOwner := False;
  Ship.SeekItems := False;
  Ship.StoreOnLanding := True;
  Ship.OrderLanding(Actor(Command).OrderTarget, True);
end;

procedure OrderTranclucatorStoreCargo;
begin
  SubmitSimple(ckOrderTranclucatorStoreCargo);
end;

// Moved from TfTalk.ApplyOrderToAllTranclucators.
procedure ExecuteApplyOrderToAllTranclucators(const Command: TPlayerCommand);
var
  H: THuman;
  Current, Target: TTranclucator;
  Ship: TShip;
  I: Integer;
begin
  H := ActorHuman(Command);
  Current := H.TalkShip as TTranclucator;
  for I := 0 to Current.CurrentStar.Ships.Count - 1 do
  begin
    Ship := Current.CurrentStar.Ships[I];
    if (Ship is TTranclucator)
        and (Ship <> Current)
        and ((Ship as TTranclucator).OwnerShip = Actor(Command))
        and Ship.InNormalSpace then
    begin
      Target := TTranclucator(Ship);
      Target.FollowOwner := Current.FollowOwner;
      Target.SeekItems := Current.SeekItems;
      Target.StoreOnLanding := Current.StoreOnLanding;
      Target.Order := Current.Order;
      Target.OrderStateData := Current.OrderStateData;
      Target.OrderTarget := Current.OrderTarget;
      Target.OrderDestination := Current.OrderDestination;
      Target.OrderAbsolute := Current.OrderAbsolute;
      if Current.OrderTarget = Current.EnemyShip then
        Target.EnemyShip := Current.EnemyShip;
      if Target.SeekItems then
      begin
        if Current.CargoFreeSpace > 0 then
          Target.TryCollectPreferredFloatingLoot(50)
        else
          Target.UpdateFreeFlightOrder;
      end;
    end;
  end;
end;

procedure ApplyOrderToAllTranclucators;
begin
  SubmitSimple(ckApplyOrderToAllTranclucators);
end;

{ Dominators }

// Moved from TfTalk.RunDominatorProgram.
procedure ExecuteRunDominatorProgram(const Command: TPlayerCommand);
var
  H: THuman;
  ProgramIndex: Byte;
  Remaining: Integer;
  Player: TPlayer;
begin
  H := ActorHuman(Command);
  Player := Actor(Command);
  ProgramIndex := IntArg(Command, 0);
  Remaining := Player.ProgramCounts[ProgramIndex] - 1;
  Player.ProgramCounts[ProgramIndex] := Remaining;
  if (H.TalkShip as TKling).KlingType in [ktBoss, ktBertor] then
  begin
    (H.TalkShip as TKling).DetectAttackingPlayer(Player);
    TalkOutcome := 0;
    Exit;
  end;
  (H.TalkShip as TKling).ActiveProgramAppliedTurn := Galaxy.CurrentTurn;
  (H.TalkShip as TKling).ActiveProgramId := ProgramIndex;
  Inc(Player.AchievementStats.SuccessfulDominatorHacks);
  case (H.TalkShip as TKling).ActiveProgramId of
    prgShipwreck:
      H.TalkShip.DropItemsForDominatorProgram(SeededRandomIntRange(1, 3, Galaxy.CurrentTurn));
    prgSelfDestruction: H.TalkShip.DestroyQueued := True;
    prgDisconnection:
    begin
      H.TalkShip.OrderNone(False);
      H.TalkShip.ClearWeaponTargets(nil);
    end;
  end;
  (H.TalkShip as TKling).DetectAttackingPlayer(Player);
  TalkOutcome := 1;
end;

function RunDominatorProgram(ProgramIndex: Integer): Boolean;
begin
  SubmitInt(ckRunDominatorProgram, ProgramIndex);
  Result := TalkOutcome <> 0;
end;

{ Military support }

function GetMilitaryHullRepairCost(Player: TPlayer): Integer;
begin
  Result :=
      Ceil(
          ((Player.GetHull.Weight - Player.GetHull.HullPoints) / 10)
              * (Player.GetCombatStatusStrength(cseBWRepairDebuff) * 0.002 + 1)
              * RemapClamped(Galaxy.TechLevel, 2, 8, 5, 1)
      );
end;

// Moved from TfTalk.AcceptMilitaryHullRepair; the screen shows the repair.
procedure ExecuteMilitaryHullRepair(const Command: TPlayerCommand);
var
  RepairAmount, Nodes: Integer;
  Fraction: Single;
  Player: TPlayer;
begin
  Player := Actor(Command);
  Nodes := IntArg(Command, 0);
  Player.ConsumeAvailableNodes(Nodes, nil);
  Fraction := Nodes / GetMilitaryHullRepairCost(Player);
  RepairAmount :=
      Ceil(
          RemapClamped(
              Fraction,
              0,
              1,
              0.01,
              Player.GetHull.Weight - Player.GetHull.HullPoints
          )
      );
  Inc(Player.GetHull.HullPoints, RepairAmount);
  Player.AddCombatStatusStrength(cseBWRepairDebuff, RepairAmount, nil);
  Player.RefreshDerivedStats(True);
  TalkOutcome := RepairAmount;
end;

function MilitaryHullRepair(Nodes: Integer): Integer;
begin
  SubmitInt(ckMilitaryHullRepair, Nodes);
  Result := TalkOutcome;
end;

function GetMilitaryEquipmentRepairCost(Human: THuman): Integer;
var
  I: Integer;
  Item: TEquipment;
begin
  Result := 0;
  for I := 0 to Human.Player.Inventory.Count - 1 do
  begin
    Item := Human.Player.Inventory[I];
    if ((not (Item is TWeapon))
            or (TWeapon(Item).GetWeaponInfo.Availability <> waNotSoldAndNodeRepair))
        and (Item.ItemType <> t_Hull)
        and (Item.EquippedFlag <> 0)
        and Human.TalkShip.CanRepairEquipmentTech(Item)
        and (Item.ConditionPercent < 90) then
      Inc(Result, Round(Item.CalculateRepairCost));
  end;
  if Result > 0 then
  begin
    Result := Round(Result * 0.0025 * RemapClamped(Galaxy.TechLevel, 2, 8, 5, 1));
    if Result = 0 then
      Result := 1;
  end;
end;

// Moved from TfTalk.AcceptMilitaryEquipmentRepair.
procedure ExecuteMilitaryEquipmentRepair(const Command: TPlayerCommand);
var
  H: THuman;
  Fraction: Single;
  I, Nodes: Integer;
  Item: TEquipment;
  Player: TPlayer;
begin
  H := ActorHuman(Command);
  Player := Actor(Command);
  Nodes := IntArg(Command, 0);
  Fraction := Nodes / GetMilitaryEquipmentRepairCost(H);
  Player.ConsumeAvailableNodes(Nodes, nil);
  for I := 0 to Player.Inventory.Count - 1 do
  begin
    Item := Player.Inventory[I];
    if ((not (Item is TWeapon))
            or (TWeapon(Item).GetWeaponInfo.Availability <> waNotSoldAndNodeRepair))
        and (Item.ItemType <> t_Hull)
        and (Item.EquippedFlag <> 0)
        and H.TalkShip.CanRepairEquipmentTech(Item)
        and (Item.ConditionPercent < 90) then
    begin
      Item.ConditionPercent := RemapClamped(Fraction, 0, 1, Item.ConditionPercent, 100);
      if Item.ConditionPercent > 0 then
        Item.BrokenFlag := 0;
    end;
  end;
  Player.RefreshDerivedStats(True);
end;

procedure MilitaryEquipmentRepair(Nodes: Integer);
begin
  SubmitInt(ckMilitaryEquipmentRepair, Nodes);
end;

function IsMilitaryProtectedQuestItem(Player: TPlayer; Item: TItem): Boolean;
var
  I: Integer;
  Quest: PQuest;
begin
  Result := False;
  if (Item is TUselessItem) and (Item.ScriptItem = nil) then
    for I := 0 to Player.Quests.Count - 1 do
    begin
      Quest := Player.Quests[I];
      if Quest.QuestType = qtSendLetter then
        if LocalizedColorText(
                WideString('Quest.SendLetter.' + IntToStr(Quest.QuestNumber) + '.SysName'))
            = (Item as TUselessItem).ConfigBlockName then
          Result := True;
    end;
end;

procedure DonateMilitaryResearchMaterial(Series: TDominatorSeries; Amount: Integer);
var
  Other: TDominatorSeries;
  Count: Integer;
begin
  if (Galaxy.DominatorResearch[Ord(Series)].Progress < 100)
      and Galaxy.IsDominatorSeriesUnresolved(Series) then
    Inc(Galaxy.DominatorResearch[Ord(Series)].Material, Amount)
  else
  begin
    Count := 0;
    for Other := dsBlazer to dsTerron do
      if (Galaxy.DominatorResearch[Ord(Other)].Progress < 100)
          and Galaxy.IsDominatorSeriesUnresolved(Other) then
        Inc(Count);
    if Count <> 0 then
      for Other := dsBlazer to dsTerron do
        if (Galaxy.DominatorResearch[Ord(Other)].Progress < 100)
            and Galaxy.IsDominatorSeriesUnresolved(Other) then
          Inc(Galaxy.DominatorResearch[Ord(Other)].Material, Amount div Count);
  end;
end;

// Moved from TfTalk.SellAllMilitaryRemains.
procedure ExecuteSellAllMilitaryRemains(const Command: TPlayerCommand);
var
  I, Cost: Integer;
  Item: TEquipment;
  Player: TPlayer;
begin
  Player := Actor(Command);
  Cost := 0;
  for I := Player.Inventory.Count - 1 downto 1 do
  begin
    Item := Player.Inventory[I];
    if (Item.OwnerId = Byte(oiDominator))
        and (Item is TUselessItem)
        and not IsMilitaryProtectedQuestItem(Player, Item) then
    begin
      Player.Inventory.Delete(I);
      if (Galaxy.DominatorResearch[Ord(Item.DominatorSeries)].Progress < 100)
          and Galaxy.IsDominatorSeriesUnresolved(Item.DominatorSeries) then
        Inc(Cost, Round(Item.Cost * 1.5))
      else
        Inc(Cost, Item.Cost);
      DonateMilitaryResearchMaterial(Item.DominatorSeries, Item.Weight);
      Item.Free;
    end;
  end;
  Player.SetMoney(Player.Money + Cost);
end;

procedure SellAllMilitaryRemains;
begin
  SubmitSimple(ckSellAllMilitaryRemains);
end;

// Moved from TfTalk.SellIndividualMilitaryRemains.
procedure ExecuteSellMilitaryRemains(const Command: TPlayerCommand);
var
  I, Cost: Integer;
  Item: TEquipment;
  Player: TPlayer;
begin
  Player := Actor(Command);
  TalkOutcome := 0;
  Item := TEquipment(RefObject(Command, 0));
  I := Player.Inventory.IndexOf(Item);
  if I >= 0 then
  begin
    Player.Inventory.Delete(I);
    if (Galaxy.DominatorResearch[Ord(Item.DominatorSeries)].Progress < 100)
        and Galaxy.IsDominatorSeriesUnresolved(Item.DominatorSeries) then
      Cost := Round(Item.Cost * 1.5)
    else
      Cost := Item.Cost;
    DonateMilitaryResearchMaterial(Item.DominatorSeries, Item.Weight);
    Player.SetMoney(Player.Money + Cost);
    TalkOutcome := 1;
    Item.Free;
  end;
end;

function SellMilitaryRemains(Item: TItem): Boolean;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckSellMilitaryRemains);
  AddRef(Command, Item);
  SubmitCommand(Command);
  Result := TalkOutcome <> 0;
end;

// Moved from TfTalk.AcceptMilitaryBuff.
procedure ExecuteMilitaryBuff(const Command: TPlayerCommand);
var
  Player: TPlayer;
begin
  Player := Actor(Command);
  Player.ConsumeAvailableNodes(IntArg(Command, 0), nil);
  TalkOutcome := Ord(Player.GetCombatStatusStrength(cseBWBuff) > 0.01);
  Player.AddCombatStatusStrength(cseBWBuff, 20, nil);
  Player.RefreshDerivedStats(True);
end;

function MilitaryBuff(Nodes: Integer): Boolean;
begin
  SubmitInt(ckMilitaryBuff, Nodes);
  Result := TalkOutcome <> 0;
end;

initialization
  RegisterCommand(ckBeginTalk, 'BeginTalk', @ExecuteBeginTalk);
  RegisterCommand(ckResetScriptDialog, 'ResetScriptDialog', @ExecuteResetScriptDialog);
  RegisterCommand(ckEnterTalk, 'EnterTalk', @ExecuteEnterTalk);
  RegisterCommand(ckLeaveTalk, 'LeaveTalk', @ExecuteLeaveTalk);
  RegisterCommand(ckEndTalk, 'EndTalk', @ExecuteEndTalk);
  RegisterCommand(ckAcceptScriptedTalk, 'AcceptScriptedTalk', @ExecuteAcceptScriptedTalk);
  RegisterCommand(ckClearTalkDialogRules, 'ClearTalkDialogRules', @ExecuteClearTalkDialogRules);
  RegisterCommand(ckTalkScriptMessage, 'TalkScriptMessage', @ExecuteTalkScriptMessage);
  RegisterCommand(ckTalkShipDialog, 'TalkShipDialog', @ExecuteTalkShipDialog);
  RegisterCommand(ckTalkDialogOverride, 'TalkDialogOverride', @ExecuteTalkDialogOverride);
  RegisterCommand(
      ckSortTalkDialogInjections,
      'SortTalkDialogInjections',
      @ExecuteSortTalkDialogInjections
  );
  RegisterCommand(ckCheckTalkCamouflage, 'CheckTalkCamouflage', @ExecuteCheckTalkCamouflage);
  RegisterCommand(ckPublishTalkShipContext, 'PublishTalkShipContext', @ExecutePublishTalkShipContext);
  RegisterCommand(ckTalkShipAuxiliaryCode, 'TalkShipAuxiliaryCode', @ExecuteTalkShipAuxiliaryCode);
  RegisterCommand(ckTalkRecognizesPlayer, 'TalkRecognizesPlayer', @ExecuteTalkRecognizesPlayer);
  RegisterCommand(ckRunInjectedAnswerAction, 'RunInjectedAnswerAction', @ExecuteRunInjectedAnswerAction);
  RegisterCommand(ckCallInjectedDialog, 'CallInjectedDialog', @ExecuteCallInjectedDialog);
  RegisterCommand(ckShowMoneyDemand, 'ShowMoneyDemand', @ExecuteShowMoneyDemand);
  RegisterCommand(ckDemandMoney, 'DemandMoney', @ExecuteDemandMoney);
  RegisterCommand(ckDemandCargo, 'DemandCargo', @ExecuteDemandCargo);
  RegisterCommand(ckShowTruceOffer, 'ShowTruceOffer', @ExecuteShowTruceOffer);
  RegisterCommand(ckAcceptTruceOffer, 'AcceptTruceOffer', @ExecuteAcceptTruceOffer);
  RegisterCommand(ckShowAttackTargets, 'ShowAttackTargets', @ExecuteShowAttackTargets);
  RegisterCommand(ckRequestAttackTarget, 'RequestAttackTarget', @ExecuteRequestAttackTarget);
  RegisterCommand(ckAcceptJointAttack, 'AcceptJointAttack', @ExecuteAcceptJointAttack);
  RegisterCommand(ckRequestProtection, 'RequestProtection', @ExecuteRequestProtection);
  RegisterCommand(ckRequestPreserveItems, 'RequestPreserveItems', @ExecuteRequestPreserveItems);
  RegisterCommand(ckAcceptPartnerOffer, 'AcceptPartnerOffer', @ExecuteAcceptPartnerOffer);
  RegisterCommand(
      ckAcceptPiratePartnerOffer,
      'AcceptPiratePartnerOffer',
      @ExecuteAcceptPiratePartnerOffer
  );
  RegisterCommand(ckOrderTalkShipFollow, 'OrderTalkShipFollow', @ExecuteOrderTalkShipFollow);
  RegisterCommand(ckOrderTalkShipLand, 'OrderTalkShipLand', @ExecuteOrderTalkShipLand);
  RegisterCommand(ckOrderTalkShipJump, 'OrderTalkShipJump', @ExecuteOrderTalkShipJump);
  RegisterCommand(ckOrderPartnerDropCargo, 'OrderPartnerDropCargo', @ExecuteOrderPartnerDropCargo);
  RegisterCommand(ckGivePartnerGift, 'GivePartnerGift', @ExecuteGivePartnerGift);
  RegisterCommand(ckGivePiratePartnerGift, 'GivePiratePartnerGift', @ExecuteGivePiratePartnerGift);
  RegisterCommand(ckApplyOrderToAllPartners, 'ApplyOrderToAllPartners', @ExecuteApplyOrderToAllPartners);
  RegisterCommand(
      ckOrderPiratePartnerAttack,
      'OrderPiratePartnerAttack',
      @ExecuteOrderPiratePartnerAttack
  );
  RegisterCommand(ckDismissPartner, 'DismissPartner', @ExecuteDismissPartner);
  RegisterCommand(ckOffendOverOldHull, 'OffendOverOldHull', @ExecuteOffendOverOldHull);
  RegisterCommand(ckOrderTranclucatorFollow, 'OrderTranclucatorFollow', @ExecuteOrderTranclucatorFollow);
  RegisterCommand(ckOrderTranclucatorReturn, 'OrderTranclucatorReturn', @ExecuteOrderTranclucatorReturn);
  RegisterCommand(
      ckOrderTranclucatorSeekItems,
      'OrderTranclucatorSeekItems',
      @ExecuteOrderTranclucatorSeekItems
  );
  RegisterCommand(
      ckCancelTranclucatorSeekItems,
      'CancelTranclucatorSeekItems',
      @ExecuteCancelTranclucatorSeekItems
  );
  RegisterCommand(ckSetTranclucatorOptions, 'SetTranclucatorOptions', @ExecuteSetTranclucatorOptions);
  RegisterCommand(
      ckOrderTranclucatorDropCargo,
      'OrderTranclucatorDropCargo',
      @ExecuteOrderTranclucatorDropCargo
  );
  RegisterCommand(ckOrderTranclucatorLand, 'OrderTranclucatorLand', @ExecuteOrderTranclucatorLand);
  RegisterCommand(
      ckOrderTranclucatorStoreCargo,
      'OrderTranclucatorStoreCargo',
      @ExecuteOrderTranclucatorStoreCargo
  );
  RegisterCommand(
      ckApplyOrderToAllTranclucators,
      'ApplyOrderToAllTranclucators',
      @ExecuteApplyOrderToAllTranclucators
  );
  RegisterCommand(ckRunDominatorProgram, 'RunDominatorProgram', @ExecuteRunDominatorProgram);
  RegisterCommand(ckMilitaryHullRepair, 'MilitaryHullRepair', @ExecuteMilitaryHullRepair);
  RegisterCommand(ckMilitaryEquipmentRepair, 'MilitaryEquipmentRepair', @ExecuteMilitaryEquipmentRepair);
  RegisterCommand(ckSellAllMilitaryRemains, 'SellAllMilitaryRemains', @ExecuteSellAllMilitaryRemains);
  RegisterCommand(ckSellMilitaryRemains, 'SellMilitaryRemains', @ExecuteSellMilitaryRemains);
  RegisterCommand(ckMilitaryBuff, 'MilitaryBuff', @ExecuteMilitaryBuff);
end.
