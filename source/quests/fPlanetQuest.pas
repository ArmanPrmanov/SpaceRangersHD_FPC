{$EXCESSPRECISION OFF}
unit fPlanetQuest;
{$R-}
{$Q-}
{$B-}
{$A8}
interface
uses
  EC_BlockPar,
  EC_CacheFont,
  GI_Label,
  GI_MessageLoop,
  QuestPage,
  QuestRun,
  QuestWatch,
  Types;
type
  TPlanetQuestView = class;
  TfPlanetQuest = class;
  // CHANGE: ENHANCEMENT - The screen is the view of a TQuestRun (QuestRun; docs/progress/
  // 2026-10-19-text-quests-plan.md, Phase A): the run plays the quest and does what it does to
  // the game; the screen lays out its page, maps the clicks and keys to TQuestRun.Choose, and
  // keeps the boxes and the screen changes. A choice's panel holds its index plus one in
  // UserValue (0: played).
  // CHANGE: ENHANCEMENT - In multiplayer (IsMultiplayer; docs/progress/
  // 2026-10-19-text-quests-plan.md, rule 3) a quest always ends by its own choices: no exit
  // (Escape, the exit button), no reload (R), no "load the autosave?" box after a failure or
  // a death, which respawns the ranger (TQuestRun.Respawned).
  TfPlanetQuest = class(TMessageLoopGI)
    Run: TQuestRun;
    QuestView: TPlanetQuestView;
    CurrentPicture: WideString;
    NextChoiceTop: Integer;
    ParameterPanelWidth: Integer;
    ParameterPanelHeight: Integer;
    PageAnimationTimer: PCallbackTimerGI;
    PreviousStyleIndex: PtrInt;
    ChoiceCount: Integer;
    Gap104: array[0..1] of Byte;
    ParameterPanelOrigin: TPoint;
    Gap10E: array[0..1] of Byte;
    procedure OnOpen; override;
    procedure OnClose; override;
    procedure SelectMusic; override;
    procedure ProcessMouseWheel(KeyState: Cardinal; Point: TPoint; Delta: Integer); override;
    procedure InitializeLayout; override;
    procedure ExecuteUiCode(Block: TBlockParEC; Key: Cardinal); override;
    procedure ClearChoices;
    procedure AddChoice(Index: Integer; const Text: WideString);
    procedure AddDisabledChoice(Index: Integer; const Text: WideString);
    function CreateChoiceInlineObject(Sender: TLabelGI; Item: PFontObjectEC): TObjectGI;
    procedure ChoiceMouseEnter(Sender: TObjectGI);
    procedure ChoiceMouseLeave(Sender: TObjectGI);
    procedure ChoiceMouseDown(Sender: TObjectGI; KeyState: Cardinal; Point: TPoint);
    procedure ChoiceMouseUp(Sender: TObjectGI; KeyState: Cardinal; Point: TPoint);
    procedure DisabledChoiceMouseEnter(Sender: TObjectGI);
    procedure DisabledChoiceMouseLeave(Sender: TObjectGI);
    procedure DisabledChoiceMouseUp(Sender: TObjectGI; KeyState: Cardinal; Point: TPoint);
    procedure FinishChoiceLayout;
    procedure AnimateTextPage(Timer: PCallbackTimerGI; UserData: PtrInt);
    procedure ClearParameterPanel;
    procedure AppendParameterText(Text: WideString);
    procedure LayoutParameterPanel;
    procedure SetQuestText(const Text: WideString);
    function GetTextColorTag(StyleIndex: Integer): WideString;
    function GetTextColor(StyleIndex: Integer): Cardinal;
    function GetDisabledTextColor(StyleIndex: Integer): Cardinal;
    procedure ApplyStyle;
    procedure SelectPageMode(Sender: TObjectGI);
    procedure SelectStyle(Sender: TObjectGI);
    procedure ShowControlHelp(Sender: TObjectGI; Visible: Boolean);
    procedure SetQuestPicture(Name: WideString);
    procedure RequestLoadGame(Sender: TObjectGI);
    procedure QuestKeyDown(Sender: TObjectGI; VirtualKey: Cardinal);
    function ConfirmQuestDeath: Boolean;
    procedure EndQuest(Outcome: TQuestRunOutcome);
    // CHANGE: ENHANCEMENT - The quest is a game's, not the one the main menu runs (galaxy,
    // player, StandaloneQuestMode off): a networked game's screen (NetPlay).
    function PlaysGameQuest: Boolean;
    // CHANGE: ENHANCEMENT - A networked client reconnected while it played the quest
    // (docs/progress/2026-10-19-text-quests-plan.md, Disconnects): the run is left without
    // CloseQuest (TQuestRun.Abandon), and the caller closes the screen.
    procedure AbandonQuest;
  end;
  // CHANGE: ENHANCEMENT - What the run shows goes to the screen (was TTextQuestPlayerInterface).
  TPlanetQuestView = class(TQuestView)
    Screen: TfPlanetQuest;
    constructor Create(AScreen: TfPlanetQuest);
    procedure ShowText(const Text: WideString); override;
    procedure ShowPicture(const Name: WideString); override;
    procedure PlayMusic(const Name: WideString); override;
    procedure PlaySound(const Name: WideString); override;
    procedure ShowParameters(const Text: WideString); override;
    procedure ClearChoices; override;
    procedure AddChoice(Index: Integer; const Choice: TQuestChoice); override;
    procedure FinishPage; override;
    function ConfirmDeath: Boolean; override;
    procedure EndQuest(Outcome: TQuestRunOutcome); override;
  end;
var
  QuestStyleCount: Integer = 0;
procedure LinkRecoveredTypes;
implementation
uses
  aHuman,
  aSession,
  aSaveLoad,
  aPlayerActions,
  aQuestActions,
  Windows,
  Classes,
  Math,
  GI_GraphBuf,
  GI_GraphButton,
  GI_ScrollBar,
  GI_Window,
  EC_Cache,
  EC_CacheBuf,
  EC_Expression,
  EC_Str,
  GI_Image,
  GI_Main,
  GI_Panel,
  GI_PanelScrollBar,
  Globals,
  GlobalsV,
  GR_Main,
  SysUtils,
  ThreadCalc,
  aCalc,
  aConst,
  aGalaxy,
  aPlayer,
  GI_MessageBox,
  fSaveManager,
  fScore,
  fLoadQuest,
  fHangar,
  aShip,
  aPlanet,
  aItem,
  Achievements,
  aGalaxyStruct,
  aMyFunction,
  aScript;

procedure TfPlanetQuest.ClearChoices;
var
  Panel: TPanelScrollBarGI;
  Spacer: TPanelGI;
begin
  Panel := GetByName('ActionListWindow') as TPanelScrollBarGI;
  Panel.FreeOwnedChildren;
  Panel.Invalidate;
  NextChoiceTop := 10;
  ParameterPanelWidth := 0;
  ParameterPanelHeight := 0;
  ChoiceCount := 0;
  Spacer := TPanelGI.Create(GetByName('ActionListWindow'));
  Spacer.SetPosition(Classes.Point(0, 0));
  Spacer.SetSize(Classes.Point(10, 10));
  Spacer.SetPositionModeW(True);
end;

procedure TfPlanetQuest.AddChoice(Index: Integer; const Text: WideString);
var
  Owner: TPanelScrollBarGI;
  Panel: TPanelGI;
  Highlight: TImageGI;
  Path: WideString;
  TextLabel: TLabelGI;
