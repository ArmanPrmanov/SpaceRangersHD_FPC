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
// applied between two screens, where the human's screen then opens. A dialogue the host's day
// asks the client's human opens over the waiting star map. Without a session every function
// here does what the game did before.
// CHANGE: ENHANCEMENT - Text quests in a session (docs/progress/2026-10-19-text-quests-plan.md,
// Phase C): a game's quest screen is a game screen, the waits name a human in a quest or busy
// with its days, the quest's own day ends with an EndTurn the host waits for, the planet screens
// end owed days by themselves, and a reconnect abandons the quest that plays.
interface
uses
  GI_MessageLoop,
  aEFilm,
  aGalaxy,
  aHuman;
var
  // --host=PORT: hosts the game once one runs (0 picks a port); -1 without it.
  CommandLineHostPort: Integer = -1;
  // --join=HOST:PORT and --name=NAME; empty without them.
  CommandLineJoin: AnsiString;
  CommandLineName: AnsiString;

const
  // CHANGE: ENHANCEMENT - The port the menus propose, and the one an address without a port
  // (--join=HOST, the main menu's join) connects to.
  DefaultNetPort = 47300;
  // CHANGE: ENHANCEMENT - How often a screen looks at what the network changed under it (the
  // planet screens' text quest prompt and owed quest days, NetQuestDayDue).
  NetScreenPollMs = 250;

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
// CHANGE: ENHANCEMENT - What the menus call (NetMenus; docs/network.md, Hosting and joining).
// The language data's Multiplayer.Key, or English when it has none.
function MultiplayerText(const Key, English: WideString): WideString;
// Splits HOST or HOST:PORT; a missing port is DefaultNetPort. False when it is malformed.
function ParseNetAddress(const Text: AnsiString; out Host: AnsiString; out Port: Integer): Boolean;
// Asks to join Address (HOST or HOST:PORT) as Name, as --join does; RunPendingJoin joins.
procedure RequestJoin(const Address: AnsiString; const Name: WideString);
// CHANGE: ENHANCEMENT - The join RequestJoin asked for, over Screen (the main menu): a box shows
// its progress (connecting, waiting for the host, the bytes of the state received) with a
// Cancel that stays on Screen. When the state has come, Screen closes and the state is applied
// between screens; a failure says why over Screen.
procedure RunPendingJoin(Screen: TMessageLoopGI);
// CHANGE: ENHANCEMENT - A first join chooses its character (docs/network.md, Joining): when the
// host asks, the join's box closes and the new-game screen opens without its difficulty
// (TfGameSettings2). True while it is open for that.
function NetCharacterScreen: Boolean;
// The name the join gave, which the screen proposes.
function NetJoinName: WideString;
// The screen's choice goes to the host, and the join goes on over the main menu.
procedure SendNetCharacter(const Name: WideString; const Character: TJoinCharacter);
// The screen was cancelled: the join ends on the way to the main menu.
procedure CancelNetCharacter;
// Why the running game cannot be hosted from the in-game menu now; '' when it can.
function HostingRefusal: WideString;
// Hosts the running game on Port (0 picks one), as --host does; returns the port it listens on.
// Raises when it cannot listen.
function HostRunningGame(Port: Integer): Integer;
// Stops hosting: the peers' humans are disconnected (their rangers hold position), the peers
// get Bye, and the game goes on without a session.
procedure StopHostingGame;
// The host's state for the in-game menu: port, addresses, who is connected.
function HostStatusText: WideString;
// The humans connected to this host (not the host's own), by name; '' when none.
function ConnectedPlayerNames: WideString;
// CHANGE: ENHANCEMENT - Text quests in a session (docs/progress/2026-10-19-text-quests-plan.md,
// The day): whether the local human owes days for a text quest, so that its planet screen ends
// its turns by itself (NetEndTurn), as the star map's automatic continue does: the host's own
// starts the next day once its peers are ready, a client's ends the quest's own day and then
// waits for each state.
function NetQuestDayDue: Boolean;
// What a wait for the day says (the host's, and a client's from the host's status); the tests
// print them (HeadlessNet).
function HostWaitText: WideString;
function ClientWaitText: WideString;
// CHANGE: ENHANCEMENT - What the planet screens say about a planet's text quest that another
// human plays (aQuestActions.TextQuestHolder): '<Player> is playing this quest.'
function TextQuestTakenText(Holder: THuman): WideString;
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
  aCommands,
  ThreadCalc,
  NetThread,
  NetProtocol,
  NetTransport,
  NetHost,
  NetClient,
  NetSession,
  HotSeat,
  fPlanetQuest,
  fStarMap;

const
  // How often a wait in a session looks at the network.
  NetWaitMs = 10;
  // How long a join waits without progress (a phase, or bytes of the state) before it gives up.
  JoinTimeoutMs = 60000;
  // CHANGE: ENHANCEMENT - The join's box shows new progress at most this often.
  JoinRetextMs = 500;
  // The screens a client that lost its host leaves for the main menu from: those that start a
  // day, which already leave that way (LeaveForMainMenu). Not a shop, the ship or another
  // screen that moves goods on closing.
  LostHostLeaveScreens = [
      screenStarMap,
      screenPlanet,
      screenPlanetNO,
      screenRuinsTalk,
      screenHangar,
      screenJump];
  // The wait box closes with this when its text has changed, and opens again with the new one.
  WaitRetext = 3;
  // The screens during which the host does not take joins, leaves or commands: no game, or one
  // being loaded, generated or saved in memory. CHANGE: ENHANCEMENT - Not the quest screen of a
  // game (NoGameScreen; docs/progress/2026-10-19-text-quests-plan.md, The day): the quest is
  // not in the galaxy, and the screen pumps as any game screen.
  NoGameScreens = [
      screenNone,
      screenMainMenu,
      screenLoad,
      screenGameLoad,
      screenNewGame,
      screenIntroduction,
      screenGameEnd,
      screenArcadeBattle,
      screenLoadRobot,
      screenLoadQuest,
      screenLoadArcade];

