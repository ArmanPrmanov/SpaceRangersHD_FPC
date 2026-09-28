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
// - Local: hot-seat passed the screen to another human (aHuman.SetLocalHuman). It is not a
//   command: it changes only whose screen this is, but the save, and so the hash, starts with
//   the local human.
// Commands and jobs carry the hash of the state after them, so the replay reports the
// first record where it differs from the recording.
//
// Hot-seat (ROADMAP.md, Phase 4): the replay can take one log per human, as
// tools/split_commands.py writes them from one recording. Each such log holds its human's
// commands and a copy of every other record (loads, jobs, checkpoints, local changes), which
// are the points where the logs meet. Between two such points the replay applies each
// human's commands in Session.Humans order, the hot-seat order, then the next shared record
// (RunMergedReplay). A day's job must find every human's end turn (the end-turn barrier).
interface
type
  TReplayOptions = record
    // One log, several separated by commas, or a directory of *.srcl logs; several logs are
    // one per human and are merged.
    LogPath: AnsiString;
    Seed: Cardinal;
    // Print every record, not only differences and the summary.
    Verbose: Boolean;
  end;
// Records from the next loaded save on, into Path.
procedure StartCommandRecording(const Path: AnsiString);
procedure StopCommandRecording;
// CHANGE: BUGFIX - The commands the recorder has open (0 between two commands, and when it does
// not record); for the unit tests.
function RecordingCommandDepth: Integer;
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
  aHuman,
  aObjectRefs,
  aSaveLoad;

const
  LogMagic = $4C435253; // 'SRCL'
  LogVersion = 1;

type
  TRecordType = (rtLoad = 1, rtCommand = 2, rtJob = 3, rtCheckpoint = 4, rtLocal = 5);

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
    procedure CommandFailed(const Command: TPlayerCommand);
    procedure JobStarting(AJob: TTurnCalculationJob);
    procedure JobFinished;
    procedure WaitChanged(Starting, Talk: Boolean);
    procedure Answer(Query: TSimQuery; Value: PtrInt);
    procedure LocalChanged(Human: THuman; Before: Boolean);
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

// CHANGE: BUGFIX - A command that raised is not recorded: the replay would raise as well.
// Whatever it changed before it raised is not a command, so the next boundary writes a
// checkpoint. Without this the depth stayed raised and no later command was recorded.
procedure TRecorder.CommandFailed(const Command: TPlayerCommand);
begin
  Lock.Enter;
  try
    Dec(CommandDepth);
    if CommandDepth > 0 then
      Exit;
    CommandAnswers.Clear;
    CommandAnswerCount := 0;
    if Stream = nil then
      Exit;
    ResyncNeeded := True;
    AppendLogLineThreadSafe(
        'Command log: ' + CommandKindName(Command.Kind) + ' failed and is not recorded'
    );
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

// Before the change, whatever changed the game since the last record is written as a
// checkpoint; after it, the new local human and the hash.
procedure TRecorder.LocalChanged(Human: THuman; Before: Boolean);
var
  Payload: TBufEC;
  Hash: QWord;
begin
  Lock.Enter;
  try
    if (Stream = nil) or JobRunning then
      Exit;
    if Before then
    begin
      Boundary;
      Exit;
    end;
    Payload := TBufEC.Create;
    try
      Hash := CurrentHash;
      LastHash := Hash;
      Payload.AddInt32(Human.Id);
      Payload.AddBytes(@Hash, 8);
      WriteRecord(rtLocal, Payload);
    finally
      Payload.Free
    end;
  finally
    Lock.Leave;
  end;
end;

procedure RecorderLocalChanged(Human: THuman; Before: Boolean);
begin
  Recorder.LocalChanged(Human, Before);
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

procedure RecorderCommandFailed(const Command: TPlayerCommand);
begin
  Recorder.CommandFailed(Command);
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
  CommandFailedHook := @RecorderCommandFailed;
  TurnJobHook := @RecorderJob;
  TurnWaitHook := @RecorderWait;
  QueryAnswerHook := @RecorderAnswer;
  LocalHumanHook := @RecorderLocalChanged;
end;

procedure StopCommandRecording;
begin
  if Recorder = nil then
    Exit;
  GameLoadedHook := nil;
  BeforeCommandHook := nil;
  AfterCommandHook := nil;
  CommandFailedHook := nil;
  TurnJobHook := nil;
  TurnWaitHook := nil;
  QueryAnswerHook := nil;
  LocalHumanHook := nil;
  FreeAndNil(Recorder);
end;

