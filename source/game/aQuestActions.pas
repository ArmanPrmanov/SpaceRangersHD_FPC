{$EXCESSPRECISION OFF}
unit aQuestActions;
{$R-}
{$Q-}
{$B-}

// CHANGE: ENHANCEMENT - What a text quest (QuestRun) does to the game, as commands
// (docs/commands.md).
//
// Granularity: the quest interpreter (TTextQuest, its location, parameters and its own random
// stream) stays in the quest run (QuestRun, which the screen or a headless player shows) and
// outside the galaxy save; it only reads the game. Each point where the quest writes to the
// galaxy is one command whose arguments are the values the interpreter computed:
// - the draw that seeds the quest's random stream from the galaxy's (QuestRandomSeed);
// - the quest's money parameter copied to the player (SetQuestMoney);
// - the quest's ext_ parameters copied to script variables (SetQuestVariables);
// - the outcome applied to the player's government quest, the prison or the ranger's life
//   (CompleteGovernmentQuest, ReleaseFromPrison, FailGovernmentQuest, DieInQuest);
// - the script that queued the quest resuming with the outcome (FinishQueuedTextQuest);
// - leaving the quest (CloseQuest).
// Replaying these reproduces the galaxy without the interpreter, and without replaying each
// choice the player made. Days that pass in a quest are turn jobs, as on the star map.
//
// CHANGE: ENHANCEMENT - Multiplayer (docs/progress/2026-10-19-text-quests-plan.md, Phase B):
// - a quest starts with BeginTextQuest, a trade: one human at a time plays a planet's quest;
// - a quest runs no galaxy day: CloseQuest carries the days it passed, which the human owes
//   (THuman.QuestDaysOwed);
// - a death in a quest kills the ranger, which respawns as after a ship loss (DieInQuest);
// - a queued quest's outcome resumes its actor's request (FinishQueuedTextQuest).
//
// With no player (a quest run from the main menu) there is no one to act, and the changes run
// directly, unrecorded.
interface
uses
  EC_Expression,
  aCommands,
  aHuman,
  aScript;
const
  // Command kinds 600-624 (see TCommandKind).
  ckQuestRandomSeed = 600;
  ckSetQuestMoney = 601;
  ckSetQuestVariables = 602;
  ckCompleteGovernmentQuest = 603;
  ckReleaseFromPrison = 604;
  ckFailGovernmentQuest = 605;
  ckDieInQuest = 606;
  ckFinishQueuedTextQuest = 607;
  ckCloseQuest = 608;
  ckBeginTextQuest = 609;
  // CHANGE: ENHANCEMENT - The form of a BeginTextQuest a host relays to the clients at the
  // actor's planet (RelayedTextQuestOf; aCommands.RegisterRelayCommand): only the lock.
  ckRelayedTextQuest = 610;
  // The kinds of quest BeginTextQuest names. Only a planet quest names a planet and can be
  // refused; the values are part of the command log format.
  tqkPlanet = 0;
  tqkPrison = 1;
  tqkQueued = 2;
  tqkNamed = 3;