type
  // CHANGE: ENHANCEMENT - nwHostTalk: the host's day waits for a remote human's answer to a
  // dialogue; nwJoin: a join waits for the host's state. CHANGE: ENHANCEMENT - nwReconnect: a
  // client that lost its host waits for the reconnect, outside a wait for the day.
  TNetWaitKind = (nwHostPeers, nwClientDay, nwClientState, nwHostTalk, nwJoin, nwReconnect);
  // CHANGE: ENHANCEMENT - What a wait's Cancel does: nothing (no Cancel), end the reconnect, or
  // take the local human's end turn back (docs/network.md, Waiting).
  TNetWaitCancel = (nwcNone, nwcReconnect, nwcEndTurn);

  // A message box without buttons (a join's has Cancel) that closes by itself once what it
  // waits for has come.
  TNetWaitBoxGI = class(TMessageBoxGI)
    Kind: TNetWaitKind;
    PollTimer: PCallbackTimerGI;
    OpenedAt: QWord;
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
  // CHANGE: ENHANCEMENT - A client's wait for the host's day is open (WaitModal): a dialogue
  // the host asks can be shown there. Outside one, the client declines it at once, unless it
  // plays its film (ClientFilmPlaying): then the dialogue waits for the film's end, where the
  // wait for the state answers it.
  ClientTalkWaits: Integer;
  // CHANGE: ENHANCEMENT - The star map plays the host's film (TakeClientFilm .. ClientFilmEnded).
  ClientFilmPlaying: Boolean;
  // A client has applied its first state: from then on, losing the host sends it to the main
  // menu at the next safe screen (NetFrame).
  ClientInGame: Boolean;
  HostLossLogged: Boolean;
  // The host's box for a remote dialogue is open (HostTalkWait).
  HostTalkBoxOpen: Boolean;
  // CHANGE: ENHANCEMENT - The client's box for a reconnect is open (ClientReconnectWait); the
  // state after the reconnect has been asked to be applied (ApplyRejoinState), logged once.
  ReconnectBoxOpen: Boolean;
  RejoinApplyLogged: Boolean;
  // CHANGE: ENHANCEMENT - The reconnect abandoned the text quest the human played (ApplyRejoinState);
  // the next state's screen tells it.
  QuestAbandonedNotice: Boolean;
  // CHANGE: ENHANCEMENT - A client's Cancel asked the host to stop its continuing travel
  // (docs/network.md, Continuing travel): until the host has applied it, or the next state has
  // been applied, where the travel stops here too (OpenClientScreen).
  ClientStopRequested: Boolean;
  // CHANGE: ENHANCEMENT - The network is pumped from the message loop between two of its
  // messages (FramePumpHook), not from a wait inside a handler; the host's end turn waits for
  // its peers (WaitModal nwHostPeers), where it applies their queues anyway (MayChangeUnderScreen).
  InFramePump: Boolean;
  HostPeersWaitOpen: Boolean;
  // The join's progress: when it last changed, and what it was.
  JoinProgressAt: QWord;
  JoinProgressMark: Int64;
  JoinAddressText: WideString;

function MultiplayerText(const Key, English: WideString): WideString;
begin
  Result := LocalizedColorText('Multiplayer.' + Key);
  if Result = '' then
    Result := English;
end;

// CHANGE: ENHANCEMENT - Whether the screen Id holds no game the network may touch
// (NoGameScreens): the quest screen only when it runs the main menu's quest.
function NoGameScreen(Id: TGameScreenId): Boolean;
begin
  Result :=
      (Id in NoGameScreens)
          or ((Id = screenPlanetQuest)
              and ((Galaxy = nil) or (LocalPlayer = nil) or StandaloneQuestMode));
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

// CHANGE: ENHANCEMENT - A human the day waits for, as the waits name it: one who plays a text
// quest says so (docs/progress/2026-10-19-text-quests-plan.md, The day).
function WaitName(const Name: WideString; Activity: TStatusActivity): WideString;
begin
  Result := Name;
  if Activity = saInTextQuest then
    Result := Result + ' ' + MultiplayerText('InTextQuest', '(text quest)');
end;

// CHANGE: ENHANCEMENT - A line of a wait for a human who owes Days for a text quest: the day does
// not wait for it meanwhile.
function QuestBusyLine(const Name: WideString; Days: Integer): WideString;
begin
  Result :=
      NamedLine('QuestBusy', '<Players> is busy with a text quest for <Days> more days.', Name);
  ReplaceTextToken(Result, '<Days>', WideString(IntToStr(Days)), '<color=255,240,100>');
end;

function TextQuestTakenText(Holder: THuman): WideString;
begin
  Result := NamedLine('QuestTaken', '<Players> is playing this quest.', HumanName(Holder));
end;

// The humans the host's day waits for, and who is away.
function HostWaitText: WideString;
var
  Rest, Item, Names, Away, Busy: WideString;
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
    Human := FindHuman(StrToIntDef(AnsiString(Item), -1));
    if Human <> nil then
      AddName(Names, WaitName(HumanName(Human), HumanQuestActivity(Human)))
    else
      AddName(Names, HumanName(Human));
  end;
  Away := '';
  Busy := '';
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Human := Session.Humans[I];
    if not Human.Connected and (Human.Player <> nil) and not Human.Finished then
      AddName(Away, HumanName(Human))
    else if (Human <> LocalHuman)
        and (HumanQuestActivity(Human) = saQuestDays)
        and (Human.Player <> nil) then
      Busy := Busy + #13#10 + QuestBusyLine(HumanName(Human), Human.QuestDaysOwed);
  end;
  if Names = '' then
    Result := MultiplayerText('WaitingPlayers', 'Waiting for the players.')
  else
    Result := NamedLine('Waiting', 'Waiting for <Players>.', Names);
  Result := Result + Busy;
  if Away <> '' then
    Result := Result + #13#10 + NamedLine('Away', 'Away: <Players>.', Away);
end;

// Who the day waits for, as the host's status says.
function ClientWaitText: WideString;
var
  Client: TNetClient;
  Status: TStatusMessage;
  Names, Away, Talker, Busy: WideString;
  I: Integer;
begin
  Client := CurrentClient;
  Status := Client.Status;
  Names := '';
  Away := '';
  Busy := '';
  for I := 0 to High(Status.Humans) do
    if Status.Humans[I].Id <> Client.HumanId then
    begin
      if not Status.Humans[I].Connected then
        AddName(Away, Status.Humans[I].Name)
      else if Status.Humans[I].HoldsDay then
        AddName(Names, WaitName(Status.Humans[I].Name, Status.Humans[I].Activity))
      // CHANGE: ENHANCEMENT - The day does not wait for a human busy with a quest's days.
      else if Status.Humans[I].Activity = saQuestDays then
        Busy := Busy + #13#10 + QuestBusyLine(Status.Humans[I].Name, Status.Humans[I].QuestDays);
    end;
  Talker := '';
  for I := 0 to High(Status.Humans) do
    if (Status.TalkHumanId <> 0) and (Status.Humans[I].Id = Status.TalkHumanId) then
      Talker := Status.Humans[I].Name;
  // CHANGE: ENHANCEMENT - The day waits for another human's answer to a hail (Status).
  if Status.DayRunning and (Talker <> '') and (Status.TalkHumanId <> Client.HumanId) then
    Result := NamedLine('WaitingTalk', 'Waiting for <Players> to answer a hail.', Talker)
  else if Status.DayRunning then
    Result := MultiplayerText('DayRuns', 'The day is running.')
  else if Names <> '' then
    Result := NamedLine('Waiting', 'Waiting for <Players>.', Names)
  else
    Result := MultiplayerText('WaitingHost', 'Waiting for the host.');
  Result := Result + Busy;
  if Away <> '' then
    Result := Result + #13#10 + NamedLine('Away', 'Away: <Players>.', Away);
end;

// CHANGE: ENHANCEMENT - Whose answer to a dialogue the host's day waits for.
function HostTalkText: WideString;
begin
  Result :=
      NamedLine(
          'WaitingTalk',
          'Waiting for <Players> to answer a hail.',
          HumanName(FindHuman(CurrentHost.TalkHumanId))
      );
end;

// CHANGE: ENHANCEMENT - The client reconnects to its host (docs/network.md, Disconnects), with
// the seconds it may still try.
function ReconnectText: WideString;
var
  Seconds: Integer;