begin
  Owner := GetByName('ActionListWindow') as TPanelScrollBarGI;
  Panel := TPanelGI.Create(Owner);
  Panel.UserValue := Index + 1;
  Panel.SetName(IntToStr(ChoiceCount));
  Panel.SetPosition(Classes.Point(0, NextChoiceTop));
  Panel.SetSize(Classes.Point(Owner.ClientSize.X, 20));
  Panel.SetPositionModeW(True);
  Panel.MouseEnterCallback := ChoiceMouseEnter;
  Panel.MouseLeaveCallback := ChoiceMouseLeave;
  Panel.LeftButtonDownCallback := ChoiceMouseDown;
  Panel.LeftButtonUpCallback := ChoiceMouseUp;
  Highlight := TImageGI.Create(Panel);
  Highlight.SetDepth(3);
  Highlight.SetPosition(Classes.Point(0, 0));
  Highlight.SetSize(Classes.Point(Owner.ClientSize.X, 20));
  Path :=
      'Bm.FormPQuest2.' + GiResourceSuffix + 'S' + IntToWideString(QuestStyleIndex + 1) + 'Line';
  if CacheDataRoot.FileExistsByPath(Path) then
    Highlight.SetImagePath('GI,' + Path)
  else
    Highlight.SetImagePath('GI,Bm.FormPQuest2.' + GiResourceSuffix + 'S1Line');
  Highlight.SetImageKindX(ikxLeftFill);
  Highlight.SetImageKindY(ikyTopFill);
  Highlight.SetActive(False);
  TextLabel := TLabelGI.Create(Panel);
  TextLabel.SetName(IntToStr(ChoiceCount));
  if FontQuest = 0 then
    TextLabel.SetFontName(NormalFontName)
  else if FontQuest = 1 then
    TextLabel.SetFontName(SmoothBigFontName)
  else if FontQuest = 2 then
    TextLabel.SetFontName(SmoothHugeFontName)
  else if FontQuest >= 3 then
    TextLabel.SetFontName(SmoothIntroFontName);
  TextLabel.SetSize(Classes.Point(Owner.ClientSize.X - 20, 20));
  TextLabel.SetPosition(Classes.Point(10, 0));
  TextLabel.SetDepth(2);
  TextLabel.SetWordWrapEnabled(True);
  TextLabel.SetTextAlignX(taxLeft);
  TextLabel.SetTextAlignY(tayAuto);
  TextLabel.SetText('<Object=0,20,14,0>' + Text);
  TextLabel.SetPositionModeW(True);
  TextLabel.SetActive(True);
  TextLabel.CreateEmbeddedControl := CreateChoiceInlineObject;
  TextLabel.SetTextAlignY(tayCenterEx);
  TextLabel.SetTextColor(GetTextColor(QuestStyleIndex));
  Panel.SetSize(
      Classes.Point(Panel.ClientSize.X, GiScalePixelsEx(2, 1) * 2 + TextLabel.ClientSize.Y)
  );
  TextLabel.SetSize(Classes.Point(TextLabel.ClientSize.X, Panel.ClientSize.Y));
  Highlight.SetSize(Panel.ClientSize);
  Inc(NextChoiceTop, Panel.ClientSize.Y);
  Owner.VerticalScrollBar.SetSmallChange(TextLabel.GetLineHeight);
  Owner.UpdateScrollRanges;
  Inc(ChoiceCount);
end;

procedure TfPlanetQuest.AddDisabledChoice(Index: Integer; const Text: WideString);
var
  Owner: TPanelScrollBarGI;
  Panel: TPanelGI;
  Highlight: TImageGI;
  Path: WideString;
  TextLabel: TLabelGI;
begin
  Owner := GetByName('ActionListWindow') as TPanelScrollBarGI;
  Panel := TPanelGI.Create(Owner);
  Panel.SetName(IntToStr(ChoiceCount));
  Panel.SetPosition(Classes.Point(0, NextChoiceTop));
  Panel.SetSize(Classes.Point(Owner.ClientSize.X, 20));
  Panel.SetPositionModeW(True);
  Panel.MouseEnterCallback := DisabledChoiceMouseEnter;
  Panel.MouseLeaveCallback := DisabledChoiceMouseLeave;
  Panel.LeftButtonDownCallback := ChoiceMouseDown;
  Panel.LeftButtonUpCallback := DisabledChoiceMouseUp;
  Highlight := TImageGI.Create(Panel);
  Highlight.SetDepth(3);
  Highlight.SetPosition(Classes.Point(0, 0));
  Highlight.SetSize(Classes.Point(Owner.ClientSize.X, 20));
  Path :=
      'Bm.FormPQuest2.' + GiResourceSuffix + 'S' + IntToWideString(QuestStyleIndex + 1) + 'Line';
  if CacheDataRoot.FileExistsByPath(Path) then
    Highlight.SetImagePath('GI,' + Path)
  else
    Highlight.SetImagePath('GI,Bm.FormPQuest2.' + GiResourceSuffix + 'S1Line');
  Highlight.SetImageKindX(ikxLeftFill);
  Highlight.SetImageKindY(ikyTopFill);
  Highlight.SetActive(False);
  TextLabel := TLabelGI.Create(Panel);
  TextLabel.SetName(IntToStr(ChoiceCount));
  if FontQuest = 0 then
    TextLabel.SetFontName(NormalFontName)
  else if FontQuest = 1 then
    TextLabel.SetFontName(SmoothBigFontName)
  else if FontQuest = 2 then
    TextLabel.SetFontName(SmoothHugeFontName)
  else if FontQuest >= 3 then
    TextLabel.SetFontName(SmoothIntroFontName);
  TextLabel.SetSize(Classes.Point(Owner.ClientSize.X - 20, 20));
  TextLabel.SetPosition(Classes.Point(10, 0));
  TextLabel.SetDepth(2);
  TextLabel.SetWordWrapEnabled(True);
  TextLabel.SetTextAlignX(taxLeft);
  TextLabel.SetTextAlignY(tayAuto);
  TextLabel.SetText('<Object=0,20,14,0>' + Text);
  TextLabel.SetPositionModeW(False);
  TextLabel.SetActive(True);
  TextLabel.UserState := 1;
  TextLabel.CreateEmbeddedControl := CreateChoiceInlineObject;
  TextLabel.SetTextAlignY(tayCenterEx);
  TextLabel.SetTextColor(GetDisabledTextColor(QuestStyleIndex));
  Panel.SetSize(
      Classes.Point(Panel.ClientSize.X, GiScalePixelsEx(2, 1) * 2 + TextLabel.ClientSize.Y)
  );
  TextLabel.SetSize(Panel.ClientSize);
  Highlight.SetSize(Panel.ClientSize);
  Inc(NextChoiceTop, Panel.ClientSize.Y);
  Owner.UpdateScrollRanges;
  Inc(ChoiceCount);
end;

function TfPlanetQuest.CreateChoiceInlineObject(Sender: TLabelGI; Item: PFontObjectEC): TObjectGI;
var
  Path: WideString;
  Image: TImageGI;
