{$EXCESSPRECISION OFF}
unit NetPlay;
{$R-}
{$Q-}
{$B-}
{$A8}

// CHANGE: ENHANCEMENT - Networked play in the game's screens (ROADMAP.md, Phase 5;
// docs/network.md). --host=PORT hosts the running game; --join=HOST:PORT --name=NAME joins one.
// The network is pumped every frame (GR_Main.FramePumpHook) and while the UI thread waits for
// a job (aCalc.TurnWaitPumpHook). On the host, an end turn waits until every peer is ready,
// applies their commands and starts the day from the same screen, and the state goes out at
// the first quiet point after the day. A client never runs a day: its end turn sends EndTurn
// and waits; in space it plays the host's film of its star on the star map, and the state is
// applied between two screens, where the human's screen then opens. Without a session every
// function here does what the game did before.
interface
uses
  GI_MessageLoop,
  aEFilm,
  aGalaxy;
var
  // --host=PORT: hosts the game once one runs (0 picks a port); -1 without it.
  CommandLineHostPort: Integer = -1;
  // --join=HOST:PORT and --name=NAME; empty without them.
  CommandLineJoin: AnsiString;
  CommandLineName: AnsiString;

// The screen loop calls this between two screens, after the hot-seat pass: it starts hosting
// or joins as the command line asks, applies a client's state and chooses the screen that
// opens for it, and ends the session on the way to the main menu.
procedure NetBetweenScreens;
// Ends the session (Bye to the peers) and clears the hooks.
procedure EndNetSession;
// Ends the local human's turn (aPlayerActions.EndTurn) where a day starts. Without a session
// it is EndTurn. On a host it then waits, modal, until every peer is ready, applies their
// commands and begins the day; true when the day may start. On a client it sends EndTurn and
// waits, modal, for the host's day, and returns false: then either a film waits for the star
// map (ClientFilmWaiting) or Screen closes (NetScreenClosing).
function NetEndTurn(Screen: TMessageLoopGI): Boolean;
// Host: waits until every peer is ready (the last day's state goes first), applies their
// commands and begins the day. False when the local human still holds the day.
function HostDayMayStart: Boolean;
// Client: a film of the client's star waits to be played on the star map.
function ClientFilmWaiting: Boolean;
// Client: loads the waiting film into Film and binds its objects to the scene of Star,
// creating those the scene does not have, as the film history binds a preloaded film.
function TakeClientFilm(Film: TEFilm; Star: TStar): Boolean;
// Client: the film has ended on the star map. Waits for the state when it has not come, and
// closes Screen so that it is applied between screens.
procedure ClientFilmEnded(Screen: TMessageLoopGI; BreakRequested, CombatRecorded: Boolean);
// Client: the jump screen's tick. A state that arrived closes Screen to be applied.
procedure ClientTravelTick(Screen: TMessageLoopGI);
// Client: Screen has been asked to close for a state or for the main menu.
function NetScreenClosing: Boolean;
// What the main menu tells the player (a refusal, the host left); '' when nothing. Clears it.
function TakeNetNotice: WideString;
// WaitForMultipleObjects without a timeout; in a session a loop that pumps the network.
function NetWaitForEvents(Count: Cardinal; Handles: Pointer): Cardinal;
implementation
uses
  SysUtils,
  Classes,
  Windows,
  EC_Struct,
  GR_Main,
  Globals,
  GlobalsV,
  GI_Main,
  GI_MessageBox,
  SE_Process,
  SE_Space,
  aCalc,
  aConst,
  aHuman,
  aSession,
  aMyFunction,
  aAsteroid,
  aGalaxyStruct,
  aItem,
  aMissile,
  aPlanet,
  aPlayer,
  aPlayerActions,
  aShip,
  ThreadCalc,
  NetThread,
  NetProtocol,
  NetHost,
  NetClient,
  NetSession,
  HotSeat,
  fStarMap;

