{$EXCESSPRECISION OFF}
unit aPlanetActions;

// CHANGE: ENHANCEMENT - What a human does on a planet, as commands (docs/commands.md): the
// planet screens (fPlanet, fPlanetNO), the government (fGov), the information and journal
// screens (fInfo, fJournal), the day's end on the main panel and the results of a planetary
// battle. The code is moved from the screens; they keep their text, choices, sounds,
// achievements and images. A command that decides for itself returns its branch in
// PlanetOutcome and the text the game built in PlanetText.
//
// The government's negotiation state is not in the screen, so a replay has it, and it is
// each human's (THuman): the planet scripts whose dialogs it walks through
// (GovernmentDialogNames) and the quest being negotiated (GovernmentQuestOffer). So is the
// satellite the human holds on the uninhabited planet's cursor (PlanetHeldSatellite), which
// is in neither the hold nor the deployed satellites while it is held.
interface
uses
  EC_Str,
  aCommands,
  aGalaxy,
  aItem,
  aRanger,
  aScript,
  aShip;
const
  // Command kinds 400-499 (see TCommandKind).
  ckRunGlobalScripts = 400;
  ckPlanetCaptured = 401;
  ckEnterGovernment = 402;
  ckLeaveGovernment = 403;
  ckRefreshGovernment = 404;
  ckBeginGovernmentDialog = 405;
  ckContinueGovernmentDialog = 406;
  ckGovernmentDialogOverride = 407;
  ckGovernmentInjectedDialog = 408;
  ckEnterPrison = 410;
  ckChoosePrison = 411;
  ckPayBribe = 412;
  ckBuyMap = 413;
  ckPayPrisonBail = 414;
  ckRequestQuest = 420;
  ckNegotiateQuest = 421;
  ckAcceptQuest = 422;
  ckDeclineQuestPermanently = 423;
  ckRecordPlanetBattle = 430;
  ckDeclineAllPlanetBattles = 431;
  ckPlanetBattleResult = 432;
  ckFinishTerronBattle = 433;
  ckRefreshPlayerStats = 440;
  ckArrangeSatellites = 441;
  ckSatelliteSlot = 442;
  ckSatelliteOrbit = 443;
  ckReturnHeldSatellite = 444;
  ckPickUpSurfaceLoot = 445;
  ckPayInfoSearch = 450;
  ckMarkShipSeen = 451;
  ckAddJournalRecord = 460;
  ckDeleteJournalRecord = 461;
  ckClearJournal = 462;
  ckClearNews = 463;
const
  // RefreshGovernment outcomes.
  grPrisonReleased = 0;
  grHostile = 1;
  grLiberation = 2;
  grGreeting = 3;
  // BeginGovernmentDialog outcomes when a planet script's dialog opens.
  gdContinue = 0;
  gdShowMessage = 1;
  // RequestQuest outcomes.
  rqPlanetBattle = 0;
  rqRefused = 1;
  rqOffer = 2;
  // RecordPlanetBattle flags.
  pbSetLastTurn = 1;
  pbCountBattle = 2;
  // ArrangeSatellites flags, applied in this order.
  saRepairDuplicates = 1;
  saCompact = 2;
  saAssignFromHold = 4;
  // SatelliteSlot outcomes.
  ssNone = 0;
  ssTaken = 1;
  ssPut = 2;
  // SatelliteOrbit outcomes.
  soNone = 0;
  soPut = 1;
  soTaken = 2;
var
  // What the last command decided, the amount it worked out and the text the game built.
  PlanetOutcome: Integer;
  PlanetAmount: Integer;
  PlanetText: WideString;
  // The government: the script the last dialog command selected, and whether
  // BeginGovernmentDialog turned a quest in (PlanetText then holds the answer). The
  // negotiation state that lasts between commands is the human's (THuman).
  GovernmentScript: TScript;
  GovernmentQuestTurnedIn: Boolean;
  // The planetary battle the government offers (RequestQuest).
  GovernmentBattleMapId: Integer;
  // The experience GrantPlanetQuestReward awarded (PlanetBattleResult).
  PlanetBattleExperience: Integer;

// The global scripts for Star, as a screen runs them when the player lands (RunFrom 0).
procedure RunGlobalScripts(Star: TStar; RunFrom: Integer);
// The dominators capture the planet the local human is on. Single player loses the game.
// CHANGE: ENHANCEMENT - In multiplayer the captured human respawns like any destroyed human
// instead (ROADMAP.md, Phase 6, item 14; ApplyPlanetCaptured). Returns whether the game ended
// for the local human, so the caller still shows game end only then.
function ReportPlanetCaptured: Boolean;

// The government screen.
// Forgets that the government asked to see the player on docking.
procedure EnterGovernment;
procedure LeaveGovernment;
// What the government says first; HasPendingRequests is whether scripts wait for the UI.
function RefreshGovernment(HasPendingRequests: Boolean): Integer;
// The planet's script dialogs: clears the dialog rules, looks for the first script with a
// dialog and turns quests in. Leaves the script in GovernmentScript.
procedure BeginGovernmentDialog;
procedure ContinueGovernmentDialog;
// Applies the dialog override with the highest priority; returns its script.
function ApplyGovernmentDialogOverride: TScript;
// Opens the dialog an injected answer leads to; returns whether it has a message.
function RunGovernmentInjectedDialog(Injection: PScriptDialogInjection): Boolean;
procedure EnterPrison;
// Takes prison instead of the planetary battle.
procedure ChoosePrison;
// Returns the bribe paid.
function PayBribe: Integer;
// Constellation is the map the screen offered.
procedure BuyMap(Constellation: TConstellation);
// Returns whether Ship was released.
function PayPrisonBail(Ship: TShip): Boolean;
// Returns an rq outcome; a refusal leaves the answer in PlanetText.
function RequestQuest: Integer;
// Direction -1 makes the offer easier, 1 harder.
procedure NegotiateQuest(Direction: Integer);
procedure AcceptQuest;
procedure DeclineQuestPermanently;

// Planetary battles. Statistics are what the battle reported (RobotBattleStatistics).
type
  TPlanetBattleStatistics = array[0..5] of Integer;
procedure RecordPlanetBattle(
    MapId, ResultCode, CompletionMode, Flags: Integer;
    const Statistics: TPlanetBattleStatistics
);
procedure DeclineAllPlanetBattles;
// The government's reward or reaction after a battle that ended with Mode (2 lost, 3 won,
// 4 cancelled). Returns the money paid; PlanetText holds the reward text of a win.
function ApplyPlanetBattleResult(Mode, Difficulty, MapId: Integer): Integer;
// The end of the battle for a planet that Terron's landing started (fStarMap).
procedure FinishTerronBattle(Mode, MapId: Integer; const Statistics: TPlanetBattleStatistics);

