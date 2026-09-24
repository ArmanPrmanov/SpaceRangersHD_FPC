{$EXCESSPRECISION OFF}
unit CommandLog;

// CHANGE: ENHANCEMENT - Records a play session as commands and replays it headlessly
// (ROADMAP.md, Phase 3).
//
// A log is a list of records, in the order they changed the game:
// - Load: a save the player loaded, with its bytes. The log starts at the first load.
// - Command: a player command (aCommands) and the answers the UI gave to the simulation's
//   questions while it ran (SimEvents).
// - Job: a turn job, the answers given on the turn thread, and the commands the UI ran
//   while the turn thread waited for it (a conversation), wait by wait.
// - Checkpoint: the whole game state. The recorder hashes the state after each command and
//   job, and again before the next one. When the two differ, something that is not a command
//   changed the game; the recorder then writes the state so that the replay can go on, and
//   names the screen that was open. Their number measures what is still to be converted.
// Commands and jobs carry the hash of the state after them, so the replay reports the
// first record where it differs from the recording.
interface
type
  TReplayOptions = record
    LogPath: AnsiString;
    Seed: Cardinal;
    // Print every record, not only differences and the summary.
    Verbose: Boolean;
  end;
// Records from the next loaded save on, into Path.
procedure StartCommandRecording(const Path: AnsiString);
procedure StopCommandRecording;
function RunCommandReplay(const Options: TReplayOptions): Integer;
implementation
uses
  Windows,
  SysUtils,
  Classes,
  SyncObjs,
  EC_Buf,
  aMyFunction,
  Globals,
  GlobalsV,
  GR_Main,
  SimulationThread,
  SimEvents,
  ThreadCalc,
  aSession,
  aGalaxy,
  aShip,
  aCommands,
  aObjectRefs,
  aSaveLoad;

const
  LogMagic = $4C435253; // 'SRCL'
  LogVersion = 1;

type
  TRecordType = (rtLoad = 1, rtCommand = 2, rtJob = 3, rtCheckpoint = 4);

// Appends Source's bytes without a length.
procedure AppendRaw(Target, Source: TBufEC);
begin
  if Source.DataSize > 0 then
    Target.AddBytes(Source.Data, Source.DataSize);
end;

// Answers are written as (query, value); a ship is written by id.
procedure AddAnswer(Buffer: TBufEC; Query: TSimQuery; Value: PtrInt);
begin
  Buffer.AddByte(Ord(Query));
  if (Query = sqInspectedShip) and (Value <> 0) then
    Buffer.AddInt32(TShip(Value).Id)
  else
    Buffer.AddInt32(Integer(Value));
end;

{ Recorder }

type
  TRecorder = class
    Path: AnsiString;
    Stream: TFileStream;
    Lock: TCriticalSection;
    // Hash of the state after the last record; 0 before the first load.
    LastHash: QWord;
    // Something ran out of order; the next boundary writes a checkpoint.
    ResyncNeeded: Boolean;
    CommandDepth: Integer;
    CommandAnswers: TBufEC;
    CommandAnswerCount: Integer;
    // The job that is running, its answers, and its waits for the UI so far.
    JobRunning: Boolean;
    Job: TTurnCalculationJob;
    JobAnswers: TBufEC;
    JobAnswerCount: Integer;
    Waits: TBufEC;
    WaitCount: Integer;
    // The wait that is open: whether it is a conversation, and its commands.
    InWait: Boolean;
    WaitTalk: Boolean;
    WaitCommands: TBufEC;
    WaitCommandCount: Integer;
    // Commands the UI ran while a job ran without waiting for it.
    Concurrent: TBufEC;
    Checkpoints: Integer;
    constructor Create(const APath: AnsiString);
    destructor Destroy; override;
    procedure WriteRecord(RecordType: TRecordType; Payload: TBufEC);
    procedure Boundary;
    procedure WriteCheckpoint(const Reason: WideString);
    procedure GameLoaded(const FileName: WideString);
    procedure BeforeCommand(const Command: TPlayerCommand);
    procedure AfterCommand(const Command: TPlayerCommand);
    procedure JobStarting(AJob: TTurnCalculationJob);
    procedure JobFinished;
    procedure WaitChanged(Starting, Talk: Boolean);
    procedure Answer(Query: TSimQuery; Value: PtrInt);
  end;