const
  // How often a wait in a session looks at the network.
  NetWaitMs = 10;
  // How long a join from the command line waits for the host's state.
  JoinTimeoutMs = 60000;
  // The wait box closes with this when its text has changed, and opens again with the new one.
  WaitRetext = 3;
  // The screens during which the host does not take joins, leaves or commands: no game, or one
  // being loaded, generated or saved in memory.
  NoGameScreens = [
      screenNone,
      screenMainMenu,
      screenLoad,
      screenGameLoad,
      screenNewGame,
      screenIntroduction,
      screenGameEnd,
      screenPlanetQuest,
      screenArcadeBattle,
      screenLoadRobot,
      screenLoadQuest,
      screenLoadArcade];

type
  TNetWaitKind = (nwHostPeers, nwClientDay, nwClientState);

  // A message box without buttons that closes by itself once what it waits for has come.
  TNetWaitBoxGI = class(TMessageBoxGI)
    Kind: TNetWaitKind;
    PollTimer: PCallbackTimerGI;
    procedure OnOpen; override;
    procedure OnClose; override;
    procedure Poll(Timer: PCallbackTimerGI; UserData: PtrInt);
  end;

var
  // State jobs sent by the host, freed once done.
  StateJobs: TList;
  // A film of the client's star, taken while the client waits for the day.
  PendingFilm: TNetClientFilm;
  // The star whose film the waiting client plays; -1 when it plays none.
  WantedFilmStar: Integer = -1;
  // The client's state waits to be applied between screens.
  ApplyPending: Boolean;
  // A film was played before the state (its end steps run on the new state), whether the
  // player broke it, and whether it showed the player in combat.
  AppliedAfterFilm, FilmBroken, FilmCombat: Boolean;
  ScreenClosing: Boolean;
  Notice: WideString;
  InPump: Boolean;

function MultiplayerText(const Key, English: WideString): WideString;
begin
  Result := LocalizedColorText('Multiplayer.' + Key);
  if Result = '' then
    Result := English;
end;

function NamedLine(const Key, English, Names: WideString): WideString;
begin
  Result := MultiplayerText(Key, English);
  ReplaceTextToken(Result, '<Players>', Names, '<color=255,240,100>');
end;

procedure AddName(var Names: WideString; const Name: WideString);
begin
  if Names <> '' then
    Names := Names + ', ';
  Names := Names + Name;
end;

function HumanName(Human: THuman): WideString;
begin
  if (Human <> nil) and (Human.Player <> nil) then
    Result := Human.Player.Name
  else
    Result := '?';
end;

// The humans the host's day waits for, and who is away.
function HostWaitText: WideString;
var
  Rest, Item, Names, Away: WideString;
  Position, I: Integer;
  Human: THuman;
begin
  Names := '';
  Rest := WideString(CurrentHost.WaitingFor);
  while Rest <> '' do
  begin
    Position := Pos(',', Rest);
    if Position = 0 then
      Position := Length(Rest) + 1;
    Item := Copy(Rest, 1, Position - 1);
    Delete(Rest, 1, Position);
    AddName(Names, HumanName(FindHuman(StrToIntDef(AnsiString(Item), -1))));
  end;
  Away := '';
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Human := Session.Humans[I];
    if not Human.Connected and (Human.Player <> nil) and not Human.Finished then
      AddName(Away, HumanName(Human));
  end;
  if Names = '' then
    Result := MultiplayerText('WaitingPlayers', 'Waiting for the players.')
  else
    Result := NamedLine('Waiting', 'Waiting for <Players>.', Names);
  if Away <> '' then
    Result := Result + #13#10 + NamedLine('Away', 'Away: <Players>.', Away);
end;

// Who the day waits for, as the host's status says.
function ClientWaitText: WideString;
var
  Client: TNetClient;
  Status: TStatusMessage;
  Names, Away: WideString;
  I: Integer;