// Draws the seed of the quest's own random stream from the galaxy's stream.
function QuestRandomSeed: Cardinal;
// Sets the player's money to the quest's money parameter.
procedure SetQuestMoney(Value: Integer);
// The script variable a quest parameter named ext_... stands for: the queued quest's
// script's own variable, else the shared one. Name is the variable's name (GQuestVarExt_...).
function FindQuestVariable(Script: TScript; const Name: WideString): TVarEC;
// Sets the integer script variables Names[I] (see FindQuestVariable) to Values[I].
procedure SetQuestVariables(
    Script: TScript;
    const Names: array of WideString;
    const Values: array of Integer
);
// The quest on the player's planet was won: its government quest is done, the planet's quest
// goes, and the planet's relation changes by RelationDelta. CompleteOnFinish is the quest's
// own flag. Returns whether the player had such a government quest.
function CompleteGovernmentQuest(CompleteOnFinish: Boolean; RelationDelta: Integer): Boolean;
// The prison quest was lost: the player is free and the planet (or the pirates) hostile.
procedure ReleaseFromPrison;
// The quest on the player's planet was lost: its government quest fails.
procedure FailGovernmentQuest;
// The ranger died in the quest. In single player the game ends. In multiplayer the ranger is
// killed and respawns as after a ship loss (TShip.RespawnHuman), after the quest's failure:
// a prison quest frees it with the planet hostile, and with FailGovernmentQuest (a quest no
// script queued) its government quest to the planet fails. Returns whether the game is over
// for the ranger: always in single player, in multiplayer only when no planet takes it (it
// leaves the game as a destroyed human with nowhere to go does).
function DieInQuest(FailGovernmentQuest: Boolean): Boolean;
// The script that queued the quest runs with the outcome: the actor's first queued quest.
procedure FinishQueuedTextQuest(Status: TScriptQuestStatus);
// Leaving the quest screen: the player keeps at most MoneyLimit, and the quest timers run.
// CHANGE: ENHANCEMENT - DaysOwed: the game days the quest passed in multiplayer, which the
// human owes (THuman.QuestDaysOwed; 0 in single player, where the quest ran them). The
// human's quest is no longer open (BeginTextQuest).
procedure CloseQuest(MoneyLimit: Cardinal; DaysOwed: Integer);
// CHANGE: ENHANCEMENT - The local human starts a quest of Kind (tqk...), at Planet for a planet
// quest (nil otherwise), as a trade (docs/commands.md, Trades): one human at a time plays a
// planet's quest. Returns False when it is refused: the planet's quest is gone or the human
// holds none to it (offer-gone), or another human plays it (in-use); a session's refusal
// hook tells the player (TradeRefusedHook). A prison, script or named quest always starts.
function BeginTextQuest(Kind: Integer; Planet: TObject): Boolean;
// CHANGE: ENHANCEMENT - The human other than Excluded who has Planet's text quest open
// (BeginTextQuest; THuman.TextQuestPlanetId); nil when none. On a networked client it is known
// from the relay of that human's BeginTextQuest to the clients at the planet (docs/progress/
// 2026-10-19-text-quests-plan.md, The lock), until the next state.
function TextQuestHolder(Planet: TObject; Excluded: THuman): THuman;
// CHANGE: ENHANCEMENT - What a host relays for a BeginTextQuest it applied (docs/network.md,
// Trades; docs/progress/2026-10-19-text-quests-plan.md, The lock): the same arguments as a
// RelayedTextQuest, which sets the actor's lock without the checks, since the host made them
// and a client's copy may not have the actor's quest (its probe or offer is no trade).
function RelayedTextQuestOf(const Command: TPlayerCommand): TPlayerCommand;
implementation
uses
  SysUtils,
  EC_Str,
  aMyFunction,
  aConst,
  aDialogActions,
  aGalaxy,
  aGalaxyStruct,
  aItem,
  aPlanet,
  aPlayer,
  aRanger,
  aSession,
  Globals,
  GR_Main;

function ScriptIndex(Script: TScript): Integer;
begin
  if Script = nil then
    Result := -1
  else
    Result := Galaxy.Scripts.IndexOf(Script);
end;

// Runs the command, or with no player to act, the executor directly.
procedure SubmitOrRun(const Command: TPlayerCommand; Executor: TCommandExecutor);
begin
  if LocalPlayer = nil then
    Executor(Command)
  else
    SubmitCommand(Command);
end;

var
  QuestSeedResult: Cardinal;
  GovernmentQuestFound: Boolean;

// Moved from TfPlanetQuest.StartLoadedQuest.
procedure ExecuteQuestRandomSeed(const Command: TPlayerCommand);
begin
  // CHANGE: BUGFIX - Seed the quest's own stream from the simulation stream.
  QuestSeedResult := Cardinal(GameRandomIntRange(0, MaxInt));
end;

function QuestRandomSeed: Cardinal;
begin
  SubmitOrRun(NewCommand(ckQuestRandomSeed), @ExecuteQuestRandomSeed);
  Result := QuestSeedResult;
end;

// Moved from TfPlanetQuest.ExportMoneyToPlayer.
procedure ExecuteSetQuestMoney(const Command: TPlayerCommand);
begin
  Actor(Command).SetMoney(IntArg(Command, 0));
end;

procedure SetQuestMoney(Value: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckSetQuestMoney);
  AddInt(Command, Value);
  SubmitCommand(Command);
end;

// Moved from TfPlanetQuest.ExportExternalParameters and ImportExternalParameters.
function FindQuestVariable(Script: TScript; const Name: WideString): TVarEC;
begin
  Result := nil;
  if Script <> nil then
    Result := Script.InitCode.LocalVar.GetVarNE(Name);
  if Result = nil then
    Result := Session.SharedScriptVariables.GetVarNE(Name);
end;