var
  Recorder: TRecorder;

function CurrentHash: QWord;
begin
  if Galaxy = nil then
    Result := 0
  else
    Result := GalaxyStateHash;
end;

constructor TRecorder.Create(const APath: AnsiString);
begin
  Path := APath;
  Lock := TCriticalSection.Create;
  CommandAnswers := TBufEC.Create;
  JobAnswers := TBufEC.Create;
  Waits := TBufEC.Create;
  WaitCommands := TBufEC.Create;
  Concurrent := TBufEC.Create;
end;

destructor TRecorder.Destroy;
begin
  Stream.Free;
  Lock.Free;
  CommandAnswers.Free;
  JobAnswers.Free;
  Waits.Free;
  WaitCommands.Free;
  Concurrent.Free;
  inherited;
end;

procedure TRecorder.WriteRecord(RecordType: TRecordType; Payload: TBufEC);
var
  Header: packed record
    RecordType: Byte;
    Size: Integer;
  end;
begin
  if Stream = nil then
    Exit;
  Header.RecordType := Ord(RecordType);
  Header.Size := Payload.DataSize;
  Stream.WriteBuffer(Header, SizeOf(Header));
  if Payload.DataSize > 0 then
    Stream.WriteBuffer(Payload.Data^, Payload.DataSize);
end;

procedure TRecorder.WriteCheckpoint(const Reason: WideString);
var
  Payload, State: TBufEC;
begin
  Payload := TBufEC.Create;
  State := TBufEC.Create;
  try
    WriteGameCheckpoint(State);
    LastHash := CurrentHash;
    Payload.AddWideStringZ(Reason);
    Payload.AddInt32(State.DataSize);
    AppendRaw(Payload, State);
    Payload.AddBytes(@LastHash, 8);
    WriteRecord(rtCheckpoint, Payload);
    Inc(Checkpoints);
    AppendLogLineThreadSafe('Command log: checkpoint (' + UTF8Encode(Reason) + ')');
  finally
    Payload.Free;
    State.Free;
  end;
  ResyncNeeded := False;
end;

// Called on the UI thread before a command or a job, when no job runs.
procedure TRecorder.Boundary;
var
  Hash: QWord;
begin
  if (Stream = nil) or (Galaxy = nil) then
    Exit;
  Hash := CurrentHash;
  if ResyncNeeded or (Hash <> LastHash) then
    WriteCheckpoint('screen ' + IntToStr(Ord(CurrentScreenId)));
end;

procedure TRecorder.GameLoaded(const FileName: WideString);
var
  Payload: TBufEC;
  Save: TFileStream;
  Size: Integer;
begin
  Lock.Enter;
  try
    if Stream = nil then
    begin
      Stream := TFileStream.Create(Path, fmCreate);
      Payload := TBufEC.Create;
      try
        Payload.AddDWord(LogMagic);
        Payload.AddDWord(LogVersion);
        Stream.WriteBuffer(Payload.Data^, Payload.DataSize);
      finally
        Payload.Free
      end;
    end;
    Payload := TBufEC.Create;
    Save := TFileStream.Create(UTF8Encode(FileName), fmOpenRead or fmShareDenyWrite);
    try
      LastHash := CurrentHash;
      Payload.AddDWord(ChaoticRandomState);
      Payload.AddBytes(@LastHash, 8);
      Size := Save.Size;
      Payload.AddInt32(Size);
      Payload.SetSize(Payload.DataSize + Size);
      Save.ReadBuffer(PByte(Payload.Data)[Payload.DataSize - Size], Size);
      WriteRecord(rtLoad, Payload);
    finally
      Save.Free;
      Payload.Free;
    end;
    ResyncNeeded := False;
  finally
    Lock.Leave;
  end;
end;

procedure TRecorder.BeforeCommand(const Command: TPlayerCommand);
begin
  Lock.Enter;
  try
    Inc(CommandDepth);
    if CommandDepth > 1 then
      Exit;
    if not IsTurnCalculationRunning then
      Boundary;
    CommandAnswers.Clear;
    CommandAnswerCount := 0;
  finally
    Lock.Leave;
  end;
end;

procedure TRecorder.AfterCommand(const Command: TPlayerCommand);
var
  Payload: TBufEC;
  Hash: QWord;
