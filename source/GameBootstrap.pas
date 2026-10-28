{$EXCESSPRECISION OFF}
unit GameBootstrap;

// Shared FPC game startup and application lifecycle.
interface

procedure RunRangers;

implementation

uses
  aHuman,
  aObjectRefs,
  aPortText,
  aSession,
  RTLFileSystem,
  fIntroduction,
  fGameSettings2,
  CrashSymbols,
  PoisonFrees,
  WorkerErrors,
  {$IFDEF UNIX}
  BaseUnix,
  {$ELSE}
  Process,
  {$ENDIF}
  GameNative,
  Windows,
  SysUtils,
  Classes,
  Forms,
  MMSystem,
  ActiveX,
  GameApplication,
  GR_Main,
  Globals,
  GlobalsV,
  EC_BlockPar,
  EC_Str,
  EC_Expression,
  EC_HsFile,
  aPacket,
  aPlayer,
  aGalaxy,
  aScript,
  aMyFunction,
  GI_Main,
  GI_MessageLoop,
  GI_GraphButton,
  fMainForm,
  fLoadQuest,
  fPlanetQuest,
  fLoad,
  fLoadRobot,
  fLoadAB,
  fSaveManager,
  fPanelLoad,
  MessageText,
  fCfgSettings,
  fAbout,
  fAchievements,
  fScore,
  Achievements,
  NoSteamAchievemens,
  aConst,
  ThreadCalc,
  aSaveLoad,
  ObserverHost,
  HeadlessSim,
  HeadlessNet,
  CommandLog,
  HotSeat,
  NetPlay,
  SimEventHandlers,
  InterfaceOverrideViews,
  CheatCode;

var
  ApplicationEvents: TAD;
  StartupStage: AnsiString;
  LogReady, PlatformReady, TimerPeriodStarted, CampaignRuntimeStarted, ScriptRuntimeStarted:
      Boolean;
  GameDirectory, UserDirectory, ExecutablePath: AnsiString;
  RestartRequested: Boolean;
  GpuRendererRequested: Boolean;
  ObserverMode: Boolean;
  ObserverSave: AnsiString;
  SimulationMode: Boolean;
  Simulation: TSimulationOptions;
  RecordCommandsPath: AnsiString;
  StartupSave: AnsiString;
  Replay: TReplayOptions;
  PoisonQuarantineMB: Integer;

procedure Log(const Text: AnsiString);
begin
  if LogReady then
    try
      AppendLogLineThreadSafe(Text);
    except
      // Do not replace a startup/cleanup exception with a failed log write.
    end;
end;

procedure Stage(const Text: AnsiString);
begin
  StartupStage := Text;

  Log('Rangers: ' + Text);
end;

procedure LogExceptionTrace;
var
  I: Integer;
begin
  Log('  ' + DescribeCodeAddress(ExceptAddr));
  for I := 0 to ExceptFrameCount - 1 do
    Log('  ' + DescribeCodeAddress(ExceptFrames[I]));
  // CHANGE: ENHANCEMENT - Say whether a fault touched a poisoned address (--poison-frees).
  if PoisonFaultHint(ExceptObject) <> '' then
    Log('  ' + PoisonFaultHint(ExceptObject));
  DumpExceptionBackTrace(StdErr);
end;

// Each of a comma-separated list of paths, expanded.
function ExpandFileNames(const Paths: AnsiString): AnsiString;
var
  Rest: AnsiString;
  Position: Integer;
begin
  Result := '';
  Rest := Paths;
  while Rest <> '' do
  begin
    Position := Pos(',', Rest);
    if Position = 0 then
      Position := Length(Rest) + 1;
    if Result <> '' then
      Result := Result + ',';
    Result := Result + ExpandFileName(Copy(Rest, 1, Position - 1));
    Delete(Rest, 1, Position);
  end;
end;

procedure ReadOptions;
var
  I: Integer;
  Argument, Candidate: AnsiString;
  ExplicitLanguage: Boolean;
  LanguageFile: TStringList;