begin
  Client := CurrentClient;
  Status := Client.Status;
  Names := '';
  Away := '';
  for I := 0 to High(Status.Humans) do
    if Status.Humans[I].Id <> Client.HumanId then
    begin
      if not Status.Humans[I].Connected then
        AddName(Away, Status.Humans[I].Name)
      else if Status.Humans[I].HoldsDay then
        AddName(Names, Status.Humans[I].Name);
    end;
  if Status.DayRunning then
    Result := MultiplayerText('DayRuns', 'The day is running.')
  else if Names <> '' then
    Result := NamedLine('Waiting', 'Waiting for <Players>.', Names)
  else
    Result := MultiplayerText('WaitingHost', 'Waiting for the host.');
  if Away <> '' then
    Result := Result + #13#10 + NamedLine('Away', 'Away: <Players>.', Away);
end;

// Takes the films that came: the one of the wanted star waits to be played, the rest go.
procedure CollectFilms;
var
  Film: TNetClientFilm;
begin
  repeat
    Film := CurrentClient.TakeFilm;
    if Film = nil then
      Break;
    if (PendingFilm = nil) and (WantedFilmStar >= 0) and (Film.Header.StarId = WantedFilmStar) then
      PendingFilm := Film
    else
      Film.Free;
  until False;
end;

procedure DropPendingFilm;
begin
  FreeAndNil(PendingFilm);
end;

function WaitDone(Kind: TNetWaitKind): Boolean;
var
  Client: TNetClient;
begin
  if ExitScreenLoop then
    Exit(True);
  case Kind of
    nwHostPeers:
      Result := (CurrentHost = nil) or CurrentHost.PeersReady;
    nwClientDay:
      begin
        Client := CurrentClient;
        if Client = nil then
          Exit(True);
        CollectFilms;
        Result := (PendingFilm <> nil) or Client.HasState or not Client.Connected;
      end;
  else
    Result := (CurrentClient = nil) or CurrentClient.HasState or not CurrentClient.Connected;
  end;
end;

function WaitText(Kind: TNetWaitKind): WideString;
begin
  if Kind = nwHostPeers then
    Result := HostWaitText
  else
    Result := ClientWaitText;
end;

// Pumps the network; on the host also frees the states sent and sends the state of a day that
// has run once the host is quiet after it.
procedure NetFrame; forward;

procedure TNetWaitBoxGI.OnOpen;
begin
  inherited OnOpen;
  PollTimer := ScheduleCallbackTimer(NetWaitMs * 2, NetWaitMs * 2, Poll);
end;

procedure TNetWaitBoxGI.OnClose;
begin
  if PollTimer <> nil then
  begin
    CancelCallbackTimer(PollTimer);
    PollTimer := nil;
  end;
  inherited OnClose;
end;

procedure TNetWaitBoxGI.Poll(Timer: PCallbackTimerGI; UserData: PtrInt);
begin
  if ExitCode <> 0 then
    Exit;
  NetFrame;
  if WaitDone(Kind) then
    RequestClose(mbgResultOK)
  else if WaitText(Kind) <> MessageText then
    RequestClose(WaitRetext);
end;

// ShowMessageBoxGI for a wait box, over the innermost screen.
function RunWaitBox(Kind: TNetWaitKind; const Text: WideString): Cardinal;
var
  Parent: TMessageLoopGI;
  Dialog: TNetWaitBoxGI;
  CursorState: TCursorStateGI;
begin
  Parent := GetInnermostScreenLoop;
  Parent.RootUiObject.NativeHook50;
  Parent.CaptureCursorState(@CursorState);
  Parent.SetCursorActive(False);
  Parent.DrawQueuedUpdateRects;
  Dialog := TNetWaitBoxGI.Create;
  Dialog.ParentLoop := Parent;
  Parent.ChildLoop := Dialog;
  Dialog.InitializeDefaults;
  try
    Dialog.MessageText := Text;
    Dialog.Options := 0;
    Dialog.Kind := Kind;
    Result := Dialog.Run;
    Parent.InvalidateViewport;
  finally
    Parent.ChildLoop := nil;
    Dialog.Free;
  end;
  Parent.RestoreCursorState(@CursorState);
  Parent.UpdateCursorPosition;
  Parent.RootUiObject.NativeHook48;
  if Result = 254 then
    BreakUiMessage;
