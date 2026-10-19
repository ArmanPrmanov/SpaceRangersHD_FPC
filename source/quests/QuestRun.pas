{$EXCESSPRECISION OFF}
unit QuestRun;
{$R-}
{$Q-}
{$B-}
{$A8}

// CHANGE: ENHANCEMENT - One run of a text quest, without its screen (docs/progress/
// 2026-10-19-text-quests-plan.md, Phase A). Moved out of TfPlanetQuest: which quest a visit
// plays, the texts it starts with, the engine's calls (TTextQuestInterface), the parameters it
// trades with the game, the days it passes and what each outcome does to the game (the
// aQuestActions commands). The run keeps the page being shown as a TQuestPage and tells a
// TQuestView what changes, in the order the screen drew it; the view also shows the boxes and
// picks the next screen. TfPlanetQuest is one view, the headless quest player
// (HeadlessQuest) another. A choice is played by its index in the page (Choose).
//
// CHANGE: ENHANCEMENT - Multiplayer (Phase B of the plan): a run starts with BeginTextQuest
// (one human at a time per planet quest, a refusal ends it before it starts), passes no game
// day (the days are counted and owed, CloseQuest), and a death respawns the ranger instead of
// ending the game (DieInQuest). The local human's queued quest is the one it plays.
//
// CHANGE: ENHANCEMENT - The network (Phase C of the plan): a run a networked client lost its
// host in is abandoned (Abandon): it closes without CloseQuest, since the host dropped its
// commands with the connection.
interface
uses
  TextQuest,
  TextQuestInterface,
  aRanger,
  aScript;
type
  // Where the quest comes from. qrkNamed is a quest given by its name or number with no
  // visit that offered it (the headless quest player); it ends as a planet quest does.
  TQuestRunKind = (qrkStandalone, qrkPrison, qrkQueued, qrkPlanet, qrkNamed);
  // How the run ended; qroNone while it plays. qroAbandoned: it was left without an outcome.
  TQuestRunOutcome = (qroNone, qroSuccess, qroFailure, qroDeath, qroAbandoned);
  // What a choice does when it is played: go to a location or along a path (Value is its
  // id), show the outcome of a critical parameter, or end the quest.
  TQuestChoiceAction = (
      qcaNone,
      qcaLocation,
      qcaPath,
      qcaOutcome,
      qcaSuccess,
      qcaFailure,
      qcaDeath
  );
  TQuestChoice = record
    // As shown: without the leading dashes, and a disabled one without its colours.
    Text: WideString;
    Enabled: Boolean;
    Action: TQuestChoiceAction;
    Value: Integer;
  end;
  // The page as shown: the text and the parameters with their colour tags, the picture's
  // name, the choices in their order, and the outcome once the quest has ended.
  TQuestPage = record
    Text: WideString;
    Picture: WideString;
    Parameters: WideString;
    Choices: array of TQuestChoice;
    Outcome: TQuestRunOutcome;
  end;
  TQuestRun = class;
  // What shows a run. Each call follows the change in TQuestRun.Page; the base class shows
  // nothing.
  TQuestView = class(TObject)
    procedure ShowText(const Text: WideString); virtual;
    procedure ShowPicture(const Name: WideString); virtual;
    procedure PlayMusic(const Name: WideString); virtual;
    procedure PlaySound(const Name: WideString); virtual;
    procedure ShowParameters(const Text: WideString); virtual;
    procedure ClearChoices; virtual;
    // Page.Choices[Index] was added.
    procedure AddChoice(Index: Integer; const Choice: TQuestChoice); virtual;
    // The page is complete: after the start and after each choice.
    procedure FinishPage; virtual;
    // The ranger is about to die in the quest: True lets it, False keeps the game as it is
    // (the screen loads the autosave instead).
    function ConfirmDeath: Boolean; virtual;
    // The quest ended with Outcome, after the outcome's own commands; a queued quest's script
    // resumes after this.
    procedure EndQuest(Outcome: TQuestRunOutcome); virtual;
    // The engine found the quest broken (no start, no answers).
    procedure ShowError(const Text: AnsiString); virtual;
  end;
  TQuestRun = class(TTextQuestInterface)
    View: TQuestView;
    Kind: TQuestRunKind;
    Quest: TTextQuest;
    QuestName: WideString;
    // The quest's number, or -1 for one loaded by name.
    QuestId: Integer;
    CurrentDate: WideString;
    DaysElapsed: Integer;
    // The most money the player may keep when the quest closes (CloseQuest).
    MoneyLimit: Cardinal;
    // The government quest a planet quest plays, and the script request a queued one does;
    // QueuedQuest is nil again once its script has resumed.
    GovernmentQuest: PQuest;
    QueuedQuest: PQueuedTextQuest;
    Page: TQuestPage;
    // How far Open got, for the screen's error message.
    Stage: Integer;
    // Set by the outcomes: a won quest completed a government quest, a lost one freed the
    // ranger from prison, the ranger died.
    GovernmentQuestDone: Boolean;
    ReleasedFromPrison: Boolean;
    // Died: the game is over for the ranger (single player, or in multiplayer no planet takes
    // it); Respawned: in multiplayer it died and respawned (aQuestActions.DieInQuest).
    Died: Boolean;
    Respawned: Boolean;
    // CHANGE: ENHANCEMENT - The run passes no game day: the game had more than one human when it
    // started (IsMultiplayer). Its days are counted in DaysElapsed and owed (CloseQuest).
    OwesDays: Boolean;
    // BeginTextQuest refused the quest (another human plays it, or it is gone): Open returned
    // False and nothing started.
    Refused: Boolean;
    // CHANGE: ENHANCEMENT - Abandon has left the run.
    Abandoned: Boolean;
    // The galaxy job of a day in the quest is waited for before the quest goes on. The screen
    // leaves it running, so the rest of the page can read the galaxy while it changes; a test
    // that must repeat sets this (HeadlessQuest).
    WaitForQuestDays: Boolean;
    constructor Create(AView: TQuestView);
    destructor Destroy; override;
    // Picks and starts the quest the screen opens for, as the visit gives it: the prison's,
    // the local human's first queued one, the planet quest of the player's government quest
    // to its planet, or with no player the one from the main menu. False when the player
    // holds no quest to its planet, or BeginTextQuest refused it (Refused): there is nothing
    // to play.
    function Open: Boolean;
    // Starts the quest Name (a number or a name) for the local player, as qrkNamed.
    procedure OpenNamed(const Name: WideString);
    // Plays Page.Choices[Index]; a disabled one or one out of range does nothing.
    procedure Choose(Index: Integer);
    // Leaving the quest: the money cap and the quest timers (CloseQuest).
    procedure Close;
    // CHANGE: ENHANCEMENT - The quest is left without an outcome and without CloseQuest: a
    // networked client reconnected to its host, which dropped the quest's commands with the old
    // connection (docs/progress/2026-10-19-text-quests-plan.md, Disconnects). Close then does
    // nothing more; the state from the host replaces what the quest predicted here.
    procedure Abandon;
    function ExpandTemplateText(Text: WideString): WideString;
    // The engine's calls.
    procedure ShowText(Text: WideString); override;
    procedure ShowPicture(Name: WideString); override;
    procedure PlayMusic(Name: WideString); override;
    procedure PlaySound(Name: WideString); override;
    procedure ShowParameters(Text: WideString); override;
    procedure AddContinueAction; override;
    procedure AddSuccessAction; override;
    procedure AddDeathAction; override;
    procedure AddFailureAction; override;
    procedure AddPathAction(Text: WideString; PathId: Integer); override;
    procedure AddDisabledPath(Text: WideString); override;
    procedure AddPathContinueAction(PathId: Integer); override;
    procedure AddLocationContinueAction(LocationId: Integer); override;
    procedure AdvanceDays(Days: Integer); override;
    procedure ShowError(const Text: AnsiString); override;
  private
    procedure ComputeMoneyLimit;
    // BeginTextQuest for this run's kind; False (and Refused) when it is refused. With no
    // player there is no one to lock for.
    function BeginRun(QuestKind: Integer; Planet: TObject): Boolean;
    procedure LoadQuestById(Id: Integer);
    procedure LoadQuestByName(const Name: WideString);
    procedure SetVisitTexts;
    procedure StartLoadedQuest;
    procedure ClearChoices;
    procedure AddChoice(
        Text: WideString;
        Enabled: Boolean;
        Action: TQuestChoiceAction;
        Value: Integer
    );
    procedure FinishPage;
    procedure Succeed;
    procedure Fail;
    procedure Die;
    procedure FinishQueuedQuest(Status: TScriptQuestStatus);
    // One day of the galaxy inside the quest; False stops the days (the game is closing).
    function RunQuestDay: Boolean;
    procedure ApplyLegacyPictureOverrides;
    procedure ExportMoneyToPlayer;
    procedure ImportMoneyFromPlayer;
    procedure ExportExternalParameters;
    procedure ImportExternalParameters;
    function ExpandExternalText(Text: WideString): WideString;
  end;