// The uninhabited planet.
procedure RefreshPlayerStats;
procedure ArrangeSatellites(Flags: Integer);
// A click on the satellite inventory's slot for TrajectoryIndex; returns an ss outcome.
function ClickSatelliteSlot(TrajectoryIndex: Integer): Integer;
// A click on the orbit TrajectoryIndex; returns an so outcome.
function ClickSatelliteOrbit(TrajectoryIndex: Integer): Integer;
// Puts the held satellite back; returns where it came from.
function ReturnHeldSatellite: Integer;
procedure PickUpSurfaceLoot(EntryIndex: Integer; Item: TItem);

// The information screen charges for a search that found something.
procedure PayInfoSearch;
// The information screen shows where Ship is.
procedure MarkShipSeen(Ship: TShip);

// The journal.
procedure AddJournalRecord(const Text: WideString);
procedure DeleteJournalRecord(Index: Integer);
procedure ClearJournal;
procedure ClearNews;
implementation
uses
  Classes,
  SysUtils,
  Math,
  GR_Main,
  Globals,
  aConst,
  aGalaxyEvent,
  aGalaxyStruct,
  aHuman,
  aKling,
  aMyFunction,
  aNormalShip,
  aPirate,
  aPlanet,
  aPlayer,
  aSession,
  aTranclucator;

procedure AddScript(var Command: TPlayerCommand; Script: TScript);
begin
  if Script = nil then
    AddInt(Command, -1)
  else
    AddInt(Command, Galaxy.Scripts.IndexOf(Script));
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

{ Landing }

// Moved from TfPlanet.OnOpen and TfGov.OnOpen.
procedure ExecuteRunGlobalScripts(const Command: TPlayerCommand);
begin
  RunGlobalScriptsForContext(
      RefObject(Command, 0) as TStar,
      IntArg(Command, 0),
      ActorHuman(Command)
  );
end;

procedure RunGlobalScripts(Star: TStar; RunFrom: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckRunGlobalScripts);
  AddRef(Command, Star);
  AddInt(Command, RunFrom);
  SubmitCommand(Command);
end;

// Moved from TfPlanet.OnOpen, TfGov.OnOpen and TfPanelMain.EndTurnClicked. This is a human
// being captured: the actor is whoever docked or landed on ground that fell to the
// dominators, named by the PlanetCaptured PlayerDeath event, as RecordHumanDeath names a
// destroyed ranger's human. In multiplayer that human respawns like any destroyed one
// (ROADMAP.md, Phase 6, item 14) instead of ending the game for everyone; single player is
// unchanged, since ActingHuman is the one player and always has nowhere better to go than
// game over. Returns whether the game ended for the captured human.
function ApplyPlanetCaptured: Boolean;
var
  Event: TGalaxyEvent;
  CapturedHuman: THuman;
  RespawnPlanet: TPlanet;
begin
  Result := True;
  CapturedHuman := ActingHuman;
  Event := AddGalaxyEvent('PlayerDeath');
  Event.AddTextData('PlanetCaptured');
  if CapturedHuman <> nil then
    Event.HumanId := CapturedHuman.Id;
  if IsMultiplayer and (CapturedHuman <> nil) and (CapturedHuman.Player <> nil) then
  begin
    RespawnPlanet := CapturedHuman.Player.FindRespawnPlanet;
    if RespawnPlanet <> nil then
    begin
      CapturedHuman.Player.RespawnHuman(RespawnPlanet);
      Result := False;
      Exit;
    end;
  end;
  Session.GameEndReason := 2;
end;

procedure ExecutePlanetCaptured(const Command: TPlayerCommand);
begin
  PlanetOutcome := Ord(ApplyPlanetCaptured);
end;

function ReportPlanetCaptured: Boolean;
begin
  // With no player there is no one to act; this runs unrecorded, and the log's next
  // boundary writes a checkpoint.
  if LocalPlayer = nil then
    Result := ApplyPlanetCaptured
  else
  begin
    SubmitSimple(ckPlanetCaptured);
    Result := PlanetOutcome <> 0;
  end;
end;

{ The government }

// Moved from TfGov.OnOpen.
procedure ExecuteEnterGovernment(const Command: TPlayerCommand);
begin
  if Actor(Command).PendingDockDialogue = 1 then
    Actor(Command).PendingDockDialogue := 0;
end;

procedure EnterGovernment;
begin
  SubmitSimple(ckEnterGovernment);
end;

// Moved from TfGov.OnClose.
procedure ExecuteLeaveGovernment(const Command: TPlayerCommand);
begin
  Actor(Command).ScriptItemsAct($19, nil, nil, 0);
  Session.ScriptDialogIndex := -1;
  ActorHuman(Command).GovernmentDialogNames.Clear;
end;

procedure LeaveGovernment;
begin
  if LocalPlayer = nil then
  begin
    Session.ScriptDialogIndex := -1;
    LocalHuman.GovernmentDialogNames.Clear;
  end
  else
    SubmitSimple(ckLeaveGovernment);
end;

// Moved from TfGov.RefreshGovernmentDialog.
procedure ExecuteRefreshGovernment(const Command: TPlayerCommand);
var
  I, J: Integer;
  Planet: TPlanet;
  Ship: TShip;
  P: TPlayer;
begin
  P := Actor(Command);
  PlanetText := '';
  if P.InPrison then
  begin
    P.InPrison := False;
    Inc(P.PrisonStaysCompleted);
    for I := 0 to Galaxy.Planets.Count - 1 do
    begin
      Planet := Galaxy.Planets[I];
      for J := 0 to Planet.Warriors.Count - 1 do
      begin
        Ship := Planet.Warriors[J];
        if P = Ship.EnemyShip then
          Ship.EnemyShip := nil;
        if P.EnemyShip = Ship then
          P.EnemyShip := nil;
      end;
    end;
    PlanetOutcome := grPrisonReleased;
  end
  else if (P.CurrentPlanet.GetRelationLevelToShip(P) = rlHostile)
      and (IntArg(Command, 0) = 0)
      and not P.CurrentPlanet.IsMainPiratePlanet then
    PlanetOutcome := grHostile
  else if P.PendingLiberationCeremonyPlanet = P.CurrentPlanet then
  begin
    PlanetText := TNormalShip(P).CollectLiberationRewards;
    PlanetOutcome := grLiberation;
  end
  else
    PlanetOutcome := grGreeting;