function RecordingCommandDepth: Integer;
begin
  if Recorder = nil then
    Result := 0
  else
    Result := Recorder.CommandDepth;
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
    // CHANGE: ENHANCEMENT - A log recorded without a network session (hot-seat) never asked
    // whether a remote human can be asked: nobody remote was.
    if Query = sqRemoteTalk then
    begin
      Value := 0;
      Exit;
    end;
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

// CHANGE: ENHANCEMENT - The job asks a remote human something as the host's did (the recorded
// sqRemoteTalk answers say whom and whether it answered; docs/network.md, Remote dialogue).
// The host ran that human's commands inside the talk's wait, so the log holds them as a
// conversation's; the replay answers it as a local one's (ReplayJob).
function ReplayRemoteTalk(Human: THuman): Boolean;
begin
  ResetEvent(Session.TalkCompletedEvent);
  SetEvent(Session.TalkRequestEvent);
  WaitForSingleObject(Session.TalkCompletedEvent, INFINITE);
  Result := True;
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
    procedure ReplayLocal(Buffer: TBufEC);
    procedure ReplayRecord(RecordType: Byte; Payload: TBufEC);
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

procedure TReplay.ReplayLocal(Buffer: TBufEC);
var
  Id: Integer;
  Hash: QWord;
  Human: THuman;
begin
  Id := Buffer.GetInt32;
  ReadHash(Buffer, Hash);
  Human := FindHuman(Id);
  if Human = nil then
    raise Exception.CreateFmt('Record %d makes a missing human %d local', [Index, Id]);
  SetLocalHuman(Human);
  Compare(Format('local human=%d', [Id]), Hash);
end;

procedure TReplay.ReplayRecord(RecordType: Byte; Payload: TBufEC);
begin
  Payload.SetPosition(0);
  Inc(Index);
  case TRecordType(RecordType) of
    rtLoad: ReplayLoad(Payload);
    rtCommand: ReplayCommand(Payload);
    rtJob: ReplayJob(Payload);
    rtCheckpoint: ReplayCheckpoint(Payload);
    rtLocal: ReplayLocal(Payload);
  else
    raise Exception.CreateFmt('Unknown record type %d', [RecordType]);
  end;
end;

type
  TLogRecord = class
    RecordType: Byte;
    Payload: TBufEC;
    destructor Destroy; override;
  end;
  // One human's log: its records, the actor of its commands, and how far it is replayed.
  TLogFile = class
    Path: AnsiString;
    Records: TList;
    Actor: Cardinal;
    HasActor: Boolean;
    Next: Integer;
    constructor Create(const APath: AnsiString);
    destructor Destroy; override;
    function Item(I: Integer): TLogRecord;
  end;

destructor TLogRecord.Destroy;
begin
  Payload.Free;
  inherited Destroy;
end;

// Every record but a command is shared: each human's log has a copy.
function IsSharedRecord(RecordType: Byte): Boolean;
begin
  Result := TRecordType(RecordType) <> rtCommand;
end;

// The actor of a command record: the command starts with its kind (a word), then the actor.
function CommandActor(Payload: TBufEC): Cardinal;
begin
  Move(PByte(Payload.Data)[2], Result, 4);
end;

constructor TLogFile.Create(const APath: AnsiString);
var
  Stream: TFileStream;
  Header: packed record
    RecordType: Byte;
    Size: Integer;
  end;
  Magic, Version, CommandBy: Cardinal;
  LogRecord: TLogRecord;
begin
  Path := APath;
  Records := TList.Create;
  Stream := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    Stream.ReadBuffer(Magic, 4);
    Stream.ReadBuffer(Version, 4);
    if (Magic <> LogMagic) or (Version <> LogVersion) then
      raise Exception.Create('Not a command log of this version: ' + APath);
    while Stream.Position < Stream.Size do
    begin
      Stream.ReadBuffer(Header, SizeOf(Header));
      LogRecord := TLogRecord.Create;
      Records.Add(LogRecord);
      LogRecord.RecordType := Header.RecordType;
      LogRecord.Payload := TBufEC.Create;
      LogRecord.Payload.SetSize(Header.Size);
      if Header.Size > 0 then
        Stream.ReadBuffer(LogRecord.Payload.Data^, Header.Size);
      if TRecordType(Header.RecordType) = rtCommand then
      begin
        CommandBy := CommandActor(LogRecord.Payload);
        if HasActor and (CommandBy <> Actor) then
          raise Exception.CreateFmt(
              '%s holds commands of humans %d and %d; give one log per human',
              [APath, Actor, CommandBy]
          );
        Actor := CommandBy;
        HasActor := True;
      end;
    end;
  finally
    Stream.Free;
  end;
end;