// The colour tag the quest's highlighted text uses in style StyleIndex.
function QuestTextColorTag(StyleIndex: Integer): WideString;
// The CRC of the planet quest file Id, as the quest licence lists it.
function QuestContentHash(Id: Integer): WideString;
implementation
uses
  Classes,
  Dialogs,
  SysUtils,
  EC_BlockPar,
  EC_Cache,
  EC_CacheBuf,
  EC_Expression,
  EC_Str,
  Globals,
  GlobalsV,
  GR_Main,
  ThreadCalc,
  aCalc,
  aConst,
  aGalaxy,
  aGalaxyStruct,
  aMyFunction,
  aPlanet,
  aPlayer,
  aPlayerActions,
  aQuestActions,
  aHuman,
  aSession,
  CPDiapClass,
  ParameterClass,
  ValueListClass,
  EventClass;

procedure TQuestView.ShowText(const Text: WideString);
begin
end;

procedure TQuestView.ShowPicture(const Name: WideString);
begin
end;

procedure TQuestView.PlayMusic(const Name: WideString);
begin
end;

procedure TQuestView.PlaySound(const Name: WideString);
begin
end;

procedure TQuestView.ShowParameters(const Text: WideString);
begin
end;

procedure TQuestView.ClearChoices;
begin
end;

procedure TQuestView.AddChoice(Index: Integer; const Choice: TQuestChoice);
begin
end;

procedure TQuestView.FinishPage;
begin
end;

function TQuestView.ConfirmDeath: Boolean;
begin
  Result := True;
end;

procedure TQuestView.EndQuest(Outcome: TQuestRunOutcome);
begin
end;

procedure TQuestView.ShowError(const Text: AnsiString);
begin
  Dialogs.ShowMessage(Text);
end;

// Moved from TfPlanetQuest.GetTextColorTag.
function QuestTextColorTag(StyleIndex: Integer): WideString;
var
  Block: TBlockParEC;