end;

function RefreshGovernment(HasPendingRequests: Boolean): Integer;
begin
  SubmitInt(ckRefreshGovernment, Ord(HasPendingRequests));
  Result := PlanetOutcome;
end;

// Moved from TfGov.BuildGovernmentChoices.
procedure ExecuteBeginGovernmentDialog(const Command: TPlayerCommand);
var
  H: THuman;
  Script: TScript;
  Text: WideString;
begin
  H := ActorHuman(Command);
  ClearScriptDialogRules;
  Actor(Command).CurrentPlanet.CollectScriptDialogChoices(H.GovernmentDialogNames);
  H.GovernmentDialogCursor := 0;
  Script := nil;
  Session.ScriptDialogIndex := -1;
  while H.GovernmentDialogCursor < H.GovernmentDialogNames.GetCount do
  begin
    Script := TScript(H.GovernmentDialogNames.GetDataAt(H.GovernmentDialogCursor));
    Script.CallDialogByVariable(H.GovernmentDialogNames.GetTextAt(H.GovernmentDialogCursor));
    if Session.ScriptDialogIndex >= 0 then
      Break;
    Inc(H.GovernmentDialogCursor);
  end;
  GovernmentQuestTurnedIn := Actor(Command).TryTurnInAnyQuest(Text);
  PlanetText := Text;
  GovernmentScript := Script;
  PlanetOutcome := gdContinue;
  if Session.ScriptDialogIndex >= 0 then
    if Script.SkipGreeting then
    begin
      Script.SkipGreeting := False;
      PlanetOutcome := gdShowMessage;
    end;
end;

procedure BeginGovernmentDialog;
begin
  SubmitSimple(ckBeginGovernmentDialog);
end;

// Moved from TfGov.ContinueScriptDialog.
procedure ExecuteContinueGovernmentDialog(const Command: TPlayerCommand);
var
  H: THuman;
  Script: TScript;
begin
  H := ActorHuman(Command);
  Session.ScriptDialogIndex := -1;
  Inc(H.GovernmentDialogCursor);
  Script := nil;
  while H.GovernmentDialogCursor < H.GovernmentDialogNames.GetCount do
  begin
    Script := H.GovernmentDialogNames.GetDataAt(H.GovernmentDialogCursor);
    Script.CallDialogByVariable(H.GovernmentDialogNames.GetTextAt(H.GovernmentDialogCursor));
    if Session.ScriptDialogIndex >= 0 then
      Break;
    Inc(H.GovernmentDialogCursor);
  end;
  GovernmentScript := Script;
end;

procedure ContinueGovernmentDialog;
begin
  SubmitSimple(ckContinueGovernmentDialog);
end;

// Moved from TfGov.BuildGovernmentChoices.
procedure ExecuteGovernmentDialogOverride(const Command: TPlayerCommand);
var
  Script: TScript;
  Text: WideString;
  I, Selected, Priority: Integer;
begin
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
  GovernmentScript := Script;
end;

function ApplyGovernmentDialogOverride: TScript;
begin
  SubmitSimple(ckGovernmentDialogOverride);
  Result := GovernmentScript;
end;

// Moved from TfGov.RunInjectedAnswer: the dialog the answer leads to, and its message.
procedure ExecuteGovernmentInjectedDialog(const Command: TPlayerCommand);
var
  Index: Integer;
  Injection: PScriptDialogInjection;
begin
  Index := IntArg(Command, 0);
  if (ScriptDialogInjections = nil) or (Index < 0) or (Index >= ScriptDialogInjections.Count) then
    raise Exception.Create(CommandKindName(Command.Kind) + ' names a missing dialog injection');
  Injection := PScriptDialogInjection(ScriptDialogInjections[Index]);
  CurrentScript := Injection.Script;
  CurrentScript.InitCode.LocalVar.GetVar('GAnswerData').SetDword(Injection.AnswerData);
  Session.ScriptDialogIndex := -1;
  CurrentScript.CallDialogByVariable(Injection.DialogName);
  if Session.ScriptDialogIndex < 0 then
    PlanetOutcome := 0
  else
  begin
    PlanetOutcome := 1;
    CurrentScript.CallDialogMessage(Session.ScriptDialogIndex);
  end;
end;

function RunGovernmentInjectedDialog(Injection: PScriptDialogInjection): Boolean;
begin
  SubmitInt(ckGovernmentInjectedDialog, ScriptDialogInjections.IndexOf(Injection));
  Result := PlanetOutcome <> 0;
end;

// Moved from TfGov.EnterPrison.
procedure ExecuteEnterPrison(const Command: TPlayerCommand);
var
  I: Integer;
  Ship: TShip;
  P: TPlayer;
begin
  P := Actor(Command);
  P.InPrison := True;
  P.CurrentSystemKills.Normal := 0;
  P.CurrentSystemKills.Pirate := 0;
  if P.CurrentPlanet.OwnerId = Byte(oiPirate) then
  begin
    if MainPiratePlanet <> nil then
      MainPiratePlanet.ChangeRelationToRanger(P, 80)
    else
      P.CurrentPlanet.ChangeRelationToRanger(P, 80);
  end
  else
  begin
    P.CurrentPlanet.ChangeRelationToRanger(P, 80);
    P.ChangePlanetRelations(nil, rcmRaiseTo, 20, TOwnerMask(PlanetOwnerMasks.Coalition));
    P.ChangePlanetRelations(
        P.CurrentStar.Constellation,
        rcmIncrease,
        30,
        TOwnerMask(PlanetOwnerMasks.Coalition)
    );
  end;
  for I := 0 to P.CurrentStar.Ships.Count - 1 do
  begin
    Ship := P.CurrentStar.Ships[I];
    if ((Ship.TypeId = stWarrior) or ((Ship.TypeId = stPirate) and (TPirate(Ship).PirateType <> 0)))
        and (P = Ship.EnemyShip) then
    begin
      Ship.EnemyShip := nil;
      if P = Ship.OrderTarget then
        Ship.OrderNone(False);
    end;
  end;
end;

procedure EnterPrison;
begin
  SubmitSimple(ckEnterPrison);
end;

// Moved from TfGov.ChoosePrisonInsteadOfBattle.
procedure ExecuteChoosePrison(const Command: TPlayerCommand);
begin
  Actor(Command).CurrentPlanet.SetRelationLevelToRanger(Actor(Command), rlHostile);
