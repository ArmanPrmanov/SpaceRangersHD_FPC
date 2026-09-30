{$EXCESSPRECISION OFF}
unit ThreadCalc;
{$R-}
{$Q-}
{$B-}
{$A8}
interface
uses
  EC_Thread;
type
  TThreadCalc = class;
  {$Z4}
  TTurnCalculationJob = (tcjGalaxy = 1, tcjPlayerStar = 2, tcjPreparePlayerStar = 3);
  {$Z4}
  TTurnCalculationPhase = (
      tcpIdle = 0,
      tcpGalaxyRunning = 1,
      tcpGalaxyFinished = 2,
      tcpPlayerStarRunning = 3,
      tcpPlayerStarFinished = 4,
      tcpPlayerStarPreparationRunning = 5,
      tcpPlayerStarPrepared = 6,
      tcpNotStarted = 4294967295
  );
  TThreadCalc = class(TThreadEC)
    Job: TTurnCalculationJob;
    procedure Execute; override;
    procedure RunJob;
  end;
  // Told when a job starts (on the thread that starts it) and when it has finished (on the
  // turn thread, before the job counts as idle).
  TTurnJobHook = procedure(Job: TTurnCalculationJob; Starting: Boolean);
  // CHANGE: ENHANCEMENT - Told on the turn thread, in the player-star job, after each filmed
  // star's day with the film it recorded (Recorded: whether the day was filmed), while no other
  // thread uses the film. A host encodes the films its clients need here (ROADMAP.md, Phase 5;
  // docs/network.md, Films).
  TStarDayHook = procedure(Star: TObject; Film: TObject; Recorded: Boolean);
  // CHANGE: ENHANCEMENT - Told on the turn thread when the player-star job has run the day,
  // after StartDayRound.
  TDayCompletedHook = procedure;
var
  AdaptiveBeginCalcNextTurn: Single = 0.5;
  LastGalaxyTurnDuration: Integer;
  TurnJobHook: TTurnJobHook;
  StarDayHook: TStarDayHook;
  DayCompletedHook: TDayCompletedHook;
  // CHANGE: ENHANCEMENT - A networked client never runs a job: the host runs every day
  // (ROADMAP.md, Phase 5; docs/network.md). Starting one then is a bug, and raises.
  TurnJobsForbidden: Boolean;
procedure StartGalaxyTurnCalculation;
procedure StartPlayerStarTurnCalculation;
procedure StartPlayerStarPreparation;
function IsTurnCalculationRunning: Boolean;
procedure WaitForTurnCalculation;
procedure ProcessPlayerStarTurn;
implementation
uses
  aSession,
  aHuman,
  SimulationThread,
  SimEvents,
  aCalc,
  Windows,
  MMSystem,
  SysUtils,
  Math,
  Globals,
  GlobalsV,
  GR_Main,
  aGalaxy,
  aPlayer,
  aShip,
  aEFilm,
  aStarFilms,
  Classes;
procedure StartJob(Job: TTurnCalculationJob);
begin
  if TurnJobsForbidden then
    raise Exception.Create('A networked client never runs a turn job');
  if Assigned(TurnJobHook) then
    TurnJobHook(Job, True);
  Session.TurnCalculationThread.Job := Job;
  Session.TurnCalculationThread.Start;
end;
procedure StartGalaxyTurnCalculation;
begin
  StartJob(tcjGalaxy);
end;
procedure StartPlayerStarTurnCalculation;
begin
  StartJob(tcjPlayerStar);
end;
procedure StartPlayerStarPreparation;
begin
  StartJob(tcjPreparePlayerStar);
end;
function IsTurnCalculationRunning: Boolean;
begin
  if Session.TurnCalculationThread = nil then
    Result := False
  else
    Result := Session.TurnCalculationThread.IsRunning;
