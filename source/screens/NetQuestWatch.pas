{$EXCESSPRECISION OFF}
unit NetQuestWatch;
{$R-}
{$Q-}
{$B-}
{$A8}

// CHANGE: ENHANCEMENT - The watch window (docs/progress/2026-10-19-text-quests-plan.md,
// Watching; Phase E): a box over the innermost screen that shows another human's text quest
// as its machine shows it, read-only, from the latest page this machine has
// (NetSession.QuestPages): the quest's picture, its text, its parameters and its choices,
// greyed and not clickable. It redraws when a new page comes, keeps the end page with its
// outcome until it is closed, and W shows the next human who plays one. Escape, Enter and the
// button close it. It opens no game screen and closes none, so no OnOpen or OnClose command
// runs; it submits nothing and changes no game state. The caller's poll pumps the network and
// says when it must close (NetPlay: from a wait for the day, or from the in-game menu). The
// decisions and texts are QuestWatch's; the dialog is built in code like NetMenus' with the
// message box's window, fonts and buttons.
interface
type
  // Pumps the network; true when the window must close now.
  TQuestWatchPoll = function: Boolean;

// Shows HumanId's quest over the innermost screen until it is closed or Poll says so; then
// HumanId is the human it showed last.
procedure RunQuestWatch(var HumanId: Integer; Poll: TQuestWatchPoll);
implementation
uses
  Classes,
  Math,
  SysUtils,
  Types,
  Windows,
  EC_Str,
  GI_GraphBuf,
  GI_GraphButton,
  GI_Label,
  GI_Main,
  GI_MessageBox,
  GI_MessageLoop,
  GI_Panel,
  GI_PanelScrollBar,
  GI_Window,
  GR_Main,
  Globals,
  GlobalsV,
  NetPlay,
  NetSession,
  fPlanetQuest,
  QuestPage,
  QuestRun,
  QuestWatch;

const
  // How often the window looks for a new page and asks the poll.
  WatchPollMs = 100;
  BoxWidth = 760;
  BoxHeight = 560;
  PictureWidth = 220;
  Gap = 8;
  // The colours of the message box: its text, its highlight, a greyed choice.
  HighlightTag = '<color=0,50,200>';

type
  TQuestStyleTags = array of WideString;
  TQuestWatchBoxGI = class(TMessageLoopGI)
    HumanId: Integer;
    Poll: TQuestWatchPoll;
    PollTimer: PCallbackTimerGI;
    Window: TWindowGI;
    Header: TLabelGI;
    ScrollPanel: TPanelScrollBarGI;
    Picture: TGraphBufGI;
    Borders: TRect;
    // What is shown: the store's change count, and the page.
    ShownChange: Cardinal;
    Shown: Boolean;
    ShownHuman, ShownRun, ShownNumber: Integer;
    ShownPicture: WideString;
    // The line height of the scrolled text, its small scroll step.
    LineHeight: Integer;
    procedure OnOpen; override;
    procedure OnClose; override;
    procedure ProcessCallbackTimers; override;
    procedure ProcessMouseWheel(KeyState: Cardinal; Point: TPoint; Delta: Integer); override;
    procedure PollWatch(Timer: PCallbackTimerGI; UserData: PtrInt);
    procedure CloseClicked(Sender: TObjectGI);
    procedure WatchKeyDown(Sender: TObjectGI; Key: Cardinal);
    procedure Refresh(Force: Boolean);
    procedure ShowPage(const Page: TWatchedQuestPage; HavePage: Boolean);
    procedure ShowHeader(const Page: TWatchedQuestPage; HavePage: Boolean);
    function ShowPicture(const Name: WideString): Integer;
    function AddText(Top: Integer; const Text: WideString; Fixed: Boolean; Color: Cardinal): Integer;
  end;

function WatchTexts: TQuestWatchTexts;
begin
  Result := Default(TQuestWatchTexts);
  Result.Title := MultiplayerText('WatchTitle', '<Players>''s text quest');
  Result.Ended := MultiplayerText('WatchEnded', '<Players> finished the quest: <Outcome>.');
  Result.Outcomes[qroSuccess] := MultiplayerText('WatchSuccess', 'success');
  Result.Outcomes[qroFailure] := MultiplayerText('WatchFailure', 'failure');
  Result.Outcomes[qroDeath] := MultiplayerText('WatchDeath', 'death');
  Result.Outcomes[qroAbandoned] := MultiplayerText('WatchAbandoned', 'abandoned');
  Result.NoPage := MultiplayerText('WatchNoPage', 'Nothing to show yet.');
