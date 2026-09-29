{$EXCESSPRECISION OFF}
unit HeadlessNet;

// CHANGE: ENHANCEMENT - Networked play without a window, for tests (ROADMAP.md, Phase 5;
// docs/network.md, Tests). A host process loads a save, waits for its clients, and runs the
// days: its own human plays its turn, it waits for every client's end turn while pumping,
// applies their commands, runs the player-star job, sends the films, runs the galaxy job and
// sends the state. A client process joins, and each day plays the turn --sim-hotseat plays
// for its human, sends it, and waits for the film and the state. Both print one line per day
// with the state hash, the sizes and the load time. A client answers the dialogues the host's
// day asks its human with the talk screen's first answer.
// CHANGE: ENHANCEMENT - The LAN-session checks (docs/network.md, Tests): a client joins with
// the connect on its own thread and prints each phase of its join, can cancel it, plays each
// film of its star for a while and keeps a dialogue that comes meanwhile for the film's end;
// the host can send the films before its probe asks, and can stop hosting.
interface
uses
  HeadlessSim;
function RunNetHost(const Options: TSimulationOptions): Integer;
function RunNetClient(const Options: TSimulationOptions): Integer;
// CHANGE: ENHANCEMENT - --sim-net-talk=DAY (docs/network.md, Tests): from the FromDay-th day
// the player-star job runs (counting from 1, so a host and the replay of its log agree), right
// after the day of the first filmed star that holds remote humans who can be asked (in normal
// space, not on automatic control), the first ship of that star that is no human's asks each
// of them a truce offer (TShip.ShowPlayerDialogue), once in the run. An answer that agrees
// gives the human 1 credit, so the state shows it. It prints one line per human asked. The
// host installs it after it starts hosting; a replay of the host's log installs it too, and
// asks the same.
procedure InstallNetTalkProbe(FromDay: Integer);
procedure RemoveNetTalkProbe;
implementation
uses
  SysUtils,
  EC_Buf,
  Globals,
  GlobalsV,
  aEFilm,
  aGalaxy,
  aHuman,
  aObjectRefs,
  aPlayer,
  aSession,
  aShip,
  aGalaxyStruct,
  aTalkActions,
  ThreadCalc,
  WorkerErrors,
  NetThread,
  NetProtocol,
  NetHost,
  NetClient,
  NetSession;

const
  // Without progress for this long, a run fails instead of hanging the test.
  StallTimeoutMs = 120000;

procedure EmitNetEvent(const Text: AnsiString);
begin
  Emit('net ' + Text);
end;

function HashText(Value: QWord): AnsiString;
begin
  Result := IntToHex(Value, 16);
end;

function AwayCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Session.Humans.Count - 1 do
    if not Session.Humans[I].Connected then
      Inc(Result);
end;

var
  ProbeFromDay: Integer;
  // The days the player-star job has run since the probe was installed, and the last one.
  ProbeDays: Integer;
  ProbeLastTurn: Integer;
  ProbeDone: Boolean;
  ProbePrevious: TStarDayHook;
  // CHANGE: ENHANCEMENT - --sim-net-talk-after-film: the films of the day so far go before the
  // probe asks, so a client plays its film when the talk comes. The bytes they had, for the
  // host's day line.
  ProbeSendsFilms: Boolean;
  ProbeFilmBytes: Integer;

// StarDayHook of the probe, on the turn thread (InstallNetTalkProbe).
procedure NetTalkProbe(Star, Film: TObject; Recorded: Boolean);
var
  I, J: Integer;
  Human: THuman;
  Ship, Other: TShip;
  Response: Byte;
  Asked: Boolean;
