{$EXCESSPRECISION OFF}
unit aStationActions;
{$R-}
{$Q-}
{$B-}

// CHANGE: ENHANCEMENT - What a human does at a space station and on a capital ship's bridge
// (fRuinsTalk), as commands (docs/commands.md). The code is moved from the screen; it keeps
// its text, choices, sounds, achievements and images. The station is the player's DockedTo.
// A quote the screen showed and the player accepted (a price, a micromodule, a destination,
// the parts of a ship to build) travels in the command, and the executor pays what the player
// saw. A command that decides for itself returns its branch in StationOutcome, a number in
// StationAmount and the text the game built in StationText.
//
// The quotes shown in one step and accepted in the next stay in the screen's unit variables
// (BusinessQuote*, InvestmentQuoteCosts, DominionTravelQuotes, ConstructionEquipment...):
// they are per human and screen-held.
interface
uses
  aCommands,
  aGalaxy,
  aItem,
  aPlayer,
  aScript,
  aShip;
const
  // Command kinds 500-599 (see TCommandKind).
  ckEnterBridgeScreen = 500;
  ckEnterStation = 501;
  ckClearStationDialog = 502;
  ckBeginStationDialog = 503;
  ckShowDominatorVictory = 504;
  ckRefreshRangerRatings = 505;
  ckPromoteAtMilitaryBase = 506;
  ckStationDialogOverride = 507;
  ckStationInjectedDialog = 508;
  ckStationScriptGameEnd = 509;
  ckCloseBridge = 510;
  ckToggleImpulseShields = 511;
  ckRecallInterceptors = 512;
  ckRecallAllInterceptors = 513;
  ckChangeInterceptorPassCount = 514;
  ckSetInterceptorStrategy = 515;
  ckPayForModernization = 520;
  ckDepositNodes = 521;
  ckTakeServiceMicroModule = 522;
  ckGiveMicroModuleForNodes = 523;
  ckChangeNationality = 530;
  ckChangeSide = 531;
  ckBuyPirateNodes = 532;
  ckBuyPirateProgram = 533;
  ckPirateBaseRepair = 534;
  ckBuySubCrack = 535;
  ckBuyChameleon = 536;
  ckMilitaryBaseRepair = 540;
  ckCollectMilitaryPrograms = 541;
  ckOrderLiberationOperation = 542;
  ckImproveEquipment = 550;
  ckScienceBaseRepair = 551;
  ckBuySatellite = 552;
  ckSellResearchRemains = 553;
  ckSellResearchEquipment = 554;
  ckSellResearchItem = 555;
  ckBuyResearchProgram = 556;
  ckTakeLoan = 560;
  ckRepayLoan = 561;
  ckOpenDeposit = 562;
  ckCloseDeposit = 563;
  ckBuyMedicalPolicy = 564;
  ckInvest = 565;
  ckBuyTradeAdvice = 566;
  ckExamineDiseases = 570;
  ckTreatDisease = 571;
  ckTreatAllDiseases = 572;
  ckBuyStimulant = 573;
  ckBuySpecialShip = 574;
  ckPriceSpecialShip = 575;
  ckBuildPirateShip = 580;
  ckImproveAtDominion = 581;
  ckBuyPirateLicense = 582;
  ckQueueDominionTravel = 583;
  ckDropDominionTravel = 584;
  ckRelocateDominion = 585;
  ckOrderPirateRaid = 586;
  ckOrderPirateAmbush = 587;
  ckOrderPirateAssault = 588;
const
  // BeginStationDialog outcomes.
  sdContinue = 0;
  // The station's script dialog opens without the greeting's "continue".
  sdSkipGreeting = 1;
  // A dominator series was defeated: the Ranger Center shows the news and a medal.
  sdVictory = 2;
  // The parts of a ship built at a Dominion (BuildPirateShip): hull 42 to def generator 49,
  // then weapons 1 to 5. Source 0 is the hold, 1 the storage, 2 the shop.
  ConstructionPartCount = 13;
type
  TConstructionPart = record
    Item: TEquipment;
    Source: Byte;
  end;
  TConstructionParts = array[0..ConstructionPartCount - 1] of TConstructionPart;
var
  // What the last command decided, the number it worked out and the text the game built.
  StationOutcome: Integer;
  StationAmount: Integer;
  StationText: WideString;
  StationText2: WideString;
  // BeginStationDialog: the station's script; StationDialogOverride: the override's script.
  StationScript: TScript;
  // The dominator series whose defeat the Ranger Center reported (1 Blazer, 2 Keller,
  // 3 Terron, 0 none), the variant of its text and the medal awarded.
  StationVictorySeries: Integer;
  StationVictoryVariant: Integer;
  StationVictoryMedal: WideString;
  // OrderPirateRaid: the star the pirates were sent to.
  StationTargetStar: TStar;

// Opening and closing the station screen.
// A capital ship's bridge is not on a planet.
procedure EnterBridgeScreen;
// Forgets that the station asked to see the player on docking.
procedure EnterStation;
procedure ClearStationDialog;

// The station's dialog. Clears the dialog rules, reports a defeated dominator series when
// CheckVictory, and opens the station's script dialog (StationScript).
function BeginStationDialog(CheckVictory: Boolean): Integer;
// Returns StationVictorySeries.
function ReportDominatorVictory: Integer;
procedure RefreshRangerRatings;
// Returns whether the player was promoted; StationText is the micromodule awarded at rank 7,
// StationText2 the item awarded.
function PromoteAtMilitaryBase(StationOwner: Byte): Boolean;
// Applies the script dialog override with the highest priority; returns its script.
function ApplyStationDialogOverride: TScript;
// Opens an injected answer's dialog; returns whether it has a message to show.
function RunStationInjectedDialog(Injection: PScriptDialogInjection): Boolean;
// The script answer that ends the game.
procedure EndGameByScriptAnswer(Answer: Integer);

// A capital ship's bridge.
procedure CloseBridge;
procedure SwitchImpulseShields;
procedure RecallInterceptorsFrom(Ship: TShip);
procedure RecallEveryInterceptor;
procedure ChangeInterceptorPassCount(Delta: Integer);
procedure SetInterceptorStrategy(Strategy: Integer);

// Every station.
procedure PayForModernization(Cost: Integer);
// Takes the special ship the station offers; with no money only ends the offer.
procedure PurchaseSpecialShip;
// The price of the special ship the station offers. Pricing it builds the hull, which takes an
// item id.
function PriceSpecialShip: Integer;

// The Ranger Center.
procedure DepositNodes;
procedure TakeServiceMicroModule(ModuleIndex, Cost: Integer);
// StationText is the micromodule's name and StationAmount the nodes it was worth.
procedure GiveMicroModuleForNodes(ModuleId, LowCost, MediumCost: Integer);

// The pirate base.
procedure ChangeNationality(Race: Byte; Portrait: Integer; const Name: WideString; Cost: Integer);
// QuotedCost is the price the screen showed.
procedure ChangeSide(QuotedCost: Integer);
procedure PurchasePirateNodes;
function PurchasePirateProgram(ProgramIndex: Byte; Cost: Integer): Boolean;
function PirateBaseRepair: Boolean;
// Returns the price paid.
function PurchaseSubCrack(HalfPrice: Boolean): Integer;
procedure PurchaseChameleon(Series: Byte; Cost: Integer);

// The military base.
procedure MilitaryBaseRepair;
procedure CollectMilitaryPrograms;
// Returns whether a liberation group was formed (the last of Galaxy.LiberationGroups).
function OrderLiberationOperation(Cost, FailureCost: Integer): Boolean;

// The science base.
function ImproveEquipment(Item: TEquipment; Kind: TImprovementKind; Detail: Integer): Boolean;
function ScienceBaseRepair: Boolean;
procedure PurchaseSatellite;
// Each returns the money paid for the items.
function SellAllResearchRemains(Series: Byte): Integer;
function SellAllResearchEquipment(Series: Byte): Integer;
function SellOneResearchItem(Series: Byte; Item: TEquipment): Integer;
procedure PurchaseResearchProgram(Series: Byte; Cost: Integer);

// The business center.
function TakeLoan(Quote, Amount, DueTurn: Integer): Boolean;
procedure RepayLoan;
procedure OpenDeposit(Amount: Integer; InterestRate: Single);
// Returns whether the deposit was paid out; StationAmount is the profit.
function CloseDeposit: Boolean;
procedure PurchaseMedicalPolicy;
// Target is the star of a new station or the planet of a war subsidy. StationText is the
// business center's answer.
procedure Invest(Kind: Byte; Cost: Integer; Target: TObject);
// Returns the number of trade routes found; StationText lists them.
function PurchaseTradeAdvice(Nearby: Boolean; Cost: Integer): Integer;

// The medical center.
// The medical center looks at the player's diseases.
procedure ExamineDiseases;
procedure TreatDisease(Index: Integer);
procedure TreatAllDiseases(Cost: Integer);
procedure PurchaseStimulant(Index: Integer);

// The Dominion.
// StationOutcome is 1 when the ship became a partner, StationText its name and StationAmount
// the months of partnership. Returns the number of shop items used.
function BuildPirateShip(const Parts: TConstructionParts): Integer;
function ImproveAtDominion(Item: TEquipment): Boolean;
procedure PurchasePirateLicense(Cost: Integer);
procedure QueueDominionTravel(Star: TStar; Cost: Integer);
procedure DropDominionTravel;
procedure RelocateDominion(Star: TStar);
// Returns whether pirates were sent (StationTargetStar); StationText names them and
// StationAmount is the price. QuotedCost is the price the screen showed.
function OrderPirateRaid(QuotedCost: Integer): Boolean;
procedure OrderPirateAmbush(Star: TStar);
procedure OrderPirateAssault(Star: TStar);

// What P pays to move the station it is docked with to Star.
function GetDominionRelocationCost(P: TPlayer; Star: TStar): Integer;
function ApplyRecentDominionOrderSurcharge(Cost: Single): Integer;
implementation
uses
  SysUtils,
  Classes,
  Math,
  EC_Str,
  aMyFunction,
  aConst,
  aDialogActions,
  aGalaxyEvent,
  aGalaxyStruct,
  aHuman,
  aKling,
  aPlanet,
  aRanger,
  aNormalShip,
  aPirate,
  aWarrior,
  aGroup,
  aRuins,
  aSession,
  aShopStock,
  Globals,
  GR_Main;

// CHANGE: ENHANCEMENT - A trade a screen submits; another human may have been first
// (aCommands.SubmitTrade).
procedure SubmitAny(const Command: TPlayerCommand);
begin
  if IsTradeCommand(Command.Kind) then
    SubmitTrade(Command)
  else
    SubmitCommand(Command);
end;

procedure SubmitSimple(Kind: TCommandKind);
begin
  SubmitAny(NewCommand(Kind));
end;