end;

procedure ChoosePrison;
begin
  SubmitSimple(ckChoosePrison);
end;

// Moved from TfGov.PayBribe.
procedure ExecutePayBribe(const Command: TPlayerCommand);
var
  Cost, RelationDeficit: Integer;
  P: TPlayer;
begin
  P := Actor(Command);
  RelationDeficit := 100 - (Integer(P.CurrentPlanet.RelationToShip(P)) and $7F);
  Cost :=
      Round(
          RemapClamped(RelationDeficit, 0, 100, 1, 5)
              * (Galaxy.AverageRangerCapital div 100)
              * OwnerInfo[P.CurrentPlanet.OwnerId].FuelPriceFactor
      );
  P.SetMoney(P.Money - Cost);
  if P.CurrentPlanet.OwnerId = Byte(oiPirate) then
  begin
    if MainPiratePlanet <> nil then
      MainPiratePlanet.ChangeRelationToRanger(P, 100)
    else
      P.CurrentPlanet.ChangeRelationToRanger(P, 100);
  end
  else
  begin
    P.CurrentPlanet.ChangeRelationToRanger(P, 100);
    P.ChangePlanetRelations(
        P.CurrentStar,
        rcmIncrease,
        20,
        TOwnerMask(PlanetOwnerMasks.Coalition)
    );
  end;
  PlanetAmount := Cost;
end;

function PayBribe: Integer;
begin
  SubmitSimple(ckPayBribe);
  Result := PlanetAmount;
end;

// Moved from TfGov.BuyMap.
procedure ExecuteBuyMap(const Command: TPlayerCommand);
var
  Cost: Integer;
  P: TPlayer;
  Constellation: TConstellation;
begin
  P := Actor(Command);
  Cost :=
      RoundAndTruncateToTens(
          Min(
                  P.Wealth div 40,
                  Galaxy.ComputeScaledBigMoney(P.CurrentPlanet.OwnerId))
              + 50
      );
  // CHANGE: BUGFIX - The command names the constellation the screen offered (a log from before
  // names none: the map is the first uncharted neighbour, as it was). The government sells it
  // while it is still an uncharted neighbour, before it takes the money. Between days another
  // human may have bought it: the host charged and revealed the next one, or crashed when none
  // was left (docs/network.md, Commands).
  if Length(Command.Refs) > 0 then
  begin
    Constellation := RefObject(Command, 0) as TConstellation;
    if (Constellation = nil)
        or Constellation.Visible
        or (Constellation.Id = 20)
        or not Constellation.SharesOutlineSegment(P.CurrentPlanet.CurrentStar.Constellation) then
      raise ECommandRefused.CreateReason(rrOfferGone, 'BuyMap: the constellation is charted');
  end
  else
  begin
    Constellation := P.CurrentPlanet.FindUnchartedNeighborConstellation;
    if Constellation = nil then
      raise ECommandRefused.CreateReason(rrOfferGone, 'BuyMap: no uncharted neighbour');
  end;
  if P.Money < Cost then
    raise ECommandRefused.CreateReason(rrNoMoney, 'BuyMap: not enough money');
  P.SetMoney(P.Money - Cost);
  Constellation.Visible := True;
  P.AchievementStats.CheckMapBuilderAchievement;
end;

procedure BuyMap(Constellation: TConstellation);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckBuyMap);
  AddRef(Command, Constellation);
  SubmitCommand(Command);
end;

// Preserve the native receiver evaluation before the bounded payment,
// with the clamp cells allocated before the receiver cell.
// Moved from fGov.
procedure PayBailMoney(Player: TPlayer; Ship: TShip); inline;
var
  Remaining, Payment: Integer;
begin
  Remaining := Player.Money - Ship.GetPrisonReleaseCost;
  if Remaining < 0 then
    Payment := 0
  else
    Payment := Remaining;
  Player.SetMoney(Payment);
end;

// Moved from TfGov.PayPrisonBail.
procedure ExecutePayPrisonBail(const Command: TPlayerCommand);
var
  Ship: TShip;
  P: TPlayer;
begin
  P := Actor(Command);
  Ship := RefObject(Command, 0) as TShip;
  PlanetOutcome := 0;
  if Ship.IsInPrison then
  begin
    PayBailMoney(P, Ship);
    Ship.ClearPrisonTerm;
    Ship.ChangeRelationToRanger(P, 100);
    Ship.OrderTakeoff;
    Inc(P.AchievementStats.PrisonersBailedOut);
    PlanetOutcome := 1;
  end;
end;

function PayPrisonBail(Ship: TShip): Boolean;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckPayPrisonBail);
  AddRef(Command, Ship);
  SubmitCommand(Command);
  Result := PlanetOutcome <> 0;
end;

{ Quests }

// Moved from TfGov.RequestQuest.
procedure ExecuteRequestQuest(const Command: TPlayerCommand);
var
  H: THuman;
  ResponseText: WideString;
  MapId: Integer;
  P: TPlayer;
begin
  H := ActorHuman(Command);
  P := Actor(Command);
  if P.DeclinePlanetBattleOffers then
    MapId := -1
  else
    MapId := P.SelectPlanetBattleMap;
  if (MapId >= 0) and (Session.ForcedPlanetQuestId < 0) then
  begin
    GovernmentBattleMapId := MapId;
    PlanetOutcome := rqPlanetBattle;
  end
  else if not P.GenerateQuestOffer(H.GovernmentQuestOffer, ResponseText) then
  begin
    PlanetText := ResponseText;
    PlanetOutcome := rqRefused;
  end
  else
  begin
    H.GovernmentQuestLevel := 0;
    H.GovernmentQuestRewardStep := Round(H.GovernmentQuestOffer.RewardMoney * 0.3);
    H.GovernmentQuestDurationStep :=
        Round((H.GovernmentQuestOffer.DeadlineTurn - Galaxy.CurrentTurn) * 0.5);
    PlanetOutcome := rqOffer;
  end;
end;

function RequestQuest: Integer;
begin
  SubmitSimple(ckRequestQuest);
  Result := PlanetOutcome;
end;