begin
  ExplicitLanguage := False;
  ExecutablePath := ExpandFileName(ParamStr(0));
  GameDirectory := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  Candidate := GameDirectory;
  for I := 0 to 7 do
  begin
    if RTLFileSystem.FileExists(Candidate + '/INSTALL.TXT') then
    begin
      GameDirectory := Candidate;
      Break
    end;
    if RTLFileSystem.FileExists(Candidate + '/game/INSTALL.TXT') then
    begin
      GameDirectory := Candidate + '/game';
      Break
    end;
    Candidate := ExcludeTrailingPathDelimiter(ExtractFileDir(Candidate));
  end;
{$IFDEF MSWINDOWS}
  // CHANGE: PORTABILITY - Use a Windows profile apart from the original game's Documents folder.
  UserDirectory :=
      UTF8Encode(SysUtils.GetEnvironmentVariable(UnicodeString('APPDATA'))) + '\SpaceRangersHD';
{$ELSE}
  UserDirectory :=
      SysUtils.GetEnvironmentVariable('HOME') + '/Library/Application Support/SpaceRangersHD';
{$ENDIF}
  SelectedLanguage := 'russian';
  Simulation.NetHostPort := -1;
  for I := 1 to ParamCount do
  begin
    Argument := ParamStr(I);
    if Argument = '--no-thumbnail-cache' then
      CacheInfoThumbnails := False
    else if Argument = '--renderer=software' then
    begin
      GpuRendererRequested := False;
      sr_renderer_select(0)
    end
    else if Argument = '--renderer=sdl' then
    begin
      GpuRendererRequested := True;
      sr_renderer_select(1)
    end
    else if Argument = '--transitions=fast' then
      FastTravelTransitions := True
    else if Argument = '--transitions=original' then
      FastTravelTransitions := False
    else if Argument = '--observer' then
      ObserverMode := True
    else if Pos('--observer-save=', Argument) = 1 then
    begin
      ObserverMode := True;
      ObserverSave := ExpandFileName(Copy(Argument, 17, MaxInt))
    end
    // CHANGE: ENHANCEMENT - Headless turn runner for regression tests.
    else if Pos('--sim-save=', Argument) = 1 then
    begin
      SimulationMode := True;
      Simulation.SavePath := ExpandFileName(Copy(Argument, 12, MaxInt))
    end
    // CHANGE: ENHANCEMENT - A new game instead of a save, to test a host's new game.
    else if Argument = '--sim-new-game' then
    begin
      SimulationMode := True;
      Simulation.SavePath := NewGameSave
    end
    else if Pos('--sim-turns=', Argument) = 1 then
      Simulation.Turns := StrToInt(Copy(Argument, 13, MaxInt))
    else if Pos('--sim-seed=', Argument) = 1 then
      Simulation.Seed := StrToDWord(Copy(Argument, 12, MaxInt))
    // CHANGE: ENHANCEMENT - Record play as commands and replay it headlessly.
    else if Pos('--record-commands=', Argument) = 1 then
      RecordCommandsPath := ExpandFileName(Copy(Argument, 19, MaxInt))
    else if Pos('--replay-commands=', Argument) = 1 then
    begin
      SimulationMode := True;
      // One log, several separated by commas (one per human), or a directory of them.
      Replay.LogPath := ExpandFileNames(Copy(Argument, 19, MaxInt))
    end
    else if Argument = '--replay-verbose' then
      Replay.Verbose := True
    // CHANGE: ENHANCEMENT - Add humans to test more than one (ROADMAP.md, Phase 4).
    else if Pos('--sim-humans=', Argument) = 1 then
      Simulation.Humans := StrToInt(Copy(Argument, 14, MaxInt))
    else if Argument = '--sim-session-probe' then
      Simulation.SessionProbe := True
    else if Argument = '--sim-humans-dump' then
      Simulation.HumansDump := True
    else if Argument = '--sim-pvp' then
      Simulation.Pvp := True
    // CHANGE: ENHANCEMENT - Hot-seat (ROADMAP.md, Phase 4): N humans take turns at this
    // machine; headless, every human plays DAYS days from its own commands.
    else if Pos('--hotseat=', Argument) = 1 then
      HotSeatHumans := StrToInt(Copy(Argument, 11, MaxInt))
    // CHANGE: ENHANCEMENT - Open a save at startup, past the main menu.
    else if Pos('--load-save=', Argument) = 1 then
      StartupSave := ExpandFileName(Copy(Argument, 13, MaxInt))
    else if Pos('--sim-hotseat=', Argument) = 1 then
      Simulation.HotSeatDays := StrToInt(Copy(Argument, 15, MaxInt))
    // CHANGE: ENHANCEMENT - Networked play over loopback (ROADMAP.md, Phase 5): a headless
    // host with --sim-save, and headless clients that join it.
    else if Pos('--sim-net-host=', Argument) = 1 then
      Simulation.NetHostPort := StrToInt(Copy(Argument, 16, MaxInt))
    else if Pos('--sim-net-clients=', Argument) = 1 then
      Simulation.NetClients := StrToInt(Copy(Argument, 19, MaxInt))
    else if Pos('--sim-net-join=', Argument) = 1 then
    begin
      SimulationMode := True;
      Simulation.NetJoin := Copy(Argument, 16, MaxInt)
    end
    else if Pos('--sim-net-name=', Argument) = 1 then
      Simulation.NetName := Copy(Argument, 16, MaxInt)
    // CHANGE: ENHANCEMENT - Networked play in the game (ROADMAP.md, Phase 5): host the running
    // game, or join one.
    else if Pos('--host=', Argument) = 1 then
      CommandLineHostPort := StrToInt(Copy(Argument, 8, MaxInt))
    else if Pos('--join=', Argument) = 1 then
      CommandLineJoin := Copy(Argument, 8, MaxInt)
    else if Pos('--name=', Argument) = 1 then
      CommandLineName := Copy(Argument, 8, MaxInt)
    else if Pos('--net-dump=', Argument) = 1 then
      StateDumpDirectory := ExpandFileName(Copy(Argument, 12, MaxInt))
    else if Pos('--sim-net-leave-at=', Argument) = 1 then
      Simulation.NetLeaveAt := StrToInt(Copy(Argument, 20, MaxInt))
    // CHANGE: ENHANCEMENT - Remote dialogue (ROADMAP.md, Phase 5): the host's day asks a remote
    // human something from day N on; a replay of the host's log with the same flag asks it too.
    else if Pos('--sim-net-talk=', Argument) = 1 then
      Simulation.NetTalkDay := StrToInt(Copy(Argument, 16, MaxInt))
    else if Argument = '--sim-net-talk-leave' then
      Simulation.NetTalkLeave := True
    // CHANGE: ENHANCEMENT - LAN-session checks (docs/network.md, Tests): a talk during a
    // client's film, a join cancelled while the state comes, a host that stops hosting.
    else if Argument = '--sim-net-talk-after-film' then
      Simulation.NetTalkAfterFilm := True
    else if Pos('--sim-net-film-ms=', Argument) = 1 then
      Simulation.NetFilmMs := StrToInt(Copy(Argument, 19, MaxInt))
    else if Argument = '--sim-net-cancel-join' then
      Simulation.NetCancelJoin := True
    else if Pos('--sim-net-stop-at=', Argument) = 1 then
      Simulation.NetStopAt := StrToInt(Copy(Argument, 19, MaxInt))
    // CHANGE: ENHANCEMENT - A client that goes silent, and one that joins again with its token
    // (docs/network.md, Tests).
    else if Pos('--sim-net-silent-at=', Argument) = 1 then
      Simulation.NetSilentAt := StrToInt(Copy(Argument, 21, MaxInt))
    else if Argument = '--sim-net-takeover' then
      Simulation.NetTakeover := True
    // CHANGE: ENHANCEMENT - A host that goes silent or vanishes, and a client's reconnect window
    // (docs/network.md, Tests).
    else if Pos('--sim-net-host-silent-at=', Argument) = 1 then
      Simulation.NetHostSilentAt := StrToInt(Copy(Argument, 26, MaxInt))
    else if Pos('--sim-net-host-exit-at=', Argument) = 1 then
      Simulation.NetHostExitAt := StrToInt(Copy(Argument, 24, MaxInt))
    else if Pos('--sim-net-reconnect-ms=', Argument) = 1 then
      Simulation.NetReconnectMs := StrToInt(Copy(Argument, 24, MaxInt))
    // CHANGE: ENHANCEMENT - A client's purchase of goods that the host's day sold first: the
    // host refuses it and tells the client (docs/network.md, Tests).
    else if Argument = '--sim-net-buy-race' then
      Simulation.NetBuyRace := True
    // CHANGE: ENHANCEMENT - Two humans share one shop's stock (HeadlessSim.RunSharedShop).
    else if Argument = '--sim-shared-shop' then
      Simulation.SharedShop := True
    // CHANGE: ENHANCEMENT - Two humans share one planet's storage (HeadlessSim.RunSharedStorage).
    else if Argument = '--sim-shared-storage' then
      Simulation.SharedStorage := True
    // CHANGE: ENHANCEMENT - The humans share the government quests (HeadlessSim.RunSharedQuests).
    else if Argument = '--sim-shared-quests' then
      Simulation.SharedQuests := True
    // CHANGE: ENHANCEMENT - The shared storage between networked humans (HeadlessNet).
    else if Argument = '--sim-net-storage' then
      Simulation.NetStorage := True
    // CHANGE: ENHANCEMENT - The shared quests between networked humans (HeadlessNet).
    else if Argument = '--sim-net-shared-quest' then
      Simulation.NetSharedQuest := True
    // CHANGE: ENHANCEMENT - Money transfers between networked humans (HeadlessNet).
    else if Argument = '--sim-net-transfer' then
      Simulation.NetTransfer := True
    // CHANGE: ENHANCEMENT - Script builtins act for the right human (HeadlessSim.RunScriptRouting).
    else if Argument = '--sim-script-routing' then
      Simulation.ScriptRouting := True
    // CHANGE: ENHANCEMENT - Commands from stale copies are refused (HeadlessSim.RunStaleCommands).
    else if Argument = '--sim-stale-commands' then
      Simulation.StaleCommands := True
    // CHANGE: ENHANCEMENT - A nested command reaches the host once (HeadlessNet).
    else if Argument = '--sim-net-nested' then
      Simulation.NetNested := True
    // CHANGE: ENHANCEMENT - Trades between humans at one planet (HeadlessNet).
    else if Argument = '--sim-net-shop' then
      Simulation.NetShop := True
    // CHANGE: ENHANCEMENT - A client takes its end turn back (HeadlessNet).
    else if Argument = '--sim-net-cancel-end-turn' then
      Simulation.NetCancelEndTurn := True
    // CHANGE: ENHANCEMENT - A text quest played headlessly (HeadlessSim.RunTextQuest).
    else if Pos('--sim-text-quest=', Argument) = 1 then
      Simulation.TextQuest := Copy(Argument, 18, MaxInt)
    // CHANGE: ENHANCEMENT - One human at a time plays a planet's quest (HeadlessSim.RunQuestLock).
    else if Argument = '--sim-quest-lock' then
      Simulation.QuestLock := True
    // CHANGE: ENHANCEMENT - A client plays a text quest in a networked session (HeadlessNet); a
    // replay of the host's log with the same flag knows the quest probe.
    else if Pos('--sim-net-quest=', Argument) = 1 then
      Simulation.NetQuestDay := StrToInt(Copy(Argument, 17, MaxInt))
    else if Pos('--sim-kill-human=', Argument) = 1 then
      Simulation.KillHumansAt := StrToInt(Copy(Argument, 18, MaxInt))
    else if Pos('--sim-reload-at=', Argument) = 1 then
      Simulation.ReloadAt := StrToInt(Copy(Argument, 17, MaxInt))
    else if Pos('--sim-dump=', Argument) = 1 then
      Simulation.DumpDirectory := ExpandFileName(Copy(Argument, 12, MaxInt))
    else if Argument = '--sim-hash' then
      Simulation.Hash := True
    else if Argument = '--sim-hash-last' then
    begin
      Simulation.Hash := True;
      Simulation.HashLastOnly := True
    end
    else if Argument = '--sim-roundtrip' then
      Simulation.RoundTrip := True
    // CHANGE: ENHANCEMENT - Poisoned frees (ROADMAP.md, Phase 5): a debug build fills freed
    // memory with a pattern and holds it back from reuse, so a stale reference fails at once.
    else if Argument = '--poison-frees' then
      PoisonQuarantineMB := DefaultPoisonQuarantineMB
    else if Pos('--poison-frees=', Argument) = 1 then
    begin
      PoisonQuarantineMB := StrToInt(Copy(Argument, 16, MaxInt));
      if PoisonQuarantineMB <= 0 then
        raise Exception.Create('--poison-frees takes a quarantine size in MB');
    end
    else if Pos('--game-dir=', Argument) = 1 then
      GameDirectory := Copy(Argument, 12, MaxInt)
    else if Pos('--user-dir=', Argument) = 1 then
      UserDirectory := Copy(Argument, 12, MaxInt)
    else if Pos('--language=', Argument) = 1 then
    begin
      SelectedLanguage := WideString(Copy(Argument, 12, MaxInt));
      ExplicitLanguage := True
    end
    else
      raise Exception.Create('Unknown argument: ' + Argument);
  end;
  // Installed before the game allocates anything else. Blocks allocated earlier are the wrapped
  // manager's too, so the wrapper frees them like its own.
  if PoisonQuarantineMB > 0 then
  begin
    if not PoisonFreesAvailable then
      raise Exception.Create('--poison-frees needs a debug build (tools/build.py without --release)');
    InstallPoisonFrees(PtrUInt(PoisonQuarantineMB) * 1024 * 1024);
  end;
  GameDirectory := ExpandFileName(GameDirectory);
  UserDirectory := ExcludeTrailingPathDelimiter(ExpandFileName(UserDirectory));
  if (CommandLineJoin <> '') and (CommandLineName = '') then
    raise Exception.Create('--join takes --name');
  if (CommandLineJoin <> '') and ((CommandLineHostPort >= 0) or (StartupSave <> '')) then
    raise Exception.Create('--join cannot be combined with --host or --load-save');
  if SimulationMode and ((CommandLineJoin <> '') or (CommandLineHostPort >= 0)) then
    raise Exception.Create('--host and --join are for the game; headless, use --sim-net-host and --sim-net-join');
  if SimulationMode then
  begin
    if ObserverMode then
      raise Exception.Create('--sim-save cannot be combined with the observer');
    if (Replay.LogPath <> '') and (Simulation.SavePath <> '') then
      raise Exception.Create('--replay-commands cannot be combined with --sim-save');
    if (RecordCommandsPath <> '') and (Replay.LogPath <> '') then
      raise Exception.Create('--record-commands cannot be combined with --replay-commands');
    if HotSeatHumans <> 0 then
      raise Exception.Create('--hotseat is for the game; headless, use --sim-humans and --sim-hotseat');
    if (Simulation.NetJoin <> '') and ((Simulation.SavePath <> '') or (Simulation.NetName = '')) then
      raise Exception.Create('--sim-net-join takes --sim-net-name and no --sim-save');
    if (Simulation.NetHostPort >= 0) and (Simulation.SavePath = '') then
      raise Exception.Create('--sim-net-host needs --sim-save');
    Replay.Seed := Simulation.Seed;
    GpuRendererRequested := False;
    sr_renderer_select(0);
    sr_set_headless(1)
  end
  else if (Simulation.Turns <> 0) or Simulation.Hash or Simulation.RoundTrip then
    raise Exception.Create('--sim-* options require --sim-save=/path/to/save.sav');
  if ObserverMode then
  begin
    GpuRendererRequested := True;
    sr_renderer_select(1)
  end;
  if not RTLFileSystem.FileExists(IncludeTrailingPathDelimiter(GameDirectory) + 'INSTALL.TXT') then
    raise Exception.Create('Game assets not found; use --game-dir=/path/to/game');
  if not SetCurrentDir(GameDirectory) then
    RaiseLastOSError;
  if not ForceDirectories(UserDirectory) then
    raise Exception.Create('Cannot create user directory: ' + UserDirectory);
  if not ExplicitLanguage and RTLFileSystem.FileExists(UserDirectory + '/Lang.txt') then
  begin
    LanguageFile := TStringList.Create;
    try
      LanguageFile.LoadFromFile(UserDirectory + '/Lang.txt');
      if LanguageFile.Values['Lang'] <> '' then
        SelectedLanguage := WideString(LanguageFile.Values['Lang']);
    finally
      LanguageFile.Free
    end;
  end;
  ForceDirectories(UserDirectory + '/Cache');
  ForceDirectories(UserDirectory + '/Save');
  OverrideGameUserDirectory := WideString(UserDirectory);
  CachedGameUserDirectory := '';
