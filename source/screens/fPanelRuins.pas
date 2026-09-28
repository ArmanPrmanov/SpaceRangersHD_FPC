{$EXCESSPRECISION OFF}
unit fPanelRuins;
{$R-}
{$Q-}
{$B-}
{$A8}
interface
uses
  EC_Struct,
  GI_MessageLoop;
type
  TfPanelRuins = class;
  TfPanelRuins = class(TObjectEx)
    Screen: TMessageLoopGI;
    constructor Create;
    destructor Destroy; override;
    procedure InitializeLayout(Screen: TMessageLoopGI);
    procedure OnOpen;
    procedure OnClose;
    procedure Show;
    procedure Hide;
    procedure ServicesClicked(Sender: TObjectGI);
    procedure EquipmentShopClicked(Sender: TObjectGI);
    procedure GoodsShopClicked(Sender: TObjectGI);
    procedure InformationClicked(Sender: TObjectGI);
    procedure HangarClicked(Sender: TObjectGI);
    procedure TakeOffForStationTravel;
    procedure ProcessKeyDown(Key: Integer);
  end;
procedure LinkRecoveredTypes;
implementation
uses
  aPlayerActions,
  aHuman,
  Math,
  aRanger,
  fEquipmentShop,
  aShopStock,
  fGalaxy2,
  Classes,
  Windows,
  GR_Main,
  GR_Music,
  Globals,
  GlobalsV,
  GI_GraphButton,
  GI_MessageBox,
  aConst,
  aGalaxy,
  aGalaxyStruct,
  aMyFunction,
  aPlayer,
  aSaveLoad,
  aScript,
  fRuinsTalk,
  fPanelLoad,
  fSaveManager,
  fStarMap,
  ThreadCalc,
  aCalc,
  HotSeat,
  NetPlay;

constructor TfPanelRuins.Create;
begin
  inherited Create;
end;

destructor TfPanelRuins.Destroy;
begin
  inherited Destroy;
end;

procedure TfPanelRuins.InitializeLayout(Screen: TMessageLoopGI);
begin
  Self.Screen := Screen;
  AppendLogTextThreadSafe('fPanelRuins... ');
  with Self.Screen.GetByName('PanelRuins') do
    SetPosition(
        Classes.Point(LocalPosition.X + ExtraScreenWidth, LocalPosition.Y + ExtraScreenHeight)
    );
  AppendLogLineThreadSafe('ok');
  (Self.Screen.GetByName('PR_Gov') as TGraphButtonGI).UpCallback := ServicesClicked;
  (Self.Screen.GetByName('PR_Shop') as TGraphButtonGI).UpCallback := EquipmentShopClicked;
  (Self.Screen.GetByName('PR_Goods') as TGraphButtonGI).UpCallback := GoodsShopClicked;
  (Self.Screen.GetByName('PR_Info') as TGraphButtonGI).UpCallback := InformationClicked;
  (Self.Screen.GetByName('PR_Hangar') as TGraphButtonGI).UpCallback := HangarClicked;
end;

procedure TfPanelRuins.OnOpen;
begin
  with Screen.GetByName('PanelRuins') do
    SetActive(LocalPlayer.RuinsMode = 0);
end;

procedure TfPanelRuins.OnClose;
begin
end;

procedure TfPanelRuins.Show;
begin
  Screen.GetByName('PanelRuins').SetActive(True);
end;

procedure TfPanelRuins.Hide;
begin
  Screen.GetByName('PanelRuins').SetActive(False);
end;

procedure TfPanelRuins.ServicesClicked(Sender: TObjectGI);
begin
  if Screen.ExitCode <> 0 then
    Exit;
  if (ActiveLoadPanel <> nil) and ActiveLoadPanel.IsAnimatingShutters then
    Exit;
  if (LocalPlayer.PendingDockDialogue > 1) and (RuinsTalkScreen = Screen) then
    Exit;
  if HasPendingScriptRequests then
    Exit;
  RequestedScreenId := screenRuinsTalk;
  Screen.RequestClose(1);
end;

procedure TfPanelRuins.EquipmentShopClicked(Sender: TObjectGI);
begin
  if Screen.ExitCode <> 0 then
    Exit;
  if (ActiveLoadPanel <> nil) and ActiveLoadPanel.IsAnimatingShutters then
    Exit;
  if (LocalPlayer.PendingDockDialogue > 1) and (RuinsTalkScreen = Screen) then
    Exit;
  if (LocalPlayer.RuinsMode > 0) and (RuinsTalkScreen = Screen) then
    Exit;
  if HasPendingScriptRequests then
    Exit;
  if (LocalPlayer.DockedTo.TypeId = Byte(rstBusinessCenter)) and (LocalPlayer.DebtDefaultCount > 1) then
    ShowMessageBoxGI(
        Screen,
        LocalizedColorText('FormRuins.BK.DebtNoAccess'),
        mbgCancel or mbgWarning
    )
  else
  begin
    RequestedScreenId := screenEquipmentShop;
    Screen.RequestClose(1);
  end;
end;