end;

// Waits, modal over the open screen, until what Kind waits for has come or the window closes.
procedure WaitModal(Kind: TNetWaitKind);
begin
  NetFrame;
  while not WaitDone(Kind) do
    if RunWaitBox(Kind, WaitText(Kind)) <> WaitRetext then
      Break;
end;

procedure FreeSentStates;
var
  I: Integer;
begin
  if StateJobs = nil then
    Exit;
  for I := StateJobs.Count - 1 downto 0 do
    if TNetStateJob(StateJobs[I]).Done then
    begin
      TObject(StateJobs[I]).Free;
      StateJobs.Delete(I);
    end;
end;

// The state of the day that ran goes out, after any film of it not sent yet. A quiet point.
procedure HostSendDayState;
var
  Host: TNetHost;
begin
  Host := CurrentHost;
  if (Host = nil) or not Host.DayUnderWay then
    Exit;
  Host.SendFilms;
  if StateJobs = nil then
    StateJobs := TList.Create;
  StateJobs.Add(Host.SendState(False));
  NetLog(Format('state %d of day %d sent (%d ms)', [Host.LastSerial, Galaxy.CurrentTurn, Host.LastTakeMs]));
end;

// Whether the host may take joins, leaves and states now: a game is on the screen.
function HostMayTouchGame: Boolean;
begin
  Result := (Galaxy <> nil) and not MemorySnapshotActive and not (CurrentScreenId in NoGameScreens);
end;

// The quiet point after a day (docs/network.md, States): no job runs, and the next day is
// prepared, or the galaxy job has run and this screen does not prepare days. Only the star map
// prepares days (after its film), so there the state waits for the preparation.
function QuietAfterDay: Boolean;
begin
  Result :=
      not IsTurnCalculationRunning
          and ((TurnCalculationPhase = tcpPlayerStarPrepared)
              or ((TurnCalculationPhase = tcpGalaxyFinished) and (CurrentScreenId <> screenStarMap)));
end;

procedure NetFrame;
begin
  if InPump or (GetCurrentThreadId <> MainRuntimeThreadId) then
    Exit;
  InPump := True;
  try
    case NetRole of
      nrHost:
        begin
          FreeSentStates;
          if HostMayTouchGame then
          begin
            CurrentHost.Pump;
            if CurrentHost.DayUnderWay and QuietAfterDay then
              HostSendDayState;
          end;
        end;
      nrClient:
        CurrentClient.Pump;
    end;
  finally
    InPump := False;
  end;
end;

procedure BeginNetSession(AsClient: Boolean);
begin
  FramePumpHook := @NetFrame;
  TurnWaitPumpHook := @NetFrame;
  TurnJobsForbidden := AsClient;
end;

procedure EndNetSession;
var
  I: Integer;
begin
  FramePumpHook := nil;
  TurnWaitPumpHook := nil;
  TurnJobsForbidden := False;
  StopNetwork;
  // The network thread has stopped; the jobs it held can go.
  if StateJobs <> nil then
  begin
    for I := 0 to StateJobs.Count - 1 do
      TObject(StateJobs[I]).Free;
    FreeAndNil(StateJobs);
  end;
  DropPendingFilm;
  ApplyPending := False;
end;

// The client goes back to the main menu, which says Text. The session ends between screens.
procedure LeaveForMainMenu(Screen: TMessageLoopGI; const Text: WideString);
begin
  Notice := Text;
  NetLog('leaving the game: ' + UTF8Encode(Text));
  ApplyPending := False;
  DropPendingFilm;
  RequestedScreenId := screenMainMenu;
  if Screen <> nil then
  begin
    ScreenClosing := True;
    Screen.RequestClose(1);
  end;
end;

function ClientGoneText: WideString;
var
  Client: TNetClient;