end;

procedure PrepareUserSettings;
var
  Settings: TBlockParEC;
  FileName: WideString;
{$IFDEF ANDROID}
  DisplayWidth, DisplayHeight, SwapSize: Integer;
{$ENDIF}
begin
  FileName := GetGameUserDirectory + 'CFG.TXT';
  Settings := TBlockParEC.Create;
  try
    if RTLFileSystem.FileExists(AnsiString(FileName)) then
      Settings.LoadFromTextFileWithEncodingProbe(PWideChar(FileName), True)
    else
    begin
      Settings.LoadFromTextFileWithEncodingProbe('CFG.TXT', True);
      Settings.SetOrAddParam('Window', 'True');
      Settings.SetOrAddParam('VideoMode', '1024,768');
    end;
{$IFDEF ANDROID}
    // Resolve the physical display before allocating the game render buffers.
    if sr_display_size(DisplayWidth, DisplayHeight) <> 0 then
    begin
      if DisplayWidth < DisplayHeight then
      begin
        SwapSize := DisplayWidth;
        DisplayWidth := DisplayHeight;
        DisplayHeight := SwapSize;
      end;
      // The recovered layouts require at least 1024x768.
      if DisplayWidth < 1024 then
        DisplayWidth := 1024;
      if DisplayHeight < 768 then
        DisplayHeight := 768;
      Settings.SetOrAddParam('VideoMode', IntToStr(DisplayWidth) + ',' + IntToStr(DisplayHeight));
      Log('Android render resolution: ' + IntToStr(DisplayWidth) + 'x' + IntToStr(DisplayHeight));
    end;
{$ENDIF}
    // Movie playback and recording are unavailable in the native runtime.
    Settings.SetOrAddParam('HardwareRender', 'False');
    Settings.SetOrAddParam('ShowSystemMouse', 'False');
    Settings.SetOrAddParam('SkipIntro', 'True');
    Settings.SetOrAddParam('SkipVideo', 'True');
    Settings.SetOrAddParam('FilmBufSize', '0');
    Settings.SetOrAddParam('FilmFPS', '20');
    Settings.SaveTextFile(PWideChar(FileName), True, False);
  finally
    Settings.Free;
  end;