begin
  Lock.Enter;
  try
    Dec(CommandDepth);
    if (CommandDepth > 0) or (Stream = nil) then
      Exit;
    Payload := TBufEC.Create;
    try
      EncodeCommand(Command, Payload);
      Payload.AddInt32(CommandAnswerCount);
      AppendRaw(Payload, CommandAnswers);
      if JobRunning then
        Hash := 0
      else
      begin
        Hash := CurrentHash;
        LastHash := Hash;
      end;
      Payload.AddBytes(@Hash, 8);
      if not JobRunning then
        WriteRecord(rtCommand, Payload)
      else if InWait then
      begin
        WaitCommands.AddInt32(Payload.DataSize);
        AppendRaw(WaitCommands, Payload);
        Inc(WaitCommandCount);
      end
      else
      begin
        // The replay cannot run this at the same point; it runs it after the job, and the
        // next boundary resynchronises.
        Concurrent.AddInt32(Payload.DataSize);
        AppendRaw(Concurrent, Payload);
        AppendLogLineThreadSafe(
            'Command log: ' + CommandKindName(Command.Kind) + ' ran during a turn job'
        );
      end;
    finally
      Payload.Free
    end;
  finally
    Lock.Leave;
  end;
end;

procedure TRecorder.JobStarting(AJob: TTurnCalculationJob);
begin
  Lock.Enter;
  try
    if Stream = nil then
      Exit;
    Boundary;
    JobRunning := True;
    Job := AJob;
    JobAnswers.Clear;
    JobAnswerCount := 0;
    Waits.Clear;
    WaitCount := 0;
    Concurrent.Clear;
  finally
    Lock.Leave;
  end;
end;

// On the turn thread, while the UI still waits for the job.
procedure TRecorder.JobFinished;
var
  Payload: TBufEC;
  Hash: QWord;
  Size: Integer;
begin
  Lock.Enter;
  try
    if not JobRunning then
      Exit;
    JobRunning := False;
    Payload := TBufEC.Create;
    try
      Hash := CurrentHash;
      LastHash := Hash;
      Payload.AddByte(Ord(Job));
      Payload.AddInt32(JobAnswerCount);
      AppendRaw(Payload, JobAnswers);
      Payload.AddInt32(WaitCount);
      AppendRaw(Payload, Waits);
      Payload.AddBytes(@Hash, 8);
      WriteRecord(rtJob, Payload);
      Concurrent.SetPosition(0);
      while not Concurrent.IsAtEnd do
      begin
        Size := Concurrent.GetInt32;
        Payload.Clear;
        Payload.SetSize(Size);
        Concurrent.ReadBytes(Payload.Data, Size);
        WriteRecord(rtCommand, Payload);
        ResyncNeeded := True;
      end;
      Concurrent.Clear;
    finally
      Payload.Free
    end;
  finally
    Lock.Leave;
  end;
end;

procedure TRecorder.WaitChanged(Starting, Talk: Boolean);
begin
  Lock.Enter;
  try
    if not JobRunning then
      Exit;
    if Starting then
    begin
      InWait := True;
      WaitTalk := Talk;
      WaitCommands.Clear;
      WaitCommandCount := 0;
    end
    else if InWait then
    begin
      InWait := False;
      Waits.AddBoolean(WaitTalk);
      Waits.AddInt32(WaitCommandCount);
      AppendRaw(Waits, WaitCommands);
      Inc(WaitCount);
    end;
  finally
    Lock.Leave;
  end;
end;

procedure TRecorder.Answer(Query: TSimQuery; Value: PtrInt);
begin
  Lock.Enter;
  try
    if InTurnJob then
    begin
      if JobRunning then
      begin
        AddAnswer(JobAnswers, Query, Value);
        Inc(JobAnswerCount);
      end;
    end
    else if CommandDepth > 0 then
    begin
      AddAnswer(CommandAnswers, Query, Value);
      Inc(CommandAnswerCount);
    end;
  finally
    Lock.Leave;
  end;
end;

procedure RecorderGameLoaded(const FileName: WideString);
begin
  Recorder.GameLoaded(FileName);
end;

procedure RecorderBeforeCommand(const Command: TPlayerCommand);
begin
  Recorder.BeforeCommand(Command);
end;

procedure RecorderAfterCommand(const Command: TPlayerCommand);
begin
  Recorder.AfterCommand(Command);
end;