begin
  Client := CurrentClient;
  if (Client <> nil) and Client.Refused then
    Result := MultiplayerText('Refused', 'The host refused to let you join:') + ' ' + Client.RefuseReason
  else if (Client <> nil) and (Client.Error <> '') then
    Result := MultiplayerText('Lost', 'The connection to the host is lost.') + #13#10 + WideString(Client.Error)
  else
    Result := MultiplayerText('HostLeft', 'The host has left the game.');
end;

// Closes Screen; its state is applied between screens (NetBetweenScreens).
procedure RequestApply(Screen: TMessageLoopGI; AfterFilm, Broken, Combat: Boolean);
begin
  ApplyPending := True;
  AppliedAfterFilm := AfterFilm;
  FilmBroken := Broken;
  FilmCombat := Combat;
  ScreenClosing := True;
  // A placeholder: NetBetweenScreens chooses the screen after the state.
  RequestedScreenId := screenStarMap;
  Screen.RequestClose(1);
end;

function HostDayMayStart: Boolean;
var
  Host: TNetHost;
begin
  Result := False;
  Host := CurrentHost;
  WaitForTurnCalculationUI;
  HostSendDayState;
  repeat
    WaitModal(nwHostPeers);
    if ExitScreenLoop then
      Exit;
    Host.ApplyQueues;
    if AllHumansEndedTurn then
    begin
      Host.BeginDay;
      Exit(True);
    end;
    if HumanHoldsDay(LocalHuman) then
      Exit;
  until False;
end;

procedure ClientWaitForDay(Screen: TMessageLoopGI);
var
  Client: TNetClient;
  P: TPlayer;
begin
  Client := CurrentClient;
  DropPendingFilm;
  P := LocalPlayer;
  // A film shows the human's own day: in space, or taking off.
  if (P <> nil) and (P.InNormalSpace or (P.Order = soTakeoff)) then
    WantedFilmStar := Integer(LocalHuman.PlayerStar.Id)
  else
    WantedFilmStar := -1;
  WaitModal(nwClientDay);
  WantedFilmStar := -1;
  if ExitScreenLoop then
    Exit;
  if PendingFilm <> nil then
  begin
    if Screen = StarMapScreen then
      Exit;
    // Taking off: the star map opens and plays it.
    StarMapScreen.ResumeMode := smrNetFilm;
    ScreenLoadMode := 2;
    PostLoadScreenId := screenStarMap;
    RequestedScreenId := screenLoad;
    ScreenClosing := True;
    Screen.RequestClose(1);
  end
  else if Client.HasState then
    RequestApply(Screen, False, False, False)
  else
    LeaveForMainMenu(Screen, ClientGoneText);
end;

function NetEndTurn(Screen: TMessageLoopGI): Boolean;
begin
  case NetRole of
    nrHost:
      begin
        EndTurn(False);
        Result := HostDayMayStart;
      end;
    nrClient:
      begin
        EndTurn(False);
        ClientWaitForDay(Screen);
        Result := False;
      end;
  else
    Result := EndTurn(False);
  end;
end;

function ClientFilmWaiting: Boolean;
begin
  Result := (NetRole = nrClient) and (PendingFilm <> nil);
end;

function NetScreenClosing: Boolean;
begin
  Result := ScreenClosing;
end;

function TakeNetNotice: WideString;
begin
  Result := Notice;
  Notice := '';
end;

// Binding a film to the star map's scene -----------------------------------------------------

type
  TSceneCandidate = record
    Id: Cardinal;
    SceneObject: TObjectSE;
    Used: Boolean;
  end;
  TSceneCandidates = array of TSceneCandidate;

procedure AddCandidate(var Candidates: TSceneCandidates; Id: Cardinal; SceneObject: TObjectSE);
var
  I: Integer;
begin
  if SceneObject = nil then
    Exit;
  I := Length(Candidates);
  SetLength(Candidates, I + 1);
  Candidates[I].Id := Id;
  Candidates[I].SceneObject := SceneObject;
  Candidates[I].Used := False;
end;

// The scene objects the star map shows for Star (StarScene.OpenSpaceScene), by the ids a film
// names them with. Jump gates have none (0).
function CollectSceneCandidates(Star: TStar): TSceneCandidates;
var
  I, J: Integer;
  Planet: TPlanet;
  Hole: THole;
