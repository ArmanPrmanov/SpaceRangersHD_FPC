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
    RoundTrip: Boolean;
    Seed: Cardinal;
    DumpDirectory: AnsiString;
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
  aGalaxy,
  aPlanet,
  aItem,
  aShip,
  aScript,
  aRuins,
  aGalaxyEvent,
  aSaveLoad,
  ThreadCalc,
  ObserverSimulation;

function HashBytes(Data: PByte; Size: Integer): QWord;
var
  I: Integer;
begin
  // FNV-1a, 64-bit.
  Result := QWord($CBF29CE484222325);
  for I := 0 to Size - 1 do
  begin
    Result := Result xor Data[I];
    Result := Result * QWord($100000001B3);
  end;
end;

type
  TObjectIdentity = record
    Address: PtrUInt;
    Key: WideString;
  end;
var
  Identities: array of TObjectIdentity;
  IdentityCount, UnresolvedCount: Integer;

procedure AddIdentity(Instance: TObject; const Key: WideString);
begin
  if IdentityCount = Length(Identities) then
    SetLength(Identities, IdentityCount * 2 + 1024);
  Identities[IdentityCount].Address := PtrUInt(Instance);
  Identities[IdentityCount].Key := Key;
  Inc(IdentityCount);
end;

procedure SortIdentities(Low, High: Integer);
var
  I, J: Integer;
  Pivot: PtrUInt;
  Swap: TObjectIdentity;
begin
  while Low < High do
  begin
    Pivot := Identities[(Low + High) div 2].Address;
    I := Low;
    J := High;
    repeat
      while Identities[I].Address < Pivot do
        Inc(I);
      while Identities[J].Address > Pivot do
        Dec(J);
      if I <= J then
      begin
        Swap := Identities[I];
        Identities[I] := Identities[J];
        Identities[J] := Swap;
        Inc(I);
        Dec(J);
      end;
    until I > J;
    if J - Low < High - I then
    begin
      SortIdentities(Low, J);
      Low := I
    end
    else
    begin
      SortIdentities(I, High);
      High := J
    end;
  end;
end;

// Lists the game has not created yet are nil.
function ListCount(List: TList): Integer;
begin
  if List = nil then
    Result := 0
  else
    Result := List.Count;
end;

procedure AddListIdentities(List: TList; const Prefix: WideString);
var
  I: Integer;
begin
  for I := 0 to ListCount(List) - 1 do
    AddIdentity(TObject(List[I]), Prefix + IntToStr(I));
end;

procedure AddItem(Instance: TObject);
begin
  if Instance is TItem then
    AddIdentity(Instance, 'item:' + IntToStr(TItem(Instance).Id));
end;

procedure AddItemIdentities(List: TList);
var
  I: Integer;
begin
  for I := 0 to ListCount(List) - 1 do
    AddItem(TObject(List[I]));
end;

procedure AddShipIdentity(Ship: TShip);
begin
  AddIdentity(Ship, 'ship:' + IntToStr(Ship.Id));
  AddItemIdentities(Ship.Inventory);
  AddItemIdentities(Ship.Artefacts);
  AddItemIdentities(Ship.GuaranteedDeathDropItems);
  if Ship is TRuins then
    AddItemIdentities(TRuins(Ship).EquipmentShop);
end;

procedure CollectIdentities;
var
  I, J, K: Integer;
  Star: TStar;
  Planet: TPlanet;
  Stored: TStoredItem;
  Script: TScript;
  Prefix: WideString;
