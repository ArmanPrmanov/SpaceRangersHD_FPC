{$EXCESSPRECISION OFF}
unit QuestWatch;
{$R-}
{$Q-}
{$B-}
{$A8}

// CHANGE: ENHANCEMENT - What the watch window decides and shows, without the window
// (docs/progress/2026-10-19-text-quests-plan.md, Watching; Phase E): whom it shows, when it
// closes, its header, and the quest text cut into the paragraphs the quest screen lays out
// (TfPlanetQuest.SetQuestText uses the same cut). The window itself is NetQuestWatch; these
// are unit-tested (TestNet).
interface
uses
  QuestPage;
type
  // A paragraph of a quest text as the quest screen shows it: one label each.
  TQuestTextParagraph = record
    // The label's text: a paragraph of the normal font that does not start with a dash is
    // indented by five spaces. Ends with its line feed, but the text's last one.
    Text: WideString;
    // Inside <fix>..</fix>: the fixed-width font, never indented.
    Fixed: Boolean;
  end;
  TQuestTextParagraphs = array of TQuestTextParagraph;
  // The texts of the header, in the player's language data or English (NetQuestWatch).
  TQuestWatchTexts = record
    // '<Players>''s text quest': <Players> is the name.
    Title: WideString;
    // '<Players> finished the quest: <Outcome>.'
    Ended: WideString;
    // The outcome's word for each end (qroNone is not used).
    Outcomes: array[TQuestRunOutcome] of WideString;
    // No page has come yet.
    NoPage: WideString;
    // How to switch and close: shown under the header.
    Keys: WideString;
  end;
  // What the window knows at each poll.
  TQuestWatchState = record
    // A session runs and this machine keeps pages (NetSession.QuestPages).
    Session: Boolean;
    // This client reconnects: the reconnect's box takes the screen.
    Reconnecting: Boolean;
    // The wait the window was opened from is done: the day's film or state came, a dialogue
    // was asked, or the end turn was taken back (always False from the in-game menu).
    WaitDone: Boolean;
    // The screen under the window closes.
    ParentClosing: Boolean;
  end;

// Cuts Text as TfPlanetQuest.SetQuestText does: <fix>..</fix> parts in the fixed-width font
// (blanks and one line feed after each tag skipped), each part cut after every line feed,
// empty paragraphs left out.
function QuestTextParagraphs(const Text: WideString): TQuestTextParagraphs;
// The human the window shows next (the W key; Current 0 when it opens): the one after Current
// in Playing, from the first again after the last, the first when Current is not in Playing,
// and Current when nobody plays (the window keeps the end page it shows).
function NextWatchedHuman(const Playing: TQuestHumanIds; Current: Integer): Integer;
// Whether the window closes now. It never closes by itself on an end page: it shows the
// outcome until the player closes it or the wait it was opened from is done.
function QuestWatchMustClose(const State: TQuestWatchState): Boolean;
// The header: the title with Name, the outcome line on an end page, the NoPage line without a
// page, and the keys.
function QuestWatchHeader(
    const Page: TWatchedQuestPage;
    HavePage: Boolean;
    const Name: WideString;
    const Texts: TQuestWatchTexts
): WideString;
// Text with each of the colour tags Tags (the quest styles' highlight, whichever the player
// uses) replaced by Into, for the watch window's light background.
function RecolourQuestText(
    const Text: WideString;
    const Tags: array of WideString;
    const Into: WideString
): WideString;
implementation
uses
  EC_Str;