end;

// The quest styles' highlight tags, whichever the player's machine uses.
function StyleTags: TQuestStyleTags;
var
  I: Integer;
begin
  SetLength(Result, Max(4, QuestStyleCount));
  for I := 0 to High(Result) do
    Result[I] := QuestTextColorTag(I);
end;

function CreateCloseButton(Owner: TObjectGI): TGraphButtonGI;
begin
  Result := TGraphButtonGI.Create(Owner);
  Result.EnterSound := 'Sound.ButtonEnter';
  Result.LeaveSound := 'Sound.ButtonLeave';
  Result.ClickSound := 'Sound.ButtonClick';
  Result.UpOnlyDown := True;
  Result.SetDepth(0);
  Result.SetImageNormalPath('GI,Bm.FormMessageBox.' + GiResourceSuffix + 'OkN');
  Result.SetImageNormalActivePath('GI,Bm.FormMessageBox.' + GiResourceSuffix + 'OkA');
  Result.SetImageDownPath('GI,Bm.FormMessageBox.' + GiResourceSuffix + 'OkD');
  Result.SetSize(Result.GetMaxStateImageSize);
  Result.HitKind := gbhRect;
end;

procedure TQuestWatchBoxGI.OnOpen;
var
  CloseButton: TGraphButtonGI;
  Size: TPoint;
  HeaderHeight: Integer;
begin
  ContentPanel.KeyDownCallback := WatchKeyDown;
  Window := TWindowGI.Create(ContentPanel);
  Window.SetDepth(1);
  Window.SetConfigPath('Style.Window.' + GiResourceSuffix + 'MessageBox');
  Window.SetSize(
      Classes.Point(
          Min(GiScalePixels(BoxWidth), GameScreenWidth - GiScalePixels(20)),
          Min(GiScalePixels(BoxHeight), GameScreenHeight - GiScalePixels(20))
      )
  );
  Window.UpdateAutoGeometry;
  Borders := Window.WorkSubRect;
  Size := Window.ClientSize;
  CloseButton := CreateCloseButton(ContentPanel);
  CloseButton.SetPosition(
      Classes.Point(
          Size.X div 2 - CloseButton.ClientSize.X div 2,
          Size.Y - Borders.Bottom - CloseButton.ClientSize.Y
      )
  );
  CloseButton.UpdateStateImagePlacement;
  CloseButton.UpdateStateVisuals;
  CloseButton.UpCallback := CloseClicked;
  Header := TLabelGI.Create(ContentPanel);
  Header.SetDepth(0);
  Header.SetFontName(NormalBoldFontName);
  Header.SetTextColor(CurrentPixelFormat.PackRgbBytes(0, 0, 0));
  Header.SetTextAlignX(taxLeft);
  Header.SetTextAlignY(tayTop);
  Header.SetWordWrapEnabled(True);
  Header.SetText('W');
  // The title, the outcome and the keys.
  HeaderHeight := Header.GetLineHeight * 3 + GiScalePixels(4);
  Header.SetPosition(Classes.Point(Borders.Left, Borders.Top));
  Header.SetSize(Classes.Point(Size.X - Borders.Left - Borders.Right, HeaderHeight));
  ScrollPanel := TPanelScrollBarGI.Create(Window);
  ScrollPanel.SetDepth(9);
  ScrollPanel.SetUnlimitedWorldEnabled(False);
  ScrollPanel.SetScrollbarsOutside(True);
  ScrollPanel.SetVerticalScrollBarConfigPath('Style.ScrollBar.' + GiResourceSuffix + 'PQS2');
  ScrollPanel.SetHorizontalScrollbarEnabled(False);
  ScrollPanel.SetVerticalScrollbarEnabled(True);
  ScrollPanel.ScrollAxis := psaVertical;
  ScrollPanel.SetPosition(
      Classes.Point(Borders.Left, Borders.Top + HeaderHeight + GiScalePixels(Gap))
  );
  ScrollPanel.SetSize(
      Classes.Point(
          Size.X - Borders.Right - ScrollPanel.LocalPosition.X - ScrollPanel.VerticalScrollBar.ClientSize.X,
          CloseButton.LocalPosition.Y - ScrollPanel.LocalPosition.Y - GiScalePixels(Gap)
      )
  );
  Picture := TGraphBufGI.Create(Window, False);
  Picture.SetDepth(9);
  Picture.SetActive(False);
  ViewportRect.Left := GameScreenWidth shr 1 - Size.X div 2;
  ViewportRect.Top := GameScreenHeight shr 1 - Size.Y div 2;
  ViewportRect.Right := ViewportRect.Left + Size.X;
  ViewportRect.Bottom := ViewportRect.Top + Size.Y;
  ContentPanel.SetPosition(ViewportRect.TopLeft);
  ContentPanel.SetSize(Size);
  Refresh(True);
  ContentPanel.UpdateAbsolutePosition;
  ContentPanel.UpdateSubtreeHitBounds;
  PollTimer := ScheduleCallbackTimer(WatchPollMs, WatchPollMs, PollWatch);