begin
  Result := TPanelGI.Create(Sender);
  Image := TImageGI.Create(Result);
  Path :=
      'Bm.FormPQuest2.' + GiResourceSuffix + 'S' + IntToWideString(QuestStyleIndex + 1) + 'Answer';
  if Sender.UserState = 1 then
  begin
    if CacheDataRoot.FileExistsByPath(Path + 'H') then
      Image.SetImagePath('GI,' + Path + 'H')
    else
      Image.SetImagePath('GI,Bm.FormPQuest2.' + GiResourceSuffix + 'S1AnswerH');
  end
  else
  begin
    if CacheDataRoot.FileExistsByPath(Path) then
      Image.SetImagePath('GI,' + Path)
    else
      Image.SetImagePath('GI,Bm.FormPQuest2.' + GiResourceSuffix + 'S1Answer');
  end;
  Image.SetImageKindX(ikxLeft);
  Image.SetSize(Image.GetContentSize);
end;

procedure TfPlanetQuest.ChoiceMouseEnter(Sender: TObjectGI);
begin
  Sender.FirstChild.SetActive(True);
end;

procedure TfPlanetQuest.ChoiceMouseLeave(Sender: TObjectGI);
begin
  Sender.FirstChild.SetActive(False);
end;

procedure TfPlanetQuest.ChoiceMouseDown(Sender: TObjectGI; KeyState: Cardinal; Point: TPoint);
begin
  if (Sender.FirstChild <> nil)
      and (Sender.FirstChild.NextSibling <> nil)
      and (Sender.FirstChild.NextSibling.FirstChild <> nil)
      and (Sender.FirstChild.NextSibling.FirstChild.FirstChild <> nil) then
    Sender.FirstChild.NextSibling.FirstChild.FirstChild.SetPosition(Classes.Point(2, 0));
end;

procedure TfPlanetQuest.ChoiceMouseUp(Sender: TObjectGI; KeyState: Cardinal; Point: TPoint);
var
  Index: Integer;
begin
  if Galaxy <> nil then
    aCalc.WaitForTurnCalculationUI;
  Index := Integer(Sender.UserValue) - 1;
  Sender.UserValue := 0;
  // The run clears the choices, plays the choice and lays out the next page.
  if Index >= 0 then
    Run.Choose(Index)
  else
  begin
    ClearChoices;
    FinishChoiceLayout;
  end;
  if Galaxy <> nil then
    aCalc.WaitForTurnCalculationUI;
  PostMouseMoveMessage;
  BreakUiMessage;
end;

procedure TfPlanetQuest.DisabledChoiceMouseEnter(Sender: TObjectGI);
begin
  Sender.FirstChild.SetActive(True);
end;

procedure TfPlanetQuest.DisabledChoiceMouseLeave(Sender: TObjectGI);
begin
  if (Sender <> nil)
      and (Sender.FirstChild <> nil)
      and (Sender.FirstChild.NextSibling <> nil)
      and (Sender.FirstChild.NextSibling.FirstChild <> nil)
      and (Sender.FirstChild.NextSibling.FirstChild.FirstChild <> nil) then
  begin
    Sender.FirstChild.NextSibling.FirstChild.FirstChild.SetPosition(Classes.Point(0, 0));
    Sender.FirstChild.SetActive(False);
  end;
end;

procedure TfPlanetQuest.DisabledChoiceMouseUp(Sender: TObjectGI; KeyState: Cardinal; Point: TPoint);
begin
  if (Sender.FirstChild <> nil)
      and (Sender.FirstChild <> nil)
      and (Sender.FirstChild.NextSibling <> nil)
      and (Sender.FirstChild.NextSibling.FirstChild <> nil)
      and (Sender.FirstChild.NextSibling.FirstChild.FirstChild <> nil) then
    Sender.FirstChild.NextSibling.FirstChild.FirstChild.SetPosition(Classes.Point(0, 0));
end;

procedure TfPlanetQuest.ProcessMouseWheel(KeyState: Cardinal; Point: TPoint; Delta: Integer);
var
  Panel1, Panel2, Panel3, Panel4: TPanelScrollBarGI;
begin
  if Delta = WHEEL_DELTA then
  begin
    if GetByName('ActionListWindow').ContainsPoint(Point) then
    begin
      Panel1 := GetByName('ActionListWindow') as TPanelScrollBarGI;
      Panel1.SetScrollOffset(
          Classes.Point(0, Panel1.ScrollOffset.Y - Panel1.VerticalScrollBar.SmallChange)
      );
      Panel1.PanelScrollChanged(nil);
    end
    else
    begin
      Panel2 := GetByName('MessageWindow') as TPanelScrollBarGI;
      Panel2.SetScrollOffset(
          Classes.Point(0, Panel2.ScrollOffset.Y - Panel2.VerticalScrollBar.SmallChange)
      );
      Panel2.PanelScrollChanged(nil);
    end;
  end
  else if Delta = -WHEEL_DELTA then
  begin
    if GetByName('ActionListWindow').ContainsPoint(Point) then
    begin
      Panel3 := GetByName('ActionListWindow') as TPanelScrollBarGI;
      Panel3.SetScrollOffset(
          Classes.Point(0, Panel3.ScrollOffset.Y + Panel3.VerticalScrollBar.SmallChange)
      );
      Panel3.PanelScrollChanged(nil);
    end
    else
    begin
      Panel4 := GetByName('MessageWindow') as TPanelScrollBarGI;
      Panel4.SetScrollOffset(
          Classes.Point(0, Panel4.ScrollOffset.Y + Panel4.VerticalScrollBar.SmallChange)
      );
      Panel4.PanelScrollChanged(nil);
    end;
  end;
end;

procedure TfPlanetQuest.FinishChoiceLayout;
var
  Panel: TPanelScrollBarGI;
  Control: TObjectGI;
  LineCount, Page, ExtraOffset: Integer;
  Spacer: TPanelGI;
begin
  Inc(NextChoiceTop, 10);
  Panel := GetByName('ActionListWindow') as TPanelScrollBarGI;
  Spacer := TPanelGI.Create(Panel);
  Spacer.SetPosition(Classes.Point(0, NextChoiceTop - 10));
  Spacer.SetSize(Classes.Point(10, 10));
  Spacer.SetPositionModeW(True);
  Panel.SetActive(True);
  Panel.SetVerticalScrollbarEnabled(NextChoiceTop > Panel.ClientSize.Y);
  Panel.VerticalScrollBar.SetLargeChange(Panel.ClientSize.Y);
  Panel.VerticalScrollBar.SetPageSize(Panel.ClientSize.Y);
  Panel.SetScrollOffset(Classes.Point(0, 0));
  Panel.SetDragScrollingEnabled(Panel.IsVerticalScrollbarEnabled);
  Panel.UpdateScrollRanges;
  if QuestPageAnimationEnabled then
  begin
    GetByName('ActionListWindow').SetActive(False);
    Panel := GetByName('MessageWindow') as TPanelScrollBarGI;
    Panel.SetUnlimitedWorldEnabled(True);
    Panel.SetDragScrollingEnabled(False);
    Control := Panel.FirstChild;
    LineCount := 0;
    Page := 1;
    ExtraOffset := 0;
    while Control <> nil do
    begin
      Control.UserIndex := Control.LocalPosition.Y;
      if Control is TLabelGI then
        if Control.LocalPosition.Y < Panel.ClientSize.Y then
        begin
          Control.UserValue := Page;
          if Page > 1 then
            Control.SetPosition(
                Classes.Point(
                    Control.LocalPosition.X,
                    -Control.LocalPosition.Y - Control.ClientSize.Y - ExtraOffset
                )
            );
          Inc(LineCount, (Control as TLabelGI).GetRenderedLineCount);
          if LineCount > 5 then
          begin
            LineCount := 0;
            Inc(Page);
          end;
        end;
      Control := Control.NextSibling;
    end;
    if PageAnimationTimer <> nil then
    begin
      CancelCallbackTimer(PageAnimationTimer);
      PageAnimationTimer := nil;
    end;
    PageAnimationTimer := ScheduleCallbackTimer(20, 20, AnimateTextPage);
  end;
