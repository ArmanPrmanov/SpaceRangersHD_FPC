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
  SysUtils,
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
  // CHANGE: ENHANCEMENT - Why a command could not run, as a host tells the client that sent it
  // (docs/network.md, Commands: CommandResult). The values travel in that message, so never
  // renumber one. An executor raises ECommandRefused where the reason is one of these; any
  // other exception is rrOther. ECommandRefused means that the command changed nothing
  // before it raised, so the command log needs no checkpoint after it: raise it only before
  // the executor's first change.
  // rrOfferGone: an offer the player accepted is no longer made (taken by another human, or
  // replaced); rrTargetGone: what the command acts on has changed since the player chose it;
  // rrNoRoom: the other side has no room for what the player sells; rrInUse: another human is
  // using it (a shared ship's screen). A client of an older build reads a value it does not
  // know as rrOther.
  TRefusalReason = (
      rrOther = 0,
      rrOutOfStock = 1,
      rrNoMoney = 2,
      rrItemGone = 3,
      rrOfferGone = 4,
      rrTargetGone = 5,
      rrNoRoom = 6,
      rrInUse = 7
  );
  ECommandRefused = class(Exception)
    Reason: TRefusalReason;
    constructor CreateReason(AReason: TRefusalReason; const Text: string);
  end;
var
  // Called around every submitted command, on the thread that submits it.
  BeforeCommandHook: TCommandHook;
  AfterCommandHook: TCommandHook;
  // CHANGE: ENHANCEMENT - Called after AfterCommandHook, so that the command log and the
  // network can both listen: a client's network session sends the command to the host
  // (ROADMAP.md, Phase 5; docs/network.md, Commands).
  NetworkCommandHook: TCommandHook;
  // CHANGE: BUGFIX - Called instead of AfterCommandHook when the command raises, before the
  // exception goes on to the caller, so that the command log closes what BeforeCommandHook
  // opened (a remote command the host drops, docs/network.md, Commands).
  CommandFailedHook: TCommandHook;
  // CHANGE: ENHANCEMENT - A client's trade (IsTradeCommand) goes to the host and runs here only
  // once the host has applied it (docs/network.md, Trades). Called by SubmitCommand for an
  // outermost trade, before anything runs: it returns when the host applied the command, which
  // then runs here, and raises ECommandRefused when the host refused it or did not answer.
  TradeSubmitHook: TCommandHook;
  // CHANGE: ENHANCEMENT - What SubmitTrade does with a refused trade of this machine's player:
  // tells the player (a bubble), then ends the UI action that submitted it (the screens set it
  // to break the UI message), so that nothing after the submit acts as if it had been done.
  // Set in a session; without them SubmitTrade raises the refusal as SubmitCommand does.
  TradeRefusedHook: procedure(Reason: TRefusalReason);
  TradeAbortHook: procedure;
  // CHANGE: BUGFIX - Around a command that runs while none does (the outermost), of a human who
  // is not the local one: Enter puts that human's script dialogue state (a THuman's) in place
  // of the local human's and returns whether it did, and Leave puts the local one's back
  // (aScript.EnterHumanDialogState, set by aDialogActions; docs/humans.md, Scripts). So a
  // client's dialogue on a host, at the barrier, in a remote dialogue or before a trade,
  // leaves the host's own open dialogue as it was.
  EnterActorStateHook: function(Human: TObject): Boolean;
  LeaveActorStateHook: procedure;

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
// The reason E gives (ECommandRefused), else rrOther.
function RefusalReasonOf(E: Exception): TRefusalReason;
function RefusalReasonName(Reason: TRefusalReason): AnsiString;