// Ints: the script's index, then one value per name, then the script's key. Text: the names,
// one per line.
procedure ApplyQuestVariables(Script: TScript; const Command: TPlayerCommand);
var
  Names: WideString;
  Name: WideString;
  I, Position: Integer;
  Variable: TVarEC;
begin
  Names := Command.Text;
  I := 1;
  while Names <> '' do
  begin
    Position := Pos(WideString(#10), Names);
    if Position = 0 then
    begin
      Name := Names;
      Names := '';
    end
    else
    begin
      Name := Copy(Names, 1, Position - 1);
      Names := Copy(Names, Position + 1, Length(Names) - Position);
    end;
    Variable := FindQuestVariable(Script, Name);
    if Variable <> nil then
      if Variable.RealVType = vkInt then
      begin
        Variable.SetInt(IntArg(Command, I));
      end;
    Inc(I);
  end;
end;

// The number of names in the command's text.
function QuestVariableCount(const Command: TPlayerCommand): Integer;
var
  I: Integer;
begin
  Result := 0;
  if Command.Text = '' then
    Exit;
  Result := 1;
  for I := 1 to Length(Command.Text) do
    if Command.Text[I] = #10 then
      Inc(Result);
end;

procedure ExecuteSetQuestVariables(const Command: TPlayerCommand);
begin
  // CHANGE: BUGFIX - The script by its key after the values; a log from before names it by
  // its index only (aDialogActions.ScriptArgument). CHANGE: BUGFIX - The key's count follows it.
  ApplyQuestVariables(
      ScriptArgument(
          Command,
          0,
          1 + QuestVariableCount(Command),
          4 + QuestVariableCount(Command),
          True
      ),
      Command
  );
end;

procedure SetQuestVariables(
    Script: TScript;
    const Names: array of WideString;
    const Values: array of Integer
);
var
  Command: TPlayerCommand;
  I: Integer;
begin
  if Length(Names) = 0 then
    Exit;
  Command := NewCommand(ckSetQuestVariables);
  if LocalPlayer = nil then
    AddInt(Command, -1)
  else
    AddInt(Command, ScriptIndex(Script));
  for I := 0 to High(Names) do
  begin
    if I > 0 then
      Command.Text := Command.Text + #10;
    Command.Text := Command.Text + Names[I];
    AddInt(Command, Values[I]);
  end;
  if LocalPlayer <> nil then
  begin
    AddScriptKey(Command, Script);
    AddScriptCount(Command, Script);
  end;
  // With no player, or a script the command cannot name, this runs unrecorded.
  if (LocalPlayer = nil) or ((Script <> nil) and (Command.Ints[0] < 0)) then
    ApplyQuestVariables(Script, Command)
  else
    SubmitCommand(Command);
end;

// Moved from TfPlanetQuest.CompleteQuestSuccess.
procedure ExecuteCompleteGovernmentQuest(const Command: TPlayerCommand);
var
  News, ItemName: WideString;
  GovernmentQuest: PQuest;
  I: Integer;
  Item: TUselessItem;
  P: TPlayer;
begin
  P := Actor(Command);
  GovernmentQuestFound := False;
  if not P.InPrison then
    if P.Quests.Count > 0 then
      for I := 0 to P.Quests.Count - 1 do
      begin
        GovernmentQuest := P.Quests[I];
        if (GovernmentQuest.QuestType = qtPlanetQuest)
            and (GovernmentQuest.ObjectiveTarget is TPlanet)
            and (P.CurrentPlanet = (GovernmentQuest.ObjectiveTarget as TPlanet)) then
        begin
          if IntArg(Command, 0) <> 0 then
          begin
            GovernmentQuest.Successful := True;
            News :=
                PickLocalizedTextVariant(
                    'GalaxyNews.Quest.Successful.PlanetaryQuest',
                    (Galaxy.CurrentTurn div 10) * Integer(Galaxy.GenerationSeed)
                );
            ReplaceTextToken(
                News,
                '<FromPlanet>',
                GovernmentQuest.Planet.Name,
                '<color=255,240,100>'
            );
            ReplaceTextToken(
                News,
                '<ToPlanet>',
                P.CurrentPlanet.Name,
                '<color=255,240,100>'
            );
            // CHANGE: ENHANCEMENT - Every human's news when the quests are shared
            // (docs/humans.md, Quests).
            AddQuestBubble(P, News);
          end;
          ItemName :=
              LookupLocalizedTextByKey(
                  'PlanetQuest.ItemForPlanetQuest.' + IntToStr(GovernmentQuest.QuestNumber)
              );
          if ItemName <> 'none' then
          begin
            Item := TUselessItem.Create;
            Item.Init(ItemName, dsBlazer, 0, False);
            P.Inventory.Add(Item);
          end;
          P.CurrentPlanet.TextQuestId := -1;
          GovernmentQuestFound := True;
          if P.CurrentPlanet.IsCoalitionOwned
              or (P.CurrentPlanet.OwnerId = Byte(oiPirate)) then
          begin
            P.CurrentPlanet.ChangeRelationToRanger(P, IntArg(Command, 1));
            if P.CurrentPlanet.RelationToShip(P) < 20 then
              P.CurrentPlanet.SetRelationLevelToRanger(P, rlBad);
          end;
          Break;
        end;
      end;
end;

function CompleteGovernmentQuest(CompleteOnFinish: Boolean; RelationDelta: Integer): Boolean;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckCompleteGovernmentQuest);
  AddInt(Command, Ord(CompleteOnFinish));
  AddInt(Command, RelationDelta);
  SubmitCommand(Command);
  Result := GovernmentQuestFound;
end;

// Moved from TfPlanetQuest.CompleteQuestFailure.
procedure ApplyReleaseFromPrison(P: TPlayer);
begin
  P.InPrison := False;
  if P.CurrentPlanet <> nil then
    if (P.CurrentPlanet.OwnerId = Byte(oiPirate)) and (MainPiratePlanet <> nil) then
      MainPiratePlanet.SetRelationLevelToRanger(P, rlHostile)
    else
      P.CurrentPlanet.SetRelationLevelToRanger(P, rlHostile);
end;

procedure ExecuteReleaseFromPrison(const Command: TPlayerCommand);
begin
  ApplyReleaseFromPrison(Actor(Command));
end;

procedure ReleaseFromPrison;
begin
  SubmitCommand(NewCommand(ckReleaseFromPrison));
end;

// Moved from TfPlanetQuest.CompleteQuestFailure.
procedure ApplyFailGovernmentQuest(Human: THuman);
var
  News: WideString;
  GovernmentQuest: PQuest;
  I: Integer;
  P: TPlayer;
begin
  P := Human.Player;
  if P.Quests.Count > 0 then
    for I := P.Quests.Count - 1 downto 0 do
    begin
      GovernmentQuest := P.Quests[I];
      if (GovernmentQuest.QuestType = qtPlanetQuest)
          and (GovernmentQuest.ObjectiveTarget is TPlanet)
          and (P.CurrentPlanet = (GovernmentQuest.ObjectiveTarget as TPlanet)) then
      begin
        GovernmentQuest.Successful := False;
        P.PublishQuestStatus(GovernmentQuest, -1);
        News :=
            PickLocalizedTextVariant(
                'GalaxyNews.Quest.Failure.PlanetaryQuest',
                Integer(P.Seed) * (Galaxy.CurrentTurn div 10)
            );
        ReplaceTextToken(
            News,
            '<ToPlanet>',
            P.CurrentPlanet.Name,
            '<color=255,240,100>'
        );
        ReplaceTextToken(
            News,
            '<FromPlanet>',
            GovernmentQuest.Planet.Name,
            '<color=255,240,100>'
        );
        ReplaceTextToken(
            News,
            '<Relation>',
            GovernmentQuest.Planet.GetRelationLevelTextToShip(P),
            '<color=255,240,100>'
        );
        // CHANGE: ENHANCEMENT - Every human's news when the quests are shared (docs/humans.md,
        // Quests).
        AddQuestBubble(P, News);
        P.CurrentPlanet.TextQuestId := -1;
        P.ArchiveQuest(I);
        Break;
      end;
    end;
end;

procedure ExecuteFailGovernmentQuest(const Command: TPlayerCommand);
begin
  ApplyFailGovernmentQuest(ActorHuman(Command));
end;

procedure FailGovernmentQuest;
begin
  SubmitCommand(NewCommand(ckFailGovernmentQuest));
end;

var
  DiedForGood: Boolean;

// Moved from TfPlanetQuest.CompleteQuestDeath.
procedure ExecuteDieInQuest(const Command: TPlayerCommand);
var
  Human: THuman;
  P: TPlayer;
  RespawnPlanet: TPlanet;
begin
  DiedForGood := True;
  // CHANGE: ENHANCEMENT - In multiplayer the death is a ship loss (docs/progress/
  // 2026-10-19-text-quests-plan.md, decisions): the quest fails as a lost one does, the
  // PlayerDeath event names the human (TShip.RecordHumanDeath), and the ranger respawns at once
  // where FindRespawnPlanet takes it, as a captured human does (aPlanetActions.
  // ApplyPlanetCaptured). Only the actor's game can end, and only when no planet takes it.
  if IsMultiplayer then
  begin
    Human := ActorHuman(Command);
    P := Human.Player;
    if P.InPrison then
      ApplyReleaseFromPrison(P)
    else if (Length(Command.Ints) > 0) and (IntArg(Command, 0) <> 0) then
      ApplyFailGovernmentQuest(Human);
    P.RecordHumanDeath('KilledInQuest');
    RespawnPlanet := P.FindRespawnPlanet;
    if RespawnPlanet <> nil then
    begin
      P.RespawnHuman(RespawnPlanet);
      DiedForGood := False;
      Exit;
    end;
    // As a destroyed human with nowhere to go (TStar.NextDay): it leaves the game, and the
    // game is over on its own machine only.
    Human.ReleaseTextQuest;
    if Human = LocalHuman then
      Session.GameEndReason := 1;
    P.Free;
    Exit;
  end;
  Actor(Command).Free;
  Session.GameEndReason := 1;
end;

function DieInQuest(FailGovernmentQuest: Boolean): Boolean;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckDieInQuest);
  AddInt(Command, Ord(FailGovernmentQuest));
  SubmitCommand(Command);
  Result := DiedForGood;
