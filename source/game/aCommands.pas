{$EXCESSPRECISION OFF}
unit aCommands;

// CHANGE: ENHANCEMENT - Player commands (ROADMAP.md, Phase 3). Every change a human makes to
// the simulation is one command: a kind, the acting ranger, the objects it names by id, and
// integers. The UI submits commands instead of changing game objects; the command log
// (CommandLog) records them and the headless runner replays them. aPlayerActions builds and
// executes the commands.
interface
uses
  EC_Buf,
  Types;
type
  // A command's kind. Each actions unit declares its kinds as constants in a range of its
  // own and registers them (RegisterCommand); values are part of the command log format,
  // so never renumber one. Ranges: 0-99 aPlayerActions (travel, orders, the day), 100-199
  // shops, 200-299 the ship and hold screen, 300-399 conversations, 400-499 planets and the
  // government, 500-599 stations, 600-699 text quests, arcade battles, cheats and UI scripts.
  TCommandKind = type Word;
const
  ckNone = 0;
type
  TCommandRefKind = (
      crNone = 0,
      crStar = 1,
      crPlanet = 2,
      crShip = 3,
      crItem = 4,
      crHole = 5,
      crConstellation = 6,
      crAsteroid = 7,
      crMissile = 8
  );
  TCommandRef = record
    Kind: TCommandRefKind;
    Id: Cardinal;
  end;
  TPlayerCommand = record
    Kind: TCommandKind;
    // The ship id of the acting human's ranger.
    Actor: Cardinal;
    Refs: array of TCommandRef;
    Ints: array of Integer;
    Text: WideString;
  end;
  TCommandExecutor = procedure(const Command: TPlayerCommand);
  TCommandHook = procedure(const Command: TPlayerCommand);
var
  // Called around every submitted command, on the thread that submits it.
  BeforeCommandHook: TCommandHook;
  AfterCommandHook: TCommandHook;

function NewCommand(Kind: TCommandKind): TPlayerCommand;
// Names Instance by kind and id; nil names nothing.
procedure AddRef(var Command: TPlayerCommand; Instance: TObject);
procedure AddInt(var Command: TPlayerCommand; Value: Integer);
procedure AddFloat(var Command: TPlayerCommand; Value: Single);
procedure AddPoint(var Command: TPlayerCommand; const Value: TPointF);
function RefObject(const Command: TPlayerCommand; Index: Integer): TObject;
function IntArg(const Command: TPlayerCommand; Index: Integer): Integer;
function FloatArg(const Command: TPlayerCommand; Index: Integer): Single;
function PointArg(const Command: TPlayerCommand; Index: Integer): TPointF;
function ResolveRef(const Ref: TCommandRef): TObject;
// Whether AddRef can name Instance.
function CanNameObject(Instance: TObject): Boolean;

procedure EncodeCommand(const Command: TPlayerCommand; Buffer: TBufEC);
function DecodeCommand(Buffer: TBufEC): TPlayerCommand;
function CommandKindName(Kind: TCommandKind): AnsiString;

procedure RegisterCommand(Kind: TCommandKind; const Name: AnsiString; Executor: TCommandExecutor);
// Runs the command and tells the hooks.
procedure SubmitCommand(const Command: TPlayerCommand);
// Runs the command only; the replay uses this.
procedure ExecuteCommand(const Command: TPlayerCommand);
implementation
uses
  SysUtils,
  aGalaxy,
  aPlanet,
  aShip,
  aItem,
  aAsteroid,
  aMissile,
  aHuman,
  aPlayer,
  SimulationThread;

const
  MaximumCommandKind = 1023;
var
  Executors: array[0..MaximumCommandKind] of TCommandExecutor;
  KindNames: array[0..MaximumCommandKind] of AnsiString;

function NewCommand(Kind: TCommandKind): TPlayerCommand;
begin
  Result := Default(TPlayerCommand);
  Result.Kind := Kind;
  // The UI submits commands for the human at this machine.
  if LocalPlayer <> nil then
    Result.Actor := Cardinal(LocalPlayer.Id);