// Moved from TfGov.MakeQuestEasier and TfGov.MakeQuestHarder.
procedure ExecuteNegotiateQuest(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  if IntArg(Command, 0) < 0 then
  begin
    Dec(H.GovernmentQuestLevel);
    case H.GovernmentQuestOffer.QuestType of
      qtSendLetter..qtPlanetQuest:
        Inc(H.GovernmentQuestOffer.DeadlineTurn, H.GovernmentQuestDurationStep);
      qtDefendSystem..qtDefendShip:
        Dec(H.GovernmentQuestOffer.DeadlineTurn, H.GovernmentQuestDurationStep);
    end;
    Dec(H.GovernmentQuestOffer.RewardMoney, H.GovernmentQuestRewardStep);
  end
  else
  begin
    Inc(H.GovernmentQuestLevel);
    case H.GovernmentQuestOffer.QuestType of
      qtSendLetter..qtPlanetQuest:
        Dec(H.GovernmentQuestOffer.DeadlineTurn, H.GovernmentQuestDurationStep);
      qtDefendSystem..qtDefendShip:
        Inc(H.GovernmentQuestOffer.DeadlineTurn, H.GovernmentQuestDurationStep);
    end;
    Inc(H.GovernmentQuestOffer.RewardMoney, H.GovernmentQuestRewardStep);
  end;
end;

procedure NegotiateQuest(Direction: Integer);
begin
  SubmitInt(ckNegotiateQuest, Direction);
end;

// Moved from TfGov.AcceptQuest.
procedure ExecuteAcceptQuest(const Command: TPlayerCommand);
var
  H: THuman;
  Quest: PQuest;
  Item: TUselessItem;
  P: TPlayer;
begin
  H := ActorHuman(Command);
  P := Actor(Command);
  New(Quest);
  Quest^ := H.GovernmentQuestOffer;
  Quest.Description := P.BuildQuestText(Quest^, qtkOffer);
  Quest.CompletionText := P.BuildQuestText(Quest^, qtkCompletion);
  P.Quests.Add(Quest);
  P.PublishQuestStatus(Quest, 0);
  if Quest.QuestType = qtSendLetter then
  begin
    Item := TUselessItem.Create;
    Item.Init(
        LookupLocalizedTextByKey(
            WideString('Quest.SendLetter.' + IntToStr(Quest.QuestNumber) + '.SysName')
        ),
        dsBlazer,
        0,
        False
    );
    P.Inventory.Add(Item);
  end;
end;

procedure AcceptQuest;
begin
  SubmitSimple(ckAcceptQuest);
end;

// Moved from TfGov.PermanentlyDeclineQuest.
procedure ExecuteDeclineQuestPermanently(const Command: TPlayerCommand);
var
  H: THuman;
  Quest: PPlayerOldQuest;
begin
  H := ActorHuman(Command);
  New(Quest);
  Quest.QuestType := H.GovernmentQuestOffer.QuestType;
  Quest.QuestNumber := H.GovernmentQuestOffer.QuestNumber;
  Quest.Planet := H.GovernmentQuestOffer.Planet;
  Quest.Description := 'PlanetQuestClose';
  Quest.Successful := False;
  Quest.Declined := True;
  H.PlayerOldQuests.Add(Quest);
end;

procedure DeclineQuestPermanently;
begin
  SubmitSimple(ckDeclineQuestPermanently);
end;

{ Planetary battles }

procedure AddStatistics(var Command: TPlayerCommand; const Statistics: TPlanetBattleStatistics);
var
  I: Integer;
begin
  for I := 0 to 5 do
    AddInt(Command, Statistics[I]);
end;

procedure AddPlanetBattleHistory(
    P: TPlayer;
    const Command: TPlayerCommand;
    StatisticsIndex, MapIdValue, ResultCodeValue, CompletionModeValue: Integer
);
begin
  SetLength(P.PlanetBattleHistory, High(P.PlanetBattleHistory) + 1 + 1);
  with P.PlanetBattleHistory[High(P.PlanetBattleHistory)] do
  begin
    MapId := MapIdValue;
    Statistics[0] := IntArg(Command, StatisticsIndex);
    Statistics[1] := IntArg(Command, StatisticsIndex + 1);
    Statistics[2] := IntArg(Command, StatisticsIndex + 2);
    Statistics[3] := IntArg(Command, StatisticsIndex + 3);
    Statistics[4] := IntArg(Command, StatisticsIndex + 4);
    Statistics[5] := IntArg(Command, StatisticsIndex + 5);
    ResultCode := ResultCodeValue;
    CompletionMode := CompletionModeValue;
    DateTurn := Galaxy.CurrentTurn;
  end;
end;

// Moved from TfGov.OnOpen and TfGov.DeclinePlanetBattle.
procedure ExecuteRecordPlanetBattle(const Command: TPlayerCommand);
var
  P: TPlayer;
  Flags: Integer;
begin
  P := Actor(Command);
  Flags := IntArg(Command, 3);
  AddPlanetBattleHistory(P, Command, 4, IntArg(Command, 0), IntArg(Command, 1), IntArg(Command, 2));
  if (Flags and pbSetLastTurn) <> 0 then
    P.LastPlanetBattleTurn := Galaxy.CurrentTurn;
  if (Flags and pbCountBattle) <> 0 then
    Inc(P.PlanetBattles);
end;

procedure RecordPlanetBattle(
    MapId, ResultCode, CompletionMode, Flags: Integer;
    const Statistics: TPlanetBattleStatistics
);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckRecordPlanetBattle);
  AddInt(Command, MapId);
  AddInt(Command, ResultCode);
  AddInt(Command, CompletionMode);
  AddInt(Command, Flags);
  AddStatistics(Command, Statistics);
  SubmitCommand(Command);
end;

// Moved from TfGov.DeclineAllPlanetBattles.
procedure ExecuteDeclineAllPlanetBattles(const Command: TPlayerCommand);
begin
  Actor(Command).DeclinePlanetBattleOffers := True;
end;

procedure DeclineAllPlanetBattles;
begin
  SubmitSimple(ckDeclineAllPlanetBattles);
end;

// Moved from TfGov.OnOpen.
procedure ExecutePlanetBattleResult(const Command: TPlayerCommand);
var
  Money, Mode, Difficulty, MapId, ExperienceAwarded: Integer;
  Event: TGalaxyEvent;
  P: TPlayer;