procedure RecorderJob(Job: TTurnCalculationJob; Starting: Boolean);
begin
  if Starting then
    Recorder.JobStarting(Job)
  else
    Recorder.JobFinished;
end;

procedure RecorderWait(Starting, Talk: Boolean);
begin
  Recorder.WaitChanged(Starting, Talk);
end;

procedure RecorderAnswer(Query: TSimQuery; var Value: PtrInt);
begin
  Recorder.Answer(Query, Value);
end;

procedure StartCommandRecording(const Path: AnsiString);
begin
  StopCommandRecording;
  Recorder := TRecorder.Create(Path);
  GameLoadedHook := @RecorderGameLoaded;
  BeforeCommandHook := @RecorderBeforeCommand;
  AfterCommandHook := @RecorderAfterCommand;
  TurnJobHook := @RecorderJob;
  TurnWaitHook := @RecorderWait;
  QueryAnswerHook := @RecorderAnswer;
end;

procedure StopCommandRecording;
begin
  if Recorder = nil then
    Exit;
  GameLoadedHook := nil;
  BeforeCommandHook := nil;
  AfterCommandHook := nil;
  TurnJobHook := nil;
  TurnWaitHook := nil;
  QueryAnswerHook := nil;
  FreeAndNil(Recorder);
end;

{ Replay }

type
  TAnswer = record
    Query: TSimQuery;
    Value: Integer;
  end;
  TAnswerList = record
    Items: array of TAnswer;
    Next: Integer;
  end;

var
  // The answers the running command and the running job gave in the recording.
  CommandReplayAnswers: TAnswerList;
  JobReplayAnswers: TAnswerList;
  ReplayingCommand: Boolean;
  AnswerMismatches: Integer;

procedure ReadAnswers(Buffer: TBufEC; var List: TAnswerList);
var
  I: Integer;
begin
  SetLength(List.Items, Buffer.GetInt32);
  List.Next := 0;
  for I := 0 to High(List.Items) do
  begin
    List.Items[I].Query := TSimQuery(Buffer.GetByte);
    List.Items[I].Value := Buffer.GetInt32;
  end;
end;

procedure TakeAnswer(var List: TAnswerList; Query: TSimQuery; var Value: PtrInt);
begin
  if (List.Next > High(List.Items)) or (List.Items[List.Next].Query <> Query) then
  begin
    // The replay asks something the recording did not: it has diverged already.
    Inc(AnswerMismatches);
    Exit;
  end;
  if Query = sqInspectedShip then
    Value := PtrInt(Galaxy.IdToShip(Cardinal(List.Items[List.Next].Value), False))
  else
    Value := List.Items[List.Next].Value;
  Inc(List.Next);
end;

procedure ReplayAnswer(Query: TSimQuery; var Value: PtrInt);
begin
  if InTurnJob then
    TakeAnswer(JobReplayAnswers, Query, Value)
  else if ReplayingCommand then
    TakeAnswer(CommandReplayAnswers, Query, Value);
end;

type
  TReplay = class
    Options: TReplayOptions;
    Index: Integer;
    Commands, Jobs, Loads, Checkpoints, Differences, DriftAfterCheckpoint: Integer;
    // A checkpoint does not restore everything the live game held (see
    // ReadGameCheckpoint), so later differences may be drift rather than a regression.
    AfterCheckpoint: Boolean;
    procedure Emit(const Line: AnsiString);
    procedure Compare(const What: AnsiString; Expected: QWord);
    procedure ReplayCommand(Buffer: TBufEC);
    procedure ReplayLoad(Buffer: TBufEC);
    procedure ReplayCheckpoint(Buffer: TBufEC);
    procedure ReplayJob(Buffer: TBufEC);
  end;

procedure TReplay.Emit(const Line: AnsiString);
begin
  WriteLn(Line);
  Flush(Output);
end;

procedure TReplay.Compare(const What: AnsiString; Expected: QWord);
var
  Actual: QWord;