end;

procedure TQuestWatchBoxGI.OnClose;
begin
  if PollTimer <> nil then
  begin
    CancelCallbackTimer(PollTimer);
    PollTimer := nil;
  end;
end;

procedure TQuestWatchBoxGI.ProcessCallbackTimers;
begin
  inherited ProcessCallbackTimers;
  if (ParentLoop.ExitCode <> 0) and (ExitCode = 0) then
    RequestClose(255);
end;

procedure TQuestWatchBoxGI.ProcessMouseWheel(KeyState: Cardinal; Point: TPoint; Delta: Integer);
begin
  with ScrollPanel.VerticalScrollBar do
    if Delta = WHEEL_DELTA then
      SetPosition(Position - SmallChange)
    else if Delta = -WHEEL_DELTA then
      SetPosition(Position + SmallChange);
end;

procedure TQuestWatchBoxGI.CloseClicked(Sender: TObjectGI);
begin
  if ExitCode = 0 then
    RequestClose(mbgResultOK);
end;

// Escape and Enter close the window; W shows the next human who plays a quest.
procedure TQuestWatchBoxGI.WatchKeyDown(Sender: TObjectGI; Key: Cardinal);
var
  Next: Integer;
begin
  if (Key = VK_ESCAPE) or (Key = VK_RETURN) then
    CloseClicked(Sender)
  else if Key = Ord('W') then
  begin
    Next := NextWatchedHuman(WatchableQuestHumans, HumanId);
    if Next <> HumanId then
    begin
      HumanId := Next;
      Refresh(True);
    end;
  end;
end;

procedure TQuestWatchBoxGI.PollWatch(Timer: PCallbackTimerGI; UserData: PtrInt);
begin
  if ExitCode <> 0 then
    Exit;
  if Poll() then
    RequestClose(mbgResultOK)
  else
    Refresh(False);
end;

// Shows the human's latest page when it is another than the one shown.
procedure TQuestWatchBoxGI.Refresh(Force: Boolean);
var
  Store: TQuestPageStore;
  Page: TWatchedQuestPage;
  HavePage: Boolean;
begin
  Store := QuestPages;
  if Store = nil then
    Exit;
  if not Force and (Store.ChangeCount = ShownChange) then
    Exit;
  ShownChange := Store.ChangeCount;
  HavePage := Store.Latest(HumanId, Page);
  if not Force
      and Shown
      and (HavePage = (ShownRun <> 0))
      and (ShownHuman = HumanId)
      and (Page.Run = ShownRun)
      and (Page.Number = ShownNumber) then
  begin
    // Another human's page: whether W has another quest to show may have changed.
    ShowHeader(Page, HavePage);
    Exit;
  end;
  Shown := True;
  ShownHuman := HumanId;
  ShownRun := Page.Run;
  ShownNumber := Page.Number;
  ShowPage(Page, HavePage);
end;

// The quest's picture at the right of the text, as wide as PictureWidth at most; its width,
// or 0 without one (none, or not in this machine's data).
function TQuestWatchBoxGI.ShowPicture(const Name: WideString): Integer;
var
  Width, Height: Integer;
  Scale: Double;