function QuestTextParagraphs(const Text: WideString): TQuestTextParagraphs;
var
  Paragraphs: TQuestTextParagraphs;
  Count: Integer;

  procedure AddParagraph(const Part: WideString; Fixed: Boolean);
  var
    Indent: Boolean;
    I: Integer;
  begin
    if Part = '' then
      Exit;
    // A paragraph whose first character but blanks is a dash is not indented.
    Indent := not Fixed;
    if Indent then
      for I := 1 to Length(Part) do
        if Part[I] = '-' then
        begin
          Indent := False;
          Break;
        end
        else if (Part[I] <> ' ') and (Part[I] <> #9) then
          Break;
    if Length(Paragraphs) <= Count then
      SetLength(Paragraphs, Count * 2 + 4);
    if Indent then
      Paragraphs[Count].Text := '     ' + Part
    else
      Paragraphs[Count].Text := Part;
    Paragraphs[Count].Fixed := Fixed;
    Inc(Count);
  end;

  procedure AddLines(const Part: WideString; Fixed: Boolean);
  var
    N, StartIndex, EndIndex: Integer;
  begin
    N := Length(Part);
    StartIndex := 0;
    while StartIndex < N do
    begin
      EndIndex := FindTextOffsetW(Part, #10, StartIndex);
      if EndIndex < 0 then
      begin
        AddParagraph(Copy(Part, StartIndex + 1, N - StartIndex), Fixed);
        Break;
      end;
      AddParagraph(Copy(Part, StartIndex + 1, EndIndex - StartIndex + 1), Fixed);
      StartIndex := EndIndex + 1;
    end;
  end;

  // Past the blanks and one line feed after a tag that ends before TagEnd.
  function SkipAfterTag(TagEnd, TextLength: Integer): Integer;
  begin
    Result := TagEnd;
    while (Result < TextLength)
        and ((Text[Result + 1] = ' ') or (Text[Result + 1] = #9) or (Text[Result + 1] = #13)) do
      Inc(Result);
    if (Result < TextLength) and (Text[Result + 1] = #10) then
      Inc(Result);
  end;

var
  LowerText: WideString;
  StartIndex, TagIndex, TextLength: Integer;
begin
  Paragraphs := nil;
  Count := 0;
  TextLength := Length(Text);
  LowerText := LowerCaseWideString(Text);
  StartIndex := 0;
  while StartIndex < TextLength do
  begin
    TagIndex := FindTextOffsetW(LowerText, '<fix>', StartIndex);
    if TagIndex < 0 then
    begin
      AddLines(Copy(Text, StartIndex + 1, TextLength - StartIndex), False);
      Break;
    end;
    if StartIndex < TagIndex then
      AddLines(Copy(Text, StartIndex + 1, TagIndex - StartIndex), False);
    StartIndex := SkipAfterTag(TagIndex + 5, TextLength);
    TagIndex := FindTextOffsetW(LowerText, '</fix>', StartIndex);
    if TagIndex < 0 then
    begin
      AddLines(Copy(Text, StartIndex + 1, TextLength - StartIndex), True);
      Break;
    end;
    if StartIndex < TagIndex then
      AddLines(Copy(Text, StartIndex + 1, TagIndex - StartIndex), True);
    StartIndex := SkipAfterTag(TagIndex + 6, TextLength);
  end;
  SetLength(Paragraphs, Count);
  Result := Paragraphs;
end;

function NextWatchedHuman(const Playing: TQuestHumanIds; Current: Integer): Integer;
var
  I: Integer;
begin
  if Length(Playing) = 0 then
    Exit(Current);
  for I := 0 to High(Playing) do
    if Playing[I] = Current then
      Exit(Playing[(I + 1) mod Length(Playing)]);
  Result := Playing[0];
end;

function QuestWatchMustClose(const State: TQuestWatchState): Boolean;
begin
  Result := not State.Session or State.Reconnecting or State.WaitDone or State.ParentClosing;
end;

function QuestWatchHeader(
    const Page: TWatchedQuestPage;
    HavePage: Boolean;
    const Name: WideString;
    const Texts: TQuestWatchTexts
): WideString;
var
  Line: WideString;
begin
  Result := ReplaceAllWideString(Texts.Title, '<Players>', Name);
  if not HavePage then
    Result := Result + #13#10 + Texts.NoPage
  else if Page.Page.Outcome <> qroNone then
  begin
    Line := ReplaceAllWideString(Texts.Ended, '<Players>', Name);
    Line := ReplaceAllWideString(Line, '<Outcome>', Texts.Outcomes[Page.Page.Outcome]);
    Result := Result + #13#10 + Line;
  end;
  if Texts.Keys <> '' then
    Result := Result + #13#10 + Texts.Keys;
end;

function RecolourQuestText(
    const Text: WideString;
    const Tags: array of WideString;
    const Into: WideString
): WideString;
var
  I: Integer;
begin
  Result := Text;
  for I := 0 to High(Tags) do
    if (Tags[I] <> '') and (Tags[I] <> Into) then
      Result := ReplaceAllWideString(Result, Tags[I], Into);
end;

end.