begin
  Result := nil;
  AddCandidate(Result, Star.Id, Star.Graphic);
  for I := 0 to Star.Planets.Count - 1 do
  begin
    Planet := TPlanet(Star.Planets[I]);
    AddCandidate(Result, Planet.Id, Planet.Graphic);
    for J := 0 to Planet.Satellites.Count - 1 do
      AddCandidate(Result, TSputnik(Planet.Satellites[J]).Id, TSputnik(Planet.Satellites[J]).Graphic);
  end;
  for I := 0 to Star.Asteroids.Count - 1 do
    AddCandidate(Result, TAsteroid(Star.Asteroids[I]).Id, TAsteroid(Star.Asteroids[I]).GraphObject);
  for I := 0 to Star.Ships.Count - 1 do
    AddCandidate(Result, Cardinal(TShip(Star.Ships[I]).Id), TShip(Star.Ships[I]).Graphic);
  for I := 0 to Star.Items.Count - 1 do
    AddCandidate(Result, Cardinal(TItem(Star.Items[I]).Id), TItem(Star.Items[I]).GetGraphObject);
  for I := 0 to Star.Missiles.Count - 1 do
    AddCandidate(Result, TMissile(Star.Missiles[I]).Id, TMissile(Star.Missiles[I]).GetGraphObject);
  for I := 0 to Galaxy.Holes.Count - 1 do
  begin
    Hole := THole(Galaxy.Holes[I]);
    if (Hole.Star1 = Star) or (Hole.Star2 = Star) then
      AddCandidate(Result, Hole.Id, Hole.Graphic);
  end;
  for I := 0 to Galaxy.JumpGates.Count - 1 do
  begin
    AddCandidate(Result, 0, PJumpGateEntry(Galaxy.JumpGates[I]).Gate);
    AddCandidate(Result, 0, PJumpGateEntry(Galaxy.JumpGates[I]).Effect);
  end;
end;

function FindCandidate(var Candidates: TSceneCandidates; Obj: TEFilmObj): TObjectSE;
var
  I: Integer;
begin
  for I := 0 to High(Candidates) do
    with Candidates[I] do
      if not Used
          and (Id = Obj.ObjectId)
          and (SceneObject.GraphKey = Obj.GraphKey)
          and (ClassSEtoName(SceneObject) = Obj.KindName) then
      begin
        Used := True;
        Exit(SceneObject);
      end;
  Result := nil;
end;

// The film's objects bind to the scene objects of Star's galaxy objects by kind, graphics key
// and id; the rest (effects, weapons, ships that came that day) are created, as the film
// history creates a stored film's objects (fFilm.CreateFilmSceneObjects).
procedure BindFilmToScene(Film: TEFilm; Star: TStar);
var
  Candidates: TSceneCandidates;
  Obj: TEFilmObj;
  Found: TObjectSE;
begin
  Candidates := CollectSceneCandidates(Star);
  Obj := Film.FirstObject;
  while Obj <> nil do
  begin
    if Obj.SceneObject = nil then
    begin
      Found := FindCandidate(Candidates, Obj);
      if Found <> nil then
        RetainSpaceObject(Obj.SceneObject, Found)
      else
        RetainSpaceObject(
            Obj.SceneObject,
            CreateSpaceObjectByName(Obj.KindName, Obj.GraphKey, Classes.Point(0, 0))
        );
    end;
    Obj := Obj.Next;
  end;
end;

function TakeClientFilm(Film: TEFilm; Star: TStar): Boolean;
begin
  Result := (NetRole = nrClient) and (PendingFilm <> nil) and (Star <> nil);
  if not Result then
    Exit;
  try
    Film.LoadFromBuffer(PendingFilm.Bytes);
  finally
    DropPendingFilm;
  end;
  BindFilmToScene(Film, Star);
end;