end;

procedure InitializeScreens;
begin
  CampaignRuntimeStarted := True;
  InitializeGlobalUiRuntime;
end;

procedure RunScreens;
var
  NextScreen: TGameScreenId;
  Screen: TMessageLoopGI;
begin
  ScreenLoadMode := 0;
  PostLoadScreenId := screenMainMenu;
  if StartupSave <> '' then
  begin
    PendingLoadFileName := StartupSave;
    PostLoadScreenId := screenGameLoad;
  end;
  RequestedScreenId := screenLoad;
  while not ExitScreenLoop and (RequestedScreenId <> screenNone) do
  begin
    // CHANGE: ENHANCEMENT - Hot-seat: the next human's screen opens as that human's. A networked
    // game starts, joins and applies the host's state here.
    ApplyTurnPass;
    NetBetweenScreens;
    NextScreen := RequestedScreenId;
    if NextScreen = screenLoadRobot then
      raise Exception.Create('This port has robot battles disabled');

    if ObserverMode
        and (Galaxy <> nil)
        and (LocalPlayer <> nil)
        and (NextScreen
            in [
                screenStarMap,
                screenPlanet,
                screenPlanetNO,
                screenRuinsTalk,
                screenIntroduction]) then
    begin
      RunObserver('');
      Break
    end;

    Screen := TMessageLoopGI(RegisteredScreens[Ord(NextScreen)]);
    if Screen = nil then
      raise Exception.Create('Missing registered campaign screen');
    CurrentScreenId := NextScreen;
    RequestedScreenId := screenNone;
    Stage('run ' + AnsiString(Screen.RegisteredLoopName));
    if NextScreen in [screenArcadeBattle, screenStarMap, screenFilm] then
      Screen.RunContinuous
    else
      Screen.Run;
    if (NextScreen = screenSettings) and SettingsScreen.RestartRequested then
      RestartRequested := True;
    if ReloadModsRequested then
      RestartRequested := True;
    PreviousScreenId := NextScreen;
    CurrentScreenId := screenNone;
  end;
