{$EXCESSPRECISION OFF}
unit QuestPage;
{$R-}
{$Q-}
{$B-}
{$A8}

// CHANGE: ENHANCEMENT - The page of a text quest as shown, and the form it travels in to the
// players who watch it (docs/progress/2026-10-19-text-quests-plan.md, Watching; Phase D). The
// run (QuestRun) keeps its page as a TQuestPage; after each page and at the end it tells
// QuestPageHook a TWatchedQuestPage, which a session sends to the host and the host to every
// other client. Every machine keeps the latest page of each human in a TQuestPageStore for its
// watch window. A page is presentation only: no command, not in the command log, not in a
// state or its hash, and nothing about it changes the game.
interface
uses
  EC_Buf;
type
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
  // A page for the watchers: whose quest, which run of it on the player's machine (from 1, one
  // more for each quest that machine starts), which page of the run (from 1), the quest's name
  // (its number or file name) and the page. A choice travels as its text and whether it is
  // enabled: its action and value stay with the player (qcaNone and 0 here). A page with an
  // outcome is the run's end page, its last.
  TWatchedQuestPage = record
    HumanId: Integer;
    Run: Integer;
    Number: Integer;
    QuestName: WideString;
    Page: TQuestPage;
  end;
  TQuestHumanIds = array of Integer;
  // The latest page of each human, as this machine has it. The host's and each client's
  // (NetSession.QuestPages) are for the watch window: whose quest is open (Playing), its page
  // (Latest), and ChangeCount, which goes up with every page put, so a window can redraw when
  // it changes.
  TQuestPageStore = class
  private
    FPages: array of TWatchedQuestPage;
    FChangeCount: Cardinal;
    function IndexOf(HumanId: Integer): Integer;
  public
    // Keeps Page as its human's latest.
    procedure Put(const Page: TWatchedQuestPage);
    // The latest page of the human; False when none came.
    function Latest(HumanId: Integer; out Page: TWatchedQuestPage): Boolean;
    // The human's latest page is not an end page: its quest is open.
    function Playing(HumanId: Integer): Boolean;
    // The humans whose quest is open, in the order their first page came, but ExceptId (0:
    // none left out).
    function PlayingHumans(ExceptId: Integer = 0): TQuestHumanIds;
    // Forgets every page (a client's reconnect: the host sends the open ones again).
    procedure Clear;
    property ChangeCount: Cardinal read FChangeCount;
  end;

var
  // Told every page a run on this machine shows for its local human: after the start, after
  // each choice, and the end page when it closes (TQuestRun). Set by a session
  // (NetSession.StartHosting, JoinGame); nil otherwise, and then no page is made.
  QuestPageHook: procedure(const Page: TWatchedQuestPage);

procedure EncodeWatchedQuestPage(const Page: TWatchedQuestPage; Buffer: TBufEC);
// Raises on a payload that is not a page.
function DecodeWatchedQuestPage(Buffer: TBufEC): TWatchedQuestPage;
// A hash of the page as it travels (its encoding): equal on the player's machine and on every
// machine that received it.
function WatchedQuestPageHash(const Page: TWatchedQuestPage): QWord;
// The run's end page after its last page Page, when the run is left without one (the host
// lost the player): the next number, no choices, abandoned.
function AbandonedQuestPage(const Page: TWatchedQuestPage): TWatchedQuestPage;
function QuestOutcomeName(Outcome: TQuestRunOutcome): AnsiString;
implementation
uses
  SysUtils,
  aObjectRefs;

const
  // A page has a handful of choices; more is a broken payload.
  MaxPageChoices = 1000;

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

procedure EncodeWatchedQuestPage(const Page: TWatchedQuestPage; Buffer: TBufEC);
var
  I: Integer;