begin
  Result := 0;
  if Name = '' then
  begin
    Picture.SetActive(False);
    ShownPicture := '';
    Exit;
  end;
  if Name <> ShownPicture then
  begin
    ShownPicture := Name;
    try
      if not CacheDataRoot.FileExistsByPath('Bm.PQI.' + Name) then
        Abort;
      Picture.LoadBitmapPathAsRgb('Bm.PQI.' + Name + '?RGB');
      Width := Picture.GraphBuf.Width;
      Height := Picture.GraphBuf.Height;
      Scale := Min(
          1.0,
          Min(GiScalePixels(PictureWidth) / Max(1, Width), ScrollPanel.ClientSize.Y / Max(1, Height))
      );
      if Scale < 1.0 then
        Picture.GraphBuf.RescaleRgb(Max(1, Round(Width * Scale)), Max(1, Round(Height * Scale)));
      Picture.GraphBuf.ConvertRgbTo565;
      Picture.SetSize(Classes.Point(Picture.GraphBuf.Width, Picture.GraphBuf.Height));
    except
      ShownPicture := '';
    end;
  end;
  if ShownPicture = '' then
  begin
    Picture.SetActive(False);
    Exit;
  end;
  Picture.SetPosition(
      Classes.Point(
          Window.ClientSize.X - Borders.Right - Picture.ClientSize.X,
          ScrollPanel.LocalPosition.Y
      )
  );
  Picture.SetActive(True);
  Picture.Invalidate;
  Result := Picture.ClientSize.X;
end;

// A word-wrapped label in the scrolled panel at Top; the top of the next.
function TQuestWatchBoxGI.AddText(
    Top: Integer;
    const Text: WideString;
    Fixed: Boolean;
    Color: Cardinal
): Integer;
var
  TextLabel: TLabelGI;
begin
  TextLabel := TLabelGI.Create(ScrollPanel);
  if Fixed then
    TextLabel.SetFontName('Font.' + GiResourceSuffix + 'Fix')
  else
    TextLabel.SetFontName(NormalFontName);
  TextLabel.SetPosition(Classes.Point(0, Top));
  TextLabel.SetSize(Classes.Point(ScrollPanel.ClientSize.X, 1));
  TextLabel.SetWordWrapEnabled(True);
  TextLabel.SetTextAlignX(taxLeft);
  TextLabel.SetTextAlignY(tayAuto);
  TextLabel.SetText(Text);
  TextLabel.SetPositionModeW(True);
  TextLabel.SetTextColor(Color);
  TextLabel.SetTextAlignY(tayTop);
  TextLabel.SetSize(
      Classes.Point(
          TextLabel.ClientSize.X,
          Max(1, TextLabel.GetRenderedLineCount) * TextLabel.GetLineHeight + 4
      )
  );
  if LineHeight = 0 then
    LineHeight := TextLabel.GetLineHeight;
  Result := TextLabel.LocalPosition.Y + TextLabel.ClientSize.Y - 2;
end;

// The title, the outcome on an end page, and the keys (W only while it has another to show).
procedure TQuestWatchBoxGI.ShowHeader(const Page: TWatchedQuestPage; HavePage: Boolean);
var
  Texts: TQuestWatchTexts;
  Text: WideString;
begin
  Texts := WatchTexts;
  if NextWatchedHuman(WatchableQuestHumans, HumanId) <> HumanId then
    Texts.Keys := MultiplayerText('WatchKeys', 'W: the next player''s quest. Escape: close.')
  else
    Texts.Keys := MultiplayerText('WatchKeysOne', 'Escape: close.');
  Text :=
      QuestWatchHeader(Page, HavePage, HighlightTag + NetHumanName(HumanId) + '</color>', Texts);
  if Text <> Header.GetText then
  begin
    Header.SetText(Text);
    Header.Invalidate;
  end;
end;

procedure TQuestWatchBoxGI.ShowPage(const Page: TWatchedQuestPage; HavePage: Boolean);
var
  Tags: TQuestStyleTags;
  Paragraphs: TQuestTextParagraphs;
  Black, Grey: Cardinal;
  Top, I, PictureSpace: Integer;
  Parameters: WideString;
  Fixed: Boolean;