begin
  Seconds := (CurrentClient.ReconnectRemainingMs + 999) div 1000;
  Result :=
      MultiplayerText(
          'Reconnecting',
          'The connection to the host is lost. Reconnecting... (<Seconds> s)'
      );
  ReplaceTextToken(Result, '<Seconds>', WideString(IntToStr(Seconds)), '<color=255,240,100>');
end;

// CHANGE: ENHANCEMENT - A client's wait shows the reconnect instead while there is one.
function ClientReconnecting: Boolean;
begin
  Result := (NetRole = nrClient) and CurrentClient.Reconnecting;
end;

function KilobytesText(Bytes: Integer): WideString;
begin
  Result := WideString(IntToStr((Bytes + 1023) div 1024)) + ' KB';
end;

// CHANGE: ENHANCEMENT - How far the join has come.
function JoinWaitText: WideString;
var
  Client: TNetClient;
  Have, Size: Integer;
begin
  Client := CurrentClient;
  case Client.JoinPhase of
    jpConnecting:
      Result := NamedLine('JoinConnecting', 'Connecting to <Players>.', JoinAddressText);
    jpJoining, jpCharacter:
      Result := MultiplayerText('JoinWaiting', 'Connected. Waiting for the host to let you in.');
  else
    begin
      Client.ReceiveProgress(Have, Size);
      if Size > 0 then
        Result :=
            NamedLine(
                'JoinReceiving',
                'Receiving the game: <Players>.',
                KilobytesText(Have) + ' / ' + KilobytesText(Size)
            )
      else
        Result := MultiplayerText('JoinReceivingStart', 'The host let you in. Receiving the game.');
    end;
  end;
end;

// Whether the join has made no progress (a phase, or bytes of the state) for JoinTimeoutMs.
function JoinStalled: Boolean;
var
  Have, Size: Integer;
  Mark: Int64;
begin
  CurrentClient.ReceiveProgress(Have, Size);
  Mark := Int64(Ord(CurrentClient.JoinPhase)) shl 40 + Have;
  if Mark <> JoinProgressMark then
  begin
    JoinProgressMark := Mark;
    JoinProgressAt := GetTickCount64;
  end;
  Result := GetTickCount64 > JoinProgressAt + JoinTimeoutMs;
end;

// Takes the film of the next day in the wanted star, which waits to be played. CHANGE:
// ENHANCEMENT - The next day's film is the one of the state's day (a film is recorded before
// the galaxy job counts the day). Films of earlier days go; films of later days stay, since the
// host runs the next day of a human who continues its travel while the client still plays the
// last one (docs/network.md, Continuing travel).
procedure CollectFilms;
begin
  if Galaxy = nil then
    Exit;
  if (PendingFilm = nil) and (WantedFilmStar >= 0) then
    PendingFilm := CurrentClient.TakeFilmOfDay(Galaxy.CurrentTurn, WantedFilmStar)
  else
    CurrentClient.DropFilmsBefore(Galaxy.CurrentTurn);
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
  // The host's day asks a dialogue: the box closes and the talk opens (WaitModal).
  if (Kind in [nwClientDay, nwClientState]) and (CurrentClient <> nil) and CurrentClient.HasTalkRequest then
    Exit(True);
  case Kind of
    nwHostPeers:
      Result := (CurrentHost = nil) or CurrentHost.PeersReady;
    nwHostTalk:
      Result := (CurrentHost = nil) or (CurrentHost.TalkHumanId = 0);
    nwJoin:
      Result :=
          (CurrentClient = nil)
              or CurrentClient.HasState
              or CurrentClient.CharacterWanted
              or not CurrentClient.Connected
              or JoinStalled;
    nwReconnect:
      Result := (CurrentClient = nil) or not CurrentClient.Reconnecting;
    nwClientDay:
      begin
        Client := CurrentClient;
        if Client = nil then
          Exit(True);
        CollectFilms;
        // CHANGE: ENHANCEMENT - The host took the end turn back.
        Result :=
            (PendingFilm <> nil)
                or Client.HasState
                or not Client.Connected
                or (Client.EndTurnCancel = ncAccepted);
      end;
  else
    Result := (CurrentClient = nil) or CurrentClient.HasState or not CurrentClient.Connected;
  end;
end;

// CHANGE: ENHANCEMENT - The wait may take the local human's end turn back (below).
function MayCancelEndTurn(Kind: TNetWaitKind): Boolean; forward;

function WaitText(Kind: TNetWaitKind): WideString;
begin
  // CHANGE: ENHANCEMENT - The client's waits say that it reconnects, and have a Cancel then.
  if (Kind in [nwClientDay, nwClientState, nwReconnect]) and ClientReconnecting then
    Exit(ReconnectText);
  case Kind of
    nwHostPeers:
      Result := HostWaitText;
    nwHostTalk:
      Result := HostTalkText;
    nwJoin:
      Result := JoinWaitText;
  else
    Result := ClientWaitText;
  end;
  // CHANGE: ENHANCEMENT - The Cancel takes the end turn back, or stops the travel that goes on;
  // a client's waits for the host's answer, or for the next state when the day had begun
  // (docs/network.md, Waiting).
  if MayCancelEndTurn(Kind) and LocalHuman.ContinueUntilArrival then
    Result :=
        Result + #13#10 + MultiplayerText('CancelTravel', 'Cancel: stop your travel and take your turn back.')
  else if MayCancelEndTurn(Kind) then
    Result := Result + #13#10 + MultiplayerText('CancelEndTurn', 'Cancel: take your end turn back.')
  else if (Kind in [nwClientDay, nwClientState])
      and (NetRole = nrClient)
      and ((CurrentClient.EndTurnCancel = ncPending) or ClientStopRequested) then
    Result := Result + #13#10 + MultiplayerText('CancellingEndTurn', 'Taking your end turn back...');
end;

// CHANGE: ENHANCEMENT - Whether the wait for the day may take the local human's end turn back
// (docs/network.md, Waiting): before the day has begun, when the end turn made the human stop
// holding the day and taking it back makes it hold the day again. Not for a takeoff (the screen
// that took off would stay with the ranger leaving), nor in hyperspace (the jump cannot stop).
// On the host, while it waits for its peers (also at the end of a film whose travel goes on);
// on a client, while it waits for the day, for the EndTurn it sent since its last state, once.
// CHANGE: ENHANCEMENT - A client whose travel continues (it sent no EndTurn) may stop it in its
// waits for the film and for the state, once per state, also while the host's day runs: then
// the stop holds the day after it.
function MayCancelEndTurn(Kind: TNetWaitKind): Boolean;
var
  P: TPlayer;