begin
  Block := UiStyleConfig.GetBlockByPath('Style');
  if Block.CountBlocks('QTextColor') > 0 then
  begin
    Block := Block.GetBlock('QTextColor');
    if Block.CountParams('Sel' + IntToWideString(StyleIndex + 1)) > 0 then
    begin
      Result := '<color=' + Block.GetParam('Sel' + IntToWideString(StyleIndex + 1)) + '>';
      Exit;
    end;
  end;
  if StyleIndex = 0 then
    Result := '<color=' + IntToStr(255) + ',' + IntToStr(240) + ',' + IntToStr(100) + '>'
  else if StyleIndex = 1 then
    Result := '<color=' + IntToStr(255) + ',' + IntToStr(240) + ',' + IntToStr(100) + '>'
  else if StyleIndex = 2 then
    Result := '<color=' + IntToStr(0) + ',' + IntToStr(4) + ',' + IntToStr(173) + '>'
  else if StyleIndex = 3 then
    Result := '<color=' + IntToStr(0) + ',' + IntToStr(4) + ',' + IntToStr(173) + '>'
  else
    Result := QuestTextColorTag(0);
end;

// Moved from TfPlanetQuest.GetQuestContentHash.
function QuestContentHash(Id: Integer): WideString;
var
  Control: TCBufControlEC;
  Data: TCBufEC;
begin
  Control := nil;
  try
    Control := TCBufControlEC.Create;
    GlobalCache.ResetControl(Control);
    Control.SetCacheKey('PlanetQuest.' + IntToStr(Id));
    Data := AcquireOrCreateBuffer(Control);
    Result := ScriptDwordToHex(Data.Buffer.ComputeCrc32 xor $FFFFFFFF);
  finally
    if Control <> nil then
    begin
      Control.Release;
      Control.Free;
    end;
  end;
end;

// Moved from TfPlanetQuest.GetTextBeforeDelimiter.
function GetTextBeforeDelimiter(const Text: WideString; Delimiter: WideChar): WideString;
var
  I, N: Integer;
  S: WideString;
begin
  S := '';
  N := Length(Text);
  for I := 1 to N do
  begin
    if Text[I] = Delimiter then
      Break;
    S := S + Text[I];
  end;
  Result := S;
end;

// Moved from TfPlanetQuest.GetTextAfterComma.
function GetTextAfterComma(const Text: WideString; IgnoredDelimiter: WideChar): WideString;
var
  I, N: Integer;
  S: WideString;
begin
  S := '';
  N := Length(Text);
  if N <> 0 then
  begin
    I := 1;
    while Text[I] <> ',' do
      Inc(I);
    Inc(I);
    while I <= N do
    begin
      S := S + Text[I];
      Inc(I);
    end;
  end;
  Result := S;
end;

constructor TQuestRun.Create(AView: TQuestView);
begin
  inherited Create;
  View := AView;
  QuestId := -1;
  Stage := 0;
end;

destructor TQuestRun.Destroy;
begin
  if Quest <> nil then
  begin
    Quest.Free;
    Quest := nil;
  end;
  inherited Destroy;
end;

procedure TQuestRun.LoadQuestById(Id: Integer);
var
  Control: TCBufControlEC;
  Data: TCBufEC;
begin
  QuestId := Id;
  Control := nil;
  QuestName := IntToStr(Id);
  try
    Control := TCBufControlEC.Create;
    GlobalCache.ResetControl(Control);
    Control.SetCacheKey('PlanetQuest.' + IntToStr(Id));
    Data := AcquireOrCreateBuffer(Control);
    Quest.LoadFromReader(Data.Buffer, False);
  finally
    if Control <> nil then
    begin
      Control.Release;
      Control.Free;
    end;
  end;
end;

procedure TQuestRun.LoadQuestByName(const Name: WideString);
var
  Control: TCBufControlEC;
  Data: TCBufEC;
begin
  QuestId := -1;
  Control := nil;
  QuestName := Name;
  try
    Control := TCBufControlEC.Create;
    GlobalCache.ResetControl(Control);
    Control.SetCacheKey('PlanetQuest.' + Name);
    Data := AcquireOrCreateBuffer(Control);
    Quest.LoadFromReader(Data.Buffer, False);
  finally
    if Control <> nil then
    begin
      Control.Release;
      Control.Free;
    end;
  end;
end;

// Moved from TfPlanetQuest.OnOpen.
procedure TQuestRun.ComputeMoneyLimit;
begin
  // CHANGE: ENHANCEMENT - The local human's queued quest (rule 5 of the text-quests plan).
  if (LocalScriptRequest(srqTextQuest) = nil)
      and (LocalPlayer <> nil)
      and (LocalPlayer.CurrentPlanet <> nil)
      and (LocalPlayer.CurrentPlanet.TextQuestId >= 10000)
      and ((LanguageDataConfig.GetBlock('PlanetQuest').CountBlocks('PlanetQuestLic') <= 0)
          or (LanguageDataConfig
                  .GetBlock('PlanetQuest')
                  .GetBlock('PlanetQuestLic')
                  .GetParamOrMarker(IntToStr(LocalPlayer.CurrentPlanet.TextQuestId))
              = QuestContentHash(LocalPlayer.CurrentPlanet.TextQuestId))) then
    MoneyLimit := (Galaxy.ComputeScaledBigMoney(2) + LocalPlayer.Money)
  else if (LocalPlayer <> nil) and (LocalScriptRequest(srqTextQuest) = nil) then
    MoneyLimit := (LocalPlayer.Money + 50000)
  else
    MoneyLimit := 1000000000;
end;