procedure TfPanelRuins.GoodsShopClicked(Sender: TObjectGI);
begin
  if Screen.ExitCode <> 0 then
    Exit;
  if (ActiveLoadPanel <> nil) and ActiveLoadPanel.IsAnimatingShutters then
    Exit;
  if (LocalPlayer.PendingDockDialogue > 1) and (RuinsTalkScreen = Screen) then
    Exit;
  if (LocalPlayer.RuinsMode > 0) and (RuinsTalkScreen = Screen) then
    Exit;
  if HasPendingScriptRequests then
    Exit;
  if (LocalPlayer.DockedTo.TypeId = Byte(rstBusinessCenter)) and (LocalPlayer.DebtDefaultCount > 1) then
    ShowMessageBoxGI(
        Screen,
        LocalizedColorText('FormRuins.BK.DebtNoAccess'),
        mbgCancel or mbgWarning
    )
  else
  begin
    RequestedScreenId := screenGoodsShop;
    Screen.RequestClose(1);
  end;
end;

procedure TfPanelRuins.InformationClicked(Sender: TObjectGI);
begin
  if Screen.ExitCode <> 0 then
    Exit;
  if (ActiveLoadPanel <> nil) and ActiveLoadPanel.IsAnimatingShutters then
    Exit;
  if (LocalPlayer.PendingDockDialogue > 1) and (RuinsTalkScreen = Screen) then
    Exit;
  if (LocalPlayer.RuinsMode > 0) and (RuinsTalkScreen = Screen) then
    Exit;
  if HasPendingScriptRequests then
    Exit;
  if (LocalPlayer.DockedTo.TypeId = Byte(rstBusinessCenter)) and (LocalPlayer.DebtDefaultCount > 1) then
    ShowMessageBoxGI(
        Screen,
        LocalizedColorText('FormRuins.BK.DebtNoAccess'),
        mbgCancel or mbgWarning
    )
  else
  begin
    RequestedScreenId := screenInfo;
    Screen.RequestClose(1);
  end;
end;

procedure TfPanelRuins.HangarClicked(Sender: TObjectGI);
begin
  if Screen.ExitCode <> 0 then
    Exit;
  if (ActiveLoadPanel <> nil) and ActiveLoadPanel.IsAnimatingShutters then
    Exit;
  if (LocalPlayer.PendingDockDialogue > 1) and (RuinsTalkScreen = Screen) then
    Exit;
  if (LocalPlayer.RuinsMode > 0) and (RuinsTalkScreen = Screen) then
    Exit;
  if HasPendingScriptRequests then
    Exit;
  RequestedScreenId := screenHangar;
  Screen.RequestClose(1);
end;

procedure TfPanelRuins.TakeOffForStationTravel;
var
  Index: Integer;
begin

  aCalc.WaitForTurnCalculationUI;
  CaptureSavePreview;
  CaptureGalaxyPreview(Screen);
  SaveManagerReturnScreenId := FormToId(Screen);
  SaveGameToFile(SaveManagerScreen.GetAutoSavePath, 'as');
  if MusicManager.CategoryOverride = '' then
    MusicManager.RequestFadeOut;
  Takeoff(tfEndAutomaticControl or tfReturnShopStock);
  LocalHuman.StarMapWeaponPanelOpen := False;
  FilmCameraFollow := True;
  // CHANGE: ENHANCEMENT - The day starts only when every human has ended the turn
  // (ROADMAP.md, Phase 4, item 2); in hot-seat the screen passes to the next human. A
  // networked host waits for its peers; a client waits for the host's day (NetPlay).
  if not NetEndTurn(Screen) then
  begin
    PassTurn(Screen);
    Exit;
  end;
  CalculatePlayerStarTurnAndWait;
  if ExitScreenLoop then
    Exit;
  QueueGalaxyTurnCalculation;
  LocalHuman.StarMapWeaponPanelOpen := False;
  StarMapScreen.ResumeMode := smrTurnFilm;
  ScreenLoadMode := 2;
  PostLoadScreenId := screenStarMap;
  RequestedScreenId := screenLoad;
  if ActiveLoadPanel <> nil then
  begin
    ActiveLoadPanel.SelectBackgroundStyle(0);
    ActiveLoadPanel.RefreshBackgroundImages;
    ActiveLoadPanel.StartClosingShutters;
  end
  else
    Screen.RequestClose(1);
end;

procedure TfPanelRuins.ProcessKeyDown(Key: Integer);
begin
  if Screen.ExitCode <> 0 then
    Exit;
  if IsVirtualKeyDown(VK_CONTROL) or IsVirtualKeyDown(VK_SHIFT) or IsVirtualKeyDown(VK_MENU) then
    Exit;
  if not LocalPlayer.IsDockedToShip then
    Exit;
  if (ActiveLoadPanel <> nil) and ActiveLoadPanel.IsAnimatingShutters then
    Exit;
  if (Key = Ord('G')) and Screen.GetByName('PR_Gov').Active then
    ServicesClicked(nil)
  else if (Key = Ord('E')) and Screen.GetByName('PR_Shop').Active then
    EquipmentShopClicked(nil)
  else if (Key = Ord('T')) and Screen.GetByName('PR_Goods').Active then
    GoodsShopClicked(nil)
  else if (Key = Ord('I')) and Screen.GetByName('PR_Info').Active then
    InformationClicked(nil)
  else if (Key = Ord('H')) and Screen.GetByName('PR_Hangar').Active then
    HangarClicked(nil);
end;

procedure LinkRecoveredTypes;
begin
  TGraphButtonGI.ClassName;
end;
end.