begin
  Result := False;
  P := LocalPlayer;
  // CHANGE: ENHANCEMENT - Nor for a human who owes days for a text quest: its days end the turn
  // by themselves (NetQuestDayDue).
  if ExitScreenLoop
      or (Galaxy = nil)
      or (P = nil)
      or LocalHuman.Finished
      or not LocalHuman.Connected
      or P.InHyperspace
      or (P.Order = soTakeoff)
      or (LocalHuman.QuestDaysOwed > 0) then
    Exit;
  case Kind of
    nwHostPeers:
      Result :=
          (NetRole = nrHost)
              and (LocalHuman.EndedTurn or LocalHuman.ContinueUntilArrival)
              and not CurrentHost.DayUnderWay;
    nwClientDay, nwClientState:
      if (NetRole <> nrClient) or CurrentClient.Reconnecting or ClientStopRequested then
        Result := False
      // The client's own EndTurn asks to continue its travel too; the host has not applied it.
      else if CurrentClient.MayCancelEndTurn then
        Result := (Kind = nwClientDay) and not CurrentClient.Status.DayRunning
      else
        Result :=
            LocalHuman.ContinueUntilArrival
                and LocalHuman.EndedTurn
                and CurrentClient.MayCancelEndTurn(True);
  end;
end;

// CHANGE: ENHANCEMENT - What the wait's Cancel would do now.
function WaitCancel(Kind: TNetWaitKind): TNetWaitCancel;
begin
  if (Kind in [nwClientDay, nwClientState, nwReconnect]) and ClientReconnecting then
    Result := nwcReconnect
  else if MayCancelEndTurn(Kind) then
    Result := nwcEndTurn
  else
    Result := nwcNone;
end;

// CHANGE: ENHANCEMENT - The buttons of a wait: a Cancel while a client reconnects, or while the
// end turn may be taken back.
function WaitOptions(Kind: TNetWaitKind): Cardinal;
begin
  Result := 0;
  if WaitCancel(Kind) <> nwcNone then
    Result := mbgCancel;
end;

// Pumps the network; on the host also frees the states sent and sends the state of a day that
// has run once the host is quiet after it.
procedure NetFrame; forward;
// CHANGE: ENHANCEMENT - A client that lost its host goes to the main menu at a safe screen.
procedure LeaveLostGame; forward;
// CHANGE: ENHANCEMENT - The state after a reconnect is applied at a safe screen.
procedure ApplyRejoinState; forward;

procedure TNetWaitBoxGI.OnOpen;
begin
  inherited OnOpen;
  OpenedAt := GetTickCount64;
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
  // A join's progress changes often; its box opens again at most every JoinRetextMs.
  // CHANGE: ENHANCEMENT - A reconnect's seconds too; and a client's wait opens again with a
  // Cancel when the reconnect starts, without one when it ends.
  else if (((Kind <> nwJoin) and not ClientReconnecting) or (GetTickCount64 >= OpenedAt + JoinRetextMs))
      and ((WaitText(Kind) <> MessageText) or (WaitOptions(Kind) <> Options)) then
    RequestClose(WaitRetext);
end;

// ShowMessageBoxGI for a wait box, over the innermost screen; Options are its buttons (0: none).
function RunWaitBox(Kind: TNetWaitKind; const Text: WideString; Options: Cardinal = 0): Cardinal;
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
    Dialog.Options := Options;
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

// CHANGE: ENHANCEMENT - A client answers the dialogue the host's day asks its human
// (docs/network.md, Remote dialogue): the talk screen opens over the waiting star map, on the
// state before the day, for the ship the request names; its answers are commands, predicted
// here and sent to the host as usual. TalkDone follows, also when the talk cannot be shown
// here (no such ship, not in its star, not on the star map).
procedure AnswerClientTalk;
var
  Client: TNetClient;
  Request: TTalkRequestMessage;
  Ship: TShip;
  SavedScreen: TGameScreenId;
  SavedResume: TStarMapResumeMode;
  Shown: Boolean;
  Age: Integer;
begin
  Client := CurrentClient;
  Age := Client.TalkRequestAge;
  if not Client.TakeTalkRequest(Request) then
    Exit;
  Shown := False;
  try
    Ship := nil;
    if (Galaxy <> nil) and (Request.ShipId <> 0) then
      Ship := TShip(Galaxy.IdToShip(Cardinal(Request.ShipId), False));
    if (ClientTalkWaits > 0)
        and not ExitScreenLoop
        and (Request.HumanId = Client.HumanId)
        and (Request.PlanetId = 0)
        and (Ship <> nil)
        and (LocalPlayer <> nil)
        and (Ship <> LocalPlayer)
        and LocalPlayer.InNormalSpace
        and (Ship.CurrentStar = LocalPlayer.CurrentStar)
        and (CurrentScreenId = screenStarMap)
        and (GetInnermostScreenLoop = StarMapScreen) then
    begin
      LocalHuman.TalkShip := Ship;
      LocalHuman.TalkPlanet := nil;
      LocalHuman.TalkScripted := Request.Scripted;
      LocalHuman.TalkType := Request.TalkType;
      LocalHuman.TalkAmount := Request.Amount;
      LocalHuman.TalkResponse := 0;
      LocalHuman.TalkText := Request.Text;
      Session.ScriptDialogIndex := -1;
      SavedScreen := RequestedScreenId;
      SavedResume := StarMapScreen.ResumeMode;
      StarMapScreen.RunTalkDialogs;
      // The talk screen returns to the star map, which still waits for the day.
      if RequestedScreenId in [screenTalk, screenStarMap] then
        RequestedScreenId := SavedScreen;
      StarMapScreen.ResumeMode := SavedResume;
      LocalHuman.TalkScripted := False;
      Shown := True;
    end;
  finally
    Client.SendTalkDone;
  end;
  NetLog(
      Format(
          'talk from ship %d: %s, response %d, %d ms after it came',
          [Request.ShipId, BoolToStr(Shown, 'answered', 'cannot be shown here'),
              LocalHuman.TalkResponse, Age]
      )
  );
end;

// Waits, modal over the open screen, until what Kind waits for has come or the window closes.
// A client answers the dialogues the host's day asks meanwhile.
procedure WaitModal(Kind: TNetWaitKind);
var
  Closed: Cardinal;
  SavedPeersWait: Boolean;
  Cancel: TNetWaitCancel;
begin
  if Kind in [nwClientDay, nwClientState] then
    Inc(ClientTalkWaits);
  SavedPeersWait := HostPeersWaitOpen;
  if Kind = nwHostPeers then
    HostPeersWaitOpen := True;
  try
    NetFrame;
    repeat
      if (Kind in [nwClientDay, nwClientState]) and not ExitScreenLoop and CurrentClient.HasTalkRequest then
        AnswerClientTalk
      else if WaitDone(Kind) then
        Break
      else
      begin
        Cancel := WaitCancel(Kind);
        Closed := RunWaitBox(Kind, WaitText(Kind), WaitOptions(Kind));
        if Closed = mbgResultCancel then
        begin
          // CHANGE: ENHANCEMENT - The player gave up the reconnect: the client is gone, which
          // the wait sees next (docs/network.md, Waiting).
          if Cancel = nwcReconnect then
          begin
            if CurrentClient <> nil then
              CurrentClient.CancelReconnect;
          end
          // CHANGE: ENHANCEMENT - The player takes the end turn back: the host's wait ends here,
          // its human holds the day again (HostDayMayStart); a client's goes on until the host
          // answers (WaitDone).
          else if (Cancel = nwcEndTurn) and MayCancelEndTurn(Kind) then
          begin
            if Kind = nwHostPeers then
            begin
              CancelEndTurn;
              NetLog('end turn taken back');
              Break;
            end;
            if CurrentClient.MayCancelEndTurn then
              CurrentClient.SendCancelEndTurn(CancelEndTurnCommand)
            // CHANGE: ENHANCEMENT - The travel that goes on stops (docs/network.md, Continuing
            // travel): before the host's next day, the wait ends as for an end turn taken back;
            // otherwise the next state's screen stops it (OpenClientScreen).
            else if CurrentClient.SendCancelEndTurn(CancelEndTurnCommand(True)) then
              ClientStopRequested := True;
          end;
        end
        else if (Closed <> mbgResultOK) and (Closed <> WaitRetext) then
          Break;
      end;
    until False;
  finally
    HostPeersWaitOpen := SavedPeersWait;
    if Kind in [nwClientDay, nwClientState] then
      Dec(ClientTalkWaits);
  end;