end;


function CanNameObject(Instance: TObject): Boolean;
begin
  Result :=
      (Instance = nil)
          or (Instance is TStar)
          or (Instance is TPlanet)
          or (Instance is TShip)
          or (Instance is TItem)
          or (Instance is THole)
          or (Instance is TConstellation)
          or (Instance is TAsteroid)
          or (Instance is TMissile);
end;

procedure AddRef(var Command: TPlayerCommand; Instance: TObject);
var
  Ref: TCommandRef;
begin
  Ref.Kind := crNone;
  Ref.Id := 0;
  if Instance = nil then
  else if Instance is TStar then
  begin
    Ref.Kind := crStar;
    Ref.Id := Cardinal(TStar(Instance).Id);
  end
  else if Instance is TPlanet then
  begin
    Ref.Kind := crPlanet;
    Ref.Id := Cardinal(TPlanet(Instance).Id);
  end
  else if Instance is TShip then
  begin
    Ref.Kind := crShip;
    Ref.Id := Cardinal(TShip(Instance).Id);
  end
  else if Instance is TItem then
  begin
    Ref.Kind := crItem;
    Ref.Id := Cardinal(TItem(Instance).Id);
  end
  else if Instance is THole then
  begin
    Ref.Kind := crHole;
    Ref.Id := Cardinal(THole(Instance).Id);
  end
  else if Instance is TConstellation then
  begin
    Ref.Kind := crConstellation;
    Ref.Id := Cardinal(TConstellation(Instance).Id);
  end
  else if Instance is TAsteroid then
  begin
    Ref.Kind := crAsteroid;
    Ref.Id := Cardinal(TAsteroid(Instance).Id);
  end
  else if Instance is TMissile then
  begin
    Ref.Kind := crMissile;
    Ref.Id := Cardinal(TMissile(Instance).Id);
  end
  else
    raise Exception.Create('A command cannot name a ' + Instance.ClassName);
  SetLength(Command.Refs, Length(Command.Refs) + 1);
  Command.Refs[High(Command.Refs)] := Ref;
end;

procedure AddInt(var Command: TPlayerCommand; Value: Integer);
begin
  SetLength(Command.Ints, Length(Command.Ints) + 1);
  Command.Ints[High(Command.Ints)] := Value;
end;

// Floats travel as their bits, so a replay gets exactly the value the UI computed.
procedure AddFloat(var Command: TPlayerCommand; Value: Single);
var
  Bits: Integer;
begin
  Move(Value, Bits, SizeOf(Bits));
  AddInt(Command, Bits);
end;

procedure AddPoint(var Command: TPlayerCommand; const Value: TPointF);
begin
  AddFloat(Command, Value.X);
  AddFloat(Command, Value.Y);
end;

function ResolveRef(const Ref: TCommandRef): TObject;
begin
  case Ref.Kind of
    crNone: Result := nil;
    crStar: Result := Galaxy.IdToStar(Ref.Id);
    crPlanet: Result := TObject(Galaxy.IdToPlanet(Ref.Id, False));
    crShip: Result := TObject(Galaxy.IdToShip(Ref.Id, False));
    crItem: Result := TObject(Galaxy.IdToItem(Ref.Id, False));
    crHole: Result := Galaxy.IdToHole(Ref.Id);
    crConstellation: Result := Galaxy.IdToConstellation(Ref.Id);
    crAsteroid: Result := TObject(Galaxy.IdToAsteroid(Ref.Id));
    crMissile: Result := TObject(Galaxy.IdToMissile(Ref.Id));
  else
    raise Exception.Create('Unknown command reference kind');
  end;
  if (Result = nil) and (Ref.Kind <> crNone) and (Ref.Id <> 0) then
    raise Exception.CreateFmt('A command names a missing object (%d:%d)', [Ord(Ref.Kind), Ref.Id]);
end;