end;

procedure ReleaseObject(var Slot; const Name: AnsiString);
var
  Instance: TObject;
begin
  Instance := TObject(PPointer(@Slot)^);
  try
    try
      // Native child destructors still consult their owning global (Galaxy).
      Instance.Free;
    except
      on E: Exception do
      begin
        Log('Cleanup ' + Name + ': ' + E.ClassName + ': ' + E.Message);
        LogExceptionTrace;
        System.ExitCode := 1;
      end;
    end;
  finally
    PPointer(@Slot)^ := nil;
  end;
end;

procedure Shutdown;
begin
  Stage('shutdown');
  ExitScreenLoop := True;
  if Session.TurnCalculationThread <> nil then
  begin
    WaitForTurnCalculation;
    // Join the worker while the galaxy and script/UI owners are still alive.
    FreeAndNil(Session.TurnCalculationThread);
  end;
  // CHANGE: ENHANCEMENT - Say Bye to the peers while the humans are still there.
  try
    EndNetSession;
  except
    on E: Exception do
      Log('Network cleanup: ' + E.Message);
  end;
  if CampaignRuntimeStarted then
    try
      FinalizeGlobalUiRuntime
    except
      on E: Exception do
      begin
        Log('Campaign UI cleanup: ' + E.Message);
        System.ExitCode := 1
      end;
    end;
  ReleaseObject(Galaxy, 'galaxy');
  if ScriptRuntimeStarted then
    try
      FinalizeScriptHostRuntime
    except
      on E: Exception do
      begin
        Log('Script cleanup: ' + E.Message);
        System.ExitCode := 1
      end;
    end;
  ReleaseObject(AchievementDefinitions, 'achievement definitions');
  try
    FinalizeRuntimeAndSettings
  except
    on E: Exception do
    begin
      Log('Runtime cleanup: ' + E.Message);
      System.ExitCode := 1
    end;
  end;
  Direct3DDevice := nil;
  Direct3D := nil;
  ReleaseObject(Session.EditableSaveBlock, 'save configuration');
  ReleaseObject(NewGameSettingsConfig, 'new-game configuration');
  UiStyleConfig := nil;
  UiDepthConfig := nil;
  try
    FreeDatConfigRoots
  except
    on E: Exception do
    begin
      Log('Config cleanup: ' + E.Message);
      System.ExitCode := 1
    end;
  end;
  ReleaseObject(ModInstallConfigs, 'mod install list');
  ReleaseObject(ModLanguageInstallConfigs, 'mod language list');
  ReleaseObject(QuestMessages, 'quest messages');
  ReleaseObject(InstallConfig, 'install configuration');
  ReleaseObject(LanguageInstallConfig, 'language configuration');
  if PackageCollection <> nil then
    try
      FinalizePackageCollection
    except
      on E: Exception do
      begin
        Log('Package cleanup: ' + E.Message);
        System.ExitCode := 1
      end;
    end;
  ClipCursor(nil);
  ShowCursor(True);
  if MainWindowHandle <> 0 then
  begin
    KillTimer(MainWindowHandle, 1);
    DestroyWindow(MainWindowHandle);
    MainWindowHandle := 0;
  end;
  if PlatformReady then
    CoUninitialize;
  if TimerPeriodStarted then
    timeEndPeriod(1);
  Application.OnActivate := nil;
  Application.OnDeactivate := nil;
  ReleaseObject(ApplicationEvents, 'application events');
  // Every block still in the quarantine is checked for writes after it was freed.
  if PoisonFreesInstalled then
  begin
    FlushPoisonQuarantine;
    Log(PoisonFreesSummary);
    if SimulationMode and (PoisonFreesStats.WritesAfterFree > 0) then
      WriteLn(StdErr, PoisonFreesSummary);
  end;
  Log('Rangers: shutdown complete');
  LogReady := False;
  ReleaseObject(SessionLogLock, 'log lock');