end;

// CHANGE: ENHANCEMENT - The screen loop that runs now, when it is the innermost screen's
// (no box or dialogue above it, and a screen is open, not between two); nil otherwise.
function RunningScreenLoop: TMessageLoopGI;
begin
  Result := nil;
  if (CurrentScreenId = screenNone)
      or (RegisteredScreens[Ord(CurrentScreenId)] = nil)
      or (MessageLoopStack = nil)
      or (MessageLoopStack.Count = 0) then
    Exit;
  if TMessageLoopGI(MessageLoopStack[MessageLoopStack.Count - 1]) = GetInnermostScreenLoop then
    Result := GetInnermostScreenLoop;
end;

// CHANGE: ENHANCEMENT - The host's UI waits for its day while the turn thread waits for a remote
// human's answer to a dialogue: a box says whose (docs/network.md, Waiting). Only over a
// screen that runs, from the waits of a day (NetWaitForEvents, TurnWaitPumpHook).
procedure HostTalkWait;
begin
  if HostTalkBoxOpen
      or (NetRole <> nrHost)
      or (CurrentHost.TalkHumanId = 0)
      or ExitScreenLoop
      or (RunningScreenLoop = nil) then
    Exit;
  HostTalkBoxOpen := True;
  try
    WaitModal(nwHostTalk);
  finally
    HostTalkBoxOpen := False;
  end;
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
  Result := (Galaxy <> nil) and not MemorySnapshotActive and not NoGameScreen(CurrentScreenId);
end;

// The quiet point after a day (docs/network.md, States): no job runs, and the next day is
// prepared, or the galaxy job has run and this screen does not prepare days. Only the star map
// prepares days (after its film), so there the state waits for the preparation.
// CHANGE: ENHANCEMENT - A star map whose travel goes on (TfStarMap.NetDayDeferred) prepares no
// day: the next one starts at the film's end. Its state goes as soon as the galaxy job has run,
// while the film plays, so that neither the host's next day nor the clients' wait for it.
function QuietAfterDay: Boolean;
begin
  Result :=
      not IsTurnCalculationRunning
          and ((TurnCalculationPhase = tcpPlayerStarPrepared)
              or ((TurnCalculationPhase = tcpGalaxyFinished)
                  and ((CurrentScreenId <> screenStarMap) or StarMapScreen.NetDayDeferred)));
end;

// CHANGE: ENHANCEMENT - Whether a command from the network may change the game under the screen
// now (docs/network.md, Trades): a peer's trade on the host, a relayed trade on a client. The
// pump runs from the loop of the innermost screen between two of its messages, so no handler
// is between a submit and its read of the results, no box or dialogue is above the screen and
// no screen is being built; or the host waits at its end turn for its peers, where the queues
// are applied next anyway. No command runs, and the screen does not close.
function MayChangeUnderScreen: Boolean;
begin
  Result :=
      (Galaxy <> nil)
          and not CommandRunning
          and not ScreenClosing
          and not ExitScreenLoop
          and not MemorySnapshotActive
          and not NoGameScreen(CurrentScreenId)
          and (HostPeersWaitOpen or (InFramePump and (RunningScreenLoop <> nil)));
end;

function HostMayApplyTrades: Boolean;
begin
  Result := MayChangeUnderScreen;
end;

// CHANGE: ENHANCEMENT - A client's trade waits for the host's answer (TNetClient.SendTrade):
// the window stays alive meanwhile, and the input that comes is dropped, so that the screen
// takes no second action on what it showed before the answer.
procedure TradeWaitIdle;
var
  Saved: TRuntimeCallbackGR;
begin
  Saved := FramePumpHook;
  FramePumpHook := nil;
  try
    GR_WinMessage(nil);
  finally
    FramePumpHook := Saved;
  end;
end;

// CHANGE: ENHANCEMENT - What a bubble says when another human was first (TradeRefusedHook).
function LocalRefusalText(Reason: TRefusalReason): WideString;
const
  Keys: array[TRefusalReason] of WideString = (
      'Multiplayer.LateOther',
      'Multiplayer.LateOutOfStock',
      'Multiplayer.LateNoMoney',
      'Multiplayer.LateItemGone',
      'Multiplayer.LateOfferGone',
      'Multiplayer.LateTargetGone',
      'Multiplayer.LateNoRoom',
      'Multiplayer.LateInUse',
      'Multiplayer.LateTooLate'
  );
  English: array[TRefusalReason] of WideString = (
      'Your action was not done: another player acted first.',
      'Another player was first: not enough in stock.',
      'Your action was not done: not enough money.',
      'Another player was first: the item is gone.',
      'Another player was first: the offer is no longer there.',
      'Your action was not done: things changed before it.',
      'Your sale was not done: the buyer has no room for it.',
      'Another player is using it.',
      'Your action was not done: the day has begun.'
  );
begin
  Result := MultiplayerText(Copy(Keys[Reason], Length('Multiplayer.') + 1, MaxInt), English[Reason]);
end;

// TradeRefusedHook: the refusal as a bubble of the local human. A client shows the host's
// refusal with the host's text (TNetClient), and the same text adds no second bubble.
procedure ShowTradeRefusal(Reason: TRefusalReason);
var
  Text: WideString;
begin
  if (Galaxy = nil) or (LocalHuman = nil) then
    Exit;
  // A trade the host did not answer has its own bubble (TNetClient.SendTrade).
  if (NetRole = nrClient) and CurrentClient.TakeNoAnswerShown then
    Exit;
  if NetRole = nrClient then
    Text := RefusalText(Reason)
  else
    Text := LocalRefusalText(Reason);
  LocalHuman.AddOrUpdateBubble(0, Galaxy.CurrentTurn, Text, '');
  NetLog('own trade refused: ' + RefusalReasonName(Reason));
end;

// CHANGE: ENHANCEMENT - The client reconnects to its host (docs/network.md, Waiting): a box with
// Cancel (also Escape) over the innermost screen until the reconnect ends, from the frame pump
// between two messages of that screen's loop, so over any screen of a game, a shop too: the
// box changes nothing. Not while a wait for the day is open (it says the same with its own
// Cancel), nor while the star map plays the host's film, whose end waits anyway. It closes by
// itself when the host has let the client in again; Cancel ends the reconnect, and the lost
// game leaves for the main menu at the next safe screen (LeaveLostGame).
procedure ClientReconnectWait;
var
  Closed: Cardinal;
