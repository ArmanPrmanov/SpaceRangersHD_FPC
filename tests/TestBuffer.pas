unit TestBuffer;
{$MODE delphi}
{$EXCESSPRECISION OFF}
interface
procedure RunBufferTests;
implementation
uses
  SysUtils,
  EC_Buf,
  TestSupport;

procedure RunReadWriteTests;
var
  Buf: TBufEC;
begin
  Buf := TBufEC.Create;
  try
    Buf.AddInt32(-123456789);
    Buf.AddDWord($FEDCBA98);
    Buf.AddWord($BEEF);
    Buf.AddByte($7F);
    Buf.AddBoolean(True);
    Buf.AddBoolean(False);
    Buf.AddSingle(-1.5);
    Buf.AddDouble(1e300);
    Buf.AddWideStringZ('Рейнджер');
    Buf.AddWideStringZ('');
    Buf.AddAnsiStringZ('ansi');
    CheckInt(4 + 4 + 2 + 1 + 1 + 1 + 4 + 8 + 18 + 2 + 5, Buf.DataSize, 'TBufEC size');
    Check(Buf.IsAtEnd, 'TBufEC at end after writes');

    Buf.SetPosition(0);
    CheckInt(-123456789, Buf.GetInt32, 'TBufEC Int32');
    CheckHex($FEDCBA98, Buf.GetUInt32, 'TBufEC DWord');
    CheckInt($BEEF, Buf.GetWord, 'TBufEC Word');
    CheckInt($7F, Buf.GetByte, 'TBufEC Byte');
    Check(Buf.GetBoolean, 'TBufEC Boolean true');
    Check(not Buf.GetBoolean, 'TBufEC Boolean false');
    CheckFloat(-1.5, Buf.GetSingle, 0, 'TBufEC Single');
    CheckFloat(1e300, Buf.GetDouble, 0, 'TBufEC Double');
    CheckText('Рейнджер', Buf.ReadWideString, 'TBufEC WideStringZ');
    CheckText('', Buf.ReadWideString, 'TBufEC empty WideStringZ');
    CheckText('ansi', WideString(Buf.ReadAnsiTextLine), 'TBufEC AnsiStringZ');
    Check(Buf.IsAtEnd, 'TBufEC at end after reads');

    // Little-endian layout is part of the save format.
    CheckHex($F8A432EB, Buf.GetUInt32At(0), 'TBufEC Int32 layout');
    CheckInt($98, Buf.GetByteAt(4), 'TBufEC DWord low byte');
    Buf.SetInt32At(0, 7);
    Buf.SetPosition(0);
    CheckInt(7, Buf.GetInt32, 'TBufEC SetInt32At');
    Buf.SetPosition(Buf.DataSize);
    Check(Buf.IsAtEnd, 'TBufEC SetPosition to end');
    try
      Buf.SetPosition(Buf.DataSize + 1);
      Fail('TBufEC SetPosition past end', 'no exception');
    except
      on Exception do
        Check(True, 'TBufEC SetPosition past end raises');
    end;
    Buf.SetPosition(Buf.DataSize - 1);
    try
      Buf.GetUInt32;
      Fail('TBufEC read past end', 'no exception');
    except
      on Exception do
        Check(True, 'TBufEC read past end raises');
    end;
  finally
    Buf.Free;
  end;
end;

procedure RunTextLineTests;
var
  Buf: TBufEC;