end;

procedure TfPlanetQuest.AnimateTextPage(Timer: PCallbackTimerGI; UserData: PtrInt);
var
  Panel: TPanelScrollBarGI;
  Control: TObjectGI;
  Moving: Boolean;
  Step: Integer;
begin
  Moving := False;
  Panel := GetByName('MessageWindow') as TPanelScrollBarGI;
  Control := Panel.FirstChild;
  while Control <> nil do
  begin
    if Control is TLabelGI then
      if Control.LocalPosition.Y < Control.UserIndex then
      begin
        Moving := True;
        Step := Round(Min(1.0, (Control.UserIndex - Control.LocalPosition.Y) / 100) * 30);
        if Step < 1 then
          Step := 1;
        Control.SetPosition(
            Classes.Point(
                Control.LocalPosition.X,
                Min(Control.UserIndex, Control.LocalPosition.Y + Step)
            )
        );
      end;
    Control := Control.NextSibling;
  end;
  if not Moving then
  begin
    Panel.SetUnlimitedWorldEnabled(False);
    Panel.SetDragScrollingEnabled(True);
    if PageAnimationTimer <> nil then
    begin
      CancelCallbackTimer(PageAnimationTimer);
      PageAnimationTimer := nil;
    end;
    GetByName('ActionListWindow').SetActive(True);
    PostMouseMoveMessage;
  end;
end;

procedure TfPlanetQuest.ClearParameterPanel;
var
  Panel: TPanelGI;
begin
  Panel := GetByName('ParamsShowWindow') as TPanelGI;
  Panel.FreeOwnedChildren;
  ParameterPanelWidth := 0;
  ParameterPanelHeight := 0;
end;

procedure TfPlanetQuest.AppendParameterText(Text: WideString);
var
  Panel: TPanelGI;
  FixedWidth: Boolean;
  Lines: TStringsEC;
  TextLabel: TLabelGI;
begin
  Panel := GetByName('ParamsShowWindow') as TPanelGI;
  FixedWidth := FindTextOffsetW(LowerCaseWideString(Text), '<fix>') >= 0;
  Text := RemoveMatchingTextTagsW(Text, 'fix', 'FIX');
  Text := RemoveMatchingTextTagsW(Text, '/fix', '/FIX');
  Text := ReplaceAllWideString(Text, GetTextColorTag(QuestStyleIndex), '<color=255,240,100>');
  Lines := TStringsEC.Create;
  Lines.SetText(Text);
  Lines.First;
  while not Lines.IsAtEnd do
  begin
    TextLabel := TLabelGI.Create(Panel);
    if FixedWidth then
      TextLabel.SetFontName('Font.' + GiResourceSuffix + 'Fix')
    else
      TextLabel.SetFontName(NormalFontName);
    TextLabel.SetSize(Classes.Point(1, 1));
    TextLabel.SetTextAlignX(taxAuto);
    TextLabel.SetTextAlignY(tayAuto);
    TextLabel.SetWordWrapEnabled(False);
    TextLabel.SetText(Lines.GetCurrentText);
    TextLabel.SetTextColor(GetTextColor(0));
    TextLabel.SetPosition(Classes.Point(0, ParameterPanelHeight));
    TextLabel.SetTextAlignY(tayCenterEx);
    if TextLabel.ClientSize.Y < 10 then
      TextLabel.SetSize(Classes.Point(TextLabel.ClientSize.X, TextLabel.ClientSize.Y + 10));
    Inc(ParameterPanelHeight, TextLabel.ClientSize.Y);
    TextLabel.UserData := PtrInt(FixedWidth);
    if FixedWidth then
      Inc(ParameterPanelHeight, 2);
    ParameterPanelWidth := Max(ParameterPanelWidth, TextLabel.ClientSize.X);
    Lines.Next;
  end;
  Lines.Free;
end;

procedure TfPlanetQuest.LayoutParameterPanel;
var
  Window: TWindowGI;
  Panel: TPanelGI;
  Control: TObjectGI;
  Y: Integer;
begin
  Window := GetByName('ParamsShowWindowParent') as TWindowGI;
  Panel := GetByName('ParamsShowWindow') as TPanelGI;
  Window.SetPosition(ParameterPanelOrigin);
  Window.SetSize(
      Classes.Point(
          ParameterPanelWidth + Window.WorkSubRect.Left + Window.WorkSubRect.Right,
          ParameterPanelHeight + Window.WorkSubRect.Top + Window.WorkSubRect.Bottom
      )
  );
  Window.UpdateAutoGeometry;
  Panel.SetSize(Window.ClientSize);
  Y := 0;
  Control := Panel.FirstChild;
  while Control <> nil do
  begin
    Control.SetPosition(
        Classes.Point(
            Window.WorkSubRect.Left,
            (Window.ClientSize.Y
                        - Window.WorkSubRect.Top
                        - Window.WorkSubRect.Bottom
                        - ParameterPanelHeight)
                    div 2
                + (Window.WorkSubRect.Top + Y)
        )
    );
    Inc(Y, Control.ClientSize.Y);
    if Control.UserData <> 0 then
      Inc(Y, 2);
    Control := Control.NextSibling;
  end;
  if GameScreenHeight - GiScalePixels(30) < Window.LocalPosition.Y + Window.ClientSize.Y then
    Window.SetPosition(
        Classes.Point(
            Window.LocalPosition.X,
            GameScreenHeight - GiScalePixels(30) - Window.ClientSize.Y
        )
    );
  if GameScreenWidth - GiScalePixels(10) < Window.LocalPosition.X + Window.ClientSize.X then
    Window.SetPosition(
        Classes.Point(
            GameScreenWidth - GiScalePixels(10) - Window.ClientSize.X,
            Window.LocalPosition.Y
        )
    );
end;

// CHANGE: ENHANCEMENT - The text's cut into paragraphs (the <fix> parts, the lines, the indent)
// is QuestWatch.QuestTextParagraphs, which the watch window shares (docs/progress/
// 2026-10-19-text-quests-plan.md, Phase E); was the nested AddQuestTextLines (native 0x5DF03C)
// and the parsing of AddQuestTextParagraph (0x5DED88). The labels are laid out as before.
procedure TfPlanetQuest.SetQuestText(const Text: WideString);
var
  Panel: TPanelScrollBarGI;
  NextTop: Integer;
  Paragraphs: TQuestTextParagraphs;
  I: Integer;
  TextLabel: TLabelGI;
