{$EXCESSPRECISION OFF}
unit fJump;
{$R-}
{$Q-}
{$B-}
{$A8}
interface
uses
  GI_MessageLoop,
  fPanelLoad;
type
  TfJump = class;
  TfJump = class(TMessageLoopGI)
    TransitionTimer: PCallbackTimerGI;
    LoadingStarted: Boolean;
    NoPendingLoads: Boolean;
    GapD6: array[0..1] of Byte;
    Progress: Single;
    LoadPanel: TfPanelLoad;
    MovieStartTick: Cardinal;
    MovieTimer: PCallbackTimerGI;
    RestoreOrdersOnArrival: Boolean;
    GapE9: array[0..2] of Byte;
    procedure OnOpen; override;
    procedure OnClose; override;
    procedure SelectMusic; override;
    procedure InitializeLayout; override;
    constructor Create;
    destructor Destroy; override;
    procedure AdvanceTravel(Timer: PCallbackTimerGI; UserData: PtrInt);
    procedure AdvanceLoading(Timer: PCallbackTimerGI; UserData: PtrInt);
    procedure AdvanceMovie(Timer: PCallbackTimerGI; UserData: PtrInt);
    function StopMovie: Boolean;
  end;
procedure LinkRecoveredTypes;
implementation
uses
  aPlayerActions,
  aHuman,
  EC_Cache,
  EC_Struct,
  aGalaxyStruct,
  SysUtils,
  Classes,
  Types,
  Math,
  Windows,
  MMSystem,
  Globals,
  GlobalsV,
  GR_Main,
  GR_DX,
  GR_Music,
  GI_XviD,
  EC_Str,
  aPlayer,
  aShip,
  aGalaxy,
  aRuins,
  aScript,
  aItem,
  ThreadCalc,
  aCalc,
  fLoad,
  fStarMap,
  fRuinsTalk,
  HotSeat,
  NetPlay,
  NetSession;

constructor TfJump.Create;
begin
  inherited Create;
  LoadPanel := TfPanelLoad.Create;
end;

destructor TfJump.Destroy;
begin
  if LoadPanel <> nil then
  begin
    LoadPanel.Free;
    LoadPanel := nil;
  end;
  inherited Destroy;
end;

procedure TfJump.InitializeLayout;
begin
  inherited InitializeLayout;
  LoadPanel.InitializeLayout(Self);
  AppendLogTextThreadSafe('fJump... ');
  ViewportRect := Classes.Rect(0, 0, GameScreenWidth, GameScreenHeight);
  with GetByName('') do
  begin
    SetSize(Classes.Point(GameScreenWidth, GameScreenHeight));
    FindByNameRecursive('Film').SetSize(Classes.Point(GameScreenWidth, GameScreenHeight));
  end;
  AppendLogLineThreadSafe('ok');
  RestoreOrdersOnArrival := False;
end;

procedure TfJump.OnOpen;
var
  MovieConfig, MoviePath: WideString;
  PollMs: Integer;
  procedure BeginTravel; cdecl; // @addr $670C2C @ida "void __cdecl $name(void *ParentFrame);"
  begin
    if TransitionTimer <> nil then
    begin
      CancelCallbackTimer(TransitionTimer);
      TransitionTimer := nil;
    end;
    TransitionTimer := ScheduleCallbackTimer(PollMs, PollMs, AdvanceTravel);
    LoadPanel.SetProgress(0);
    if not DeferScreenPresentation then
      LoadPanel.Show;
  end;