begin
  if ReconnectBoxOpen
      or not ClientInGame
      or not ClientReconnecting
      or ScreenClosing
      or ExitScreenLoop
      or (ClientFilmPlaying and (CurrentScreenId = screenStarMap))
      or (ClientTalkWaits > 0)
      or NoGameScreen(CurrentScreenId)
      or (RunningScreenLoop = nil) then
    Exit;
  ReconnectBoxOpen := True;
  try
    repeat
      if WaitDone(nwReconnect) then
        Break;
      Closed := RunWaitBox(nwReconnect, WaitText(nwReconnect), WaitOptions(nwReconnect));
      if Closed = mbgResultCancel then
      begin
        if CurrentClient <> nil then
          CurrentClient.CancelReconnect;
        Break;
      end;
      if (Closed <> mbgResultOK) and (Closed <> WaitRetext) then
        Break;
    until False;
  finally
    ReconnectBoxOpen := False;
  end;
end;

// FramePumpHook.
procedure NetFramePump;
begin
  InFramePump := True;
  try
    NetFrame;
  finally
    InFramePump := False;
  end;
  // CHANGE: ENHANCEMENT - Outside NetFrame, so that the box's own pump runs.
  ClientReconnectWait;
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
        begin
          CurrentClient.Pump;
          // CHANGE: ENHANCEMENT - The trades the host relayed run at a safe point, as a state is
          // applied at one (docs/network.md, Trades).
          if CurrentClient.HasRelayed
              and not ApplyPending
              and not (ClientFilmPlaying and (CurrentScreenId = screenStarMap))
              and MayChangeUnderScreen then
            CurrentClient.ApplyRelayed;
          // A client that does not wait for the day cannot show the host's dialogue, except at
          // the end of the film it plays, where the wait for the state answers it.
          if (ClientTalkWaits = 0)
              and CurrentClient.HasTalkRequest
              and not CurrentClient.MayHoldTalk(ClientFilmPlaying and (CurrentScreenId = screenStarMap)) then
            AnswerClientTalk;
          // CHANGE: ENHANCEMENT - The host left or stopped hosting while the client plays its
          // turn: back to the main menu at the next safe screen, which says why. CHANGE:
          // ENHANCEMENT - A lost connection is not that while the client reconnects (Connected
          // stays True); the whole state after the reconnect, which may come while no wait for
          // the day is open, is applied at the next safe screen (docs/network.md, Disconnects).
          if ClientInGame and not CurrentClient.Connected then
            LeaveLostGame
          else if ClientInGame and CurrentClient.RejoinStatePending and not ApplyPending then
            ApplyRejoinState;
        end;
    end;
  finally
    InPump := False;
  end;
end;

// TurnWaitPumpHook: the pump, and on the host the box of a remote dialogue.
procedure NetTurnWait;
begin
  NetFrame;
  HostTalkWait;
end;

procedure BeginNetSession(AsClient: Boolean);
begin
  FramePumpHook := @NetFramePump;
  TurnWaitPumpHook := @NetTurnWait;
  TurnJobsForbidden := AsClient;
  // CHANGE: ENHANCEMENT - Trades (docs/network.md, Trades): the host applies a peer's at a
  // point MayChangeUnderScreen allows; a client's wait keeps the window alive; a refused trade
  // of this machine's player is a bubble and ends the UI action that submitted it.
  if not AsClient and (CurrentHost <> nil) then
    CurrentHost.MayApplyTrades := @HostMayApplyTrades;
  TradeWaitIdleHook := @TradeWaitIdle;
  TradeRefusedHook := @ShowTradeRefusal;
  TradeAbortHook := @BreakUiMessage;
end;

procedure EndNetSession;
var
  I: Integer;
begin
  FramePumpHook := nil;
  TurnWaitPumpHook := nil;
  TurnJobsForbidden := False;
  TradeWaitIdleHook := nil;
  TradeRefusedHook := nil;
  TradeAbortHook := nil;
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
  ClientFilmPlaying := False;
  ClientInGame := False;
  HostLossLogged := False;
  RejoinApplyLogged := False;
  ClientStopRequested := False;
  QuestAbandonedNotice := False;
end;

// The client goes back to the main menu, which says Text. The session ends between screens.
procedure LeaveForMainMenu(Screen: TMessageLoopGI; const Text: WideString);
begin
  Notice := Text;
  NetLog('leaving the game: ' + UTF8Encode(Text));
  ApplyPending := False;
  ClientFilmPlaying := False;
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
  ClientFilmPlaying := False;
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
    // CHANGE: ENHANCEMENT - The player took the end turn back (WaitModal): its screen goes on in
    // order mode, and the peers' queues wait for the next end turn.
    if HumanHoldsDay(LocalHuman) then
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
  ClientFilmPlaying := False;
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
  // CHANGE: ENHANCEMENT - The host took the end turn back: it runs here too, and the screen goes
  // on in order mode (NetEndTurn's callers, as when the day does not start).
  if Client.TakeCancelledEndTurn then
  begin
    ClientStopRequested := False;
    NetLog('end turn taken back');
    Exit;
  end;
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

// CHANGE: ENHANCEMENT - The day a client's human played a text quest that owes days
// (docs/progress/2026-10-19-text-quests-plan.md, The day): the quest's CloseQuest ran here, so
// the human owes the days and holds no day here, and EndTurn would send nothing. The host has the
// days only once its barrier applies that CloseQuest, and until then its day waits for the
// human's EndTurn: the last state said the human owed none, and it has not ended this turn.
function ClientQuestDayEnds: Boolean;
var
  P: TPlayer;
begin
  P := LocalPlayer;
  Result :=
      (NetRole = nrClient)
          and (P <> nil)
          and (LocalHuman.QuestDaysOwed > 0)
          and (CurrentClient.StateQuestDays = 0)
          and not LocalHuman.EndedTurn
          and not LocalHuman.Finished
          and LocalHuman.Connected
          and not P.InHyperspace;
end;

procedure SubmitQuestDayEndTurn;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckEndTurn);
  AddInt(Command, 0);
  SubmitCommand(Command);
end;

function NetQuestDayDue: Boolean;
begin
  Result :=
      (NetRole <> nrNone)
          and (Galaxy <> nil)
          and (LocalPlayer <> nil)
          and (LocalHuman.QuestDaysOwed > 0)
          and not LocalHuman.Finished
          and not ExitScreenLoop
          and not ScreenClosing
          and not ((NetRole = nrClient) and CurrentClient.Reconnecting);
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
        // CHANGE: ENHANCEMENT - The end turn asks the host to go on with the travel until it
        // stops (THuman.ContinueUntilArrival), as the star map's automatic continue goes on:
        // the host then runs the next days without waiting for this client, and the break
        // stops it (docs/network.md, Continuing travel). Not with the break key held.
        if ClientQuestDayEnds then
          SubmitQuestDayEndTurn
        else
          EndTurn(not ((Screen = StarMapScreen) and StarMapScreen.BreakOnNextFilm));
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
  ClientFilmPlaying := True;
end;