begin
  if Expected = 0 then
  begin
    if Options.Verbose then
      Emit(Format('record %d %s', [Index, What]));
    Exit;
  end;
  Actual := CurrentHash;
  if Actual = Expected then
  begin
    if Options.Verbose then
      Emit(Format('record %d %s hash=%s', [Index, What, IntToHex(Actual, 16)]));
    Exit;
  end;
  if AfterCheckpoint then
  begin
    Inc(DriftAfterCheckpoint);
    Emit(
        Format(
            'drift record=%d %s day=%d expected=%s actual=%s',
            [Index, What, Galaxy.CurrentTurn, IntToHex(Expected, 16), IntToHex(Actual, 16)]
        )
    );
  end
  else
  begin
    Inc(Differences);
    Emit(
        Format(
            'diverged record=%d %s day=%d expected=%s actual=%s',
            [Index, What, Galaxy.CurrentTurn, IntToHex(Expected, 16), IntToHex(Actual, 16)]
        )
    );
  end;
end;

procedure ReadHash(Buffer: TBufEC; out Hash: QWord);
begin
  Buffer.ReadBytes(@Hash, 8);
end;

procedure TReplay.ReplayCommand(Buffer: TBufEC);
var
  Command: TPlayerCommand;
  Hash: QWord;
begin
  Command := DecodeCommand(Buffer);
  ReadAnswers(Buffer, CommandReplayAnswers);
  ReadHash(Buffer, Hash);
  ReplayingCommand := True;
  try
    ExecuteCommand(Command);
  finally
    ReplayingCommand := False;
  end;
  Inc(Commands);
  Compare('command ' + CommandKindName(Command.Kind), Hash);
end;

procedure TReplay.ReplayLoad(Buffer: TBufEC);
var
  Chaotic: Cardinal;
  Hash: QWord;
  Size: Integer;
  FileName: AnsiString;
  Save: TFileStream;
begin
  Chaotic := Buffer.GetUInt32;
  ReadHash(Buffer, Hash);
  Size := Buffer.GetInt32;
  FileName := GetTempDir(False) + 'rangers-replay-' + IntToStr(GetProcessID) + '.sav';
  Save := TFileStream.Create(FileName, fmCreate);
  try
    Save.WriteBuffer(PByte(Buffer.Data)[Buffer.Position], Size);
  finally
    Save.Free
  end;
  try
    if not LoadGameFromFile(UTF8Decode(FileName)) then
      raise Exception.Create('Load failed: ' + UTF8Encode(LastSaveLoadError));
  finally
    DeleteFile(FileName);
  end;
  WaitForTurnCalculation;
  System.RandSeed := Integer(Options.Seed);
  ChaoticRandomState := Chaotic;
  CurrentScreenId := screenPlanet;
  RequestedScreenId := screenNone;
  Inc(Loads);
  AfterCheckpoint := False;
  Compare(Format('load day=%d', [Galaxy.CurrentTurn]), Hash);
end;

procedure TReplay.ReplayCheckpoint(Buffer: TBufEC);
var
  Reason: WideString;
  Size: Integer;
  State: TBufEC;
  Hash: QWord;
begin
  Reason := Buffer.ReadWideString;
  Size := Buffer.GetInt32;
  State := TBufEC.Create;
  try
    State.SetSize(Size);
    Buffer.ReadBytes(State.Data, Size);
    State.SetPosition(0);
    ReadGameCheckpoint(State);
  finally
    State.Free
  end;
  ReadHash(Buffer, Hash);
  Inc(Checkpoints);
  Emit(Format('checkpoint record=%d day=%d %s', [Index, Galaxy.CurrentTurn, UTF8Encode(Reason)]));
  // The state written must load back to the same hash.
  AfterCheckpoint := False;
  Compare('checkpoint', Hash);
  AfterCheckpoint := True;
end;

procedure TReplay.ReplayJob(Buffer: TBufEC);
var
  Job: TTurnCalculationJob;
  Hash: QWord;
  I, WaitCount, CommandCount, Size, Next: Integer;
  WaitTalk: array of Boolean;
  WaitCommands: array of TBufEC;
  Handles: array[0..1] of THandle;
  Command: TBufEC;