begin
  if Assigned(ProbePrevious) then
    ProbePrevious(Star, Film, Recorded);
  if Galaxy.CurrentTurn <> ProbeLastTurn then
  begin
    ProbeLastTurn := Galaxy.CurrentTurn;
    Inc(ProbeDays);
  end;
  if ProbeDone or (ProbeDays < ProbeFromDay) then
    Exit;
  Asked := False;
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Human := Session.Humans[I];
    if (Human = LocalHuman)
        or (Human.Player = nil)
        or (Human.PlayerStar <> Star)
        or (Human.Player.CurrentStar <> Star)
        or not Human.Player.InNormalSpace
        or Human.PlayerAutomaticControl
        or not CanAskHuman(Human) then
      Continue;
    Ship := nil;
    for J := 0 to TStar(Star).Ships.Count - 1 do
    begin
      Other := TShip(TStar(Star).Ships[J]);
      if not IsHuman(Other) and Other.InNormalSpace then
      begin
        Ship := Other;
        Break;
      end;
    end;
    if Ship = nil then
      Continue;
    // The films go from the turn thread; the headless host does not pump while the job runs.
    if ProbeSendsFilms and not Asked and (ActiveHost <> nil) then
      Inc(ProbeFilmBytes, ActiveHost.SendFilms);
    Response :=
        Ship.ShowPlayerDialogue(
            Human.Player,
            tkTruceOffer,
            Ship.LookupTalkText('Talk.Truce.' + Ship.GetTypeNameKey + 'Send'),
            0
        );
    if Response <> 0 then
      Human.Player.SetMoney(Human.Player.Money + 1);
    Emit(
        Format(
            'net talk day=%d human=%d ship=%d response=%d',
            [Galaxy.CurrentTurn, Human.Id, Ship.Id, Response]
        )
    );
    Asked := True;
  end;
  if Asked then
    ProbeDone := True;
end;

procedure InstallNetTalkProbe(FromDay: Integer);
begin
  RemoveNetTalkProbe;
  ProbeFromDay := FromDay;
  ProbeDays := 0;
  ProbeLastTurn := -1;
  ProbeDone := False;
  ProbePrevious := StarDayHook;
  StarDayHook := @NetTalkProbe;
end;

procedure RemoveNetTalkProbe;
begin
  if @StarDayHook = @NetTalkProbe then
    StarDayHook := ProbePrevious;
  ProbePrevious := nil;
end;

function RunNetHost(const Options: TSimulationOptions): Integer;
var
  Host: TNetHost;
  Deadline: QWord;
  Day: Integer;
  Plan: AnsiString;
  Job: TNetStateJob;
  FilmBytes, StateBytes, Away: Integer;