// The texts a queued quest starts with: where the player is, and its name.
procedure TQuestRun.SetVisitTexts;
begin
  if LocalPlayer.CurrentStar <> nil then
  begin
    Quest.ToStarText.Text := LocalPlayer.CurrentStar.Name;
    Quest.FromStarText.Text := LocalPlayer.CurrentStar.Name;
  end
  else
  begin
    Quest.ToStarText.Text := '';
    Quest.FromStarText.Text := '';
  end;
  if LocalPlayer.CurrentPlanet <> nil then
  begin
    Quest.ToPlanetText.Text := LocalPlayer.CurrentPlanet.Name;
    Quest.FromPlanetText.Text := LocalPlayer.CurrentPlanet.Name;
  end
  else
  begin
    Quest.ToPlanetText.Text := '';
    Quest.FromPlanetText.Text := '';
  end;
  Quest.DateText.Text := '';
  Quest.MoneyText.Text := '';
  Quest.RangerText.Text := LocalPlayer.Name;
end;

function TQuestRun.BeginRun(QuestKind: Integer; Planet: TObject): Boolean;
begin
  Result := True;
  if LocalPlayer = nil then
    Exit;
  Result := BeginTextQuest(QuestKind, Planet);
  // CHANGE: ENHANCEMENT - Only a planet quest can be refused by the game; a prison, queued or
  // named one is refused only when a networked client's host did not answer (or the client
  // reconnects). It starts all the same: the lock guards nothing for it, its commands go to the
  // host with the day's, and the prison or the script that queued it would otherwise send the
  // player back to the quest at once (docs/progress/2026-10-19-text-quests-plan.md, Phase C).
  if not Result and (QuestKind <> tqkPlanet) then
  begin
    AppendLogLineThreadSafe('BeginTextQuest went unanswered; the quest starts all the same');
    Result := True;
  end;
  Refused := not Result;
end;

// Moved from TfPlanetQuest.OnOpen; the stages continue the screen's.
function TQuestRun.Open: Boolean;
var
  I, J: Integer;
  Candidate: PQuest;
begin
  Result := True;
  Stage := 4;
  ComputeMoneyLimit;
  Stage := 5;
  if (LocalPlayer <> nil) and (LocalPlayer.CurrentPlanet <> nil) and LocalPlayer.InPrison then
  begin
    Stage := 6;
    Kind := qrkPrison;
    if not BeginRun(tqkPrison, nil) then
      Exit(False);
    Quest := TTextQuest.Create;
    if LocalPlayer.CurrentPlanet.OwnerId <> Byte(oiPirate) then
      LoadQuestByName('Prison')
    else
      LoadQuestByName('PirateClanPrison');
    Stage := 7;
    Quest.ToStarText.Text := LocalPlayer.CurrentStar.Name;
    Quest.ToPlanetText.Text := LocalPlayer.CurrentPlanet.Name;
    Quest.DateText.Text := '';
    Quest.MoneyText.Text := '';
    Quest.FromPlanetText.Text := LocalPlayer.CurrentPlanet.Name;
    Quest.FromStarText.Text := LocalPlayer.CurrentStar.Name;
    Quest.RangerText.Text := LocalPlayer.Name;
    Stage := 8;
    StartLoadedQuest;
    Stage := 9;
  end
  else if LocalScriptRequest(srqTextQuest) <> nil then
  begin
    Stage := 10;
    Kind := qrkQueued;
    if not BeginRun(tqkQueued, nil) then
      Exit(False);
    QueuedQuest := LocalScriptRequest(srqTextQuest);
    Quest := TTextQuest.Create;
    if IsIntegerTextW(QueuedQuest.Name) then
      LoadQuestById(StrToInt(QueuedQuest.Name))
    else
      LoadQuestByName(QueuedQuest.Name);
    Stage := 11;
    SetVisitTexts;
    Stage := 12;
    StartLoadedQuest;
    Stage := 13;
  end
  else if (LocalPlayer <> nil) and not StandaloneQuestMode then
  begin
    Stage := 14;
    Kind := qrkPlanet;
    Result := False;
    if LocalPlayer.CurrentPlanet.TextQuestId > -1 then
      if LocalPlayer.Quests.Count > 0 then
        for I := 0 to LocalPlayer.Quests.Count - 1 do
        begin
          Candidate := LocalPlayer.Quests[I];
          if (Candidate.QuestType = qtPlanetQuest)
              and (Candidate.ObjectiveTarget is TPlanet)
              and ((Candidate.ObjectiveTarget as TPlanet) = LocalPlayer.CurrentPlanet) then
          begin
            Stage := 15;
            if not BeginRun(tqkPlanet, LocalPlayer.CurrentPlanet) then
              Break;
            GovernmentQuest := Candidate;
            Quest := TTextQuest.Create;
            LoadQuestById(LocalPlayer.CurrentPlanet.TextQuestId);
            Stage := 16;
            Quest.ToStarText.Text := LocalPlayer.CurrentStar.Name;
            Quest.ToPlanetText.Text := LocalPlayer.CurrentPlanet.Name;
            Quest.DateText.Text := Galaxy.FormatTurnDate(Candidate.DeadlineTurn);
            Quest.MoneyText.Text := IntToStr(Candidate.RewardMoney);
            Quest.FromPlanetText.Text := Candidate.Planet.Name;
            Quest.FromStarText.Text := Candidate.Planet.CurrentStar.Name;
            Quest.RangerText.Text := LocalPlayer.Name;
            for J := 1 to Quest.GetParameterCount do
              if Quest.GetParameter(J).Enabled
                  and (Quest.GetParameter(J).NameText.Text = 'GRewardMoney') then
              begin
                Quest.GetParameter(J).Value := Candidate.RewardMoney;
                Break;
              end;
            Stage := 17;
            StartLoadedQuest;
            Stage := 18;
            Result := True;
            Break;
          end;
        end;
  end
  else
  begin
    Stage := 19;
    Kind := qrkStandalone;
    Quest := TTextQuest.Create;
    if IsIntegerTextW(PendingQuestName) then
      LoadQuestById(StrToInt(PendingQuestName))
    else
      LoadQuestByName(PendingQuestName);
    Stage := 20;
    Quest.ToStarText.Text := LocalizedText('FormLoadQuest.PToStar');
    Quest.ToPlanetText.Text := LocalizedText('FormLoadQuest.PToPlanet');
    Quest.DateText.Text := FormatGameTurnDate(1500);
    Quest.MoneyText.Text := '10000';
    Quest.FromPlanetText.Text := LocalizedText('FormLoadQuest.PFromPlanet');
    Quest.FromStarText.Text := LocalizedText('FormLoadQuest.PFromStar');
    Quest.RangerText.Text := LocalizedText('FormLoadQuest.PRanger');
    Stage := 21;
    StartLoadedQuest;
    Stage := 22;
  end;