procedure ClientFilmEnded(Screen: TMessageLoopGI; BreakRequested, CombatRecorded: Boolean);
begin
  WaitModal(nwClientState);
  if ExitScreenLoop then
    Exit;
  if (CurrentClient <> nil) and CurrentClient.HasState then
    RequestApply(Screen, True, BreakRequested, CombatRecorded)
  else
    LeaveForMainMenu(Screen, ClientGoneText);
end;

procedure ClientTravelTick(Screen: TMessageLoopGI);
begin
  if ScreenClosing or (Screen.ExitCode <> 0) then
    Exit;
  NetFrame;
  // Films of the days in hyperspace are not shown (docs/network.md, Films).
  DropPendingFilm;
  CollectFilms;
  if CurrentClient.HasState then
    RequestApply(Screen, False, False, False)
  else if not CurrentClient.Connected then
    LeaveForMainMenu(Screen, ClientGoneText);
end;

function NetWaitForEvents(Count: Cardinal; Handles: Pointer): Cardinal;
begin
  if NetRole = nrNone then
    Exit(WaitForMultipleObjects(Count, Handles, False, INFINITE));
  repeat
    Result := WaitForMultipleObjects(Count, Handles, False, NetWaitMs);
    if Result <> WAIT_TIMEOUT then
      Exit;
    NetFrame;
  until False;
end;

// Between screens ------------------------------------------------------------------------------

// The screen of the client's human after a state: the film's end steps run first, on the new
// state, as the star map runs them after a film (landing wear, a black hole's scripts); the
// commands go to the host with the next day's.
procedure OpenClientScreen(NewStar: Boolean);
var
  P: TPlayer;
  Continues: Boolean;
begin
  P := LocalPlayer;
  if P.InHyperspace then
  begin
    if AppliedAfterFilm and (P.Order = soJumpHole) then
      RunScriptTurns;
    RequestedScreenId := screenJump;
  end
  else if P.CurrentPlanet <> nil then
  begin
    if AppliedAfterFilm and not LocalHuman.PlayerAutomaticControl then
      ApplyLandingWear;
    if P.CurrentPlanet.OwnerId = Byte(oiUninhabited) then
      RequestedScreenId := screenPlanetNO
    else
      RequestedScreenId := screenPlanet;
  end
  else if P.DockedTo <> nil then
    RequestedScreenId := screenRuinsTalk
  else
  begin
    // Travel that goes on ends the next day's turn by itself, as the star map's automatic
    // continue does, until the film shows a fight or the player breaks it.
    Continues :=
        AppliedAfterFilm and not FilmBroken and not FilmCombat and HumanTravelContinues(LocalHuman);
    SpaceViewPosition := P.Position;
    StarMapScreen.SetMapCenterManually(TruncatePointF(P.Position));
    StarMapScreen.ResumeMode := smrNormal;
    StarMapScreen.NetEndTurnAfterOpen := Continues;
    if NewStar then
    begin
      // The new star's images load first, as after a takeoff.
      ScreenLoadMode := 2;
      PostLoadScreenId := screenStarMap;
      RequestedScreenId := screenLoad;
    end
    else
      RequestedScreenId := screenStarMap;
  end;
  AppliedAfterFilm := False;
end;

// Applies the state that waits, between two screens: the galaxy is loaded again, the client's
// human is the local one, and its screen opens.
procedure ApplyClientState;
var
  Client: TNetClient;
  OldStarId: Int64;
  Background: array of TSpaceBackgroundEntry;
  Report: TNetApplyReport;
  Star: TStar;
  I: Integer;