begin
  Buffer.AddInt32(Page.HumanId);
  Buffer.AddInt32(Page.Run);
  Buffer.AddInt32(Page.Number);
  Buffer.AddWideStringZ(Page.QuestName);
  Buffer.AddWideStringZ(Page.Page.Text);
  Buffer.AddWideStringZ(Page.Page.Picture);
  Buffer.AddWideStringZ(Page.Page.Parameters);
  Buffer.AddInt32(Length(Page.Page.Choices));
  for I := 0 to High(Page.Page.Choices) do
  begin
    Buffer.AddBoolean(Page.Page.Choices[I].Enabled);
    Buffer.AddWideStringZ(Page.Page.Choices[I].Text);
  end;
  Buffer.AddByte(Ord(Page.Page.Outcome));
end;

function DecodeWatchedQuestPage(Buffer: TBufEC): TWatchedQuestPage;
var
  I, Count: Integer;
  Outcome: Byte;
begin
  Result := Default(TWatchedQuestPage);
  Result.HumanId := Buffer.GetInt32;
  Result.Run := Buffer.GetInt32;
  Result.Number := Buffer.GetInt32;
  Result.QuestName := Buffer.ReadWideString;
  Result.Page.Text := Buffer.ReadWideString;
  Result.Page.Picture := Buffer.ReadWideString;
  Result.Page.Parameters := Buffer.ReadWideString;
  Count := Buffer.GetInt32;
  if (Count < 0) or (Count > MaxPageChoices) then
    raise Exception.Create('Bad quest page');
  SetLength(Result.Page.Choices, Count);
  for I := 0 to Count - 1 do
  begin
    Result.Page.Choices[I].Enabled := Buffer.GetBoolean;
    Result.Page.Choices[I].Text := Buffer.ReadWideString;
  end;
  Outcome := Buffer.GetByte;
  if Outcome > Ord(High(TQuestRunOutcome)) then
    raise Exception.Create('Bad quest page');
  Result.Page.Outcome := TQuestRunOutcome(Outcome);
end;

function WatchedQuestPageHash(const Page: TWatchedQuestPage): QWord;
var
  Buffer: TBufEC;
begin
  Buffer := TBufEC.Create;
  try
    EncodeWatchedQuestPage(Page, Buffer);
    Result := HashBytes(PByte(Buffer.Data), Buffer.DataSize);
  finally
    Buffer.Free;
  end;
end;

function AbandonedQuestPage(const Page: TWatchedQuestPage): TWatchedQuestPage;
begin
  Result := Page;
  Inc(Result.Number);
  Result.Page.Choices := nil;
  Result.Page.Outcome := qroAbandoned;
end;

function TQuestPageStore.IndexOf(HumanId: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FPages) do
    if FPages[I].HumanId = HumanId then
      Exit(I);
  Result := -1;
end;

procedure TQuestPageStore.Put(const Page: TWatchedQuestPage);
var
  I: Integer;
begin
  I := IndexOf(Page.HumanId);
  if I < 0 then
  begin
    I := Length(FPages);
    SetLength(FPages, I + 1);
  end;
  FPages[I] := Page;
  Inc(FChangeCount);
end;

function TQuestPageStore.Latest(HumanId: Integer; out Page: TWatchedQuestPage): Boolean;
var
  I: Integer;
begin
  I := IndexOf(HumanId);
  Result := I >= 0;
  if Result then
    Page := FPages[I]
  else
    Page := Default(TWatchedQuestPage);
end;

function TQuestPageStore.Playing(HumanId: Integer): Boolean;
var
  I: Integer;
begin
  I := IndexOf(HumanId);
  Result := (I >= 0) and (FPages[I].Page.Outcome = qroNone);
end;

function TQuestPageStore.PlayingHumans(ExceptId: Integer): TQuestHumanIds;
var
  I, Count: Integer;
begin
  Result := nil;
  Count := 0;
  for I := 0 to High(FPages) do
    if (FPages[I].Page.Outcome = qroNone) and (FPages[I].HumanId <> ExceptId) then
    begin
      SetLength(Result, Count + 1);
      Result[Count] := FPages[I].HumanId;
      Inc(Count);
    end;
end;

procedure TQuestPageStore.Clear;
begin
  if Length(FPages) = 0 then
    Exit;
  FPages := nil;
  Inc(FChangeCount);
end;

end.