begin

  // CHANGE: PERFORMANCE - Skip travel waits/presentation when fast transitions are enabled.
  DeferScreenPresentation := FastTravelTransitions and not LocalPlayer.IsDockedToShip;
  if DeferScreenPresentation then
    PollMs := 1
  else
    PollMs := 20;
  // These resources are immutable and often shared by adjacent systems. Keep
  // them under the normal LRU budget instead of forcing disk reads every jump.
  GlobalCache.TrimToBudget(GlobalCache.ResidentByteLimit);
  ReleaseAllTextureSurfaces;
  if not LocalPlayer.IsDockedToShip then
  begin
    SetCursorActive(True);
    LoadPanel.OnOpen;
    RunGlobalScriptsForContext(LocalPlayer.CurrentStar, 2, LocalHuman);
    LoadingStarted := False;
    NoPendingLoads := False;
    if LocalPlayer.InHyperspace or LocalPlayer.IsDockedToShip then
      TransitionTimer := ScheduleCallbackTimer(PollMs, PollMs, AdvanceTravel)
    else
      AdvanceLoading(nil, 0);
    Progress := 0;
    LoadPanel.SetProgress(0);
    if not DeferScreenPresentation then
      LoadPanel.Show;
    Present;
  end
  else if LocalPlayer.IsDockedToShip then
  begin
    SetCursorActive(False);
    LoadPanel.OnOpen;
    RunGlobalScriptsForContext(LocalPlayer.CurrentStar, 2, LocalHuman);
    LoadingStarted := False;
    NoPendingLoads := False;
    Progress := 0;
    Present;
    if SkipVideo then
    begin
      BeginTravel;
      Exit;
    end;
    LoadPanel.SetProgress(1);
    LoadPanel.Hide;
    if LocalPlayer.DockedTo.TypeId = Byte(rstMilitaryBase) then
      MovieConfig := LanguageDataConfig.GetParamByPathOrMarker('FormRuins.WB.HyperJumpVideo')
    else if LocalPlayer.DockedTo.TypeId = Byte(rstDominion) then
      MovieConfig := LanguageDataConfig.GetParamByPathOrMarker('FormRuins.CB.HyperJumpVideo')
    else
    begin
      BeginTravel;
      Exit;
    end;
    MoviePath := ExtractDelimitedPartW(MovieConfig, 0, ',');
    with GetByName('Film') as TxvidGI do
    begin
      SetActive(True);
      if ImageOpen(MoviePath, True) then
      begin
        if MusicEnabled and (CountDelimitedPartsW(MovieConfig, ',') > 1) then
        begin
          MusicManager.StopImmediately;
          while MusicManager.IsPlaying do
            SysUtils.Sleep(1);
          MusicManager.PlayCategory(ExtractDelimitedPartW(MovieConfig, 1, ','));
          while not MusicManager.IsPlaying do
            SysUtils.Sleep(1);
        end;
        MovieStartTick := timeGetTime;
        if MovieTimer <> nil then
        begin
          CancelCallbackTimer(MovieTimer);
          MovieTimer := nil;
        end;
        MovieTimer := ScheduleCallbackTimer(5, 5, AdvanceMovie);
      end
      else
      begin
        SetActive(False);
        BeginTravel;
      end;
    end;
  end;
end;

procedure TfJump.OnClose;
begin
  StopMovie;
  with GetByName('Film') as TxvidGI do
  begin
    ImageClose;
    SetActive(False);
  end;
  LoadPanel.OnClose;
  if TransitionTimer <> nil then
  begin
    CancelCallbackTimer(TransitionTimer);
    TransitionTimer := nil;
  end;
end;

procedure TfJump.AdvanceTravel(Timer: PCallbackTimerGI; UserData: PtrInt);
begin
  // CHANGE: ENHANCEMENT - A networked client runs no hyperspace day: the host runs its steps,
  // and each state it sends is applied between screens (NetPlay).
  if NetRole = nrClient then
  begin
    Progress := Progress + 0.008;
    if Progress > 0.49 then
      Progress := 0.5;
    LoadPanel.SetProgress(Progress);
    ClientTravelTick(Self);
    Exit;
  end;
  if (LocalPlayer = nil) or (LocalPlayer.GetHull.HullPoints <= 0) then
  begin
    if LocalPlayer <> nil then
      DismissScoreScreen;
    while LocalPlayer <> nil do
      SysUtils.Sleep(1);
    RequestedScreenId := screenGameEnd;
    RequestClose(1);
    Exit;
  end;
  Progress := Progress + 0.008;
  if Progress > 0.49 then
    Progress := 0.5;
  LoadPanel.SetProgress(Progress);
  if IsTurnCalculationRunningUI
      or (TurnCalculationPhase in [tcpGalaxyRunning, tcpPlayerStarRunning]) then
    Exit;
  if TurnCalculationPhase = tcpGalaxyFinished then
  begin
    // CHANGE: ENHANCEMENT - A human in hyperspace does not hold the day, but the others do
    // (ROADMAP.md, Phase 4, item 2); in hot-seat the screen passes to the next one of them. A
    // networked host waits for its peers (NetPlay).
    if not NetEndTurn(Self) then
    begin
      PassTurn(Self);
      Exit;
    end;
    QueuePlayerStarTurnCalculation;
    Exit;
  end;
  if LocalPlayer.IsDockedToShip then
  begin
    if (LocalPlayer.DockedTo.Order <> soTeleport)
        and (((LocalPlayer.DockedTo as TRuins).FlyToStar = LocalPlayer.DockedTo.CurrentStar)
            or ((LocalPlayer.DockedTo as TRuins).FlyToStar = nil)) then
    begin
      QueueGalaxyTurnCalculation;
      AdvanceLoading(nil, 0);
      Exit;
    end;
    HyperspaceStep(False);
    Galaxy.GenerateSpaceBackground(LocalPlayer.CurrentStar.BackgroundImage);
    QueueGalaxyTurnCalculation;
    Present;
  end
  else
  begin
    if not (LocalPlayer.Order in [soJump, soJumpHole, soTeleport])
        or ((LocalPlayer.Order = soJumpHole) and (LocalPlayer.OrderStateData = -65536)) then
    begin
      QueueGalaxyTurnCalculation;
      StarMapScreen.SetMapCenterManually(TruncatePointF(LocalPlayer.Position));
      StarMapScreen.ResumeMode := smrTurnFilm;
      AdvanceLoading(nil, 0);
      Exit;
    end;
    HyperspaceStep(False);
    Galaxy.GenerateSpaceBackground(LocalPlayer.CurrentStar.BackgroundImage);
    QueueGalaxyTurnCalculation;
    Present;
  end;