begin
  Panel := GetByName('MessageWindow') as TPanelScrollBarGI;
  Panel.FreeOwnedChildren;
  if Text <> '' then
  begin
    NextTop := 0;
    Paragraphs := QuestTextParagraphs(Text);
    for I := 0 to High(Paragraphs) do
    begin
      TextLabel := TLabelGI.Create(Panel);
      if not Paragraphs[I].Fixed then
      begin
        if FontQuest = 0 then
          TextLabel.SetFontName(NormalFontName)
        else if FontQuest = 1 then
          TextLabel.SetFontName(SmoothBigFontName)
        else if FontQuest = 2 then
          TextLabel.SetFontName(SmoothHugeFontName)
        else if FontQuest >= 3 then
          TextLabel.SetFontName(SmoothIntroFontName);
      end
      else
        TextLabel.SetFontName('Font.' + GiResourceSuffix + 'Fix');
      TextLabel.SetPosition(Point(0, NextTop));
      TextLabel.SetSize(Point(Panel.ClientSize.X, 1));
      TextLabel.SetWordWrapEnabled(True);
      TextLabel.SetTextAlignX(taxAuto);
      TextLabel.SetTextAlignY(tayAuto);
      TextLabel.SetText(Paragraphs[I].Text);
      TextLabel.SetPositionModeW(True);
      TextLabel.SetTextColor(GetTextColor(QuestStyleIndex));
      TextLabel.SetTextAlignY(tayTop);
      { Preserve native getter order: rendered line count, then line height. }
      TextLabel.SetSize(
          Point(
              TextLabel.ClientSize.X,
              Max(1, TextLabel.GetRenderedLineCount) * TextLabel.GetLineHeight + 4
          )
      );
      NextTop := TextLabel.LocalPosition.Y + TextLabel.ClientSize.Y - 2;
    end;
    Panel.SetScrollOffset(Point(0, 0));
    Panel.SetVerticalScrollbarEnabled(Panel.ClientSize.Y < NextTop);
    if Panel.FirstChild <> nil then
      Panel.VerticalScrollbar.SetSmallChange((Panel.FirstChild as TLabelGI).GetLineHeight);
    Panel.VerticalScrollbar.SetLargeChange(Panel.ClientSize.Y);
    Panel.VerticalScrollbar.SetPageSize(Panel.ClientSize.Y);
    Panel.UpdateScrollRanges;
    Panel.Invalidate;
  end;
end;

procedure TfPlanetQuest.InitializeLayout;
var
  I, Shift: Integer;
  Control: TObjectGI;
begin
  inherited InitializeLayout;
  AppendLogTextThreadSafe('fPlanetQuest... ');
  ViewportRect := Rect(0, 0, GameScreenWidth, GameScreenHeight);
  with GetByName('MainPanel') do
  begin
    SetSize(Point(GameScreenWidth, GameScreenHeight));
    with FindByNameRecursive('ImageFrame') do
      SetPosition(Point(LocalPosition.X + ExtraScreenWidth, LocalPosition.Y));
    with FindByNameRecursive('PQI') do
      SetPosition(Point(LocalPosition.X + ExtraScreenWidth, LocalPosition.Y));
    with FindByNameRecursive('AnimTextOn') do
      SetPosition(Point(LocalPosition.X + ExtraScreenWidth, LocalPosition.Y + ExtraScreenHeight));
    with FindByNameRecursive('AnimTextOff') do
      SetPosition(Point(LocalPosition.X + ExtraScreenWidth, LocalPosition.Y + ExtraScreenHeight));
    for I := 1 to 4 do
      with FindByNameRecursive('Style' + IntToStr(I)) do
        SetPosition(Point(LocalPosition.X + ExtraScreenWidth, LocalPosition.Y + ExtraScreenHeight));
    with FindByNameRecursive('ButtonExit') do
      SetPosition(Point(LocalPosition.X + ExtraScreenWidth, LocalPosition.Y + ExtraScreenHeight));
    I := 0;
    Shift := 39;
    if ExtraScreenWidth < Shift then
      I := Shift - ExtraScreenWidth;
    Shift := Shift - I;
    with FindByNameRecursive('BGStyle') do
    begin
      SetPosition(Point(LocalPosition.X + Shift, LocalPosition.Y));
      SetSize(Point(ClientSize.X + (ExtraScreenWidth - Shift), ClientSize.Y + ExtraScreenHeight));
    end;
    with FindByNameRecursive('BGImage') do
      SetPosition(Point(GameScreenWidth - ClientSize.X, LocalPosition.Y));
    with FindByNameRecursive('PanelImage') do
      if (ExtraScreenWidth > 0) or (ExtraScreenHeight > 0) then
      begin
        SetPosition(Point(0, LocalPosition.Y));
        SetSize(Point(GameScreenWidth, GameScreenHeight));
      end
      else
        SetSize(Point(ClientSize.X, GameScreenHeight));
    with FindByNameRecursive('QuestPanel') do
    begin
      SetSize(Point(GameScreenWidth, GameScreenHeight));
      with FindByNameRecursive('MessageWindow') as TPanelScrollBarGI do
      begin
        SetPosition(Point(LocalPosition.X + Shift, LocalPosition.Y));
        SetSize(
            Point(ClientSize.X + (ExtraScreenWidth - Shift), ClientSize.Y + ExtraScreenHeight div 2)
        );
        TObjectGI(VerticalScrollbar)
            .SetPosition(
                Point(
                    VerticalScrollbar.LocalPosition.X + ExtraScreenWidth,
                    VerticalScrollbar.LocalPosition.Y
                ));
        VerticalScrollbar.SetSize(
            Point(
                VerticalScrollbar.ClientSize.X,
                VerticalScrollbar.ClientSize.Y + ExtraScreenHeight div 2
            )
        );
      end;
      with FindByNameRecursive('ActionListWindow') as TPanelScrollBarGI do
      begin
        SetPosition(Point(LocalPosition.X + Shift, LocalPosition.Y + ExtraScreenHeight div 2));
        SetSize(
            Point(ClientSize.X + (ExtraScreenWidth - Shift), ClientSize.Y + ExtraScreenHeight div 2)
        );
        TObjectGI(VerticalScrollbar)
            .SetPosition(
                Point(
                    VerticalScrollbar.LocalPosition.X + ExtraScreenWidth,
                    VerticalScrollbar.LocalPosition.Y
                ));
        VerticalScrollbar.SetSize(
            Point(
                VerticalScrollbar.ClientSize.X,
                VerticalScrollbar.ClientSize.Y + ExtraScreenHeight div 2
            )
        );
      end;
    end;
    with FindByNameRecursive('LabelHelp') do
      SetPosition(Point(LocalPosition.X + ExtraScreenWidth, LocalPosition.Y + ExtraScreenHeight));
    with FindByNameRecursive('ParamsShowWindowParent') do
      SetPosition(Point(LocalPosition.X + ExtraScreenWidth, LocalPosition.Y));
  end;
  AppendLogLineThreadSafe('ok');
  ParameterPanelOrigin := GetByName('ParamsShowWindowParent').LocalPosition;
  SetHelpCallback(ShowControlHelp);
  with GetByName('AnimTextOn') as TGraphButtonGI do
  begin
    UserValue := 0;
    UpCallback := SelectPageMode;
  end;
  with GetByName('AnimTextOff') as TGraphButtonGI do
  begin
    UserValue := 1;
    UpCallback := SelectPageMode;
  end;
  I := 1;
  while True do
  begin
    Control := FindControlByPath('Style' + IntToWideString(I));
    if Control = nil then
      Break;
    with Control as TGraphButtonGI do
    begin
      UserValue := I - 1;
      UpCallback := SelectStyle;
      DownCallback := SelectStyle;
    end;
    Inc(I);
  end;
  QuestStyleCount := I - 1;
  GetByName('MainPanel').KeyDownCallback := QuestKeyDown;
  (GetByName('ButtonExit') as TGraphButtonGI).UpCallback := RequestLoadGame;
  if QuestView = nil then
    QuestView := TPlanetQuestView.Create(Self);
