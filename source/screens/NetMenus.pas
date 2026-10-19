{$EXCESSPRECISION OFF}
unit NetMenus;
{$R-}
{$Q-}
{$B-}
{$A8}

// CHANGE: ENHANCEMENT - The menus of networked play (ROADMAP.md, Phase 5; docs/network.md,
// Hosting and joining). The main menu joins a game: a Network game entry beside Mods opens a
// dialog for the address and the name, and the join runs over the menu as --join's does
// (NetPlay.RunPendingJoin). The in-game menu hosts the running game: a button under the menu
// asks for the port and hosts as --host does (NetPlay.HostRunningGame), shows the host's state
// and stops hosting. The last address, name and port are kept in the user settings. The
// dialogs are built in code with the message box's window, fonts and buttons; they change no
// game state themselves.
// CHANGE: ENHANCEMENT - The in-game menu's "Watch text quest" button (and W) under the host's
// state, while another human of the session plays a text quest: the watch window
// (docs/progress/2026-10-19-text-quests-plan.md, Watching; NetPlay.WatchTextQuestFromMenu).
interface
uses
  GI_MessageLoop,
  Types;

// The main menu (InitializeLayout): the Network game entry, a copy of the Mods button and its
// label in the next place of that row.
procedure AddMainMenuJoin(Screen: TMessageLoopGI);
// The join dialog over the main menu, then the join over it; a join that succeeds closes the
// menu (the J key and the entry).
procedure ShowJoinDialog(Screen: TMessageLoopGI);
// The in-game menu (InitializeLayout): the host button and the state under the menu.
procedure AddGameMenuHost(Screen: TMessageLoopGI);
// The in-game menu opens and closes: the button follows the session.
procedure GameMenuHostOpened(Screen: TMessageLoopGI);
procedure GameMenuHostClosed(Screen: TMessageLoopGI);
// The host button's action (the N key and the button): hosts, or offers to stop hosting.
procedure GameMenuHostClicked(Screen: TMessageLoopGI);
// CHANGE: ENHANCEMENT - The watch button's action (the W key and the button): the watch window
// while another human plays a text quest; nothing otherwise.
procedure GameMenuWatchClicked(Screen: TMessageLoopGI);
// Whether Point (the menu's coordinates) is on the host or the watch button, which a click on
// the background must not take for a click beside the menu.
function GameMenuHostContains(Screen: TMessageLoopGI; Point: TPoint): Boolean;
implementation
uses
  Classes,
  SysUtils,
  Windows,
  EC_Str,
  GI_Edit,
  GI_GraphButton,
  GI_Label,
  GI_Main,
  GI_MessageBox,
  GI_Window,
  GR_Main,
  Globals,
  GlobalsV,
  NetPlay,
  NetSession;

const
  JoinButtonName = 'NetJoin';
  JoinLabelName = 'LNetJoin';
  HostButtonName = 'NetHost';
  HostLabelName = 'LNetHost';
  WatchButtonName = 'NetWatch';
  // How often the in-game menu shows the host's state again.
  HostRefreshMs = 1000;
  MaximumFields = 2;

type
  // What a dialog asks: its text and its fields.
  TNetEntryFields = record
    Text: WideString;
    Count: Integer;
    Captions: array[0..MaximumFields - 1] of WideString;
    Values: array[0..MaximumFields - 1] of WideString;
    MaxLengths: array[0..MaximumFields - 1] of Integer;
    DigitsOnly: array[0..MaximumFields - 1] of Boolean;
  end;

  // A message box with text fields: the text, a label and an edit per field, OK and Cancel.
  TNetEntryBoxGI = class(TMessageLoopGI)
    Fields: TNetEntryFields;
    Edits: array[0..MaximumFields - 1] of TEditGI;
    // A key went down in this dialog. The character of the key that opened it (J on the main
    // menu) arrives afterwards and is not typed.
    KeySeen: Boolean;
    procedure OnOpen; override;
    procedure ProcessCallbackTimers; override;
    procedure AcceptClick(Sender: TObjectGI);
    procedure CancelClick(Sender: TObjectGI);
    procedure DialogKeyDown(Sender: TObjectGI; Key: Cardinal);
    function AcceptCharacter(Sender: TObjectGI; Character: WideChar): Boolean;
  end;

  // The callbacks of the menus' controls.
  TNetMenuActions = class
    HostTimer: PCallbackTimerGI;
    procedure JoinClicked(Sender: TObjectGI);
    procedure HostClicked(Sender: TObjectGI);
    procedure WatchClicked(Sender: TObjectGI);
    procedure RefreshHost(Timer: PCallbackTimerGI; UserData: PtrInt);
  end;