end;

procedure TfJump.AdvanceLoading(Timer: PCallbackTimerGI; UserData: PtrInt);
var
  Loads: TList;
  PollMs: Integer;
begin
  if DeferScreenPresentation then
    PollMs := 1
  else
    PollMs := 20;
  if not LoadingStarted then
  begin

    LoadingStarted := True;
    if TransitionTimer <> nil then
    begin
      CancelCallbackTimer(TransitionTimer);
      TransitionTimer := nil;
    end;
    Loads := TList.Create;
    QueueSpaceLoadingAssets(Loads, RootUiObject);
    if Loads.Count > 0 then
    begin
      CacheLoader.SetPendingLoads(Loads, True);
      TransitionTimer := ScheduleCallbackTimer(PollMs, PollMs, AdvanceLoading);
    end
    else
    begin
      TransitionTimer := ScheduleCallbackTimer(PollMs, PollMs, AdvanceLoading);
      NoPendingLoads := True;
      Loads.Free;
    end;
  end
  else
  begin
    if NoPendingLoads then
      Progress := Progress + 0.008
    else
      Progress :=
          Min(
              Progress + 0.008,
              CacheLoader.CompletedLoadCount / CacheLoader.TotalLoadCount * 0.5 + 0.5
          );
    if Progress > 0.99 then
      Progress := 1;
    LoadPanel.SetProgress(Progress);
    // Travel is finished before this phase; only pending assets gate arrival.
    if NoPendingLoads or not CacheLoader.IsRunning then
    begin
      Progress := 1;
      LoadPanel.SetProgress(1);
      if TransitionTimer <> nil then
      begin
        CancelCallbackTimer(TransitionTimer);
        TransitionTimer := nil;
      end;
      if LocalPlayer.IsDockedToShip then
      begin
        RuinsTalkScreen.ShowArrivalVideo := True;
        RequestedScreenId := screenRuinsTalk;
      end
      else
      begin
        RequestedScreenId := screenStarMap;
        if RestoreOrdersOnArrival then
        begin
          StarMapScreen.ResumeMode := smrOrders;
          SpaceViewPosition := LocalPlayer.Position;
          RestoreOrdersOnArrival := False;
        end;
      end;
      RequestClose(1);
    end;
  end;
end;

procedure TfJump.AdvanceMovie(Timer: PCallbackTimerGI; UserData: PtrInt);
begin
  if (GetByName('Film') as TxvidGI).SetPlaybackTime(timeGetTime - MovieStartTick) then
    StopMovie;
end;

function TfJump.StopMovie: Boolean;
begin
  Result := MovieTimer <> nil;
  if MusicEnabled and Result then
    MusicManager.StopImmediately;
  if MovieTimer <> nil then
  begin
    CancelCallbackTimer(MovieTimer);
    MovieTimer := nil;
  end;
  InvalidateViewport;
  if TransitionTimer <> nil then
  begin
    CancelCallbackTimer(TransitionTimer);
    TransitionTimer := nil;
  end;
  TransitionTimer := ScheduleCallbackTimer(20, 20, AdvanceTravel);
end;

procedure TfJump.SelectMusic;
begin
end;

procedure LinkRecoveredTypes;
begin
  TRuins.ClassName;
  TxvidGI.ClassName;
end;
end.