begin
  Job := TTurnCalculationJob(Buffer.GetByte);
  ReadAnswers(Buffer, JobReplayAnswers);
  WaitCount := Buffer.GetInt32;
  SetLength(WaitTalk, WaitCount);
  SetLength(WaitCommands, WaitCount);
  try
    for I := 0 to WaitCount - 1 do
    begin
      WaitTalk[I] := Buffer.GetBoolean;
      CommandCount := Buffer.GetInt32;
      WaitCommands[I] := TBufEC.Create;
      WaitCommands[I].AddInt32(CommandCount);
      while CommandCount > 0 do
      begin
        Size := Buffer.GetInt32;
        WaitCommands[I].AddInt32(Size);
        WaitCommands[I].SetSize(WaitCommands[I].DataSize + Size);
        Buffer.ReadBytes(@PByte(WaitCommands[I].Data)[WaitCommands[I].DataSize - Size], Size);
        Dec(CommandCount);
      end;
    end;
    ReadHash(Buffer, Hash);
    case Job of
      tcjGalaxy: StartGalaxyTurnCalculation;
      tcjPlayerStar: StartPlayerStarTurnCalculation;
      tcjPreparePlayerStar: StartPlayerStarPreparation;
    end;
    Next := 0;
    Handles[0] := Session.TurnCalculationThread.IdleEvent;
    Handles[1] := Session.TalkRequestEvent;
    // The job asks for a conversation the way it did in the recording; answer it with the
    // commands the UI ran then.
    while WaitForMultipleObjects(2, @Handles[0], False, INFINITE) = WAIT_OBJECT_0 + 1 do
    begin
      ResetEvent(Session.TalkRequestEvent);
      while (Next < WaitCount) and not WaitTalk[Next] do
        Inc(Next);
      if Next < WaitCount then
      begin
        Command := WaitCommands[Next];
        Command.SetPosition(0);
        CommandCount := Command.GetInt32;
        for I := 1 to CommandCount do
        begin
          Command.GetInt32;
          ReplayCommand(Command);
        end;
        Inc(Next);
      end
      else
        Emit(Format('record %d: the job asked for a conversation the recording lacks', [Index]));
      SetEvent(Session.TalkCompletedEvent);
    end;
    WaitForTurnCalculation;
  finally
    for I := 0 to High(WaitCommands) do
      WaitCommands[I].Free;
  end;
  Inc(Jobs);
  Compare(Format('job %d day=%d', [Ord(Job), Galaxy.CurrentTurn]), Hash);
end;

function RunCommandReplay(const Options: TReplayOptions): Integer;
var
  Stream: TFileStream;
  Header: packed record
    RecordType: Byte;
    Size: Integer;
  end;
  Magic, Version: Cardinal;
  Payload: TBufEC;
  Replay: TReplay;
begin
  Replay := TReplay.Create;
  Payload := TBufEC.Create;
  Stream := TFileStream.Create(Options.LogPath, fmOpenRead or fmShareDenyWrite);
  QueryAnswerHook := @ReplayAnswer;
  try
    Replay.Options := Options;
    Stream.ReadBuffer(Magic, 4);
    Stream.ReadBuffer(Version, 4);
    if (Magic <> LogMagic) or (Version <> LogVersion) then
      raise Exception.Create('Not a command log of this version: ' + Options.LogPath);
    Replay.Emit('replay log=' + Options.LogPath);
    while Stream.Position < Stream.Size do
    begin
      Stream.ReadBuffer(Header, SizeOf(Header));
      Payload.Clear;
      Payload.SetSize(Header.Size);
      if Header.Size > 0 then
        Stream.ReadBuffer(Payload.Data^, Header.Size);
      Payload.SetPosition(0);
      Inc(Replay.Index);
      case TRecordType(Header.RecordType) of
        rtLoad: Replay.ReplayLoad(Payload);
        rtCommand: Replay.ReplayCommand(Payload);
        rtJob: Replay.ReplayJob(Payload);
        rtCheckpoint: Replay.ReplayCheckpoint(Payload);
      else
        raise Exception.CreateFmt('Unknown record type %d', [Header.RecordType]);
      end;
    end;
    Replay.Emit(
        Format(
            'done records=%d loads=%d commands=%d jobs=%d checkpoints=%d diverged=%d drift=%d'
                + ' answer-mismatches=%d day=%d hash=%s',
            [Replay.Index, Replay.Loads, Replay.Commands, Replay.Jobs, Replay.Checkpoints,
                Replay.Differences, Replay.DriftAfterCheckpoint, AnswerMismatches,
                Galaxy.CurrentTurn, IntToHex(CurrentHash, 16)]
        )
    );
    if Replay.Differences > 0 then
      Result := 1
    else
      Result := 0;
  finally
    QueryAnswerHook := nil;
    Stream.Free;
    Payload.Free;
    Replay.Free;
  end;
end;

finalization
  StopCommandRecording;
end.
