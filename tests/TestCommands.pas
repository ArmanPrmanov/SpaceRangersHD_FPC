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
  TestSupport;

procedure RunCommandTests;
var
  Command, Decoded: TPlayerCommand;
  Buf: TBufEC;
  Point: TPointF;
  NegativeZero: Single;
begin
  Command := NewCommand(ckOrderMove);
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
    CheckInt(Ord(ckOrderMove), Buf.GetByteAt(0) + Buf.GetByteAt(1) shl 8, 'command kind comes first');
    Buf.SetPosition(0);
    Decoded := DecodeCommand(Buf);
    Check(Buf.IsAtEnd, 'decoding reads the whole command');
  finally
    Buf.Free
  end;
  CheckInt(Ord(ckOrderMove), Ord(Decoded.Kind), 'decoded kind');
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
  CheckText('OrderMove', WideString(CommandKindName(ckOrderMove)), 'command kind name');
end;

end.