end;

// Moved from TfPlanetQuest.CompleteQuestSuccess and CompleteQuestFailure.
procedure ExecuteFinishQueuedTextQuest(const Command: TPlayerCommand);
begin
  // CHANGE: ENHANCEMENT - The actor's request; a command of no human (0) finishes the first.
  CompleteQueuedTextQuest(TScriptQuestStatus(IntArg(Command, 0)), Integer(Command.Actor));
end;

procedure FinishQueuedTextQuest(Status: TScriptQuestStatus);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckFinishQueuedTextQuest);
  AddInt(Command, Ord(Status));
  SubmitOrRun(Command, @ExecuteFinishQueuedTextQuest);
end;

// Moved from TfPlanetQuest.OnClose.
procedure ExecuteCloseQuest(const Command: TPlayerCommand);
var
  Money, CappedMoney: Int64;
  Player: TPlayer;
  Human: THuman;
  MoneyLimit: Cardinal;
begin
  MoneyLimit := Cardinal(IntArg(Command, 0));
  Player := Actor(Command);
  Money := Player.Money;
  // The native inlined Int64 minimum compares an unsigned limit with signed money.
  if Int64(MoneyLimit) < Money then
    CappedMoney := MoneyLimit
  else
    CappedMoney := Money;
  Player.SetMoney(Integer(CappedMoney));
  Player.ProcessQuestTimersAndOutcomes;
  // CHANGE: ENHANCEMENT - The days the quest passed, owed in multiplayer (a command from
  // before carries none), and the quest is no longer open.
  Human := ActorHuman(Command);
  if Length(Command.Ints) > 1 then
    Inc(Human.QuestDaysOwed, IntArg(Command, 1));
  Human.ReleaseTextQuest;