end;
procedure WaitForTurnCalculation;
begin
  // CHANGE: FIX - The job itself may call this: a remote human's answer to a talk runs on
  // the turn thread (NetHost.RemoteTalk), and leaving the talk waits for the job it is in.
  if (Session.TurnCalculationThread <> nil)
      and not Session.TurnCalculationThread.IsCurrentThread
      and Session.TurnCalculationThread.IsRunning then
    Session.TurnCalculationThread.WaitForIdle(INFINITE);
end;
// CHANGE: ENHANCEMENT - Every star that holds a human runs its day in the player-star job,
// with a film of its own (ROADMAP.md, Phase 4). The local human's star records into
// PrimaryFilm as before; the others record into aStarFilms.
function FilmOfStar(Star: TStar): TEFilm;
begin
  if Star = LocalHuman.PlayerStar then
    Result := PrimaryFilm
  else
    Result := StarFilm(Star);
end;

// Whether Star's day is recorded: a human there is in normal space, taking off, or just
// entering hyperspace.
function StarRecordsFilm(Star: TStar): Boolean;
var
  I: Integer;
  Human: THuman;
  P: TPlayer;
begin
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Human := Session.Humans[I];
    P := Human.Player;
    if (Human.PlayerStar = Star)
        and (P <> nil)
        and (P.InNormalSpace
            or ((P.Order = soTakeoff) and ((P.CurrentPlanet <> nil) or (P.DockedTo <> nil)))
            or (P.InHyperspace and (Cardinal(P.OrderStateData and $FFFF) <= 1))) then
      Exit(True);
  end;
  Result := False;
end;

procedure ProcessPlayerStarTurn;
var
  RecordFilm, LocalRecordFilm: Boolean;
  Stage, I: Integer;
  Stars: TList;
  Star: TStar;
  SavedFilm: TEFilm;
begin
  Stage := 0;
  Stars := TList.Create;
  try
    CollectFilmedStars(Stars);
    KeepStarFilms(Stars);
    LocalRecordFilm := False;
    for I := 0 to Stars.Count - 1 do
    begin
      Star := TStar(Stars[I]);
      SavedFilm := PrimaryFilm;
      PrimaryFilm := FilmOfStar(Star);
      try
        if not Session.PlayerStarDayPrepared then
          PrimaryFilm.Clear;
        Stage := 1;
        RecordFilm := StarRecordsFilm(Star);
        if Star = LocalHuman.PlayerStar then
          LocalRecordFilm := RecordFilm;
        Star.NextDay(RecordFilm);
        if Assigned(StarDayHook) then
          StarDayHook(Star, PrimaryFilm, RecordFilm);
      finally
        PrimaryFilm := SavedFilm;
      end;
    end;
    Stage := 2;
    if Galaxy.StasisModEnabled <> 1 then
      Galaxy.CompleteDay(LocalRecordFilm);
    Stage := 3;
    Galaxy.TransferShipsInTransit;
    Stage := 4;
    Session.PlayerStarDayPrepared := False;
    // CHANGE: ENHANCEMENT - The day has run: every human holds the next one again (the end-turn
    // barrier, ROADMAP.md, Phase 4, item 2).
    StartDayRound;
    if Assigned(DayCompletedHook) then
      DayCompletedHook;
  except
    on E: Exception do
    begin
      AppendLogLineThreadSafe(E.ClassName + ' ' + E.Message);
      LogExceptionBackTrace;
      NotifyTurnFailed;
      raise Exception.Create('Error in procedure ThCa label = ' + IntToStr(Stage));
    end;
  end;
  Stars.Free;
end;

// Prepares the next day of every filmed star while the last one's film plays.
procedure PrepareFilmedStars;
var
  I: Integer;
  Stars: TList;
  Star: TStar;
  SavedFilm: TEFilm;
begin
  Stars := TList.Create;
  try
    CollectFilmedStars(Stars);
    KeepStarFilms(Stars);
    // The local film is cleared even when no star is filmed, as before.
    PrimaryFilm.Clear;
    for I := 0 to Stars.Count - 1 do
    begin
      Star := TStar(Stars[I]);
      SavedFilm := PrimaryFilm;
      PrimaryFilm := FilmOfStar(Star);
      try
        PrimaryFilm.Clear;
        if Galaxy.StasisModEnabled <> 1 then
          Star.PrepareNextDay;
      finally
        PrimaryFilm := SavedFilm;
      end;
    end;
  finally
    Stars.Free;
  end;