procedure SubmitInt(Kind: TCommandKind; Value: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(Kind);
  AddInt(Command, Value);
  SubmitAny(Command);
end;

procedure SubmitInt2(Kind: TCommandKind; Value1, Value2: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(Kind);
  AddInt(Command, Value1);
  AddInt(Command, Value2);
  SubmitAny(Command);
end;

procedure SubmitRef(Kind: TCommandKind; Instance: TObject);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(Kind);
  AddRef(Command, Instance);
  SubmitCommand(Command);
end;

function EquipmentArg(const Command: TPlayerCommand; Index: Integer): TEquipment;
begin
  Result := RefObject(Command, Index) as TEquipment;
  if Result = nil then
    raise Exception.Create(CommandKindName(Command.Kind) + ' names no item');
end;

function StarArg(const Command: TPlayerCommand; Index: Integer): TStar;
begin
  Result := RefObject(Command, Index) as TStar;
  if Result = nil then
    raise Exception.Create(CommandKindName(Command.Kind) + ' names no star');
end;

// Moved from fRuinsTalk. Native evaluates the receiver before the bounded payment, with the
// clamp cells allocated before the receiver cell.
procedure PayStationModernization(P: TPlayer; QuotedCost: Cardinal); inline;
var
  Remaining, Payment: Int64;
begin
  Remaining := P.Money - Trunc(QuotedCost);
  if Remaining < 0 then
    Payment := 0
  else
    Payment := Remaining;
  P.SetMoney(Integer(Payment));
end;

procedure PayNationalityMoney(P: TPlayer; QuotedCost: Integer); inline;
var
  Cost, Remaining, Payment: Integer;
begin
  if QuotedCost < 0 then
    Cost := 0
  else
    Cost := QuotedCost;
  Remaining := P.Money - Cost;
  if Remaining < 0 then
    Payment := 0
  else
    Payment := Remaining;
  P.SetMoney(Payment);
end;

procedure PayClampedMoney(P: TPlayer; Cost: Integer); inline;
var
  Remaining, Payment: Integer;
begin
  Remaining := P.Money - Cost;
  if Remaining < 0 then
    Payment := 0
  else
    Payment := Remaining;
  P.SetMoney(Payment);
end;

procedure PayDepositMoney(P: TPlayer); inline;
var
  Remaining, Payment: Integer;
begin
  Remaining := P.Money - P.DepositAmount;
  if Remaining < 0 then
    Payment := 0
  else
    Payment := Remaining;
  P.SetMoney(Payment);
end;

// Moved from TfRuinsTalk.SpendDominionServiceCredit.
procedure SpendDominionServiceCredit(P: TPlayer; CreditCost: Single);
begin
  P.PirateLicenseCash :=
      Max(
          0,
          Round((P.PirateLicenseCash - Galaxy.AverageRangerCapital * CreditCost / 600) * 0.85)
      );
end;

// Moved from fRuinsTalk.
function GetDominionRelocationCost(P: TPlayer; Star: TStar): Integer;
var
  Discount: Byte;
begin
  Discount := P.GetPirateServiceDiscount;
  Result :=
      Min(
          100000000,
          Round(
              (PointDistanceSquared(P.DockedTo.CurrentStar.Position, Star.Position) + 6400)
                  * SeededRandomIntRange(
                      Galaxy.ComputeScaledHugeMoney(2) div 2,
                      Galaxy.ComputeScaledHugeMoney(2) * 2,
                      Star.GenerationSeed + 1171 + P.DockedTo.CurrentStar.GenerationSeed)
                  / 6400
                  * (100 - Discount)
                  / 100
          )
      );
end;

// Moved from fRuinsTalk.
function ApplyRecentDominionOrderSurcharge(Cost: Single): Integer;
var
  I: Integer;
  EventType: WideString;
begin
  for I := Galaxy.GalaxyEvents.Count - 1 downto 0 do
  begin
    if TGalaxyEvent(Galaxy.GalaxyEvents[I]).Turn + 60 < Galaxy.CurrentTurn then
      Break;
    EventType := TGalaxyEvent(Galaxy.GalaxyEvents[I]).EventType;
    if (EventType = 'PlayerOrdersPirateAmbush')
        or (EventType = 'PlayerOrdersPirateRaid')
        or (EventType = 'PlayerOrdersPirateAssault') then
      Cost := Min(100000000.0, Cost * 1.5);
  end;
  Result := RoundAndTruncateToHundreds(Cost);
end;

{ Opening and closing the station screen }

// Moved from TfRuinsTalk.OnOpen.
procedure ExecuteEnterBridgeScreen(const Command: TPlayerCommand);
begin
  Actor(Command).CurrentPlanet := nil;
end;

procedure EnterBridgeScreen;
begin
  SubmitSimple(ckEnterBridgeScreen);
end;

// Moved from TfRuinsTalk.OnOpen.
procedure ExecuteEnterStation(const Command: TPlayerCommand);
begin
  if Actor(Command).PendingDockDialogue = 1 then
    Actor(Command).PendingDockDialogue := 0;
end;

procedure EnterStation;
begin
  SubmitSimple(ckEnterStation);
end;

// Moved from TfRuinsTalk.OnClose.
procedure ExecuteClearStationDialog(const Command: TPlayerCommand);
begin
  Session.ScriptDialogIndex := -1;
end;

procedure ClearStationDialog;
begin
  // With no player there is no one to act; this runs unrecorded.
  if LocalPlayer = nil then
    Session.ScriptDialogIndex := -1
  else
    SubmitSimple(ckClearStationDialog);
end;

{ The station's dialog }

// Moved from TfRuinsTalk.ShowDominatorVictoryDialog; the screen builds the text. The news
// bubbles and the medal are Human's.
function ApplyDominatorVictory(Human: THuman): Boolean;
var
  P: TPlayer;
  MessageEntry: TMessagePlayer;
  Variant: Integer;
begin
  P := Human.Player;
  Result := False;
  StationVictorySeries := 0;
  StationVictoryVariant := 0;
  StationVictoryMedal := '';
  if (Galaxy.TerronSeriesResolvedTurn <> 0)
      or (Galaxy.KellerSeriesResolvedTurn <> 0)
      or (Galaxy.BlazerSeriesResolvedTurn <> 0) then
  begin
    MessageEntry := Human.FindBubbleByKey('BlazerWin', False);
    if (MessageEntry <> nil) and (MessageEntry.Kind = 3) then
    begin
      MessageEntry.Kind := 4;
      MessageEntry.WasRead := False;
      Result := True;
      if (BlazerShip = nil) and (Galaxy.BlazerSelfDestructTurn <> 0) then
        Variant := 1
      else if Galaxy.BlazerLandingPlanetId <> 0 then
        Variant := 2
      else
        Variant := 3;
      StationVictorySeries := 1;
      StationVictoryVariant := Variant;
      StationVictoryMedal := P.AwardRandomMedal;
    end
    else
    begin
      MessageEntry := Human.FindBubbleByKey('KellerWin', False);
      if (MessageEntry <> nil) and (MessageEntry.Kind = 3) then
      begin
        MessageEntry.Kind := 4;
        MessageEntry.WasRead := False;
        Result := True;
        if KellerShip = nil then
          Variant := 1
        else
          Variant := 2;
        StationVictorySeries := 2;
        StationVictoryVariant := Variant;
        StationVictoryMedal := P.AwardRandomMedal;
      end
      else
      begin
        MessageEntry := Human.FindBubbleByKey('TerronWin', False);
        if (MessageEntry <> nil) and (MessageEntry.Kind = 3) then
        begin
          MessageEntry.Kind := 4;
          MessageEntry.WasRead := False;
          Result := True;
          if Galaxy.TerronToStarTurn <> 0 then
            Variant := 1
          else if Galaxy.TerronWeaponLockTurn <> 0 then
            Variant := 2
          else if Galaxy.TerronGrowLockTurn <> 0 then
            Variant := 3
          else if Galaxy.TerronLandingLockTurn <> 0 then
            Variant := 4
          else
          begin
            if TerronShip = nil then
              Variant := 5
            else
            begin
              Variant := 1;
              RaiseWideMessage('Terron status');
            end;
          end;
          StationVictorySeries := 3;
          StationVictoryVariant := Variant;
          StationVictoryMedal := P.AwardRandomMedal;
        end;
      end;
    end;
  end;
end;

// Moved from TfRuinsTalk.M_Main: the dialog rules, the dominator victory news at a Ranger
// Center, the station's script dialog, and the greeting it skips.
procedure ExecuteBeginStationDialog(const Command: TPlayerCommand);
var
  P: TPlayer;
  Script: TScript;
  Text: WideString;
begin
  P := Actor(Command);
  ClearScriptDialogRules;
  Session.ScriptDialogIndex := -1;
  Script := nil;
  StationScript := nil;
  StationOutcome := sdContinue;
  if (IntArg(Command, 0) <> 0) and ApplyDominatorVictory(ActorHuman(Command)) then
  begin
    StationOutcome := sdVictory;
    Exit;
  end;
  if P.DockedTo.ScriptShip <> nil then
  begin
    Script := TScriptShip(P.DockedTo.ScriptShip).Script;
    Text := TScriptShip(P.DockedTo.ScriptShip).GetGroup.DefinitionText;
    if Text <> '' then
    begin
      Script.PublishShipContext(TScriptShip(P.DockedTo.ScriptShip));
      Script.CallDialogByVariable(Text);
    end;
  end;
  StationScript := Script;
  if Session.ScriptDialogIndex >= 0 then
    if Script.SkipGreeting then
    begin
      Script.SkipGreeting := False;
      StationOutcome := sdSkipGreeting;
    end;
end;

function BeginStationDialog(CheckVictory: Boolean): Integer;
begin
  SubmitInt(ckBeginStationDialog, Ord(CheckVictory));
  Result := StationOutcome;
end;

// Moved from TfRuinsTalk.ShowDominatorVictoryDialog.
procedure ExecuteShowDominatorVictory(const Command: TPlayerCommand);
begin
  ApplyDominatorVictory(ActorHuman(Command));
end;

function ReportDominatorVictory: Integer;
begin
  SubmitSimple(ckShowDominatorVictory);
  Result := StationVictorySeries;
end;

// Moved from TfRuinsTalk.M_Main and DepositNodesAtRangerCenter.
procedure ExecuteRefreshRangerRatings(const Command: TPlayerCommand);
begin
  Galaxy.RefreshRangerRatingPlaces;
end;

procedure RefreshRangerRatings;
begin
  SubmitSimple(ckRefreshRangerRatings);
end;

// Moved from TfRuinsTalk.M_Main.
procedure ExecutePromoteAtMilitaryBase(const Command: TPlayerCommand);
var
  P: TPlayer;
  StationOwner: Byte;
  Item: TItem;
  ModuleIndex: Integer;
  Seed: Cardinal;
  ItemType: Byte;
  Weight, Level: Integer;
  Info: PWeaponInfo;
  MinimumSizeFactor, MaximumSizeFactor: Single;
begin
  P := Actor(Command);
  StationOwner := IntArg(Command, 0);
  StationOutcome := 0;
  StationText := '';
  StationText2 := '';
  if not P.TryPromoteRank then
    Exit;
  StationOutcome := 1;
  if P.Rank = 7 then
  begin
    ModuleIndex := FindMicroModuleTemplateByCustomTag('AkrinAmplifier');
    Item := TMicroModule.Create;
    if ModuleIndex >= 0 then
      (Item as TMicroModule).Init(ModuleIndex)
    else
      (Item as TMicroModule)
          .Init(
              Galaxy.SelectMicroModule(
                  1,
                  15,
                  Galaxy.GenerationSeed + Cardinal(Galaxy.CurrentTurn),
                  P.DockedTo
              ));
    P.Inventory.Add(Item);
    StationText := (Item as TMicroModule).GetPlainName;
  end;
  Seed := Galaxy.CurrentTurn div 50 * (P.DockedTo.Id * (P.Rank + 11));
  MinimumSizeFactor := EquipmentSizeFactors[4];
  MaximumSizeFactor := EquipmentSizeFactors[2];
  if NextRandomIntRange(1, 100, Seed) > 70 then
  begin
    Info :=
        Galaxy.SelectWeaponInfo(
            Seed,
            [0, 1, Ord(OwnerWeaponAvailability[StationOwner])],
            Min(Galaxy.TechLevel + 2, 8),
            Galaxy.TechLevel
        );
    Seed := Galaxy.CurrentTurn div 33 * (P.DockedTo.Id * (P.Rank + 17));
    Weight :=
        NextRandomIntRange(
            Round(Info.AverageSize * MinimumSizeFactor),
            Round(Info.AverageSize * MaximumSizeFactor),
            Seed
        );
    Level :=
        Round(
            RemapClamped(
                Round(RemapClamped(ShortInt(P.Rank * 1), 0, 7, 1, 5)),
                1,
                5,
                3,
                8
            )
        );
    Item := CreateGeneratedWeapon(Info, Weight, Level, StationOwner);
  end
  else
  begin
    ItemType := PickRandomItemType([Ord(t_FuelTanks)..Ord(t_DefGenerator)]);
    Seed := Galaxy.CurrentTurn div 33 * (P.DockedTo.Id * (P.Rank + 17));
    Weight :=
        NextRandomIntRange(
            Round(GetAverageItemSize(ItemType) * MinimumSizeFactor),
            Round(GetAverageItemSize(ItemType) * MaximumSizeFactor),
            Seed
        );
    Level := Round(RemapClamped(ShortInt(P.Rank * 1), 0, 7, 3, 8));
    Item := CreateGeneratedEquipment(TItemType(ItemType), Weight, Level, StationOwner);
  end;
  if Item <> nil then
    StationText2 := Item.GetDisplayName
  else
    RaiseWideMessage('eq=nil');
  P.Inventory.Add(Item);
end;

function PromoteAtMilitaryBase(StationOwner: Byte): Boolean;
begin
  SubmitInt(ckPromoteAtMilitaryBase, StationOwner);
  Result := StationOutcome <> 0;
end;

// Moved from TfRuinsTalk.M_Main.
procedure ExecuteStationDialogOverride(const Command: TPlayerCommand);
var
  P: TPlayer;
  Script: TScript;
  Text: WideString;
  Entry: PScriptDialogOverride;
begin
  P := Actor(Command);
  // CHANGE: BUGFIX - The override the sender's screen selected, by its key; a log from before
  // selects the one with the highest priority here. None (an empty list) is refused.
  // CHANGE: BUGFIX - Ints: the key, then its script key's count.
  Entry := OverrideArgument(Command, 0, 5);
  Script := Entry.Script;
  Script.InitCode.LocalVar.GetVar('GAnswerData').SetDword(Entry.AnswerData);
  Text := Entry.DialogName;
  if Text <> '' then
  begin
    Script.PublishCurrentShip(P.DockedTo);
    Script.CallDialogByVariable(Text);
    if Session.ScriptDialogIndex < 0 then
      AppendLogLineThreadSafe(
          Script.ScriptFileName
              + ' has overriden dialog with '
              + Text
              + ' but it failed to start'
      );
  end;
  StationScript := Script;
end;

function ApplyStationDialogOverride: TScript;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckStationDialogOverride);
  AddOverrideKey(Command, SelectedDialogOverride);
  AddOverrideCount(Command, SelectedDialogOverride);
  SubmitCommand(Command);
  Result := StationScript;
end;

// Moved from TfRuinsTalk.RunInjectedDialog: the dialog the answer leads to, and its message.
// The dialog runs in the script current when the answer was chosen.
procedure ExecuteStationInjectedDialog(const Command: TPlayerCommand);
var
  Injection: PScriptDialogInjection;
  Script: TScript;
begin
  // CHANGE: BUGFIX - Ints: the answer's index, the script's index, the answer's key (five),
  // then the script's key (three). Both are found before anything changes.
  // CHANGE: BUGFIX - Then the count of the answer's script key and that of the script's key.
  Injection := InjectionArgument(Command, 0, 2, 10);
  Script := ScriptArgument(Command, 1, 7, 11, True);
  if Injection.Script = nil then
    raise ECommandRefused.CreateReason(
        rrTargetGone,
        CommandKindName(Command.Kind) + ' names an answer whose script has ended'
    );
  if Script <> nil then
    CurrentScript := Script;
  Injection.Script.PublishCurrentShip(Actor(Command).DockedTo);
  CurrentScript.InitCode.LocalVar.GetVar('GAnswerData').SetDword(Injection.AnswerData);
  Session.ScriptDialogIndex := -1;
  CurrentScript.CallDialogByVariable(Injection.DialogName);
  if Session.ScriptDialogIndex < 0 then
    StationOutcome := 0
  else
  begin
    StationOutcome := 1;
    CurrentScript.CallDialogMessage(Session.ScriptDialogIndex);
  end;
end;

function RunStationInjectedDialog(Injection: PScriptDialogInjection): Boolean;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckStationInjectedDialog);
  AddInt(Command, ScriptDialogInjections.IndexOf(Injection));
  AddScriptIndex(Command, CurrentScript);
  AddInjectionKey(Command, Injection);
  AddScriptKey(Command, CurrentScript);
  AddInjectionCount(Command, Injection);
  AddScriptCount(Command, CurrentScript);
  SubmitCommand(Command);
  Result := StationOutcome <> 0;
end;

// Moved from TfRuinsTalk.RunScriptGameEnd.
procedure ExecuteStationScriptGameEnd(const Command: TPlayerCommand);
begin
  // CHANGE: BUGFIX - Ints: the script's index, the answer, then the script's key and its count.
  CurrentScript := ScriptArgument(Command, 0, 2, 5, False);
  CurrentScript.ExecuteDialogAnswer(IntArg(Command, 1));
  Session.GameEndReason := 0;
end;

procedure EndGameByScriptAnswer(Answer: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckStationScriptGameEnd);
  AddScriptIndex(Command, CurrentScript);
  AddInt(Command, Answer);
  AddScriptKey(Command, CurrentScript);
  AddScriptCount(Command, CurrentScript);
  SubmitCommand(Command);
end;

{ A capital ship's bridge }

// Moved from TfRuinsTalk.CloseHullMode and CloseRuinsMode.
procedure ExecuteCloseBridge(const Command: TPlayerCommand);
begin
  Actor(Command).CloseRuinsModeScreen;
end;

procedure CloseBridge;
begin
  SubmitSimple(ckCloseBridge);
end;

// Moved from TfRuinsTalk.ToggleImpulseShields.
procedure ExecuteToggleImpulseShields(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  P.GetHull.ImpulseShieldsEnabled := not P.GetHull.ImpulseShieldsEnabled;
  P.GetHull.Energy := Max(0, P.GetHull.Energy - 10);
end;

procedure SwitchImpulseShields;
begin
  SubmitSimple(ckToggleImpulseShields);
end;

// Moved from TfRuinsTalk.RecallInterceptorsFromTarget.
procedure ExecuteRecallInterceptors(const Command: TPlayerCommand);
var
  Ship: TShip;
begin
  Ship := RefObject(Command, 0) as TShip;
  // CHANGE: BUGFIX - As the bridge lists them: the actor's own interceptors only. A client's
  // command recalled anyone's from any ship, and between days they may have returned or
  // another human's may have been sent (docs/network.md, Commands).
  if (Ship = nil) or (Ship.InterceptorSourceShip <> Actor(Command)) then
    raise ECommandRefused.CreateReason(
        rrTargetGone,
        'RecallInterceptors: the human has no interceptors at the ship'
    );
  Ship.ClearIncomingInterceptors;
end;

procedure RecallInterceptorsFrom(Ship: TShip);
begin
  SubmitRef(ckRecallInterceptors, Ship);
end;

// Moved from TfRuinsTalk.RecallAllInterceptors.
procedure ExecuteRecallAllInterceptors(const Command: TPlayerCommand);
var
  I, J: Integer;
  Star: TStar;
  Ship: TShip;
  P: TPlayer;
begin
  P := Actor(Command);
  for I := 0 to Galaxy.Stars.Count - 1 do
  begin
    Star := P.CurrentStar.StarDistances[I].Star;
    for J := 0 to Star.Ships.Count - 1 do
    begin
      Ship := TShip(Star.Ships[J]);
      if P = Ship.InterceptorSourceShip then
        Ship.ClearIncomingInterceptors;
    end;
  end;
end;

procedure RecallEveryInterceptor;
begin
  SubmitSimple(ckRecallAllInterceptors);
end;

// Moved from TfRuinsTalk.IncreaseInterceptorPassCount and DecreaseInterceptorPassCount.
procedure ExecuteChangeInterceptorPassCount(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  P.GetHull.InterceptorPassCountOverride := P.GetInterceptorPassCount + IntArg(Command, 0);
end;

procedure ChangeInterceptorPassCount(Delta: Integer);
begin
  SubmitInt(ckChangeInterceptorPassCount, Delta);
end;

// Moved from TfRuinsTalk.SelectInterceptorStrategy.
procedure ExecuteSetInterceptorStrategy(const Command: TPlayerCommand);
begin
  Actor(Command).GetHull.InterceptorTargetingStrategy :=
      TInterceptorTargetingStrategy(IntArg(Command, 0));
end;

procedure SetInterceptorStrategy(Strategy: Integer);
begin
  SubmitInt(ckSetInterceptorStrategy, Strategy);
end;

{ Every station }

// Moved from TfRuinsTalk.OpenStationModernization.
procedure ExecutePayForModernization(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  // CHANGE: BUGFIX - The station asks for the money only while nobody has paid it
  // (TfRuinsTalk.OpenStationModernization), and the screen checks the money. Between days a
  // second human paid for what another human's payment had already bought, and the money
  // stopped at 0 (docs/network.md, Commands).
  if (P.DockedTo as TRuins).ModernizationSponsor then
    raise ECommandRefused.CreateReason(rrOfferGone, 'PayForModernization: the station is paid for');
  if P.Money < IntArg(Command, 0) then
    raise ECommandRefused.CreateReason(rrNoMoney, 'PayForModernization: not enough money');
  PayStationModernization(P, Cardinal(IntArg(Command, 0)));
  (P.DockedTo as TRuins).ModernizationSponsor := True;
end;

procedure PayForModernization(Cost: Integer);
begin
  SubmitInt(ckPayForModernization, Cost);
end;

// Moved from TfRuinsTalk.BuyStationSpecialShip.
procedure ExecuteBuySpecialShip(const Command: TPlayerCommand);
const
  RelationShipTypes = [htRanger, htPirate..htDiplomat];
  PirateOwners = [1];
  CoalitionOwners = [0, 2..4];
var
  Price: Integer;
  Hull: THull;
  P: TPlayer;
begin
  P := Actor(Command);
  // CHANGE: BUGFIX - The station makes this offer once. A second human who accepted it from a
  // copy where it was still made between days got another hull (docs/network.md, Commands).
  if not (P.DockedTo as TRuins).SpecialServiceActive then
    raise ECommandRefused.CreateReason(rrOfferGone, 'BuySpecialShip: the offer was taken');
  (P.DockedTo as TRuins).SpecialServiceActive := False;
  Hull := THull.Create;
  if P.DockedTo.TypeId = Byte(rstPirateBase) then
  begin
    Hull.Init(1000, 8, P.DockedTo.OwnerId, 9, -1, False);
    ApplySpecialMicroModule(FindMicroModuleTemplateByCustomTag('SuperHullPB'), Hull);
  end
  else if P.DockedTo.TypeId = Byte(rstMilitaryBase) then
  begin
    Hull.Init(1000, 8, P.DockedTo.OwnerId, 9, -1, False);
    ApplySpecialMicroModule(FindMicroModuleTemplateByCustomTag('SuperHullWB'), Hull);
  end
  else if P.DockedTo.TypeId = Byte(rstScienceBase) then
  begin
    Hull.Init(1000, 8, P.DockedTo.OwnerId, 9, -1, False);
    ApplySpecialMicroModule(FindMicroModuleTemplateByCustomTag('SuperHullSB'), Hull);
  end
  else
    RaiseWideMessage('Buy special ship');
  Price := Hull.GetConditionAdjustedCost;
  if P.Money >= Price then
  begin
    P.SetMoney(P.Money - Price);
    if P.IsOnPlanet then
      P.AddItemToPlayerStorage(Hull, P.CurrentPlanet, -1)
    else
      P.AddItemToPlayerStorage(Hull, P.DockedTo, -1);
    // CHANGE: ENHANCEMENT - The storage is shared: the others' open ship screen there shows it.
    StorageChanged(PlayerStorageLocation(P), ActorHuman(Command));
    if P.DockedTo.TypeId = Byte(rstPirateBase) then
    begin
      P.ChangePlanetRelations(nil, rcmIncrease, 30, [1]);
      P.ChangeShipRelations(nil, rcmIncrease, 30, RelationShipTypes, PirateOwners);
      P.ChangePlanetRelations(nil, rcmDecreaseWithFloor20, 50, [0, 2, 3, 4]);
      P.ChangeShipRelations(nil, rcmDecreaseWithFloor20, 50, RelationShipTypes, CoalitionOwners);
    end;
  end
  else
    Hull.Free;
end;

procedure PurchaseSpecialShip;
begin
  SubmitSimple(ckBuySpecialShip);
end;

// Moved from TfRuinsTalk.ShowStationSpecialShipDialog.
procedure ExecutePriceSpecialShip(const Command: TPlayerCommand);
var
  Hull: THull;
  P: TPlayer;
begin
  P := Actor(Command);
  Hull := THull.Create;
  if P.DockedTo.TypeId = Byte(rstPirateBase) then
  begin
    Hull.Init(1000, 8, P.DockedTo.OwnerId, 9, -1, False);
    ApplySpecialMicroModule(FindMicroModuleTemplateByCustomTag('SuperHullPB'), Hull);
  end
  else if P.DockedTo.TypeId = Byte(rstMilitaryBase) then
  begin
    Hull.Init(1000, 8, P.DockedTo.OwnerId, 9, -1, False);
    ApplySpecialMicroModule(FindMicroModuleTemplateByCustomTag('SuperHullWB'), Hull);
  end
  else if P.DockedTo.TypeId = Byte(rstScienceBase) then
  begin
    Hull.Init(1000, 8, P.DockedTo.OwnerId, 9, -1, False);
    ApplySpecialMicroModule(FindMicroModuleTemplateByCustomTag('SuperHullSB'), Hull);
  end
  else
    RaiseWideMessage('Ask special ship');
  StationAmount := Hull.GetConditionAdjustedCost;
  Hull.Free;
end;

function PriceSpecialShip: Integer;
begin
  SubmitSimple(ckPriceSpecialShip);
  Result := StationAmount;
end;

{ The Ranger Center }

// Moved from TfRuinsTalk.DepositNodesAtRangerCenter; the achievement check stays in the
// screen.
procedure ExecuteDepositNodes(const Command: TPlayerCommand);
begin
  Actor(Command).DepositCarriedNodes;
  Galaxy.RefreshRangerRatingPlaces;
end;

procedure DepositNodes;
begin
  SubmitSimple(ckDepositNodes);
end;

// Moved from TfRuinsTalk.BuyRangerCenterMicroModule.
procedure ExecuteTakeServiceMicroModule(const Command: TPlayerCommand);
var
  Cost, ModuleIndex: Integer;
  Item: TMicroModule;
  Event: TGalaxyEvent;
  P: TPlayer;
begin
  P := Actor(Command);
  ModuleIndex := IntArg(Command, 0);
  Cost := IntArg(Command, 1);
  Dec(P.BaseNodes, Cost);
  Item := TMicroModule.Create;
  Item.Init(ModuleIndex);
  P.Inventory.Add(Item);
  Event := AddGalaxyEvent('PlayerReceivesMM');
  Event.AddData(Item.Id);
  Event.AddData(ModuleIndex);
  Event.AddData(Cost);
end;

procedure TakeServiceMicroModule(ModuleIndex, Cost: Integer);
begin
  SubmitInt2(ckTakeServiceMicroModule, ModuleIndex, Cost);
end;

// Moved from TfRuinsTalk.ExchangeMicroModuleForNodes.
procedure ExecuteGiveMicroModuleForNodes(const Command: TPlayerCommand);
var
  I, Value, ModuleId: Integer;
  Item: TItem;
  Module: TMicroModule;
  P: TPlayer;
begin
  P := Actor(Command);
  ModuleId := IntArg(Command, 0);
  Module := nil;
  for I := 0 to P.Inventory.Count - 1 do
  begin
    Item := TItem(P.Inventory[I]);
    if Item.ItemType = t_MicroModule then
    begin
      Module := Item as TMicroModule;
      if Module.Id = ModuleId then
        Break;
      Module := nil;
    end;
  end;
  if Module = nil then
    RaiseWideMessage(
        'Косяк: TfRuinsTalk.I_GiveNodOk [FId = ' + IntToStr(Cardinal(ModuleId)) + ']'
    );
  Value := Module.CalculateNodeExchangeValue(IntArg(Command, 1), IntArg(Command, 2), P.DockedTo);
  StationText := Module.GetHighlightedName;
  StationAmount := Value;
  P.Inventory.Delete(P.Inventory.IndexOf(Module));
  Module.Free;
  Inc(P.BaseNodes, Value);
  P.AchievementStats.CheckNodesAchievement;
  P.RefreshDerivedStats(True);
end;

procedure GiveMicroModuleForNodes(ModuleId, LowCost, MediumCost: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckGiveMicroModuleForNodes);
  AddInt(Command, ModuleId);
  AddInt(Command, LowCost);
  AddInt(Command, MediumCost);
  SubmitCommand(Command);
end;

{ The pirate base }

// Moved from TfRuinsTalk.AcceptPirateBaseNationality: what the player chose in the face
// screen. The achievement stays in the screen.
procedure ExecuteChangeNationality(const Command: TPlayerCommand);
const
  RelationShipTypes = [htRanger, htPirate..htDiplomat];
var
  RangerIndex, J: Integer;
  Relation: Byte;
  Event: TGalaxyEvent;
  Race: Byte;
  P: TPlayer;
begin
  P := Actor(Command);
  Race := IntArg(Command, 0);
  P.PortraitFaceId := IntArg(Command, 1);
  P.PilotRace := Race;
  if P.OwnerId <> Byte(oiPirate) then
    P.OwnerId := RaceToOwner(Race);
  P.Name := Command.Text;
  Session.LastLoadedPlayerName := P.Name;
  PayNationalityMoney(P, IntArg(Command, 2));
  P.AddPirateCareerActivity(8);
  Inc(P.NationalityChangeCount);
  for J := 1 to 12 do
    if not CaptainHealthDefinitions[J].Disabled then
      if not (RaceToOwner(P.PilotRace) in CaptainHealthDefinitions[J].AllowedOwners)
          and (P.CaptainHealth[J].Progress < 100) then
      begin
        P.CaptainHealth[J].Progress := 0;
        P.StatusEffectSourceNames[J] := '';
      end;
  P.ChangePlanetRelations(nil, rcmRaiseTo, 70, TOwnerMask(PlanetOwnerMasks.Coalition));
  P.ChangeShipRelations(
      nil,
      rcmRaiseTo,
      70,
      RelationShipTypes,
      TOwnerMask(PlanetOwnerMasks.Coalition)
  );
  if MainPiratePlanet <> nil then
  begin
    RangerIndex := Galaxy.Rangers.IndexOf(P);
    Relation := Byte(MainPiratePlanet.RangerRelations[RangerIndex]);
    if Relation < 45 then
      MainPiratePlanet.RangerRelations[RangerIndex] := Pointer(45);
  end;
  P.ChangeShipRelations(
      nil,
      rcmRaiseTo,
      45,
      RelationShipTypes,
      TOwnerMask(PlanetOwnerMasks.PirateClan)
  );
  Event := AddGalaxyEvent('PlayerChangesNationality');
  Event.AddData(P.PilotRace);
end;

procedure ChangeNationality(Race: Byte; Portrait: Integer; const Name: WideString; Cost: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckChangeNationality);
  AddInt(Command, Race);
  AddInt(Command, Portrait);
  AddInt(Command, Cost);
  Command.Text := Name;
  SubmitCommand(Command);
end;

// Moved from TfRuinsTalk.AcceptPirateBaseSideChange; the achievement stays in the screen.
procedure ExecuteChangeSide(const Command: TPlayerCommand);
const
  RelationShipTypes = [htRanger, htPirate..htDiplomat];
var
  Event: TGalaxyEvent;
  I, RangerIndex, Cost: Integer;
  Relation: Byte;
  P: TPlayer;
begin
  P := Actor(Command);
  Cost := Galaxy.ComputeScaledHugeMoney(2);
  for I := Galaxy.GalaxyEvents.Count - 1 downto 0 do
  begin
    if TGalaxyEvent(Galaxy.GalaxyEvents[I]).Turn + 365 < Galaxy.CurrentTurn then
      Break;
    if TGalaxyEvent(Galaxy.GalaxyEvents[I]).EventType = 'PlayerChangesSide' then
      Cost := Min(Int64(100000000), Round(Cost * 1.5));
  end;
  // CHANGE: BUGFIX - The command carries the price the screen quoted (a log from before has
  // none, and pays the price as it stands). Every side change in the last year raises the
  // price, also another human's between days, and the money stopped at 0
  // (docs/network.md, Commands). The price was computed after the side changed; it does not
  // depend on it.
  if (Length(Command.Ints) > 0) and (Cost > IntArg(Command, 0)) then
    raise ECommandRefused.CreateReason(rrOfferGone, 'ChangeSide: the price went up');
  if (Length(Command.Ints) > 0) and (P.Money < Cost) then
    raise ECommandRefused.CreateReason(rrNoMoney, 'ChangeSide: not enough money');
  if P.OwnerId = Byte(oiPirate) then
    P.OwnerId := RaceToOwner(P.PilotRace)
  else
    P.OwnerId := Byte(oiPirate);
  StationAmount := Cost;
  P.SetMoney(P.Money - Cost);
  Inc(P.SideChangeCount);
  RangerIndex := Galaxy.Rangers.IndexOf(P);
  if MainPiratePlanet <> nil then
    Relation := Byte(MainPiratePlanet.RangerRelations[RangerIndex])
  else
    Relation := 0;
  if P.OwnerId = Byte(oiPirate) then
  begin
    if (Relation < 45) and (MainPiratePlanet <> nil) then
      MainPiratePlanet.RangerRelations[RangerIndex] := Pointer(45);
    P.ChangeShipRelations(
        nil,
        rcmRaiseTo,
        45,
        RelationShipTypes,
        TOwnerMask(PlanetOwnerMasks.PirateClan)
    );
    P.ChangePlanetRelations(nil, rcmCapAt, 20, TOwnerMask(PlanetOwnerMasks.Coalition));
    P.ChangeShipRelations(
        nil,
        rcmCapAt,
        20,
        RelationShipTypes,
        TOwnerMask(PlanetOwnerMasks.Coalition)
    );
  end
  else
  begin
    P.ChangePlanetRelations(nil, rcmRaiseTo, 45, TOwnerMask(PlanetOwnerMasks.Coalition));
    P.ChangeShipRelations(
        nil,
        rcmRaiseTo,
        45,
        RelationShipTypes,
        TOwnerMask(PlanetOwnerMasks.Coalition)
    );
    if (Relation > 20) and (MainPiratePlanet <> nil) then
      MainPiratePlanet.RangerRelations[RangerIndex] := Pointer(20);
    P.ChangeShipRelations(
        nil,
        rcmCapAt,
        20,
        RelationShipTypes,
        TOwnerMask(PlanetOwnerMasks.PirateClan)
    );
  end;
  Event := AddGalaxyEvent('PlayerChangesSide');
  Event.AddData(Ord(P.OwnerId = Byte(oiPirate)));
end;

procedure ChangeSide(QuotedCost: Integer);
begin
  SubmitInt(ckChangeSide, QuotedCost);
end;

// Moved from TfRuinsTalk.BuyPirateBaseNodes.
procedure ExecuteBuyPirateNodes(const Command: TPlayerCommand);
var
  Count, Cost, DiscountedCost: Integer;
  Stack: TProtoplasm;
  Item: TItem;
  I: Integer;
  NewStack: Boolean;
  Discount: Byte;
  P: TPlayer;
begin
  P := Actor(Command);
  // CHANGE: BUGFIX - As the screen offers them (TfRuinsTalk.ShowPirateBaseNodeDialog): while
  // the base has nodes, for money the human has. Between days another human may have bought
  // the reserve, and this purchase paid for none (docs/network.md, Commands).
  if P.DockedTo.NodeReserve <= 0 then
    raise ECommandRefused.CreateReason(rrOutOfStock, 'BuyPirateNodes: the base has no nodes');
  Count := (P.DockedTo as TRuins).GetNodeSaleBatchSize;
  Cost := Galaxy.ScaleGoodsPriceByGalaxyAge(Count * 10 * 3);
  Discount := P.GetPirateServiceDiscount;
  DiscountedCost := Max(Int64(1), Cost - Round(Cost / 100 * Discount));
  if P.Money < DiscountedCost then
    raise ECommandRefused.CreateReason(rrNoMoney, 'BuyPirateNodes: not enough money');
  P.SetMoney(P.Money - DiscountedCost);
  Dec(P.DockedTo.NodeReserve, Count);
  P.AddPirateCareerActivity(4);
  NewStack := True;
  for I := 1 to P.Inventory.Count - 1 do
  begin
    Item := P.Inventory[I];
    if Item is TProtoplasm then
    begin
      Stack := Item as TProtoplasm;
      Stack.Init(Stack.StackCount + Count, 1);
      NewStack := False;
      Break;
    end;
  end;
  if NewStack then
  begin
    Stack := TProtoplasm.Create;
    Stack.Init(Count, 1);
    P.Inventory.Add(Stack);
  end;
end;

procedure PurchasePirateNodes;
begin
  SubmitSimple(ckBuyPirateNodes);
end;

// Moved from TfRuinsTalk.BuyPirateBaseProgram. Cost is the quote the screen showed.
procedure ExecuteBuyPirateProgram(const Command: TPlayerCommand);
var
  ProgramIndex: Byte;
  Cost, CarriedNodes, BaseNodes: Integer;
  P: TPlayer;
begin
  P := Actor(Command);
  ProgramIndex := IntArg(Command, 0);
  Cost := IntArg(Command, 1);
  CarriedNodes := P.GetAvailableNodeCount(nil);
  StationOutcome := 0;
  // CHANGE: BUGFIX - The nodes kept at the base, which the screen counts when it offers the
  // program and the purchase then takes. The decompiled code read an uninitialised local here,
  // so the outcome depended on the stack (and could differ between a host and its replay).
  BaseNodes := P.BaseNodes;
  if CarriedNodes + BaseNodes >= Cost then
  begin
    if CarriedNodes > 0 then
      P.ConsumeAvailableNodes(Cost, nil);
    if Cost > CarriedNodes then
      P.BaseNodes := Max(0, P.BaseNodes - (Cost - CarriedNodes));
    Inc(P.ProgramCounts[ProgramIndex], PirateProgramBatchSizes[ProgramIndex]);
    P.AddPirateCareerActivity(3);
    StationOutcome := 1;
  end;
end;

function PurchasePirateProgram(ProgramIndex: Byte; Cost: Integer): Boolean;
begin
  SubmitInt2(ckBuyPirateProgram, ProgramIndex, Cost);
  Result := StationOutcome <> 0;
end;

// Moved from TfRuinsTalk.AcceptPirateBaseRepair.
procedure ExecutePirateBaseRepair(const Command: TPlayerCommand);
var
  Cost, DiscountedCost: Integer;
  Discount: Byte;
  I, NodeCost: Integer;
  Item: TEquipment;
  P: TPlayer;
begin
  P := Actor(Command);
  NodeCost := 0;
  for I := 0 to P.Inventory.Count - 1 do
  begin
    Item := P.Inventory[I];
    if Item.EquippedFlag <> 0 then
      if (Item is TWeapon)
          and (TWeapon(Item).GetWeaponInfo.Availability = waNotSoldAndNodeRepair)
          and Item.NeedsRepair then
        if (P.DockedTo as TRuins).CanRepairEquipmentTech(Item) then
          Inc(NodeCost, Item.CalculateRepairCost);
  end;
  if NodeCost > 0 then
  begin
    NodeCost := Round(NodeCost * 0.0025);
    if NodeCost = 0 then
      NodeCost := 1;
  end;
  Cost := (P.DockedTo as TRuins).GetRepairCost(P);
  Discount := P.GetPirateServiceDiscount;
  DiscountedCost := Max(Int64(1), Cost - Round(Cost / 100 * Discount));
  StationOutcome := 0;
  if (P.Money >= DiscountedCost) and (P.GetAvailableNodeCount(nil) >= NodeCost) then
  begin
    P.ConsumeAvailableNodes(NodeCost, nil);
    P.SetMoney(P.Money + (Cost - DiscountedCost));
    (P.DockedTo as TRuins).RepairShipEquipment(P);
    P.RefreshDerivedStats(True);
    P.AddPirateCareerActivity(4);
    StationOutcome := 1;
  end;
end;

function PirateBaseRepair: Boolean;
begin
  SubmitSimple(ckPirateBaseRepair);
  Result := StationOutcome <> 0;
end;

// Moved from TfRuinsTalk.BuyPirateBaseSubCrack and BuyPirateBaseSubCrackHalfPrice.
procedure ExecuteBuySubCrack(const Command: TPlayerCommand);
var
  Cost: Integer;
  P: TPlayer;
begin
  P := Actor(Command);
  if IntArg(Command, 0) = 0 then
  begin
    P.SetMoney(P.Money - P.GetSubCrackCost);
    StationAmount := P.GetSubCrackCost;
    P.ProgramCounts[prgSabCrack] := 1;
  end
  else
  begin
    Cost := P.GetSubCrackCost div 2;
    StationAmount := Cost;
    P.SetMoney(P.Money - Cost);
    P.ProgramCounts[prgSabCrack] := 1;
  end;
end;

function PurchaseSubCrack(HalfPrice: Boolean): Integer;
begin
  SubmitInt(ckBuySubCrack, Ord(HalfPrice));
  Result := StationAmount;
end;

// Moved from TfRuinsTalk.BuyPirateBaseChameleon. Cost is the quote the screen showed.
procedure ExecuteBuyChameleon(const Command: TPlayerCommand);
var
  Series: Byte;
  P: TPlayer;
begin
  P := Actor(Command);
  Series := IntArg(Command, 0);
  Inc(P.ChameleonCharges[Series]);
  PayClampedMoney(P, IntArg(Command, 1));
end;

procedure PurchaseChameleon(Series: Byte; Cost: Integer);
begin
  SubmitInt2(ckBuyChameleon, Series, Cost);
end;

{ The military base }

// Moved from TfRuinsTalk.AcceptMilitaryBaseRepair.
procedure ExecuteMilitaryBaseRepair(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  (P.DockedTo as TRuins).RepairShipEquipment(P);
  P.RefreshDerivedStats(True);
end;

procedure MilitaryBaseRepair;
begin
  SubmitSimple(ckMilitaryBaseRepair);
end;

// Moved from TfRuinsTalk.AcceptMilitaryBasePrograms.
procedure ExecuteCollectMilitaryPrograms(const Command: TPlayerCommand);
var
  I: Byte;
  P: TPlayer;
begin
  P := Actor(Command);
  for I := Low(ProgramNames) to High(ProgramNames) do
    if P.ProgramRewardStocks[I] > 0 then
    begin
      Inc(P.ProgramCounts[I], P.ProgramRewardStocks[I]);
      P.ProgramRewardStocks[I] := 0;
    end;
  P.LastDominatorProgramRewardTurn := Galaxy.CurrentTurn;
  P.DestroyedDominatorHullMass := 0;
end;

procedure CollectMilitaryPrograms;
begin
  SubmitSimple(ckCollectMilitaryPrograms);
end;

// Moved from TfRuinsTalk.AcceptMilitaryBaseWarOperation. The costs are the quotes the
// screen showed.
procedure ExecuteOrderLiberationOperation(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  if Galaxy.TryCreateLiberationGroup then
  begin
    P.SetMoney(P.Money - IntArg(Command, 0));
    P.StationServiceLastUseTurns[cpWarOperation] := Galaxy.CurrentTurn;
    P.ChangePlanetRelations(nil, rcmIncrease, 25, [0]);
    P.ChangePlanetRelations(nil, rcmIncrease, 15, [2, 3, 4]);
    P.ChangePlanetRelations(nil, rcmIncrease, 5, [1]);
    StationOutcome := 1;
  end
  else
  begin
    P.SetMoney(P.Money - IntArg(Command, 1));
    StationOutcome := 0;
  end;
end;

function OrderLiberationOperation(Cost, FailureCost: Integer): Boolean;
begin
  SubmitInt2(ckOrderLiberationOperation, Cost, FailureCost);
  Result := StationOutcome <> 0;
end;

{ The science base }

// Moved from TfRuinsTalk.AcceptScienceBaseImprovement.
procedure ExecuteImproveEquipment(const Command: TPlayerCommand);
var
  Item: TEquipment;
  Kind: TImprovementKind;
  Cost, Nodes: Integer;
  P: TPlayer;
begin
  P := Actor(Command);
  Item := EquipmentArg(Command, 0);
  Kind := TImprovementKind(IntArg(Command, 0));
  Cost := Item.CalculateImprovementCost(Kind);
  if Item.OwnerId = Byte(oiDominator) then
    Nodes := Round(Cost * 0.01)
  else
    Nodes := 0;
  StationOutcome := 0;
  if (P.Money >= Cost) and (P.GetAvailableNodeCount(nil) >= Nodes) then
  begin
    P.SetMoney(P.Money - Cost);
    if Item.OwnerId = Byte(oiDominator) then
      P.ConsumeAvailableNodes(Nodes, nil);
    Item.DetailImprovement := IntArg(Command, 1);
    Item.Improve(Kind);
    P.RefreshDerivedStats(True);
    StationOutcome := 1;
  end;
end;

function ImproveEquipment(Item: TEquipment; Kind: TImprovementKind; Detail: Integer): Boolean;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckImproveEquipment);
  AddRef(Command, Item);
  AddInt(Command, Ord(Kind));
  AddInt(Command, Detail);
  SubmitCommand(Command);
  Result := StationOutcome <> 0;
end;

// Moved from TfRuinsTalk.AcceptScienceBaseRepair.
procedure ExecuteScienceBaseRepair(const Command: TPlayerCommand);
var
  I, NodeCost: Integer;
  Item: TEquipment;
  P: TPlayer;
begin
  P := Actor(Command);
  NodeCost := 0;
  for I := 0 to P.Inventory.Count - 1 do
  begin
    Item := P.Inventory[I];
    if Item.EquippedFlag <> 0 then
      if (Item is TWeapon)
          and (TWeapon(Item).GetWeaponInfo.Availability = waNotSoldAndNodeRepair)
          and Item.NeedsRepair then
        if (P.DockedTo as TRuins).CanRepairEquipmentTech(Item) then
          Inc(NodeCost, Item.CalculateRepairCost);
  end;
  if NodeCost > 0 then
  begin
    NodeCost := Round(NodeCost * 0.0025);
    if NodeCost = 0 then
      NodeCost := 1;
  end;
  StationOutcome := 0;
  if P.GetAvailableNodeCount(nil) >= NodeCost then
  begin
    P.ConsumeAvailableNodes(NodeCost, nil);
    (P.DockedTo as TRuins).RepairShipEquipment(P);
    P.RefreshDerivedStats(True);
    StationOutcome := 1;
  end;
end;

function ScienceBaseRepair: Boolean;
begin
  SubmitSimple(ckScienceBaseRepair);
  Result := StationOutcome <> 0;
end;

// Moved from TfRuinsTalk.BuyScienceBaseSatellite.
procedure ExecuteBuySatellite(const Command: TPlayerCommand);
var
  Satellite: TSatellite;
  P: TPlayer;
begin
  P := Actor(Command);
  Satellite := (P.DockedTo as TRuins).SatelliteOffer;
  // CHANGE: BUGFIX - The command names the offer the screen showed and its price (a log from
  // before has neither, and buys the offer as it stands). Between days another human may have
  // bought it, and the station offers another one, which the player did not accept; nothing
  // checked the money either (docs/network.md, Commands).
  if Length(Command.Ints) >= 2 then
  begin
    if (Satellite = nil)
        or (Integer(Satellite.Id) <> IntArg(Command, 0))
        or (Satellite.Cost <> IntArg(Command, 1)) then
      raise ECommandRefused.CreateReason(rrOfferGone, 'BuySatellite: the offer changed');
    if Galaxy.CountExistingSatellites >= P.GetSatelliteLimit then
      raise ECommandRefused.CreateReason(rrOfferGone, 'BuySatellite: no more satellites allowed');
    if P.Money < Satellite.Cost then
      raise ECommandRefused.CreateReason(rrNoMoney, 'BuySatellite: not enough money');
  end;
  P.SetMoney(P.Money - Satellite.Cost);
  P.Inventory.Add(Satellite);
  (P.DockedTo as TRuins).SatelliteOffer := nil;
  (P.DockedTo as TRuins).RegenerateSatelliteOffer;
end;

procedure PurchaseSatellite;
var
  Satellite: TItem;
begin
  Satellite := (LocalPlayer.DockedTo as TRuins).SatelliteOffer;
  SubmitInt2(ckBuySatellite, Integer(Satellite.Id), Satellite.Cost);
end;

// Moved from TfRuinsTalk.IsResearchItemQuestLetter.
function IsResearchItemQuestLetter(P: TPlayer; Item: TItem): Boolean;
var
  I, J: Integer;
  Quest: PQuest;
begin
  Result := False;
  if (Item is TUselessItem) and (Item.ScriptItem = nil) then
    for I := 0 to P.Quests.Count - 1 do
    begin
      Quest := P.Quests[I];
      if Quest.QuestType = qtSendLetter then
        if LocalizedColorText(
                WideString('Quest.SendLetter.' + IntToStr(Quest.QuestNumber) + '.SysName'))
            = (Item as TUselessItem).ConfigBlockName then
          Result := True;
    end;
  // CHANGE: ENHANCEMENT - Or the letter of another human's quest: the quests are shared
  // (docs/humans.md, Quests), and any human may carry the letter.
  if not Result and (Item is TUselessItem) and (Item.ScriptItem = nil) and QuestsShared(P) then
    for J := 0 to Session.Humans.Count - 1 do
      if (Session.Humans[J].Player <> nil) and (Session.Humans[J].Player <> P) then
        for I := 0 to Session.Humans[J].Player.Quests.Count - 1 do
        begin
          Quest := Session.Humans[J].Player.Quests[I];
          if Quest.QuestType = qtSendLetter then
            if LocalizedColorText(
                    WideString('Quest.SendLetter.' + IntToStr(Quest.QuestNumber) + '.SysName'))
                = (Item as TUselessItem).ConfigBlockName then
              Result := True;
        end;
end;

// Moved from TfRuinsTalk.SellResearchRemains.
procedure ExecuteSellResearchRemains(const Command: TPlayerCommand);
var
  Money, I: Integer;
  Item: TEquipment;
  SelectedResearchSeries: Byte;
  P: TPlayer;
begin
  P := Actor(Command);
  SelectedResearchSeries := IntArg(Command, 0);
  Money := 0;
  for I := P.Inventory.Count - 1 downto 0 do
  begin
    Item := P.Inventory[I];
    if (Item.OwnerId = Byte(oiDominator))
        and (Item.DominatorSeries = TDominatorSeries(SelectedResearchSeries))
        and (Item.NoDropFlag = 0)
        and (Item is TUselessItem) then
      if not IsResearchItemQuestLetter(P, Item as TUselessItem) and (Item.CustomFaction = '') then
      begin
        Inc(Galaxy.DominatorResearch[SelectedResearchSeries].Material, Item.Weight);
        Inc(Money, 2 * Item.Cost);
        P.Inventory.Delete(I);
        Item.Free;
      end;
  end;
  P.SetMoney(P.Money + Money);
  P.RefreshDerivedStats(True);
  StationAmount := Money;
end;

function SellAllResearchRemains(Series: Byte): Integer;
begin
  SubmitInt(ckSellResearchRemains, Series);
  Result := StationAmount;
end;

// Moved from TfRuinsTalk.SellResearchEquipment.
procedure ExecuteSellResearchEquipment(const Command: TPlayerCommand);
var
  Money, I: Integer;
  Item: TEquipment;
  SelectedResearchSeries: Byte;
  P: TPlayer;
begin
  P := Actor(Command);
  SelectedResearchSeries := IntArg(Command, 0);
  Money := 0;
  for I := P.Inventory.Count - 1 downto 0 do
  begin
    Item := P.Inventory[I];
    if (Item.OwnerId = Byte(oiDominator))
        and not (Item is TUselessItem)
        and (Item.EquippedFlag = 0)
        and (Item.NoDropFlag = 0)
        and (Item.ItemType <> t_Protoplasm)
        and (Item.ItemType <> t_MicroModule)
        and (Item.CustomFaction = '') then
    begin
      Inc(Galaxy.DominatorResearch[SelectedResearchSeries].Material, Item.Weight);
      Inc(Money, Item.Cost);
      P.Inventory.Delete(I);
      Item.Free;
    end;
  end;
  P.SetMoney(P.Money + Money);
  P.RefreshDerivedStats(True);
  StationAmount := Money;
end;

function SellAllResearchEquipment(Series: Byte): Integer;
begin
  SubmitInt(ckSellResearchEquipment, Series);
  Result := StationAmount;
end;

// Moved from TfRuinsTalk.SellResearchItem, which named the item by its index in the hold.
procedure ExecuteSellResearchItem(const Command: TPlayerCommand);
var
  Money: Integer;
  Item: TEquipment;
  SelectedResearchSeries: Byte;
  P: TPlayer;
begin
  P := Actor(Command);
  SelectedResearchSeries := IntArg(Command, 0);
  Item := EquipmentArg(Command, 0);
  if P.Inventory.IndexOf(Item) < 0 then
    raise Exception.Create(CommandKindName(Command.Kind) + ' names an item not in the hold');
  Inc(Galaxy.DominatorResearch[SelectedResearchSeries].Material, Item.Weight);
  if (Item.DominatorSeries = TDominatorSeries(SelectedResearchSeries))
      and (Item is TUselessItem) then
    Money := Item.Cost * 2
  else
    Money := Item.Cost;
  P.SetMoney(P.Money + Money);
  P.Inventory.Delete(P.Inventory.IndexOf(Item));
  P.RefreshDerivedStats(True);
  Item.Free;
  StationAmount := Money;
end;

function SellOneResearchItem(Series: Byte; Item: TEquipment): Integer;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckSellResearchItem);
  AddInt(Command, Series);
  AddRef(Command, Item);
  SubmitCommand(Command);
  Result := StationAmount;
end;

// Moved from TfRuinsTalk.AcceptScienceBaseResearchProgram. Cost is the quote the screen
// showed.
procedure ExecuteBuyResearchProgram(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  P.SetMoney(P.Money - IntArg(Command, 1));
  case IntArg(Command, 0) of
    Ord(dsBlazer): P.ProgramCounts[prgLogicalNegation] := 1;
    Ord(dsKeller): P.ProgramCounts[prgDematerial] := 1;
    Ord(dsTerron): P.ProgramCounts[prgEnergotron] := 1;
  end;
end;

procedure PurchaseResearchProgram(Series: Byte; Cost: Integer);
begin
  SubmitInt2(ckBuyResearchProgram, Series, Cost);
end;

{ The business center }

// Moved from TfRuinsTalk.AcceptBusinessCenterDebtQuote. The amount and the due turn are the
// quote the screen showed.
procedure ExecuteTakeLoan(const Command: TPlayerCommand);
var
  Amount: Integer;
  P: TPlayer;
begin
  P := Actor(Command);
  Amount := IntArg(Command, 1);
  StationOutcome := 0;
  case IntArg(Command, 0) of
    1:
    begin
      P.DebtAmount := Round(Amount * 1.2);
      P.DebtDueTurn := IntArg(Command, 2);
    end;
    2:
    begin
      P.DebtAmount := Round(Amount * 1.15);
      P.DebtDueTurn := IntArg(Command, 2);
    end;
    3:
    begin
      P.DebtAmount := Round(Amount * 1.1);
      P.DebtDueTurn := IntArg(Command, 2);
    end;
  else
    Exit;
  end;
  P.DebtDefaultCount := 0;
  P.SetMoney(P.Money + Amount);
  StationOutcome := 1;
end;

function TakeLoan(Quote, Amount, DueTurn: Integer): Boolean;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckTakeLoan);
  AddInt(Command, Quote);
  AddInt(Command, Amount);
  AddInt(Command, DueTurn);
  SubmitCommand(Command);
  Result := StationOutcome <> 0;
end;

// Moved from TfRuinsTalk.RepayBusinessCenterDebt.
procedure ExecuteRepayLoan(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  P.DebtDefaultCount := 0;
  P.SetMoney(P.Money - P.DebtAmount);
  P.DebtAmount := 0;
  P.DebtDueTurn := 0;
end;

procedure RepayLoan;
begin
  SubmitSimple(ckRepayLoan);
end;

// Moved from TfRuinsTalk.AcceptBusinessCenterDepositQuote. The amount and the rate are the
// quote the screen showed.
procedure ExecuteOpenDeposit(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  // CHANGE: BUGFIX - The screen offers only a deposit the human can pay
  // (TfRuinsTalk.ShowBusinessCenterDepositDialog). The deposit kept the amount while the
  // payment stopped at the money there was, which made money (docs/network.md, Commands).
  if (IntArg(Command, 0) < 0) or (P.Money < IntArg(Command, 0)) then
    raise ECommandRefused.CreateReason(rrNoMoney, 'OpenDeposit: not enough money');
  P.DepositAmount := Round(IntArg(Command, 0));
  P.DepositInterestRate := FloatArg(Command, 1);
  P.DepositDayCount := 0;
  P.DepositStartTurn := Galaxy.CurrentTurn;
  PayDepositMoney(P);
end;

procedure OpenDeposit(Amount: Integer; InterestRate: Single);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckOpenDeposit);
  AddInt(Command, Amount);
  AddFloat(Command, InterestRate);
  SubmitCommand(Command);
end;

// Moved from TfRuinsTalk.WithdrawBusinessCenterDeposit; the achievement check stays in the
// screen.
procedure ExecuteCloseDeposit(const Command: TPlayerCommand);
var
  Profit: Integer;
  P: TPlayer;
begin
  P := Actor(Command);
  StationOutcome := 0;
  if P.CurrentStar.Battle <> 0 then
    Exit;
  Profit := P.ComputeDepositAccruedValue - P.DepositAmount;
  P.SetMoney(P.Money + P.ComputeDepositAccruedValue);
  StationAmount := Profit;
  P.DepositAmount := 0;
  P.DepositStartTurn := 0;
  P.DepositDayCount := 0;
  P.DepositInterestRate := 0;
  StationOutcome := 1;
end;

function CloseDeposit: Boolean;
begin
  SubmitSimple(ckCloseDeposit);
  Result := StationOutcome <> 0;
end;

// Moved from TfRuinsTalk.BuyBusinessCenterMedicalPolicy.
procedure ExecuteBuyMedicalPolicy(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  P.SetMoney(P.Money - Galaxy.ComputeScaledAverageMoney(2));
  P.MedicalPolicyTicks := 1825;
end;

procedure PurchaseMedicalPolicy;
begin
  SubmitSimple(ckBuyMedicalPolicy);
end;

// CHANGE: BUGFIX - The rules TfRuinsTalk.ShowBusinessCenterInvestmentDialog offers an
// investment by, as they stand now: the service is not used again too soon, the money is
// there, and a new station's star and constellation still have no station of its kind and
// room for one. Between days two humans could invest in the same new station from their
// copies, and the galaxy got two (docs/network.md, Commands). The screen also scores the
// stars; a star it chose that still passes these is kept.
procedure CheckInvestment(P: TPlayer; Kind: Byte; Cost: Integer; Star: TStar);
const
  StationTypes = [Ord(rstRangerCenter)..Ord(rstDominion)];
var
  StationType: Byte;
  Crowded: Boolean;
  MaximumStations: Integer;
begin
  if P.StationServiceLastUseTurns[Kind] > Galaxy.CurrentTurn - StationServiceRepeatPeriods[Kind] then
    raise ECommandRefused.CreateReason(rrOfferGone, 'Invest: the service was used too recently');
  if P.Money < Cost then
    raise ECommandRefused.CreateReason(rrNoMoney, 'Invest: not enough money');
  if Kind > cpCreateMedicalBase then
    Exit;
  if Star = nil then
    raise ECommandRefused.CreateReason(rrTargetGone, 'Invest: no star for the new station');
  MaximumStations := 1;
  case Kind of
    cpCreateRangerCenter:
    begin
      StationType := Ord(rstRangerCenter);
      Crowded :=
          Galaxy.ShipTypeCounts[StationType] > Galaxy.CountFactionStars(Ord(sfCoalition)) * 0.33;
      MaximumStations := 2;
    end;
    cpCreatePirateBase:
    begin
      StationType := Ord(rstPirateBase);
      Crowded :=
          Galaxy.ShipTypeCounts[StationType] > Galaxy.CountFactionStars(Ord(sfCoalition)) * 0.22;
    end;
    cpCreateMilitaryBase:
    begin
      StationType := Ord(rstMilitaryBase);
      Crowded :=
          Galaxy.ShipTypeCounts[StationType] > Galaxy.CountFactionStars(Ord(sfCoalition)) * 0.22;
    end;
    cpCreateScienceBase:
    begin
      StationType := Ord(rstScienceBase);
      Crowded :=
          Galaxy.ShipTypeCounts[StationType] > Galaxy.CountFactionStars(Ord(sfCoalition)) * 0.15;
    end;
    cpCreateBusinessCenter:
    begin
      StationType := Ord(rstBusinessCenter);
      Crowded :=
          Galaxy.ShipTypeCounts[StationType] > Galaxy.CountFactionStars(Ord(sfCoalition)) * 0.1;
    end;
  else
    StationType := Ord(rstMedicalBase);
    Crowded :=
        Galaxy.ShipTypeCounts[StationType] > Galaxy.CountFactionStars(Ord(sfCoalition)) * 0.15;
  end;
  if Crowded
      or (Star.Constellation.ShipTypeCounts[StationType] > 0)
      or (Star.Constellation.CountShipsByTypeMask(StationTypes) >= Star.Constellation.Stars.Count)
      or (Star.ShipTypeCounts[StationType] > 0)
      or (Star.CountShipsByTypeMask(StationTypes) > MaximumStations) then
    raise ECommandRefused.CreateReason(
        rrOfferGone,
        Format('Invest: star %d has no room for the station any more', [Star.Id])
    );
end;

// Moved from TfRuinsTalk.AcceptBusinessCenterInvestment. The cost and the star or planet are
// the quote the screen showed; the achievements stay in the screen.
procedure ExecuteInvest(const Command: TPlayerCommand);
const
  RangerTypes = [htRanger];
  FriendlyTypes = [htRanger, htTransport..htDiplomat];
  PirateTypes = [htPirate];
  TransportTypes = [htRanger..15] - [htRanger..htPirate, htDiplomat..15];
var
  Kind: Byte;
  RangerCenter, PirateBase, MilitaryBase, ScienceBase, BusinessCenter, MedicalBase: TRuins;
  I, J, Experience, RankPoints, Count, Cost: Integer;
  Star: TStar;
  Ship: TShip;
  Ranger: TRanger;
  Warrior: TWarrior;
  Text, ShipNames, DialogText: WideString;
  Target: TObject;
  TargetStar: TStar;
  TargetPlanet: TPlanet;
  P: TPlayer;
begin
  P := Actor(Command);
  Kind := IntArg(Command, 0);
  Cost := IntArg(Command, 1);
  Target := RefObject(Command, 0);
  TargetStar := nil;
  TargetPlanet := nil;
  if Target is TStar then
    TargetStar := TStar(Target)
  else if Target is TPlanet then
    TargetPlanet := TPlanet(Target);
  CheckInvestment(P, Kind, Cost, TargetStar);
  DialogText := '';
  P.StationServiceLastUseTurns[Kind] := Galaxy.CurrentTurn;
  case Kind of
    cpCreateRangerCenter:
    begin
      P.SetMoney(P.Money - Cost);
      RangerCenter := TRuins.Create;
      RangerCenter.Init(rstRangerCenter, TargetStar, '');
      Galaxy.AddPlanetNewsWithPlayerBubble(
          41,
          FormatText3(
              PickLocalizedTextVariant(
                  'GalaxyNews.CreateNewObject.RC',
                  Galaxy.CurrentTurn div 10 * P.DockedTo.Seed
              ),
              '<color=255,240,100>',
              '<Name>',
              RangerCenter.GetName,
              '<Star>',
              RangerCenter.CurrentStar.Name,
              '<Sector>',
              RangerCenter.CurrentStar.Constellation.GetName
          )
      );
      DialogText := LocalizedColorText('FormRuins.BK.Investment.BKAfterInvestment');
      ReplaceTextToken(
          DialogText,
          '<InvestmentText>',
          LocalizedColorText('Investment.' + CoalitionProjectNames[Kind] + '.Text'),
          ''
      );
      ReplaceTextToken(DialogText, '<BK>', P.DockedTo.Name, '<color=255,240,100>');
      ReplaceTextToken(DialogText, '<Name>', RangerCenter.Name, '<color=255,240,100>');
      ReplaceTextToken(DialogText, '<Star>', RangerCenter.CurrentStar.Name, '<color=255,240,100>');
      Experience := SeededRandomIntRange(1000, 1500, RangerCenter.Seed);
      P.GainExperience(Experience, 0);
      ReplaceTextToken(DialogText, '<Point>', IntToStr(Experience), '<color=255,240,100>');
      Galaxy.UpdateConstellationMilitaryStats;
      P.ChangePlanetRelations(nil, rcmIncrease, 10, TOwnerMask(PlanetOwnerMasks.Coalition));
      P.ChangeShipRelations(
          nil,
          rcmIncrease,
          40,
          RangerTypes,
          TOwnerMask(PlanetOwnerMasks.Coalition)
      );
    end;
    cpCreatePirateBase:
    begin
      P.SetMoney(P.Money - Cost);
      PirateBase := TRuins.Create;
      PirateBase.Init(rstPirateBase, TargetStar, '');
      Galaxy.AddPlanetNewsWithPlayerBubble(
          41,
          FormatText3(
              PickLocalizedTextVariant(
                  'GalaxyNews.CreateNewObject.PB',
                  Galaxy.CurrentTurn div 10 * P.DockedTo.Seed
              ),
              '<color=255,240,100>',
              '<Name>',
              PirateBase.GetName,
              '<Star>',
              PirateBase.CurrentStar.Name,
              '<Sector>',
              PirateBase.CurrentStar.Constellation.GetName
          )
      );
      DialogText := LocalizedColorText('FormRuins.BK.Investment.BKAfterInvestment');
      ReplaceTextToken(
          DialogText,
          '<InvestmentText>',
          LocalizedColorText('Investment.' + CoalitionProjectNames[Kind] + '.Text'),
          ''
      );
      ReplaceTextToken(DialogText, '<BK>', P.DockedTo.Name, '<color=255,240,100>');
      ReplaceTextToken(DialogText, '<Name>', PirateBase.Name, '<color=255,240,100>');
      ReplaceTextToken(DialogText, '<Star>', PirateBase.CurrentStar.Name, '<color=255,240,100>');
      Galaxy.UpdateConstellationMilitaryStats;
      P.ChangePlanetRelations(nil, rcmDecreaseWithFloor20, 30, [3, 4]);
      P.ChangePlanetRelations(nil, rcmDecreaseWithFloor20, 10, [0, 2]);
      P.ChangePlanetRelations(nil, rcmIncrease, 20, [1]);
    end;
    cpCreateMilitaryBase:
    begin
      P.SetMoney(P.Money - Cost);
      MilitaryBase := TRuins.Create;
      MilitaryBase.Init(rstMilitaryBase, TargetStar, '');
      Galaxy.AddPlanetNewsWithPlayerBubble(
          41,
          FormatText3(
              PickLocalizedTextVariant(
                  'GalaxyNews.CreateNewObject.WB',
                  Galaxy.CurrentTurn div 10 * P.DockedTo.Seed
              ),
              '<color=255,240,100>',
              '<Name>',
              MilitaryBase.GetName,
              '<Star>',
              MilitaryBase.CurrentStar.Name,
              '<Sector>',
              MilitaryBase.CurrentStar.Constellation.GetName
          )
      );
      DialogText := LocalizedColorText('FormRuins.BK.Investment.BKAfterInvestment');
      if P.OwnerId <> Byte(oiPirate) then
        ReplaceTextToken(
            DialogText,
            '<InvestmentText>',
            LocalizedColorText('Investment.' + CoalitionProjectNames[Kind] + '.Text'),
            ''
        )
      else
        ReplaceTextToken(
            DialogText,
            '<InvestmentText>',
            LocalizedColorText('Investment.' + CoalitionProjectNames[Kind] + '.TextAlt'),
            ''
        );
      ReplaceTextToken(DialogText, '<BK>', P.DockedTo.Name, '<color=255,240,100>');
      ReplaceTextToken(DialogText, '<Name>', MilitaryBase.Name, '<color=255,240,100>');
      ReplaceTextToken(DialogText, '<Star>', MilitaryBase.CurrentStar.Name, '<color=255,240,100>');
      if P.OwnerId <> Byte(oiPirate) then
      begin
        RankPoints := SeededRandomIntRange(50, 200, MilitaryBase.Seed);
        P.AddRankPoints(RankPoints);
        ReplaceTextToken(DialogText, '<Point>', IntToStr(RankPoints), '<color=255,240,100>');
      end;
      Galaxy.UpdateConstellationMilitaryStats;
      P.ChangePlanetRelations(nil, rcmIncrease, 30, TOwnerMask(PlanetOwnerMasks.Coalition));
      P.ChangeShipRelations(
          nil,
          rcmIncrease,
          10,
          FriendlyTypes,
          TOwnerMask(PlanetOwnerMasks.Coalition)
      );
      P.ChangeShipRelations(
          nil,
          rcmDecreaseWithFloor20,
          30,
          PirateTypes,
          TOwnerMask(PlanetOwnerMasks.Coalition)
      );
    end;
    cpCreateScienceBase:
    begin
      P.SetMoney(P.Money - Cost);
      ScienceBase := TRuins.Create;
      ScienceBase.Init(rstScienceBase, TargetStar, '');
      Galaxy.AddPlanetNewsWithPlayerBubble(
          41,
          FormatText3(
              PickLocalizedTextVariant(
                  'GalaxyNews.CreateNewObject.SB',
                  Galaxy.CurrentTurn div 10 * P.DockedTo.Seed
              ),
              '<color=255,240,100>',
              '<Name>',
              ScienceBase.GetName,
              '<Star>',
              ScienceBase.CurrentStar.Name,
              '<Sector>',
              ScienceBase.CurrentStar.Constellation.GetName
          )
      );
      DialogText := LocalizedColorText('FormRuins.BK.Investment.BKAfterInvestment');
      ReplaceTextToken(
          DialogText,
          '<InvestmentText>',
          LocalizedColorText('Investment.' + CoalitionProjectNames[Kind] + '.Text'),
          ''
      );
      ReplaceTextToken(DialogText, '<BK>', P.DockedTo.Name, '<color=255,240,100>');
      ReplaceTextToken(DialogText, '<Name>', ScienceBase.Name, '<color=255,240,100>');
      ReplaceTextToken(DialogText, '<Star>', ScienceBase.CurrentStar.Name, '<color=255,240,100>');
      Galaxy.UpdateConstellationMilitaryStats;
      P.ChangeShipRelations(
          nil,
          rcmIncrease,
          25,
          RangerTypes,
          TOwnerMask(PlanetOwnerMasks.Coalition)
      );
    end;
    cpCreateBusinessCenter:
    begin
      P.SetMoney(P.Money - Cost);
      BusinessCenter := TRuins.Create;
      BusinessCenter.Init(rstBusinessCenter, TargetStar, '');
      Galaxy.AddPlanetNewsWithPlayerBubble(
          41,
          FormatText3(
              PickLocalizedTextVariant(
                  'GalaxyNews.CreateNewObject.BK',
                  Galaxy.CurrentTurn div 10 * P.DockedTo.Seed
              ),
              '<color=255,240,100>',
              '<Name>',
              BusinessCenter.GetName,
              '<Star>',
              BusinessCenter.CurrentStar.Name,
              '<Sector>',
              BusinessCenter.CurrentStar.Constellation.GetName
          )
      );
      DialogText := LocalizedColorText('FormRuins.BK.Investment.BKAfterInvestment');
      ReplaceTextToken(
          DialogText,
          '<InvestmentText>',
          LocalizedColorText('Investment.' + CoalitionProjectNames[Kind] + '.Text'),
          ''
      );
      ReplaceTextToken(DialogText, '<BK>', P.DockedTo.Name, '<color=255,240,100>');
      ReplaceTextToken(DialogText, '<Name>', BusinessCenter.Name, '<color=255,240,100>');
      ReplaceTextToken(
          DialogText,
          '<Star>',
          BusinessCenter.CurrentStar.Name,
          '<color=255,240,100>'
      );
      Galaxy.UpdateConstellationMilitaryStats;
      P.ChangeShipRelations(
          nil,
          rcmIncrease,
          30,
          TransportTypes,
          TOwnerMask(PlanetOwnerMasks.Coalition)
      );
    end;
    cpCreateMedicalBase:
    begin
      P.SetMoney(P.Money - Cost);
      MedicalBase := TRuins.Create;
      MedicalBase.Init(rstMedicalBase, TargetStar, '');
      Galaxy.AddPlanetNewsWithPlayerBubble(
          41,
          FormatText3(
              PickLocalizedTextVariant(
                  'GalaxyNews.CreateNewObject.MC',
                  Galaxy.CurrentTurn div 10 * P.DockedTo.Seed
              ),
              '<color=255,240,100>',
              '<Name>',
              MedicalBase.GetName,
              '<Star>',
              MedicalBase.CurrentStar.Name,
              '<Sector>',
              MedicalBase.CurrentStar.Constellation.GetName
          )
      );
      DialogText := LocalizedColorText('FormRuins.BK.Investment.BKAfterInvestment');
      ReplaceTextToken(
          DialogText,
          '<InvestmentText>',
          LocalizedColorText('Investment.' + CoalitionProjectNames[Kind] + '.Text'),
          ''
      );
      ReplaceTextToken(DialogText, '<BK>', P.DockedTo.Name, '<color=255,240,100>');
      ReplaceTextToken(DialogText, '<Name>', MedicalBase.Name, '<color=255,240,100>');
      ReplaceTextToken(DialogText, '<Star>', MedicalBase.CurrentStar.Name, '<color=255,240,100>');
      Galaxy.UpdateConstellationMilitaryStats;
      P.ChangeShipRelations(
          nil,
          rcmIncrease,
          30,
          FriendlyTypes,
          TOwnerMask(PlanetOwnerMasks.Coalition)
      );
    end;
    cpRangersSubsidy:
    begin
      P.SetMoney(P.Money - Cost);
      Count := 0;
      for I := 1 to Galaxy.Rangers.Count - 1 do
      begin
        Ranger := Galaxy.Rangers[I];
        if (P <> Ranger)
            and not Ranger.ExcludedFromRating
            and (Ranger.Wealth <= Galaxy.AverageRangerCapital) then
          Inc(Count);
      end;
      for I := 1 to Galaxy.Rangers.Count - 1 do
      begin
        Ranger := Galaxy.Rangers[I];
        if (P <> Ranger)
            and not Ranger.ExcludedFromRating
            and (Ranger.Wealth <= Galaxy.AverageRangerCapital) then
          Ranger.SetMoney(Ranger.Money + Round(Cost / Count));
      end;
      Galaxy.AddPlanetNewsWithPlayerBubble(
          42,
          FormatText1(
              PickLocalizedTextVariant(
                  'Investment.' + CoalitionProjectNames[Kind] + '.GalaxyMessage',
                  Kind + Galaxy.CurrentTurn div 10 * P.DockedTo.Seed
              ),
              '<color=255,240,100>',
              '<Money>',
              IntToStr(Cost)
          )
      );
      DialogText := LocalizedColorText('FormRuins.BK.Investment.BKAfterInvestment');
      ReplaceTextToken(
          DialogText,
          '<InvestmentText>',
          LocalizedColorText('Investment.' + CoalitionProjectNames[Kind] + '.Text'),
          ''
      );
      ReplaceTextToken(DialogText, '<BK>', P.DockedTo.Name, '<color=255,240,100>');
      ReplaceTextToken(
          DialogText,
          '<Money>',
          IntToStr(Cost),
          '<color=255,240,100>'
      );
    end;
    cpPiratesSubsidy:
    begin
      P.SetMoney(P.Money - Cost);
      Count := Max(1, Galaxy.ShipTypeCounts[stPirate]);
      for I := 0 to Galaxy.Stars.Count - 1 do
      begin
        Star := Galaxy.Stars[I];
        for J := 0 to Star.Ships.Count - 1 do
        begin
          Ship := Star.Ships[J];
          if Ship.TypeId = stPirate then
            Ship.SetMoney(Ship.Money + Cost div Count);
        end;
      end;
      Galaxy.AddPlanetNewsWithPlayerBubble(
          42,
          FormatText2(
              PickLocalizedTextVariant(
                  'Investment.' + CoalitionProjectNames[Kind] + '.GalaxyMessage',
                  Kind + Galaxy.CurrentTurn div 10 * P.DockedTo.Seed
              ),
              '<color=255,240,100>',
              '<Money>',
              IntToStr(Cost),
              '<BK>',
              P.DockedTo.Name
          )
      );
      DialogText := LocalizedColorText('FormRuins.BK.Investment.BKAfterInvestment');
      ReplaceTextToken(
          DialogText,
          '<InvestmentText>',
          LocalizedColorText('Investment.' + CoalitionProjectNames[Kind] + '.Text'),
          ''
      );
      ReplaceTextToken(DialogText, '<BK>', P.DockedTo.Name, '<color=255,240,100>');
      ReplaceTextToken(
          DialogText,
          '<Money>',
          IntToStr(Cost),
          '<color=255,240,100>'
      );
    end;
    cpTransportSubsidy:
    begin
      P.SetMoney(P.Money - Cost);
      Count := Max(1, Galaxy.ShipTypeCounts[stTransport]);
      for I := 0 to Galaxy.Stars.Count - 1 do
      begin
        Star := Galaxy.Stars[I];
        for J := 0 to Star.Ships.Count - 1 do
        begin
          Ship := Star.Ships[J];
          if Ship.TypeId = stTransport then
            Ship.SetMoney(Ship.Money + Cost div Count);
        end;
      end;
      Galaxy.AddPlanetNewsWithPlayerBubble(
          42,
          FormatText2(
              PickLocalizedTextVariant(
                  'Investment.' + CoalitionProjectNames[Kind] + '.GalaxyMessage',
                  Kind + Galaxy.CurrentTurn div 10 * P.DockedTo.Seed
              ),
              '<color=255,240,100>',
              '<Money>',
              IntToStr(Cost),
              '<BK>',
              P.DockedTo.Name
          )
      );
      DialogText := LocalizedColorText('FormRuins.BK.Investment.BKAfterInvestment');
      ReplaceTextToken(
          DialogText,
          '<InvestmentText>',
          LocalizedColorText('Investment.' + CoalitionProjectNames[Kind] + '.Text'),
          ''
      );
      ReplaceTextToken(DialogText, '<BK>', P.DockedTo.Name, '<color=255,240,100>');
      ReplaceTextToken(
          DialogText,
          '<Money>',
          IntToStr(Cost),
          '<color=255,240,100>'
      );
    end;
    cpLostSubsidy:
    begin
      P.SetMoney(P.Money - Cost);
      Galaxy.AddPlanetNewsWithPlayerBubble(
          42,
          FormatText2(
              PickLocalizedTextVariant(
                  'Investment.' + CoalitionProjectNames[Kind] + '.GalaxyMessage',
                  Kind + Galaxy.CurrentTurn div 10 * P.DockedTo.Seed
              ),
              '<color=255,240,100>',
              '<Money>',
              IntToStr(Cost),
              '<BK>',
              P.DockedTo.Name
          )
      );
      DialogText := LocalizedColorText('FormRuins.BK.Investment.BKAfterInvestment');
      ReplaceTextToken(
          DialogText,
          '<InvestmentText>',
          LocalizedColorText('Investment.' + CoalitionProjectNames[Kind] + '.Text'),
          ''
      );
      ReplaceTextToken(DialogText, '<BK>', P.DockedTo.Name, '<color=255,240,100>');
      ReplaceTextToken(
          DialogText,
          '<Money>',
          IntToStr(Cost),
          '<color=255,240,100>'
      );
      P.ChangePlanetRelations(nil, rcmIncrease, 30, TOwnerMask(PlanetOwnerMasks.Coalition));
      P.ChangeShipRelations(
          nil,
          rcmIncrease,
          20,
          FriendlyTypes,
          TOwnerMask(PlanetOwnerMasks.Coalition)
      );
      P.ChangeShipRelations(
          nil,
          rcmDecreaseWithFloor20,
          20,
          PirateTypes,
          TOwnerMask(PlanetOwnerMasks.Coalition)
      );
    end;
    cpWarSubsidy:
    begin
      P.SetMoney(P.Money - Cost);
      Count :=
          SeededRandomIntRange(
              4,
              7,
              TargetPlanet.GenerationSeed + Galaxy.CurrentTurn div 60
          );
      ShipNames := #13#10;
      for I := 1 to Count do
      begin
        Warrior := TObject(TargetPlanet.BuyWarrior(100)) as TWarrior;
        Warrior.Name := Warrior.Name + ' ' + P.Name;
        ShipNames := ShipNames + Warrior.GetName + #13#10;
      end;
      Text :=
          PickLocalizedTextVariant(
              'Investment.' + CoalitionProjectNames[Kind] + '.GalaxyMessage',
              Kind + Galaxy.CurrentTurn div 10 * P.DockedTo.Seed
          );
      ReplaceTextToken(Text, '<BK>', P.DockedTo.Name, '<color=255,240,100>');
      ReplaceTextToken(Text, '<Count>', IntToStr(Count), '<color=255,240,100>');
      ReplaceTextToken(Text, '<Planet>', TargetPlanet.Name, '<color=255,240,100>');
      ReplaceTextToken(
          Text,
          '<Star>',
          TargetPlanet.CurrentStar.Name,
          '<color=255,240,100>'
      );
      ReplaceTextToken(Text, '<Money>', IntToStr(Cost), '<color=255,240,100>');
      Galaxy.AddPlanetNewsWithPlayerBubble(42, Text);
      DialogText := LocalizedColorText('FormRuins.BK.Investment.BKAfterInvestment');
      ReplaceTextToken(
          DialogText,
          '<InvestmentText>',
          LocalizedColorText('Investment.' + CoalitionProjectNames[Kind] + '.Text'),
          ''
      );
      ReplaceTextToken(DialogText, '<BK>', P.DockedTo.Name, '<color=255,240,100>');
      ReplaceTextToken(DialogText, '<ShipsName>', ShipNames, '');
      ReplaceTextToken(DialogText, '<Count>', IntToStr(Count), '<color=255,240,100>');
      ReplaceTextToken(DialogText, '<Planet>', TargetPlanet.Name, '<color=255,240,100>');
      ReplaceTextToken(
          DialogText,
          '<Star>',
          TargetPlanet.CurrentStar.Name,
          '<color=255,240,100>'
      );
      ReplaceTextToken(
          DialogText,
          '<Money>',
          IntToStr(Cost),
          '<color=255,240,100>'
      );
      TargetPlanet.ChangeRelationToRanger(P, 100);
      P.ChangePlanetRelations(nil, rcmIncrease, 20, TOwnerMask(PlanetOwnerMasks.Coalition));
      P.ChangeShipRelations(
          nil,
          rcmDecreaseWithFloor20,
          30,
          PirateTypes,
          TOwnerMask(PlanetOwnerMasks.Coalition)
      );
    end;
  end;
  StationText := DialogText;
end;

procedure Invest(Kind: Byte; Cost: Integer; Target: TObject);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckInvest);
  AddInt(Command, Kind);
  AddInt(Command, Cost);
  AddRef(Command, Target);
  SubmitTrade(Command);
end;

// Moved from TfRuinsTalk.BuyBusinessCenterTradeAdvice; the screen builds the answer and the
// message.
procedure ExecuteBuyTradeAdvice(const Command: TPlayerCommand);
var
  Text: WideString;
  Count: Integer;
  Paths: WideString;
  Nearby, Found: Boolean;
  P: TPlayer;
  procedure FindBusinessCenterTradeRoutes; // @addr $5CCFE4 @ida "void __cdecl $name(void *ParentFrame);" @calls "0x5CD5F9"
  type
    TRoute = record
      FromPlanet, ToPlanet: TPlanet;
      GoodsIndex: Byte;
    end;
  var
    I, Attempts, J: Integer;
    GoodsMask: TItemTypeMask;
    Routes: array[1..3] of TRoute;
  begin
    GoodsMask := [Ord(t_Food)..Ord(t_Narcotics)];
    for I := Low(Routes) to High(Routes) do
    begin
      Routes[I].FromPlanet := nil;
      Routes[I].ToPlanet := nil;
    end;
    for I := Low(Routes) to High(Routes) do
    begin
      Attempts := 0;
      repeat
        Inc(Attempts);
        if Attempts > 100 then
        begin
          if I = Low(Routes) then
          begin
            Count := 0;
            Paths := '';
          end;
          Exit;
        end;
        Found :=
            P.FindProfitableTradeRoute(
                Nearby,
                AdvanceRandomSeed(Galaxy.RandomState) + Byte(Nearby),
                Routes[I].FromPlanet,
                Routes[I].ToPlanet,
                Routes[I].GoodsIndex,
                GoodsMask
            );
        for J := Low(Routes) to I - 1 do
          if Routes[I].GoodsIndex = Routes[J].GoodsIndex then
            Found := False;
      until Found;
      Exclude(GoodsMask, Routes[I].GoodsIndex);
      Inc(Count);
      Text := LocalizedColorText('FormRuins.BK.Trade.BKFindTradePath');
      ReplaceTextToken(Text, '<Num>', IntToStr(I), '');
      ReplaceTextToken(
          Text,
          '<Goods>',
          GoodsMarket[Routes[I].GoodsIndex].DisplayName,
          '<color=255,240,100>'
      );
      ReplaceTextToken(Text, '<FromPlanet>', Routes[I].FromPlanet.Name, '<color=255,240,100>');
      ReplaceTextToken(
          Text,
          '<FromStar>',
          Routes[I].FromPlanet.CurrentStar.Name,
          '<color=255,240,100>'
      );
      ReplaceTextToken(
          Text,
          '<Buy>',
          IntToStr(P.ShopGoodsPurchasePrice(Routes[I].GoodsIndex, Routes[I].FromPlanet)),
          '<color=255,240,100>'
      );
      ReplaceTextToken(
          Text,
          '<Cnt>',
          IntToStr(Routes[I].FromPlanet.Goods[Routes[I].GoodsIndex].Count),
          '<color=255,240,100>'
      );
      ReplaceTextToken(Text, '<ToPlanet>', Routes[I].ToPlanet.Name, '<color=255,240,100>');
      ReplaceTextToken(
          Text,
          '<ToStar>',
          Routes[I].ToPlanet.CurrentStar.Name,
          '<color=255,240,100>'
      );
      ReplaceTextToken(
          Text,
          '<Sale>',
          IntToStr(P.ShopGoodsSellPrice(Routes[I].GoodsIndex, Routes[I].ToPlanet)),
          '<color=255,240,100>'
      );
      if Paths = '' then
        Paths := Text
      else
        Paths := Paths + #13#10 + Text;
    end;
  end;
begin
  P := Actor(Command);
  Paths := '';
  Count := 0;
  Nearby := IntArg(Command, 0) <> 0;
  FindBusinessCenterTradeRoutes;
  if Count <> 0 then
    P.SetMoney(P.Money - IntArg(Command, 1));
  StationAmount := Count;
  StationText := Paths;
end;

function PurchaseTradeAdvice(Nearby: Boolean; Cost: Integer): Integer;
begin
  SubmitInt2(ckBuyTradeAdvice, Ord(Nearby), Cost);
  Result := StationAmount;
end;

{ The medical center }

// Moved from TfRuinsTalk.ShowMedicalCenterIllnessTreatmentDialog: showing the diseases
// counts them as applied.
procedure ExecuteExamineDiseases(const Command: TPlayerCommand);
var
  I: Integer;
  P: TPlayer;
begin
  P := Actor(Command);
  for I := 1 to 12 do
    if P.CaptainHealth[I].Progress <> 0 then
      if not (P.CaptainHealth[I].Progress >= 100) then
      begin
        Inc(P.CaptainHealth[I].ApplicationCount);
        P.AchievementStats.CheckAllDiseasesAchievement;
      end;
end;

procedure ExamineDiseases;
begin
  SubmitSimple(ckExamineDiseases);
end;

// Moved from TfRuinsTalk.TreatSelectedDiseaseAtMedicalCenter.
procedure ExecuteTreatDisease(const Command: TPlayerCommand);
var
  I, Cost, DiseaseIndex: Integer;
  P: TPlayer;
begin
  P := Actor(Command);
  DiseaseIndex := IntArg(Command, 0);
  for I := 1 to 12 do
    if I = DiseaseIndex then
    begin
      if I = 3 then
      begin
        Galaxy.GraphDominatorSurfacesEnabled := True;
        Galaxy.DisableDominatorSurfaces;
      end;
      P.CaptainHealth[I].Progress := 0;
      P.StatusEffectSourceNames[I] := '';
      Cost :=
          GenerateValueForSizeLevel(
              CaptainHealthDefinitions[I].EffectClass0D,
              Galaxy.ComputeScaledMiniMoney(P.DockedTo.OwnerId),
              Galaxy.ComputeScaledAverageMoney(P.DockedTo.OwnerId),
              50,
              (Galaxy.CurrentTurn div 10) * Galaxy.GenerationSeed * I
          );
      if (P.MedicalPolicyTicks > 0)
          and (P.DockedTo.CurrentStar.ControlFaction <> sfPirates) then
        Cost := Cost div 2;
      P.SetMoney(P.Money - Cost);
      P.DiseaseImmunity := Min(100, P.DiseaseImmunity + 40);
      Break;
    end;
end;

procedure TreatDisease(Index: Integer);
begin
  SubmitInt(ckTreatDisease, Index);
end;

// Moved from TfRuinsTalk.TreatAllDiseasesAtMedicalCenter. Cost is the quote the screen
// showed.
procedure ExecuteTreatAllDiseases(const Command: TPlayerCommand);
var
  I: Integer;
  P: TPlayer;
begin
  P := Actor(Command);
  for I := 1 to 12 do
    if P.CaptainHealth[I].Progress <> 0 then
    begin
      if I = 3 then
      begin
        Galaxy.GraphDominatorSurfacesEnabled := True;
        Galaxy.DisableDominatorSurfaces;
      end;
      P.CaptainHealth[I].Progress := 0;
      P.StatusEffectSourceNames[I] := '';
    end;
  P.SetMoney(P.Money - IntArg(Command, 0));
  P.DiseaseImmunity := Min(100, P.DiseaseImmunity + 80);
end;

procedure TreatAllDiseases(Cost: Integer);
begin
  SubmitInt(ckTreatAllDiseases, Cost);
end;

// Moved from TfRuinsTalk.BuySelectedStimulantAtMedicalCenter.
procedure ExecuteBuyStimulant(const Command: TPlayerCommand);
var
  I, Cost, Duration, StimulantIndex: Integer;
  P: TPlayer;
begin
  P := Actor(Command);
  StimulantIndex := IntArg(Command, 0);
  for I := 13 to 24 do
    if I = StimulantIndex then
    begin
      P.CaptainHealth[I].Progress := 100;
      P.StatusEffectSourceNames[I] := '';
      Duration :=
          CaptainHealthDefinitions[I].Duration
              + SeededRandomIntRange(
                  CaptainHealthDefinitions[I].Duration div 10,
                  CaptainHealthDefinitions[I].Duration div 3,
                  P.DockedTo.Id + I + Galaxy.CurrentTurn div 13);
      Duration :=
          Round(
              Duration / GalaxyDifficultyTuning[Galaxy.DifficultyLevels[7]].GoodsEventDurationFactor
          );
      P.CaptainHealth[I].AppliedTurn := Galaxy.CurrentTurn;
      P.CaptainHealth[I].ExpireTurn := Duration + Galaxy.CurrentTurn;
      Cost :=
          GenerateValueForSizeLevel(
              CaptainHealthDefinitions[I].EffectClass0D,
              Galaxy.ComputeScaledSmallMoney(P.DockedTo.OwnerId),
              2 * Galaxy.ComputeScaledAverageMoney(P.DockedTo.OwnerId),
              50,
              (Galaxy.CurrentTurn div 13) * Galaxy.GenerationSeed * I
          );
      if (P.MedicalPolicyTicks > 0)
          and (P.DockedTo.CurrentStar.ControlFaction <> sfPirates) then
        Cost := Cost div 2;
      P.SetMoney(P.Money - Cost);
      P.DiseaseImmunity := Max(0, P.DiseaseImmunity - 20);
      Inc(P.StimulantPurchaseCount);
      Inc(P.CaptainHealth[I].ApplicationCount);
      P.AchievementStats.CheckAllDrugsAchievement;
      Break;
    end;
end;

procedure PurchaseStimulant(Index: Integer);
begin
  SubmitInt(ckBuyStimulant, Index);
end;

{ The Dominion }

// Moved from TfRuinsTalk.CompleteDominionConstruction. The parts are the ones the player
// picked; an item from the shop is taken out of the station's shop. The screen rebuilds its
// shop controls once for each (the result).
procedure ExecuteBuildPirateShip(const Command: TPlayerCommand);
var
  Parts: TConstructionParts;
  Ship: TPirate;
  Planet: TPlanet;
  TotalCost, Price: Integer;
  I, J, Months, ShopItems: Integer;
  Item: TEquipment;
  P: TPlayer;
  procedure RemoveConstructionStoredItem(
      Item: TEquipment
  ); // @addr $5D432C @ida "void __usercall $name(TEquipment *Item@<eax>, void *ParentFrame@<^0>);" @stackpop 0 @calls "0x5D4540 0x5D45F7"
  var
    I: Integer;
    Entry: PStorageEntry;
  begin
    for I := 0 to P.StorageEntries.Count - 1 do
    begin
      Entry := P.StorageEntries[I];
      if (Entry <> nil) and (Entry.Item = Item) then
      begin
        P.StorageEntries.Delete(I);
        P.RefreshStorageBubbles;
        Dispose(Entry);
        // CHANGE: ENHANCEMENT - The storage is shared: the others' open ship screen there shows it.
        StorageChanged(PlayerStorageLocation(P), HumanOf(P));
        Break;
      end;
    end;
  end;
  procedure RemoveConstructionShopItem(
      Item: TEquipment
  ); // @addr $5D43B4 @ida "void __usercall $name(TEquipment *Item@<eax>, void *ParentFrame@<^0>);" @stackpop 0 @calls "0x5D454C 0x5D4603"
  var
    Station: TRuins;
  begin
    Station := TRuins(P.DockedTo);
    if ActorHuman(Command).TemporaryShopSlots <> nil then
    begin
      // CHANGE: ENHANCEMENT - ReturnShopStock and OpenShopStock as they run inside this
      // command; the screen rebuilds the shop controls after it.
      RestoreTemporaryShopStock(ActorHuman(Command));
      Station.EquipmentShop.Delete(Station.EquipmentShop.IndexOf(Item));
      // CHANGE: BUGFIX - The actor's columns, not this machine's (THuman.ShopColumnCount).
      ActorHuman(Command).ShopColumnCount := IntArg(Command, 2 * ConstructionPartCount);
      BuildTemporaryShopSlotGrid(ActorHuman(Command));
      Inc(ShopItems);
    end
    // CHANGE: BUGFIX - The stock stays in the station's list while no grid shows it
    // (aShopStock): the part leaves it, and the grids of other humans there.
    else
      TakeShopStockItem(ActorHuman(Command), Station, Item);
  end;
  // Whether the part is still where the screen found it: the actor's hold or storage, or the
  // station's shop.
  function IsPartAvailable(const Part: TConstructionPart): Boolean;
  var
    I: Integer;
    Entry: PStorageEntry;
  begin
    if Part.Source = 0 then
      Exit(P.Inventory.IndexOf(Part.Item) >= 0);
    if Part.Source = 1 then
    begin
      for I := 0 to P.StorageEntries.Count - 1 do
      begin
        Entry := P.StorageEntries[I];
        if (Entry <> nil) and (Entry.Item = Part.Item) then
          Exit(True);
      end;
      Exit(False);
    end;
    Result :=
        (P.DockedTo is TRuins)
            and (FindShopStockItem(P.DockedTo, Integer(Part.Item.Id)) = TItem(Part.Item));
  end;
begin
  P := Actor(Command);
  ShopItems := 0;
  // Every part is found before any is taken: taking one from the shop rebuilds the shop grid.
  for I := 0 to ConstructionPartCount - 1 do
  begin
    Parts[I].Source := IntArg(Command, 2 * I);
    if IntArg(Command, 2 * I + 1) = 0 then
      Parts[I].Item := nil
    else
    begin
      Parts[I].Item := TEquipment(Galaxy.IdToItem(Cardinal(IntArg(Command, 2 * I + 1)), False));
      if Parts[I].Item = nil then
        raise ECommandRefused.CreateReason(
            rrItemGone,
            CommandKindName(Command.Kind) + ' names a missing part'
        );
    end;
  end;
  // CHANGE: BUGFIX - Every part must still be where the screen found it, once, and the shop's
  // parts paid for, before anything changes. Between days another human may have bought a
  // shop part or built with it first (docs/network.md, Commands): native paid, then put a
  // part already in another ship into this one too, or raised halfway when it was missing.
  for I := 0 to ConstructionPartCount - 1 do
    if Parts[I].Item <> nil then
    begin
      for J := 0 to I - 1 do
        if Parts[J].Item = Parts[I].Item then
          raise ECommandRefused.CreateReason(
              rrItemGone,
              CommandKindName(Command.Kind) + ' names a part twice'
          );
      if not IsPartAvailable(Parts[I]) then
        raise ECommandRefused.CreateReason(
            rrItemGone,
            Format('%s: part %d is gone', [CommandKindName(Command.Kind), Parts[I].Item.Id])
        );
    end;
  Price := 0;
  for I := 0 to ConstructionPartCount - 1 do
    if (Parts[I].Item <> nil) and (Parts[I].Source = 2) then
      Inc(Price, Parts[I].Item.Cost);
  if Price > P.Money then
    raise ECommandRefused.CreateReason(
        rrNoMoney,
        CommandKindName(Command.Kind) + ': the parts cost more than the money'
    );
  if Price > 0 then
    PayClampedMoney(P, Price);
  Ship := TPirate.Create;
  Planet := P.DockedTo.CurrentStar.SelectRandomInhabitedPlanet;
  TotalCost := 0;
  for I := 0 to ConstructionPartCount - 1 do
    if Parts[I].Item <> nil then
    begin
      Item := Parts[I].Item;
      if Parts[I].Source = 0 then
        P.Inventory.Delete(P.Inventory.IndexOf(Item))
      else if Parts[I].Source = 1 then
        RemoveConstructionStoredItem(Item)
      else
        RemoveConstructionShopItem(Item);
      Ship.Inventory.Add(Item);
      Ship.EquipItem(Item);
      Inc(TotalCost, Parts[I].Item.Cost);
    end;
  Ship.InitGenerated(Planet, TotalCost div 10 + 1000, 0);
  Ship.DockedTo := P.DockedTo;
  Ship.TrainSkillsAutomatically;
  Ship.RefreshEquipmentEvaluationMetrics;
  Ship.ChangeRelationToRanger(P, 100);
  if P.GetMaxDominionShips > P.PiratePartners.Count then
  begin
    Ship.PartnerShip := P;
    Months := Ship.CalculatePartnershipMonths(TotalCost, Ship);
    Ship.PartnershipDaysRemaining := 30 * Months;
    P.PiratePartners.Add(Ship);
    P.AchievementStats.CheckMasterAchievement;
    StationOutcome := 1;
  end
  else
  begin
    Months := 0;
    StationOutcome := 0;
  end;
  StationText := Ship.GetFullName(' ');
  StationAmount := Months;
  StationText2 := IntToStr(ShopItems);
end;

function BuildPirateShip(const Parts: TConstructionParts): Integer;
var
  Command: TPlayerCommand;
  I: Integer;
begin
  Command := NewCommand(ckBuildPirateShip);
  for I := 0 to ConstructionPartCount - 1 do
  begin
    AddInt(Command, Parts[I].Source);
    if Parts[I].Item = nil then
      AddInt(Command, 0)
    else
      AddInt(Command, Integer(Parts[I].Item.Id));
  end;
  AddInt(Command, ShopVisibleColumnCount);
  SubmitTrade(Command);
  Result := StrToInt(StationText2);
end;

// Moved from TfRuinsTalk.AcceptDominionImprovement.
procedure ExecuteImproveAtDominion(const Command: TPlayerCommand);
var
  Item: TEquipment;
  Cost, Nodes: Integer;
  Discount: Byte;
  P: TPlayer;
begin
  P := Actor(Command);
  Discount := P.GetPirateServiceDiscount;
  Item := EquipmentArg(Command, 0);
  Cost := Item.CalculateImprovementCost(ikMajor);
  if Item.OwnerId = Byte(oiDominator) then
    Nodes := Round(Cost * 0.01 * 1.5 * (100 - Discount) / 100)
  else
    Nodes := 0;
  Cost := Round(Cost * (100 - Discount) / 100);
  StationOutcome := 0;
  if (P.Money >= Cost) and (P.GetAvailableNodeCount(nil) >= Nodes) then
  begin
    P.SetMoney(P.Money - Cost);
    if Item.OwnerId = Byte(oiDominator) then
      P.ConsumeAvailableNodes(Nodes, nil);
    Item.ImproveAtScientificBase;
    P.RefreshDerivedStats(True);
    StationOutcome := 1;
  end;
end;

function ImproveAtDominion(Item: TEquipment): Boolean;
begin
  SubmitRef(ckImproveAtDominion, Item);
  Result := StationOutcome <> 0;
end;

// Moved from TfRuinsTalk.BuyDominionPirateLicense. Cost is the quote the screen showed.
procedure ExecuteBuyPirateLicense(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  P.SetMoney(P.Money - IntArg(Command, 0));
  P.PirateLicenseTicks := 365;
end;

procedure PurchasePirateLicense(Cost: Integer);
begin
  SubmitInt(ckBuyPirateLicense, Cost);
end;

// Moved from TfRuinsTalk.AcceptDominionTravel. The star and the cost are the quote the
// screen showed.
procedure ExecuteQueueDominionTravel(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  P.QueuedTravelTarget := StarArg(Command, 0);
  P.SetMoney(P.Money - IntArg(Command, 0));
  SpendDominionServiceCredit(P, 0.5);
  TRuins(P.DockedTo).RelocationAge := (TRuins(P.DockedTo).RelocationAge - 45) div 2;
end;

procedure QueueDominionTravel(Star: TStar; Cost: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckQueueDominionTravel);
  AddRef(Command, Star);
  AddInt(Command, Cost);
  SubmitCommand(Command);
end;

// Moved from TfRuinsTalk.CancelDominionTravel.
procedure ExecuteDropDominionTravel(const Command: TPlayerCommand);
begin
  Actor(Command).QueuedTravelTarget := nil;
end;

procedure DropDominionTravel;
begin
  SubmitSimple(ckDropDominionTravel);
end;

// CHANGE: BUGFIX - TfRuinsTalk.CheckDominionAvailable and the energy the war-plan dialogs ask
// for, as they stand now, and the money for the order. Between days two humans docked at one
// Dominion could both order it: both paid, the last order won, and two relocations left two
// stars pointing at it (docs/network.md, Commands).
procedure CheckDominionOrder(P: TPlayer; Star: TStar; Cost: Integer);
begin
  if not (P.DockedTo is TRuins)
      or (TRuins(P.DockedTo).FlyToStar <> nil)
      or (P.DockedTo.Order = soTeleport)
      or P.DockedTo.HasScriptControl
      or (TRuins(P.DockedTo).RelocationAge < 150) then
    raise ECommandRefused.CreateReason(
        rrTargetGone,
        Format('Dominion order to star %d: the Dominion has other plans', [Star.Id])
    );
  if P.Money < Cost then
    raise ECommandRefused.CreateReason(rrNoMoney, 'Dominion order: not enough money');
end;

// Moved from TfRuinsTalk.AcceptDominionRelocation.
procedure ExecuteRelocateDominion(const Command: TPlayerCommand);
var
  Star: TStar;
  P: TPlayer;
begin
  P := Actor(Command);
  Star := StarArg(Command, 0);
  CheckDominionOrder(P, Star, GetDominionRelocationCost(P, Star));
  // CHANGE: BUGFIX - Another human's relocation to this star made it the Dominion's.
  if Star.Dominion <> nil then
    raise ECommandRefused.CreateReason(rrTargetGone, 'RelocateDominion: the star has a Dominion');
  P.SetMoney(P.Money - GetDominionRelocationCost(P, Star));
  SpendDominionServiceCredit(P, 1);
  TRuins(P.DockedTo).RelocationAge := (TRuins(P.DockedTo).RelocationAge - 150) div 2;
  P.DockedTo.OrderTeleport(Star, TRuins(P.DockedTo).SelectTeleportArrivalPoint(Star), 10, True);
  P.DockedTo.CurrentStar.Dominion := nil;
  Star.Dominion := P.DockedTo;
end;

procedure RelocateDominion(Star: TStar);
begin
  SubmitRef(ckRelocateDominion, Star);
end;

// Moved from TfRuinsTalk.AcceptDominionWarOperation; the screen builds the answer.
procedure ExecuteOrderPirateRaid(const Command: TPlayerCommand);
var
  Names: WideString;
  I, J, K, Available, BestAvailable, Total, BestTotal, Cost: Integer;
  Ship: TShip;
  Strength: Extended;
  Target, Candidate, Origin: TStar;
  Event: TGalaxyEvent;
  P: TPlayer;
begin
  P := Actor(Command);
  Cost := ApplyRecentDominionOrderSurcharge(Galaxy.ComputeScaledHugeMoney(2));
  // CHANGE: BUGFIX - The command carries the price the screen quoted (a log from before has
  // none, and pays the price as it stands). Every Dominion order in the last 60 days raises
  // it, also another human's between days, and the money stopped at 0 (docs/network.md,
  // Commands).
  if (Length(Command.Ints) > 0) and (Cost > IntArg(Command, 0)) then
    raise ECommandRefused.CreateReason(rrOfferGone, 'OrderPirateRaid: the price went up');
  if (Length(Command.Ints) > 0) and (P.Money < Cost) then
    raise ECommandRefused.CreateReason(rrNoMoney, 'OrderPirateRaid: not enough money');
  P.SetMoney(P.Money - Cost);
  if MainPiratePlanet <> nil then
    MainPiratePlanet.ChangeRelationToRanger(P, 10);
  Target := nil;
  BestAvailable := 0;
  BestTotal := 0;
  for I := 0 to Galaxy.Stars.Count - 1 do
  begin
    Candidate := Galaxy.Stars[I];
    if (Candidate.Constellation.Id <> 20)
        and Candidate.IsConstellationVisible
        and not Candidate.NoComeKling
        and not IsStarProtectedByScript(Candidate)
        and (Candidate.ControlFaction <> sfPirates) then
    begin
      Available := 0;
      Total := 0;
      for J := 0 to Galaxy.Stars.Count - 1 do
      begin
        Origin := Galaxy.Stars[J];
        if (Candidate <> Origin)
            and (Origin.ControlFaction = sfPirates)
            and (Origin.Status.CustomFaction = '')
            and (Origin.Battle = 0)
            and (Origin.CountForcesByOwnerGroups(Strength, True, True, False, False) <= 0) then
          for K := 0 to Origin.Ships.Count - 1 do
          begin
            Ship := Origin.Ships[K];
            if (Ship is TPirate)
                and (Ship.OwnerId = Byte(oiPirate))
                and (Ship.PartnerShip = nil) then
              if not ((Ship.GetFuelTanks = nil)
                  or (Ship.GetEngine = nil)
                  or (PointDistance(Origin.Position, Candidate.Position)
                      > Min(Ship.GetFuelTanks.Capacity, Ship.GetEngine.JumpRange) + 10)) then
              begin
                Inc(Total);
                if not Ship.OrderAbsolute
                    and (Ship.AbsoluteScriptOrder = 0)
                    and not Ship.IsOutsideStarSpace
                    and (Ship.ScriptShip = nil) then
                  Inc(Available);
              end;
          end;
      end;
      if Available > BestAvailable then
      begin
        BestAvailable := Available;
        BestTotal := Total;
        Target := Candidate;
      end;
    end;
  end;
  StationAmount := Cost;
  StationText := '';
  StationTargetStar := nil;
  if (Target = nil) or (BestTotal < 10) or (BestAvailable < 7) then
    StationOutcome := 0
  else
  begin
    BestAvailable := Min(P.PirateRank + 7, BestAvailable);
    // Native completes each pass even after the requested ship count is reached.
    while BestAvailable > 0 do
      for J := 1 to Galaxy.Stars.Count - 1 do
      begin
        Origin := Target.StarDistances[J].Star;
        if (Origin.ControlFaction = sfPirates)
            and (Origin.Status.CustomFaction = '')
            and (Origin.Battle = 0)
            and (Origin.CountForcesByOwnerGroups(Strength, True, True, False, False) <= 0) then
          for K := 0 to Origin.Ships.Count - 1 do
          begin
            Ship := Origin.Ships[K];
            if (Ship is TPirate)
                and (Ship.OwnerId = Byte(oiPirate))
                and (Ship.PartnerShip = nil) then
              if not ((Ship.GetFuelTanks = nil)
                  or (Ship.GetEngine = nil)
                  or (PointDistance(Origin.Position, Target.Position)
                      > Min(Ship.GetFuelTanks.Capacity, Ship.GetEngine.JumpRange) + 10)) then
                if not Ship.OrderAbsolute
                    and (Ship.AbsoluteScriptOrder = 0)
                    and not Ship.IsOutsideStarSpace
                    and (Ship.ScriptShip = nil) then
                  if NextRandomIntRange(1, 10, P.DockedTo.RandomState) < 3 then
                  begin
                    Ship.OrderJump(Target, True);
                    TPirate(Ship).RaidPressure := TPirate(Ship).RaidPressure + 10;
                    if Names = '' then
                      Names := Ship.GetFullName(' ')
                    else
                      Names := Names + #13#10 + Ship.GetFullName(' ');
                    Dec(BestAvailable);
                  end;
          end;
      end;
    Event := AddGalaxyEvent('PlayerOrdersPirateRaid');
    Event.AddData(Target.Id);
    StationOutcome := 1;
    StationText := Names;
    StationTargetStar := Target;
  end;
end;

function OrderPirateRaid(QuotedCost: Integer): Boolean;
begin
  SubmitInt(ckOrderPirateRaid, QuotedCost);
  Result := StationOutcome <> 0;
end;

// Moved from TfRuinsTalk.AcceptDominionAmbush.
procedure ExecuteOrderPirateAmbush(const Command: TPlayerCommand);
var
  Star: TStar;
  Event: TGalaxyEvent;
  Cost, I: Integer;
  P: TPlayer;
begin
  P := Actor(Command);
  Star := StarArg(Command, 0);
  Cost := ApplyRecentDominionOrderSurcharge(GetDominionRelocationCost(P, Star) * 1.5);
  CheckDominionOrder(P, Star, Cost);
  // CHANGE: BUGFIX - As the screen: no second ambush at the same star.
  for I := 0 to Galaxy.Stars.Count - 1 do
    if (TStar(Galaxy.Stars[I]).Dominion <> nil)
        and (TRuins(TStar(Galaxy.Stars[I]).Dominion).FlyToStar = Star) then
      raise ECommandRefused.CreateReason(rrTargetGone, 'OrderPirateAmbush: an ambush is under way');
  Event := AddGalaxyEvent('PlayerOrdersPirateAmbush');
  Event.AddData(Star.Id);
  P.SetMoney(P.Money - Cost);
  SpendDominionServiceCredit(P, 1.5);
  TRuins(P.DockedTo).RelocationAge := (TRuins(P.DockedTo).RelocationAge - 150) div 2;
  TRuins(P.DockedTo).FlyToStar := Star;
  if Star.ControlFaction = sfPirates then
    TRuins(P.DockedTo).FlyDate := Galaxy.CurrentTurn + 12
  else
    TRuins(P.DockedTo).FlyDate := Galaxy.CurrentTurn + 16;
  StationAmount := Cost;
end;

procedure OrderPirateAmbush(Star: TStar);
begin
  SubmitRef(ckOrderPirateAmbush, Star);
end;

// Moved from TfRuinsTalk.AcceptDominionAssault.
procedure ExecuteOrderPirateAssault(const Command: TPlayerCommand);
var
  Star: TStar;
  P: TPlayer;
begin
  P := Actor(Command);
  Star := StarArg(Command, 0);
  CheckDominionOrder(
      P,
      Star,
      ApplyRecentDominionOrderSurcharge(GetDominionRelocationCost(P, Star) * 2.5)
  );
  // CHANGE: BUGFIX - Another human's relocation to this star made it the Dominion's.
  if Star.Dominion <> nil then
    raise ECommandRefused.CreateReason(rrTargetGone, 'OrderPirateAssault: the star has a Dominion');
  P.SetMoney(P.Money - ApplyRecentDominionOrderSurcharge(GetDominionRelocationCost(P, Star) * 2.5));
  SpendDominionServiceCredit(P, 1);
  TRuins(P.DockedTo).RelocationAge := (TRuins(P.DockedTo).RelocationAge - 150) div 2;
  TRuins(P.DockedTo).FlyToStar := Star;
  TRuins(P.DockedTo).FlyDate := Galaxy.CurrentTurn + 12;
end;

procedure OrderPirateAssault(Star: TStar);
begin
  SubmitRef(ckOrderPirateAssault, Star);
end;

initialization
  // CHANGE: ENHANCEMENT - The trades (True) apply on a host as they arrive (docs/commands.md,
  // Trades).
  RegisterCommand(ckEnterBridgeScreen, 'EnterBridgeScreen', @ExecuteEnterBridgeScreen);
  RegisterCommand(ckEnterStation, 'EnterStation', @ExecuteEnterStation);
  RegisterCommand(ckClearStationDialog, 'ClearStationDialog', @ExecuteClearStationDialog);
  RegisterCommand(ckBeginStationDialog, 'BeginStationDialog', @ExecuteBeginStationDialog);
  RegisterCommand(ckShowDominatorVictory, 'ShowDominatorVictory', @ExecuteShowDominatorVictory);
  RegisterCommand(ckRefreshRangerRatings, 'RefreshRangerRatings', @ExecuteRefreshRangerRatings);
  RegisterCommand(ckPromoteAtMilitaryBase, 'PromoteAtMilitaryBase', @ExecutePromoteAtMilitaryBase);
  RegisterCommand(ckStationDialogOverride, 'StationDialogOverride', @ExecuteStationDialogOverride);
  RegisterCommand(ckStationInjectedDialog, 'StationInjectedDialog', @ExecuteStationInjectedDialog);
  RegisterCommand(ckStationScriptGameEnd, 'StationScriptGameEnd', @ExecuteStationScriptGameEnd);
  RegisterCommand(ckCloseBridge, 'CloseBridge', @ExecuteCloseBridge);
  RegisterCommand(ckToggleImpulseShields, 'ToggleImpulseShields', @ExecuteToggleImpulseShields);
  RegisterCommand(ckRecallInterceptors, 'RecallInterceptors', @ExecuteRecallInterceptors);
  RegisterCommand(ckRecallAllInterceptors, 'RecallAllInterceptors', @ExecuteRecallAllInterceptors);
  RegisterCommand(
      ckChangeInterceptorPassCount,
      'ChangeInterceptorPassCount',
      @ExecuteChangeInterceptorPassCount
  );
  RegisterCommand(ckSetInterceptorStrategy, 'SetInterceptorStrategy', @ExecuteSetInterceptorStrategy);
  RegisterCommand(ckPayForModernization, 'PayForModernization', @ExecutePayForModernization, True);
  RegisterCommand(ckDepositNodes, 'DepositNodes', @ExecuteDepositNodes);
  RegisterCommand(ckTakeServiceMicroModule, 'TakeServiceMicroModule', @ExecuteTakeServiceMicroModule);
  RegisterCommand(
      ckGiveMicroModuleForNodes,
      'GiveMicroModuleForNodes',
      @ExecuteGiveMicroModuleForNodes
  );
  RegisterCommand(ckChangeNationality, 'ChangeNationality', @ExecuteChangeNationality);
  RegisterCommand(ckChangeSide, 'ChangeSide', @ExecuteChangeSide);
  RegisterCommand(ckBuyPirateNodes, 'BuyPirateNodes', @ExecuteBuyPirateNodes, True);
  RegisterCommand(ckBuyPirateProgram, 'BuyPirateProgram', @ExecuteBuyPirateProgram);
  RegisterCommand(ckPirateBaseRepair, 'PirateBaseRepair', @ExecutePirateBaseRepair);
  RegisterCommand(ckBuySubCrack, 'BuySubCrack', @ExecuteBuySubCrack);
  RegisterCommand(ckBuyChameleon, 'BuyChameleon', @ExecuteBuyChameleon);
  RegisterCommand(ckMilitaryBaseRepair, 'MilitaryBaseRepair', @ExecuteMilitaryBaseRepair);
  RegisterCommand(
      ckCollectMilitaryPrograms,
      'CollectMilitaryPrograms',
      @ExecuteCollectMilitaryPrograms
  );
  RegisterCommand(
      ckOrderLiberationOperation,
      'OrderLiberationOperation',
      @ExecuteOrderLiberationOperation
  );
  RegisterCommand(ckImproveEquipment, 'ImproveEquipment', @ExecuteImproveEquipment);
  RegisterCommand(ckScienceBaseRepair, 'ScienceBaseRepair', @ExecuteScienceBaseRepair);
  RegisterCommand(ckBuySatellite, 'BuySatellite', @ExecuteBuySatellite, True);
  RegisterCommand(ckSellResearchRemains, 'SellResearchRemains', @ExecuteSellResearchRemains);
  RegisterCommand(ckSellResearchEquipment, 'SellResearchEquipment', @ExecuteSellResearchEquipment);
  RegisterCommand(ckSellResearchItem, 'SellResearchItem', @ExecuteSellResearchItem);
  RegisterCommand(ckBuyResearchProgram, 'BuyResearchProgram', @ExecuteBuyResearchProgram);
  RegisterCommand(ckTakeLoan, 'TakeLoan', @ExecuteTakeLoan);
  RegisterCommand(ckRepayLoan, 'RepayLoan', @ExecuteRepayLoan);
  RegisterCommand(ckOpenDeposit, 'OpenDeposit', @ExecuteOpenDeposit);
  RegisterCommand(ckCloseDeposit, 'CloseDeposit', @ExecuteCloseDeposit);
  RegisterCommand(ckBuyMedicalPolicy, 'BuyMedicalPolicy', @ExecuteBuyMedicalPolicy);
  RegisterCommand(ckInvest, 'Invest', @ExecuteInvest, True);
  RegisterCommand(ckBuyTradeAdvice, 'BuyTradeAdvice', @ExecuteBuyTradeAdvice);
  RegisterCommand(ckExamineDiseases, 'ExamineDiseases', @ExecuteExamineDiseases);
  RegisterCommand(ckTreatDisease, 'TreatDisease', @ExecuteTreatDisease);
  RegisterCommand(ckTreatAllDiseases, 'TreatAllDiseases', @ExecuteTreatAllDiseases);
  RegisterCommand(ckBuyStimulant, 'BuyStimulant', @ExecuteBuyStimulant);
  RegisterCommand(ckBuySpecialShip, 'BuySpecialShip', @ExecuteBuySpecialShip, True);
  RegisterCommand(ckPriceSpecialShip, 'PriceSpecialShip', @ExecutePriceSpecialShip);
  RegisterCommand(ckBuildPirateShip, 'BuildPirateShip', @ExecuteBuildPirateShip, True);
  RegisterCommand(ckImproveAtDominion, 'ImproveAtDominion', @ExecuteImproveAtDominion);
  RegisterCommand(ckBuyPirateLicense, 'BuyPirateLicense', @ExecuteBuyPirateLicense);
  RegisterCommand(ckQueueDominionTravel, 'QueueDominionTravel', @ExecuteQueueDominionTravel);
  RegisterCommand(ckDropDominionTravel, 'DropDominionTravel', @ExecuteDropDominionTravel);
  RegisterCommand(ckRelocateDominion, 'RelocateDominion', @ExecuteRelocateDominion);
  RegisterCommand(ckOrderPirateRaid, 'OrderPirateRaid', @ExecuteOrderPirateRaid);
  RegisterCommand(ckOrderPirateAmbush, 'OrderPirateAmbush', @ExecuteOrderPirateAmbush);
  RegisterCommand(ckOrderPirateAssault, 'OrderPirateAssault', @ExecuteOrderPirateAssault);
end.