var
  Actions: TNetMenuActions;

function CreateMessageBoxButton(Owner: TObjectGI; const Kind: WideString): TGraphButtonGI;
begin
  Result := TGraphButtonGI.Create(Owner);
  Result.EnterSound := 'Sound.ButtonEnter';
  Result.LeaveSound := 'Sound.ButtonLeave';
  Result.ClickSound := 'Sound.ButtonClick';
  Result.UpOnlyDown := True;
  Result.SetDepth(0);
  Result.SetImageNormalPath('GI,Bm.FormMessageBox.' + GiResourceSuffix + Kind + 'N');
  Result.SetImageNormalActivePath('GI,Bm.FormMessageBox.' + GiResourceSuffix + Kind + 'A');
  Result.SetImageDownPath('GI,Bm.FormMessageBox.' + GiResourceSuffix + Kind + 'D');
  Result.SetSize(Result.GetMaxStateImageSize);
  Result.HitKind := gbhRect;
end;

function CreateDialogLabel(Owner: TObjectGI; const Text: WideString; Width: Integer): TLabelGI;
begin
  Result := TLabelGI.Create(Owner);
  Result.SetDepth(0);
  Result.SetFontName(NormalFontName);
  Result.SetTextColor(CurrentPixelFormat.PackRgbBytes(0, 0, 0));
  Result.SetText(Text);
  Result.SetTextAlignX(taxLeft);
  Result.SetTextAlignY(tayAuto);
  Result.SetSize(Classes.Point(Width, 1));
  Result.SetWordWrapEnabled(True);
end;

procedure TNetEntryBoxGI.OnOpen;
const
  Width = 380;
  CaptionWidth = 90;
  FieldHeight = 22;
  FieldGap = 8;
var
  Window: TWindowGI;
  TextLabel: TLabelGI;
  FieldLabels: array[0..MaximumFields - 1] of TLabelGI;
  AcceptButton, CancelButton: TGraphButtonGI;
  Borders: TRect;
  Size: TPoint;
  InnerWidth, Y, I: Integer;