function RefObject(const Command: TPlayerCommand; Index: Integer): TObject;
begin
  if Index > High(Command.Refs) then
    raise Exception.Create(CommandKindName(Command.Kind) + ' has too few references');
  Result := ResolveRef(Command.Refs[Index]);
end;

function IntArg(const Command: TPlayerCommand; Index: Integer): Integer;
begin
  if Index > High(Command.Ints) then
    raise Exception.Create(CommandKindName(Command.Kind) + ' has too few integers');
  Result := Command.Ints[Index];
end;

function FloatArg(const Command: TPlayerCommand; Index: Integer): Single;
var
  Bits: Integer;
begin
  Bits := IntArg(Command, Index);
  Move(Bits, Result, SizeOf(Result));
end;

function PointArg(const Command: TPlayerCommand; Index: Integer): TPointF;
begin
  Result.X := FloatArg(Command, Index);
  Result.Y := FloatArg(Command, Index + 1);
end;

procedure EncodeCommand(const Command: TPlayerCommand; Buffer: TBufEC);
var
  I: Integer;
begin
  Buffer.AddWord(Ord(Command.Kind));
  Buffer.AddDWord(Command.Actor);
  Buffer.AddByte(Length(Command.Refs));
  for I := 0 to High(Command.Refs) do
  begin
    Buffer.AddByte(Ord(Command.Refs[I].Kind));
    Buffer.AddDWord(Command.Refs[I].Id);
  end;
  Buffer.AddWord(Length(Command.Ints));
  for I := 0 to High(Command.Ints) do
    Buffer.AddInt32(Command.Ints[I]);
  Buffer.AddWideStringZ(Command.Text);
end;

function DecodeCommand(Buffer: TBufEC): TPlayerCommand;
var
  I: Integer;
begin
  Result := Default(TPlayerCommand);
  Result.Kind := TCommandKind(Buffer.GetWord);
  Result.Actor := Buffer.GetUInt32;
  SetLength(Result.Refs, Buffer.GetByte);
  for I := 0 to High(Result.Refs) do
  begin
    Result.Refs[I].Kind := TCommandRefKind(Buffer.GetByte);
    Result.Refs[I].Id := Buffer.GetUInt32;
  end;
  SetLength(Result.Ints, Buffer.GetWord);
  for I := 0 to High(Result.Ints) do
    Result.Ints[I] := Buffer.GetInt32;
  Result.Text := Buffer.ReadWideString;
end;

function CommandKindName(Kind: TCommandKind): AnsiString;
begin
  if (Kind <= MaximumCommandKind) and (KindNames[Kind] <> '') then
    Result := KindNames[Kind]
  else
    Result := 'Command' + IntToStr(Kind);
end;

procedure RegisterCommand(Kind: TCommandKind; const Name: AnsiString; Executor: TCommandExecutor);
begin
  if Kind > MaximumCommandKind then
    raise Exception.Create('Command kind out of range: ' + Name);
  if KindNames[Kind] <> '' then
    raise Exception.Create('Command kind registered twice: ' + Name);
  Executors[Kind] := Executor;
  KindNames[Kind] := Name;
end;

procedure ExecuteCommand(const Command: TPlayerCommand);
begin
  if (Command.Kind > MaximumCommandKind) or not Assigned(Executors[Command.Kind]) then
    raise Exception.Create('No executor for ' + CommandKindName(Command.Kind));
  if Actor(Command) = nil then
    raise Exception.Create(CommandKindName(Command.Kind) + ' names no human');
  Executors[Command.Kind](Command);
end;

procedure SubmitCommand(const Command: TPlayerCommand);
begin
  // On the turn thread a command is part of the job that runs it, not something a human did.
  if InTurnJob then
  begin
    ExecuteCommand(Command);
    Exit;
  end;
  if Assigned(BeforeCommandHook) then
    BeforeCommandHook(Command);
  ExecuteCommand(Command);
  if Assigned(AfterCommandHook) then
    AfterCommandHook(Command);
end;

end.