end;

procedure TfPlanetQuest.OnOpen;
var
  Stage: Integer;
begin
  Stage := 0;
  try
    SelectMusic;
    FreeAndNil(Run);
    Run := TQuestRun.Create(QuestView);
    if Galaxy <> nil then
      EvictMainMenuShipCachesWhenAddressSpaceHigh;
    Stage := 1;
    if LocalPlayer <> nil then
      RunScriptItemsAct(LocalPlayer, satOnEnteringForm, nil, nil, 0);
    Stage := 2;
    if (QuestStyleIndex < 0) or (QuestStyleIndex >= QuestStyleCount) then
      QuestStyleIndex := 0;
    GetByName('PQI').SetActive(False);
    CurrentPicture := '';
    (GetByName('QuestPanel') as TPanelGI).SetActive(True);
    Stage := 3;
    ClearChoices;
    SetQuestText('');
    ClearParameterPanel;
    LayoutParameterPanel;
    Stage := 4;
    // The run picks the quest and starts it (stages 4 to 22).
    if not Run.Open then
    begin
      RequestedScreenId := QuestReturnScreenId;
      RequestClose(1);
    end;
    Stage := 23;
    ApplyStyle;
    Stage := 24;
    TGraphButtonGI(GetByName('Style' + IntToWideString(QuestStyleIndex + 1))).ExecuteOnPressCode;
    Stage := 25;
    if Galaxy <> nil then
      aCalc.WaitForTurnCalculationUI;
  except
    on E: Exception do
    begin
      if (Stage = 4) and (Run <> nil) then
        Stage := Run.Stage;
      AppendLogLineThreadSafe(E.ClassName + ' ' + E.Message);
      raise Exception.Create(
          'Error in procedure TfPlanetQuest.BeforeRun, label = ' + IntToStr(Stage));
    end;
  end;
end;

procedure TfPlanetQuest.OnClose;
begin
  if Galaxy <> nil then
    aCalc.WaitForTurnCalculationUI;
  if LocalPlayer <> nil then
    RunScriptItemsAct(LocalPlayer, satOnLeavingForm, nil, nil, 0);
  if PageAnimationTimer <> nil then
  begin
    CancelCallbackTimer(PageAnimationTimer);
    PageAnimationTimer := nil;
  end;
  ClearParameterPanel;
  ClearChoices;
  // The money cap and the quest timers (TQuestRun.Close).
  if Run <> nil then
  begin
    Run.Close;
    FreeAndNil(Run);
  end;
  if (RequestedScreenId = screenMainMenu) or (RequestedScreenId = screenLoad) then
    ClearPendingScriptRequests;
end;

function TfPlanetQuest.PlaysGameQuest: Boolean;
begin
  Result := (Galaxy <> nil) and (LocalPlayer <> nil) and not StandaloneQuestMode;
end;

procedure TfPlanetQuest.AbandonQuest;
begin
  if Run <> nil then
    Run.Abandon;
end;

function TfPlanetQuest.GetTextColorTag(StyleIndex: Integer): WideString;
begin
  Result := QuestTextColorTag(StyleIndex);
end;

function TfPlanetQuest.GetTextColor(StyleIndex: Integer): Cardinal;
var
  Block: TBlockParEC;
  S: WideString;
begin
  Block := UiStyleConfig.GetBlockByPath('Style');
  if Block.CountBlocks('QTextColor') > 0 then
  begin
    Block := Block.GetBlock('QTextColor');
    if Block.CountParams('Text' + IntToWideString(StyleIndex + 1)) > 0 then
    begin
      S := Block.GetParam('Text' + IntToWideString(StyleIndex + 1));
      Result :=
          CurrentPixelFormat.PackRgb(
              ExtractDigitsToIntW(ExtractDelimitedPartW(S, 0, ',')),
              ExtractDigitsToIntW(ExtractDelimitedPartW(S, 1, ',')),
              ExtractDigitsToIntW(ExtractDelimitedPartW(S, 2, ','))
          );
      Exit;
    end;
  end;
  if StyleIndex = 0 then
    Result := CurrentPixelFormat.PackRgbBytes(212, 208, 180)
  else if StyleIndex = 1 then
    Result := CurrentPixelFormat.PackRgbBytes(212, 208, 180)
  else if StyleIndex = 2 then
    Result := CurrentPixelFormat.PackRgbBytes(0, 0, 0)
  else if StyleIndex = 3 then
    Result := CurrentPixelFormat.PackRgbBytes(0, 0, 0)
  else
    Result := GetTextColor(0);
end;

function TfPlanetQuest.GetDisabledTextColor(StyleIndex: Integer): Cardinal;
var
  Block: TBlockParEC;
  S: WideString;
begin
  Block := UiStyleConfig.GetBlockByPath('Style');
  if Block.CountBlocks('QTextColor') > 0 then
  begin
    Block := Block.GetBlock('QTextColor');
    if Block.CountParams('Grey' + IntToWideString(StyleIndex + 1)) > 0 then
    begin
      S := Block.GetParam('Grey' + IntToWideString(StyleIndex + 1));
      Result :=
          CurrentPixelFormat.PackRgb(
              ExtractDigitsToIntW(ExtractDelimitedPartW(S, 0, ',')),
              ExtractDigitsToIntW(ExtractDelimitedPartW(S, 1, ',')),
              ExtractDigitsToIntW(ExtractDelimitedPartW(S, 2, ','))
          );
      Exit;
    end;
  end;
  if StyleIndex = 0 then
    Result := CurrentPixelFormat.PackRgbBytes(120, 120, 120)
  else if StyleIndex = 1 then
    Result := CurrentPixelFormat.PackRgbBytes(120, 120, 120)
  else if StyleIndex = 2 then
    Result := CurrentPixelFormat.PackRgbBytes(120, 120, 120)
  else if StyleIndex = 3 then
    Result := CurrentPixelFormat.PackRgbBytes(120, 120, 120)
  else
    Result := GetDisabledTextColor(0);
end;

procedure TfPlanetQuest.ApplyStyle;
var
  I: Integer;
  Control: TObjectGI;
  Path: WideString;