end;

procedure TQuestRun.OpenNamed(const Name: WideString);
begin
  ComputeMoneyLimit;
  Kind := qrkNamed;
  if not BeginRun(tqkNamed, nil) then
    Exit;
  Quest := TTextQuest.Create;
  if IsIntegerTextW(Name) then
    LoadQuestById(StrToInt(Name))
  else
    LoadQuestByName(Name);
  SetVisitTexts;
  StartLoadedQuest;
end;

// Moved from TfPlanetQuest.StartLoadedQuest.
procedure TQuestRun.StartLoadedQuest;
begin
  ClearChoices;
  DaysElapsed := 0;
  OwesDays := (LocalPlayer <> nil) and IsMultiplayer;
  if Quest.FormatVersion <= 1111111124 then
    ApplyLegacyPictureOverrides;
  if LocalPlayer = nil then
    CurrentDate := TrimWideString(Galaxy.FormatTurnDate(300))
  else
    CurrentDate := TrimWideString(Galaxy.FormatTurnDate(Galaxy.CurrentTurn));
  Quest.PlayerInterface := Self;
  ImportExternalParameters;
  // CHANGE: BUGFIX - Seed the quest's own stream from the simulation stream.
  TextQuestRandomState := QuestRandomSeed;
  if LocalPlayer = nil then
    Quest.Start(-1, False)
  else
    Quest.Start(LocalPlayer.Money, True);
  FinishPage;
end;

procedure TQuestRun.ClearChoices;
begin
  SetLength(Page.Choices, 0);
  View.ClearChoices;
end;

// Moved from TfPlanetQuest.AddChoice and AddDisabledChoice: the text they showed.
procedure TQuestRun.AddChoice(
    Text: WideString;
    Enabled: Boolean;
    Action: TQuestChoiceAction;
    Value: Integer
);
var
  Skip, Index: Integer;
begin
  Skip := 0;
  while Skip < Length(Text) do
  begin
    if (Text[Skip + 1] <> '-') and (Text[Skip + 1] <> ' ') then
      Break;
    Inc(Skip);
  end;
  if Skip > 0 then
    Text := Copy(Text, Skip + 1, Length(Text) - Skip);
  if not Enabled then
  begin
    Text := RemoveMatchingTextTagsW(Text, 'color', 'COLOR');
    Text := RemoveMatchingTextTagsW(Text, '/color', '/COLOR');
  end;
  Index := Length(Page.Choices);
  SetLength(Page.Choices, Index + 1);
  Page.Choices[Index].Text := Text;
  Page.Choices[Index].Enabled := Enabled;
  Page.Choices[Index].Action := Action;
  Page.Choices[Index].Value := Value;
  View.AddChoice(Index, Page.Choices[Index]);
end;

procedure TQuestRun.FinishPage;
begin
  View.FinishPage;
end;

// Moved from TfPlanetQuest.ChoiceMouseUp and the choices' callbacks.
procedure TQuestRun.Choose(Index: Integer);
var
  Choice: TQuestChoice;
begin
  if (Index < 0) or (Index >= Length(Page.Choices)) or not Page.Choices[Index].Enabled then
    Exit;
  Choice := Page.Choices[Index];
  ClearChoices;
  case Choice.Action of
    qcaLocation:
      begin
        ClearChoices;
        Quest.EnterLocation(Choice.Value);
      end;
    qcaPath:
      begin
        ClearChoices;
        Quest.FollowPath(Choice.Value);
      end;
    qcaOutcome:
      begin
        ClearChoices;
        Quest.ShowOutcome;
      end;
    qcaSuccess:
      Succeed;
    qcaFailure:
      Fail;
    qcaDeath:
      Die;
  end;
  FinishPage;
end;

procedure TQuestRun.FinishQueuedQuest(Status: TScriptQuestStatus);
begin
  if QueuedQuest <> nil then
  begin
    QueuedQuest := nil;
    FinishQueuedTextQuest(Status);
  end;
end;

// Moved from TfPlanetQuest.CompleteQuestSuccess.
procedure TQuestRun.Succeed;
begin
  ClearChoices;
  GovernmentQuestDone := False;
  if QueuedQuest = nil then
    if LocalPlayer <> nil then
      GovernmentQuestDone :=
          CompleteGovernmentQuest(Quest.CompleteOnFinish, Quest.SuccessRelationDelta);
  Page.Outcome := qroSuccess;
  View.EndQuest(qroSuccess);
  FinishQueuedQuest(sqsSuccess);
end;

// Moved from TfPlanetQuest.CompleteQuestFailure.
procedure TQuestRun.Fail;
begin
  ReleasedFromPrison := False;
  if LocalPlayer <> nil then
    if LocalPlayer.InPrison then
    begin
      ReleaseFromPrison;
      ReleasedFromPrison := True;
    end
    else if QueuedQuest = nil then
      FailGovernmentQuest;
  Page.Outcome := qroFailure;
  View.EndQuest(qroFailure);
  FinishQueuedQuest(sqsFailure);