destructor TLogFile.Destroy;
var
  I: Integer;
begin
  for I := 0 to Records.Count - 1 do
    TLogRecord(Records[I]).Free;
  Records.Free;
  inherited Destroy;
end;

function TLogFile.Item(I: Integer): TLogRecord;
begin
  Result := TLogRecord(Records[I]);
end;

function SameRecord(A, B: TLogRecord): Boolean;
begin
  Result :=
      (A.RecordType = B.RecordType)
          and (A.Payload.DataSize = B.Payload.DataSize)
          and CompareMem(A.Payload.Data, B.Payload.Data, A.Payload.DataSize);
end;

// Every log must hold the same shared records in the same order.
procedure CheckSharedRecords(Logs: TList);
var
  I, J, K, Count: Integer;
  First, Log: TLogFile;
  Shared: array of TLogRecord;
begin
  First := TLogFile(Logs[0]);
  Count := 0;
  for I := 0 to First.Records.Count - 1 do
    if IsSharedRecord(First.Item(I).RecordType) then
    begin
      SetLength(Shared, Count + 1);
      Shared[Count] := First.Item(I);
      Inc(Count);
    end;
  for J := 1 to Logs.Count - 1 do
  begin
    Log := TLogFile(Logs[J]);
    K := 0;
    for I := 0 to Log.Records.Count - 1 do
      if IsSharedRecord(Log.Item(I).RecordType) then
      begin
        if (K >= Count) or not SameRecord(Shared[K], Log.Item(I)) then
          raise Exception.CreateFmt(
              '%s and %s are not logs of one session (shared record %d differs)',
              [First.Path, Log.Path, K + 1]
          );
        Inc(K);
      end;
    if K <> Count then
      raise Exception.CreateFmt(
          '%s and %s are not logs of one session (%d and %d shared records)',
          [First.Path, Log.Path, Count, K]
      );
  end;
end;

// Applies Log's commands up to its next shared record.
procedure ApplyCommands(Replay: TReplay; Log: TLogFile);
var
  Item: TLogRecord;
begin
  while Log.Next < Log.Records.Count do
  begin
    Item := Log.Item(Log.Next);
    if IsSharedRecord(Item.RecordType) then
      Break;
    Replay.ReplayRecord(Item.RecordType, Item.Payload);
    Inc(Log.Next);
  end;
end;

function HasCommandsBeforeShared(Log: TLogFile): Boolean;
begin
  Result := (Log.Next < Log.Records.Count) and not IsSharedRecord(Log.Item(Log.Next).RecordType);
end;

// One log per human, merged: between two shared records, each human's commands in
// Session.Humans order (a human who joins on the way comes in its turn), then the shared
// record. The player-star job starts the day, so it must find that no human holds the day.
function RunMergedReplay(Replay: TReplay; Logs: TList): Integer;
var
  I, J, BarrierWaits: Integer;
  First, Log: TLogFile;
  Human, Waiting: THuman;
  Item: TLogRecord;
  Done: array of Boolean;
begin
  CheckSharedRecords(Logs);
  for I := 0 to Logs.Count - 1 do
    Replay.Emit('replay log=' + TLogFile(Logs[I]).Path);
  BarrierWaits := 0;
  SetLength(Done, Logs.Count);
  First := TLogFile(Logs[0]);
  while True do
  begin
    for J := 0 to Logs.Count - 1 do
      Done[J] := False;
    if Galaxy <> nil then
    begin
      I := 0;
      while I < Session.Humans.Count do
      begin
        Human := Session.Humans[I];
        Inc(I);
        for J := 0 to Logs.Count - 1 do
        begin
          Log := TLogFile(Logs[J]);
          if not Done[J] and Log.HasActor and (Log.Actor = Cardinal(Human.Id)) then
          begin
            Done[J] := True;
            ApplyCommands(Replay, Log);
          end;
        end;
      end;
    end;
    for J := 0 to Logs.Count - 1 do
    begin
      Log := TLogFile(Logs[J]);
      if HasCommandsBeforeShared(Log) then
      begin
        Inc(Replay.Differences);
        Replay.Emit(
            Format('unmerged log=%s actor=%d: its human is not in the game', [Log.Path, Log.Actor])
        );
        ApplyCommands(Replay, Log);
      end;
    end;
    if First.Next >= First.Records.Count then
      Break;
    Item := First.Item(First.Next);
    if (TRecordType(Item.RecordType) = rtJob)
        and (TTurnCalculationJob(PByte(Item.Payload.Data)[0]) = tcjPlayerStar) then
    begin
      Waiting := NextHumanToEndTurn;
      if Waiting <> nil then
      begin
        Inc(BarrierWaits);
        Replay.Emit(
            Format(
                'barrier record=%d day=%d: human %d has not ended the turn',
                [Replay.Index + 1, Galaxy.CurrentTurn, Waiting.Id]
            )
        );
      end;
    end;
    Replay.ReplayRecord(Item.RecordType, Item.Payload);
    for J := 0 to Logs.Count - 1 do
      Inc(TLogFile(Logs[J]).Next);
  end;
  Replay.Emit(
      Format(
          'done records=%d loads=%d commands=%d jobs=%d checkpoints=%d diverged=%d drift=%d'
              + ' answer-mismatches=%d logs=%d humans=%d barrier-waits=%d day=%d hash=%s',
          [Replay.Index, Replay.Loads, Replay.Commands, Replay.Jobs, Replay.Checkpoints,
              Replay.Differences, Replay.DriftAfterCheckpoint, AnswerMismatches, Logs.Count,
              Session.Humans.Count, BarrierWaits, Galaxy.CurrentTurn, IntToHex(CurrentHash, 16)]
      )
  );
  if (Replay.Differences > 0) or (BarrierWaits > 0) then
    Result := 1
  else
    Result := 0;