begin
  ShowHeader(Page, HavePage);
  Tags := StyleTags;
  Black := CurrentPixelFormat.PackRgbBytes(0, 0, 0);
  Grey := CurrentPixelFormat.PackRgbBytes(120, 120, 120);
  ScrollPanel.FreeOwnedChildren;
  // The text keeps clear of the picture.
  PictureSpace := 0;
  if HavePage then
    PictureSpace := ShowPicture(Page.Page.Picture)
  else
    ShowPicture('');
  if PictureSpace > 0 then
    Inc(PictureSpace, GiScalePixels(Gap));
  ScrollPanel.SetSize(
      Classes.Point(
          Window.ClientSize.X
              - Borders.Right
              - ScrollPanel.LocalPosition.X
              - ScrollPanel.VerticalScrollBar.ClientSize.X
              - PictureSpace,
          ScrollPanel.ClientSize.Y
      )
  );
  ScrollPanel.UpdateScrollbarPlacement;
  Top := 0;
  if HavePage then
  begin
    Paragraphs := QuestTextParagraphs(RecolourQuestText(Page.Page.Text, Tags, HighlightTag));
    for I := 0 to High(Paragraphs) do
      Top := AddText(Top, Paragraphs[I].Text, Paragraphs[I].Fixed, Black);
    // The parameters, as the quest screen's panel shows them.
    Parameters := Page.Page.Parameters;
    if TrimWideString(RemoveTextTagsW(Parameters)) <> '' then
    begin
      Fixed := FindTextOffsetW(LowerCaseWideString(Parameters), '<fix>') >= 0;
      Parameters := RemoveMatchingTextTagsW(Parameters, 'fix', 'FIX');
      Parameters := RemoveMatchingTextTagsW(Parameters, '/fix', '/FIX');
      Top := AddText(
          Top + GiScalePixels(Gap),
          RecolourQuestText(Parameters, Tags, HighlightTag),
          Fixed,
          Black
      );
    end;
    // The choices: what the player may pick in black, the rest grey; none is clickable.
    if Length(Page.Page.Choices) > 0 then
      Inc(Top, GiScalePixels(Gap));
    for I := 0 to High(Page.Page.Choices) do
      if Page.Page.Choices[I].Enabled then
        Top := AddText(
            Top,
            '- ' + RecolourQuestText(Page.Page.Choices[I].Text, Tags, HighlightTag),
            False,
            Black
        )
      else
        Top := AddText(Top, '- ' + RemoveTextTagsW(Page.Page.Choices[I].Text), False, Grey);
  end;
  ScrollPanel.SetScrollOffset(Classes.Point(0, 0));
  ScrollPanel.SetVerticalScrollbarEnabled(ScrollPanel.ClientSize.Y < Top);
  if LineHeight > 0 then
    ScrollPanel.VerticalScrollBar.SetSmallChange(LineHeight);
  ScrollPanel.VerticalScrollBar.SetLargeChange(ScrollPanel.ClientSize.Y);
  ScrollPanel.VerticalScrollBar.SetPageSize(ScrollPanel.ClientSize.Y);
  ScrollPanel.UpdateScrollRanges;
  ScrollPanel.Invalidate;
  ContentPanel.UpdateAbsolutePosition;
  ContentPanel.UpdateSubtreeHitBounds;
  InvalidateViewport;
end;

procedure RunQuestWatch(var HumanId: Integer; Poll: TQuestWatchPoll);
var
  Parent: TMessageLoopGI;
  Box: TQuestWatchBoxGI;
  CursorState: TCursorStateGI;
  Closed: Cardinal;
begin
  Parent := GetInnermostScreenLoop;
  if (Parent = nil) or (HumanId = 0) or Poll() then
    Exit;
  Parent.RootUiObject.NativeHook50;
  Parent.CaptureCursorState(@CursorState);
  Parent.SetCursorActive(False);
  Parent.DrawQueuedUpdateRects;
  Box := TQuestWatchBoxGI.Create;
  Box.ParentLoop := Parent;
  Parent.ChildLoop := Box;
  Box.InitializeDefaults;
  try
    Box.HumanId := HumanId;
    Box.Poll := Poll;
    Closed := Box.Run;
    HumanId := Box.HumanId;
    Parent.InvalidateViewport;
  finally
    Parent.ChildLoop := nil;
    Box.Free;
  end;
  Parent.RestoreCursorState(@CursorState);
  Parent.UpdateCursorPosition;
  Parent.RootUiObject.NativeHook48;
  if Closed = 254 then
    BreakUiMessage;
end;

end.
