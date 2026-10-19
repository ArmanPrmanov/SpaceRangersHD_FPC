{$EXCESSPRECISION OFF}
unit HeadlessQuest;
{$R-}
{$Q-}

// CHANGE: ENHANCEMENT - A text quest played without its screen, for tests (docs/progress/
// 2026-10-19-text-quests-plan.md, Phase A). THeadlessQuestPlayer is a view of a TQuestRun
// (QuestRun) that shows nothing: it picks one of each page's enabled choices with a generator
// of its own, never the game's streams, and waits for each quest day's galaxy job, so that a
// run repeats given the save and the seed. It prints one line per page with the page's hash,
// and gives up after MaxQuestSteps choices (abandoned). A broken quest's message is a line too,
// never a box.
interface
uses
  QuestRun;
const
  MaxQuestSteps = 1000;
type
  THeadlessQuestPlayer = class(TQuestView)
    Run: TQuestRun;
    // The chooser's generator (an LCG).
    ChooserState: Cardinal;
    Steps: Integer;
    Pages: Integer;
    Errors: Integer;
    constructor Create(Seed: Cardinal);
    destructor Destroy; override;
    // Plays the quest Name (a number or a name) for the local player to its outcome, or to
    // MaxQuestSteps choices or a page with no enabled choice, and closes it (TQuestRun.Close).
    function Play(const Name: WideString): TQuestRunOutcome;
    // CHANGE: ENHANCEMENT - The two halves of Play, and the quest the local player's visit
    // gives (TQuestRun.Open: the prison's, a queued one, its planet quest at its planet), for
    // probes that act between the start and the end (docs/progress/
    // 2026-10-19-text-quests-plan.md, Phase B). OpenVisit returns False when there is nothing
    // to play or BeginTextQuest refused it (Run.Refused).
    procedure Start(const Name: WideString);
    function OpenVisit: Boolean;
    function Finish: TQuestRunOutcome;
    // CHANGE: ENHANCEMENT - Plays one choice, as Finish does; False when the quest has ended,
    // the page has no enabled choice or MaxQuestSteps choices have been played. For a probe
    // that leaves the quest in the middle (HeadlessNet, a client that loses its host).
    function Step: Boolean;
    procedure FinishPage; override;
    procedure ShowError(const Text: AnsiString); override;
  end;
// A hash of everything the page shows: its text, picture, parameters, choices and outcome.
function QuestPageHash(const Page: TQuestPage): QWord;
function QuestOutcomeName(Outcome: TQuestRunOutcome): AnsiString;
implementation
uses
  SysUtils,
  ThreadCalc,
  WorkerErrors,
  aObjectRefs,
  HeadlessSim;

function QuestPageHash(const Page: TQuestPage): QWord;
var
  Text: WideString;
  I: Integer;
begin
  Text := Page.Text + #1 + Page.Picture + #1 + Page.Parameters + #1 + IntToStr(Ord(Page.Outcome));
  for I := 0 to High(Page.Choices) do
    Text := Text + #1 + IntToStr(Ord(Page.Choices[I].Enabled)) + Page.Choices[I].Text;
  Result := HashBytes(PByte(PWideChar(Text)), Length(Text) * SizeOf(WideChar));
end;

function QuestOutcomeName(Outcome: TQuestRunOutcome): AnsiString;
const
  Names: array[TQuestRunOutcome] of AnsiString = (
      'none',
      'success',
      'failure',
      'death',
      'abandoned'
  );
begin
  Result := Names[Outcome];
end;

function EnabledChoiceCount(const Page: TQuestPage): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Page.Choices) do
    if Page.Choices[I].Enabled then
      Inc(Result);
end;

constructor THeadlessQuestPlayer.Create(Seed: Cardinal);
begin
  inherited Create;
  ChooserState := Seed;
end;

destructor THeadlessQuestPlayer.Destroy;
begin
  FreeAndNil(Run);
  inherited Destroy;
end;

procedure THeadlessQuestPlayer.FinishPage;
begin
  Emit(
      Format(
          'quest page=%d hash=%s choices=%d enabled=%d',
          [Pages, IntToHex(QuestPageHash(Run.Page), 16), Length(Run.Page.Choices),
              EnabledChoiceCount(Run.Page)]
      )
  );
  Inc(Pages);
end;

procedure THeadlessQuestPlayer.ShowError(const Text: AnsiString);
begin
  Inc(Errors);
  Emit('quest error ' + Text);
end;

function THeadlessQuestPlayer.Play(const Name: WideString): TQuestRunOutcome;
begin
  Start(Name);
  Result := Finish;
end;

procedure THeadlessQuestPlayer.Start(const Name: WideString);
begin
  FreeAndNil(Run);
  Run := TQuestRun.Create(Self);
  Run.WaitForQuestDays := True;
  Run.OpenNamed(Name);
  // A day in the quest leaves the galaxy job running, as on the screen.
  WaitForTurnCalculation;
  RaisePendingWorkerError;
end;

function THeadlessQuestPlayer.OpenVisit: Boolean;
begin
  FreeAndNil(Run);
  Run := TQuestRun.Create(Self);
  Run.WaitForQuestDays := True;
  Result := Run.Open;
  WaitForTurnCalculation;
  RaisePendingWorkerError;
end;

function THeadlessQuestPlayer.Step: Boolean;
var
  Enabled, Pick, I: Integer;
begin
  Result := False;
  if Run.Page.Outcome <> qroNone then
    Exit;
  Enabled := EnabledChoiceCount(Run.Page);
  if (Enabled = 0) or (Steps >= MaxQuestSteps) then
    Exit;
  ChooserState := ChooserState * 1664525 + 1013904223;
  Pick := (ChooserState shr 8) mod Cardinal(Enabled);
  for I := 0 to High(Run.Page.Choices) do
    if Run.Page.Choices[I].Enabled then
    begin
      if Pick = 0 then
      begin
        Inc(Steps);
        Run.Choose(I);
        Break;
      end;
      Dec(Pick);
    end;
  WaitForTurnCalculation;
  RaisePendingWorkerError;
  Result := True;
end;

function THeadlessQuestPlayer.Finish: TQuestRunOutcome;
begin
  while Step do
    ;
  Run.Close;
  WaitForTurnCalculation;
  RaisePendingWorkerError;
  Result := Run.Page.Outcome;
end;

end.
