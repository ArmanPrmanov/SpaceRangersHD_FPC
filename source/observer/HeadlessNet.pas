{$EXCESSPRECISION OFF}
unit HeadlessNet;

// CHANGE: ENHANCEMENT - Networked play without a window, for tests (ROADMAP.md, Phase 5;
// docs/network.md, Tests). A host process loads a save, waits for its clients, and runs the
// days: its own human plays its turn, it waits for every client's end turn while pumping,
// applies their commands, runs the player-star job, sends the films, runs the galaxy job and
// sends the state. A client process joins, and each day plays the turn --sim-hotseat plays
// for its human, sends it, and waits for the film and the state. Both print one line per day
// with the state hash, the sizes and the load time.
interface
uses
  HeadlessSim;
function RunNetHost(const Options: TSimulationOptions): Integer;
function RunNetClient(const Options: TSimulationOptions): Integer;
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

function RunNetHost(const Options: TSimulationOptions): Integer;
var
  Host: TNetHost;
  Deadline: QWord;
  Day: Integer;
  Plan: AnsiString;
  Job: TNetStateJob;
  FilmBytes, StateBytes: Integer;
begin
  Result := 0;
  LoadSave(Options.SavePath, Options.Seed);
  Emit(Format('sim save=%s seed=%d day=%d', [Options.SavePath, Options.Seed, Galaxy.CurrentTurn]));
  NetLogHook := @EmitNetEvent;
  try
    Host := StartHosting(Options.NetHostPort, 'Host');
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
      StartPlayerStarTurnCalculation;
      WaitForTurnCalculation;
      RaisePendingWorkerError;
      FilmBytes := Host.SendFilms;
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
    StopNetwork;
    NetLogHook := nil;
  end;
end;

// Decodes each film the host sent, as the star map would before playing it; returns the
// bytes and counts them.
function TakeFilms(Client: TNetClient; out Count: Integer): Integer;
var
  Film: TNetClientFilm;
  Decoded: TEFilm;
begin
  Result := 0;
  Count := 0;
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
      finally
        Film.Free;
      end;
    until False;
  finally
    Decoded.Free;
  end;
end;

function RunNetClient(const Options: TSimulationOptions): Integer;
var
  Client: TNetClient;
  Address: AnsiString;
  Port, Colon, Days, Day, Mismatches, FilmBytes, FilmCount, LastPlayedDay, Index: Integer;
  Deadline: QWord;
  Report: TNetApplyReport;
  Plan: AnsiString;
begin
  Result := 0;
  Colon := LastDelimiter(':', Options.NetJoin);
  Address := Copy(Options.NetJoin, 1, Colon - 1);
  Port := StrToInt(Copy(Options.NetJoin, Colon + 1, MaxInt));
  NetLogHook := @EmitNetEvent;
  Days := -1;
  Mismatches := 0;
  LastPlayedDay := -1;
  try
    Client := JoinGame(Address, Port, WideString(Options.NetName));
    if not Client.Connected then
    begin
      Emit('net client failed: ' + Client.Error);
      Exit(1);
    end;
    CurrentScreenId := screenPlanet;
    RequestedScreenId := screenNone;
    Deadline := GetTickCount64 + StallTimeoutMs;
    while not Client.HostLeft do
    begin
      Client.Pump;
      if not Client.HasState then
      begin
        if GetTickCount64 > Deadline then
        begin
          Emit('net client failed: no state from the host');
          Exit(1);
        end;
        NetInboxEvent.WaitFor(5);
        Continue;
      end;
      FilmBytes := TakeFilms(Client, FilmCount);
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
      Result := 1;
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