begin
  ContentPanel.KeyDownCallback := DialogKeyDown;
  Window := TWindowGI.Create(ContentPanel);
  Window.SetDepth(1);
  Window.SetConfigPath('Style.Window.' + GiResourceSuffix + 'MessageBox');
  Borders := Window.WorkSubRect;
  InnerWidth := GiScalePixels(Width) - Borders.Left - Borders.Right;
  TextLabel := CreateDialogLabel(
      ContentPanel,
      ReplaceAllWideString(Fields.Text, '<color=255,240,100>', '<color=0,50,200>'),
      InnerWidth
  );
  TextLabel.SetPosition(Classes.Point(Borders.Left, Borders.Top));
  Y := Borders.Top + TextLabel.ClientSize.Y + GiScalePixels(FieldGap * 2);
  for I := 0 to Fields.Count - 1 do
  begin
    FieldLabels[I] :=
        CreateDialogLabel(ContentPanel, Fields.Captions[I], GiScalePixels(CaptionWidth));
    FieldLabels[I].SetPosition(
        Classes.Point(
            Borders.Left,
            Y
                + I * GiScalePixels(FieldHeight + FieldGap)
                + (GiScalePixels(FieldHeight) - FieldLabels[I].ClientSize.Y) div 2
        )
    );
  end;
  // Created from the last to the first: Tab moves to the previous sibling edit, so it goes
  // down the fields.
  for I := Fields.Count - 1 downto 0 do
  begin
    Edits[I] := TEditGI.Create(ContentPanel);
    Edits[I].SetDepth(0);
    Edits[I].SetFontName(NormalFontName);
    Edits[I].SetTextColor(CurrentPixelFormat.PackRgbBytes(0, 0, 0));
    Edits[I].SetBorderLightColor(CurrentPixelFormat.PackRgbBytes(0, 50, 200));
    Edits[I].SetBorderDarkColor(CurrentPixelFormat.PackRgbBytes(0, 50, 200));
    Edits[I].SetBorderEnabled(True);
    Edits[I].AutoScrollText := True;
    Edits[I].ClearFocusOnEnter := False;
    Edits[I].MaxLength := Fields.MaxLengths[I];
    Edits[I].AcceptCharCallback := AcceptCharacter;
    Edits[I].SetText(Fields.Values[I]);
    Edits[I].SetPosition(
        Classes.Point(
            Borders.Left + GiScalePixels(CaptionWidth),
            Y + I * GiScalePixels(FieldHeight + FieldGap)
        )
    );
    Edits[I].SetSize(
        Classes.Point(InnerWidth - GiScalePixels(CaptionWidth), GiScalePixels(FieldHeight))
    );
  end;
  Inc(Y, Fields.Count * GiScalePixels(FieldHeight + FieldGap) + GiScalePixels(FieldGap));
  AcceptButton := CreateMessageBoxButton(ContentPanel, 'Ok');
  AcceptButton.UpCallback := AcceptClick;
  CancelButton := CreateMessageBoxButton(ContentPanel, 'Cancel');
  CancelButton.UpCallback := CancelClick;
  Window.SetPosition(Classes.Point(0, 0));
  Window.SetSize(
      Classes.Point(GiScalePixels(Width), Y + AcceptButton.ClientSize.Y + Borders.Bottom)
  );
  Window.UpdateAutoGeometry;
  Size := Window.ClientSize;
  AcceptButton.SetPosition(
      Classes.Point(
          Size.X div 2 - AcceptButton.ClientSize.X - GiScalePixels(5),
          Size.Y - Borders.Bottom - AcceptButton.ClientSize.Y
      )
  );
  CancelButton.SetPosition(
      Classes.Point(
          Size.X div 2 + GiScalePixels(5),
          Size.Y - Borders.Bottom - CancelButton.ClientSize.Y
      )
  );
  AcceptButton.UpdateStateImagePlacement;
  AcceptButton.UpdateStateVisuals;
  CancelButton.UpdateStateImagePlacement;
  CancelButton.UpdateStateVisuals;
  ViewportRect.Left := GameScreenWidth shr 1 - Size.X div 2;
  ViewportRect.Top := GameScreenHeight shr 1 - Size.Y div 2;
  ViewportRect.Right := ViewportRect.Left + Size.X;
  ViewportRect.Bottom := ViewportRect.Top + Size.Y;
  ContentPanel.SetPosition(ViewportRect.TopLeft);
  ContentPanel.SetSize(Size);
  ContentPanel.UpdateAbsolutePosition;
  ContentPanel.UpdateSubtreeHitBounds;
  if Fields.Count > 0 then
    SetFocusedControl(Edits[0]);
end;

function TNetEntryBoxGI.AcceptCharacter(Sender: TObjectGI; Character: WideChar): Boolean;
var
  I: Integer;
begin
  Result := KeySeen;
  for I := 0 to Fields.Count - 1 do
    if (Sender = Edits[I]) and Fields.DigitsOnly[I] then
      Result := Result and (Character >= '0') and (Character <= '9');