begin
  (GetByName('AnimTextOn') as TGraphButtonGI).SetActive(QuestPageAnimationEnabled);
  (GetByName('AnimTextOff') as TGraphButtonGI).SetActive(not QuestPageAnimationEnabled);
  for I := 1 to QuestStyleCount do
    (GetByName('Style' + IntToStr(I)) as TGraphButtonGI).SetDisabled(QuestStyleIndex = I - 1);
  (GetByName('BGStyle') as TImageGI)
      .SetImagePath(
          'GI,Bm.FormPQuest2.' + GiResourceSuffix + 'S' + IntToWideString(QuestStyleIndex + 1));
  (GetByName('MessageWindow') as TPanelScrollBarGI)
      .VerticalScrollbar
      .SetConfigPath(
          'Style.ScrollBar.' + GiResourceSuffix + 'PQS' + IntToWideString(QuestStyleIndex + 1));
  (GetByName('ActionListWindow') as TPanelScrollBarGI)
      .VerticalScrollbar
      .SetConfigPath(
          'Style.ScrollBar.' + GiResourceSuffix + 'PQS' + IntToWideString(QuestStyleIndex + 1));
  Control := GetByName('MessageWindow').FirstChild;
  while Control <> nil do
  begin
    if Control is TLabelGI then
      with Control as TLabelGI do
      begin
        SetTextColor(GetTextColor(QuestStyleIndex));
        SetText(
            ReplaceAllWideString(
                GetText,
                GetTextColorTag(PreviousStyleIndex),
                GetTextColorTag(QuestStyleIndex)
            )
        );
      end;
    Control := Control.NextSibling;
  end;
  Control := GetByName('ActionListWindow').FirstChild;
  while Control <> nil do
  begin
    if Control.FirstChild <> nil then
    begin
      with Control.FirstChild as TImageGI do
      begin
        Path :=
            'Bm.FormPQuest2.'
                + GiResourceSuffix
                + 'S'
                + IntToWideString(QuestStyleIndex + 1)
                + 'Line';
        if CacheDataRoot.FileExistsByPath(Path) then
          SetImagePath('GI,' + Path)
        else
          SetImagePath('GI,Bm.FormPQuest2.' + GiResourceSuffix + 'S1Line');
        SetImageKindX(ikxLeftFill);
        SetImageKindY(ikyTopFill);
      end;
      with Control.FirstChild.NextSibling as TLabelGI do
      begin
        if UserState = 1 then
          SetTextColor(GetDisabledTextColor(QuestStyleIndex))
        else
          SetTextColor(GetTextColor(QuestStyleIndex));
        SetText(
            ReplaceAllWideString(
                GetText,
                GetTextColorTag(PreviousStyleIndex),
                GetTextColorTag(QuestStyleIndex)
            )
        );
      end;
      if Control.FirstChild.NextSibling.FirstChild <> nil then
        with Control.FirstChild.NextSibling.FirstChild.FirstChild as TImageGI do
        begin
          Path :=
              'Bm.FormPQuest2.'
                  + GiResourceSuffix
                  + 'S'
                  + IntToWideString(QuestStyleIndex + 1)
                  + 'Answer';
          if Control.FirstChild.NextSibling.UserState = 1 then
          begin
            if CacheDataRoot.FileExistsByPath(Path + 'H') then
              SetImagePath('GI,' + Path + 'H')
            else
              SetImagePath('GI,Bm.FormPQuest2.' + GiResourceSuffix + 'S1AnswerH');
          end
          else if CacheDataRoot.FileExistsByPath(Path) then
            SetImagePath('GI,' + Path)
          else
            SetImagePath('GI,Bm.FormPQuest2.' + GiResourceSuffix + 'S1Answer');
        end;
    end;
    Control := Control.NextSibling;
  end;
end;

procedure TfPlanetQuest.SelectPageMode(Sender: TObjectGI);
var
  Filename: WideString;
begin
  if Boolean(Sender.UserValue) <> QuestPageAnimationEnabled then
  begin
    QuestPageAnimationEnabled := Boolean(Sender.UserValue);
    UserSettingsConfig.SetOrAddParam('PQuestAnim', BoolToWideString(QuestPageAnimationEnabled));
    Filename := GetGameUserDirectory + 'cfg.txt';
    UserSettingsConfig.SaveTextFile(PWideChar(Filename), True, False);
    if QuestPageAnimationEnabled then
      ShowControlHelp(GetByName('AnimTextOn'), True)
    else
      ShowControlHelp(GetByName('AnimTextOff'), True);
    ApplyStyle;
  end;
end;

procedure TfPlanetQuest.SelectStyle(Sender: TObjectGI);
begin
  if QuestStyleIndex <> Sender.UserValue then
  begin
    PreviousStyleIndex := QuestStyleIndex;
    QuestStyleIndex := Sender.UserValue;
    UserSettingsConfig.SetOrAddParam('PQuestStyle', IntToStr(QuestStyleIndex));
    UserSettingsConfig.SaveTextFile(PWideChar(GetGameUserDirectory + 'cfg.txt'), True, False);
    ApplyStyle;
  end;
end;

procedure TfPlanetQuest.ShowControlHelp(Sender: TObjectGI; Visible: Boolean);
var
  TextLabel: TLabelGI;
begin
  TextLabel := GetByName('LabelHelp') as TLabelGI;
  if Sender.HelpText = '' then
    Visible := False;
  TextLabel.SetActive(Visible);
  if (Sender.ControlName = 'ButtonExit') and (Run <> nil) and (Run.QueuedQuest <> nil) then
    TextLabel.SetText(LocalizedText('FormPQuest.HelpExitAlt'))
  else
    TextLabel.SetText(Sender.HelpText);
end;

procedure TfPlanetQuest.SetQuestPicture(Name: WideString);
var
  Image: TGraphBufGI;
begin
  if CurrentPicture <> Name then
  begin
    CurrentPicture := Name;
    Image := GetByName('PQI') as TGraphBufGI;
    Image.SetActive(True);
    Image.LoadBitmapPathAsRgb('Bm.PQI.' + Name + '?RGB');
    if GiResourceVariant = 1 then
      Image.GraphBuf.RescaleRgb(
          Round(Cardinal(Image.GraphBuf.Width) * 800 / 1024),
          Round(Cardinal(Image.GraphBuf.Height) * 800 / 1024)
      );
    Image.GraphBuf.ConvertRgbTo565;
    Image.Invalidate;
  end;
end;

procedure TfPlanetQuest.RequestLoadGame(Sender: TObjectGI);
var
  Standalone: Boolean;
begin
  if IsMultiplayer then
    Exit;
  if ShowMessageBoxGI(
          Self,
          LanguageDataConfig.GetParamByPathOrMarker('FormGameMenu.QExit'),
          mbgOK or mbgCancel)
      = mbgResultOK then
  begin
    Standalone := Galaxy = nil;
    ClearPendingScriptRequests;
    if MemorySnapshotBuffer <> nil then
      MemorySnapshotBuffer.Free;
    MemorySnapshotBuffer := nil;
    MemorySnapshotActive := False;
    if Galaxy <> nil then
      if not Galaxy.Destroying then
        Galaxy.Free;
    Galaxy := nil;
    ScreenLoadMode := 4;
    if Standalone then
      PostLoadScreenId := QuestReturnScreenId
    else
      PostLoadScreenId := screenMainMenu;
    RequestedScreenId := screenLoad;
    RequestClose(1);
  end;
end;

procedure TfPlanetQuest.QuestKeyDown(Sender: TObjectGI; VirtualKey: Cardinal);
var
  Index: Integer;
  Panel: TPanelScrollBarGI;
  Choice, Control: TObjectGI;
