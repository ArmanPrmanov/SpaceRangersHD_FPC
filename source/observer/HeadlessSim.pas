{$EXCESSPRECISION OFF}
unit HeadlessSim;

// CHANGE: ENHANCEMENT - Headless turn runner and state hash for regression tests.
// Loads a save, parks the player as the observer does, advances turns without
// a window and prints one line per result. The state hash covers the bytes
// TGalaxy.SaveToBuffer writes, so the save writer is the only serialiser.
interface
type
  TSimulationOptions = record
    SavePath: AnsiString;
    Turns: Integer;
    Hash: Boolean;
    // Hash only after the last turn, to show that hashing changes nothing.
    HashLastOnly: Boolean;
    RoundTrip: Boolean;
    Seed: Cardinal;
    DumpDirectory: AnsiString;
    // Write a checkpoint after this turn and continue from it (0: never).
    ReloadAt: Integer;
  end;
function RunHeadlessSimulation(const Options: TSimulationOptions): Integer;
implementation
uses
  SysUtils,
  Classes,
  EC_Buf,
  EC_Expression,
  Globals,
  GlobalsV,
  aMyFunction,
  aGalaxy,
  aGalaxyEvent,
  aObjectRefs,
  aSaveLoad,
  SaveTrace,
  ThreadCalc,
  ObserverSimulation;

var
  // Where each object starts in the state being dumped (SaveTrace).
  TraceLines: TStringList;

procedure RecordTrace(const Kind: AnsiString; Id: Cardinal; Offset: Integer);
begin
  TraceLines.Add(Format('%d %s:%d', [Offset, Kind, Id]));
end;

procedure Emit(const Line: AnsiString);
begin
  WriteLn(Line);
  Flush(Output);
end;

procedure DumpBuffer(const Directory, Name: AnsiString; Buffer: TBufEC);
var
  Stream: TFileStream;
begin
  if Directory = '' then
    Exit;
  Stream := TFileStream.Create(IncludeTrailingPathDelimiter(Directory) + Name, fmCreate);
  try
    Stream.WriteBuffer(Buffer.Data^, Buffer.DataSize);
  finally
    Stream.Free
  end;
end;

procedure EmitHash(Turn: Integer; const DumpDirectory: AnsiString);
var
  State: TBufEC;
begin
  if DumpDirectory <> '' then
  begin
    TraceLines := TStringList.Create;
    SaveTraceHook := @RecordTrace;
  end;
  try
    State := SerializeGalaxyState;
  finally
    SaveTraceHook := nil;
  end;
  try
    DumpBuffer(DumpDirectory, Format('turn-%.4d.bin', [Turn]), State);
    if TraceLines <> nil then
      TraceLines.SaveToFile(
          IncludeTrailingPathDelimiter(DumpDirectory) + Format('turn-%.4d.index', [Turn])
      );
    Emit(
        Format(
            'turn %d day=%d hash=%s bytes=%d unresolved=%d',
            [Turn, Galaxy.CurrentTurn, IntToHex(HashBytes(State.Data, State.DataSize), 16),
                State.DataSize, UnresolvedObjectCount]
        )
    );
  finally
    FreeAndNil(TraceLines);
    State.Free
  end;
end;

// Decodes a save file into its game-state and film payloads, as LoadGameFromFile reads them.
procedure ReadSavePayloads(const FileName: AnsiString; State, Films: TBufEC);
var
  Stream: TFileStream;
  Raw: TBufEC;
  I, Size, Seed: Integer;
  Crc: Cardinal;
begin
  Raw := TBufEC.Create;
  try
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      Raw.SetSize(Stream.Size);
      Stream.ReadBuffer(Raw.Data^, Stream.Size);
    finally
      Stream.Free
    end;
    Raw.SetPosition(0);
    for I := 1 to 8 do
      Raw.ReadWideString;
    for I := 1 to 2 do
    begin
      Size := Raw.GetInt32;
      Raw.SetPosition(Raw.Position + Size);
    end;
    Crc := Raw.GetUInt32;
    Seed := Raw.GetInt32;
    Size := Raw.GetInt32;
    State.SetSize(Size);
    Raw.ReadBytes(State.Data, Size);
    State.ApplyDatXorCipher(Seed);
    if State.ComputeCrc32 <> Crc then
      raise Exception.Create('Integrity check failed: ' + FileName);
    State.ExpandZlibPayloadInPlace;
    Size := Raw.DataSize - Raw.Position;
    Films.SetSize(Size);
    if Size > 0 then
    begin
      Raw.ReadBytes(Films.Data, Size);
      Films.ExpandZlibPayloadInPlace;
    end;
  finally
    Raw.Free
  end;
end;

function FirstDifference(A, B: TBufEC): Integer;
var
  I, Size: Integer;
begin
  Size := A.DataSize;
  if B.DataSize < Size then
    Size := B.DataSize;
  for I := 0 to Size - 1 do
    if PByte(A.Data)[I] <> PByte(B.Data)[I] then
      Exit(I);
  if A.DataSize = B.DataSize then
    Result := -1
  else
    Result := Size;
end;

function ComparePayload(const Name: AnsiString; Expected, Actual: TBufEC): Boolean;
var
  Offset: Integer;
begin
  Offset := FirstDifference(Expected, Actual);
  Result := Offset < 0;
  if Result then
    Emit(Format('roundtrip %s=ok bytes=%d', [Name, Expected.DataSize]))
  else
    Emit(
        Format(
            'roundtrip %s=diff offset=%d expected=%d actual=%d',
            [Name, Offset, Expected.DataSize, Actual.DataSize]
        )
    );