end;

// Moved from TfPlanetQuest.CompleteQuestDeath.
procedure TQuestRun.Die;
begin
  Died := False;
  Respawned := False;
  if LocalPlayer <> nil then
    if View.ConfirmDeath then
    begin
      // CHANGE: ENHANCEMENT - In multiplayer the ranger respawns, and the quest has failed
      // (DieInQuest), a queued one too.
      Died := DieInQuest(QueuedQuest = nil);
      Respawned := not Died;
    end;
  Page.Outcome := qroDeath;
  View.EndQuest(qroDeath);
  if Respawned then
    FinishQueuedQuest(sqsFailure);
end;

// Moved from TfPlanetQuest.OnClose.
procedure TQuestRun.Close;
begin
  QuestId := -1;
  if Quest <> nil then
  begin
    Quest.Free;
    Quest := nil;
  end;
  if Page.Outcome = qroNone then
    Page.Outcome := qroAbandoned;
  // The money cap and the quest timers, in that order; in multiplayer, the days owed. CHANGE:
  // ENHANCEMENT - Not for a quest that never started here (refused) or that was abandoned.
  if (LocalPlayer <> nil) and not Abandoned and not Refused then
    if OwesDays then
      CloseQuest(MoneyLimit, DaysElapsed)
    else
      CloseQuest(MoneyLimit, 0);
end;

procedure TQuestRun.Abandon;
begin
  Abandoned := True;
  ClearChoices;
  Close;
end;

// Moved from TfPlanetQuest.ExpandTemplateText.
function TQuestRun.ExpandTemplateText(Text: WideString): WideString;
var
  Expanded, SourceLineBreak, ReplacementLineBreak, IndentedLineBreak: WideString;