begin
  Buf := TBufEC.Create;
  try
    Buf.AddAnsiStringRaw('first'#13#10'second'#10#10'third');
    Buf.SetPosition(0);
    CheckText('first', WideString(Buf.ReadAnsiTextLine), 'ReadAnsiTextLine CRLF');
    CheckText('second', WideString(Buf.ReadAnsiTextLine), 'ReadAnsiTextLine LF');
    CheckText('third', WideString(Buf.ReadAnsiTextLine), 'ReadAnsiTextLine after two LFs');
    Buf.Clear;
    Buf.AddWideStringRaw('один'#13#10'two');
    Buf.SetPosition(0);
    CheckText('один', Buf.ReadWideTextLine, 'ReadWideTextLine');
    CheckText('two', Buf.ReadWideTextLine, 'ReadWideTextLine last');
  finally
    Buf.Free;
  end;
end;

procedure RunChecksumTests;
var
  Buf: TBufEC;
  i: Integer;
const
  DatKeystream: array[0..7] of Byte = ($A6, $F0, $D8, $29, $81, $C7, $D7, $FD);
begin
  Buf := TBufEC.Create;
  try
    CheckHex(0, Buf.ComputeCrc32, 'ComputeCrc32 empty');
    Buf.AddAnsiStringRaw('123456789');
    CheckHex($CBF43926, Buf.ComputeCrc32, 'ComputeCrc32 check value');
    CheckHex($CBF43926, Buf.ComputeCrc32Range(0, 9), 'ComputeCrc32Range whole');

    // Park-Miller keystream from seed 1: low bytes of 16807 - 1, 282475249 - 1, ...
    Buf.Clear;
    for i := 0 to High(DatKeystream) do
      Buf.AddByte(0);
    Buf.ApplyDatXorCipher(1);
    for i := 0 to High(DatKeystream) do
      CheckInt(DatKeystream[i], Buf.GetByteAt(i), Format('ApplyDatXorCipher byte %d', [i]));

    Buf.Clear;
    for i := 0 to 999 do
      Buf.AddByte(Byte(i * 7));
    Buf.ApplyDatXorCipher($12345678);
    Buf.ApplyDatXorCipher($12345678);
    for i := 0 to 999 do
      if Buf.GetByteAt(i) <> Byte(i * 7) then
      begin
        Fail('ApplyDatXorCipher round trip', Format('byte %d differs', [i]));
        Break;
      end;

    // The embedded CRC plus its correction word keep the range CRC equal to the stored value.
    Buf.SetInt32At(100, 0);
    Buf.SetInt32At(104, 0);
    Buf.UpdateEmbeddedCrc32(16, 1000, 100);
    CheckHex(Buf.GetUInt32At(100), Buf.ComputeCrc32Range(16, 1000), 'UpdateEmbeddedCrc32');
  finally
    Buf.Free;
  end;
end;

procedure RunZlibTests;
var
  Buf: TBufEC;
  i: Integer;
  Intact: Boolean;
begin
  Buf := TBufEC.Create;
  try
    for i := 0 to 9999 do
      Buf.AddByte(Byte(i mod 13));
    Check(Buf.CompressZlibPayloadInPlace(False), 'CompressZlibPayloadInPlace');
    Check(Buf.DataSize < 10000, 'CompressZlibPayloadInPlace shrinks');
    // 'ZL01' magic and the uncompressed size precede the zlib stream.
    CheckHex($31304C5A, Buf.GetUInt32At(0), 'Zlib payload magic');
    CheckInt(10000, Buf.GetInt32At(4), 'Zlib payload size');
    Check(Buf.ExpandZlibPayloadInPlace, 'ExpandZlibPayloadInPlace');
    CheckInt(10000, Buf.DataSize, 'ExpandZlibPayloadInPlace size');
    Intact := True;
    for i := 0 to 9999 do
      Intact := Intact and (Buf.GetByteAt(i) = Byte(i mod 13));
    Check(Intact, 'Zlib round trip content');

    Buf.Clear;
    Buf.AddAnsiStringRaw('not compressed');
    Check(not Buf.ExpandZlibPayloadInPlace, 'ExpandZlibPayloadInPlace rejects raw data');
    CheckInt(14, Buf.DataSize, 'ExpandZlibPayloadInPlace leaves raw data');
  finally
    Buf.Free;
  end;
end;

procedure RunBufferTests;
begin
  RunReadWriteTests;
  RunTextLineTests;
  RunChecksumTests;
  RunZlibTests;
end;

end.