end;

procedure TNetEntryBoxGI.AcceptClick(Sender: TObjectGI);
var
  I: Integer;
begin
  for I := 0 to Fields.Count - 1 do
    Fields.Values[I] := TrimWideString(Edits[I].Text);
  if ExitCode = 0 then
    RequestClose(mbgResultOK)
  else
    RequestClose(ExitCode);
end;

procedure TNetEntryBoxGI.CancelClick(Sender: TObjectGI);
begin
  if ExitCode = 0 then
    RequestClose(mbgResultCancel)
  else
    RequestClose(ExitCode);
end;

// Only Enter and Escape: every other key is the fields' text.
procedure TNetEntryBoxGI.DialogKeyDown(Sender: TObjectGI; Key: Cardinal);
begin
  KeySeen := True;
  if Key = VK_ESCAPE then
    CancelClick(Sender)
  else if Key = VK_RETURN then
    AcceptClick(Sender);
end;

procedure TNetEntryBoxGI.ProcessCallbackTimers;
begin
  inherited ProcessCallbackTimers;
  if (ParentLoop.ExitCode <> 0) and (ExitCode = 0) then
    RequestClose(255);
end;

// Asks for Fields over Parent, modally, as ShowMessageBoxGI asks; true on OK, and then
// Fields.Values holds what was typed, trimmed.
function AskFields(Parent: TMessageLoopGI; var Fields: TNetEntryFields): Boolean;
var
  Dialog: TNetEntryBoxGI;
  CursorState: TCursorStateGI;
  Closed: Cardinal;
  I: Integer;
begin
  Parent.RootUiObject.NativeHook50;
  Parent.CaptureCursorState(@CursorState);
  Parent.SetCursorActive(False);
  Parent.DrawQueuedUpdateRects;
  Dialog := TNetEntryBoxGI.Create;
  Dialog.ParentLoop := Parent;
  Parent.ChildLoop := Dialog;
  Dialog.InitializeDefaults;
  try
    Dialog.Fields := Fields;
    Closed := Dialog.Run;
    if Closed = mbgResultOK then
      for I := 0 to Fields.Count - 1 do
        Fields.Values[I] := Dialog.Fields.Values[I];
    Parent.InvalidateViewport;
  finally
    Parent.ChildLoop := nil;
    Dialog.Free;
  end;
  Parent.RestoreCursorState(@CursorState);
  Parent.UpdateCursorPosition;
  Parent.RootUiObject.NativeHook48;
  if Closed = 254 then
    BreakUiMessage;
  Result := Closed = mbgResultOK;
end;

// User settings ---------------------------------------------------------------------------------

function UserSetting(const Name, Default: WideString): WideString;
begin
  Result := Default;
  if (UserSettingsConfig <> nil) and (UserSettingsConfig.CountParams(Name) > 0) then
    Result := TrimWideString(UserSettingsConfig.GetParam(Name));
end;

procedure SaveUserSetting(const Name, Value: WideString);
begin
  if UserSettingsConfig = nil then
    Exit;
  UserSettingsConfig.SetOrAddParam(Name, Value);
  UserSettingsConfig.SaveTextFile(PWideChar(GetGameUserDirectory + 'cfg.txt'), True, False);
end;

// The name a join proposes: the last one, else the new-game screen's ranger name.
function DefaultJoinName: WideString;
begin
  Result := UserSetting('NetJoinName', '');
  if (Result = '')
      and (NewGameSettingsConfig <> nil)
      and (NewGameSettingsConfig.CountParams('Name') > 0) then
    Result := TrimWideString(NewGameSettingsConfig.GetParam('Name'));
end;

// Joining (the main menu) -----------------------------------------------------------------------

procedure ShowJoinDialog(Screen: TMessageLoopGI);
var
  Fields: TNetEntryFields;
  Address: AnsiString;
  Port: Integer;
  Problem: WideString;