procedure ClientFilmEnded(Screen: TMessageLoopGI; BreakRequested, CombatRecorded: Boolean);
begin
  // A dialogue that came during the film is answered in this wait.
  ClientFilmPlaying := False;
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
  CurrentClient.DropFilmsBefore(High(Integer));
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
    HostTalkWait;
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
    // CHANGE: ENHANCEMENT - The host goes on with the travel (the state says so: the human
    // continues until arrival), so the star map waits for the next day's film at once, as the
    // star map's automatic continue does, until the host stops it or the player breaks a film.
    // A break asks the host to stop (it may have run the next day already).
    // CHANGE: ENHANCEMENT - So does a Cancel the host answered too late (ClientStopRequested):
    // the host has the stop queued for its next day, and this sends it again (harmless).
    Continues :=
        LocalHuman.ContinueUntilArrival
            and not (AppliedAfterFilm and FilmBroken)
            and not ClientStopRequested;
    if LocalHuman.ContinueUntilArrival and not Continues then
      StopContinuing;
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
  ClientStopRequested := False;
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
  RejoinApplyLogged := False;
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
  ClientInGame := True;
  // CHANGE: ENHANCEMENT - The state replaced the bubbles; the abandoned quest's goes after it.
  if QuestAbandonedNotice then
  begin
    QuestAbandonedNotice := False;
    LocalHuman.AddOrUpdateBubble(
        0,
        Galaxy.CurrentTurn,
        MultiplayerText(
            'QuestAbandoned',
            'The connection to the host was lost: your text quest was abandoned. You can start it again.'
        ),
        ''
    );
  end;
end;

var
  // CHANGE: ENHANCEMENT - The join the command line or the main menu asks for; it runs between
  // screens on the way to the main menu.
  PendingJoinAddress: AnsiString;
  PendingJoinName: WideString;
  // CHANGE: ENHANCEMENT - The new-game screen is open for a first join's character; the join
  // goes on over the main menu once it has been sent (the session stays on the way there).
  CharacterScreenOpen: Boolean;
  JoinResumes: Boolean;

function ParseNetAddress(const Text: AnsiString; out Host: AnsiString; out Port: Integer): Boolean;
var
  Colon: Integer;
begin
  Host := Trim(Text);
  Port := DefaultNetPort;
  Colon := LastDelimiter(':', Host);
  if Colon > 0 then
  begin
    Port := StrToIntDef(Copy(Host, Colon + 1, MaxInt), -1);
    Host := Copy(Host, 1, Colon - 1);
  end;
  Result := (Host <> '') and (Port > 0) and (Port <= 65535);
end;

procedure RequestJoin(const Address: AnsiString; const Name: WideString);
begin
  PendingJoinAddress := Address;
  PendingJoinName := Name;
end;

function NetCharacterScreen: Boolean;
begin
  Result := CharacterScreenOpen and (NetRole = nrClient);
end;

function NetJoinName: WideString;
begin
  Result := PendingJoinName;
end;

procedure SendNetCharacter(const Name: WideString; const Character: TJoinCharacter);
begin
  CharacterScreenOpen := False;
  if CurrentClient = nil then
    Exit;
  CurrentClient.SendCharacter(Name, Character);
  PendingJoinName := Name;
  JoinResumes := True;
  NetLog(
      Format(
          'character sent: race %d, preset %d, face %d',
          [Character.Race, Character.Preset, Character.Face]
      )
  );
end;

procedure CancelNetCharacter;
begin
  CharacterScreenOpen := False;
  JoinResumes := False;
  NetLog('the join was cancelled on the new-game screen');
end;

// The join's box over Screen until the state has come, the host asks for a character (the
// new-game screen opens), or the join fails or is cancelled.
procedure FollowJoin(Screen: TMessageLoopGI);
var
  Client: TNetClient;
  Closed: Cardinal;
  Cancelled: Boolean;
  Text: WideString;
begin
  Client := CurrentClient;
  if Client = nil then
    Exit;
  JoinProgressMark := -1;
  JoinProgressAt := GetTickCount64;
  Cancelled := False;
  repeat
    if WaitDone(nwJoin) then
      Break;
    Closed := RunWaitBox(nwJoin, JoinWaitText, mbgCancel);
    if Closed = mbgResultCancel then
      Cancelled := True
    else if (Closed = mbgResultOK) or (Closed = WaitRetext) then
      Continue;
    Break;
  until False;
  if ExitScreenLoop or (Screen.ExitCode <> 0) then
  begin
    EndNetSession;
    Exit;
  end;
  if not Cancelled and Client.Connected and Client.CharacterWanted then
  begin
    CharacterScreenOpen := True;
    RequestedScreenId := screenNewGame;
    Screen.RequestClose(1);
    Exit;
  end;
  if Cancelled or not Client.HasState then
  begin
    if Cancelled then
    begin
      NetLog('the join was cancelled');
      Text := '';
    end
    else if Client.Connected then
      Text := MultiplayerText('NoState', 'The host did not send the game.')
    else
      Text := ClientGoneText;
    EndNetSession;
    if Text <> '' then
      ShowMessageBoxGI(Screen, Text, mbgOK or mbgError);
    Exit;
  end;
  NetLog(Format('joined %s as human %d', [UTF8Encode(Client.HostName), Client.HumanId]));
  // The state is applied between screens; the human's screen opens after it.
  RequestApply(Screen, False, False, False);
end;

procedure RunPendingJoin(Screen: TMessageLoopGI);
var
  Address: AnsiString;
  Port: Integer;
  Text: WideString;
begin
  if PendingJoinAddress = '' then
  begin
    if JoinResumes then
    begin
      JoinResumes := False;
      FollowJoin(Screen);
    end;
    Exit;
  end;
  if not ParseNetAddress(PendingJoinAddress, Address, Port) then
  begin
    Text :=
        MultiplayerText('BadAddress', 'Expected an address as HOST or HOST:PORT:')
            + ' '
            + WideString(PendingJoinAddress);
    PendingJoinAddress := '';
    ShowMessageBoxGI(Screen, Text, mbgOK or mbgError);
    Exit;
  end;
  PendingJoinAddress := '';
  JoinAddressText := WideString(Address) + ':' + WideString(IntToStr(Port));
  NetLog(Format('joining %s:%d as %s', [Address, Port, UTF8Encode(PendingJoinName)]));
  // The connect runs on its own thread, so the box can show it and Cancel can end it.
  JoinGame(Address, Port, PendingJoinName, False);
  BeginNetSession(True);
  FollowJoin(Screen);
end;

// CHANGE: ENHANCEMENT - The screen a client may close now, outside a wait for the day, to
// leave the game or to apply a state (LostHostLeaveScreens); nil when none.
function SafeClientScreen: TMessageLoopGI;
begin
  Result := nil;
  if ScreenClosing
      or (ClientFilmPlaying and (CurrentScreenId = screenStarMap))
      or (ClientTalkWaits > 0)
      or ExitScreenLoop
      or not (CurrentScreenId in LostHostLeaveScreens) then
    Exit;
  Result := RunningScreenLoop;
  if (Result <> nil)
      and ((Result <> TMessageLoopGI(RegisteredScreens[Ord(CurrentScreenId)])) or (Result.ExitCode <> 0)) then
    Result := nil;