// CHANGE: ENHANCEMENT - Trade: the command is a trade (docs/commands.md, Trades): a host applies
// a client's as it arrives, and a client waits for the host's answer instead of predicting it.
procedure RegisterCommand(
    Kind: TCommandKind;
    const Name: AnsiString;
    Executor: TCommandExecutor;
    Trade: Boolean = False
);
function IsTradeCommand(Kind: TCommandKind): Boolean;
// CHANGE: ENHANCEMENT - A kind only a host's relay carries (docs/network.md, Trades: a sale's
// self-contained form): ExecuteRelayedCommand runs it, SubmitCommand refuses it, so no player
// submits it and the command log never records it, and a host refuses it from a peer.
procedure RegisterRelayCommand(Kind: TCommandKind; const Name: AnsiString; Executor: TCommandExecutor);
function IsRelayOnlyCommand(Kind: TCommandKind): Boolean;
// Runs the command and tells the hooks.
procedure SubmitCommand(const Command: TPlayerCommand);
// CHANGE: ENHANCEMENT - SubmitCommand for a trade the UI submits: a refusal
// (ECommandRefused: another human was first) goes to TradeRefusedHook and TradeAbortHook.
procedure SubmitTrade(const Command: TPlayerCommand);
// CHANGE: ENHANCEMENT - Runs another human's command that a host relays to this client
// (docs/network.md, Trades): as the executor runs it, with no hook, and what it submits from
// inside goes nowhere, as for a nested command.
procedure ExecuteRelayedCommand(const Command: TPlayerCommand);
// Whether SubmitCommand or ExecuteRelayedCommand runs a command on this thread.
function CommandRunning: Boolean;
// Runs the command only; the replay uses this.
procedure ExecuteCommand(const Command: TPlayerCommand);
implementation
uses
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
  TradeKinds: array[0..MaximumCommandKind] of Boolean;
  RelayOnlyKinds: array[0..MaximumCommandKind] of Boolean;
threadvar
  // The commands SubmitCommand is executing on this thread.
  SubmitDepth: Integer;

constructor ECommandRefused.CreateReason(AReason: TRefusalReason; const Text: string);
begin
  inherited Create(Text);
  Reason := AReason;
end;

function RefusalReasonOf(E: Exception): TRefusalReason;
begin
  if E is ECommandRefused then
    Result := ECommandRefused(E).Reason
  else
    Result := rrOther;
end;

function RefusalReasonName(Reason: TRefusalReason): AnsiString;
begin
  case Reason of
    rrOutOfStock: Result := 'out-of-stock';
    rrNoMoney: Result := 'no-money';
    rrItemGone: Result := 'item-gone';
    rrOfferGone: Result := 'offer-gone';
    rrTargetGone: Result := 'target-gone';
    rrNoRoom: Result := 'no-room';
    rrInUse: Result := 'in-use';
  else
    Result := 'other';
  end;
end;

function NewCommand(Kind: TCommandKind): TPlayerCommand;
var
  Player: TPlayer;
begin
  Result := Default(TPlayerCommand);
  Result.Kind := Kind;
  // The UI submits commands for the human at this machine.
  Player := LocalPlayer;
  // CHANGE: BUGFIX - A command submitted while another one executes, or by the turn job, is
  // for the human whose code runs: the human of the script code that runs, else the actor of
  // the executing command. It was always the local human, so a nested command of a remote
  // human's command acted for the host's human (docs/commands.md, Threads).
  if (ActingHuman <> nil) or InTurnJob then
  begin
    if (ScriptHuman <> nil) and (ScriptHuman.Player <> nil) then
      Player := ScriptHuman.Player
    else if (ActingHuman <> nil) and (ActingHuman.Player <> nil) then
      Player := ActingHuman.Player;
  end;
  if Player <> nil then
    Result.Actor := Cardinal(Player.Id);
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

procedure RegisterCommand(
    Kind: TCommandKind;
    const Name: AnsiString;
    Executor: TCommandExecutor;
    Trade: Boolean
);
begin
  if Kind > MaximumCommandKind then
    raise Exception.Create('Command kind out of range: ' + Name);
  if KindNames[Kind] <> '' then
    raise Exception.Create('Command kind registered twice: ' + Name);
  Executors[Kind] := Executor;
  KindNames[Kind] := Name;
  TradeKinds[Kind] := Trade;
end;

function IsTradeCommand(Kind: TCommandKind): Boolean;
begin
  Result := (Kind <= MaximumCommandKind) and TradeKinds[Kind];
end;