begin
  Fields := Default(TNetEntryFields);
  Fields.Text := MultiplayerText(
      'JoinText',
      'Join a network game. The address is the host''s computer, and its port when it is not '
          + WideString(IntToStr(DefaultNetPort))
          + ' (HOST:PORT). To play your ranger again, give the name you played with.'
  );
  Fields.Count := 2;
  Fields.Captions[0] := MultiplayerText('JoinAddress', 'Address:');
  Fields.Values[0] := UserSetting('NetJoinAddress', '');
  Fields.MaxLengths[0] := 80;
  Fields.Captions[1] := MultiplayerText('JoinName', 'Name:');
  Fields.Values[1] := DefaultJoinName;
  Fields.MaxLengths[1] := 32;
  repeat
    if not AskFields(Screen, Fields) or (Screen.ExitCode <> 0) then
      Exit;
    Problem := '';
    if not ParseNetAddress(UTF8Encode(Fields.Values[0]), Address, Port) then
      Problem :=
          MultiplayerText('BadAddress', 'Expected an address as HOST or HOST:PORT:')
              + ' '
              + Fields.Values[0]
    else if Fields.Values[1] = '' then
      Problem := MultiplayerText('NoName', 'Give the name to play with.');
    if Problem = '' then
      Break;
    ShowMessageBoxGI(Screen, Problem, mbgOK or mbgError);
  until False;
  SaveUserSetting('NetJoinAddress', Fields.Values[0]);
  SaveUserSetting('NetJoinName', Fields.Values[1]);
  RequestJoin(UTF8Encode(Fields.Values[0]), Fields.Values[1]);
  // CHANGE: ENHANCEMENT - The join runs over this menu with its progress and a Cancel; once the
  // state has come the menu closes and the human's screen opens.
  RunPendingJoin(Screen);
end;

procedure AddMainMenuJoin(Screen: TMessageLoopGI);
var
  Mods, Before, ModsLabel: TObjectGI;
  Button: TGraphButtonGI;
  Caption: TLabelGI;
  Step: TPoint;
begin
  Mods := Screen.FindControlByPath('Mods');
  Before := Screen.FindControlByPath('LoadAB');
  ModsLabel := Screen.FindControlByPath('LMods');
  if (Mods = nil) or (Before = nil) or (ModsLabel = nil) or (Mods.SourceBlock = nil) then
    Exit;
  if Actions = nil then
    Actions := TNetMenuActions.Create;
  // The next place of the row: as far from Mods as Mods is from the arcade battles.
  Step := Classes.Point(
      Mods.LocalPosition.X - Before.LocalPosition.X,
      Mods.LocalPosition.Y - Before.LocalPosition.Y
  );
  Button := TGraphButtonGI(Screen.FindControlByPath(JoinButtonName));
  if Button = nil then
  begin
    Button := TGraphButtonGI.Create(Mods.Parent);
    // The Mods button's look and sounds; the game has no picture for network play.
    Button.LoadFromBlock(Mods.SourceBlock);
    Button.SetName(JoinButtonName);
    Button.OnPressCode := nil;
    Button.OnKeyDownCode := nil;
    Button.HelpText := '';
    Button.UpdateAutoGeometry;
  end;
  Button.SetPosition(Classes.Point(Mods.LocalPosition.X + Step.X, Mods.LocalPosition.Y + Step.Y));
  Button.UpCallback := Actions.JoinClicked;
  Caption := TLabelGI(Screen.FindControlByPath(JoinLabelName));
  if (Caption = nil) and (ModsLabel.SourceBlock <> nil) then
  begin
    Caption := TLabelGI.Create(ModsLabel.Parent);
    Caption.LoadFromBlock(ModsLabel.SourceBlock);
    Caption.SetName(JoinLabelName);
    Caption.HelpText := '';
  end;
  if Caption <> nil then
  begin
    Caption.SetText(MultiplayerText('MenuJoin', 'Network game'));
    Caption.SetPosition(
        Classes.Point(ModsLabel.LocalPosition.X + Step.X, ModsLabel.LocalPosition.Y + Step.Y)
    );
  end;
  Screen.RootUiObject.UpdateAbsolutePosition;
  Screen.RootUiObject.UpdateSubtreeHitBounds;
