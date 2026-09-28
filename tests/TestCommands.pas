unit TestCommands;
{$MODE delphi}
{$EXCESSPRECISION OFF}
interface
procedure RunCommandTests;
implementation
uses
  SysUtils,
  Types,
  EC_Buf,
  aCommands,
  aPlayerActions,
  CommandLog,
  aSession,
  TestSupport;

const
  ckTestMove = 1023;

// The session flags and their defaults. Executing the command needs a human, so the
// headless runner tests it (--sim-session-probe).
procedure RunSessionFlagTests;
begin
  ResetSessionFlags;
  Check(SessionFlagsAreDefault, 'session flags start at their defaults');
  Check(Session.FriendlyFireEnabled, 'friendly fire is on by default');
  Check(not Session.TextQuestsDisabled, 'text quests are on by default');
  SetSessionFlag(SessionFlagFriendlyFire, False);
  Check(not Session.FriendlyFireEnabled, 'the flag turns friendly fire off');
  Check(not SessionFlagsAreDefault, 'a changed flag is not the default');
  SetSessionFlag(SessionFlagTextQuestsDisabled, True);
  Check(Session.TextQuestsDisabled, 'the flag disables text quests');
  SetSessionFlag(99, True);
  ResetSessionFlags;
  Check(SessionFlagsAreDefault, 'reset restores the defaults');
  CheckText('SetSessionFlag', WideString(CommandKindName(ckSetSessionFlag)), 'flag command name');
end;

var
  HookCalls: string;

procedure TestBeforeHook(const Command: TPlayerCommand);
begin
  HookCalls := HookCalls + 'B';
end;

procedure TestAfterHook(const Command: TPlayerCommand);
begin
  HookCalls := HookCalls + 'A';
end;

procedure TestFailedHook(const Command: TPlayerCommand);
begin
  HookCalls := HookCalls + 'F';
end;

// Submits a command that raises (ckTestMove has no executor); true when it raised.
function SubmitFailing: Boolean;
begin
  Result := False;
  try
    SubmitCommand(NewCommand(ckTestMove));
  except
    on Exception do
      Result := True;
  end;
end;

// A command that raises tells CommandFailedHook, not AfterCommandHook, and the exception goes
// on to the caller (the host logs and drops it). The command log's depth then returns to 0,
// so later commands are recorded; before the fix it stayed raised.
procedure RunFailedCommandTests;
var
  Path: AnsiString;
begin
  HookCalls := '';
  BeforeCommandHook := TestBeforeHook;
  AfterCommandHook := TestAfterHook;
  CommandFailedHook := TestFailedHook;
  try
    Check(SubmitFailing, 'a failing command raises to its caller');
    CheckText('BF', WideString(HookCalls), 'a failing command tells the failure hook, not the after hook');
  finally
    BeforeCommandHook := nil;
    AfterCommandHook := nil;
    CommandFailedHook := nil;
  end;
  Path := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'SpaceRangersUnitTests.srcl';
  StartCommandRecording(Path);
  try
    CheckInt(0, RecordingCommandDepth, 'the recorder starts with no command open');
    Check(SubmitFailing, 'a failing command raises while recording');
    CheckInt(0, RecordingCommandDepth, 'a failing command closes its record');
    Check(SubmitFailing, 'a second failing command raises while recording');
    CheckInt(0, RecordingCommandDepth, 'the depth stays at 0 after failures');
  finally
    StopCommandRecording;
  end;
  Check(not Assigned(CommandFailedHook), 'stopping the recorder clears the failure hook');
end;

procedure RunCommandTests;
var
  Command, Decoded: TPlayerCommand;
  Buf: TBufEC;
  Point: TPointF;
  NegativeZero: Single;
begin
  RegisterCommand(ckTestMove, 'TestMove', nil);
  Command := NewCommand(ckTestMove);
  CheckInt(0, Command.Actor, 'NewCommand without a player has no actor');
  Command.Actor := 1234;
  SetLength(Command.Refs, 2);
  Command.Refs[0].Kind := crShip;
  Command.Refs[0].Id := 77;
  Command.Refs[1].Kind := crNone;
  Command.Refs[1].Id := 0;
  Point.X := 0.1;
  Point.Y := -12345.678;
  AddPoint(Command, Point);
  NegativeZero := -0.0;
  AddFloat(Command, NegativeZero);
  AddInt(Command, -5);
  Command.Text := 'Рейнджер';

  Buf := TBufEC.Create;
  try
    EncodeCommand(Command, Buf);
    // Kind, actor, 2 references, 4 integers, the text and its terminator.
    CheckInt(2 + 4 + 1 + 2 * 5 + 2 + 4 * 4 + 18, Buf.DataSize, 'encoded command size');
    CheckInt(ckTestMove, Buf.GetByteAt(0) + Buf.GetByteAt(1) shl 8, 'command kind comes first');
    Buf.SetPosition(0);
    Decoded := DecodeCommand(Buf);
    Check(Buf.IsAtEnd, 'decoding reads the whole command');
  finally
    Buf.Free
  end;
  CheckInt(ckTestMove, Decoded.Kind, 'decoded kind');
  CheckInt(1234, Decoded.Actor, 'decoded actor');
  CheckInt(2, Length(Decoded.Refs), 'decoded reference count');
  CheckInt(Ord(crShip), Ord(Decoded.Refs[0].Kind), 'decoded reference kind');
  CheckInt(77, Decoded.Refs[0].Id, 'decoded reference id');
  CheckInt(Ord(crNone), Ord(Decoded.Refs[1].Kind), 'decoded empty reference');
  Point := PointArg(Decoded, 0);
  // Floats must come back bit for bit, or a replayed order moves the ship elsewhere.
  CheckHex(Cardinal(Command.Ints[0]), Cardinal(Decoded.Ints[0]), 'point X bits');
  CheckFloat(0.1, Point.X, 1e-7, 'point X');
  CheckFloat(-12345.678, Point.Y, 0.001, 'point Y');
  CheckHex($80000000, Cardinal(Decoded.Ints[2]), 'negative zero keeps its sign bit');
  CheckInt(-5, IntArg(Decoded, 3), 'decoded integer');
  CheckText('Рейнджер', Decoded.Text, 'decoded text');
  try
    IntArg(Decoded, 4);
    Fail('reading a missing integer', 'no exception');
  except
    on Exception do
      Check(True, 'reading a missing integer raises');
  end;
  CheckText('TestMove', WideString(CommandKindName(ckTestMove)), 'command kind name');
  CheckText('Command1022', WideString(CommandKindName(1022)), 'unregistered kind name');
  RunSessionFlagTests;
  RunFailedCommandTests;
end;

end.