end;

procedure RunRangers;
var
  ErrorText: AnsiString;
  RestartText: array[0..4] of AnsiString;
  RestartArgs: array[0..5] of PAnsiChar;
{$IFDEF MSWINDOWS}
  Restarter: TProcess;
{$ENDIF}
  I: Integer;
begin
  StartupStage := 'options and user directory';
  DecimalSeparator := '.';
  Randomize;
  MainRuntimeThreadId := GetCurrentThreadId;
  RuntimeStartupTick := timeGetTime;
  RuntimeActive := True;
  try
    try
      ReadOptions;
      CreateStartupLogFile;
      LogReady := True;
      Log('Game directory: ' + GameDirectory);
      Log('User directory: ' + UserDirectory);
      if PoisonFreesInstalled then
        Log('Poisoned frees: ' + IntToStr(PoisonQuarantineMB) + ' MB quarantine');
      Application.Initialize;
      ApplicationEvents := TAD.Create;
      Application.OnActivate := ApplicationEvents.ApplicationActivated;
      Application.OnDeactivate := ApplicationEvents.ApplicationDeactivated;
      // CHANGE: BUGFIX - Cheat codes (Ctrl+Shift and the code's letters) reach CheatCode again:
      // nothing set the callback, so no cheat worked, in single player or multiplayer.
      DebugKeyCallback := HandleDebugKey;
      RunningUnderWine := False;
      Stage('platform and window');
      InitializePlatformRuntimeAndMainWindow;
      PlatformReady := True;
      SetWindowTextA(MainWindowHandle, 'Rangers');
      Stage('language and packages');
      LoadLanguageAndPackages;
      Stage('stock DAT configuration');
      LoadDatConfigAndModOverrides;
      Stage('user settings');
      PrepareUserSettings;
      Stage('renderer, resources and audio');
      InitializeRuntimeAndSettings;
      if CacheInfoThumbnails then
        Log('Star info thumbnails: cached per turn')
      else
        Log('Star info thumbnails: cache disabled');
      if BuildVersionMismatch then
        raise Exception.Create('This build requires 2.1.2500 game data');
      GR_DXReset;
      ApplyGammaRamp(DisplayBrightness, DisplayContrast);
      Stage('campaign script runtime');
      ScriptRuntimeStarted := True;
      InitializeScriptHostRuntime;
      InitializeAchievementDefinitions;
      LoadLocalAchievements;
      AvailableLanguageCodes := CollectInstallLanguageCodes;
      if AvailableLanguageCodes = '' then
        AvailableLanguageCodes := SelectedLanguage;
      // CHANGE: ENHANCEMENT - The port's own texts fall back to Russian in a Russian game.
      PortTextRussian := WideCompareText(SelectedLanguage, 'russian') = 0;
      InitializeScreens;
      InstallSimEventHandlers;
      TimerPeriodStarted := timeBeginPeriod(1) = 0;
      if SimulationMode and (Replay.LogPath <> '') then
      begin
        Stage('command replay');
        if Simulation.NetTalkDay > 0 then
          InstallNetTalkProbe(Simulation.NetTalkDay);
        if Simulation.NetQuestDay > 0 then
          RegisterNetQuestProbe;
        if Simulation.NetSharedQuest then
          RegisterNetSharedQuestProbe;
        System.ExitCode := RunCommandReplay(Replay);
      end
      else if SimulationMode then
      begin
        Stage('headless simulation');
        // Recording a headless run tests the command log itself.
        if RecordCommandsPath <> '' then
          StartCommandRecording(RecordCommandsPath);
        if Simulation.NetJoin <> '' then
          System.ExitCode := RunNetClient(Simulation)
        else if Simulation.NetHostPort >= 0 then
          System.ExitCode := RunNetHost(Simulation)
        else
          System.ExitCode := RunHeadlessSimulation(Simulation);
        StopCommandRecording;
      end
      else if ObserverSave <> '' then
      begin
        Stage('galaxy observer');
        RunObserver(ObserverSave);
      end
      else
      begin
        if RecordCommandsPath <> '' then
          StartCommandRecording(RecordCommandsPath);
        RunScreens;
        StopCommandRecording;
      end;
      // Workers stop the screen loop; show their error on the main thread while
      // the window and SDL are still alive, before shutdown destroys them.
      RaisePendingWorkerError;
    except
      on E: Exception do
      begin
        System.ExitCode := 1;
        ErrorText := 'Stage: ' + StartupStage + #13#10 + E.ClassName + ': ' + E.Message;
        Log(ErrorText);
        // The original worker backtrace is already in the log.
        if not (E is EWorkerFailure) then
          LogExceptionTrace;
        if LogReady then
          ErrorText :=
              ErrorText + #13#10#13#10 + 'Log: ' + UserDirectory + '/' + RuntimeLogFileName;
        if SimulationMode then
          WriteLn(StdErr, ErrorText)
        else
          MessageBoxA(
              0,
              PAnsiChar(ErrorText),
              'Rangers startup/runtime error',
              MB_OK or MB_ICONERROR
          );
      end;
    end;
  finally
    Shutdown;
  end;
  if RestartRequested and (System.ExitCode = 0) then
  begin

{$IFNDEF ANDROID}
    RestartText[0] := ExecutablePath;
    RestartText[1] := '--game-dir=' + GameDirectory;
    RestartText[2] := '--user-dir=' + UserDirectory;
    RestartText[3] := '--language=' + UTF8Encode(SelectedLanguage);
    if GpuRendererRequested then
      RestartText[4] := '--renderer=sdl'
    else
      RestartText[4] := '--renderer=software';
{$IFDEF MSWINDOWS}
    // CHANGE: PORTABILITY - Windows has no exec; start a fresh process and let this one exit.
    Restarter := TProcess.Create(nil);
    try
      Restarter.Executable := ExecutablePath;
      for I := 1 to 4 do
        Restarter.Parameters.Add(RestartText[I]);
      Restarter.Execute;
    finally
      Restarter.Free
    end;
{$ELSE}
    for I := 0 to 4 do
      RestartArgs[I] := PAnsiChar(RestartText[I]);
    RestartArgs[5] := nil;
    fpExecV(PAnsiChar(ExecutablePath), @RestartArgs[0]);
    raise Exception.Create('Cannot restart game: ' + SysErrorMessage(fpGetErrNo));
{$ENDIF}
{$ENDIF}

  end;
end;

end.