begin
  if LocalPlayer = nil then
    CurrentDate := TrimWideString(Galaxy.FormatTurnDate(DaysElapsed + 300))
  // CHANGE: ENHANCEMENT - In multiplayer the galaxy's date stays; the quest's goes on.
  else if OwesDays then
    CurrentDate := TrimWideString(Galaxy.FormatTurnDate(Galaxy.CurrentTurn + DaysElapsed))
  else
    CurrentDate := TrimWideString(Galaxy.FormatTurnDate(Galaxy.CurrentTurn));
  Expanded := ExpandExternalText(Text);
  SourceLineBreak := #13#10;
  ReplacementLineBreak := #13#10;
  IndentedLineBreak := #13#10'          ';
  Expanded :=
      ReplaceAllWideString(
          Expanded,
          '<ToStar>',
          WrapTextInColor(TrimWideString(Quest.ToStarText.Text), QuestTextColorTag(QuestStyleIndex))
      );
  Expanded :=
      ReplaceAllWideString(
          Expanded,
          '<ToPlanet>',
          WrapTextInColor(
              TrimWideString(Quest.ToPlanetText.Text),
              QuestTextColorTag(QuestStyleIndex)
          )
      );
  Expanded :=
      ReplaceAllWideString(
          Expanded,
          '<Date>',
          WrapTextInColor(Quest.DateText.Text, QuestTextColorTag(QuestStyleIndex))
      );
  Expanded :=
      ReplaceAllWideString(
          Expanded,
          '<Money>',
          WrapTextInColor(Quest.MoneyText.Text, QuestTextColorTag(QuestStyleIndex))
      );
  Expanded :=
      ReplaceAllWideString(
          Expanded,
          '<FromPlanet>',
          WrapTextInColor(
              TrimWideString(Quest.FromPlanetText.Text),
              QuestTextColorTag(QuestStyleIndex)
          )
      );
  Expanded :=
      ReplaceAllWideString(
          Expanded,
          '<FromStar>',
          WrapTextInColor(
              TrimWideString(Quest.FromStarText.Text),
              QuestTextColorTag(QuestStyleIndex)
          )
      );
  Expanded :=
      ReplaceAllWideString(
          Expanded,
          '<Ranger>',
          WrapTextInColor(TrimWideString(Quest.RangerText.Text), QuestTextColorTag(QuestStyleIndex))
      );
  Expanded :=
      ReplaceAllWideString(
          Expanded,
          '<CurDate>',
          WrapTextInColor(CurrentDate, QuestTextColorTag(QuestStyleIndex))
      );
  Expanded := ReplaceAllWideString(Expanded, SourceLineBreak, ReplacementLineBreak);
  Expanded := ReplaceAllWideString(Expanded, IndentedLineBreak, ReplacementLineBreak);
  if Pos('<', Expanded) > 0 then
  begin
    Expanded := ReplaceAllWideString(Expanded, '<br>', #13#10);
    Expanded := ReplaceAllWideString(Expanded, '<ll>', #13#10' '#13#10);
    // Native quirk: <Player> is expanded into Result, then overwritten below.
    if LocalPlayer <> nil then
      Result :=
          ReplaceAllWideString(
              Result,
              '<Player>',
              WrapTextInColor(LocalPlayer.Name, QuestTextColorTag(QuestStyleIndex))
          );
    Expanded := ReplaceAllWideString(Expanded, '<clr>', QuestTextColorTag(QuestStyleIndex));
    Expanded := ReplaceAllWideString(Expanded, '<clrEnd>', '</color>');
  end;
  Result := Expanded;
end;

// Moved from TfPlanetQuest.ApplyLegacyPictureOverrides.
procedure TQuestRun.ApplyLegacyPictureOverrides;
var
  Found, Count, I, J, K: Integer;
  Kind, Indices, Name, Picture: WideString;
  Values: TValuesList;
  Config: TBlockParEC;
begin
  Values := TValuesList.Create;
  Config := GameDataConfig.GetBlock('PQI');
  Count := Config.GetParamCount;
  for I := 0 to Count - 1 do
  begin
    Name := Config.GetParamName(I);
    if GetTextBeforeDelimiter(Name, ',') = QuestName then
    begin
      Kind := GetTextAfterComma(Name, ',');
      Indices := GetTextAfterComma(Kind, ',');
      Kind := GetTextBeforeDelimiter(Kind, ',');
      Values.LoadFromSemicolonText(Indices);
      Picture := Config.GetParamValue(I);
      Picture := ReplaceAllWideString(Picture, 'Bm.PQI.', '');
      if Kind = 'L' then
        for J := 1 to Values.Count do
        begin
          Found := -1;
          for K := 1 to Quest.GetLocationCount do
            if Quest.GetLocation(K).Id = Values.Values[J] then
            begin
              Found := K;
              Break;
            end;
          if Found > 0 then
            for K := 1 to Quest.GetLocation(Found).EventCount do
              Quest.GetLocation(Found).Events[K].Picture.Text := Picture;
        end;
      if Kind = 'P' then
        for J := 1 to Values.Count do
        begin
          Found := -1;
          for K := 1 to Quest.GetPathCount do
            if Quest.GetPath(K).Id = Values.Values[J] then
            begin
              Found := K;
              Break;
            end;
          if Found > 0 then
            Quest.GetPath(Found).Event.Picture.Text := Picture;
        end;
      if Kind = 'PAR' then
        for J := 1 to Values.Count do
          if Quest.GetParameterCount >= Values.Values[J] then
            if Quest.GetParameter(Values.Values[J]).Enabled then
              if Quest.GetParameter(Values.Values[J]).CriticalOutcome <> qoNone then
                Quest.GetParameter(Values.Values[J]).CriticalEvent.Picture.Text := Picture;
    end;
  end;
  Values.Destroy;
end;

// Moved from TfPlanetQuest.ExportMoneyToPlayer.
procedure TQuestRun.ExportMoneyToPlayer;
var
  I: Integer;
begin
  if LocalPlayer <> nil then
    for I := 1 to Quest.GetParameterCount do
      if Quest.GetParameter(I).Enabled then
        if Quest.GetParameter(I).IsMoney then
        begin
          SetQuestMoney(Quest.GetParameter(I).Value);
          Quest.GetParameter(I).Value := LocalPlayer.Money;
          Break;
        end;
end;

// Moved from TfPlanetQuest.ImportMoneyFromPlayer.
procedure TQuestRun.ImportMoneyFromPlayer;
var
  I: Integer;
begin
  if LocalPlayer <> nil then
    for I := 1 to Quest.GetParameterCount do
      if Quest.GetParameter(I).Enabled then
        if Quest.GetParameter(I).IsMoney then
        begin
          Quest.GetParameter(I).Value := LocalPlayer.Money;
          Break;
        end;
end;

// The script the queued quest came from, whose variables come before the shared ones.
function QueuedQuestScript(Run: TQuestRun): TScript;
begin
  Result := nil;
  if Run.QueuedQuest <> nil then
    Result := Run.QueuedQuest.Script;
end;

// Moved from TfPlanetQuest.ExportExternalParameters.
procedure TQuestRun.ExportExternalParameters;
var
  I: Integer;
  Name: WideString;
  Names: array of WideString;
  Values: array of Integer;
begin
  Names := nil;
  Values := nil;
  for I := 1 to Quest.GetParameterCount do
    if FindTextPosW('ext_', Quest.GetParameter(I).NameText.Text) = 1 then
    begin
      Name := Quest.GetParameter(I).NameText.Text;
      Name[1] := 'E';
      Name := 'GQuestVar' + Name;
      SetLength(Names, Length(Names) + 1);
      Names[High(Names)] := Name;
      SetLength(Values, Length(Values) + 1);
      Values[High(Values)] := Quest.GetParameter(I).Value;
    end;
  SetQuestVariables(QueuedQuestScript(Self), Names, Values);
end;

// Moved from TfPlanetQuest.ImportExternalParameters. The quest takes the variables' values,
// within its parameters' limits, and the variables then take the quest's values back.
procedure TQuestRun.ImportExternalParameters;
var
  I: Integer;
  Name: WideString;
  Variable: TVarEC;
  Names: array of WideString;
  Values: array of Integer;
begin
  Names := nil;
  Values := nil;
  for I := 1 to Quest.GetParameterCount do
    if FindTextPosW('ext_', Quest.GetParameter(I).NameText.Text) = 1 then
    begin
      Name := Quest.GetParameter(I).NameText.Text;
      Name[1] := 'E';
      Name := 'GQuestVar' + Name;
      Variable := FindQuestVariable(QueuedQuestScript(Self), Name);
      if Variable <> nil then
        if Variable.RealVType = vkInt then
        begin
          Quest.GetParameter(I).SetValue(Variable.GetInt);
          SetLength(Names, Length(Names) + 1);
          Names[High(Names)] := Name;
          SetLength(Values, Length(Values) + 1);
          Values[High(Values)] := Quest.GetParameter(I).Value;
        end;
    end;
  SetQuestVariables(QueuedQuestScript(Self), Names, Values);
end;

// Moved from TfPlanetQuest.ExpandExternalText.
function TQuestRun.ExpandExternalText(Text: WideString): WideString;
var
  I: Integer;
  Name, Token, Expanded: WideString;
  Variable: TVarEC;
begin
  Expanded := Text;
  // +0 preserves the native argument-load order.
  for I := 1 to Quest.GetParameterCount do
    if FindTextPosW('ext_', Quest.GetParameter(I + 0).NameText.Text) = 1 then
    begin
      Name := Quest.GetParameter(I + 0).NameText.Text;
      Token := Name;
      Name[1] := 'E';
      Token[1] := 't';
      Token := '<' + Token + '>';
      Name := 'GQuestVar' + Name;
      Variable := Session.SharedScriptVariables.GetVarNE(Name);
      if Variable <> nil then
        Expanded :=
            ReplaceAllWideString(
                Expanded,
                Token,
                WrapTextInColor(
                    TrimWideString(Variable.GetString),
                    QuestTextColorTag(QuestStyleIndex)
                )
            );
    end;
  Result := Expanded;
end;

// The engine's calls, moved from TTextQuestPlayerInterface.

procedure TQuestRun.ShowText(Text: WideString);
var
  ExpandedText: WideString;
begin
  ExpandedText := ExpandTemplateText(Text);
  if ExpandedText <> TrimWideString(Page.Text) then
  begin
    Page.Text := ExpandedText;
    View.ShowText(ExpandedText);
  end;
end;

procedure TQuestRun.ShowPicture(Name: WideString);
begin
  Page.Picture := Name;
  View.ShowPicture(Name);
end;

procedure TQuestRun.PlayMusic(Name: WideString);
begin
  View.PlayMusic(Name);
end;

procedure TQuestRun.PlaySound(Name: WideString);
begin
  View.PlaySound(Name);
end;

procedure TQuestRun.ShowParameters(Text: WideString);
begin
  Page.Parameters := TrimWideString(ExpandTemplateText(Text));
  View.ShowParameters(Page.Parameters);
  ExportMoneyToPlayer;
  ExportExternalParameters;
end;

procedure TQuestRun.AddContinueAction;
begin
  AddChoice(
      '  - ' + LocalizedText('Planet.NotCivil.QuestPlay.MsgContinue'),
      True,
      qcaOutcome,
      0
  );
end;

procedure TQuestRun.AddSuccessAction;
begin
  if (LocalPlayer <> nil) and LocalPlayer.InPrison then
    AddChoice(
        '  - ' + LocalizedText('Planet.NotCivil.QuestPlay.MsgSuccessPrison'),
        True,
        qcaSuccess,
        0
    )
  else if (QueuedQuest <> nil) and (QueuedQuest.SuccessCaption <> '') then
    AddChoice(' - ' + QueuedQuest.SuccessCaption, True, qcaSuccess, 0)
  else
    AddChoice(
        ' - ' + LocalizedColorText('Planet.NotCivil.QuestPlay.MsgSuccess'),
        True,
        qcaSuccess,
        0
    );
end;

procedure TQuestRun.AddDeathAction;
begin
  AddChoice('  - ' + LocalizedText('Planet.NotCivil.QuestPlay.MsgDeath'), True, qcaDeath, 0);
end;

procedure TQuestRun.AddFailureAction;
begin
  if (LocalPlayer <> nil) and LocalPlayer.InPrison then
    AddChoice(
        '  - ' + LocalizedText('Planet.NotCivil.QuestPlay.MsgFailPrison'),
        True,
        qcaFailure,
        0
    )
  else if (QueuedQuest <> nil) and (QueuedQuest.FailureCaption <> '') then
    AddChoice(' - ' + QueuedQuest.FailureCaption, True, qcaFailure, 0)
  else
    AddChoice('  - ' + LocalizedText('Planet.NotCivil.QuestPlay.MsgFail'), True, qcaFailure, 0);
end;

procedure TQuestRun.AddPathAction(Text: WideString; PathId: Integer);
begin
  AddChoice('  - ' + ExpandTemplateText(Text), True, qcaPath, PathId);
end;

procedure TQuestRun.AddDisabledPath(Text: WideString);
begin
  AddChoice('  - ' + ExpandTemplateText(Text), False, qcaNone, 0);
end;

procedure TQuestRun.AddPathContinueAction(PathId: Integer);
begin
  AddChoice(
      '  - ' + LocalizedText('Planet.NotCivil.QuestPlay.MsgContinue'),
      True,
      qcaPath,
      PathId
  );
end;

procedure TQuestRun.AddLocationContinueAction(LocationId: Integer);
begin
  AddChoice(
      '  - ' + LocalizedText('Planet.NotCivil.QuestPlay.MsgContinue'),
      True,
      qcaLocation,
      LocationId
  );
end;

// Moved from TTextQuestPlayerInterface.AdvanceDays.
function TQuestRun.RunQuestDay: Boolean;
begin
  WaitForTurnCalculation;
  PruneMessages;
  CalculatePlayerStarTurnAndWait;
  Result := not ExitScreenLoop;
  if Result then
  begin
    QueueGalaxyTurnCalculation;
    if WaitForQuestDays then
      WaitForTurnCalculation;
  end;
end;

procedure TQuestRun.AdvanceDays(Days: Integer);
var
  I: Integer;
begin
  ExportMoneyToPlayer;
  ExportExternalParameters;
  // CHANGE: ENHANCEMENT - In multiplayer the days are only counted; the human owes them after
  // the quest (CloseQuest), and the others do not wait for them.
  if OwesDays then
  begin
    if Days > 0 then
      Inc(DaysElapsed, Days);
    Exit;
  end;
  for I := 1 to Days do
  begin
    Inc(DaysElapsed);
    // The native standalone path stops after one increment, even when Days is greater than one.
    if StandaloneQuestMode then
      Break;
    if not RunQuestDay then
      Break;
    ImportMoneyFromPlayer;
    ImportExternalParameters;
  end;
end;

procedure TQuestRun.ShowError(const Text: AnsiString);
begin
  View.ShowError(Text);
end;

end.
