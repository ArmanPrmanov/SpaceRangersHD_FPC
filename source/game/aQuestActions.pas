{$EXCESSPRECISION OFF}
unit aQuestActions;
{$R-}
{$Q-}
{$B-}

// CHANGE: ENHANCEMENT - What a text quest (fPlanetQuest) does to the game, as commands
// (docs/commands.md).
//
// Granularity: the quest interpreter (TTextQuest, its location, parameters and its own random
// stream) stays in the screen and outside the galaxy save; it only reads the game. Each point
// where the quest writes to the galaxy is one command whose arguments are the values the
// interpreter computed:
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
// With no player (a quest run from the main menu) there is no one to act, and the changes run
// directly, unrecorded.
interface
uses
  EC_Expression,
  aCommands,
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
// The ranger died in the quest; the game ends.
procedure DieInQuest;
// The script that queued the quest runs with the outcome.
procedure FinishQueuedTextQuest(Status: TScriptQuestStatus);
// Leaving the quest screen: the player keeps at most MoneyLimit, and the quest timers run.
procedure CloseQuest(MoneyLimit: Cardinal);
implementation
uses
  SysUtils,
  EC_Str,
  aMyFunction,
  aConst,
  aGalaxy,
  aGalaxyStruct,
  aItem,
  aPlanet,
  aHuman,
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

function ScriptAtIndex(Index: Integer): TScript;
begin
  if Index < 0 then
    Result := nil
  else
    Result := TScript(Galaxy.Scripts[Index]);
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

// Ints: the script's index, then one value per name. Text: the names, one per line.
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

procedure ExecuteSetQuestVariables(const Command: TPlayerCommand);
begin
  ApplyQuestVariables(ScriptAtIndex(IntArg(Command, 0)), Command);
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
            ActorHuman(Command).AddOrUpdateBubble(0, Galaxy.CurrentTurn, News, '');
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
procedure ExecuteReleaseFromPrison(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  P.InPrison := False;
  if P.CurrentPlanet <> nil then
    if (P.CurrentPlanet.OwnerId = Byte(oiPirate)) and (MainPiratePlanet <> nil) then
      MainPiratePlanet.SetRelationLevelToRanger(P, rlHostile)
    else
      P.CurrentPlanet.SetRelationLevelToRanger(P, rlHostile);
end;

procedure ReleaseFromPrison;
begin
  SubmitCommand(NewCommand(ckReleaseFromPrison));
end;

// Moved from TfPlanetQuest.CompleteQuestFailure.
procedure ExecuteFailGovernmentQuest(const Command: TPlayerCommand);
var
  News: WideString;
  GovernmentQuest: PQuest;
  I: Integer;
  P: TPlayer;
begin
  P := Actor(Command);
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
        ActorHuman(Command).AddOrUpdateBubble(0, Galaxy.CurrentTurn, News, '');
        P.CurrentPlanet.TextQuestId := -1;
        P.ArchiveQuest(I);
        Break;
      end;
    end;
end;

procedure FailGovernmentQuest;
begin
  SubmitCommand(NewCommand(ckFailGovernmentQuest));
end;

// Moved from TfPlanetQuest.CompleteQuestDeath.
procedure ExecuteDieInQuest(const Command: TPlayerCommand);
begin
  Actor(Command).Free;
  Session.GameEndReason := 1;
end;

procedure DieInQuest;
begin
  SubmitCommand(NewCommand(ckDieInQuest));
end;

// Moved from TfPlanetQuest.CompleteQuestSuccess and CompleteQuestFailure.
procedure ExecuteFinishQueuedTextQuest(const Command: TPlayerCommand);
begin
  CompleteQueuedTextQuest(TScriptQuestStatus(IntArg(Command, 0)));
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
end;

procedure CloseQuest(MoneyLimit: Cardinal);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckCloseQuest);
  AddInt(Command, Integer(MoneyLimit));
  SubmitCommand(Command);
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
end.