end;

procedure LoadSave(const FileName: AnsiString; Seed: Cardinal);
begin
  if not LoadGameFromFile(UTF8Decode(FileName)) then
    raise Exception.Create('Load failed: ' + UTF8Encode(LastSaveLoadError));
  WaitForTurnCalculation;
  // TGalaxy.Create reseeds the shared stream from the clock; pin it so that
  // call sites still on the shared stream repeat between runs.
  System.RandSeed := Integer(Seed);
  SeedChaoticRandom(Seed);
end;

// The save and load counters would differ between the two files; write the
// values the galaxy was loaded with.
procedure SaveUnchanged(const FileName: AnsiString);
begin
  Dec(Galaxy.SaveCount);
  Dec(Galaxy.LoadCount);
  try
    if not SaveGameToFile(UTF8Decode(FileName), 'roundtrip') then
      raise Exception.Create('Save failed: ' + UTF8Encode(LastSaveLoadError));
  finally
    Inc(Galaxy.LoadCount);
  end;
end;

// Loading logs a SaveLoaded event; drop the one the round trip's load added.
procedure DropSaveLoadedEvent;
var
  Event: TGalaxyEvent;
begin
  if Galaxy.GalaxyEvents.Count = 0 then
    Exit;
  Event := TGalaxyEvent(Galaxy.GalaxyEvents.Last);
  if Event.EventType <> 'SaveLoaded' then
    raise Exception.Create('Load did not log SaveLoaded as the last galaxy event');
  Galaxy.GalaxyEvents.Extract(Event);
  Event.Free;
end;

// Save, load that save, and compare the state before and after in hashable
// form. A save made by the game can differ from its re-save, because loading
// recomputes derived values such as the average ranger capital, so the
// comparison starts from a loaded game.
function CheckRoundTrip(const DumpDirectory: AnsiString; Seed: Cardinal): Boolean;
var
  Before, After, FirstState, FirstFilms, SecondState, SecondFilms: TBufEC;
  First, Second: AnsiString;
begin
  Before := nil;
  After := nil;
  FirstState := TBufEC.Create;
  FirstFilms := TBufEC.Create;
  SecondState := TBufEC.Create;
  SecondFilms := TBufEC.Create;
  First := GetTempDir(False) + 'rangers-roundtrip-' + IntToStr(GetProcessID) + '-1.sav';
  Second := GetTempDir(False) + 'rangers-roundtrip-' + IntToStr(GetProcessID) + '-2.sav';
  try
    Before := SerializeGalaxyState;
    SaveUnchanged(First);
    LoadSave(First, Seed);
    DropSaveLoadedEvent;
    After := SerializeGalaxyState;
    SaveUnchanged(Second);
    ReadSavePayloads(First, FirstState, FirstFilms);
    ReadSavePayloads(Second, SecondState, SecondFilms);
    DumpBuffer(DumpDirectory, 'roundtrip-before.bin', Before);
    DumpBuffer(DumpDirectory, 'roundtrip-after.bin', After);
    Result := ComparePayload('galaxy', Before, After);
    Result := ComparePayload('films', FirstFilms, SecondFilms) and Result;
  finally
    DeleteFile(First);
    DeleteFile(Second);
    Before.Free;
    After.Free;
    FirstState.Free;
    FirstFilms.Free;
    SecondState.Free;
    SecondFilms.Free;
  end;
end;

// A checkpoint must give back a game that plays on as the one it was written from.
procedure ReloadFromCheckpoint;
var
  Buffer: TBufEC;
begin
  Buffer := TBufEC.Create;
  try
    WriteGameCheckpoint(Buffer);
    Buffer.SetPosition(0);
    ReadGameCheckpoint(Buffer);
  finally
    Buffer.Free
  end;
  Emit(Format('reloaded day=%d', [Galaxy.CurrentTurn]));
end;

function RunHeadlessSimulation(const Options: TSimulationOptions): Integer;
var
  Turn: Integer;
begin
  Result := 0;
  LoadSave(Options.SavePath, Options.Seed);
  Emit(Format('sim save=%s seed=%d day=%d', [Options.SavePath, Options.Seed, Galaxy.CurrentTurn]));
  if Options.RoundTrip then
  begin
    if not CheckRoundTrip(Options.DumpDirectory, Options.Seed) then
      Result := 1;
    // Simulate from the save itself, not from its round-tripped copy.
    if Options.Turns > 0 then
      LoadSave(Options.SavePath, Options.Seed);
  end;
  if Options.Turns <= 0 then
    Exit;
  ParkObserverPlayer;
  CurrentScreenId := screenPlanet;
  RequestedScreenId := screenNone;
  if Options.Hash and not Options.HashLastOnly then
    EmitHash(0, Options.DumpDirectory);
  for Turn := 1 to Options.Turns do
  begin
    SimulateParkedTurn;
    if Turn = Options.ReloadAt then
      ReloadFromCheckpoint;
    if Options.Hash and (not Options.HashLastOnly or (Turn = Options.Turns)) then
      EmitHash(Turn, Options.DumpDirectory);
  end;
  // A game that has run turns holds script references made during play, which
  // a round trip from the save alone does not exercise.
  if Options.RoundTrip and not CheckRoundTrip(Options.DumpDirectory, Options.Seed) then
    Result := 1;
  Emit(Format('done turns=%d day=%d', [Options.Turns, Galaxy.CurrentTurn]));
end;

end.