begin
  if not IsVirtualKeyDown(VK_CONTROL)
      and not IsVirtualKeyDown(VK_SHIFT)
      and not IsVirtualKeyDown(VK_MENU) then
  begin
    if VirtualKey = VK_ESCAPE then
      RequestLoadGame(nil);
    if (VirtualKey >= Ord('1')) and (VirtualKey <= Ord('9')) then
    begin
      Index := VirtualKey - Ord('1');
      Panel := GetByName('ActionListWindow') as TPanelScrollBarGI;
      Control := Panel.FirstChild;
      while (Control <> nil)
          and (not (Control is TPanelGI)
              or ((@Control.LeftButtonUpCallback <> @TfPlanetQuest.ChoiceMouseUp)
                  and (@Control.LeftButtonUpCallback <> @TfPlanetQuest.DisabledChoiceMouseUp))) do
        Control := Control.NextSibling;
      Choice := Control;
      while (Choice <> nil) and (Index >= 0) do
      begin
        if Index = 0 then
        begin
          Choice.LeftButtonUpCallback(Choice, 0, Point(0, 0));
          Exit;
        end
        else
        begin
          Dec(Index);
          Control := Choice.NextSibling;
          while (Control <> nil)
              and (not (Control is TPanelGI)
                  or ((@Control.LeftButtonUpCallback <> @TfPlanetQuest.ChoiceMouseUp)
                      and (@Control.LeftButtonUpCallback
                          <> @TfPlanetQuest.DisabledChoiceMouseUp))) do
            Control := Control.NextSibling;
          Choice := Control;
        end;
      end;
    end;
    if (VirtualKey = Ord('R')) and not IsMultiplayer then
      if (Run = nil) or (Run.QueuedQuest = nil) then
        if SaveManagerScreen.AutoSaveExists then
          if ShowMessageBoxGI(
                  Self,
                  LocalizedText('Planet.NotCivil.QuestPlay.MsgLoad'),
                  mbgOK or mbgCancel)
              = mbgResultOK then
            if LocalPlayer <> nil then
            begin
              PendingLoadFileName := SaveManagerScreen.GetAutoSavePath;
              RequestedScreenId := screenGameLoad;
              RequestClose(1);
            end
            else
            begin
              StandaloneQuestMode := True;
              RequestedScreenId := screenPlanetQuest;
              CurrentScreenId := screenNone;
              RequestClose(1);
            end;
  end;
end;

procedure TfPlanetQuest.SelectMusic;
begin
  if not MusicInPlanetEnabled then
    MusicManager.RequestFadeOut
  else
    MusicManager.PlayCategory('Quest');
end;

// Moved from TfPlanetQuest.CompleteQuestDeath: the box before the run's DieInQuest.
function TfPlanetQuest.ConfirmQuestDeath: Boolean;
begin
  // The death is a ship loss in multiplayer, which RecordHumanDeath records.
  if IsMultiplayer then
    Exit(True);
  if SaveManagerScreen.AutoSaveExists
      and (ShowMessageBoxGI(
              Self,
              LocalizedText('Planet.NotCivil.QuestPlay.MsgLoad'),
              mbgOK or mbgCancel)
          = mbgResultOK) then
  begin
    PendingLoadFileName := SaveManagerScreen.GetAutoSavePath;
    RequestedScreenId := screenGameLoad;
    Result := False;
  end
  else
  begin
    ScoreScreen.RecordPlayerResult(False);
    Result := True;
  end;
end;

// Moved from TfPlanetQuest.CompleteQuestSuccess, CompleteQuestFailure and CompleteQuestDeath:
// what follows the run's commands for the outcome.
procedure TfPlanetQuest.EndQuest(Outcome: TQuestRunOutcome);
begin
  case Outcome of
    qroSuccess:
      begin
        if Run.GovernmentQuestDone then
          (GetByName('QuestPanel') as TPanelGI).SetActive(False);
        if Run.QuestId >= 0 then
          if (Run.QueuedQuest = nil)
              or (LocalPlayer = nil)
              or not (LocalPlayer.PirateRank in [4, 6]) then
          begin
            if LocalPlayer <> nil then
              TryAddAchievementProgress('QUEST', 1);
            LoadQuestScreen.LoadCompletionData;
            LoadQuestScreen.RecordCompletion(Run.QuestId, 0, 1);
            LoadQuestScreen.SaveCompletionData;
          end;
        RequestedScreenId := QuestReturnScreenId;
        RequestClose(1);
      end;
    qroFailure:
      begin
        if LocalPlayer = nil then
          RequestedScreenId := QuestReturnScreenId
        else if Run.ReleasedFromPrison then
        begin
          if not HangarScreen.TryTakeOff then
            RequestedScreenId := screenHangar;
        end
        else if (Run.QueuedQuest = nil)
            and not IsMultiplayer
            and SaveManagerScreen.AutoSaveExists
            and (ShowMessageBoxGI(
                    Self,
                    LocalizedText('Planet.NotCivil.QuestPlay.MsgLoad'),
                    mbgOK or mbgCancel)
                = mbgResultOK) then
        begin
          PendingLoadFileName := SaveManagerScreen.GetAutoSavePath;
          RequestedScreenId := screenGameLoad;
        end
        else
          RequestedScreenId := QuestReturnScreenId;
        RequestClose(1);
      end;
    qroDeath:
      begin
        // The ranger respawned at a planet (TShip.RespawnHuman): the game goes on there, and
        // the other humans' script requests stay.
        if Run.Respawned then
        begin
          RequestedScreenId := screenPlanet;
          RequestClose(1);
          Exit;
        end;
        // A death declined for the autosave has asked for it already (ConfirmQuestDeath).
        if Run.Died then
          RequestedScreenId := screenGameEnd
        else if LocalPlayer = nil then
          RequestedScreenId := QuestReturnScreenId;
        ClearPendingScriptRequests;
        RequestClose(1);
      end;
  end;
end;

constructor TPlanetQuestView.Create(AScreen: TfPlanetQuest);
begin
  inherited Create;
  Screen := AScreen;
end;

procedure TPlanetQuestView.ShowText(const Text: WideString);
begin
  Screen.SetQuestText(Text);
end;

procedure TPlanetQuestView.ShowPicture(const Name: WideString);
begin
  Screen.SetQuestPicture(Name);
end;

procedure TPlanetQuestView.PlayMusic(const Name: WideString);
begin
  MusicManager.RequestFadeOut;
  if MusicInPlanetEnabled then
    MusicManager.PlayCategory(Name);
end;

procedure TPlanetQuestView.PlaySound(const Name: WideString);
begin
  SoundManager.PlaySound('Sound.' + Name);
end;

procedure TPlanetQuestView.ShowParameters(const Text: WideString);
begin
  Screen.ClearParameterPanel;
  Screen.AppendParameterText(Text);
  Screen.LayoutParameterPanel;
end;

procedure TPlanetQuestView.ClearChoices;
begin
  Screen.ClearChoices;
end;

procedure TPlanetQuestView.AddChoice(Index: Integer; const Choice: TQuestChoice);
begin
  if Choice.Enabled then
    Screen.AddChoice(Index, Choice.Text)
  else
    Screen.AddDisabledChoice(Index, Choice.Text);
end;

procedure TPlanetQuestView.FinishPage;
begin
  Screen.FinishChoiceLayout;
end;

function TPlanetQuestView.ConfirmDeath: Boolean;
begin
  Result := Screen.ConfirmQuestDeath;
end;

procedure TPlanetQuestView.EndQuest(Outcome: TQuestRunOutcome);
begin
  Screen.EndQuest(Outcome);
end;


procedure TfPlanetQuest.ExecuteUiCode(Block: TBlockParEC; Key: Cardinal);
begin
  if ExitScreenLoop then
    Exit;
  if Integer(TurnCalculationPhase) in [0, 2, 4, 6] then
  begin
    if Galaxy <> nil then
      aCalc.WaitForTurnCalculationUI;
    ExecuteGameplayUiCode(Block, Key);
    if Galaxy <> nil then
      aCalc.WaitForTurnCalculationUI;
  end;
end;

procedure LinkRecoveredTypes;
begin
  TGraphBufGI.ClassName;
  TGraphButtonGI.ClassName;
  TImageGI.ClassName;
  TLabelGI.ClassName;
  TPanelGI.ClassName;
  TPanelScrollBarGI.ClassName;
  TPlanet.ClassName;
  TWindowGI.ClassName;
end;
end.