end;

procedure TNetMenuActions.JoinClicked(Sender: TObjectGI);
begin
  ShowJoinDialog(Sender.MessageLoop);
end;

// Hosting (the in-game menu) --------------------------------------------------------------------

procedure UpdateHostControls(Screen: TMessageLoopGI);
var
  Button, Watch: TGraphButtonGI;
  Status: TLabelGI;
  Names: WideString;
begin
  Button := TGraphButtonGI(Screen.FindControlByPath(HostButtonName));
  Status := TLabelGI(Screen.FindControlByPath(HostLabelName));
  if (Button = nil) or (Status = nil) then
    Exit;
  // CHANGE: ENHANCEMENT - Shown while another human plays a text quest.
  Watch := TGraphButtonGI(Screen.FindControlByPath(WatchButtonName));
  if Watch <> nil then
    Watch.SetActive(Length(WatchableQuestHumans) > 0);
  // A client plays in another's game: it has nothing to host.
  Button.SetActive(NetRole <> nrClient);
  Status.SetActive(NetRole = nrHost);
  if NetRole = nrHost then
  begin
    Button.SetCaption(MultiplayerText('MenuStopHost', 'Stop hosting'));
    Names := ConnectedPlayerNames;
    if Names = '' then
      Names := '0';
    Status.SetText(
        ReplaceAllWideString(
            ReplaceAllWideString(
                MultiplayerText('MenuHostState', 'Hosting on port <Port>. Connected: <Players>.'),
                '<Port>',
                WideString(IntToStr(CurrentHost.Thread.ListenPort))
            ),
            '<Players>',
            Names
        )
    );
  end
  else
    Button.SetCaption(MultiplayerText('MenuHost', 'Host this game'));
end;

// The look of the new-game screen's caption buttons (ButExtended).
function CreateMenuButton(Owner: TObjectGI; const Name, Caption: WideString): TGraphButtonGI;
begin
  Result := TGraphButtonGI.Create(Owner);
  Result.SetName(Name);
  Result.EnterSound := 'Sound.ButtonEnter';
  Result.LeaveSound := 'Sound.ButtonLeave';
  Result.ClickSound := 'Sound.ButtonClick';
  Result.UpOnlyDown := True;
  Result.SetDepth(-3);
  Result.SetImageNormalPath('GI,Bm.FormGameSet2.ButExtN');
  Result.SetImageNormalActivePath('GI,Bm.FormGameSet2.ButExtN');
  Result.SetImageDownPath('GI,Bm.FormGameSet2.ButExtD');
  Result.SetSize(Result.GetMaxStateImageSize);
  Result.HitKind := gbhRect;
  Result.CaptionAlignX := taxCenter;
  Result.CaptionAlignY := tayCenterEx;
  Result.SetCaptionFontName('Font.2Ranger');
  Result.CaptionColors[0] := CurrentPixelFormat.PackRgbBytes(88, 229, 255);
  Result.CaptionColors[1] := CurrentPixelFormat.PackRgbBytes(248, 236, 96);
  Result.CaptionColors[2] := CurrentPixelFormat.PackRgbBytes(248, 164, 0);
  Result.CaptionColors[3] := CurrentPixelFormat.PackRgbBytes(248, 164, 0);
  Result.CaptionColors[4] := Result.CaptionColors[0];
  Result.CaptionColors[5] := Result.CaptionColors[0];
  Result.CaptionOffsets := Classes.Rect(0, -5, 0, -5);
  Result.SetCaption(Caption);
  Result.UpdateStateImagePlacement;
  Result.UpdateStateVisuals;