begin
  P := Actor(Command);
  Mode := IntArg(Command, 0);
  Difficulty := IntArg(Command, 1);
  MapId := IntArg(Command, 2);
  Money := 0;
  PlanetText := '';
  PlanetBattleExperience := 0;
  if Mode = 2 then
  begin
    Money :=
        RoundAndTruncateToTens(
            Min(
                P.Wealth * 0.03,
                Min(
                    Galaxy.ComputeScaledAverageMoney(2) * 7,
                    Galaxy.ComputeScaledHugeMoney(2) * 1.5
                )
            )
        );
    Money := Round(Money * GalaxyDifficultyTuning[Galaxy.DifficultyLevels[5]].ArcadeRewardScale);
    case Difficulty of
      1: Money := RoundAndTruncateToTens(Money * 0.5);
      2: Money := RoundAndTruncateToTens(Money * 0.2);
      3: Money := RoundAndTruncateToTens(Money * 0.1);
    end;
    P.SetMoney(P.Money + Money);
    P.CurrentPlanet.ChangeRelationToRanger(P, -40);
  end
  else if Mode = 3 then
  begin
    Money := RoundAndTruncateToTens(Max(P.Wealth * 0.03, Galaxy.ComputeScaledBigMoney(2)));
    Money := Round(Money * GalaxyDifficultyTuning[Galaxy.DifficultyLevels[5]].QuestMoneyFactor);
    if P.IsHealthEffectActive(23) then
      Money :=
          Round(
              SeededRandomFloatRange(
                      (Integer(P.CurrentPlanet.GenerationSeed) + Galaxy.CurrentTurn)
                          div 33,
                      1.3,
                      2.3)
                  * Money
          );
    Inc(
        Money,
        Round(Money * (Integer(P.GetEffectiveSkillLevel(psCharisma)) and $7F) * 0.1)
    );
    case Difficulty of
      1: Money := RoundAndTruncateToTens(Money * 4.0);
      2: Money := RoundAndTruncateToTens(Money * 1.6);
      3: Money := RoundAndTruncateToTens(Money * 0.8);
    end;
    P.SetMoney(P.Money + Money);
    PlanetText := P.GrantPlanetQuestReward(Difficulty, ExperienceAwarded);
    PlanetBattleExperience := ExperienceAwarded;
    Event := AddGalaxyEvent('PlayerFinishesPlanetaryBattle');
    Event.AddData(MapId);
    Event.AddData(Money);
    Event.AddData(ExperienceAwarded);
  end
  else if Mode = 4 then
    P.CurrentPlanet.SetRelationLevelToRanger(P, rlBad);
  PlanetAmount := Money;
end;

function ApplyPlanetBattleResult(Mode, Difficulty, MapId: Integer): Integer;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckPlanetBattleResult);
  AddInt(Command, Mode);
  AddInt(Command, Difficulty);
  AddInt(Command, MapId);
  SubmitCommand(Command);
  Result := PlanetAmount;
end;

// Moved from TfStarMap.OnOpen.
procedure ExecuteFinishTerronBattle(const Command: TPlayerCommand);
var
  Mode: Integer;
  P: TPlayer;
begin
  P := Actor(Command);
  Mode := IntArg(Command, 0);
  AddPlanetBattleHistory(P, Command, 2, IntArg(Command, 1), 1, Mode);
  if Mode = 3 then
  begin
    Inc(P.PlanetBattles);
    if TerronShip <> nil then
      TerronShip.DestroyQueued := True;
  end
  else
    Galaxy.TerronLandingLockTurn := 0;
  P.OrderTakeoff;
  ActorHuman(Command).PlayerStar.RefreshSpaceObjectPositions;
  // How dominators look follows the local human's health effect: presentation.
  if (LocalPlayer <> nil) and LocalPlayer.IsHealthEffectActive(3) then
    Galaxy.EnableDominatorSurfaces
  else
    Galaxy.DisableDominatorSurfaces;
end;

procedure FinishTerronBattle(Mode, MapId: Integer; const Statistics: TPlanetBattleStatistics);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckFinishTerronBattle);
  AddInt(Command, Mode);
  AddInt(Command, MapId);
  AddStatistics(Command, Statistics);
  SubmitCommand(Command);
end;

{ The uninhabited planet }

// Moved from TfPlanetNO.TakeoffClicked.
procedure ExecuteRefreshPlayerStats(const Command: TPlayerCommand);
begin
  Actor(Command).RefreshDerivedStats(True);
end;

procedure RefreshPlayerStats;
begin
  SubmitSimple(ckRefreshPlayerStats);
end;

// Moved from TfPlanetNO.OpenResearchPanel, ShipClicked and RefreshResearchPanel.
procedure ExecuteArrangeSatellites(const Command: TPlayerCommand);
var
  Flags: Integer;
begin
  Flags := IntArg(Command, 0);
  if (Flags and saRepairDuplicates) <> 0 then
    Actor(Command).RepairDuplicateSatelliteTrajectoryIndices;
  if (Flags and saCompact) <> 0 then
    Actor(Command).CompactSatelliteTrajectoryIndices;
  if (Flags and saAssignFromHold) <> 0 then
    Actor(Command).AssignSatelliteIndicesFromHoldOrder;
end;

procedure ArrangeSatellites(Flags: Integer);
begin
  SubmitInt(ckArrangeSatellites, Flags);
end;

// Moved from TfPlanetNO.SatelliteInventoryMouseDown.
procedure ExecuteSatelliteSlot(const Command: TPlayerCommand);
var
  H: THuman;
  Item: TSatellite;
  TrajectoryIndex: Integer;
  P: TPlayer;
begin
  H := ActorHuman(Command);
  P := Actor(Command);
  TrajectoryIndex := IntArg(Command, 0);
  Item := P.FindSatelliteByTrajectoryIndex(TrajectoryIndex);
  PlanetOutcome := ssNone;
  if (H.PlanetHeldSatellite = nil) and (Item <> nil) then
  begin
    H.PlanetHeldSatellite := Item;
    H.PlanetHeldSatelliteOrigin := 0;
    P.Inventory.Delete(P.Inventory.IndexOf(Item));
    P.RefreshDerivedStats(True);
    PlanetOutcome := ssTaken;
  end
  else if H.PlanetHeldSatellite <> nil then
  begin
    if Item <> nil then
      P.InsertSatelliteTrajectoryIndex(TrajectoryIndex);
    P.Inventory.Add(H.PlanetHeldSatellite);
    (TObject(H.PlanetHeldSatellite) as TSatellite).TrajectoryIndex := TrajectoryIndex;
    (TObject(H.PlanetHeldSatellite) as TSatellite).TargetPlanet := nil;
    H.PlanetHeldSatellite := nil;
    P.RefreshDerivedStats(True);
    P.RemoveEmptySatelliteTrajectoryIndex(TrajectoryIndex + 1);
    P.ArrangeHoldSatellitesByTrajectoryIndex;
    PlanetOutcome := ssPut;
  end;
