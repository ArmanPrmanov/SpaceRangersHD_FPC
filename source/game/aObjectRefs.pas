{$EXCESSPRECISION OFF}
unit aObjectRefs;

// CHANGE: BUGFIX - Script variables hold object references as addresses, and the
// save writes them truncated to 32 bits, so a loaded game held stale addresses.
// Saves keep the original slots and append a table that names each saved
// address by object id; loading points the variables at the new objects.
// The same identities let the headless runner hash state without addresses.
interface
uses
  Classes,
  EC_Buf;
// Indexes every addressable object of the current galaxy by a stable key.
procedure CollectObjectIdentities;
// Appends the indexed objects to List in a fixed order, the same for a galaxy and its
// loaded copy, and leaves them indexed.
procedure ListIdentifiedObjects(List: TList);
// The key of the object at Value, '' for a plain number, or 'unresolved' for a
// large value that names no collected object (counted in UnresolvedObjectCount).
function ObjectIdentity(Value: PtrUInt): WideString;
// Called around TGalaxy.SaveToBuffer and TGalaxy.LoadFromBuffer.
procedure BeginObjectReferenceSave;
procedure EndObjectReferenceSave(Buffer: TBufEC);
procedure ResolveLoadedObjectReferences(Buffer: TBufEC);
// The galaxy as TGalaxy.SaveToBuffer writes it, with objects named by key instead of
// address, and its hash. The buffer can be hashed or compared, never loaded. Safe to call
// from the UI and the turn thread; the calls take turns.
function SerializeGalaxyState: TBufEC;
function HashBytes(Data: PByte; Size: Integer): QWord;
function GalaxyStateHash: QWord;
var
  UnresolvedObjectCount: Integer;
implementation
uses
  aHuman,
  aSession,
  SysUtils,
  SyncObjs,
  contnrs,
  EC_Expression,
  Globals,
  aGalaxy,
  aPlanet,
  aItem,
  aShip,
  aScript,
  aRuins;

const
  // 'SREF', then a format version. Loaders that do not know the table stop
  // reading before it.
  ObjectReferenceMagic = $46455253;
  ObjectReferenceVersion = 1;
  // Script dwords below this are numbers; the game itself tests handles this way.
  MinimumObjectAddress = $10000;

type
  TObjectIdentity = record
    Address: PtrUInt;
    Key: WideString;
  end;
  TSavedReference = record
    Value: Cardinal;
    Key: WideString;
    Ambiguous: Boolean;
  end;
var
  Identities: array of TObjectIdentity;
  IdentityCount: Integer;
  SavedReferences: array of TSavedReference;
  SavedReferenceCount: Integer;

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

// TScript.LoadState finds named items by name and appends the unnamed ones it
// saved (those holding an item) in order, so positions in Items do not survive.
procedure AddScriptItemIdentities(Items: TList; const Prefix: WideString);
var
  I, Anonymous: Integer;
  ScriptItem: TScriptItem;
begin
  Anonymous := 0;
  for I := 0 to ListCount(Items) - 1 do
  begin
    ScriptItem := TScriptItem(Items[I]);
    if ScriptItem.Name <> '' then
      AddIdentity(ScriptItem, Prefix + 'name:' + ScriptItem.Name)
    else if ScriptItem.Item <> nil then
    begin
      AddIdentity(ScriptItem, Prefix + 'anonymous:' + IntToStr(Anonymous));
      Inc(Anonymous);
    end;
  end;
end;

procedure CollectUnsortedIdentities;
var
  I, J, K: Integer;
  Star: TStar;
  Planet: TPlanet;
  Stored: TStoredItem;
  Script: TScript;
  Prefix: WideString;
begin
  IdentityCount := 0;
  UnresolvedObjectCount := 0;
  for I := 0 to Galaxy.StoredItems.Count - 1 do
  begin
    Stored := TStoredItem(Galaxy.StoredItems[I]);
    AddItem(Stored.Item);
  end;
  for I := 0 to Galaxy.ShipsInTransit.Count - 1 do
    AddShipIdentity(TShip(Galaxy.ShipsInTransit[I]));
  AddListIdentities(Galaxy.Holes, 'hole:');
  AddListIdentities(Galaxy.Constellations, 'constellation:');
  // Script-owned objects have no id. Those built from the script definition
  // keep their position on load; ship bindings are saved and restored in order.
  for I := 0 to Galaxy.Scripts.Count - 1 do
  begin
    Script := TScript(Galaxy.Scripts[I]);
    Prefix := 'script:' + IntToStr(I);
    AddIdentity(Script, Prefix);
    AddListIdentities(Script.Constellations, Prefix + ':constellation:');
    AddListIdentities(Script.Stars, Prefix + ':star:');
    AddListIdentities(Script.Places, Prefix + ':place:');
    AddScriptItemIdentities(Script.Items, Prefix + ':item:');
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
end;