begin
  Result := 0;
  LoadSave(Options.SavePath, Options.Seed);
  Emit(Format('sim save=%s seed=%d day=%d', [Options.SavePath, Options.Seed, Galaxy.CurrentTurn]));
  NetLogHook := @EmitNetEvent;
  try
    Host := StartHosting(Options.NetHostPort, 'Host');
    if Options.NetTalkDay > 0 then
      InstallNetTalkProbe(Options.NetTalkDay);
    ProbeSendsFilms := Options.NetTalkAfterFilm;
    Emit(Format('net host port=%d clients=%d', [Host.Thread.ListenPort, Options.NetClients]));
    // Every client first, then the joins by name, so that the humans are the same each run.
    Host.HoldJoins := True;
    Deadline := GetTickCount64 + StallTimeoutMs;
    while Host.PendingJoinCount < Options.NetClients do
    begin
      if GetTickCount64 > Deadline then
      begin
        Emit(Format('net host failed: %d of %d clients came', [Host.PendingJoinCount, Options.NetClients]));
        Exit(1);
      end;
      Host.Pump;
      NetInboxEvent.WaitFor(5);
    end;
    Host.HoldJoins := False;
    Host.Pump;
    CurrentScreenId := screenPlanet;
    RequestedScreenId := screenNone;
    for Day := 1 to Options.Turns do
    begin
      Plan := '';
      if HumanHoldsDay(LocalHuman) then
        PlayHumanTurn(LocalHuman, Galaxy.CurrentTurn, 1, Plan)
      else
        Plan := '.';
      Deadline := GetTickCount64 + StallTimeoutMs;
      repeat
        Host.Pump;
        if Host.PeersReady then
          Break;
        if GetTickCount64 > Deadline then
        begin
          Emit(Format('net host failed: day %d waits for humans %s', [Day, Host.WaitingFor]));
          Exit(1);
        end;
        NetInboxEvent.WaitFor(5);
      until False;
      Host.ApplyQueues;
      if not AllHumansEndedTurn then
      begin
        Emit(Format('net host failed: day %d cannot start after every peer was ready', [Day]));
        Exit(1);
      end;
      Host.BeginDay;
      ProbeFilmBytes := 0;
      StartPlayerStarTurnCalculation;
      WaitForTurnCalculation;
      RaisePendingWorkerError;
      FilmBytes := ProbeFilmBytes + Host.SendFilms;
      if (LocalPlayer <> nil) and not LocalPlayer.InHyperspace then
      begin
        StartGalaxyTurnCalculation;
        WaitForTurnCalculation;
        RaisePendingWorkerError;
      end;
      Job := Host.SendState(True);
      try
        StateBytes := Job.State.Bytes.DataSize;
        Deadline := GetTickCount64 + StallTimeoutMs;
        while not Job.Done do
        begin
          if GetTickCount64 > Deadline then
          begin
            Emit('net host failed: the state was not compressed');
            Exit(1);
          end;
          Host.Pump;
          NetInboxEvent.WaitFor(2);
        end;
        Emit(
            Format(
                'net host day=%d serial=%d hash=%s state=%d whole=%d delta=%d film=%d take=%d compress=%d humans=%d away=%d plan=%s',
                [Galaxy.CurrentTurn, Job.State.Serial, HashText(Job.State.Hash), StateBytes,
                    Job.WholeSize, Job.DeltaSize, FilmBytes, Host.LastTakeMs, Job.CompressMs,
                    Session.Humans.Count, AwayCount, Plan]
            )
        );
      finally
        Job.Free;
      end;
      // CHANGE: ENHANCEMENT - --sim-net-stop-at: once every client has the state, the host
      // stops hosting as the in-game menu does: the clients' humans are disconnected, then Bye.
      // The clients must notice it by themselves.
      if (Options.NetStopAt > 0) and (Day >= Options.NetStopAt) then
      begin
        Deadline := GetTickCount64 + StallTimeoutMs;
        while not Host.AllAcked(Host.LastSerial) do
        begin
          if GetTickCount64 > Deadline then
          begin
            Emit('net host failed: the clients did not take the state before the stop');
            Exit(1);
          end;
          Host.Pump;
          NetInboxEvent.WaitFor(5);
        end;
        Host.DisconnectHumans;
        // Counted before StopNetwork, which counts every human connected again.
        Away := AwayCount;
        Emit(Format('net host stopped hosting day=%d tick=%d', [Galaxy.CurrentTurn, GetTickCount64]));
        StopNetwork;
        Emit(
            Format(
                'done net host stopped days=%d humans=%d away=%d day=%d',
                [Day, Session.Humans.Count, Away, Galaxy.CurrentTurn]
            )
        );
        Exit(0);
      end;
    end;
    // The end: every client there has the last state, and as many as came at the start are
    // there (one that left may rejoin at the end).
    Deadline := GetTickCount64 + StallTimeoutMs;
    repeat
      Host.Pump;
      if (Host.JoinedCount >= Options.NetClients) and Host.AllAcked(Host.LastSerial) then
        Break;
      if GetTickCount64 > Deadline then
      begin
        Emit(Format('net host failed: %d clients at the end', [Host.JoinedCount]));
        Exit(1);
      end;
      NetInboxEvent.WaitFor(5);
    until False;
    Emit(
        Format(
            'done net host days=%d humans=%d day=%d hash=%s',
            [Options.Turns, Session.Humans.Count, Galaxy.CurrentTurn, HashText(GalaxyStateHash)]
        )
    );
  finally
    RemoveNetTalkProbe;
    ProbeSendsFilms := False;
    StopNetwork;
    NetLogHook := nil;
  end;
end;

// Decodes each film the host sent, as the star map would before playing it; returns the
// bytes and adds them to Count. OwnStar says whether one was of this client's star.
function TakeFilms(Client: TNetClient; var Count: Integer; out OwnStar: Boolean): Integer;
var
  Film: TNetClientFilm;
  Decoded: TEFilm;