procedure RegisterRelayCommand(Kind: TCommandKind; const Name: AnsiString; Executor: TCommandExecutor);
begin
  RegisterCommand(Kind, Name, Executor);
  RelayOnlyKinds[Kind] := True;
end;

function IsRelayOnlyCommand(Kind: TCommandKind): Boolean;
begin
  Result := (Kind <= MaximumCommandKind) and RelayOnlyKinds[Kind];
end;

function CommandRunning: Boolean;
begin
  Result := SubmitDepth > 0;
end;

procedure ExecuteCommand(const Command: TPlayerCommand);
var
  Previous: THuman;
  Swapped: Boolean;
begin
  if (Command.Kind > MaximumCommandKind) or not Assigned(Executors[Command.Kind]) then
    raise Exception.Create('No executor for ' + CommandKindName(Command.Kind));
  if Actor(Command) = nil then
    raise Exception.Create(CommandKindName(Command.Kind) + ' names no human');
  // CHANGE: ENHANCEMENT - A human whose game has ended takes no more commands (THuman.Finished,
  // ROADMAP.md, Phase 6). What the turn job submits is part of the job, not the human's act.
  if ActorHuman(Command).Finished and not InTurnJob then
    Exit;
  Previous := ActingHuman;
  ActingHuman := ActorHuman(Command);
  Swapped :=
      (Previous = nil)
          and Assigned(EnterActorStateHook)
          and Assigned(LeaveActorStateHook)
          and EnterActorStateHook(ActingHuman);
  try
    Executors[Command.Kind](Command);
  finally
    if Swapped then
      LeaveActorStateHook;
    ActingHuman := Previous;
  end;
end;

procedure SubmitCommand(const Command: TPlayerCommand);
var
  Outermost, Sent: Boolean;
begin
  // CHANGE: ENHANCEMENT - A relay's form runs only from the relay (ExecuteRelayedCommand).
  if IsRelayOnlyCommand(Command.Kind) then
    raise Exception.Create(CommandKindName(Command.Kind) + ' runs only from a host''s relay');
  // On the turn thread a command is part of the job that runs it, not something a human did.
  if InTurnJob then
  begin
    ExecuteCommand(Command);
    Exit;
  end;
  // CHANGE: ENHANCEMENT - A client's trade runs only once the host has applied it; a refusal
  // raises before anything runs here (docs/network.md, Trades).
  Sent := False;
  if (SubmitDepth = 0) and Assigned(TradeSubmitHook) and IsTradeCommand(Command.Kind) then
  begin
    TradeSubmitHook(Command);
    Sent := True;
  end;
  if Assigned(BeforeCommandHook) then
    BeforeCommandHook(Command);
  Outermost := SubmitDepth = 0;
  Inc(SubmitDepth);
  try
    try
      ExecuteCommand(Command);
    except
      if Assigned(CommandFailedHook) then
        CommandFailedHook(Command);
      raise;
    end;
  finally
    Dec(SubmitDepth);
  end;
  if Assigned(AfterCommandHook) then
    AfterCommandHook(Command);
  // CHANGE: BUGFIX - Only a command submitted while none executes goes to the network. A
  // command submitted from inside another one is submitted again when the receiver executes
  // the outer one, as the command log records only the outermost; a client sent both, and the
  // host ran the inner one twice (docs/network.md, Commands).
  if Outermost and not Sent and Assigned(NetworkCommandHook) then
    NetworkCommandHook(Command);
end;

procedure SubmitTrade(const Command: TPlayerCommand);
var
  Reason: TRefusalReason;
begin
  try
    SubmitCommand(Command);
  except
    on E: ECommandRefused do
    begin
      if not Assigned(TradeAbortHook) then
        raise;
      Reason := E.Reason;
      if Assigned(TradeRefusedHook) then
        TradeRefusedHook(Reason);
      TradeAbortHook;
    end;
  end;
end;

procedure ExecuteRelayedCommand(const Command: TPlayerCommand);
begin
  Inc(SubmitDepth);
  try
    ExecuteCommand(Command);
  finally
    Dec(SubmitDepth);
  end;
end;

end.