procedure CollectObjectIdentities;
begin
  CollectUnsortedIdentities;
  SortIdentities(0, IdentityCount - 1);
end;

procedure ListIdentifiedObjects(List: TList);
var
  I: Integer;
begin
  CollectUnsortedIdentities;
  for I := 0 to IdentityCount - 1 do
    List.Add(Pointer(Identities[I].Address));
  SortIdentities(0, IdentityCount - 1);
end;

function FindIdentity(Value: PtrUInt): Integer;
var
  Low, High, Middle: Integer;
begin
  Low := 0;
  High := IdentityCount - 1;
  while Low <= High do
  begin
    Middle := (Low + High) div 2;
    if Identities[Middle].Address = Value then
      Exit(Middle);
    if Identities[Middle].Address < Value then
      Low := Middle + 1
    else
      High := Middle - 1;
  end;
  Result := -1;
end;

function ObjectIdentity(Value: PtrUInt): WideString;
var
  Index: Integer;
begin
  Index := FindIdentity(Value);
  if Index >= 0 then
    Exit(Identities[Index].Key);
  // A large value that names no known object is a number or a stale address
  // (for example one loaded from a save without a reference table).
  if Value < MinimumObjectAddress then
    Exit('');
  Inc(UnresolvedObjectCount);
  Result := 'unresolved';
end;

// Records one saved script dword. The save keeps only the low 32 bits, so a
// value whose truncation matches another saved value with a different meaning
// is marked ambiguous and left unresolved on load.
procedure RecordSavedReference(Value: PtrUInt);
var
  I, Index: Integer;
  Key: WideString;
begin
  if Value < MinimumObjectAddress then
    Exit;
  Index := FindIdentity(Value);
  if Index >= 0 then
    Key := Identities[Index].Key
  else
    Key := '';
  for I := 0 to SavedReferenceCount - 1 do
    if SavedReferences[I].Value = Cardinal(Value) then
    begin
      if SavedReferences[I].Key <> Key then
        SavedReferences[I].Ambiguous := True;
      Exit;
    end;
  if SavedReferenceCount = Length(SavedReferences) then
    SetLength(SavedReferences, SavedReferenceCount * 2 + 64);
  SavedReferences[SavedReferenceCount].Value := Cardinal(Value);
  SavedReferences[SavedReferenceCount].Key := Key;
  SavedReferences[SavedReferenceCount].Ambiguous := False;
  Inc(SavedReferenceCount);
end;

// A hashing snapshot writes keys in place of addresses and needs no table.
procedure BeginObjectReferenceSave;
begin
  SavedReferenceCount := 0;
  if Assigned(SnapshotObjectIdentity) then
    Exit;
  CollectObjectIdentities;
  SavedObjectReference := @RecordSavedReference;
end;

procedure EndObjectReferenceSave(Buffer: TBufEC);
var
  I, Count: Integer;
begin
  if Assigned(SnapshotObjectIdentity) then
    Exit;
  SavedObjectReference := nil;
  Count := 0;
  for I := 0 to SavedReferenceCount - 1 do
    if (SavedReferences[I].Key <> '') and not SavedReferences[I].Ambiguous then
      Inc(Count);
  Buffer.AddDWord(ObjectReferenceMagic);
  Buffer.AddDWord(ObjectReferenceVersion);
  Buffer.AddIntegerValue(Count);
  for I := 0 to SavedReferenceCount - 1 do
    if (SavedReferences[I].Key <> '') and not SavedReferences[I].Ambiguous then
    begin
      Buffer.AddDWord(SavedReferences[I].Value);
      Buffer.AddWideStringZ(SavedReferences[I].Key);
    end;
  SavedReferenceCount := 0;
end;