end;

procedure CloseQuest(MoneyLimit: Cardinal; DaysOwed: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckCloseQuest);
  AddInt(Command, Integer(MoneyLimit));
  AddInt(Command, DaysOwed);
  SubmitCommand(Command);
end;

// Whether P holds a planet quest (qtPlanetQuest) whose target is Planet.
function HoldsPlanetQuestTo(P: TPlayer; Planet: TPlanet): Boolean;
var
  I: Integer;
  Quest: PQuest;
begin
  Result := False;
  for I := 0 to P.Quests.Count - 1 do
  begin
    Quest := P.Quests[I];
    if (Quest.QuestType = qtPlanetQuest) and (Quest.ObjectiveTarget = Planet) then
      Exit(True);
  end;
end;

function TextQuestHolder(Planet: TObject; Excluded: THuman): THuman;
var
  I: Integer;
begin
  if Planet is TPlanet then
    for I := 0 to Session.Humans.Count - 1 do
    begin
      Result := Session.Humans[I];
      if (Result <> Excluded)
          and Result.TextQuestOpen
          and (Result.TextQuestPlanetId = Integer(TPlanet(Planet).Id)) then
        Exit;
    end;
  Result := nil;
end;

// The lock BeginTextQuest leaves: the actor has a quest open, at the planet of a planet quest.
procedure SetTextQuestLock(Human: THuman; Planet: TPlanet);
begin
  Human.TextQuestOpen := True;
  if Planet <> nil then
    Human.TextQuestPlanetId := Planet.Id
  else
    Human.TextQuestPlanetId := 0;