end;

function ClickSatelliteSlot(TrajectoryIndex: Integer): Integer;
begin
  SubmitInt(ckSatelliteSlot, TrajectoryIndex);
  Result := PlanetOutcome;
end;

// Moved from TfPlanetNO.FindDeployedSatellite.
function FindDeployedSatellite(P: TPlayer; TrajectoryIndex: Integer): TSatellite;
var
  I: Integer;
begin
  if TrajectoryIndex = -1 then
  begin
    Result := nil;
    Exit;
  end;
  for I := 0 to P.Satellites.Count - 1 do
  begin
    Result := TSatellite(P.Satellites[I]);
    if (P.CurrentPlanet = Result.TargetPlanet)
        and (Result.TrajectoryIndex = TrajectoryIndex) then
      Exit;
  end;
  Result := nil;
end;

// Moved from TfPlanetNO.ResearchMapMouseDown.
procedure ExecuteSatelliteOrbit(const Command: TPlayerCommand);
var
  H: THuman;
  Item: TSatellite;
  TrajectoryIndex: Integer;
  P: TPlayer;
begin
  H := ActorHuman(Command);
  P := Actor(Command);
  TrajectoryIndex := IntArg(Command, 0);
  H.PlanetHeldSatelliteOrigin := 1;
  Item := FindDeployedSatellite(P, TrajectoryIndex);
  if Item <> nil then
    P.Satellites.Delete(P.Satellites.IndexOf(Item));
  PlanetOutcome := soNone;
  if H.PlanetHeldSatellite <> nil then
  begin
    PlanetOutcome := soPut;
    P.Satellites.Add(H.PlanetHeldSatellite);
    if Item <> nil then
    begin
      Item.TrajectoryIndex := (TObject(H.PlanetHeldSatellite) as TSatellite).TrajectoryIndex;
      H.PlanetHeldSatelliteOrigin := 0;
    end;
    (TObject(H.PlanetHeldSatellite) as TSatellite).TrajectoryIndex := TrajectoryIndex;
    (TObject(H.PlanetHeldSatellite) as TSatellite).TargetPlanet := P.CurrentPlanet;
    H.PlanetHeldSatellite := nil;
  end
  else if Item <> nil then
    PlanetOutcome := soTaken;
  if Item <> nil then
    H.PlanetHeldSatellite := Item;
end;

function ClickSatelliteOrbit(TrajectoryIndex: Integer): Integer;
begin
  SubmitInt(ckSatelliteOrbit, TrajectoryIndex);
  Result := PlanetOutcome;
end;

// Moved from TfPlanetNO.ReturnHeldSatellite.
procedure ExecuteReturnHeldSatellite(const Command: TPlayerCommand);
var
  H: THuman;
begin
  H := ActorHuman(Command);
  PlanetOutcome := H.PlanetHeldSatelliteOrigin;
  if H.PlanetHeldSatellite = nil then
    Exit;
  if H.PlanetHeldSatelliteOrigin = 0 then
  begin
    Actor(Command).Inventory.Add(H.PlanetHeldSatellite);
    H.PlanetHeldSatellite := nil;
    Actor(Command).RefreshDerivedStats(True);
  end
  else
  begin
    Actor(Command).Satellites.Add(H.PlanetHeldSatellite);
    H.PlanetHeldSatellite := nil;
  end;
end;

function ReturnHeldSatellite: Integer;
begin
  SubmitSimple(ckReturnHeldSatellite);
  Result := PlanetOutcome;
end;

// The surface entry at Planet that holds the item with that id, or -1; Hint is where the
// sender's screen showed it.
function FindSurfaceLoot(Planet: TPlanet; Hint: Integer; Id: Cardinal): Integer;
var
  Entries: TList;
  I: Integer;
begin
  Result := -1;
  if Planet = nil then
    Exit;
  Entries := Planet.SurfaceLootEntries;
  if Entries = nil then
    Exit;
  if (Hint >= 0)
      and (Hint < Entries.Count)
      and (PPlanetSurfaceLootEntry(Entries[Hint]).Item <> nil)
      and (Cardinal(PPlanetSurfaceLootEntry(Entries[Hint]).Item.Id) = Id) then
    Exit(Hint);
  for I := 0 to Entries.Count - 1 do
    if (PPlanetSurfaceLootEntry(Entries[I]).Item <> nil)
        and (Cardinal(PPlanetSurfaceLootEntry(Entries[I]).Item.Id) = Id) then
      Exit(I);
end;

// Moved from TfPlanetNO.ResearchMapMouseDown. The entry is named by its index in the
// planet's list and its item's id.
procedure ExecutePickUpSurfaceLoot(const Command: TPlayerCommand);
var
  I: Integer;
  Entry: PPlanetSurfaceLootEntry;
  P: TPlayer;
begin
  P := Actor(Command);
  // CHANGE: BUGFIX - The item is found by its id; the index is where the sender's screen showed
  // it. Between days another human may have picked up an entry before it, which moved this
  // one, or picked up this one (docs/network.md, Commands).
  I := FindSurfaceLoot(P.CurrentPlanet, IntArg(Command, 0), Cardinal(IntArg(Command, 1)));
  if I < 0 then
    raise ECommandRefused.CreateReason(
        rrItemGone,
        CommandKindName(Command.Kind) + ' names a surface item that is gone'
    );
  Entry := P.CurrentPlanet.SurfaceLootEntries[I];
  if Entry.Item is TArtefactTranclucator then
    (TObject((Entry.Item as TArtefactTranclucator).Ship) as TTranclucator).OwnerShip := P;
  if Entry.Item is TGoods then
  begin
    Inc(
        P.CargoGoods[Ord(Entry.Item.ItemType)].Count,
        (Entry.Item as TGoods).Quantity
    );
    Entry.Item.Free;
  end
  else if Entry.Item is TArtefact then
    P.Artefacts.Add(Entry.Item)
  else
    P.Inventory.Add(Entry.Item);
  P.RefreshDerivedStats(True);
  P.CurrentPlanet.SurfaceLootEntries.Delete(I);
  if P.CurrentPlanet.SurfaceLootEntries.Count <= 0 then
  begin
    P.CurrentPlanet.SurfaceLootEntries.Free;
    P.CurrentPlanet.SurfaceLootEntries := nil;
  end;
  Entry.Item := nil;
  Dispose(Entry);