begin
  IdentityCount := 0;
  UnresolvedCount := 0;
  for I := 0 to Galaxy.StoredItems.Count - 1 do
  begin
    Stored := TStoredItem(Galaxy.StoredItems[I]);
    AddItem(Stored.Item);
  end;
  for I := 0 to Galaxy.ShipsInTransit.Count - 1 do
    AddShipIdentity(TShip(Galaxy.ShipsInTransit[I]));
  AddListIdentities(Galaxy.Holes, 'hole:');
  AddListIdentities(Galaxy.Constellations, 'constellation:');
  // Script-owned objects have no id; the position in their script names them.
  for I := 0 to Galaxy.Scripts.Count - 1 do
  begin
    Script := TScript(Galaxy.Scripts[I]);
    Prefix := 'script:' + IntToStr(I);
    AddIdentity(Script, Prefix);
    AddListIdentities(Script.Constellations, Prefix + ':constellation:');
    AddListIdentities(Script.Stars, Prefix + ':star:');
    AddListIdentities(Script.Places, Prefix + ':place:');
    AddListIdentities(Script.Items, Prefix + ':item:');
    AddListIdentities(Script.Groups, Prefix + ':group:');
    AddListIdentities(Script.Ships, Prefix + ':ship:');
    AddListIdentities(Script.States, Prefix + ':state:');
    AddListIdentities(Script.Dialogs, Prefix + ':dialog:');
  end;
  for I := 0 to Galaxy.Stars.Count - 1 do
  begin
    Star := TStar(Galaxy.Stars[I]);
    AddIdentity(Star, 'star:' + IntToStr(Star.Id));
    for J := 0 to Star.Planets.Count - 1 do
    begin
      Planet := TPlanet(Star.Planets[J]);
      AddIdentity(Planet, 'planet:' + IntToStr(Planet.Id));
      AddItemIdentities(Planet.EquipmentShop);
      for K := 0 to ListCount(Planet.SurfaceLootEntries) - 1 do
        AddItem(PPlanetSurfaceLootEntry(Planet.SurfaceLootEntries[K]).Item);
      for K := 0 to ListCount(Planet.Warriors) - 1 do
        AddShipIdentity(TShip(Planet.Warriors[K]));
    end;
    for J := 0 to Star.Ships.Count - 1 do
      AddShipIdentity(TShip(Star.Ships[J]));
    AddItemIdentities(Star.Items);
    for J := 0 to ListCount(Star.MovingDropItems) - 1 do
      AddItem(PointerToTMovingDropItemEntry(Star.MovingDropItems[J]).Payload);
  end;
  SortIdentities(0, IdentityCount - 1);
end;

function ObjectIdentity(Value: PtrUInt): WideString;
var
  Low, High, Middle: Integer;
begin
  Low := 0;
  High := IdentityCount - 1;
  while Low <= High do
  begin
    Middle := (Low + High) div 2;
    if Identities[Middle].Address = Value then
      Exit(Identities[Middle].Key);
    if Identities[Middle].Address < Value then
      Low := Middle + 1
    else
      High := Middle - 1;
  end;
  // Script dwords are object handles; small values are plain numbers. A large
  // one that names no known object may point to a container not collected
  // above or to a freed object. Its address is meaningless, so count it.
  if Value < $10000 then
    Exit('');
  Inc(UnresolvedCount);
  Result := 'unresolved';
end;

// Script variables keep object references as addresses, which differ between
// runs. The state buffer names those objects by id instead, so it can only be
// hashed, never loaded. The save and load counters are bookkeeping; write the
// values the galaxy was loaded with and leave both counters as they were.
function SerializeGalaxy: TBufEC;
begin
  Result := TBufEC.Create;
  CollectIdentities;
  SnapshotObjectIdentity := @ObjectIdentity;
  Dec(Galaxy.SaveCount);
  Dec(Galaxy.LoadCount);
  try
    Galaxy.SaveToBuffer(Result);
  finally
    Inc(Galaxy.LoadCount);
    SnapshotObjectIdentity := nil;
  end;
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
  State := SerializeGalaxy;
  try
    DumpBuffer(DumpDirectory, Format('turn-%.4d.bin', [Turn]), State);
    Emit(
        Format(
            'turn %d day=%d hash=%s bytes=%d unresolved=%d',
            [Turn, Galaxy.CurrentTurn, IntToHex(HashBytes(State.Data, State.DataSize), 16),
                State.DataSize, UnresolvedCount]
        )
    );
  finally
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
    Before := SerializeGalaxy;
    SaveUnchanged(First);
    LoadSave(First, Seed);
    DropSaveLoadedEvent;
    After := SerializeGalaxy;
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
  if Options.Hash then
    EmitHash(0, Options.DumpDirectory);
  for Turn := 1 to Options.Turns do
  begin
    SimulateParkedTurn;
    if Options.Hash then
      EmitHash(Turn, Options.DumpDirectory);
  end;
  Emit(Format('done turns=%d day=%d', [Options.Turns, Galaxy.CurrentTurn]));
end;

end.