end;

// CHANGE: ENHANCEMENT - The quest screen of a game, running with nothing above it: a client
// closes it to apply the state after a reconnect or to leave a lost game, and leaves its quest
// (docs/progress/2026-10-19-text-quests-plan.md, Disconnects); nil otherwise.
function ClientQuestScreen: TMessageLoopGI;
begin
  Result := nil;
  if ScreenClosing
      or (ClientTalkWaits > 0)
      or ExitScreenLoop
      or (CurrentScreenId <> screenPlanetQuest)
      or not PlanetQuestScreen.PlaysGameQuest
      or (PlanetQuestScreen.ExitCode <> 0) then
    Exit;
  if RunningScreenLoop = PlanetQuestScreen then
    Result := PlanetQuestScreen;
end;

// CHANGE: ENHANCEMENT - The client lost its host while it plays its turn (NetFrame). It leaves
// for the main menu, which says why, once a screen that starts a day is the one open: not in a
// shop, a dialogue or a box, and not while the star map plays a film, whose end leaves anyway.
procedure LeaveLostGame;
var
  Screen: TMessageLoopGI;
begin
  if not HostLossLogged then
  begin
    HostLossLogged := True;
    NetLog('the host is gone; the game goes back to the main menu at the next safe screen');
  end;
  Screen := SafeClientScreen;
  // CHANGE: ENHANCEMENT - A text quest that plays is left (docs/progress/
  // 2026-10-19-text-quests-plan.md, Disconnects): the host never got its commands.
  if Screen = nil then
  begin
    Screen := ClientQuestScreen;
    if Screen <> nil then
      PlanetQuestScreen.AbandonQuest;
  end;
  if Screen <> nil then
    LeaveForMainMenu(Screen, ClientGoneText);
end;

// CHANGE: ENHANCEMENT - The client reconnected while it played its turn (docs/network.md,
// Disconnects): the host's whole state is applied between screens, as at the end of a wait,
// once a screen that starts a day is the one open (SafeClientScreen: not a shop or the ship
// screen, which move goods when they close, no box above it, no film). Its commands are
// dropped until then (TNetClient.SendCommand). A wait for the day or the jump screen's tick
// apply it themselves.
procedure ApplyRejoinState;
var
  Screen: TMessageLoopGI;
begin
  if not RejoinApplyLogged then
  begin
    RejoinApplyLogged := True;
    NetLog('the state after the reconnect is applied at the next safe screen');
  end;
  Screen := SafeClientScreen;
  // CHANGE: ENHANCEMENT - The text quest the human plays is abandoned (docs/progress/
  // 2026-10-19-text-quests-plan.md, Disconnects): the host dropped its commands with the old
  // connection, so the quest never happened there and can be started again (the planet's quest
  // is still in the state). The screen closes without CloseQuest, and the human is told after
  // the state (ApplyClientState).
  if Screen = nil then
  begin
    Screen := ClientQuestScreen;
    if Screen = nil then
      Exit;
    PlanetQuestScreen.AbandonQuest;
    QuestAbandonedNotice := True;
    NetLog('the text quest is abandoned: the host dropped it with the lost connection');
  end;
  RejoinApplyLogged := False;
  RequestApply(Screen, False, False, False);
end;

function HostRunningGame(Port: Integer): Integer;
var
  Host: TNetHost;
begin
  WaitForTurnCalculation;
  Host := StartHosting(Port, LocalPlayer.Name);
  BeginNetSession(False);
  Result := Host.Thread.ListenPort;
  NetLog(Format('hosting on port %d as %s', [Result, UTF8Encode(LocalPlayer.Name)]));
end;

procedure StartHostingGame;
var
  Port: Integer;
begin
  Port := CommandLineHostPort;
  CommandLineHostPort := -1;
  HostRunningGame(Port);
end;

function HostingRefusal: WideString;
begin
  Result := '';
  if NetRole = nrClient then
    Result := MultiplayerText('HostOnClient', 'You play in another player''s game.')
  else if (Galaxy = nil) or (LocalPlayer = nil) or (LocalHuman = nil) or MemorySnapshotActive then
    Result := MultiplayerText('HostNoGame', 'There is no game to host now.')
  else if Galaxy.SpecialSimulationMode <> 0 then
    Result := MultiplayerText('HostMode', 'This kind of game cannot be hosted.')
  // Hot-seat hands the screen from human to human; a host is one human at one machine.
  else if (HotSeatHumans > 1) or (PendingHuman <> nil) or (LocalHuman <> HostHuman) then
    Result := MultiplayerText('HostHotSeat', 'A hot-seat game cannot be hosted.');
end;

procedure StopHostingGame;
begin
  if NetRole <> nrHost then
    Exit;
  WaitForTurnCalculation;
  CurrentHost.DisconnectHumans;
  NetLog('stopped hosting');
  EndNetSession;
end;

function ConnectedPlayerNames: WideString;
var
  I: Integer;
  Human: THuman;
begin
  Result := '';
  if NetRole <> nrHost then
    Exit;
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Human := Session.Humans[I];
    if (Human <> LocalHuman) and Human.Connected and (Human.Player <> nil) then
      AddName(Result, HumanName(Human));
  end;
end;

function HostStatusText: WideString;
var
  Names, Addresses: WideString;
begin
  if NetRole <> nrHost then
    Exit('');
  Result := MultiplayerText('Hosting', 'Hosting this game on port <Port>.');
  ReplaceTextToken(
      Result,
      '<Port>',
      WideString(IntToStr(CurrentHost.Thread.ListenPort)),
      '<color=255,240,100>'
  );
  Addresses := WideString(LocalAddressText);
  if Addresses <> '' then
    Result :=
        Result
            + #13#10
            + NamedLine(
                'Addresses',
                'This computer: <Players>.',
                WideString(StringReplace(AnsiString(Addresses), ',', ', ', [rfReplaceAll]))
            );
  Names := ConnectedPlayerNames;
  if Names = '' then
    Result := Result + #13#10 + MultiplayerText('NoneConnected', 'No player has joined yet.')
  else
    Result := Result + #13#10 + NamedLine('Connected', 'Connected: <Players>.', Names);
end;

procedure NetBetweenScreens;
begin
  ScreenClosing := False;
  if ApplyPending then
    ApplyClientState;
  // CHANGE: ENHANCEMENT - Except a join that goes on after its character was chosen.
  if (RequestedScreenId = screenMainMenu) and (NetRole <> nrNone) and not JoinResumes then
    EndNetSession;
  if (CommandLineJoin <> '') and (RequestedScreenId = screenMainMenu) then
  begin
    RequestJoin(CommandLineJoin, WideString(CommandLineName));
    CommandLineJoin := '';
  end;
  // CHANGE: ENHANCEMENT - The join itself runs over the main menu (RunPendingJoin), for the
  // main menu's entry and for --join alike.
  // Hosting from the command line starts at the first screen of a game.
  if (CommandLineHostPort >= 0)
      and (Galaxy <> nil)
      and (LocalPlayer <> nil)
      and not NoGameScreen(RequestedScreenId) then
    StartHostingGame;
end;

end.