end;

procedure AddGameMenuHost(Screen: TMessageLoopGI);
var
  Menu, MainPanel: TObjectGI;
  Button, Watch: TGraphButtonGI;
  Status: TLabelGI;
  Top: Integer;
begin
  Menu := Screen.FindControlByPath('Resume');
  MainPanel := Screen.FindControlByPath('MainPanel');
  if (Menu = nil) or (MainPanel = nil) then
    Exit;
  Menu := Menu.Parent;
  if Actions = nil then
    Actions := TNetMenuActions.Create;
  Button := TGraphButtonGI(Screen.FindControlByPath(HostButtonName));
  if Button = nil then
  begin
    Button := CreateMenuButton(MainPanel, HostButtonName, MultiplayerText('MenuHost', 'Host this game'));
    Status := TLabelGI.Create(MainPanel);
    Status.SetName(HostLabelName);
    Status.SetDepth(-3);
    Status.SetFontName('Font.2Ranger');
    Status.SetTextColor(CurrentPixelFormat.PackRgbBytes(255, 239, 132));
    Status.SetShadowOffset(1);
    Status.SetShadowColor(CurrentPixelFormat.PackRgbBytes(0, 0, 0));
    Status.SetTextAlignX(taxCenter);
    Status.SetTextAlignY(tayCenterEx);
    Status.SetSize(Classes.Point(Menu.ClientSize.X + 200, 20));
    Status.SetActive(False);
  end
  else
    Status := TLabelGI(Screen.FindControlByPath(HostLabelName));
  Watch := TGraphButtonGI(Screen.FindControlByPath(WatchButtonName));
  if Watch = nil then
  begin
    Watch := CreateMenuButton(
        MainPanel,
        WatchButtonName,
        MultiplayerText('MenuWatch', 'Watch text quest')
    );
    Watch.SetActive(False);
  end;
  Button.UpCallback := Actions.HostClicked;
  Watch.UpCallback := Actions.WatchClicked;
  // Under the round menu, centred.
  Top := Menu.LocalPosition.Y + Menu.ClientSize.Y + GiScalePixels(6);
  Button.SetPosition(
      Classes.Point(Menu.LocalPosition.X + (Menu.ClientSize.X - Button.ClientSize.X) div 2, Top)
  );
  if Status <> nil then
    Status.SetPosition(
        Classes.Point(
            Menu.LocalPosition.X + (Menu.ClientSize.X - Status.ClientSize.X) div 2,
            Top + Button.ClientSize.Y + GiScalePixels(2)
        )
    );
  // Under the host's state.
  Inc(Top, Button.ClientSize.Y + GiScalePixels(2));
  if Status <> nil then
    Inc(Top, Status.ClientSize.Y);
  Watch.SetPosition(
      Classes.Point(
          Menu.LocalPosition.X + (Menu.ClientSize.X - Watch.ClientSize.X) div 2,
          Top + GiScalePixels(4)
      )
  );
  Screen.RootUiObject.UpdateAbsolutePosition;
  Screen.RootUiObject.UpdateSubtreeHitBounds;
end;

procedure GameMenuHostOpened(Screen: TMessageLoopGI);
begin
  if Actions = nil then
    Exit;
  UpdateHostControls(Screen);
  if Actions.HostTimer = nil then
    Actions.HostTimer := Screen.ScheduleCallbackTimer(
        HostRefreshMs,
        HostRefreshMs,
        Actions.RefreshHost,
        PtrInt(Screen)
    );
end;

procedure GameMenuHostClosed(Screen: TMessageLoopGI);
begin
  if (Actions <> nil) and (Actions.HostTimer <> nil) then
  begin
    Screen.CancelCallbackTimer(Actions.HostTimer);
    Actions.HostTimer := nil;
  end;
end;