end;

procedure PickUpSurfaceLoot(EntryIndex: Integer; Item: TItem);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckPickUpSurfaceLoot);
  AddInt(Command, EntryIndex);
  AddInt(Command, Item.Id);
  SubmitCommand(Command);
end;

{ Information and journal }

// Moved from TfInfo.RunSearch.
procedure ExecutePayInfoSearch(const Command: TPlayerCommand);
begin
  Actor(Command).SetMoney(Actor(Command).Money - 3);
end;

procedure PayInfoSearch;
begin
  SubmitSimple(ckPayInfoSearch);
end;

// Moved from TfInfo.
procedure ExecuteMarkShipSeen(const Command: TPlayerCommand);
begin
  (RefObject(Command, 0) as TShip).DaysSincePlayerSeen := 0;
end;

procedure MarkShipSeen(Ship: TShip);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckMarkShipSeen);
  AddRef(Command, Ship);
  SubmitCommand(Command);
end;

// Moved from TfJournal.AddRecordClicked.
procedure ExecuteAddJournalRecord(const Command: TPlayerCommand);
begin
  Actor(Command).AddJournalRecord(Command.Text);
end;

procedure AddJournalRecord(const Text: WideString);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckAddJournalRecord);
  Command.Text := Text;
  SubmitCommand(Command);
end;

// Moved from TfJournal.DeleteEntryClicked.
procedure ExecuteDeleteJournalRecord(const Command: TPlayerCommand);
begin
  Actor(Command).DeleteJournalRecord(IntArg(Command, 0));
end;

procedure DeleteJournalRecord(Index: Integer);
begin
  SubmitInt(ckDeleteJournalRecord, Index);
end;

// Moved from TfJournal.ClearEntriesConfirmed.
procedure ExecuteClearJournal(const Command: TPlayerCommand);
begin
  Actor(Command).ClearJournal;
end;

procedure ClearJournal;
begin
  SubmitSimple(ckClearJournal);
end;

// Moved from TfJournal.ClearEntriesConfirmed.
procedure ExecuteClearNews(const Command: TPlayerCommand);
begin
  Actor(Command).TrimNewsEntries(0);
end;

procedure ClearNews;
begin
  SubmitSimple(ckClearNews);
end;

initialization
  RegisterCommand(ckRunGlobalScripts, 'RunGlobalScripts', @ExecuteRunGlobalScripts);
  RegisterCommand(ckPlanetCaptured, 'PlanetCaptured', @ExecutePlanetCaptured);
  RegisterCommand(ckEnterGovernment, 'EnterGovernment', @ExecuteEnterGovernment);
  RegisterCommand(ckLeaveGovernment, 'LeaveGovernment', @ExecuteLeaveGovernment);
  RegisterCommand(ckRefreshGovernment, 'RefreshGovernment', @ExecuteRefreshGovernment);
  RegisterCommand(ckBeginGovernmentDialog, 'BeginGovernmentDialog', @ExecuteBeginGovernmentDialog);
  RegisterCommand(
      ckContinueGovernmentDialog,
      'ContinueGovernmentDialog',
      @ExecuteContinueGovernmentDialog
  );
  RegisterCommand(
      ckGovernmentDialogOverride,
      'GovernmentDialogOverride',
      @ExecuteGovernmentDialogOverride
  );
  RegisterCommand(
      ckGovernmentInjectedDialog,
      'GovernmentInjectedDialog',
      @ExecuteGovernmentInjectedDialog
  );
  RegisterCommand(ckEnterPrison, 'EnterPrison', @ExecuteEnterPrison);
  RegisterCommand(ckChoosePrison, 'ChoosePrison', @ExecuteChoosePrison);
  RegisterCommand(ckPayBribe, 'PayBribe', @ExecutePayBribe);
  RegisterCommand(ckBuyMap, 'BuyMap', @ExecuteBuyMap);
  RegisterCommand(ckPayPrisonBail, 'PayPrisonBail', @ExecutePayPrisonBail);
  RegisterCommand(ckRequestQuest, 'RequestQuest', @ExecuteRequestQuest);
  RegisterCommand(ckNegotiateQuest, 'NegotiateQuest', @ExecuteNegotiateQuest);
  RegisterCommand(ckAcceptQuest, 'AcceptQuest', @ExecuteAcceptQuest);
  RegisterCommand(
      ckDeclineQuestPermanently,
      'DeclineQuestPermanently',
      @ExecuteDeclineQuestPermanently
  );
  RegisterCommand(ckRecordPlanetBattle, 'RecordPlanetBattle', @ExecuteRecordPlanetBattle);
  RegisterCommand(
      ckDeclineAllPlanetBattles,
      'DeclineAllPlanetBattles',
      @ExecuteDeclineAllPlanetBattles
  );
  RegisterCommand(ckPlanetBattleResult, 'PlanetBattleResult', @ExecutePlanetBattleResult);
  RegisterCommand(ckFinishTerronBattle, 'FinishTerronBattle', @ExecuteFinishTerronBattle);
  RegisterCommand(ckRefreshPlayerStats, 'RefreshPlayerStats', @ExecuteRefreshPlayerStats);
  RegisterCommand(ckArrangeSatellites, 'ArrangeSatellites', @ExecuteArrangeSatellites);
  RegisterCommand(ckSatelliteSlot, 'SatelliteSlot', @ExecuteSatelliteSlot);
  RegisterCommand(ckSatelliteOrbit, 'SatelliteOrbit', @ExecuteSatelliteOrbit);
  RegisterCommand(ckReturnHeldSatellite, 'ReturnHeldSatellite', @ExecuteReturnHeldSatellite);
  RegisterCommand(ckPickUpSurfaceLoot, 'PickUpSurfaceLoot', @ExecutePickUpSurfaceLoot);
  RegisterCommand(ckPayInfoSearch, 'PayInfoSearch', @ExecutePayInfoSearch);
  RegisterCommand(ckMarkShipSeen, 'MarkShipSeen', @ExecuteMarkShipSeen);
  RegisterCommand(ckAddJournalRecord, 'AddJournalRecord', @ExecuteAddJournalRecord);
  RegisterCommand(ckDeleteJournalRecord, 'DeleteJournalRecord', @ExecuteDeleteJournalRecord);
  RegisterCommand(ckClearJournal, 'ClearJournal', @ExecuteClearJournal);
  RegisterCommand(ckClearNews, 'ClearNews', @ExecuteClearNews);
end.