type
  TReferenceResolver = class
    Saved: array of TSavedReference;
    Objects: TFPHashList;
    Visited: TList;
    Resolved: Integer;
    constructor Create;
    destructor Destroy; override;
    procedure ResolveCell(Cell: TVarEC);
    procedure ResolveArray(Variables: TVarArrayEC);
  end;

constructor TReferenceResolver.Create;
begin
  Objects := TFPHashList.Create;
  Visited := TList.Create;
end;

destructor TReferenceResolver.Destroy;
begin
  Objects.Free;
  Visited.Free;
  inherited;
end;

procedure TReferenceResolver.ResolveCell(Cell: TVarEC);
var
  I: Integer;
  Instance: Pointer;
begin
  if (Cell = nil) or (Visited.IndexOf(Cell) >= 0) then
    Exit;
  Visited.Add(Cell);
  if Cell.Kind = vkArray then
    ResolveArray(Cell.ArrayValue)
  else if (Cell.Kind = vkDword) and (Cell.DwordValue >= MinimumObjectAddress) then
    for I := 0 to High(Saved) do
      if Saved[I].Value = Cell.DwordValue then
      begin
        Instance := Objects.Find(AnsiString(Saved[I].Key));
        if Instance <> nil then
        begin
          Cell.DwordValue := PtrUInt(Instance);
          Inc(Resolved);
        end;
        Exit;
      end;
end;

procedure TReferenceResolver.ResolveArray(Variables: TVarArrayEC);
var
  I: Integer;
begin
  if Variables = nil then
    Exit;
  for I := 0 to Variables.Count - 1 do
    ResolveCell(Variables.GetItemNE(I));
end;

// Reads the table TGalaxy.SaveToBuffer appended, if any, and points every
// script variable holding a saved address at the object that now has its key.
// Saves written by the original game have no table; their values stay as read.
var
  StateLock: TCriticalSection;

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

// The save and load counters are bookkeeping; write the values the galaxy was loaded with
// and leave both counters as they were.
function SerializeGalaxyState: TBufEC;
begin
  Result := TBufEC.Create;
  StateLock.Enter;
  try
    CollectObjectIdentities;
    SnapshotObjectIdentity := @ObjectIdentity;
    Dec(Galaxy.SaveCount);
    Dec(Galaxy.LoadCount);
    try
      Galaxy.SaveToBuffer(Result);
    finally
      Inc(Galaxy.LoadCount);
      SnapshotObjectIdentity := nil;
    end;
  finally
    StateLock.Leave;
  end;
end;

function GalaxyStateHash: QWord;
var
  State: TBufEC;
begin
  State := SerializeGalaxyState;
  try
    Result := HashBytes(State.Data, State.DataSize);
  finally
    State.Free
  end;
end;

procedure ResolveLoadedObjectReferences(Buffer: TBufEC);
var
  I, Count, Start: Integer;
  Resolver: TReferenceResolver;
  Script: TScript;
begin
  Start := Buffer.Position;
  if (Buffer.DataSize - Start < 12) or (Buffer.GetUInt32 <> ObjectReferenceMagic) then
  begin
    Buffer.SetPosition(Start);
    Exit;
  end;
  // A table from a newer build is left unread; the variables keep their values.
  if Buffer.GetUInt32 <> ObjectReferenceVersion then
    Exit;
  Resolver := TReferenceResolver.Create;
  try
    Count := Buffer.GetInt32;
    SetLength(Resolver.Saved, Count);
    for I := 0 to Count - 1 do
    begin
      Resolver.Saved[I].Value := Buffer.GetUInt32;
      Resolver.Saved[I].Key := Buffer.ReadWideString;
    end;
    if Count = 0 then
      Exit;
    CollectObjectIdentities;
    for I := 0 to IdentityCount - 1 do
      Resolver.Objects.Add(AnsiString(Identities[I].Key), Pointer(Identities[I].Address));
    Resolver.ResolveArray(Session.SharedScriptVariables);
    for I := 0 to Galaxy.Scripts.Count - 1 do
    begin
      Script := TScript(Galaxy.Scripts[I]);
      if Script.InitCode <> nil then
        Resolver.ResolveArray(Script.InitCode.LocalVar);
      if Script.TurnCode <> nil then
        Resolver.ResolveArray(Script.TurnCode.LocalVar);
    end;
  finally
    Resolver.Free;
  end;
end;

initialization
  StateLock := TCriticalSection.Create;
finalization
  StateLock.Free;
end.