procedure TNetMenuActions.RefreshHost(Timer: PCallbackTimerGI; UserData: PtrInt);
begin
  UpdateHostControls(TMessageLoopGI(UserData));
end;

function GameMenuHostContains(Screen: TMessageLoopGI; Point: TPoint): Boolean;
var
  Button, Watch: TObjectGI;
begin
  Button := Screen.FindControlByPath(HostButtonName);
  Watch := Screen.FindControlByPath(WatchButtonName);
  Result :=
      ((Button <> nil) and Button.Active and Button.ContainsPoint(Point))
          or ((Watch <> nil) and Watch.Active and Watch.ContainsPoint(Point));
end;

// Asks for the port and hosts the running game; says where it listens.
procedure HostFromMenu(Screen: TMessageLoopGI);
var
  Fields: TNetEntryFields;
  Refusal: WideString;
  Port: Integer;
begin
  Refusal := HostingRefusal;
  if Refusal <> '' then
  begin
    ShowMessageBoxGI(Screen, Refusal, mbgOK or mbgWarning);
    Exit;
  end;
  Fields := Default(TNetEntryFields);
  Fields.Text := MultiplayerText(
      'HostText',
      'Host this game: other players join it from their main menu with this computer''s address'
          + ' and the port. 0 picks a free port.'
  );
  Fields.Count := 1;
  Fields.Captions[0] := MultiplayerText('HostPort', 'Port:');
  Fields.Values[0] := UserSetting('NetHostPort', WideString(IntToStr(DefaultNetPort)));
  Fields.MaxLengths[0] := 5;
  Fields.DigitsOnly[0] := True;
  repeat
    if not AskFields(Screen, Fields) or (Screen.ExitCode <> 0) then
      Exit;
    Port := StrToIntDef(UTF8Encode(Fields.Values[0]), -1);
    if (Port >= 0) and (Port <= 65535) then
      Break;
    ShowMessageBoxGI(
        Screen,
        MultiplayerText('BadPort', 'The port is a number from 0 to 65535.'),
        mbgOK or mbgError
    );
  until False;
  SaveUserSetting('NetHostPort', WideString(IntToStr(Port)));
  try
    HostRunningGame(Port);
  except
    on E: Exception do
    begin
      ShowMessageBoxGI(
          Screen,
          MultiplayerText('HostFailed', 'Cannot host the game:') + ' ' + WideString(E.Message),
          mbgOK or mbgError
      );
      Exit;
    end;
  end;
  UpdateHostControls(Screen);
  ShowMessageBoxGI(Screen, HostStatusText, mbgOK or mbgLeftAlign);
end;

// Shows the host's state and offers to stop hosting.
procedure StopFromMenu(Screen: TMessageLoopGI);
begin
  if ShowMessageBoxGI(
          Screen,
          HostStatusText
              + #13#10#13#10
              + MultiplayerText(
                  'StopQuestion',
                  'Stop hosting? The other players leave the game; their rangers hold position.'
              ),
          mbgOK or mbgCancel or mbgQuestion or mbgLeftAlign)
      <> mbgResultOK then
    Exit;
  if NetRole = nrHost then
    StopHostingGame;
  UpdateHostControls(Screen);
end;

procedure GameMenuHostClicked(Screen: TMessageLoopGI);
begin
  case NetRole of
    nrHost:
      StopFromMenu(Screen);
    nrNone:
      HostFromMenu(Screen);
  end;
end;

procedure TNetMenuActions.HostClicked(Sender: TObjectGI);
begin
  GameMenuHostClicked(Sender.MessageLoop);
end;

procedure GameMenuWatchClicked(Screen: TMessageLoopGI);
begin
  WatchTextQuestFromMenu;
  UpdateHostControls(Screen);
end;

procedure TNetMenuActions.WatchClicked(Sender: TObjectGI);
begin
  GameMenuWatchClicked(Sender.MessageLoop);
end;

finalization
  FreeAndNil(Actions);
end.