begin
  ApplyPending := False;
  Client := CurrentClient;
  if (Client = nil) or not Client.HasState then
  begin
    LeaveForMainMenu(nil, ClientGoneText);
    Exit;
  end;
  OldStarId := -1;
  Background := nil;
  if (Galaxy <> nil) and (LocalHuman.PlayerStar <> nil) then
  begin
    OldStarId := LocalHuman.PlayerStar.Id;
    SetLength(Background, Length(Galaxy.SpaceBackgroundEntries));
    for I := 0 to High(Background) do
      Background[I] := Galaxy.SpaceBackgroundEntries[I];
  end;
  DropPendingFilm;
  CollectFilms;
  PendingHuman := nil;
  try
    Report := Client.ApplyState;
  except
    on E: Exception do
    begin
      NetLog('cannot apply the state: ' + E.Message);
      LeaveForMainMenu(nil, WideString(E.Message));
      Exit;
    end;
  end;
  NetLog(
      Format(
          'applied state %d of day %d as human %d (%d bytes, %d received, %d ms)%s',
          [Report.Serial, Report.Day, Client.HumanId, Report.StateBytes, Report.ReceivedBytes,
              Report.LoadMs, BoolToStr(Report.Hash <> Report.HostHash, ', desync', '')]
      )
  );
  // The state holds the space background of the host's screen; the client keeps its own.
  Star := LocalHuman.PlayerStar;
  if (Star <> nil) and (Star.Id = OldStarId) then
  begin
    SetLength(Galaxy.SpaceBackgroundEntries, Length(Background));
    for I := 0 to High(Background) do
      Galaxy.SpaceBackgroundEntries[I] := Background[I];
  end
  else if Star <> nil then
    Galaxy.GenerateSpaceBackground(Star.BackgroundImage);
  OpenClientScreen((Star = nil) or (Star.Id <> OldStarId));
end;

procedure JoinFromCommandLine;
var
  Colon, Port: Integer;
  Client: TNetClient;
  Deadline: QWord;
begin
  Colon := LastDelimiter(':', CommandLineJoin);
  Port := StrToIntDef(Copy(CommandLineJoin, Colon + 1, MaxInt), -1);
  if (Colon <= 1) or (Port <= 0) then
  begin
    Notice := WideString('--join=' + CommandLineJoin + ': expected HOST:PORT');
    CommandLineJoin := '';
    Exit;
  end;
  Client := JoinGame(Copy(CommandLineJoin, 1, Colon - 1), Port, WideString(CommandLineName));
  CommandLineJoin := '';
  BeginNetSession(True);
  Deadline := GetTickCount64 + JoinTimeoutMs;
  while Client.Connected and not Client.HasState and not ExitScreenLoop do
  begin
    if GetTickCount64 > Deadline then
    begin
      Notice := MultiplayerText('NoState', 'The host did not send the game.');
      EndNetSession;
      Exit;
    end;
    // Keeps the window answering; the frame hook pumps the network.
    GR_WinMessage(nil);
    NetInboxEvent.WaitFor(NetWaitMs);
  end;
  if ExitScreenLoop then
    Exit;
  if not Client.HasState then
  begin
    Notice := ClientGoneText;
    EndNetSession;
    Exit;
  end;
  NetLog(Format('joined %s as human %d', [UTF8Encode(Client.HostName), Client.HumanId]));
  ApplyClientState;
end;

procedure StartHostingGame;
var
  Host: TNetHost;
begin
  WaitForTurnCalculation;
  Host := StartHosting(CommandLineHostPort, LocalPlayer.Name);
  CommandLineHostPort := -1;
  BeginNetSession(False);
  NetLog(Format('hosting on port %d as %s', [Host.Thread.ListenPort, UTF8Encode(LocalPlayer.Name)]));
end;

procedure NetBetweenScreens;
begin
  ScreenClosing := False;
  if ApplyPending then
    ApplyClientState;
  if (RequestedScreenId = screenMainMenu) and (NetRole <> nrNone) then
    EndNetSession;
  if (CommandLineJoin <> '') and (RequestedScreenId = screenMainMenu) then
  begin
    JoinFromCommandLine;
    if (RequestedScreenId = screenMainMenu) and (NetRole <> nrNone) then
      EndNetSession;
  end;
  // Hosting from the command line starts at the first screen of a game.
  if (CommandLineHostPort >= 0)
      and (Galaxy <> nil)
      and (LocalPlayer <> nil)
      and not (RequestedScreenId in NoGameScreens) then
    StartHostingGame;
end;

end.