begin
  Result := 0;
  OwnStar := False;
  Decoded := TEFilm.Create;
  try
    repeat
      Film := Client.TakeFilm;
      if Film = nil then
        Break;
      try
        Decoded.LoadFromBuffer(Film.Bytes);
        Inc(Result, Film.Bytes.DataSize);
        Inc(Count);
        if (LocalHuman <> nil) and (LocalHuman.PlayerStar <> nil)
            and (Film.Header.StarId = Integer(LocalHuman.PlayerStar.Id)) then
          OwnStar := True;
      finally
        Film.Free;
      end;
    until False;
  finally
    Decoded.Free;
  end;
end;

// The dialogue the host's day asks this client's human: the talk screen's first answer to a
// scripted talk is to agree (AcceptScriptedTalk), predicted here and sent to the host; then
// TalkDone. A talk about a ship this state does not have is declined, as the screens decline
// it; the screens also need the star map of the ship's star, which a headless client does not
// have. With Leave the client leaves instead; returns whether it did. Held says that the talk
// waited for the end of the client's film.
function AnswerTalk(Client: TNetClient; Leave, Held: Boolean): Boolean;
var
  Request: TTalkRequestMessage;
  Ship: TShip;
  Answered: Boolean;
  Age: Integer;
begin
  Result := False;
  Age := Client.TalkRequestAge;
  if not Client.TakeTalkRequest(Request) then
    Exit;
  if Leave then
  begin
    Client.Leave(5000);
    Emit(Format('net client left in a talk ship=%d human=%d', [Request.ShipId, Client.HumanId]));
    Exit(True);
  end;
  Ship := nil;
  if (Galaxy <> nil) and (Request.ShipId <> 0) then
    Ship := TShip(Galaxy.IdToShip(Cardinal(Request.ShipId), False));
  Answered :=
      (Request.HumanId = Client.HumanId)
          and (Request.PlanetId = 0)
          and (Ship <> nil)
          and (LocalPlayer <> nil);
  try
    if Answered then
    begin
      LocalHuman.TalkShip := Ship;
      LocalHuman.TalkPlanet := nil;
      LocalHuman.TalkScripted := Request.Scripted;
      LocalHuman.TalkType := Request.TalkType;
      LocalHuman.TalkAmount := Request.Amount;
      LocalHuman.TalkResponse := 0;
      LocalHuman.TalkText := Request.Text;
      if Request.Scripted then
        AcceptScriptedTalk;
      LocalHuman.TalkScripted := False;
    end;
  finally
    Client.SendTalkDone;
  end;
  Emit(
      Format(
          'net client talk ship=%d kind=%d answered=%d response=%d human=%d held=%d wait=%d',
          [Request.ShipId, Request.TalkType, Ord(Answered), LocalHuman.TalkResponse, Client.HumanId,
              Ord(Held), Age]
      )
  );
end;

const
  JoinPhaseNames: array[TNetJoinPhase] of AnsiString = ('connecting', 'joining', 'receiving', 'joined');

function RunNetClient(const Options: TSimulationOptions): Integer;
var
  Client: TNetClient;
  Address: AnsiString;
  Port, Colon, Days, Day, Mismatches, FilmBytes, FilmCount, LastPlayedDay, Index: Integer;
  Have, Size: Integer;
  Deadline, FilmUntil: QWord;
  Report: TNetApplyReport;
  Plan: AnsiString;
  Phase, ShownPhase: TNetJoinPhase;
  OwnFilm, FilmPlaying, TalkHeld: Boolean;