end;

// The logs LogPath names: one, several separated by commas, or a directory's *.srcl in name
// order.
procedure ListLogs(const LogPath: AnsiString; Paths: TStringList);
var
  Rest, Part: AnsiString;
  Found: TSearchRec;
  Position: Integer;
begin
  if DirectoryExists(LogPath) then
  begin
    if FindFirst(IncludeTrailingPathDelimiter(LogPath) + '*.srcl', faAnyFile, Found) = 0 then
      try
        repeat
          Paths.Add(IncludeTrailingPathDelimiter(LogPath) + Found.Name);
        until FindNext(Found) <> 0;
      finally
        FindClose(Found);
      end;
    Paths.Sort;
    if Paths.Count = 0 then
      raise Exception.Create('No *.srcl logs in ' + LogPath);
    Exit;
  end;
  Rest := LogPath;
  repeat
    Position := Pos(',', Rest);
    if Position = 0 then
    begin
      Part := Rest;
      Rest := '';
    end
    else
    begin
      Part := Copy(Rest, 1, Position - 1);
      Delete(Rest, 1, Position);
    end;
    if Part <> '' then
      Paths.Add(Part);
  until Rest = '';
end;

function RunSingleReplay(const Options: TReplayOptions; const LogPath: AnsiString): Integer;
  forward;

function RunCommandReplay(const Options: TReplayOptions): Integer;
var
  Paths: TStringList;
  Logs: TList;
  Replay: TReplay;
  I: Integer;
begin
  Paths := TStringList.Create;
  try
    ListLogs(Options.LogPath, Paths);
    if Paths.Count = 1 then
      Exit(RunSingleReplay(Options, Paths[0]));
    Logs := TList.Create;
    Replay := TReplay.Create;
    QueryAnswerHook := @ReplayAnswer;
    try
      Replay.Options := Options;
      for I := 0 to Paths.Count - 1 do
        Logs.Add(TLogFile.Create(Paths[I]));
      Result := RunMergedReplay(Replay, Logs);
    finally
      QueryAnswerHook := nil;
      for I := 0 to Logs.Count - 1 do
        TLogFile(Logs[I]).Free;
      Logs.Free;
      Replay.Free;
    end;
  finally
    Paths.Free;
  end;
end;

function RunSingleReplay(const Options: TReplayOptions; const LogPath: AnsiString): Integer;
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
  Stream := TFileStream.Create(LogPath, fmOpenRead or fmShareDenyWrite);
  QueryAnswerHook := @ReplayAnswer;
  RemoteTalkHook := @ReplayRemoteTalk;
  try
    Replay.Options := Options;
    Stream.ReadBuffer(Magic, 4);
    Stream.ReadBuffer(Version, 4);
    if (Magic <> LogMagic) or (Version <> LogVersion) then
      raise Exception.Create('Not a command log of this version: ' + LogPath);
    Replay.Emit('replay log=' + LogPath);
    while Stream.Position < Stream.Size do
    begin
      Stream.ReadBuffer(Header, SizeOf(Header));
      Payload.Clear;
      Payload.SetSize(Header.Size);
      if Header.Size > 0 then
        Stream.ReadBuffer(Payload.Data^, Header.Size);
      Replay.ReplayRecord(Header.RecordType, Payload);
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
    RemoteTalkHook := nil;
    Stream.Free;
    Payload.Free;
    Replay.Free;
  end;
end;

finalization
  StopCommandRecording;
end.