end;
// CHANGE: ENHANCEMENT - Mark the turn job for the debug thread check.
procedure TThreadCalc.Execute;
begin
  InTurnJob := True;
  TurnJobRunning := True;
  try
    RunJob;
    if Assigned(TurnJobHook) then
      TurnJobHook(Job, False);
  finally
    TurnJobRunning := False;
    InTurnJob := False;
  end;
end;

procedure TThreadCalc.RunJob;
var
  ControlWord: Word;

  StartTick, EndTick: Cardinal;

  FrameMs: Integer;
begin

  // ARM64 threads use the same nontrapping round-to-nearest policy.
  SetExceptionMask(
      [exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]
  );
  SetRoundMode(rmNearest);
  if Job = tcjGalaxy then
  begin
    TurnCalculationPhase := tcpGalaxyRunning;
    if Galaxy.StasisModEnabled <> 1 then
      try
        if (LocalPlayer <> nil) and LocalPlayer.InNormalSpace then
        begin
          StartTick := timeGetTime;
          Galaxy.NextDay;
          EndTick := timeGetTime;
          LastGalaxyTurnDuration := EndTick - StartTick;
          if FilmSpeed = 0 then
            FrameMs := 16
          else if FilmSpeed = 1 then
            FrameMs := 12
          else
            FrameMs := 8;
          AdaptiveBeginCalcNextTurn :=
              Math.Min(
                  0.9,
                  (AdaptiveBeginCalcNextTurn
                          + 1
                          - Math.Min(1, (LastGalaxyTurnDuration + 100) / (200 * FrameMs)))
                      / 2
              );
        end
        else
          Galaxy.NextDay;
        Galaxy.TransferShipsInTransit;
      except
        on E: Exception do
        begin
          AppendLogLineThreadSafe(E.ClassName + ' ' + E.Message);
          LogExceptionBackTrace;
          AppendLogLineThreadSafe('ThreadCalc exception 1');
          if Galaxy.CurrentTurn < 300 then
            AppendLogLineThreadSafe(
                'Galaxy create exception, seed = ' + IntToStr(Integer(Galaxy.GenerationSeed))
            );
          SetEvent(IdleEvent);
          raise;
        end;
      end;
    TurnCalculationPhase := tcpGalaxyFinished;
  end
  else if Job = tcjPlayerStar then
  begin
    TurnCalculationPhase := tcpPlayerStarRunning;
    try
      ProcessPlayerStarTurn;
    except
      on E: Exception do
      begin
        AppendLogLineThreadSafe(E.ClassName + ' ' + E.Message);
        LogExceptionBackTrace;
        AppendLogLineThreadSafe('ThreadCalc exception 2');
        if Galaxy.CurrentTurn < 300 then
          AppendLogLineThreadSafe(
              'Galaxy create exception, seed = ' + IntToStr(Integer(Galaxy.GenerationSeed))
          );
        SetEvent(IdleEvent);
        raise;
      end;
    end;
    TurnCalculationPhase := tcpPlayerStarFinished;
  end
  else
  begin
    TurnCalculationPhase := tcpPlayerStarPreparationRunning;
    Session.PlayerStarDayPrepared := True;
    try
      PrepareFilmedStars;
    except
      on E: Exception do
      begin
        AppendLogLineThreadSafe(E.ClassName + ' ' + E.Message);
        LogExceptionBackTrace;
        AppendLogLineThreadSafe('ThreadCalc exception 3');
        if Galaxy.CurrentTurn < 300 then
          AppendLogLineThreadSafe(
              'Galaxy create exception, seed = ' + IntToStr(Integer(Galaxy.GenerationSeed))
          );
        SetEvent(IdleEvent);
        raise;
      end;
    end;
    TurnCalculationPhase := tcpPlayerStarPrepared;
  end;

end;
end.