begin
  Result := 0;
  Colon := LastDelimiter(':', Options.NetJoin);
  Address := Copy(Options.NetJoin, 1, Colon - 1);
  Port := StrToInt(Copy(Options.NetJoin, Colon + 1, MaxInt));
  NetLogHook := @EmitNetEvent;
  Days := -1;
  Mismatches := 0;
  LastPlayedDay := -1;
  FilmBytes := 0;
  FilmCount := 0;
  FilmUntil := 0;
  TalkHeld := False;
  try
    // The connect runs on its own thread, as the game's join does; each phase is printed.
    Client := JoinGame(Address, Port, WideString(Options.NetName), False);
    ShownPhase := jpJoined;
    CurrentScreenId := screenPlanet;
    RequestedScreenId := screenNone;
    Deadline := GetTickCount64 + StallTimeoutMs;
    while not Client.HostLeft do
    begin
      Client.Pump;
      Phase := Client.JoinPhase;
      if (Days < 0) and (Phase <> ShownPhase) then
      begin
        Client.ReceiveProgress(Have, Size);
        Emit(Format('net client join phase=%s have=%d size=%d', [JoinPhaseNames[Phase], Have, Size]));
        ShownPhase := Phase;
      end;
      // A join cancelled once the host has let the client in, before the state is applied.
      if Options.NetCancelJoin and (Phase >= jpReceiving) then
      begin
        Client.ReceiveProgress(Have, Size);
        Emit(
            Format(
                'net client join cancelled phase=%s have=%d size=%d human=%d',
                [JoinPhaseNames[Phase], Have, Size, Client.HumanId]
            )
        );
        StopNetwork;
        Emit('done net client cancelled');
        Exit(0);
      end;
      FilmBytes := FilmBytes + TakeFilms(Client, FilmCount, OwnFilm);
      if OwnFilm and (Options.NetFilmMs > 0) then
        FilmUntil := GetTickCount64 + QWord(Options.NetFilmMs);
      // A dialogue that comes while the client plays its film waits for the film's end, as
      // the star map's wait at the film's end answers it (NetPlay).
      FilmPlaying := GetTickCount64 < FilmUntil;
      if Client.HasTalkRequest and Client.MayHoldTalk(FilmPlaying) then
        TalkHeld := True
      else if Client.HasTalkRequest then
      begin
        if AnswerTalk(Client, Options.NetTalkLeave, TalkHeld) then
          Break;
        TalkHeld := False;
      end;
      if not Client.HasState or FilmPlaying then
      begin
        if GetTickCount64 > Deadline then
        begin
          Emit('net client failed: no state from the host');
          Exit(1);
        end;
        NetInboxEvent.WaitFor(5);
        Continue;
      end;
      Report := Client.ApplyState;
      Inc(Days);
      if Report.Hash <> Report.HostHash then
        Inc(Mismatches);
      Emit(
          Format(
              'net client day=%d serial=%d hash=%s match=%d human=%d state=%d received=%d delta=%d film=%d films=%d load=%d',
              [Report.Day, Report.Serial, HashText(Report.Hash), Ord(Report.Hash = Report.HostHash),
                  Client.HumanId, Report.StateBytes, Report.ReceivedBytes, Ord(Report.Delta),
                  FilmBytes, FilmCount, Report.LoadMs]
          )
      );
      FilmBytes := 0;
      FilmCount := 0;
      if (Options.NetLeaveAt > 0) and (Days >= Options.NetLeaveAt) then
      begin
        Client.Leave(5000);
        Emit(Format('net client left day=%d human=%d', [Galaxy.CurrentTurn, Client.HumanId]));
        Break;
      end;
      // One turn a day: a state that comes again for the same day (another join) is only
      // applied.
      if HumanHoldsDay(LocalHuman) and (Galaxy.CurrentTurn <> LastPlayedDay) then
      begin
        Plan := '';
        Index := Session.Humans.IndexOf(LocalHuman) + 1;
        PlayHumanTurn(LocalHuman, Galaxy.CurrentTurn, Index, Plan);
        LastPlayedDay := Galaxy.CurrentTurn;
      end;
      Deadline := GetTickCount64 + StallTimeoutMs;
    end;
    if Client.Refused or (Client.Error <> '') then
    begin
      Emit('net client failed: ' + Client.Error);
      Result := 1;
    end
    // CHANGE: ENHANCEMENT - The host stopped hosting or quit: noticed by the pump, not by a
    // wait for something that never comes.
    else if Client.HostSaidBye then
      Emit(Format('net client host left bye=1 tick=%d', [GetTickCount64]));
    if Mismatches > 0 then
      Result := 1;
    if Galaxy <> nil then
      Day := Galaxy.CurrentTurn
    else
      Day := 0;
    Emit(
        Format(
            'done net client days=%d human=%d mismatches=%d day=%d',
            [Days, Client.HumanId, Mismatches, Day]
        )
    );
  finally
    StopNetwork;
    NetLogHook := nil;
  end;
end;

end.