end;

procedure ExecuteRelayedTextQuest(const Command: TPlayerCommand);
var
  Planet: TPlanet;
begin
  Planet := nil;
  if (IntArg(Command, 0) = tqkPlanet) and (RefObject(Command, 0) is TPlanet) then
    Planet := TPlanet(RefObject(Command, 0));
  SetTextQuestLock(ActorHuman(Command), Planet);
end;

function RelayedTextQuestOf(const Command: TPlayerCommand): TPlayerCommand;
begin
  Result := Command;
  Result.Kind := ckRelayedTextQuest;
end;

// CHANGE: ENHANCEMENT - The lock of the text-quests plan (docs/progress/
// 2026-10-19-text-quests-plan.md, The lock): a trade, so a host decides as it arrives. Ints:
// the kind (tqk...); Refs: the planet of a planet quest. It refuses before any change.
procedure ExecuteBeginTextQuest(const Command: TPlayerCommand);
var
  Human: THuman;
  Planet: TPlanet;
begin
  Human := ActorHuman(Command);
  Planet := nil;
  if IntArg(Command, 0) = tqkPlanet then
  begin
    if RefObject(Command, 0) is TPlanet then
      Planet := TPlanet(RefObject(Command, 0));
    if (Planet = nil)
        or (Planet.TextQuestId = -1)
        or not HoldsPlanetQuestTo(Human.Player, Planet) then
      raise ECommandRefused.CreateReason(rrOfferGone, 'BeginTextQuest: the planet''s quest is gone');
    // CHANGE: ENHANCEMENT - A networked client runs it only once its host has applied it
    // (aCommands.TradeSubmitHook): another human's lock it knows of is a relay
    // (RelayedTextQuest), which the host may have released since (a disconnect).
    if not Assigned(TradeSubmitHook) and (TextQuestHolder(Planet, Human) <> nil) then
      raise ECommandRefused.CreateReason(
          rrInUse,
          'BeginTextQuest: another human plays the planet''s quest'
      );
  end;
  SetTextQuestLock(Human, Planet);
end;

function BeginTextQuest(Kind: Integer; Planet: TObject): Boolean;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckBeginTextQuest);
  AddInt(Command, Kind);
  AddRef(Command, Planet);
  Result := True;
  try
    SubmitCommand(Command);
  except
    on E: ECommandRefused do
    begin
      AppendLogLineThreadSafe(AnsiString('BeginTextQuest refused: ' + E.Message));
      if Assigned(TradeRefusedHook) then
        TradeRefusedHook(E.Reason);
      Result := False;
    end;
  end;
end;

initialization
  RegisterCommand(ckQuestRandomSeed, 'QuestRandomSeed', @ExecuteQuestRandomSeed);
  RegisterCommand(ckSetQuestMoney, 'SetQuestMoney', @ExecuteSetQuestMoney);
  RegisterCommand(ckSetQuestVariables, 'SetQuestVariables', @ExecuteSetQuestVariables);
  RegisterCommand(ckCompleteGovernmentQuest, 'CompleteGovernmentQuest', @ExecuteCompleteGovernmentQuest);
  RegisterCommand(ckReleaseFromPrison, 'ReleaseFromPrison', @ExecuteReleaseFromPrison);
  RegisterCommand(ckFailGovernmentQuest, 'FailGovernmentQuest', @ExecuteFailGovernmentQuest);
  RegisterCommand(ckDieInQuest, 'DieInQuest', @ExecuteDieInQuest);
  RegisterCommand(ckFinishQueuedTextQuest, 'FinishQueuedTextQuest', @ExecuteFinishQueuedTextQuest);
  RegisterCommand(ckCloseQuest, 'CloseQuest', @ExecuteCloseQuest);
  RegisterCommand(ckBeginTextQuest, 'BeginTextQuest', @ExecuteBeginTextQuest, True);
  RegisterRelayCommand(ckRelayedTextQuest, 'RelayedTextQuest', @ExecuteRelayedTextQuest);
end.
